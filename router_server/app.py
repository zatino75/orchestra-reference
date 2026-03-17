from __future__ import annotations

import os
import time
import json
import re
from typing import Any, Dict, List, Optional, Tuple

import httpx

# ✅ FastAPI app export (재발 방지 핵심)
from fastapi import FastAPI
from pydantic import BaseModel


MODE = "llm_orchestra"

DEEPSEEK_API_KEY = (os.getenv("DEEPSEEK_API_KEY") or "").strip()
DEEPSEEK_BASE_URL = (os.getenv("DEEPSEEK_BASE_URL") or "https://api.deepseek.com").strip()
DEEPSEEK_MODEL = (os.getenv("DEEPSEEK_MODEL") or "deepseek-chat").strip()

TIMEOUT_S = float(os.getenv("DEEPSEEK_TIMEOUT_S") or "60")
TEMPERATURE = float(os.getenv("DEEPSEEK_TEMPERATURE") or "0.2")
MAX_TOKENS = int(os.getenv("DEEPSEEK_MAX_TOKENS") or "1600")

PLANNER_LONG_TEXT_CHARS = int(os.getenv("PLANNER_LONG_TEXT_CHARS") or "600")
PLANNER_HIGH_TURNS = int(os.getenv("PLANNER_HIGH_TURNS") or "18")
PLANNER_HIGH_CTX_BYTES = int(os.getenv("PLANNER_HIGH_CTX_BYTES") or "9000")

# ✅ Debug contract trigger (default OFF)
ENABLE_CONTRACT_DEBUG = (os.getenv("ENABLE_CONTRACT_DEBUG") or "").strip() in ("1", "true", "TRUE", "yes", "YES")

# injected_context를 system 프롬프트에 넣을 때 너무 길면 자르기
INJECTED_CONTEXT_MAX_CHARS = int(os.getenv("INJECTED_CONTEXT_MAX_CHARS") or "6000")


def _strip_code_fences(s: str) -> str:
    t = (s or "").strip()
    if t.startswith("```"):
        t = t.lstrip("`").strip()
        if "\n" in t:
            first, rest = t.split("\n", 1)
            if first.strip().lower() in ("json", "javascript", "js"):
                t = rest
        if t.endswith("```"):
            t = t[: -3].strip()
    return t.strip()


def _extract_json_object(s: str) -> str:
    t = _strip_code_fences(s)
    i = t.find("{")
    j = t.rfind("}")
    if i >= 0 and j > i:
        return t[i : j + 1].strip()
    return t.strip()


def _basic_json_repair(s: str) -> str:
    t = _extract_json_object(s)
    t = t.replace("\ufeff", "").replace("\x00", "").strip()

    out = []
    i = 0
    while i < len(t):
        ch = t[i]
        if ch == "," and i + 1 < len(t) and t[i + 1] in ("}", "]"):
            i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out).strip()


def _parse_vendor_json(text: str) -> Tuple[Optional[Dict[str, Any]], Optional[str], bool]:
    raw = text or ""
    candidate = _extract_json_object(raw)

    try:
        obj = json.loads(candidate)
        repaired = False
    except Exception:
        repaired_candidate = _basic_json_repair(raw)
        try:
            obj = json.loads(repaired_candidate)
            repaired = True
        except Exception as e2:
            return None, f"JSON 파싱 실패: {type(e2).__name__}: {e2}", False

    if not isinstance(obj, dict):
        return None, f"JSON 최상위가 dict가 아님: {type(obj)}", repaired
    if "content" not in obj:
        return None, "JSON에 'content' 키가 없음", repaired
    if not isinstance(obj.get("content"), list):
        return None, f"'content'가 list가 아님: {type(obj.get('content'))}", repaired

    return obj, None, repaired


