from __future__ import annotations
import time
from typing import Any, Dict, List, Optional

from .contract import normalize_provider_result, pick_winner
from .openai_adapter import OpenAIAdapter
from .claude_adapter import ClaudeAdapter
from .gemini_adapter import GeminiAdapter
from .perplexity_adapter import PerplexityAdapter
from .deepseek_adapter import DeepSeekAdapter

_PROVIDER_MAP = {
    "openai": OpenAIAdapter(),
    "claude": ClaudeAdapter(),
    "gemini": GeminiAdapter(),
    "perplexity": PerplexityAdapter(),
    "deepseek": DeepSeekAdapter(),
}

def list_providers() -> List[str]:
    return sorted(_PROVIDER_MAP.keys())

def get_provider(name: str):
    key = (name or "").strip().lower()
    return _PROVIDER_MAP.get(key)

def call_provider(name: str, payload: Dict[str, Any], timeout_s: float = 20.0) -> Dict[str, Any]:
    t0 = time.time()
    p = get_provider(name)
    if p is None:
        return normalize_provider_result(
            provider=name or "unknown",
            ok=False,
            text="",
            latency_ms=(time.time() - t0) * 1000.0,
            citations_raw=None,
            error={"kind": "unknown_provider", "message": f"provider not allowed: {name}"},
        )
    try:
        r = p.generate(payload, timeout_s=timeout_s) or {}
        ok = bool(r.get("ok", True))
        text = str(r.get("text") or "")
        citations_raw = r.get("citations_raw")
        err = r.get("error")
        return normalize_provider_result(
            provider=p.name,
            ok=ok,
            text=text,
            latency_ms=(time.time() - t0) * 1000.0,
            citations_raw=citations_raw,
            error=err,
        )
    except Exception as e:
        return normalize_provider_result(
            provider=p.name,
            ok=False,
            text="",
            latency_ms=(time.time() - t0) * 1000.0,
            citations_raw=None,
            error={"kind":"exception","message": str(e)},
        )

def call_many(names: List[str], payload: Dict[str, Any], timeout_s: float = 20.0) -> Dict[str, Any]:
    # sequential for stability (parallel is next step)
    uniq = []
    seen = set()
    for n in names or []:
        k = (n or "").strip().lower()
        if k and k not in seen:
            uniq.append(k)
            seen.add(k)

    results = [call_provider(n, payload, timeout_s=timeout_s) for n in uniq]
    winner = pick_winner(results)
    return {"results": results, "winner": winner}