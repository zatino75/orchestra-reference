import json
import os
import sys
import time
import urllib.request
from pathlib import Path

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
BASE = os.environ.get("ORX_BASE", "http://127.0.0.1:8000").rstrip("/")
PROJ = os.environ.get("ORX_PROJECT_ID", "p_smoke")
THREAD = os.environ.get("ORX_THREAD_ID", "t_smoke")
PROVIDERS = os.environ.get("ORX_PROVIDERS", "openai,claude").split(",")
PROVIDERS = [p.strip() for p in PROVIDERS if p.strip()]
TIMEOUT_SEC = float(os.environ.get("ORX_TIMEOUT", "10"))

def die(msg: str, code: int = 1):
    print(msg)
    sys.exit(code)

def http_json(method: str, url: str, payload=None):
    data = None
    headers = {"Content-Type": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=TIMEOUT_SEC) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw)

def assert_true(cond: bool, msg: str):
    if not cond:
        die("FAIL: " + msg)

def assert_eq(a, b, msg: str):
    if a != b:
        die(f"FAIL: {msg} | got={a!r} expected={b!r}")

def tail_last_jsonl(path: Path):
    if not path.exists():
        return None
    last = None
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            last = line
    if not last:
        return None
    try:
        return json.loads(last)
    except Exception:
        return None

def main():
    # 1) status smoke
    st = http_json("GET", f"{BASE}/api/status?project_id={PROJ}")
    assert_true(bool(st.get("ok")) is True, "status ok must be true")
    assert_eq(st.get("project_id"), PROJ, "status.project_id must match")
    assert_true(isinstance(st.get("app_build"), str) and len(st.get("app_build")) > 0, "status.app_build must exist")
    assert_true(isinstance(st.get("app_file"), str) and len(st.get("app_file")) > 0, "status.app_file must exist")

    # 2) chat judge + providers
    msg = f"TEST10 smoke {int(time.time())}: scorecard must exist. providers judge mode."
    body = {
        "project_id": PROJ,
        "thread_id": THREAD,
        "message": msg,
        "role": "router_test",
        "providers": PROVIDERS,
        "policy": {"mode": "judge"}
    }
    res = http_json("POST", f"{BASE}/api/chat", body)

    assert_true(bool(res.get("ok")) is True, "chat ok must be true")

    router = res.get("router") or {}
    assert_true(isinstance(router, dict), "router must be dict")

    rule = router.get("routerRule") or router.get("rule")
    assert_eq(rule, "judge_v1_1_scorecard", "router rule must be judge_v1_1_scorecard")

    winner = router.get("routerWinner") or router.get("winner")
    assert_true(isinstance(winner, str) and winner.strip(), "winner must exist")
    assert_true(winner in PROVIDERS, "winner must be one of providers")

    sc = router.get("scorecard")
    assert_true(isinstance(sc, list), "scorecard must be list")
    assert_true(len(sc) >= 1, "scorecard_count must be >= 1")
    assert_true(len(sc) == len(PROVIDERS), "scorecard_count must equal providers length")

    # scorecard schema check
    prov_seen = set()
    for item in sc:
        assert_true(isinstance(item, dict), "scorecard item must be dict")
        prov = item.get("provider")
        assert_true(isinstance(prov, str) and prov.strip(), "scorecard.provider must exist")
        assert_true(prov in PROVIDERS, "scorecard.provider must be in providers")
        prov_seen.add(prov)

        peid = item.get("provider_evidence_id")
        prid = item.get("provider_derived_id")
        assert_true((peid is None) or (isinstance(peid, str) and peid.startswith("E_")), "provider_evidence_id must be E_* or None")
        assert_true((prid is None) or (isinstance(prid, str) and prid.startswith("R_")), "provider_derived_id must be R_* or None")

        clen = item.get("content_length")
        score = item.get("score")
        assert_true(isinstance(clen, int), "content_length must be int")
        assert_true(isinstance(score, (int, float)), "score must be number")

    assert_true(len(prov_seen) == len(PROVIDERS), "scorecard must cover all providers")

    # 3) judge_log_router.jsonl tail check
    root = Path.cwd()
    log_path = root / ".orx_store" / "projects" / PROJ / "judge_log_router.jsonl"
    last = tail_last_jsonl(log_path)
    assert_true(isinstance(last, dict), "judge_log_router last json must exist")

    assert_eq(last.get("projectId"), PROJ, "judge_log_router.projectId must match")
    assert_eq(last.get("threadId"), THREAD, "judge_log_router.threadId must match")
    assert_eq(last.get("rule"), "judge_v1_1_scorecard", "judge_log_router.rule must match")

    log_sc = last.get("scorecard")
    assert_true(isinstance(log_sc, list) and len(log_sc) == len(PROVIDERS), "judge_log_router.scorecard must exist and match providers length")

    log_winner = last.get("winner")
    assert_true(isinstance(log_winner, str) and log_winner in PROVIDERS, "judge_log_router.winner must be one of providers")

    # requestEvidenceId should equal response evidence_id
    req_eid = last.get("requestEvidenceId")
    res_eid = res.get("evidence_id")
    assert_true(isinstance(req_eid, str) and req_eid.startswith("E_"), "judge_log_router.requestEvidenceId must exist")
    assert_true(isinstance(res_eid, str) and res_eid.startswith("E_"), "response.evidence_id must exist")
    assert_eq(req_eid, res_eid, "judge_log_router.requestEvidenceId must equal response.evidence_id")

    print("PASS: TEST10 (router scorecard v1.1)")

if __name__ == "__main__":
    main()