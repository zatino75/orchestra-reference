import json, time, sys
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError

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
BASE = "http://127.0.0.1:8000"
STATUS_URL = BASE + "/api/status"
CHAT_URL   = BASE + "/api/chat"
ROOT = Path.cwd()

def fail(msg: str, *, code: int = 1):
    print(f"FAIL: {msg}")
    sys.exit(code)

def ok(msg: str):
    print(f"PASS: {msg}")

def http_get_json(url: str):
    req = Request(url, method="GET")
    with urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))

def http_post_json(url: str, payload: dict):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = Request(url, data=data, method="POST", headers={"Content-Type": "application/json; charset=utf-8"})
    try:
        with urlopen(req, timeout=20) as r:
            return json.loads(r.read().decode("utf-8"))
    except HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", errors="replace")
        except Exception:
            pass
        print(f"HTTP_STATUS = {e.code}")
        print("HTTP_BODY =")
        print(body if body else "(empty)")
        raise

def project_paths(project_id: str) -> dict:
    base = ROOT / ".orx_store" / "projects" / project_id
    return {
        "base": base,
        "evidence": base / "evidence.jsonl",
        "claims": base / "claims.jsonl",
        "decisions": base / "decisions.jsonl",
        "inject": base / "inject_log.jsonl",
        "promote": base / "promote_log.jsonl",
        "derived": base / "derived.jsonl",
    }

def read_jsonl_all(p: Path):
    if not p.exists():
        return []
    out = []
    with p.open("r", encoding="utf-8", errors="replace") as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            try:
                out.append(json.loads(ln))
            except Exception:
                pass
    return out

def read_jsonl_tail(p: Path, n: int = 1):
    if not p.exists():
        return []
    lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
    out = []
    for ln in lines[-n:]:
        ln = ln.strip()
        if not ln:
            continue
        try:
            out.append(json.loads(ln))
        except Exception:
            pass
    return out

def contains_line_with(p: Path, needle: str) -> bool:
    if not p.exists():
        return False
    with p.open("r", encoding="utf-8", errors="replace") as f:
        for ln in f:
            if needle in ln:
                return True
    return False

