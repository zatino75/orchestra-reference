from __future__ import annotations

import os
import time
import json
import uuid
import re
import threading
from pathlib import Path
from typing import Any, Dict, List, Literal, Optional, Tuple

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

import urllib.request
import urllib.error

from .project_store import ProjectStore

# =============================================================================
# core/app.py  (SAFE BOOT v9 + decision override min + FINALIZED v1)
# - guarantees: app defined before routes
# - endpoints:
#     GET  /__diag
#     POST /api/chat
#     GET  /api/_debug/scoreboard?projectId=...&windowN=...
#     POST /api/_debug/reset?projectId=...
#     POST /api/_debug/seed_claim?projectId=...&key=...&value=...&text=...
#     GET  /api/_debug/injection_log?projectId=...&tail=...
#     GET  /api/_debug/judge_log?projectId=...&tail=...
#     GET  /api/_debug/promote_log?projectId=...&tail=...
#     GET  /api/_debug/decisions_tail?projectId=...&tail=...
#     GET  /api/_debug/claims_tail?projectId=...&tail=...
#     GET  /api/_debug/finalized_tail?projectId=...&tail=...
# =============================================================================

DEFAULT_PROVIDER = os.getenv("DEFAULT_PROVIDER", "openai")
DEFAULT_MODEL = os.getenv("OPENAI_MODEL", "gpt-5.2-chat-latest")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "").strip()
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL", "https://api.openai.com").rstrip("/")
OPENAI_TIMEOUT_S = float(os.getenv("OPENAI_TIMEOUT_S", "60"))

DATA_ROOT = os.getenv("DATA_ROOT", os.path.join(os.getcwd(), "data"))
OVERRIDE_ENABLED = os.getenv("OVERRIDE_ENABLED", "1").strip() not in ("0", "false", "False")
OVERRIDE_THRESHOLD = int(os.getenv("OVERRIDE_THRESHOLD", "3"))  # opp count to override
OVERRIDE_WINDOW_N = int(os.getenv("OVERRIDE_WINDOW_N", "50"))    # recent events window

Mode = Literal["auto", "research", "document", "code", "legal", "image"]

app = FastAPI(title="ai ochastra core", version="safe-boot-v9+decision-override-min+finalized-v1")


# --------------------------- Models ---------------------------

class ChatRequest(BaseModel):
    project_id: str = "default"
    thread_id: str = ""
    task_type: str = "text"
    message: str = ""
    project_context: Optional[str] = None

    provider: Optional[str] = None
    model: Optional[str] = None
    mode: Optional[Mode] = "auto"


class ChatResponse(BaseModel):
    ok: bool = True
    provider_used: str = "openai"
    mode_used: Mode = "auto"
    output: Dict[str, Any] = Field(default_factory=dict)
    decisions: List[Any] = Field(default_factory=list)
    artifacts: List[Any] = Field(default_factory=list)


# --------------------------- Helpers (LLM) ---------------------------

def _system_prompt(mode_used: Mode) -> str:
    if mode_used == "research":
        return "당신은 리서치 어시스턴트입니다. 근거 중심으로, 과장 없이 답하세요."
    if mode_used == "document":
        return "당신은 문서 작성 어시스턴트입니다. 구조화/목차/명확한 문장으로 답하세요."
    if mode_used == "code":
        return "당신은 시니어 소프트웨어 엔지니어입니다. 재현/원인/해결을 간결히 제시하세요."
    if mode_used == "legal":
        return "당신은 법률정보를 일반적으로 설명합니다. 확정적 단정 대신 주의사항/리스크를 안내하세요."
    if mode_used == "image":
        return "사용자가 이미지 제작을 원합니다. 지금은 이미지 생성을 하지 않고, 필요한 프롬프트를 만들어주세요."
    return ""


def _auto_route(_: str) -> Mode:
    return "auto"


def _http_post_json(url: str, headers: Dict[str, str], payload: Dict[str, Any], timeout_s: float) -> Dict[str, Any]:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    for k, v in headers.items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", errors="replace")
        except Exception:
            body = ""
        raise RuntimeError(f"HTTP {e.code}: {body[:4000]}")
    except Exception as e:
        raise RuntimeError(str(e))