async def call_deepseek(messages: List[Dict[str, Any]], system: str) -> str:
    if not DEEPSEEK_API_KEY:
        raise RuntimeError("DEEPSEEK_API_KEY 미설정")

    payload = {
        "model": DEEPSEEK_MODEL,
        "messages": [{"role": "system", "content": system}] + (messages or []),
        "temperature": TEMPERATURE,
        "max_tokens": MAX_TOKENS,
    }

    headers = {
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}",
        "Content-Type": "application/json",
    }

    async with httpx.AsyncClient(timeout=TIMEOUT_S) as client:
        r = await client.post(f"{DEEPSEEK_BASE_URL}/v1/chat/completions", json=payload, headers=headers)

    if r.status_code >= 400:
        raise RuntimeError(r.text)

    j = r.json()
    return j["choices"][0]["message"]["content"]


def _has_block_type(content: List[Dict[str, Any]], want_type: str) -> bool:
    wt = (want_type or "").strip().lower()
    for b in content or []:
        if isinstance(b, dict):
            bt = str(b.get("type") or "").strip().lower()
            if bt == wt:
                return True
    return False


def _collect_block_types(content: List[Dict[str, Any]]) -> List[str]:
    types: List[str] = []
    for b in content or []:
        if not isinstance(b, dict):
            continue
        bt = str(b.get("type") or "").strip().lower()
        if not bt:
            bt = "unknown"
        types.append(bt)
    return types


def _all_blocks_are_table(content: List[Dict[str, Any]]) -> bool:
    if not isinstance(content, list) or len(content) == 0:
        return False
    for b in content:
        if not isinstance(b, dict):
            return False
        bt = str(b.get("type") or "").strip().lower()
        if bt != "table":
            return False
    return True


def _detect_table_only(user_text: str) -> bool:
    t = (user_text or "").strip()
    if not t:
        return False
    low = t.lower()

    ko = ("표로만", "표만", "테이블로만", "테이블만", "표 이외 금지", "표 외 금지")
    en = ("table only", "only table", "only tables", "tables only", "table-only")

    if any(k in t for k in ko):
        return True
    if any(k in low for k in en):
        return True
    if ("only" in low) and ("table" in low):
        return True
    return False


def _detect_require_table(user_text: str) -> bool:
    t = (user_text or "").strip()
    if not t:
        return False
    low = t.lower()

    has_table_mention = ("table" in low) or ("표" in t)
    if not has_table_mention:
        return False

    force_signals_ko = ("반드시", "필수", "없으면 실패", "아니면 실패", "무조건")
    force_signals_en = ("must", "required", "is required", "fail if", "mandatory")
    forced = any(k in t for k in force_signals_ko) or any(k in low for k in force_signals_en)

    soft_require_ko = ("표로", "표로 보여", "표로 정리", "테이블로", "table로")
    soft = any(k in t for k in soft_require_ko)

    return bool(forced or soft)


def _estimate_ctx_bytes_fallback(
    *,
    project_context: Optional[Dict[str, Any]],
    injected_context: Optional[str],
    selected_pins: Optional[List[Dict[str, Any]]],
    selected_pins_ids: Optional[List[str]],
) -> Optional[int]:
    try:
        eff: Dict[str, Any] = {}
        if isinstance(project_context, dict):
            eff["project_context"] = project_context
        if isinstance(injected_context, str) and injected_context.strip():
            eff["injected_context"] = injected_context
        if isinstance(selected_pins, list) and len(selected_pins) > 0:
            eff["selected_pins"] = selected_pins
        if isinstance(selected_pins_ids, list) and len(selected_pins_ids) > 0:
            eff["selected_pins_ids"] = selected_pins_ids
        if eff:
            s = json.dumps(eff, ensure_ascii=False, default=str)
            return len(s.encode("utf-8"))
    except Exception:
        pass

    try:
        if isinstance(injected_context, str) and injected_context:
            return len(injected_context.encode("utf-8"))
    except Exception:
        pass

    return None


