# AI Orchestra MVP RUNBOOK (Windows / Local)

## 목표
- 8000 FastAPI(Uvicorn) 서버를 동일한 방식으로 기동/점검한다.
- UI(5173)와 분리된 백엔드로 운영한다.

## 표준 기동(권장)
명령:
Set-Location C:\Users\User\Desktop\orchestra
pwsh -NoProfile -ExecutionPolicy Bypass -File .\ops\start_server.ps1

## 표준 점검(권장)
명령:
Set-Location C:\Users\User\Desktop\orchestra
pwsh -NoProfile -ExecutionPolicy Bypass -File .\ops\check_health.ps1

## 서버 종료
- 서버가 떠 있는 콘솔에서 Ctrl + C

## 포트
- API 서버: http://127.0.0.1:8000
- UI 개발 서버(별도): http://127.0.0.1:5173

## 진단 포인트
- /api/health: 서버 생존 + router 상태
- /api/status: 요청 카운터 + 마지막 요청/에러 요약

## 원칙
- ops는 “최소 표준”만 유지한다.
- 고급 운영 자동화(Docker/systemd/Reverse proxy)는 운영 방식 확정 후 별도 설계한다.