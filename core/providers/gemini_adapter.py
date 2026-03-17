from __future__ import annotations
from typing import Any, Dict
from .base import ProviderBase, _stub_ok

class GeminiAdapter(ProviderBase):
    name = "gemini"
    def generate(self, payload: Dict[str, Any], timeout_s: float = 20.0) -> Dict[str, Any]:
        user_text = str((payload or {}).get("user_text") or "")
        return _stub_ok(self.name, user_text)