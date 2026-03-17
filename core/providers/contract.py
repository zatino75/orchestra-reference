from __future__ import annotations
from typing import Any, Dict, List, Optional

def normalize_provider_result(
    provider: str,
    ok: bool,
    text: str,
    latency_ms: float,
    citations_raw: Optional[Any] = None,
    error: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    return {
        "provider": provider,
        "ok": bool(ok),
        "text": str(text or ""),
        "latencyMs": float(latency_ms or 0.0),
        "citations_raw": citations_raw,
        "error": error,
    }

def pick_winner(results: List[Dict[str, Any]]) -> Dict[str, Any]:
    # deterministic: first ok, else first
    for r in results:
        if bool(r.get("ok")):
            return r
    return results[0] if results else {"provider": "none", "ok": False, "text": "", "latencyMs": 0.0, "error": {"kind":"no_results"}}