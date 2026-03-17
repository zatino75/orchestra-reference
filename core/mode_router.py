# mode_router.py
# 역할: 사용자 입력을 업무 모드로 분기하는 규칙 기반 라우터
# 주의: LLM 호출 없음, Core/UX 의존 없음

from typing import Dict

MODES = {
    "chat": ["잡담", "대화", "이야기", "의견"],
    "research": ["조사", "리서치", "자료", "시장", "트렌드", "비교"],
    "document": ["문서", "정리", "작성", "보고서", "요약"],
    "planning": ["기획", "전략", "구성", "설계", "플랜"],
    "review": ["검토", "피드백", "평가", "문제점", "리스크"]
}

DEFAULT_MODE = "chat"


def route_mode(user_input: str) -> Dict[str, str]:
    """
    입력 텍스트를 기반으로 업무 모드를 결정한다.
    반환값은 반드시 mode / reason 포함
    """
    text = user_input.lower()

    for mode, keywords in MODES.items():
        for kw in keywords:
            if kw in text:
                return {
                    "mode": mode,
                    "reason": f"키워드 '{kw}' 감지"
                }

    return {
        "mode": DEFAULT_MODE,
        "reason": "명확한 업무 키워드 없음"
    }


if __name__ == "__main__":
    # 단독 테스트용
    samples = [
        "시장 조사 좀 해줘",
        "기획 구조를 다시 잡아보자",
        "이 문서 정리해줘",
        "이 아이디어 검토해줘",
        "그냥 생각 좀 해보자"
    ]

    for s in samples:
        print(s, "->", route_mode(s))
