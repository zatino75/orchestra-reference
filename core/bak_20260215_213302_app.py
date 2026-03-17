import os
import re
import json
import time
from typing import Any, Dict, List, Optional

# ORCH_APP_BUILD_FOR_STATUS_V1
import os as _orch_os

def _orch_get_app_build() -> str:
    v = (_orch_os.getenv("APP_BUILD", "") or "").strip()
    if v:
        return v
    try:
        p = _orch_os.path.join(_orch_os.getcwd(), ".app_build")
        if _orch_os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                s = (f.read() or "").strip()
                if s:
                    return s
    except Exception:
        pass
    return "dev"

try:
    APP_BUILD
except Exception:
    APP_BUILD = _orch_get_app_build()
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from datetime import datetime

# Project store + pipeline (thread fusion)
try:
    from core.project_store import ProjectStore
except Exception:
    ProjectStore = None  # type: ignore

try:
    from core.orchestra_pipeline import run_pipeline
except Exception:
    run_pipeline = None  # type: ignore


app = FastAPI()

# ------------------------------------------------------------
# ORX store paths (flat .orx_store for claims/conflicts/debug)
# ------------------------------------------------------------
def _orx__store_dir() -> str:
    return os.path.join(os.getcwd(), ".orx_store")

def _orx__path(kind: str) -> str:
    d = _orx__store_dir()
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, f"{kind}.jsonl")

