# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 컨텍스트

OCI(Oracle Cloud Infrastructure)를 관리하는 MSP(Managed Service Provider) 전문 웹 플랫폼. 다수의 고객사 OCI 테넌시를 단일 화면에서 직관적으로 관리하는 것이 핵심 목표.

- **상세 기획서**: `brainstorming/07_final_plan.md`
- **팀장 리뷰**: `brainstorming/06_team_lead_review.md`

---

## 아키텍처 개요

### 모노레포 구조
```
cloud-msp/
├── apps/api/          # FastAPI 백엔드 (Python 3.12)
├── apps/web/          # Next.js 15 프론트엔드 (TypeScript)
├── packages/
│   ├── shared-types/  # 공통 TypeScript 타입
│   └── oci-client/    # OCI SDK 래퍼 (Python)
├── infrastructure/
│   ├── terraform/     # OCI IaC
│   └── k8s/           # Kubernetes 매니페스트
└── docker-compose.yml
```

### 기술 스택
| 레이어 | 기술 |
|--------|------|
| 백엔드 | FastAPI + Python 3.12, OCI Python SDK |
| 프론트엔드 | Next.js 15 (App Router) + TypeScript |
| UI | shadcn/ui + Tailwind CSS |
| DB | PostgreSQL (MVP) → OCI ATP (확장 시) |
| 캐시/브로커 | Redis (OCI Cache) |
| 비동기 작업 | Celery + Celery Beat |
| 컨테이너 | OKE (Kubernetes), HPA 자동 스케일링 |
| Observability | OpenTelemetry + OCI Logging Analytics + OCI APM |

### 멀티테넌트 OCI 접근
- **권장**: Cross-Tenancy Resource Principal (고객사 테넌시에 MSP Dynamic Group 허용)
- **대안**: API Key 방식 (고객사가 MSP용 IAM User 생성)
- **Credential 저장**: OCI Vault (HSM 암호화), DB에는 참조 ID만 저장

---

## 개발 환경 시작

```bash
# 전체 로컬 환경 (PostgreSQL + Redis + API + Worker + Web + Flower)
docker-compose up -d

# 개별 서비스 확인
docker-compose logs -f api
docker-compose logs -f worker
```

---

## 백엔드 (apps/api/)

```bash
cd apps/api

# 의존성 설치 (uv 사용)
uv sync

# 개발 서버 실행
uv run uvicorn app.main:app --reload --port 8000

# DB 마이그레이션
uv run alembic upgrade head
uv run alembic revision --autogenerate -m "설명"

# Celery Worker
uv run celery -A app.workers.celery_app worker --loglevel=info --concurrency=4

# Celery Beat (스케줄러)
uv run celery -A app.workers.celery_app beat --loglevel=info

# 전체 테스트
uv run pytest tests/ -v --cov=app

# 단일 테스트
uv run pytest tests/unit/test_services/test_compute_service.py -v

# 린팅 + 타입 체크
uv run ruff check . && uv run ruff format --check . && uv run mypy app/
```

### 백엔드 모듈 구조
```
app/
├── api/v1/         # HTTP 라우터 (auth, tenants, compute, network, storage, database, monitoring, costs, incidents, jobs)
├── core/           # 보안(JWT/RBAC), 예외처리
├── services/oci/   # OCI SDK 래퍼 (compute_service, network_service, monitoring_service, cost_service ...)
├── services/       # 비즈니스 서비스 (tenant_service, incident_service, job_service ...)
├── models/         # SQLAlchemy ORM (tenant, user, oci_resource, alert, incident, cost, job, audit_log)
├── schemas/        # Pydantic 스키마 (입출력 검증)
├── repositories/   # DB 접근 레이어
└── workers/        # Celery 비동기 작업 (oci_tasks, monitoring_tasks, cost_tasks)
```

