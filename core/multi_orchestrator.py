from __future__ import annotations

from typing import Any, Dict, List, Optional

def orchestrate_multi(
    *,
    user_message: str,
    provider: str,
    router_mode: str,
    plan: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    Sprint-5 MVP frame:
    - 아직 실제 2벤더 호출을 강제하지 않음(회귀 방지)
    - 대신 meta/contracts/artifact 연동을 위한 '형식'을 고정

    반환 형식(권장):
      {
        "ok": True,
        "mode": "single_or_frame",
        "providers": ["deepseek"],
        "comparison": {"enabled": False, ...},
        "final": {"text": "...", "content_blocks": [...]}
      }
    """
    msg = (user_message or "").strip()

    # 현재는 provider 1개 프레임
    return {
        "ok": True,
        "mode": "frame",
        "router_mode": router_mode,
        "providers": [provider] if provider else [],
        "comparison": {
            "enabled": False,
            "reason": "multi-provider wiring is staged; frame only in this sprint",
        },
        "final": {
            "text": "",
            "content_blocks": [],
        },
        "signals": {
            "plan": plan or {},
            "user_message_preview": msg[:120],
        },
    }