def _orx__append_jsonl_path(p: str, obj: Dict[str, Any]) -> None:
    # NOTE: "append"는 공용 저장 지점이므로, 절대 여기서 복잡한 흐름을 만들지 말고
    #       필요한 훅만 (안전하게 try/except) 처리합니다.
    try:
        line = json.dumps(obj, ensure_ascii=False)
        with open(p, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass

# ------------------------------------------------------------
# Conflict detection helpers
# ------------------------------------------------------------
_NEG_RE = re.compile(r"(하지\s*않\w*|지\s*않\w*|\b안\s+|\b못\s+)", re.UNICODE)

def _orx__normalize_topic_ko(text: str) -> str:
    if not text:
        return ""
    t = text.strip()
    t = re.sub(r"\s+", " ", t)

    # "A 하지 않는다" 류를 topic에서만 정규화(부정 제거 목적)
    t = re.sub(r"([가-힣A-Za-z0-9_]+)\s*하지\s*않\w*", r"\1 한다", t)
    t = re.sub(r"지\s*않\w*", "", t)

    # 단독 부정 부사(보수적으로 제거)
    t = t.replace("안 ", "").replace("못 ", "")

    # 흔한 종결 제거(보수적)
    t = re.sub(r"(입니다|이다|한다|합니다|됨|된다|되다)\s*$", "", t)
    t = re.sub(r"[\.!\?]\s*$", "", t)

    t = re.sub(r"\s+", " ", t).strip()
    return t

def _orx__polarity_from_text_ko(text: str) -> str:
    if not text:
        return "pos"
    return "neg" if _NEG_RE.search(text) else "pos"

def _orx__topic_from_claim_record(claim: Dict[str, Any]) -> str:
    txt = str(claim.get("text") or claim.get("claim") or claim.get("content") or claim.get("statement") or "")
    return _orx__normalize_topic_ko(txt)

def _orx__polarity_from_claim_record(claim: Dict[str, Any]) -> str:
    txt = str(claim.get("text") or claim.get("claim") or claim.get("content") or claim.get("statement") or "")
    return _orx__polarity_from_text_ko(txt)

def _orx__tail_jsonl(path: str, max_lines: int = 800) -> List[Dict[str, Any]]:
    try:
        if not os.path.exists(path):
            return []
        # 뒤에서 max_lines만 읽기(간단/안전)
        with open(path, "rb") as f:
            lines = f.read().splitlines()
        lines = [ln for ln in lines if ln.strip()][-max_lines:]
        out: List[Dict[str, Any]] = []
        for ln in lines:
            try:
                out.append(json.loads(ln.decode("utf-8")))
            except Exception:
                continue
        return out
    except Exception:
        return []

def _orx__conflict_check_and_record(new_claim: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    # DEBUG enter
    try:
        _orx__append_jsonl_path(_orx__path("conflict_debug"), {
            "ts": datetime.utcnow().isoformat() + "Z",
            "stage": "enter",
            "new_id": new_claim.get("id"),
            "text": new_claim.get("text"),
        })
    except Exception:
        pass

    try:
        claims_p = _orx__path("claims")
        conflicts_p = _orx__path("conflicts")

        topic = _orx__topic_from_claim_record(new_claim)
        pol = _orx__polarity_from_claim_record(new_claim)

        try:
            _orx__append_jsonl_path(_orx__path("conflict_debug"), {
                "ts": datetime.utcnow().isoformat() + "Z",
                "stage": "normalized",
                "topic": topic,
                "polarity": pol,
            })
        except Exception:
            pass

        if not topic:
            return None

        prev = _orx__tail_jsonl(claims_p, max_lines=800)
        for old in reversed(prev):
            old_topic = _orx__topic_from_claim_record(old)
            if not old_topic or old_topic != topic:
                continue

            old_pol = _orx__polarity_from_claim_record(old)
            if old_pol == pol:
                continue

            conflict = {
                "ts": datetime.utcnow().isoformat() + "Z",
                "topic": topic,
                "rule": "same_topic_opposite_polarity",
                "new": {
                    "id": new_claim.get("id"),
                    "polarity": pol,
                    "text": new_claim.get("text"),
                },
                "old": {
                    "id": old.get("id"),
                    "polarity": old_pol,
                    "text": old.get("text"),
                },
            }
            _orx__append_jsonl_path(conflicts_p, conflict)

            try:
                _orx__append_jsonl_path(_orx__path("conflict_debug"), {
                    "ts": datetime.utcnow().isoformat() + "Z",
                    "stage": "conflict_written",
                    "topic": topic,
                })
            except Exception:
                pass

            return conflict

        try:
            _orx__append_jsonl_path(_orx__path("conflict_debug"), {
                "ts": datetime.utcnow().isoformat() + "Z",
                "stage": "no_conflict",
                "topic": topic,
            })
        except Exception:
            pass

        return None
    except Exception:
        try:
            _orx__append_jsonl_path(_orx__path("conflict_debug"), {
                "ts": datetime.utcnow().isoformat() + "Z",
                "stage": "error",
            })
        except Exception:
            pass
        return None

# ------------------------------------------------------------
# ProjectStore (thread fusion asset base)
# ------------------------------------------------------------
STORE = None
if ProjectStore is not None:
    try:
        # root 기준은 프로젝트 루트(현재 작업 디렉터리)
        from pathlib import Path
        STORE = ProjectStore(Path(os.getcwd()))
    except Exception:
        STORE = None

# ------------------------------------------------------------
# Routes
# ------------------------------------------------------------
@app.get("/healthz")
def healthz():
    return {"ok": True}

@app.post("/api/chat")
async def api_chat(req: Request):
    try:
        body = await req.json()
    except Exception:
        body = {}

    enforce = bool(body.get("enforce_injection", False))
    msg = body.get("message") or body.get("text") or ""

    project_id = body.get("project_id")
    thread_id = body.get("thread_id")

    ts = time.time()
    cid = f"C_{int(ts*1000)}"
    claim = {
        "id": cid,
        "ts": ts,
        "type": "claim",
        "text": msg,
        "created_reason": "force_flag" if enforce else "normal",
        "status_reason": "force_flag" if enforce else "normal",
        "project_id": project_id,
        "thread_id": thread_id,
    }

    # 1) claims 저장
    _orx__append_jsonl_path(_orx__path("claims"), claim)

    # 2) conflicts 체크
    conflict = _orx__conflict_check_and_record(claim)

    # 3) thread fusion 자산 축적(있을 때만)
    if STORE is not None and project_id and thread_id:
        try:
            # ProjectStore에 log_event가 있으면 사용
            if hasattr(STORE, "log_event"):
                STORE.log_event(project_id, thread_id, {
                    "type": "chat",
                    "ts": datetime.utcnow().isoformat() + "Z",
                    "text": msg,
                    "claim_id": cid,
                    "enforce_injection": enforce,
                    "conflict": bool(conflict),
                })
        except Exception:
            pass

    # 4) pipeline 실행(스토어/프로젝트가 있어야 resolved_threads가 나옴)
    injected_prefix = ""
    pipeline_meta: Dict[str, Any] = {}
    if run_pipeline is not None:
        try:
            pipe = await run_pipeline(body, store=STORE, project_id=project_id)
            # pipe는 {"content": "...", "meta": {...}} 구조
            injected_prefix = str(pipe.get("content") or "")
            pipeline_meta = pipe.get("meta") or {}
        except Exception:
            injected_prefix = ""
            pipeline_meta = {
                "orchestra": {"debug": {"error": "run_pipeline_failed"}}
            }

    return JSONResponse({
        "ok": True,
        "echo": msg,
        "claim_id": cid,
        "enforce_injection": enforce,
        "conflict": conflict,
        "injected_prefix": injected_prefix,
        "pipeline_meta": pipeline_meta,
    }, status_code=200)

@app.get("/api/status")
def api_status():
    def _count(p: str) -> int:
        try:
            if not os.path.exists(p):
                return 0
            with open(p, "rb") as f:
                return len([x for x in f.read().splitlines() if x.strip()])
        except Exception:
            return 0

    return JSONResponse({
        "ok": True,
        "runtime_file": __file__,
        "claims_lines": _count(_orx__path("claims")),
        "conflicts_lines": _count(_orx__path("conflicts")),
        "conflict_debug_lines": _count(_orx__path("conflict_debug")),
    }, status_code=200)