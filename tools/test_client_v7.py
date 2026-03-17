import json
import os
import sys
import time
import urllib.request

BASE = os.environ.get("ORX_BASE", "http://127.0.0.1:8000").rstrip("/")

def post_json(path, payload):
    url = BASE + path
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=20) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw)

def read_jsonl(path):
    out = []
    if not os.path.exists(path):
        return out
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except Exception:
                pass
    return out

def project_file(project_id, name):
    # ProjectStore 저장 구조: .orx_store/projects/<projectId>/<name>.jsonl
    root = os.path.join(os.getcwd(), ".orx_store", "projects", project_id)
    return os.path.join(root, f"{name}.jsonl")

def main():
    project_id = "P_TEST7"
    thread_id = "T1"
    msg = f"TEST7 router stub check {int(time.time())}"

    payload = {
        "project_id": project_id,
        "thread_id": thread_id,
        "message": msg,
        "role": "router_test",
        "providers": ["stubA", "stubB"],
        "policy": {"mode": "judge"}
    }

    try:
        r = post_json("/api/chat", payload)
    except Exception as e:
        print("FAIL: request error:", type(e).__name__, str(e))
        sys.exit(2)

    if not r.get("ok"):
        print("FAIL: response ok=false")
        print(json.dumps(r, ensure_ascii=False, indent=2))
        sys.exit(2)

    router = r.get("router")
    if not isinstance(router, dict):
        print("FAIL: missing router field (expected dict)")
        print("router=", router)
        print(json.dumps(r, ensure_ascii=False, indent=2))
        sys.exit(2)

    providers = router.get("providers") or []
    if providers != ["stubA", "stubB"]:
        print("FAIL: router.providers mismatch", providers)
        print(json.dumps(router, ensure_ascii=False, indent=2))
        sys.exit(2)

    evidence_id = r.get("evidence_id")
    if not evidence_id:
        print("FAIL: missing evidence_id")
        print(json.dumps(r, ensure_ascii=False, indent=2))
        sys.exit(2)

    dpath = project_file(project_id, "derived")
    derived = read_jsonl(dpath)

    scoped = [x for x in derived if isinstance(x, dict) and x.get("requestEvidenceId") == evidence_id]
    prov = [x for x in scoped if x.get("outputType") == "provider_response"]
    asst = [x for x in scoped if x.get("outputType") == "assistant_response"]

    if len(prov) < 2:
        print("FAIL: provider_response count < 2", len(prov))
        print("INFO: derived_path:", dpath, "| exists:", os.path.exists(dpath), "| total:", len(derived))
        sys.exit(2)

    if len(asst) < 1:
        print("FAIL: assistant_response missing")
        sys.exit(2)

    a = asst[-1]
    bpd = a.get("basedOnProviderDerivedIds") or []
    bpe = a.get("basedOnProviderEvidenceIds") or []
    if not isinstance(bpd, list) or len(bpd) < 2:
        print("FAIL: assistant basedOnProviderDerivedIds < 2", bpd)
        sys.exit(2)
    if not isinstance(bpe, list) or len(bpe) < 2:
        print("FAIL: assistant basedOnProviderEvidenceIds < 2", bpe)
        sys.exit(2)

    jpath = project_file(project_id, "judge_log_router")
    jlog = read_jsonl(jpath)
    jscoped = [x for x in jlog if isinstance(x, dict) and x.get("requestEvidenceId") == evidence_id]
    if len(jscoped) < 1:
        print("FAIL: judge_log_router missing for this request")
        print("INFO: judge_path:", jpath, "| exists:", os.path.exists(jpath), "| total:", len(jlog))
        sys.exit(2)

    print("PASS: TEST7 ok")
    print(" - evidence_id:", evidence_id)
    print(" - derived_path:", dpath)
    print(" - provider_response:", len(prov))
    print(" - assistant_response:", len(asst))
    print(" - judge_log_router:", len(jscoped))

if __name__ == "__main__":
    main()