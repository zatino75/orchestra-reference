# intent_blocks.py
# 역할: Core 응답을 UI-friendly blocks(content)로 보강/정규화
# 목표:
# - UI가 안정적으로 렌더할 수 있도록, 최소한의 블록 스키마를 보장한다.
# - "표만/테이블로만" 요청이면 content를 반드시 table block 1개로 강제한다.
# 주의:
# - 절대 throw 하지 않는다. 실패해도 원본을 최대한 유지한다.

from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple


TABLE_KEYWORDS = ("표", "테이블", "table", "markdown 표", "마크다운 표")

# "표만" 강제 키워드 (여기 포함되면 content는 table 1개로 강제)
TABLE_ONLY_KEYWORDS = (
    "표만",
    "테이블만",
    "table only",
    "table-only",
    "테이블로만",
    "표로만",
    "표(테이블)로만",
    "표 형태로만",
    "결과만 표로",
    "결과만. 표로",
)


def _safe_str(x: Any) -> str:
    try:
        if x is None:
            return ""
        if isinstance(x, str):
            return x
        return str(x)
    except Exception:
        return ""


def _ensure_list_content(resp: Dict[str, Any]) -> List[Dict[str, Any]]:
    c = resp.get("content")
    if isinstance(c, list):
        out: List[Dict[str, Any]] = []
        for it in c:
            if isinstance(it, dict) and "type" in it:
                out.append(it)
            elif isinstance(it, str):
                out.append({"type": "paragraph", "text": it})
            else:
                out.append({"type": "paragraph", "text": _safe_str(it)})
        resp["content"] = out
        return out

    if isinstance(c, dict) and "type" in c:
        resp["content"] = [c]
        return resp["content"]

    if isinstance(c, str):
        resp["content"] = [{"type": "paragraph", "text": c}]
        return resp["content"]

    resp["content"] = []
    return resp["content"]


def _looks_like_markdown_table(text: str) -> bool:
    s = (text or "").strip()
    if not s:
        return False

    lines = [ln.strip() for ln in s.splitlines() if ln.strip()]
    if len(lines) < 2:
        return False
    if "|" not in lines[0]:
        return False

    sep = lines[1].replace(" ", "")
    if set(sep) <= set("|:-"):
        return True

    pipe_lines = sum(1 for ln in lines[:5] if "|" in ln)
    return pipe_lines >= 2


def _parse_markdown_table_loose(md: str) -> Optional[Tuple[List[str], List[List[str]]]]:
    try:
        s = (md or "").strip()
        lines = [ln.strip() for ln in s.splitlines() if ln.strip()]
        if len(lines) < 2:
            return None
        if "|" not in lines[0] or "|" not in lines[1]:
            return None

        def split_row(row: str) -> List[str]:
            r = row.strip()
            if r.startswith("|"):
                r = r[1:]
            if r.endswith("|"):
                r = r[:-1]
            return [c.strip() for c in r.split("|")]

        cols = [c for c in split_row(lines[0]) if c]
        sep_cells = split_row(lines[1])
        looks_like_sep = any(cell and all(ch in ":-" for ch in cell.replace(" ", "")) and cell.replace(" ", "").count("-") >= 3 for cell in sep_cells)
        if not looks_like_sep:
            return None

        body = lines[2:]
        if not body:
            return None

        rows: List[List[str]] = []
        for b in body:
            if "|" not in b:
                continue
            rows.append(split_row(b))

        if not rows:
            return None

        if not cols:
            cols = ["col_1"]

        return cols, rows
    except Exception:
        return None


def _upgrade_markdown_tables_to_table_blocks(resp: Dict[str, Any]) -> None:
    try:
        items = _ensure_list_content(resp)
        for it in items:
            if not isinstance(it, dict):
                continue
            t = _safe_str(it.get("type")).strip().lower()
            if t != "paragraph":
                continue
            text = it.get("text")
            if isinstance(text, str) and _looks_like_markdown_table(text):
                it["type"] = "table"
                it["text"] = text
    except Exception:
        return


def _should_make_table(user_msg: str) -> bool:
    u = (user_msg or "").lower()
    return any(k.lower() in u for k in TABLE_KEYWORDS)


