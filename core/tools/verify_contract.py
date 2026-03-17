import json
import os
import sys
from typing import Any, Dict
from typing import Any

def strip_nulls(x: Any) -> Any:
    # dict/list 내부의 None 값을 가진 키를 제거(재귀)
    if isinstance(x, dict):
        out = {}
        for k, v in x.items():
            if v is None:
                continue
            out[k] = strip_nulls(v)
        return out
    if isinstance(x, list):
        return [strip_nulls(v) for v in x]
    return x


import requests
from jsonschema import Draft7Validator

HERE = os.path.dirname(os.path.abspath(__file__))
CORE_DIR = os.path.abspath(os.path.join(HERE, ".."))
SCHEMA_PATH = os.path.join(CORE_DIR, "contracts", "chat_response.schema.json")

API = os.environ.get("AI_ORCH_CORE", "http://127.0.0.1:8000")
URL = f"{API}/api/chat"

def die(msg: str, code: int = 1) -> None:
    print(msg)
    raise SystemExit(code)

def load_schema() -> Dict[str, Any]:
    if not os.path.exists(SCHEMA_PATH):
        die(f"ERROR: schema not found: {SCHEMA_PATH}")
    with open(SCHEMA_PATH, "r", encoding="utf-8") as f:
        return json.load(f)

def main() -> None:
    schema = load_schema()
    validator = Draft7Validator(schema)

    # 최소 요청 샘플 (UI 계약에 맞춤)
    payload = {
        "mode": "document",
        "message": "계약 테스트: heading/bullet_list/paragraph/code 포함해서 응답해줘",
        "messages": [{"role": "user", "content": "계약 테스트: content blocks로 답해줘"}],
        "project_context": ""
    }

    try:
        r = requests.post(URL, json=payload, timeout=30)
    except Exception as e:
        die(f"ERROR: request failed: {e!r}")

    if r.status_code != 200:
        die(f"ERROR: HTTP {r.status_code} {r.reason}\n{r.text}")

    try:
        data = r.json()
    except Exception:
        die("ERROR: response is not JSON")

    errors = sorted(validator.iter_errors(data), key=lambda e: e.path)
    if errors:
        print("ERROR: schema mismatch")
        for e in errors[:12]:
            path = "/" + "/".join([str(p) for p in e.path])
            print(f"- {path}: {e.message}")
        die("FAIL", 1)

    print("OK: contract test passed")
    print("NOTE: schema is in core/contracts/chat_response.schema.json")

if __name__ == "__main__":
    main()


