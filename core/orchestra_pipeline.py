# === AI ORCHESTRA - Thread Fusion v2 (Fixed Indent Version) ===

from __future__ import annotations
import json
import time
import re
import hashlib
from typing import Any, Dict, List, Optional

_INTENT_RE = re.compile(r"(스레드|thread|참고|반영|저번|지난|이전|전에|예전|그때)", re.IGNORECASE)

def _now_ms():
    return int(time.time() * 1000)

def _extract_user_text(body: Dict[str, Any]) -> str:
    if isinstance(body.get("message"), str):
        return body["message"]
    return ""

def _anchor(s: str) -> str:
    h = hashlib.sha1((s or "").encode("utf-8")).hexdigest()
    return "ANCHOR_" + h[:12]

async def run_pipeline(body: Dict[str, Any], store=None, project_id=None, **kwargs):

    result = {
        "content": "",
        "meta": {
            "orchestra": {
                "debug": {
                    "anchor": None,
                    "anchor_hit": False,
                    "injected_context": "",
                    "selected_assets": [],
                    "resolved_threads": [],
                    "intent_detected": False,
                }
            }
        }
    }

    if not isinstance(body, dict):
        return result

    user_text = _extract_user_text(body)
    intent = bool(user_text and _INTENT_RE.search(user_text))
    result["meta"]["orchestra"]["debug"]["intent_detected"] = intent

    if not intent:
        return result

    injected = "Thread reference detected."

    anchor = _anchor(injected)
    result["meta"]["orchestra"]["debug"]["anchor"] = anchor
    result["meta"]["orchestra"]["debug"]["anchor_hit"] = True
    result["content"] = anchor + "\n\n"
    result["meta"]["orchestra"]["debug"]["injected_context"] = injected

    return result