### OCI SDK 사용 패턴
- `OCIClientFactory`: 테넌트별 OCI 클라이언트 싱글톤 팩토리
- `oci.pagination.list_call_get_all_results()`: 페이지네이션 자동 처리
- OCI `ServiceError` → 앱 커스텀 예외 변환 (404→OCIResourceError, 429→OCIQuotaError)
- Rate Limit: Redis 토큰 버킷 + 지수 백오프

### 테스트 전략
- OCI SDK는 `patch("oci.core.ComputeClient")`로 목킹
- DB는 트랜잭션 롤백으로 격리 (`conftest.py`의 `db_session` fixture)
- 커버리지 목표: 80% 이상

---

## 프론트엔드 (apps/web/)

```bash
cd apps/web

# 의존성 설치
npm install

# 개발 서버
npm run dev        # http://localhost:3000

# 빌드
npm run build

# 타입 체크 + 린팅 + 테스트
npm run type-check && npm run lint && npm test

# E2E 테스트 (Playwright)
npx playwright test
```

### 프론트엔드 구조
```
app/                # Next.js App Router
  (auth)/           # 로그인
  (dashboard)/      # 대시보드 레이아웃
    tenants/        # 고객사 관리
    compute/        # Compute 리소스
    monitoring/     # 모니터링 & 알람
    incidents/      # Incident 관리
    costs/          # 비용 분석
    settings/       # 설정/권한
components/
  ui/               # shadcn/ui 기본 컴포넌트
  oci/              # OCI 리소스별 컴포넌트 (compute/, network/, storage/)
  charts/           # 모니터링 차트 (ECharts, Recharts)
hooks/              # Custom React Hooks (useOCIResources, useWebSocket ...)
stores/             # Zustand 상태 관리
```

### 주요 라이브러리
- **차트**: Apache ECharts (모니터링 시계열) + Recharts (스파크라인)
- **테이블**: TanStack Table v8 + TanStack Virtual (수천 행 가상화)
- **서버 상태**: TanStack Query (React Query)
- **폼**: React Hook Form + Zod
- **대시보드**: React Grid Layout (드래그앤드롭 위젯)

---

## 핵심 설계 원칙

### 멀티테넌트 보안
- 테넌트 간 데이터 격리: Row Level Security (PostgreSQL RLS)
- `tenant_id`를 모든 DB 쿼리에 명시적으로 포함
- OCI Credential은 절대 DB 원문 저장 금지 (OCI Vault 경유)

### 비동기 작업 (OCI 장기 작업)
- Celery task로 처리 → `Job` 모델로 추적
- OCI Work Request ID 저장 → 폴링으로 완료 감지
- WebSocket으로 클라이언트에 실시간 진행률 전송

### 모니터링 (MVP)
- MVP: 30초~1분 폴링 (OCI Monitoring API)
- Phase 2: OCI Streaming (Kafka) 전환

### UX 핵심 패턴
- **Command Palette** [Cmd+K]: 리소스/고객사/작업 전역 검색
- **Side Sheet**: 목록 컨텍스트 유지하며 상세 조회 (Level 1→2→3)
- **비동기 작업 센터**: 우하단 고정 패널

### 위험 작업 UX
- LOW (중지/재시작): 단순 확인 다이얼로그
- HIGH (삭제): 리소스 이름 타이핑 확인 + 영향도 표시
- CRITICAL: 이중 승인 필수

---

## Celery 모니터링

```bash
# Flower UI (Celery 작업 모니터링)
open http://localhost:5555
```

---

## 환경 변수 (apps/api/.env)

```
DATABASE_URL=postgresql+asyncpg://user:pass@localhost/msp_db
REDIS_URL=redis://localhost:6379/0
SECRET_KEY=<32자 이상 랜덤 문자열>
OCI_CREDENTIALS_ENCRYPTION_KEY=<32바이트 Fernet 키>
ENVIRONMENT=development
CORS_ORIGINS=["http://localhost:3000"]
```