def main():
    st = http_get_json(STATUS_URL)
    if not st.get("ok"):
        fail("preflight ok=false")
    ok("preflight ok")

    # TEST1
    P, T = "P_TEST1", "T_MAIN"
    r1 = http_post_json(CHAT_URL, {"project_id": P, "thread_id": T, "message": "TEST1: evidence 저장 검증"})
    if not r1.get("ok"):
        fail("TEST1 chat ok=false")
    pp = project_paths(P)
    if not pp["evidence"].exists():
        fail("TEST1 evidence.jsonl not found")
    tail = read_jsonl_tail(pp["evidence"], 1)
    if not tail or tail[0].get("sourceType") != "user":
        fail("TEST1 evidence tail invalid")
    ok("TEST1 ok")

    # TEST2
    P, T = "P_TEST2", "T_MAIN"
    msg = "TEST2_FEATURE는 작동한다"
    http_post_json(CHAT_URL, {"project_id": P, "thread_id": T, "message": msg})
    time.sleep(0.12)
    http_post_json(CHAT_URL, {"project_id": P, "thread_id": T, "message": msg})
    time.sleep(0.12)
    http_post_json(CHAT_URL, {"project_id": P, "thread_id": T, "message": msg})
    pp = project_paths(P)
    claims = read_jsonl_all(pp["claims"])
    cands = [c for c in claims if str(c.get("text") or "") == msg]
    if not cands:
        fail("TEST2 matching claim not found")
    cands.sort(key=lambda x: float(x.get("updatedAt") or x.get("createdAt") or 0), reverse=True)
    conf = float(cands[0].get("confidence") or 0.0)
    if conf < 0.60:
        fail(f"TEST2 confidence too low: {conf:.2f}")
    ok(f"TEST2 ok (confidence={conf:.2f})")

    # TEST3  ✅ 유니크 토픽으로 매번 새 Decision 생성 강제
    P, T = "P_TEST3", "T_MAIN"
    token = int(time.time() * 1000)
    pos = f"T3_UNIQ_{token} 는 작동한다"
    neg = f"T3_UNIQ_{token} 는 작동하지 않는다"

    http_post_json(CHAT_URL, {"project_id": P, "thread_id": T, "message": pos})
    time.sleep(0.2)
    r3 = http_post_json(CHAT_URL, {"project_id": P, "thread_id": T, "message": neg})

    if int(r3.get("conflicts") or 0) < 1:
        fail(f"TEST3 conflicts too low: {r3.get('conflicts')}")
    if int(r3.get("decisions") or 0) < 1:
        # 방어적으로 파일도 확인
        pp = project_paths(P)
        decs = read_jsonl_all(pp["decisions"])
        if len(decs) < 1:
            fail(f"TEST3 decisions too low: {r3.get('decisions')}")
    ok("TEST3 ok")

    # TEST4 (seed 후 rejected.reason)
    P, T = "P_TEST4", "T_MAIN"
    for i in range(1, 10):
        http_post_json(CHAT_URL, {"project_id": P, "thread_id": T, "message": f"TEST4_SEED_{i}: 서로 다른 문장 {i}"})
        time.sleep(0.05)

    http_post_json(CHAT_URL, {"project_id": P, "thread_id": T, "message": "TEST4: inject_log rejected.reason 검증"})
    pp = project_paths(P)
    inj_tail = read_jsonl_tail(pp["inject"], 1)
    if not inj_tail:
        fail("TEST4 inject_log tail parse failed")
    rejected = inj_tail[0].get("rejected") or []
    if len(rejected) < 1:
        fail("TEST4 rejected is empty")
    if not any(isinstance(x, dict) and str(x.get("reason") or "").strip() for x in rejected):
        fail("TEST4 rejected.reason missing")
    ok("TEST4 ok")

    # TEST5
    P, T = "P_TEST5", "T_MAIN"
    http_post_json(CHAT_URL, {"project_id": P, "thread_id": T, "message": "T5_DECAY_TARGET는 유지된다"})
    print("INFO: TEST5 waiting 65s for decay trigger...")
    time.sleep(65)
    http_post_json(CHAT_URL, {"project_id": P, "thread_id": T, "message": "T5_DECAY_TRIGGER"})
    pp = project_paths(P)
    pl = read_jsonl_all(pp["promote"])
    if not any(isinstance(x, dict) and x.get("type") == "decay" for x in pl):
        fail("TEST5 promote_log missing decay")
    ok("TEST5 ok")

    # TEST6
    P, T = "P_TEST6", "T_MAIN"
    r6 = http_post_json(CHAT_URL, {"project_id": P, "thread_id": T, "message": "TEST6: assistant_response derived 저장 검증 (python client)"})
    if "assistant_output" not in r6:
        fail("TEST6 missing assistant_output")
    if "assistant_derived_id" not in r6:
        fail("TEST6 missing assistant_derived_id")
    aid = str(r6.get("assistant_derived_id") or "")
    if len(aid.strip()) < 5:
        fail("TEST6 assistant_derived_id invalid")

    pp = project_paths(P)
    if not pp["derived"].exists():
        fail("TEST6 derived.jsonl not found")
    if not contains_line_with(pp["derived"], '"outputType": "assistant_response"'):
        fail('TEST6 derived missing outputType="assistant_response"')
    if not contains_line_with(pp["derived"], f'"id": "{aid}"'):
        fail(f"TEST6 derived missing id line: {aid}")
    ok(f"TEST6 ok (assistant_derived_id={aid})")

    print("ALL PASS (Python test client: TEST1~TEST6)")
    return 0

if __name__ == "__main__":
    sys.exit(main())