def _openai_chat(model: str, prompt: str, system: str) -> str:
    prompt = (prompt or "").strip()
    if not prompt:
        return ""

    if not OPENAI_API_KEY:
        return (
            "[SERVER_STUB] OPENAI_API_KEY가 설정되지 않아 실제 호출을 건너뛰었습니다.\n\n"
            f"요청 메시지:\n{prompt}"
        )

    url = f"{OPENAI_BASE_URL}/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {OPENAI_API_KEY}",
        "Content-Type": "application/json",
    }

    messages: List[Dict[str, str]] = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})

    payload = {"model": model, "messages": messages}
    j = _http_post_json(url, headers, payload, OPENAI_TIMEOUT_S)

    try:
        return (j["choices"][0]["message"]["content"] or "").strip()
    except Exception:
        return str(j)[:4000]


# --------------------------- Helpers (Knowledge / Inject / Judge / Override) ---------------------------

_LOCK = threading.Lock()
_STORE = ProjectStore(Path(DATA_ROOT))

_WORD_RE = re.compile(r"[0-9A-Za-z_]+|[가-힣]+")

def _now_epoch() -> int:
    return int(time.time())

def _uid() -> str:
    return uuid.uuid4().hex

def _pair_key_from_key(key: str) -> str:
    return f"key:{key}"

def _tokenize(s: str) -> List[str]:
    s = (s or "").strip()
    if not s:
        return []
    return [m.group(0).lower() for m in _WORD_RE.finditer(s)]

def _relevance_score(tokens: List[str], key: str, kind: str) -> float:
    # keep deterministic, simple
    if not key:
        return 0.0
    hit = 1 if key.lower() in tokens else 0
    if kind == "decision":
        return 0.25 if hit else 0.10
    # claim
    return 0.50 if hit else 0.10

def _mk_claim(project_id: str, key: str, value: str, text: str) -> Dict[str, Any]:
    return {
        "id": _uid(),
        "ts_epoch": _now_epoch(),
        "projectId": project_id,
        "kind": "claim",
        "key": str(key or "").strip(),
        "value": str(value or "").strip(),
        "text": str(text or "").strip(),
    }

def _mk_decision(project_id: str, pair_key: str, key: str, value: str, source_claim_id: str, strategy: str, text: str) -> Dict[str, Any]:
    return {
        "id": _uid(),
        "ts_epoch": _now_epoch(),
        "projectId": project_id,
        "kind": "decision",
        "pairKey": pair_key,
        "key": key,
        "value": value,
        "sourceClaimId": source_claim_id,
        "strategy": strategy,
        "text": text,
    }

def _tail(kind: str, project_id: str, tail_n: int) -> List[Dict[str, Any]]:
    tail_n = max(1, min(int(tail_n or 200), 2000))
    return _STORE.tail_knowledge(project_id, kind, max_lines=tail_n)

def _latest_decision_by_key(project_id: str) -> Dict[str, Dict[str, Any]]:
    # naive: scan last 200 decisions and take latest ts per pairKey
    out: Dict[str, Dict[str, Any]] = {}
    for d in _tail("decisions", project_id, 200):
        pk = str(d.get("pairKey", "")).strip()
        if not pk:
            continue
        if pk not in out or int(d.get("ts_epoch", 0)) >= int(out[pk].get("ts_epoch", 0)):
            out[pk] = d
    return out

