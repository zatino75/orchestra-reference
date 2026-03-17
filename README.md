# AI ORCHESTRA

AI ORCHESTRA는 여러 AI 모델을 협력 구조로 실행하는 **멀티-AI 오케스트레이션 엔진**입니다.

목표는 단일 AI 모델이 아니라 여러 모델을 동시에 활용하여 **더 정확하고 신뢰할 수 있는 결과를 생성하는 것**입니다.

지원 모델

- OpenAI
- Claude
- Gemini
- Perplexity


------------------------------------------------------------

# Quick Start

저장소 클론

git clone https://github.com/zatino75/ai-orchestra.git

프로젝트 폴더 이동

cd ai-orchestra


의존성 설치

npm install


서버 실행

scripts/run_server.ps1


UI 실행

scripts/run_ui.ps1


------------------------------------------------------------

# Architecture

AI ORCHESTRA는 다음 구조를 사용합니다.

User  
↓  
Planner  
↓  
Execution Engine  
↓  
Adaptive Router  
↓  
Parallel Providers  
(OpenAI / Claude / Gemini / Perplexity)  
↓  
Claims Engine  
↓  
Conflict Detector  
↓  
Judge  
↓  
Final Answer


------------------------------------------------------------

# Core Components

## Planner

사용자 요청을 분석하고 실행 계획을 생성합니다.


## Execution Engine

Planner가 만든 실행 계획을 실제로 실행합니다.


## Adaptive Router

작업 유형에 따라 최적의 AI 모델을 선택합니다.


## Parallel Providers

여러 AI 모델을 동시에 실행합니다.


## Claims Engine

AI 응답에서 사실 주장(claim)을 추출합니다.


## Conflict Detector

여러 모델 응답 간 충돌 여부를 검사합니다.


## Judge Engine

최종 응답을 선택합니다.


------------------------------------------------------------

# Project Structure

server/
AI orchestration backend

src/
frontend workspace

ui/
chat interface

scripts/
운영 스크립트

docs/
설계 문서

orchestra/specs/
시스템 계약 및 스키마


------------------------------------------------------------

# Backend Modules

server/src

planner/  
execution/  
router/  
orchestra/  
judge/  
research/


------------------------------------------------------------

# Environment Variables

.env 파일 예시

OPENAI_API_KEY=

CLAUDE_API_KEY=

GEMINI_API_KEY=

PERPLEXITY_API_KEY=


------------------------------------------------------------

# Development Workflow

개발 순서

1 Planner  
2 Execution Engine  
3 Adaptive Router  
4 Parallel Providers  
5 Claims Engine  
6 Conflict Detector  
7 Judge  


------------------------------------------------------------

# Benchmark

AI ORCHESTRA는 모델 평가를 위해 benchmark 시스템을 포함합니다.

위치

server/src/benchmark


평가 기준

- correctness
- reasoning
- factuality
- completeness


------------------------------------------------------------

# Tech Stack

Backend

Node.js  
TypeScript  


Frontend

React  
Vite  


------------------------------------------------------------

# Project Status

현재 단계

Architecture implementation


개발 중 기능

Dynamic Scoreboard Router  
Multi-AI Parallel Execution  
Conflict Detection  
Judge Engine  
Benchmark Evaluator  


------------------------------------------------------------

# License

MIT
