import requests
import hashlib
import os
import sys
import json
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
BASE = "http://127.0.0.1:8000"
PROJECT_ID = "P_TEST9"
THREAD_ID = "T_TEST9"

def fail(msg):
    print("FAIL:", msg)
    sys.exit(1)

def ok(msg):
    print("PASS:", msg)

def local_app_build():
    p = Path("core/app.py")
    if not p.exists():
        fail("core/app.py not found")
    data = p.read_bytes()
    return hashlib.sha1(data).hexdigest()[:12]

def server_status():
    r = requests.get(f"{BASE}/api/status", params={"project_id": PROJECT_ID}, timeout=5)
    r.raise_for_status()
    return r.json()

def chat_probe():
    payload = {
        "project_id": PROJECT_ID,
        "thread_id": THREAD_ID,
        "message": "TEST9 router v2 enforcement",
        "role": "router_test",
        "policy": {"mode": "judge"},
        "providers": ["stubA", "stubB"]
    }
    r = requests.post(f"{BASE}/api/chat", json=payload, timeout=15)
    r.raise_for_status()
    return r.json()

print("INFO: TEST9 start")

# 1) build guard
local_build = local_app_build()
status = server_status()

server_build = status.get("app_build")
server_file = status.get("app_file")

print(" - local_app_build:", local_build)
print(" - server_app_build:", server_build)

if not server_build:
    fail("server missing app_build")

if local_build != server_build:
    fail("BUILD MISMATCH: local != server (reload required)")

ok("build match")

# 2) router v2 enforcement
resp = chat_probe()
router = resp.get("router")
if not router:
    fail("router missing in response")

print(" - router keys:", list(router.keys()))

if "routerRule" not in router:
    fail("routerRule missing (v2 required)")

if "routerWinner" not in router:
    fail("routerWinner missing (v2 required)")

if "ingested_claim_ids" not in router:
    fail("ingested_claim_ids missing")

ok("router v2 keys present")

print("PASS: TEST9 ok")