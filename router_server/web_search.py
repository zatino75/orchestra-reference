from __future__ import annotations

from typing import List, Dict
import re
import html
import urllib.parse
import httpx


_DDG_HTML = "https://duckduckgo.com/html/"


def _clean(text: str) -> str:
    text = html.unescape(text or "")
    text = re.sub(r"\s+", " ", text).strip()
    return text


def _unwrap_ddg_url(url: str) -> str:
    """
    //duckduckgo.com/l/?uddg=<encoded> 형태면 uddg 파라미터를 디코딩해서 원본 URL로 복원.
    그 외면 그대로 반환.
    """
    u = (url or "").strip()
    if u.startswith("//"):
        u = "https:" + u
    try:
        pu = urllib.parse.urlparse(u)
        if "duckduckgo.com" in (pu.netloc or "") and pu.path.startswith("/l/"):
            qs = urllib.parse.parse_qs(pu.query)
            uddg = qs.get("uddg", [""])[0]
            if uddg:
                return urllib.parse.unquote(uddg)
    except Exception:
        pass
    return u


def _source_type(url: str) -> str:
    """
    아주 단순한 출처 분류(휴리스틱)
    - gov/edu/or -> 기관
    - news/media 도메인 -> 언론
    - blog/tistory/velog 등 -> 블로그
    - 리서치/마켓리포트 -> research
    """
    u = (url or "").lower()
    host = ""
    try:
        host = urllib.parse.urlparse(u).netloc.lower()
    except Exception:
        host = ""

    if host.endswith(".go.kr") or host.endswith(".gov") or host.endswith(".ac.kr") or host.endswith(".edu"):
        return "institution"
    if any(x in host for x in ["news", "press", "media", "mk.co.kr", "chosun", "joongang", "donga", "hani", "yonhap"]):
        return "news"
    if any(x in host for x in ["tistory.com", "blog.naver.com", "brunch.co.kr", "velog.io", "medium.com"]):
        return "blog"
    if any(x in host for x in ["euromonitor", "statista", "gvr", "grandviewresearch", "marketsandmarkets", "globalresearch", "frost"]):
        return "research"
    if host.endswith(".or.kr") or "kh" in host and host.endswith(".or.kr"):
        return "association"
    return "other"


def search_web(query: str, max_results: int = 5, timeout_sec: float = 12.0) -> List[Dict[str, str]]:
    """
    키/외부 SDK 없이 웹 검색 결과를 최소 형태로 반환합니다.
    - DuckDuckGo HTML 엔드포인트 사용
    - 반환: [{title, url, snippet, type}]
    """
    q = _clean(query)
    if not q:
        return []

    params = {"q": q}
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                      "AppleWebKit/537.36 (KHTML, like Gecko) "
                      "Chrome/120.0 Safari/537.36",
        "Accept-Language": "ko-KR,ko;q=0.9,en;q=0.8",
    }

    url = _DDG_HTML + "?" + urllib.parse.urlencode(params)

    with httpx.Client(timeout=timeout_sec, headers=headers, follow_redirects=True) as client:
        r = client.get(url)
        r.raise_for_status()
        html_text = r.text

    link_pat = re.compile(
        r'<a[^>]+class="result__a"[^>]+href="(?P<href>[^"]+)"[^>]*>(?P<title>.*?)</a>',
        re.IGNORECASE | re.DOTALL,
    )
    snip_pat = re.compile(
        r'<a[^>]+class="result__snippet"[^>]*>(?P<snip>.*?)</a>|<div[^>]+class="result__snippet"[^>]*>(?P<snip2>.*?)</div>',
        re.IGNORECASE | re.DOTALL,
    )

    links = list(link_pat.finditer(html_text))
    snips = list(snip_pat.finditer(html_text))

    results: List[Dict[str, str]] = []
    for i, m in enumerate(links):
        href = _clean(m.group("href"))
        href = _unwrap_ddg_url(href)

        title = _clean(re.sub(r"<.*?>", "", m.group("title")))

        snippet = ""
        if i < len(snips):
            s = snips[i].group("snip") or snips[i].group("snip2") or ""
            snippet = _clean(re.sub(r"<.*?>", "", s))

        if href and title:
            results.append({
                "title": title,
                "url": href,
                "snippet": snippet,
                "type": _source_type(href),
            })

        if len(results) >= max_results:
            break

    return results


if __name__ == "__main__":
    for item in search_web("한국 건강기능식품 시장 규모 2024 보고서", max_results=5):
        print("-", item["type"], item["title"])
        print(" ", item["url"])
        print(" ", item["snippet"])
        print()
