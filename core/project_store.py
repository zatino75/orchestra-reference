from __future__ import annotations

import os
import json
import time
import re
import threading
from pathlib import Path
from typing import Any, Dict, List, Optional

def _now_epoch() -> int:
    return int(time.time())

def _safe_id(s: Any) -> str:
    v = str(s or "").strip()
    if not v:
        return ""
    v2 = re.sub(r"[^0-9A-Za-z_\-\.]", "", v)
    return v2[:80]

_APPEND_LOCK = threading.Lock()
_FSYNC_LOGS = os.getenv("FSYNC_LOGS", "0").strip() in ("1", "true", "True")

def _append_jsonl(path: Path, obj: Any) -> None:
    """
    Append-only JSONL writer with a process-wide lock to avoid interleaving/drops
    under concurrent requests.

    Optional durability:
      FSYNC_LOGS=1 -> flush + fsync each line (slower, but safer)
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps(obj, ensure_ascii=False)

    with _APPEND_LOCK:
        with path.open("a", encoding="utf-8") as f:
            f.write(line + "\n")
            if _FSYNC_LOGS:
                try:
                    f.flush()
                    os.fsync(f.fileno())
                except Exception:
                    # durability is best-effort
                    pass

def _tail_jsonl(path: Path, max_lines: int = 200) -> List[Dict[str, Any]]:
    try:
        if not path.exists():
            return []
        with path.open("rb") as f:
            lines = f.read().splitlines()
        out: List[Dict[str, Any]] = []
        for b in lines[-max_lines:]:
            try:
                s = b.decode("utf-8", errors="ignore").strip()
                if s:
                    out.append(json.loads(s))
            except Exception:
                continue
        return out
    except Exception:
        return []

def _count_jsonl(path: Path) -> int:
    if not path.exists():
        return 0
    try:
        with path.open("rb") as f:
            return len([x for x in f.read().splitlines() if x.strip()])
    except Exception:
        return 0

class ProjectStore:
    """
    Root:
      {root}/projects/{project_id}/
          evidence.jsonl
          claims.jsonl
          decisions.jsonl
          derived.jsonl
          inject_log.jsonl
          judge_log.jsonl
          promote_log.jsonl
          finalized.jsonl
          threads/{thread_id}/events.jsonl
    """

    def __init__(self, root: Path):
        self.root = Path(root).resolve()
        self.projects_dir = self.root / "projects"
        self.projects_dir.mkdir(parents=True, exist_ok=True)

    # ---------------- dirs ----------------

    def project_dir(self, project_id: str) -> Path:
        pid = _safe_id(project_id)
        if not pid:
            raise ValueError("project_id required")
        p = self.projects_dir / pid
        p.mkdir(parents=True, exist_ok=True)
        return p

    def thread_dir(self, project_id: str, thread_id: str) -> Path:
        pid = _safe_id(project_id)
        tid = _safe_id(thread_id)
        if not pid or not tid:
            raise ValueError("project_id and thread_id required")
        td = self.project_dir(pid) / "threads" / tid
        td.mkdir(parents=True, exist_ok=True)
        return td

    # ---------------- knowledge (append-only) ----------------

    def _kpath(self, project_id: str, kind: str) -> Path:
        return self.project_dir(project_id) / f"{kind}.jsonl"

    def append_knowledge(self, project_id: str, kind: str, obj: Dict[str, Any]) -> None:
        _append_jsonl(self._kpath(project_id, kind), obj)

    def tail_knowledge(self, project_id: str, kind: str, max_lines: int = 200) -> List[Dict[str, Any]]:
        return _tail_jsonl(self._kpath(project_id, kind), max_lines=max_lines)

    def count_knowledge(self, project_id: str, kind: str) -> int:
        return _count_jsonl(self._kpath(project_id, kind))

    # typed convenience
    def append_inject_log(self, project_id: str, obj: Dict[str, Any]) -> None:
        self.append_knowledge(project_id, "inject_log", obj)

    def tail_inject_log(self, project_id: str, max_lines: int = 200) -> List[Dict[str, Any]]:
        return self.tail_knowledge(project_id, "inject_log", max_lines=max_lines)

    def append_judge_log(self, project_id: str, obj: Dict[str, Any]) -> None:
        self.append_knowledge(project_id, "judge_log", obj)

    def tail_judge_log(self, project_id: str, max_lines: int = 200) -> List[Dict[str, Any]]:
        return self.tail_knowledge(project_id, "judge_log", max_lines=max_lines)

    def append_promote_log(self, project_id: str, obj: Dict[str, Any]) -> None:
        self.append_knowledge(project_id, "promote_log", obj)

    def tail_promote_log(self, project_id: str, max_lines: int = 200) -> List[Dict[str, Any]]:
        return self.tail_knowledge(project_id, "promote_log", max_lines=max_lines)

    def append_finalized_log(self, project_id: str, obj: Dict[str, Any]) -> None:
        self.append_knowledge(project_id, "finalized", obj)

    def tail_finalized_log(self, project_id: str, max_lines: int = 200) -> List[Dict[str, Any]]:
        return self.tail_knowledge(project_id, "finalized", max_lines=max_lines)

    # ---------------- thread events ----------------

    def log_event(self, project_id: str, thread_id: str, event: Dict[str, Any]) -> None:
        td = self.thread_dir(project_id, thread_id)
        path = td / "events.jsonl"
        ev = dict(event or {})
        ev["ts_epoch"] = _now_epoch()
        _append_jsonl(path, ev)

    def tail_thread_events(self, project_id: str, thread_id: str, max_lines: int = 200) -> List[Dict[str, Any]]:
        td = self.thread_dir(project_id, thread_id)
        path = td / "events.jsonl"
        return _tail_jsonl(path, max_lines=max_lines)