def _format_injected_context_for_system(
    *,
    injected_context: Optional[str],
    selected_pins: Optional[List[Dict[str, Any]]],
    selected_pins_ids: Optional[List[str]],
) -> str:
    ic = injected_context if isinstance(injected_context, str) else ""
    ic = ic.strip()

    lines: List[str] = []
    if ic:
        if len(ic) > INJECTED_CONTEXT_MAX_CHARS:
            ic = ic[:INJECTED_CONTEXT_MAX_CHARS] + "\n...[truncated]"
        lines.append("[INJECTED_CONTEXT]")
        lines.append("아래 injected_context는 반드시 참고/반영해야 하는 프로젝트 내부 자산입니다.")
        lines.append("절대 '접근할 수 없다'고 말하지 말고, 내용 기반으로 답하세요.")
        lines.append(ic)
        lines.append("")

    # selected_pins 자체가 넘어오면(추후 확장) 간단 요약도 함께 제공
    if isinstance(selected_pins, list) and selected_pins:
        lines.append("[SELECTED_PINS]")
        for p in selected_pins[:6]:
            if not isinstance(p, dict):
                continue
            pid = str(p.get("id") or "")
            title = str(p.get("title") or "")
            text = str(p.get("text") or p.get("summary") or "")
            if len(text) > 200:
                text = text[:200] + "..."
            lines.append(f"- [{pid}] {title}: {text}")
        lines.append("")

    # ids만 있으면 "ids가 있었음" 정도만 표시(실제 내용은 injected_context로 주어지는 게 정답)
    if isinstance(selected_pins_ids, list) and selected_pins_ids:
        ids = [str(x) for x in selected_pins_ids[:10]]
        lines.append("[SELECTED_PINS_IDS]")
        lines.append(", ".join(ids))
        lines.append("")

    return "\n".join(lines).strip()


