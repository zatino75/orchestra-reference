from __future__ import annotations
import time
from typing import Any, Dict, Optional

class ProviderBase:
    name: str = "base"

    def generate(self, payload: Dict[str, Any], timeout_s: float = 20.0) -> Dict[str, Any]:
        raise NotImplementedError()

def _now_ms() -> float:
    return time.time() * 1000.0

def _stub_ok(name: str, text: str) -> Dict[str, Any]:
    # placeholder for real providers. keep deterministic.
    return {
        "provider": name,
        "ok": True,
        "text": text,
        "citations_raw": None,
        "error": None,
    }