def _should_table_only(user_msg: str) -> bool:
    u = (user_msg or "").lower()
    return any(k.lower() in u for k in TABLE_ONLY_KEYWORDS)


def _extract_kv_pairs(user_msg: str) -> List[Tuple[str, str]]:
    s = user_msg or ""
    out: List[Tuple[str, str]] = []
    for token in s.replace(",", " ").split():
        if "=" in token:
            a, b = token.split("=", 1)
            a = a.strip()
            b = b.strip()
            if a and b:
                out.append((a, b))
    return out


def _force_table_only(resp: Dict[str, Any], in_msg: str) -> None:
    """
    table_only=True면 content를 무조건 table block 1개로 만든다.
    - 기존 content에 table이 있으면: 첫 table만 남김(나머지 타입 제거)
    - table이 없으면:
      - key=value가 있으면 그걸로 table 생성
      - 없으면 markdown table을 파싱해서 table 생성 시도
      - 그래도 없으면 최소 1행짜리 table 생성
    """
    try:
        items = _ensure_list_content(resp)

        # 1) 기존 table 우선
        first_table = None
        for it in items:
            if isinstance(it, dict) and _safe_str(it.get("type")).strip().lower() == "table":
                first_table = it
                break

        if first_table is not None:
            resp["content"] = [first_table]
            return

        # 2) key=value로 table 생성
        pairs = _extract_kv_pairs(in_msg)
        if pairs:
            resp["content"] = [
                {"type": "table", "columns": ["항목", "값"], "rows": [[k, v] for (k, v) in pairs]}
            ]
            return

        # 3) markdown table이 text로 있으면 파싱해서 table 생성
        md_candidates: List[str] = []
        for it in items:
            if not isinstance(it, dict):
                continue
            txt = it.get("text")
            if isinstance(txt, str) and _looks_like_markdown_table(txt):
                md_candidates.append(txt)

        for md in md_candidates:
            parsed = _parse_markdown_table_loose(md)
            if parsed:
                cols, rows = parsed
                resp["content"] = [{"type": "table", "text": md, "columns": cols, "rows": rows}]
                return

        # 4) 마지막 fallback: 최소 table 1개
        resp["content"] = [
            {"type": "table", "columns": ["항목", "값"], "rows": [["요청", (in_msg or "").strip() or ""]]}
        ]
    except Exception:
        # table_only인데도 실패하면 최소 안전 형태
        resp["content"] = [{"type": "table", "columns": ["항목", "값"], "rows": [["error", "force_table_only_failed"]]}]


def enrich_response(
    resp: Dict[str, Any],
    in_msg: str,
    intent: Optional[str] = None,
    table_only: bool = False,
) -> Dict[str, Any]:
    """
    Core Router 응답에 대해:
    - content[] 형태를 강제
    - markdown table이 paragraph로 오면 table block으로 승격
    - table_only 요청이면 content를 table block 1개로 강제
    - (선택) intent/data/document + table 키워드면 최소 table block 보강
    """
    if not isinstance(resp, dict):
        resp = {"content": [{"type": "paragraph", "text": _safe_str(resp)}], "meta": {"error": False}}

    items = _ensure_list_content(resp)

    # 1) paragraph 속 markdown table 승격
    _upgrade_markdown_tables_to_table_blocks(resp)
    items = _ensure_list_content(resp)

    # 2) table_only 최우선 강제
    if bool(table_only) or _should_table_only(in_msg):
        _force_table_only(resp, in_msg)
        return resp

    # 3) (보너스) intent가 data/document이거나, 문장에 table 키워드가 있으면 table 생성 보강
    try:
        it = (intent or "").strip().lower()
        if (it == "data" or it == "document") and _should_make_table(in_msg):
            has_table = any(isinstance(x, dict) and _safe_str(x.get("type")).strip().lower() == "table" for x in items)
            if not has_table:
                pairs = _extract_kv_pairs(in_msg)
                if pairs:
                    resp["content"] = [
                        {
                            "type": "table",
                            "columns": ["항목", "값"],
                            "rows": [[k, v] for (k, v) in pairs],
                        }
                    ]
    except Exception:
        pass

    return resp