def _planner_decide(
    messages: List[Dict[str, Any]],
    project_context: Optional[Dict[str, Any]],
    intent: Optional[str],
    style: Optional[str],
    *,
    injected_context: Optional[str] = None,
    selected_pins: Optional[List[Dict[str, Any]]] = None,
    selected_pins_ids: Optional[List[str]] = None,
) -> Dict[str, Any]:
    last_user = ""
    for m in reversed(messages or []):
        if isinstance(m, dict) and m.get("role") == "user":
            last_user = str(m.get("content") or "")
            break

    turns_count = 0
    want_options = False

    if isinstance(project_context, dict):
        turns = project_context.get("turns")
        if isinstance(turns, list):
            turns_count = len(turns)
        want_options = bool(project_context.get("want_options") is True)

    ctx_bytes = _estimate_ctx_bytes_fallback(
        project_context=project_context if isinstance(project_context, dict) else None,
        injected_context=injected_context,
        selected_pins=selected_pins,
        selected_pins_ids=selected_pins_ids,
    )

    text_len = len(last_user)

    option_keywords = ("옵션", "비교", "추천", "몇가지", "여러", "대안", "장단점", "표로", "템플릿")
    wants_options_implicit = any(k in last_user for k in option_keywords)
    include_options = bool(want_options or wants_options_implicit)

    table_only = _detect_table_only(last_user)
    require_table = bool(table_only or _detect_require_table(last_user))

    complexity_score = 0
    if text_len >= PLANNER_LONG_TEXT_CHARS:
        complexity_score += 2
    elif text_len >= 220:
        complexity_score += 1

    if turns_count >= PLANNER_HIGH_TURNS:
        complexity_score += 2
    elif turns_count >= 8:
        complexity_score += 1

    if isinstance(ctx_bytes, int) and ctx_bytes >= PLANNER_HIGH_CTX_BYTES:
        complexity_score += 1

    if include_options:
        complexity_score += 1
    if require_table:
        complexity_score += 1
    if table_only:
        complexity_score += 1

    if (intent or "chat") in ("research", "doc", "data"):
        complexity_score += 1
    if (style or "hybrid") in ("explore",):
        complexity_score += 1

    if complexity_score >= 4:
        complexity = "high"
    elif complexity_score >= 2:
        complexity = "medium"
    else:
        complexity = "low"

    if table_only:
        base_rules = (
            "당신은 UI 렌더링용 JSON만 출력합니다. JSON 외 텍스트 금지.\n"
            "``` 코드펜스 금지. 설명문 금지.\n"
            "최상위는 dict이며 반드시 'content' 키가 있어야 합니다.\n"
            "content는 배열이며, 모든 원소는 반드시 {\"type\":\"table\",\"text\":\"...\"} 형태여야 합니다.\n"
            "paragraph/heading/list/code 등 다른 type은 절대 금지.\n"
        )
    else:
        base_rules = (
            "당신은 UI 렌더링용 JSON만 출력합니다. JSON 외 텍스트 금지.\n"
            "``` 코드펜스 금지. 설명문 금지.\n"
            "최상위는 dict이며 반드시 'content' 키가 있어야 합니다.\n"
            "content는 배열이며 각 원소는 최소한 {\"type\":\"paragraph\",\"text\":\"...\"} 형태입니다.\n"
        )

    if table_only:
        layout = (
            "요청은 '표로만(table only)' 출력입니다.\n"
            "content는 table 블록만 허용하며, 표 텍스트는 마크다운 표로 작성하세요.\n"
        )
    elif include_options:
        layout = (
            "요청이 여러 선택지를 요구합니다. 아래 구성 권장:\n"
            "1) heading(2)\n"
            "2) paragraph\n"
            "3) table 또는 list\n"
            "4) list\n"
        )
    else:
        layout = (
            "아래 구성 권장:\n"
            "1) paragraph\n"
            "2) 필요 시 list\n"
        )

    contract_rule = ""
    if table_only:
        contract_rule = (
            "\n[CONTRACT]\n"
            "- 이 요청은 table_only 계약입니다.\n"
            "- content 배열에는 type=table 블록만 허용됩니다.\n"
            "- type=paragraph/heading/list/code 등 다른 블록이 1개라도 있으면 계약 위반입니다.\n"
        )
    elif require_table:
        contract_rule = (
            "\n[CONTRACT]\n"
            "- 이 요청은 반드시 content 배열에 {\"type\":\"table\",\"text\":\"...\"} 블록을 최소 1개 포함해야 합니다.\n"
            "- 마크다운 표 텍스트를 paragraph로 쪼개지 말고, 반드시 type=table 블록으로 넣으세요.\n"
        )

    if complexity == "high":
        depth = "난이도가 높습니다. 구조적으로 답하세요.\n"
    elif complexity == "medium":
        depth = "중간 난이도입니다. 핵심 + 실행 단계를 같이 제시하세요.\n"
    else:
        depth = "낮은 난이도입니다. 짧고 정확하게 답하세요.\n"

    if table_only:
        example = (
            "{\n"
            '  "content": [\n'
            '    {"type":"table","text":"|col1|col2|\\n|---|---|\\n|...|...|"}\n'
            "  ]\n"
            "}\n"
        )
    else:
        example = (
            "{\n"
            '  "content": [\n'
            '    {"type":"paragraph","text":"..."}\n'
            "  ]\n"
            "}\n"
        )

    injected_block = _format_injected_context_for_system(
        injected_context=injected_context,
        selected_pins=selected_pins,
        selected_pins_ids=selected_pins_ids,
    )
    if injected_block:
        injected_block = "\n" + injected_block + "\n"

    system = (
        base_rules
        + layout
        + contract_rule
        + depth
        + injected_block
        + "반드시 아래 형식 그대로 반환(예시):\n"
        + example
    )

    ctx_sources = {
        "has_project_context": bool(isinstance(project_context, dict) and len(project_context or {}) > 0),
        "has_injected_context": bool(isinstance(injected_context, str) and injected_context.strip()),
        "has_selected_pins": bool(isinstance(selected_pins, list) and len(selected_pins) > 0),
        "has_selected_pins_ids": bool(isinstance(selected_pins_ids, list) and len(selected_pins_ids) > 0),
    }

    return {
        "include_options": include_options,
        "require_table": require_table,
        "table_only": table_only,
        "complexity": complexity,
        "complexity_score": complexity_score,
        "turns_count": turns_count,
        "ctx_bytes": ctx_bytes,
        "ctx_sources": ctx_sources,
        "text_len": text_len,
        "system": system,
        "last_user": last_user,
    }


def _list_text_to_items(text: str) -> List[str]:
    items: List[str] = []
    for raw in (text or "").splitlines():
        s = raw.strip()
        if not s:
            continue
        s = re.sub(r"^\s*(?:[-*•]\s+|\d+\.\s+|\d+\)\s+)", "", s).strip()
        if not s:
            continue
        items.append(s)
    out: List[str] = []
    for it in items:
        if not out or out[-1] != it:
            out.append(it)
    return out


