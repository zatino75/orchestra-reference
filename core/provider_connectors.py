import os
import json
import time
from typing import Any, Dict, List, Optional

# httpx가 없으면 requests로 폴백
try:
    import httpx  # type: ignore
except Exception:
    httpx = None  # type: ignore

try:
    import requests  # type: ignore
except Exception:
    requests = None  # type: ignore


def _now_ms() -> int:
    return int(time.time() * 1000)


def _snip(s: str, n: int = 800) -> str:
    if s is None:
        return ""
    s = str(s)
    return s[:n]


def _http_post(url: str, headers: Dict[str, str], payload: Dict[str, Any], timeout_s: float = 30.0) -> Dict[str, Any]:
    # returns: { ok, status, text, json, error }
    if httpx is not None:
        try:
            with httpx.Client(timeout=timeout_s) as c:
                r = c.post(url, headers=headers, json=payload)
            txt = r.text
            j = None
            try:
                j = r.json()
            except Exception:
                j = None
            return { "ok": (200 <= r.status_code < 300), "status": r.status_code, "text": txt, "json": j, "error": None }
        except Exception as e:
            return { "ok": False, "status": None, "text": "", "json": None, "error": str(e) }

    if requests is not None:
        try:
            r = requests.post(url, headers=headers, json=payload, timeout=timeout_s)
            txt = r.text
            j = None
            try:
                j = r.json()
            except Exception:
                j = None
            return { "ok": (200 <= r.status_code < 300), "status": r.status_code, "text": txt, "json": j, "error": None }
        except Exception as e:
            return { "ok": False, "status": None, "text": "", "json": None, "error": str(e) }

    return { "ok": False, "status": None, "text": "", "json": None, "error": "no_http_client(httpx/requests) installed" }


def _messages_to_simple_text(messages: Any) -> str:
    # messages: [{role, content}] or other
    if not messages:
        return ""
    out = []
    for m in messages:
        role = str(m.get("role", "user"))
        content = m.get("content", "")
        if isinstance(content, list):
            # tool/parts 형식이면 텍스트만 추출
            parts = []
            for p in content:
                if isinstance(p, dict) and p.get("type") == "text":
                    parts.append(p.get("text", ""))
            content = "\n".join([str(x) for x in parts if x])
        out.append(f"[{role}] {content}")
    return "\n".join(out).strip()


