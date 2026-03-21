# OCI MSP Management Platform

> OCI(Oracle Cloud Infrastructure)를 운영하는 MSP 엔지니어가 하루 업무의 80%를 단 하나의 플랫폼에서 완료할 수 있는 세상

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python](https://img.shields.io/badge/Python-3.12-blue.svg)](https://www.python.org/)
[![Next.js](https://img.shields.io/badge/Next.js-15-black.svg)](https://nextjs.org/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115-green.svg)](https://fastapi.tiangolo.com/)

---

## 개요

OCI 기반 MSP(Managed Service Provider) 전문 웹 플랫폼. 다수의 고객사 OCI 테넌시를 **단일 화면에서 직관적으로 통합 관리**하는 것이 핵심 목표입니다.

기존 클라우드 관리 도구(CloudCheckr, Apptio 등)는 AWS/Azure 중심으로 OCI를 1급으로 지원하지 않습니다. 이 플랫폼은 **OCI Compartment / Dynamic Group / IAM Policy 구조를 완전히 이해한 OCI 네이티브 MSP 운영 플랫폼**입니다.

### 핵심 가치

- **운영 효율 3배 향상**: 엔지니어 1인 관리 테넌시 5~7개 → 15~20개
- **15분 온보딩**: 5단계 위저드로 고객사 테넌시 등록 완료
- **직관적 UX**: Command Palette, Side Sheet 드릴다운, 실시간 비동기 작업 센터

---

## 주요 기능

| 기능 | MVP (Phase 1) | Phase 2 |
|------|:---:|:---:|
| 멀티 테넌시 관리 (등록/조회/온보딩) | ✅ | |
| 통합 대시보드 (드래그앤드롭 위젯) | ✅ | |
| Compute 인스턴스 관리 (시작/중지/재시작) | ✅ | |
| Network / Storage / DB 조회 | ✅ | |
| 모니터링 & 알림 (임계값 기반) | ✅ | |
| SLA 기본 관리 (Uptime %, 위반 알림) | ✅ | |
| Incident 라이프사이클 관리 | ✅ | |
| Compute 리소스 생성/삭제 | | ✅ |
| 비용 분석 & 예산 알림 | | ✅ |
| 고객사 셀프 포털 | | ✅ |
| OCI Streaming 실시간 모니터링 | | ✅ |

---

## 기술 스택

| 레이어 | 기술 |
|--------|------|
| 백엔드 | FastAPI + Python 3.12, OCI Python SDK |
| 프론트엔드 | Next.js 15 (App Router) + TypeScript |
| UI | shadcn/ui + Tailwind CSS |
| 데이터베이스 | PostgreSQL 16 (MVP) → OCI ATP (확장 시) |
| 캐시 / 메시지 브로커 | Redis (OCI Cache) |
| 비동기 작업 | Celery + Celery Beat |
| 컨테이너 오케스트레이션 | OKE (Oracle Kubernetes Engine), HPA 자동 스케일링 |
| IaC | Terraform |
| CI/CD | GitHub Actions → OCIR → OKE |
| Observability | OpenTelemetry + OCI Logging Analytics + OCI APM |

---

## 아키텍처

### 모노레포 구조

```
oci_msp/
├── apps/
│   ├── api/               # FastAPI 백엔드 (Python 3.12)
│   └── web/               # Next.js 15 프론트엔드 (TypeScript)
├── packages/
│   ├── shared-types/      # 공통 TypeScript 타입
│   └── oci-client/        # OCI SDK 래퍼 (Python)
├── infrastructure/
│   ├── terraform/         # OCI IaC 모듈
│   └── k8s/               # Kubernetes 매니페스트
├── docs/
│   ├── brainstorming/     # 기획 문서 (에이전트 협업 결과)
│   └── plan/              # 상세 설계 문서
├── docker-compose.yml
└── CLAUDE.md
```

### 멀티테넌트 OCI 접근 방식

```
MSP 플랫폼
    │
    ├── Cross-Tenancy Resource Principal (권장)
    │     └── 고객사 테넌시에 MSP Dynamic Group 허용 IAM Policy 추가
    │
    └── API Key 방식 (대안)
          └── 고객사가 MSP용 IAM User 생성 → API Key 발급
                └── OCI Vault (HSM 암호화) 저장 / DB에는 참조 ID만 저장
```

---

## 빠른 시작

### 사전 요구사항

- Docker & Docker Compose
- Python 3.12+, [uv](https://github.com/astral-sh/uv)
- Node.js 20+, npm

### 로컬 환경 실행

```bash
# 전체 서비스 실행 (PostgreSQL + Redis + API + Worker + Web + Flower)
docker-compose up -d

# 서비스 상태 확인
docker-compose ps

# 로그 확인
docker-compose logs -f api
docker-compose logs -f worker
```

### 백엔드 개발

```bash
cd apps/api

# 의존성 설치
uv sync

# 개발 서버
uv run uvicorn app.main:app --reload --port 8000

# DB 마이그레이션
uv run alembic upgrade head

# Celery Worker
uv run celery -A app.workers.celery_app worker --loglevel=info

# Celery Beat (스케줄러)
uv run celery -A app.workers.celery_app beat --loglevel=info
```

### 프론트엔드 개발

```bash
cd apps/web

# 의존성 설치
npm install

# 개발 서버 (http://localhost:3000)
npm run dev
```

---

## 테스트

### 백엔드

```bash
cd apps/api

# 전체 테스트 (커버리지 목표 80%)
uv run pytest tests/ -v --cov=app

# 단일 테스트 파일
uv run pytest tests/unit/test_services/test_compute_service.py -v

# 린팅 + 타입 체크
uv run ruff check . && uv run ruff format --check . && uv run mypy app/
```

### 프론트엔드

```bash
cd apps/web

# 타입 체크 + 린팅 + 유닛 테스트
npm run type-check && npm run lint && npm test

# E2E 테스트 (Playwright)
npx playwright test
```

---

## 환경 변수

`apps/api/.env` 파일을 생성하고 아래 값을 설정합니다.

```env
DATABASE_URL=postgresql+asyncpg://user:pass@localhost/msp_db
REDIS_URL=redis://localhost:6379/0
SECRET_KEY=<32자 이상 랜덤 문자열>
OCI_CREDENTIALS_ENCRYPTION_KEY=<32바이트 Fernet 키>
ENVIRONMENT=development
CORS_ORIGINS=["http://localhost:3000"]
```

> **보안 주의**: OCI Credential은 절대 환경 변수 또는 DB에 직접 저장하지 않습니다. 반드시 OCI Vault를 통해 관리합니다.

---

## 설계 문서

| 문서 | 설명 |
|------|------|
| [시스템 아키텍처](docs/plan/system-architecture.md) | 전체 컴포넌트 구조, 데이터 흐름, 캐싱/WebSocket 전략 |
| [데이터베이스 설계](docs/plan/database-design.md) | ERD, SQLAlchemy 모델, RLS 정책, 파티셔닝 전략 |
| [API 설계](docs/plan/api-design.md) | REST API 전체 명세, Pydantic 스키마, WebSocket |
| [보안 설계](docs/plan/security-design.md) | STRIDE 위협 모델, JWT/MFA/RBAC, OCI Vault 연동 |
| [인프라/DevOps](docs/plan/infrastructure-devops.md) | Terraform, K8s 매니페스트, CI/CD, DR 전략 |
| [UI/UX 설계](docs/plan/00_index.md) | 디자인 시스템, 화면 설계, 컴포넌트, 접근성 |
| [기획서 (최종)](docs/brainstorming/07_final_plan.md) | 비즈니스 모델, 로드맵, 스프린트 계획 |

---

## 로드맵

```
Phase 1 (MVP, 12~14주)
  └── 멀티 테넌시 관리, 통합 대시보드, Compute 관리
      모니터링 & 알림, SLA 기본 관리, Incident 관리

Phase 1.5
  └── 고객사 읽기 전용 포털, 비용 이상 감지, 월간 리포트 자동화

Phase 2
  └── 리소스 생성/삭제, 전체 비용 분석, Webhook 연동
      OCI Streaming 실시간 모니터링, Terraform Drift 감지

Phase 3
  └── 외부 SaaS 전환, 다중 클라우드(AWS/GCP) 지원 검토
```

---

## 모니터링 도구

| 도구 | URL | 용도 |
|------|-----|------|
| API 서버 | http://localhost:8000/docs | FastAPI Swagger UI |
| Flower | http://localhost:5555 | Celery 작업 모니터링 |
| 프론트엔드 | http://localhost:3000 | Web UI |

---

## 보안 정책

- **멀티테넌트 격리**: PostgreSQL Row Level Security (RLS) + 모든 쿼리에 `tenant_id` 명시
- **Credential 보안**: OCI Vault (HSM) 저장, DB에는 참조 ID만 보관
- **인증**: JWT RS256 (Access 15분 / Refresh 7일 Sliding Window Rotation)
- **권한 체계**: Super Admin / Tenant Admin / Operator / Viewer (4단계 RBAC)
- **위험 작업 보호**: 리소스명 타이핑 확인 + 이중 승인 (Critical 등급)

---

## 라이선스

MIT License — 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요.

---

## 기여

이 프로젝트는 현재 초기 개발 단계입니다. 이슈 및 PR은 언제든지 환영합니다.