def _normalize_content_blocks(content: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for b in content or []:
        if not isinstance(b, dict):
            continue

        bt = str(b.get("type") or "").strip().lower()

        if bt == "list":
            if isinstance(b.get("items"), list):
                out.append(b)
                continue

            txt = b.get("text")
            if isinstance(txt, str) and txt.strip():
                items = _list_text_to_items(txt)
                bb = dict(b)
                bb.pop("text", None)
                bb["items"] = items
                out.append(bb)
                continue

            bb = dict(b)
            bb.pop("text", None)
            bb["items"] = []
            out.append(bb)
            continue

        out.append(b)

    if not out:
        out = [{"type": "paragraph", "text": ""}]
    return out


async def _semantic_retry_if_needed(
    *,
    messages: List[Dict[str, Any]],
    plan: Dict[str, Any],
    content: List[Dict[str, Any]],
    contract_error: Optional[str],
) -> Tuple[List[Dict[str, Any]], Optional[str], bool]:
    table_only = bool(plan.get("table_only") is True)
    require_table = bool(plan.get("require_table") is True)

    if (not table_only) and (not require_table):
        return content, contract_error, False

    allowed_errors = ("missing_required_block(table)", "table_only_violation")
    if not (isinstance(contract_error, str) and contract_error in allowed_errors):
        return content, contract_error, False

    if table_only:
        repair_system = (
            str(plan.get("system") or "")
            + "\n[REPAIR]\n"
              "- 이전 출력은 계약(table_only)을 위반했습니다.\n"
              "- 반드시 content 배열을 type=table 블록만으로 구성해 다시 출력하세요.\n"
              "- paragraph/heading/list/code 등 다른 type은 1개라도 포함하면 실패입니다.\n"
              "- JSON 외 텍스트 금지.\n"
        )
    else:
        repair_system = (
            str(plan.get("system") or "")
            + "\n[REPAIR]\n"
              "- 이전 출력은 계약을 위반했습니다.\n"
              "- 반드시 content 배열에 {\"type\":\"table\",\"text\":\"...\"} 블록을 최소 1개 포함해 다시 출력하세요.\n"
              "- JSON 외 텍스트 금지.\n"
        )

    text2 = await call_deepseek(messages or [], repair_system)
    parsed2, perr2, _json_repaired2 = _parse_vendor_json(text2)

    if parsed2 is None or perr2 is not None:
        return content, contract_error, True

    c2 = parsed2.get("content")  # type: ignore
    if not isinstance(c2, list) or len(c2) == 0:
        c2 = [{"type": "paragraph", "text": ""}]

    try:
        c2 = _normalize_content_blocks(c2)
    except Exception:
        pass

    if table_only:
        if _all_blocks_are_table(c2):
            return c2, None, True
        return c2, "table_only_violation", True

    if _has_block_type(c2, "table"):
        return c2, None, True
    return c2, "missing_required_block(table)", True


async def run_orchestra(
    messages: List[Dict[str, Any]],
    project_context: Optional[Dict[str, Any]] = None,
    intent: Optional[str] = None,
    style: Optional[str] = None,
    *,
    injected_context: Optional[str] = None,
    selected_pins: Optional[List[Dict[str, Any]]] = None,
    selected_pins_ids: Optional[List[str]] = None,
) -> Dict[str, Any]:
    t0 = time.perf_counter()

    pt0 = time.perf_counter()
    plan = _planner_decide(
        messages or [],
        project_context if isinstance(project_context, dict) else None,
        intent,
        style,
        injected_context=injected_context,
        selected_pins=selected_pins,
        selected_pins_ids=selected_pins_ids,
    )
    planner_latency_ms = int((time.perf_counter() - pt0) * 1000)

    wt0 = time.perf_counter()
    text = await call_deepseek(messages or [], plan["system"])
    writer_latency_ms = int((time.perf_counter() - wt0) * 1000)

    ct0 = time.perf_counter()
    parsed, perr, json_repaired = _parse_vendor_json(text)

    error = False
    error_msg = None
    contract_error: Optional[str] = None
    content: List[Dict[str, Any]]

    if parsed is not None and perr is None:
        content = parsed.get("content")  # type: ignore
        if not isinstance(content, list) or len(content) == 0:
            content = [{"type": "paragraph", "text": ""}]
    else:
        error = True
        error_msg = perr or "unknown_parse_error"
        raw = (text or "").strip()
        if len(raw) > 4000:
            raw = raw[:4000] + " ...[truncated]"
        content = [{"type": "paragraph", "text": raw if raw else f"[오케스트라 실패] {error_msg}"}]

    try:
        content = _normalize_content_blocks(content)
    except Exception:
        pass

    try:
        last_user = str(plan.get("last_user") or "")

        if ENABLE_CONTRACT_DEBUG and ("FORCE_CONTRACT_ERROR" in last_user):
            contract_error = "contract_forced(FORCE_CONTRACT_ERROR)"
        else:
            table_only = bool(plan.get("table_only") is True) or _detect_table_only(last_user)
            require_table = bool(plan.get("require_table") is True) or _detect_require_table(last_user)

            if table_only:
                if not _all_blocks_are_table(content):
                    contract_error = "table_only_violation"
            elif require_table:
                if not _has_block_type(content, "table"):
                    contract_error = "missing_required_block(table)"
    except Exception:
        contract_error = contract_error or None

    semantic_retry_attempted = False
    try:
        if (not ENABLE_CONTRACT_DEBUG) and (contract_error in ("missing_required_block(table)", "table_only_violation")):
            content, contract_error, semantic_retry_attempted = await _semantic_retry_if_needed(
                messages=messages or [],
                plan=plan,
                content=content,
                contract_error=contract_error,
            )
    except Exception:
        semantic_retry_attempted = semantic_retry_attempted or False

    conductor_latency_ms = int((time.perf_counter() - ct0) * 1000)
    total_latency_ms = int((time.perf_counter() - t0) * 1000)

    meta: Dict[str, Any] = {
        "router_mode": MODE,
        "latency_ms": total_latency_ms,
        "core": {
            "intent": intent or "chat",
            "style": style or "hybrid",
            "error": bool(error),
        },
        "orchestra": {
            "mode": MODE,
            "latency_ms": total_latency_ms,
            "planner": {
                "vendor": "heuristic",
                "model": "rules_v1",
                "latency_ms": planner_latency_ms,
                "want_options": bool(plan.get("include_options")),
                "complexity": plan.get("complexity"),
                "complexity_score": plan.get("complexity_score"),
                "signals": {
                    "turns_count": plan.get("turns_count"),
                    "ctx_bytes": plan.get("ctx_bytes"),
                    "ctx_sources": plan.get("ctx_sources"),
                    "text_len": plan.get("text_len"),
                },
                "contracts": {
                    "require_table": bool(plan.get("require_table") is True),
                    "table_only": bool(plan.get("table_only") is True),
                },
                "error": False,
            },
            "sub": [
                {
                    "agent": "writer",
                    "vendor": "deepseek",
                    "model": DEEPSEEK_MODEL,
                    "latency_ms": writer_latency_ms,
                    "error": False,
                }
            ],
            "conductor": {
                "vendor": "deepseek",
                "model": DEEPSEEK_MODEL,
                "latency_ms": conductor_latency_ms,
                "repair_attempted": bool(json_repaired or semantic_retry_attempted),
                "repair": {
                    "json_repaired": bool(json_repaired),
                    "semantic_retry_attempted": bool(semantic_retry_attempted),
                },
                "contract_error": contract_error,
                "error": bool(error),
                "error_msg": error_msg,
            },
            "vendors": {"writer": "deepseek"},
        },
    }

    return {"content": content, "meta": meta}


class RouterChatRequest(BaseModel):
    messages: List[Dict[str, Any]] = []
    project_context: Optional[Dict[str, Any]] = None
    intent: Optional[str] = None
    style: Optional[str] = None

    injected_context: Optional[str] = None
    selected_pins_ids: Optional[List[str]] = None
    selected_pins: Optional[List[Dict[str, Any]]] = None


app = FastAPI(title="router_server", version="1.0.0")


@app.get("/health")
def health() -> Dict[str, Any]:
    return {"ok": True, "mode": MODE}


@app.post("/run_orchestra")
async def run_orchestra_api(req: RouterChatRequest) -> Dict[str, Any]:
    return await run_orchestra(
        messages=req.messages or [],
        project_context=req.project_context,
        intent=req.intent,
        style=req.style,
        injected_context=req.injected_context,
        selected_pins=req.selected_pins,
        selected_pins_ids=req.selected_pins_ids,
    )

# --- ORCHESTRA_ENSURE_ROUTER_APP_FASTAPI ---
# Guarantee that a real FastAPI instance is exported as module-level name `app`.
def _orx_ensure_router_fastapi_app():
    try:
        from fastapi import FastAPI as _FastAPI
    except Exception:
        return

    g = globals()

    # 1) If `app` already exists and is FastAPI, ok.
    v = g.get("app", None)
    try:
        if isinstance(v, _FastAPI):
            return
    except Exception:
        pass

    # 2) Search any FastAPI instance in module globals.
    found = None
    found_name = None
    for k, val in list(g.items()):
        try:
            if isinstance(val, _FastAPI):
                found = val
                found_name = k
                break
        except Exception:
            continue

    if found is not None:
        g["app"] = found
        g["_orx_app_source"] = f"bound_from_global:{found_name}"
        return

    # 3) Nothing found -> hard fail so we stop masking the issue.
    keys = [k for k in g.keys() if not str(k).startswith("_")]
    raise RuntimeError(f"router_server.app has no FastAPI instance to bind as `app`. exported_keys={keys[:60]}")

_orx_ensure_router_fastapi_app()
# --- ORCHESTRA_ENSURE_ROUTER_APP_FASTAPI ---

# --- ORCHESTRA_ROUTER_MW_FORCE_PROVIDER_V1 ---
# Force incoming request JSON {provider} or {vendors.writer} into {vendors.writer/conductor}
# so router selection cannot ignore user requested provider.
try:
    import json
    from starlette.requests import Request
except Exception:
    json = None
    Request = None

def _orx_allow_provider(p: str) -> bool:
    if not isinstance(p, str):
        return False
    p = p.strip()
    if not p:
        return False
    return p in {"openai","perplexity","claude","gemini","deepseek"}

def _orx_force_provider_in_body(data: dict) -> dict:
    try:
        p = data.get("provider", None)
    except Exception:
        p = None

    if not p:
        try:
            v = data.get("vendors", None)
            if isinstance(v, dict):
                p = v.get("writer", None) or v.get("conductor", None)
        except Exception:
            p = None

    if isinstance(p, str):
        p = p.strip()

    if not _orx_allow_provider(p):
        return data

    try:
        v = data.get("vendors", None)
    except Exception:
        v = None
    if not isinstance(v, dict):
        data["vendors"] = {}

    data["vendors"]["writer"] = p
    data["vendors"]["conductor"] = p
    data["vendor_override"] = p
    return data

try:
    # only if FastAPI `app` exists
    if "app" in globals() and json is not None and Request is not None:
        _app = globals().get("app", None)

        @_app.middleware("http")
        async def _orx_force_provider_middleware(request: Request, call_next):
            try:
                # apply only on common router chat paths
                if request.url.path in {"/run_orchestra","/api/chat","/chat","/v1/chat"}:
                    body_bytes = await request.body()
                    if body_bytes:
                        try:
                            data = json.loads(body_bytes.decode("utf-8"))
                        except Exception:
                            data = None

                        if isinstance(data, dict):
                            data2 = _orx_force_provider_in_body(data)
                            if data2 is not data:
                                new_body = json.dumps(data2, ensure_ascii=False).encode("utf-8")

                                async def receive():
                                    return {"type":"http.request","body":new_body,"more_body":False}

                                request = Request(request.scope, receive)
            except Exception:
                pass

            return await call_next(request)
except Exception:
    pass
# --- ORCHESTRA_ROUTER_MW_FORCE_PROVIDER_V1 ---