def call_provider(
    vendor: str,
    model: str,
    messages: Any,
    *,
    max_tokens: int = 512,
    temperature: Optional[float] = None,
    request_id: Optional[str] = None,
) -> Dict[str, Any]:
    """
    표준 connectorMeta를 반환합니다.
    - 성공/실패 모두 connectorMeta에 남김
    - 실패 원인은 missing_api_key / http_error / exception / no_http_client 등으로 분류
    """
    t0 = _now_ms()
    vendor_l = (vendor or "").strip().lower()
    model_s = (model or "").strip()

    meta: Dict[str, Any] = {
        "ok": False,
        "vendor": vendor_l or None,
        "model": model_s or None,
        "used_stub": True,
        "http_status": None,
        "http_body_snippet": "",
        "error_detail": None,
        "latency_ms": None,
        "request_id": request_id,
    }

    try:
        if vendor_l in ("claude", "anthropic"):
            api_key = os.getenv("ANTHROPIC_API_KEY", "").strip()
            if not api_key:
                meta["error_detail"] = "missing_api_key:ANTHROPIC_API_KEY"
                return _finalize(meta, t0)

            url = "https://api.anthropic.com/v1/messages"
            headers = {
                "Content-Type": "application/json",
                "x-api-key": api_key,
                "anthropic-version": os.getenv("ANTHROPIC_VERSION", "2023-06-01"),
            }
            # Claude messages 포맷: user content를 content[]로
            # 최소 구현: 모든 메시지를 단일 텍스트로 합쳐 user 1개로 전송
            user_text = _messages_to_simple_text(messages)
            payload: Dict[str, Any] = {
                "model": model_s or os.getenv("ANTHROPIC_MODEL", "claude-3-5-sonnet-latest"),
                "max_tokens": max_tokens,
                "messages": [
                    { "role": "user", "content": [ { "type": "text", "text": user_text } ] }
                ],
            }
            if temperature is not None:
                payload["temperature"] = temperature

            r = _http_post(url, headers, payload)
            meta["http_status"] = r.get("status")
            meta["http_body_snippet"] = _snip(r.get("text", ""))

            if r.get("ok"):
                meta["ok"] = True
                meta["used_stub"] = False
                meta["error_detail"] = None
            else:
                if r.get("error"):
                    meta["error_detail"] = f"exception:{r.get('error')}"
                else:
                    meta["error_detail"] = "http_error"
            return _finalize(meta, t0)

        if vendor_l in ("gemini", "google"):
            api_key = (os.getenv("GEMINI_API_KEY", "") or os.getenv("GOOGLE_API_KEY", "")).strip()
            if not api_key:
                meta["error_detail"] = "missing_api_key:GEMINI_API_KEY(or GOOGLE_API_KEY)"
                return _finalize(meta, t0)

            # Gemini Developer API: models.generateContent
            # https://ai.google.dev/api/generate-content (공식)
            gem_model = model_s or os.getenv("GEMINI_MODEL", "gemini-2.0-flash")
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{gem_model}:generateContent?key={api_key}"
            headers = { "Content-Type": "application/json" }

            user_text = _messages_to_simple_text(messages)
            payload = {
                "contents": [
                    { "role": "user", "parts": [ { "text": user_text } ] }
                ]
            }

            r = _http_post(url, headers, payload)
            meta["http_status"] = r.get("status")
            meta["http_body_snippet"] = _snip(r.get("text", ""))

            if r.get("ok"):
                meta["ok"] = True
                meta["used_stub"] = False
                meta["error_detail"] = None
            else:
                if r.get("error"):
                    meta["error_detail"] = f"exception:{r.get('error')}"
                else:
                    meta["error_detail"] = "http_error"
            return _finalize(meta, t0)

        if vendor_l in ("openai",):
            api_key = os.getenv("OPENAI_API_KEY", "").strip()
            if not api_key:
                meta["error_detail"] = "missing_api_key:OPENAI_API_KEY"
                return _finalize(meta, t0)

            # gpt-5.2-pro는 Responses API 전용(공식 문서)
            url = "https://api.openai.com/v1/responses"
            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}",
            }
            # 최소 구현: input을 텍스트로 합쳐 전송
            user_text = _messages_to_simple_text(messages)
            payload = {
                "model": model_s or os.getenv("OPENAI_MODEL", "gpt-5.2-pro"),
                "input": user_text,
            }

            r = _http_post(url, headers, payload)
            meta["http_status"] = r.get("status")
            meta["http_body_snippet"] = _snip(r.get("text", ""))

            if r.get("ok"):
                meta["ok"] = True
                meta["used_stub"] = False
                meta["error_detail"] = None
            else:
                if r.get("error"):
                    meta["error_detail"] = f"exception:{r.get('error')}"
                else:
                    meta["error_detail"] = "http_error"
            return _finalize(meta, t0)

        if vendor_l in ("perplexity", "pplx"):
            api_key = os.getenv("PERPLEXITY_API_KEY", "").strip()
            if not api_key:
                meta["error_detail"] = "missing_api_key:PERPLEXITY_API_KEY"
                return _finalize(meta, t0)

            url = "https://api.perplexity.ai/chat/completions"
            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}",
            }
            payload = {
                "model": model_s or os.getenv("PERPLEXITY_MODEL", "sonar"),
                "messages": messages or [],
                "max_tokens": max_tokens,
                "stream": False,
            }

            r = _http_post(url, headers, payload)
            meta["http_status"] = r.get("status")
            meta["http_body_snippet"] = _snip(r.get("text", ""))

            if r.get("ok"):
                meta["ok"] = True
                meta["used_stub"] = False
                meta["error_detail"] = None
            else:
                if r.get("error"):
                    meta["error_detail"] = f"exception:{r.get('error')}"
                else:
                    meta["error_detail"] = "http_error"
            return _finalize(meta, t0)

        meta["error_detail"] = "unsupported_vendor"
        return _finalize(meta, t0)

    except Exception as e:
        meta["error_detail"] = f"exception:{e}"
        return _finalize(meta, t0)


def _finalize(meta: Dict[str, Any], t0: int) -> Dict[str, Any]:
    meta["latency_ms"] = max(0, _now_ms() - t0)
    # 표준 키 별칭도 같이 제공(기존 스크립트 호환)
    meta["usedStub"] = meta.get("used_stub")
    meta["httpStatus"] = meta.get("http_status")
    meta["httpBodySnippet"] = meta.get("http_body_snippet")
    meta["errorDetail"] = meta.get("error_detail")
    return meta