def _pick_latest_ts_claim(claims: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    if not claims:
        return None
    return sorted(claims, key=lambda x: int(x.get("ts_epoch", 0)), reverse=True)[0]

def _judge_latest_ts(pair_key: str, key: str, candidates: List[Dict[str, Any]]) -> Dict[str, Any]:
    # candidates are claims with same key, different values possible
    keep = _pick_latest_ts_claim(candidates) or {}
    return {
        "pairKey": pair_key,
        "strategy": "latest_ts",
        "verdict": {
            "keepClaimId": keep.get("id"),
            "key": key,
            "value": keep.get("value"),
        },
        "candidates": [
            {"id": c.get("id"), "value": c.get("value"), "score": c.get("_score", 0.0), "ts_epoch": c.get("ts_epoch", 0)}
            for c in candidates
        ],
    }

def _override_track(st: Dict[str, Any], pair_key: str, opp_value: str) -> int:
    # counts within memory events window; opp_value != current decision value
    ov = st.setdefault("_override_counts", {})  # pairKey -> value -> count
    pv = ov.setdefault(pair_key, {})
    pv[opp_value] = int(pv.get(opp_value, 0)) + 1
    return int(pv[opp_value])

def _override_reset_counts(st: Dict[str, Any], pair_key: str) -> None:
    ov = st.setdefault("_override_counts", {})
    if pair_key in ov:
        ov[pair_key] = {}

def _inj_preview(selected: List[Dict[str, Any]]) -> str:
    lines = []
    for it in selected[:8]:
        kind = it.get("kind")
        iid = it.get("id")
        key = it.get("key")
        value = it.get("value")
        text = it.get("text") or ""
        lines.append(f"- [{kind}:{iid}] {key}={value} :: {text}".strip())
    return "\n".join(lines)[:2000]

def _ensure_score_state() -> Dict[str, Any]:
    return {
        "requests": 0,
        "judgeApplied": 0,
        "conflict": {"total": 0, "resolved": 0, "resolveRate": 0.0},
        "grounding": {"avgInjectedDecisionCount": 0.0, "avgCitableIdsCount": 0.0},
        "window": {
            "windowN": 20,
            "requests": 0,
            "judgeApplied": {"total": 0},
            "conflict": {"total": 0, "resolved": 0, "resolveRate": 0.0},
            "grounding": {"avgInjectedDecisionCount": 0.0, "avgCitableIdsCount": 0.0},
        },
        "baseline": {"windowN": 20, "maxEvents": 5000},
        "_events": [],  # {"kind":"inj","selDec":int,"selClaim":int,"citable":int,"conflict":int,"judge":int}
        "_override_counts": {},  # pairKey -> value -> count
    }

_SCORE: Dict[str, Dict[str, Any]] = {}

def _push_score_event(st: Dict[str, Any], ev: Dict[str, Any], window_n: int) -> None:
    st["_events"].append(ev)
    max_keep = max(10, min(int(window_n or 50), 5000))
    if len(st["_events"]) > max_keep:
        st["_events"] = st["_events"][-max_keep:]

def _recompute_scoreboard(st: Dict[str, Any], window_n: int) -> None:
    window_n = max(1, min(int(window_n or 20), 5000))
    st["window"]["windowN"] = window_n
    st["baseline"]["windowN"] = window_n

    evs = st.get("_events", [])
    w = evs[-window_n:]

    # window requests == number of inj events in window
    w_reqs = sum(1 for e in w if e.get("kind") == "inj")
    st["window"]["requests"] = w_reqs

    # judge/conflict window
    w_judge = sum(int(e.get("judge", 0)) for e in w)
    w_conf = sum(int(e.get("conflict", 0)) for e in w)
    st["window"]["judgeApplied"]["total"] = w_judge
    st["window"]["conflict"]["total"] = w_conf
    st["window"]["conflict"]["resolved"] = w_judge  # minimal: judge resolves conflicts we detected
    st["window"]["conflict"]["resolveRate"] = (float(w_judge) / float(max(1, w_conf))) if w_conf > 0 else 0.0

    # grounding window
    w_sel_dec = [int(e.get("selDec", 0)) for e in w if e.get("kind") == "inj"]
    w_citable = [int(e.get("citable", 0)) for e in w if e.get("kind") == "inj"]
    st["window"]["grounding"]["avgInjectedDecisionCount"] = (sum(w_sel_dec) / float(max(1, len(w_sel_dec)))) if w_sel_dec else 0.0
    st["window"]["grounding"]["avgCitableIdsCount"] = (sum(w_citable) / float(max(1, len(w_citable)))) if w_citable else 0.0

    # global (minimal)
    st["conflict"]["total"] = sum(int(e.get("conflict", 0)) for e in evs)
    st["judgeApplied"] = sum(int(e.get("judge", 0)) for e in evs)
    st["conflict"]["resolved"] = st["judgeApplied"]
    st["conflict"]["resolveRate"] = (float(st["judgeApplied"]) / float(max(1, st["conflict"]["total"]))) if st["conflict"]["total"] > 0 else 0.0


# --------------------------- Routes ---------------------------

@app.get("/__diag")
def __diag():
    return JSONResponse(
        {
            "ok": True,
            "service": "core",
            "app": "core.app:app",
            "ts": _now_epoch(),
            "provider_default": DEFAULT_PROVIDER,
            "model_default": DEFAULT_MODEL,
            "openai_key_present": bool(OPENAI_API_KEY),
            "data_root": str(Path(DATA_ROOT).resolve()),
            "overridePolicy": {
                "enabled": OVERRIDE_ENABLED,
                "threshold": OVERRIDE_THRESHOLD,
                "windowN": OVERRIDE_WINDOW_N,
                "strategy": "opp_count_by_value_over_threshold",
            },
        }
    )

@app.get("/api/_debug/scoreboard")
def api_debug_scoreboard(projectId: str = "default", windowN: int = 20):
    with _LOCK:
        st = _SCORE.get(projectId)
        if st is None:
            st = _ensure_score_state()
            _SCORE[projectId] = st
        _recompute_scoreboard(st, window_n=windowN)
        out = {k: v for k, v in st.items() if k not in ("_events", "_override_counts")}
        return JSONResponse({"ok": True, "projectId": projectId, "windowN": int(windowN), "scoreboard": out})

@app.post("/api/_debug/reset")
def api_debug_reset(projectId: str = "default"):
    with _LOCK:
        _SCORE[projectId] = _ensure_score_state()
    _STORE.append_knowledge(projectId, "promote_log", {"ts_epoch": _now_epoch(), "kind": "reset_marker", "projectId": projectId})
    return JSONResponse({"ok": True, "projectId": projectId})

@app.post("/api/_debug/seed_claim")
def api_debug_seed_claim(projectId: str, key: str, value: str, text: str = ""):
    c = _mk_claim(projectId, key=key, value=value, text=text)
    _STORE.append_knowledge(projectId, "claims", c)
    return JSONResponse({"ok": True, "projectId": projectId, "id": c["id"]})

@app.get("/api/_debug/injection_log")
def api_debug_injection_log(projectId: str = "default", tail: int = 20):
    rows = _tail("inject_log", projectId, tail)
    return JSONResponse({"ok": True, "projectId": projectId, "countTail": len(rows), "rows": rows})

@app.get("/api/_debug/judge_log")
def api_debug_judge_log(projectId: str = "default", tail: int = 20):
    rows = _tail("judge_log", projectId, tail)
    return JSONResponse({"ok": True, "projectId": projectId, "countTail": len(rows), "rows": rows})

@app.get("/api/_debug/promote_log")
def api_debug_promote_log(projectId: str = "default", tail: int = 50):
    rows = _tail("promote_log", projectId, tail)
    return JSONResponse({"ok": True, "projectId": projectId, "countTail": len(rows), "rows": rows})

@app.get("/api/_debug/decisions_tail")
def api_debug_decisions_tail(projectId: str = "default", tail: int = 20):
    rows = _tail("decisions", projectId, tail)
    return JSONResponse({"ok": True, "projectId": projectId, "countTail": len(rows), "rows": rows})

@app.get("/api/_debug/claims_tail")
def api_debug_claims_tail(projectId: str = "default", tail: int = 20):
    rows = _tail("claims", projectId, tail)
    return JSONResponse({"ok": True, "projectId": projectId, "countTail": len(rows), "rows": rows})

@app.get("/api/_debug/finalized_tail")
def api_debug_finalized_tail(projectId: str = "default", tail: int = 50):
    rows = _tail("finalized", projectId, tail)
    return JSONResponse({"ok": True, "projectId": projectId, "countTail": len(rows), "rows": rows})


@app.post("/api/chat", response_model=ChatResponse)
def api_chat(req: ChatRequest):
    # ---- request envelope ----
    req_id = _uid()
    t0 = time.time()

    msg = (req.message or "").strip()
    if not msg:
        raise HTTPException(status_code=400, detail="message is empty")

    project_id = (req.project_id or "default").strip() or "default"
    thread_id = (req.thread_id or "").strip() or "t0"

    provider = (req.provider or DEFAULT_PROVIDER).strip().lower()
    model = (req.model or DEFAULT_MODEL).strip()

    mode_in: Mode = (req.mode or "auto")  # type: ignore
    mode_used: Mode = mode_in if mode_in != "auto" else _auto_route(msg)

    status_code = 200
    err_text: Optional[str] = None

    # metrics for finalized
    selected_dec_ct = 0
    selected_clm_ct = 0
    citable_ids_ct = 0
    conflict_count = 0
    judge_applied = 0
    final_injected_len = 0

    resp_payload: Dict[str, Any] = {}
    try:
        if provider != "openai":
            raise HTTPException(status_code=400, detail=f"provider not supported yet: {provider}")

        # ---- Injection build (project pool scan) ----
        tokens = _tokenize(msg)

        # pull candidates
        decisions_by_pk = _latest_decision_by_key(project_id)
        recent_claims = _tail("claims", project_id, 200)

        # group claims by key
        claims_by_key: Dict[str, List[Dict[str, Any]]] = {}
        for c in recent_claims:
            k = str(c.get("key", "")).strip()
            if not k:
                continue
            claims_by_key.setdefault(k, []).append(c)

        candidates: List[Dict[str, Any]] = []
        # decisions as candidates
        for pk, d in decisions_by_pk.items():
            k = str(d.get("key", "")).strip()
            d2 = dict(d)
            d2["_score"] = _relevance_score(tokens, k, "decision")
            candidates.append({"id": d2["id"], "kind": "decision", "score": float(d2["_score"]), "_obj": d2})

        # claims as candidates
        for k, arr in claims_by_key.items():
            for c in arr[-50:]:
                c2 = dict(c)
                c2["_score"] = _relevance_score(tokens, k, "claim")
                candidates.append({"id": c2["id"], "kind": "claim", "score": float(c2["_score"]), "_obj": c2})

        # sort candidates by score desc, then ts desc
        def _cand_sort(x: Dict[str, Any]) -> Tuple[float, int]:
            obj = x.get("_obj") or {}
            return (float(x.get("score", 0.0)), int(obj.get("ts_epoch", 0)))

        candidates_sorted = sorted(candidates, key=_cand_sort, reverse=True)

        selected_objs: List[Dict[str, Any]] = []
        rejected: List[Dict[str, Any]] = []
        conflicts: List[Dict[str, Any]] = []

        # selection per key
        decisions_by_key: Dict[str, Dict[str, Any]] = {}
        for pk, d in decisions_by_pk.items():
            k = str(d.get("key", "")).strip()
            if k:
                decisions_by_key[k] = d

        # score state
        with _LOCK:
            st = _SCORE.get(project_id)
            if st is None:
                st = _ensure_score_state()
                _SCORE[project_id] = st
            st["requests"] = int(st.get("requests", 0)) + 1

        # choose keys that appear in candidates_sorted
        seen_keys: List[str] = []
        for c in candidates_sorted:
            obj = c.get("_obj") or {}
            k = str(obj.get("key", "")).strip()
            if not k:
                continue
            if k not in seen_keys:
                seen_keys.append(k)
            if len(seen_keys) >= 10:
                break

        # process keys in that order
        for k in seen_keys:
            pk = _pair_key_from_key(k)

            d = decisions_by_key.get(k)
            arr = claims_by_key.get(k, [])

            if d is not None:
                # decision exists - check override signals from opposing claims
                opp = [c for c in arr if str(c.get("value", "")).strip() != str(d.get("value", "")).strip()]
                if OVERRIDE_ENABLED and opp:
                    opp_latest = _pick_latest_ts_claim(opp)
                    if opp_latest:
                        opp_val = str(opp_latest.get("value", "")).strip()
                        with _LOCK:
                            st = _SCORE.get(project_id) or _ensure_score_state()
                            _SCORE[project_id] = st
                            cnt = _override_track(st, pk, opp_val)

                        if cnt >= OVERRIDE_THRESHOLD:
                            # create overriding decision
                            new_d = _mk_decision(
                                project_id=project_id,
                                pair_key=pk,
                                key=k,
                                value=opp_val,
                                source_claim_id=str(opp_latest.get("id", "")),
                                strategy="override_threshold",
                                text=f"{k}={opp_val}",
                            )
                            new_d["reqId"] = req_id
                            _STORE.append_knowledge(project_id, "decisions", new_d)

                            _STORE.append_knowledge(project_id, "promote_log", {
                                "reqId": req_id,
                                "ts_epoch": _now_epoch(),
                                "kind": "override_decision",
                                "projectId": project_id,
                                "pairKey": pk,
                                "from": str(d.get("value", "")).strip(),
                                "to": opp_val,
                                "decisionId": new_d["id"],
                                "sourceClaimId": new_d["sourceClaimId"],
                                "reason": "override_threshold_reached",
                                "threshold": OVERRIDE_THRESHOLD,
                                "count": cnt,
                            })

                            _STORE.append_knowledge(project_id, "judge_log", {
                                "reqId": req_id,
                                "id": _uid(),
                                "ts_epoch": _now_epoch(),
                                "pairKey": pk,
                                "strategy": "override_threshold",
                                "verdict": {"key": k, "value": opp_val, "decisionId": new_d["id"], "from": str(d.get("value", "")).strip()},
                                "candidates": [{"id": c.get("id"), "value": c.get("value"), "ts_epoch": c.get("ts_epoch", 0)} for c in (arr[-10:] if arr else [])],
                            })

                            judge_applied += 1
                            conflict_count += 1
                            conflicts.append({
                                "kind": "override",
                                "key": k,
                                "from": str(d.get("value", "")).strip(),
                                "to": opp_val,
                                "threshold": OVERRIDE_THRESHOLD,
                                "count": cnt,
                            })

                            with _LOCK:
                                st = _SCORE.get(project_id) or _ensure_score_state()
                                _SCORE[project_id] = st
                                _override_reset_counts(st, pk)

                            d = new_d  # use new decision

                selected_objs.append(d)
                for c in arr[-50:]:
                    rejected.append({"id": c.get("id"), "reason": "decision_exists", "key": k})
                continue

            if not arr:
                continue

            vals = sorted(list({str(x.get("value", "")).strip() for x in arr if str(x.get("value", "")).strip() != ""}))
            if len(vals) > 1:
                conflict_count += 1
                conflicts.append({
                    "kind": "key_mismatch",
                    "key": k,
                    "values": vals,
                    "ids": [str(x.get("id", "")) for x in arr[-50:]],
                    "decisionExists": False,
                })
                for x in arr:
                    x["_score"] = float(x.get("_score", 0.0))
                j = _judge_latest_ts(pk, k, candidates=arr[-50:])
                _STORE.append_knowledge(project_id, "judge_log", {"reqId": req_id, "id": _uid(), "ts_epoch": _now_epoch(), **j})
                judge_applied += 1

                keep_id = str(j.get("verdict", {}).get("keepClaimId", ""))
                keep_claim = next((x for x in arr if str(x.get("id", "")) == keep_id), None) or _pick_latest_ts_claim(arr) or arr[-1]

                new_d = _mk_decision(
                    project_id=project_id,
                    pair_key=pk,
                    key=k,
                    value=str(keep_claim.get("value", "")).strip(),
                    source_claim_id=str(keep_claim.get("id", "")),
                    strategy="latest_ts",
                    text=f"{k}={str(keep_claim.get('value','')).strip()}",
                )
                new_d["reqId"] = req_id
                _STORE.append_knowledge(project_id, "decisions", new_d)

                _STORE.append_knowledge(project_id, "promote_log", {
                    "reqId": req_id,
                    "ts_epoch": _now_epoch(),
                    "kind": "promote_decision",
                    "projectId": project_id,
                    "decisionId": new_d["id"],
                    "pairKey": pk,
                    "value": new_d["value"],
                    "reason": "judge_created_decision",
                })
                selected_objs.append(new_d)

                for c in arr[-50:]:
                    if str(c.get("id", "")) != str(keep_claim.get("id", "")):
                        rejected.append({"id": c.get("id"), "reason": "conflict_rejected", "key": k, "kept": str(keep_claim.get("id", ""))})
                continue

            keep = _pick_latest_ts_claim(arr) or arr[-1]
            selected_objs.append(keep)

        # Build injection log row (packet)
        selected_for_log = []
        for o in selected_objs:
            kind = str(o.get("kind", "")).strip() or ("decision" if "pairKey" in o else "claim")
            selected_for_log.append({"id": o.get("id"), "kind": kind, "score": float(o.get("_score", 0.0))})

        cands_for_log = [{"id": c.get("id"), "kind": c.get("kind"), "score": float(c.get("score", 0.0))} for c in candidates_sorted[:50]]

        injected_preview = _inj_preview(selected_objs)
        final_injected_len = len(injected_preview)

        selected_dec_ct = sum(1 for o in selected_objs if (str(o.get("kind", "")).strip() == "decision") or ("pairKey" in o))
        selected_clm_ct = sum(1 for o in selected_objs if (str(o.get("kind", "")).strip() == "claim") and ("pairKey" not in o))
        citable_ids_ct = len(selected_objs)

        inj_row = {
            "reqId": req_id,
            "id": _uid(),
            "ts_epoch": _now_epoch(),
            "projectId": project_id,
            "threadId": thread_id,
            "candidates": cands_for_log,
            "selected": selected_for_log,
            "rejected": rejected[:200],
            "conflictsDetected": conflicts,
            "finalInjectedLength": final_injected_len,
            "injectedPreview": injected_preview,
            "request": {"len": len(msg), "tokens": tokens[:20]},
            "selectedDecisionCount": selected_dec_ct,
            "selectedClaimCount": selected_clm_ct,
            "citableIdsCount": citable_ids_ct,
        }
        _STORE.append_knowledge(project_id, "inject_log", inj_row)

        # update scoreboard state
        with _LOCK:
            st = _SCORE.get(project_id)
            if st is None:
                st = _ensure_score_state()
                _SCORE[project_id] = st

            _push_score_event(st, {
                "kind": "inj",
                "selDec": selected_dec_ct,
                "selClaim": selected_clm_ct,
                "citable": citable_ids_ct,
                "conflict": conflict_count,
                "judge": judge_applied,
            }, window_n=max(OVERRIDE_WINDOW_N, 50))

            st["judgeApplied"] = int(st.get("judgeApplied", 0)) + int(judge_applied)
            _recompute_scoreboard(st, window_n=int(20))  # minimal recompute

        # ---- LLM call ----
        system = _system_prompt(mode_used)
        if req.project_context and req.project_context.strip():
            ctx = req.project_context.strip()
            if len(ctx) > 8000:
                ctx = ctx[:8000]
            if system:
                system = system + "\n\n" + "아래는 프로젝트 컨텍스트입니다. 답변에 반영하세요.\n" + ctx
            else:
                system = "아래는 프로젝트 컨텍스트입니다. 답변에 반영하세요.\n" + ctx

        if injected_preview:
            system = (system + "\n\n" if system else "") + "아래는 프로젝트에서 자동 주입된 지식입니다(우선 반영):\n" + injected_preview

        if msg.upper() == "PING":
            out_text = "PONG 🏓"
        else:
            out_text = _openai_chat(model=model, prompt=msg, system=system)

        resp = ChatResponse(
            ok=True,
            provider_used="openai",
            mode_used=mode_used,
            output={"text": out_text, "format": "plain", "reqId": req_id},
            decisions=[],
            artifacts=[],
        )
        resp_payload = resp.model_dump()
        return resp_payload

    except HTTPException as he:
        status_code = int(getattr(he, "status_code", 400) or 400)
        err_text = str(getattr(he, "detail", ""))[:2000]
        return JSONResponse(status_code=status_code, content={"ok": False, "detail": err_text, "reqId": req_id})

    except Exception as e:
        status_code = 500
        err_text = str(e)[:2000]
        return JSONResponse(status_code=500, content={"ok": False, "detail": f"Server failed: {err_text}", "reqId": req_id})

    finally:
        # ---- FINALIZED (B안): reqId당 1줄을 무조건 기록 ----
        dur_ms = int((time.time() - t0) * 1000)
        ok_flag = bool(status_code == 200 and isinstance(resp_payload, dict) and resp_payload.get("ok") is True)

        finalized = {
            "reqId": req_id,
            "ts_epoch": _now_epoch(),
            "projectId": project_id,
            "threadId": thread_id,
            "ok": ok_flag,
            "statusCode": status_code,
            "provider": provider,
            "model": model,
            "mode": mode_used,
            "durationMs": dur_ms,
            "hasConflicts": bool(conflict_count > 0),
            "hasDecisionsWritten": bool(judge_applied > 0),  # decisions are written when judge/override promotes
            "conflictCount": int(conflict_count),
            "judgeAppliedCount": int(judge_applied),
            "selectedDecisionCount": int(selected_dec_ct),
            "selectedClaimCount": int(selected_clm_ct),
            "citableIdsCount": int(citable_ids_ct),
            "finalInjectedLength": int(final_injected_len),
            "error": (err_text or ""),
        }

        try:
            _STORE.append_knowledge(project_id, "finalized", finalized)
        except Exception:
            # finalized 기록 실패는 최악이지만, 예외로 서버 응답을 깨면 더 나쁨
            pass