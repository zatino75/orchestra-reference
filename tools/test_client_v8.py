import json
import os
import sys
import time
import hashlib
import urllib.request
import urllib.parse

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

def post_json(path, payload):
    url = BASE + path
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=20) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw)

def get_json(path, params=None):
    if params:
        qs = urllib.parse.urlencode(params)
        url = BASE + path + "?" + qs
    else:
        url = BASE + path
    req = urllib.request.Request(url, headers={"Content-Type": "application/json"}, method="GET")
    with urllib.request.urlopen(req, timeout=20) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw)

def jdump(x):
    return json.dumps(x, ensure_ascii=False, indent=2)

def sha1_file(path):
    try:
        with open(path, "rb") as f:
            b = f.read()
        return hashlib.sha1(b).hexdigest()[:12]
    except Exception:
        return None

def main():
    project_id = "P_TEST8"
    thread_id = "T1"

    # ---- build guard: server vs local ----
    local_app = os.path.join(os.getcwd(), "core", "app.py")
    local_build = sha1_file(local_app)

    try:
        st = get_json("/api/status", {"project_id": project_id})
    except Exception as e:
        print("FAIL: /api/status request error:", type(e).__name__, str(e))
        sys.exit(2)

    server_build = st.get("app_build")
    server_file = st.get("app_file")

    print("INFO: build guard")
    print(" - local_app_file:", os.path.abspath(local_app))
    print(" - local_app_build:", local_build)
    print(" - server_app_file:", server_file)
    print(" - server_app_build:", server_build)

    # STEP1: providers 호출로 ingest 발생해야 함
    msg1 = f"TEST8 step1 provider ingest {int(time.time())}"
    payload1 = {
        "project_id": project_id,
        "thread_id": thread_id,
        "message": msg1,
        "role": "router_test",
        "providers": ["stubA", "stubB"],
        "policy": {"mode": "judge"}
    }

    r1 = post_json("/api/chat", payload1)
    if not r1.get("ok"):
        print("FAIL: step1 ok=false")
        print(jdump(r1))
        sys.exit(2)

    router1 = r1.get("router")
    if not isinstance(router1, dict):
        print("FAIL: step1 missing router dict")
        print("router=", router1)
        print(jdump(r1))
        sys.exit(2)

    # 핵심: v2면 키가 반드시 존재해야 함(빈 리스트라도)
    if "ingested_claim_ids" not in router1:
        print("FAIL: server router schema is not v2 (missing 'ingested_claim_ids' key)")
        print("HINT: 서버가 현재 디스크의 core/app.py(v2)를 아직 로드하지 않은 상태입니다.")
        print("router(step1) =", jdump(router1))
        sys.exit(2)

    ing = router1.get("ingested_claim_ids") or []
    if not isinstance(ing, list) or len(ing) < 2:
        print("FAIL: step1 ingested_claim_ids < 2")
        print("router(step1) =", jdump(router1))
        sys.exit(2)

    # STEP2: 다음 요청에서 inject에 섞여 들어오는지 확인
    msg2 = f"TEST8 step2 should inject prov stubA stubB router {int(time.time())}"
    payload2 = {
        "project_id": project_id,
        "thread_id": thread_id,
        "message": msg2
    }

    r2 = post_json("/api/chat", payload2)
    if not r2.get("ok"):
        print("FAIL: step2 ok=false")
        print(jdump(r2))
        sys.exit(2)

    selected = r2.get("selected_claim_ids") or []
    if not isinstance(selected, list):
        print("FAIL: step2 selected_claim_ids missing")
        print(jdump(r2))
        sys.exit(2)

    hit = [cid for cid in ing if cid in selected]
    if len(hit) < 1:
        print("FAIL: injected did not include ingested provider claims")
        print("ingested_claim_ids =", ing)
        print("selected_claim_ids =", selected)
        sys.exit(2)

    print("PASS: TEST8 ok")
    print(" - evidence_id_step1:", r1.get("evidence_id"))
    print(" - ingested_claim_ids:", ing)
    print(" - evidence_id_step2:", r2.get("evidence_id"))
    print(" - selected_claim_ids:", selected)
    print(" - hit:", hit)

if __name__ == "__main__":
    main()