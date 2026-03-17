import json
import os
import sys
import urllib.request

BASE = os.environ.get("ORX_BASE", "http://127.0.0.1:8000").rstrip("/")
PROJ = os.environ.get("ORX_PROJECT_ID", "p_smoke")
TIMEOUT_SEC = float(os.environ.get("ORX_TIMEOUT", "10"))
WINDOW = int(os.environ.get("ORX_METRICS_WINDOW", "20"))

REQUIRED_KEYS = [
    "evidence_rate_proxy",
    "conflict_signal_proxy",
    "consistency_proxy",
    "evolution_proxy",
    "router_usage_rate",
]

def die(msg: str, code: int = 1):
    print(msg)
    sys.exit(code)

def http_json(method: str, url: str):
    req = urllib.request.Request(url, headers={"Content-Type": "application/json"}, method=method)
    with urllib.request.urlopen(req, timeout=TIMEOUT_SEC) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw)

def assert_true(cond: bool, msg: str):
    if not cond:
        die("FAIL: " + msg)

def assert_between_01(x, msg: str):
    assert_true(isinstance(x, (int, float)), msg + " (type)")
    assert_true(0.0 <= float(x) <= 1.0, msg + " (range 0..1)")

def main():
    url = f"{BASE}/api/metrics?project_id={PROJ}&window={WINDOW}&persist=0"
    res = http_json("GET", url)

    assert_true(res.get("ok") is True, "ok must be true")
    assert_true(res.get("project_id") == PROJ, "project_id must match")
    assert_true(isinstance(res.get("app_build"), str) and res.get("app_build"), "app_build must exist")
    assert_true(isinstance(res.get("app_file"), str) and res.get("app_file"), "app_file must exist")

    metrics = res.get("metrics")
    assert_true(isinstance(metrics, dict), "metrics must be dict")

    for k in REQUIRED_KEYS:
        assert_true(k in metrics, f"metrics.{k} must exist")
        assert_between_01(metrics[k], f"metrics.{k}")

    assert_true(isinstance(res.get("counts"), dict), "counts must be dict")
    assert_true(isinstance(res.get("definitions"), dict), "definitions must be dict")

    print("PASS: TEST11 (/api/metrics v1)")

if __name__ == "__main__":
    main()