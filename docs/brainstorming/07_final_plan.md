# OCI MSP 관리 플랫폼 - 최종 기획서

> 작성: 기획/서비스/UI/개발 에이전트 협업 + 기획팀장 리뷰 반영
> 날짜: 2026-03-21
> 상태: 최종 (실행 준비)

---

## 1. 프로젝트 개요

### 비전
**"OCI를 운영하는 MSP 엔지니어가 하루 업무의 80%를 단 하나의 플랫폼에서 완료할 수 있는 세상"**

### 비즈니스 모델 (팀장 리뷰 반영)
**옵션 C - 하이브리드 전략 채택**
- MVP ~ Phase 2: **내부 생산성 도구** (Cost Center)
  - ROI 근거: 엔지니어 1인 관리 테넌시 5~7개 → **15~20개** (3배 효율화)
- Phase 3 이후: **외부 SaaS 전환 준비** (Revenue Center)
  - 수익 모델: 테넌시당 월정액 or 관리 리소스 종량제

### 포지셔닝
> "기존 클라우드 관리 도구(CloudCheckr, Apptio 등)는 AWS/Azure 중심이며 OCI 리소스를 1급으로 지원하지 않는다. 우리는 OCI 네이티브 MSP 운영 플랫폼으로, OCI Compartment/Dynamic Group/IAM Policy 구조를 완전히 이해한 유일한 통합 관리 솔루션이다."

### 타겟 사용자
| 페르소나 | 역할 | 핵심 니즈 |
|----------|------|----------|
| MSP 운영 엔지니어 | 내부, 주 사용자 | 다수 테넌시 통합 관리, 빠른 장애 대응 |
| MSP 서비스 관리자 | 내부, 관리자 | SLA 추적, 팀 현황, Incident 현황 |
| 고객사 IT 담당자 | 외부, 셀프 포털 | 실시간 현황, 비용 확인, SR 등록 |

---

## 2. 서비스 범위 및 로드맵

### 범위 설계 원칙 (팀장 리뷰 반영)
> **"조회는 MVP, 변경은 Phase 2"** — Network/Storage/DB 변경 작업은 Phase 2로 분리하여 MVP 일정과 장애 위험을 동시에 줄인다.

---

### Phase 1: MVP (12~14주)
**목표**: MSP 엔지니어 실 업무 투입 가능, 내부 파일럿 완료

#### 1-1. 멀티 테넌시 관리
- 고객사 테넌시 등록/조회/상태 관리
- **온보딩 위저드** (5단계, 목표 15분 이내 완료):
  1. Credential 입력 (OCI API Key or Instance Principal)
  2. 권한 검증 (필요 Policy 자동 체크)
  3. Compartment 구조 자동 탐색 & 태깅
  4. 모니터링 기본값 설정
  5. 담당 엔지니어 + SLA 티어 매핑
- 테넌시 간 빠른 전환 (사이드바 즐겨찾기)
- 멀티 리전 지원

#### 1-2. 통합 대시보드
- KPI 카드: 전체 테넌시 수 / 총 리소스 수 / 활성 알람 / 월간 비용 요약
- 이상 테넌시 하이라이트 (상태별 색상 코딩)
- 최근 활동 피드 (전체 테넌트 통합)
- 위젯 드래그앤드롭 커스터마이즈

#### 1-3. 리소스 관리

| 서비스 | MVP 범위 | Phase 2 추가 |
|--------|---------|-------------|
| Compute | 인스턴스 목록/상세, 시작/중지/재시작 | 생성/삭제, 스냅샷 |
| Network | VCN/서브넷/SG **조회만** | 생성/수정/삭제 |
| Storage | Block Volume/Object Storage **조회만** | 생성/확장/삭제 |
| Database | Autonomous DB/DB System **조회만** | 백업/복구/스케일링 |

#### 1-4. 모니터링 & 알림 (30초 폴링, Phase 2에서 스트리밍 전환)
- OCI Monitoring 지표 연동 (CPU, Memory, Network, Disk)
- 알림 규칙 설정 (임계값 기반)
- **알림 피로도 방지**: 그루핑, Maintenance Window, 무음 기능
- 알림 채널: 이메일, Slack, SMS
- 알림 심각도: P1(Critical)/P2(High)/P3(Medium)/P4(Low)

#### 1-5. SLA 기본 관리 (팀장 리뷰 반영, MVP 포함)
- SLA 티어 정의 (Basic/Standard/Premium/Enterprise)
- SLA 위반 임계값 설정 및 알림
- 가용성 기본 집계 (Uptime %)

#### 1-6. Incident 관리 (팀장 리뷰 반영, MVP 포함)
- Alert → Incident 자동 생성
- 라이프사이클: 발생 → 배정(On-call) → 조치 기록 → RCA → 종료
- 담당자 에스컬레이션

#### 1-7. 감사 로그
- 모든 쓰기 작업 자동 기록 (HTTP 미들웨어)
- 기록: 행위자, IP, 대상 리소스, 결과, 소요시간
- OCI Audit Log 연동
- 보존 정책: 감사 로그 1년, 운영 로그 90일

#### 1-8. RBAC (간소화 버전)
- 4단계 역할: Super Admin / Tenant Admin / Operator / Viewer
- MFA 지원
- 테넌시별 권한 분리

---

### Phase 1.5: 즉시 가치 제공 항목 (MVP 완료 후 2~4주)
**목표**: 고객 신뢰 및 영업 차별화

| 기능 | 내용 | 임팩트 |
|------|------|--------|
| 고객사 Read-only 포털 | 자사 리소스 현황/비용 조회 | 영업 계약 클로징 차별화 |
| 비용 이상 즉시 감지 | 전일 대비 N% 증가 시 즉시 알림 | 고객보다 먼저 발견 |
| 월간 리포트 자동화 | 운영 현황 PDF 자동 생성/발송 | 엔지니어 월말 작업 제거 |

---

### Phase 2: 운영 효율화 (4~6개월)
- 고객 포털 완성 (SR 등록, 변경 승인 워크플로우)
- 비용 관리 고도화 (OCI Cost API, 예산 설정, 자동 청구서)
- SR 티켓 관리 ITSM (생성/할당/SLA 추적)
- 리소스 변경 관리 (Network/Storage/DB 생성/수정/삭제)
- 자동화 스케줄링 (시작/중지/백업)
- 보안 모니터링 (Cloud Guard 연동)
- **Runbook 기능**: 장애 유형별 대응 절차 축적
- **변경 예약 기능**: 유지보수 시간대 자동 실행 + 승인
- 실시간 스트리밍 모니터링 (OCI Streaming 전환)

### Phase 3: 지능화 (6개월+)
- AI 기반 이상 탐지 및 용량 예측 (ML, OCI GenAI 활용)
- 자동 복구 (Runbook 기반 Auto-Remediation)
- 비용 최적화 엔진 (유휴 리소스 탐지, RI 최적화)
- IaC 관리 (Terraform 자동 생성, GitOps 연동)
- 챗봇 인터페이스 (자연어 질의)
- SaaS 전환 준비 (멀티 MSP 지원)

### Phase 4: 확장 (지속)
- 멀티 클라우드 지원 (AWS, Azure 기본 연동)
- 파트너 API 제공
- 국제화 (다국어)

---

## 3. 기술 아키텍처

### 기술 스택

| 레이어 | 기술 | 근거 |
|--------|------|------|
| 백엔드 | FastAPI + Python 3.12 | OCI 공식 SDK 완전 지원, asyncio |
| 프론트엔드 | Next.js 15 + TypeScript | SSR 성능, App Router |
| UI 라이브러리 | shadcn/ui + Tailwind CSS | 커스터마이징, 접근성(Radix UI) |
| Primary DB | **PostgreSQL on OCI** (MVP) → ATP (확장 시) | MVP 비용/복잡도 최적화 |
| 캐시/세션 | Redis (OCI Cache) | API 캐싱, Rate Limit 버퍼 |
| 비동기 작업 | Celery + Redis | OCI 장기 작업, 폴링 처리 |
| 모니터링 수집 | OCI Monitoring API + Celery Beat (폴링) | MVP 단순화, Phase 2에서 스트리밍 전환 |
| 컨테이너 | OKE (Kubernetes) | OCI 네이티브, HPA 자동 스케일링 |
| Observability | OpenTelemetry + OCI Logging Analytics + OCI APM | 플랫폼 자체 모니터링 |

### 시스템 아키텍처
```
사용자 브라우저
    │ HTTPS
OCI API Gateway (JWT 검증 + WAF + Rate Limit + CORS)
    ├── Next.js Frontend (SSR, OKE 배포)
    ├── FastAPI Backend (Modular Monolith, OKE 배포)
    │       ├── Tenant Manager Module
    │       ├── Resource Manager Module
    │       ├── Monitoring Collector Module (폴링)
    │       ├── Incident Manager Module
    │       └── Cost Module
    ├── WebSocket Gateway (Incident/Job 실시간 알림)
    │
    ├── PostgreSQL (Primary DB, OCI)
    ├── Redis (캐시 + Celery 브로커)
    ├── OCI Vault (Credential 암호화 저장)
    └── 고객 OCI 테넌시들 (Multi-Tenant, Cross-Tenancy or API Key)

Platform Observability:
    OpenTelemetry → OCI Logging Analytics + OCI APM
```

### 보안 설계

| 영역 | 설계 |
|------|------|
| Credential 저장 | OCI Vault (HSM 암호화), DB에 참조 ID만 저장 |
| 고객 접근 | Cross-Tenancy Resource Principal (권장) or API Key |
| 인증 | JWT RS256, Access 15분 / Refresh 7일 Rotation |
| RBAC | 4단계 (Super Admin / Tenant Admin / Operator / Viewer) |
| 감사 로그 | HTTP 미들웨어 자동 기록, 민감정보 마스킹 |
| 데이터 격리 | Row Level Security (테넌트 간 완전 격리) |
| 컴플라이언스 | 감사 로그 1년 보존, OCI 한국 리전 저장 |

### 고가용성 및 DR

| 항목 | 설계 |
|------|------|
| Primary | ap-seoul-1 (AD-1, AD-2 분산) |
| DR | ap-chuncheon-1 |
| DB HA | PostgreSQL Streaming Replication → Phase 2 ATP 전환 |
| 스케일링 | OKE HPA (CPU 70% 기준) |
| RTO | < 30분 |
| RPO | < 5분 |

---

## 4. 핵심 데이터 모델

```
Tenant          OCI 고객사 테넌시 (Credential 참조, 온보딩 상태 포함)
TenantSLA       SLA 티어 설정 (가용성 목표, 응답시간, 위반 알림)
User/Role       RBAC (4단계 역할, 테넌시별 권한 매핑)
OCIResource     OCI 리소스 추상화 (타입별 JSONB, 동기화 상태)
AlertRule       알람 규칙 (MQL 쿼리, 임계값, 알림 채널, Maintenance Window)
Alert           알람 발생/해결 이력
Incident        Incident 라이프사이클 (Alert 연결, 담당자, RCA)
CostRecord      일별 비용 (서비스/리소스별, 이상 탐지용)
BudgetAlert     예산 초과 알림 정책
Job             비동기 작업 이력 (Celery + Work Request, 진행률)
AuditLog        감사 로그 (행위자, 리소스, 결과, 소요시간)
```

---

## 5. UI/UX 핵심 설계

### 레이아웃
- **좌측 고정 사이드바**: 240px → 72px → 56px (Ctrl+B 토글)
- **상단 전역 검색**: 모든 리소스/고객사/알람 검색
- **주요 메뉴**: Overview / Customers / Resources / Monitoring / Incidents / Billing / Settings

### 차별화 UX 5가지
1. **Command Palette** ([Cmd+K]): 고객사/리소스/작업 통합 검색, 빠른 작업
2. **Side Sheet 드릴다운**: 목록 컨텍스트 유지하며 상세 조회 (Level 1→2→3)
3. **비동기 작업 센터**: 우하단 고정 패널, 진행률 + WebSocket 실시간 표시
4. **Incident 타임라인**: 알람 → Incident → 조치 → 해결 전체 흐름 시각화
5. **다크/라이트 모드**: 기본 다크 (딥 네이비, OCI 브랜드 연계)

### 위험 작업 UX 분류
| 위험도 | 예시 | UX |
|--------|------|-----|
| LOW | 중지/재시작 | 단순 확인 다이얼로그 |
| MED | 설정 변경, 규모 조정 | 변경 요약 표시 후 확인 |
| HIGH | 리소스 삭제 | 리소스 이름 타이핑 + 영향도 표시 |
| CRITICAL | 테넌시 삭제 | 이중 승인 + 타이핑 확인 |

### "3클릭 이내" 검증 대상 TOP 10 (팀장 리뷰 반영)
1. 특정 테넌시 Compute 인스턴스 목록 조회
2. 특정 인스턴스 중지
3. 활성 알람 확인 및 처리
4. Incident 생성 및 담당자 배정
5. 새 SR 등록
6. 비용 이상 조회
7. 테넌시 전환
8. 알람 무음 처리 (Silence)
9. 감사 로그 조회
10. 월간 리포트 생성

### 핵심 라이브러리
| 용도 | 라이브러리 |
|------|----------|
| 모니터링 차트 | Apache ECharts (Canvas 기반, 대용량) |
| 소형 차트 | Recharts (스파크라인, 도넛) |
| 테이블 | TanStack Table v8 + Virtual |
| 대시보드 레이아웃 | React Grid Layout (드래그앤드롭) |
| 알림/토스트 | Sonner |
| 상태 관리 | TanStack Query (서버) + Zustand (클라이언트) |

---

## 6. 개발 계획

### 프로젝트 구조 (모노레포)
```
cloud-msp/
├── apps/
│   ├── api/          # FastAPI (Python 3.12)
│   └── web/          # Next.js 15 (TypeScript)
├── packages/
│   ├── shared-types/ # 공통 타입
│   └── oci-client/   # OCI SDK 래퍼
├── infrastructure/
│   ├── terraform/    # OCI IaC
│   └── k8s/          # Kubernetes 매니페스트
├── docker-compose.yml
└── Makefile
```

### MVP 14주 스프린트 (현실적 조정)

```
Week 1~2:   기반 인프라 + OCI API PoC
            - Docker Compose 환경 구성
            - OCI API PoC (Rate Limit, Compartment 탐색, Cross-tenancy)
            - 보안 아키텍처 리뷰 확정 (Credential 격리 방식)
            - DB 모델 설계 확정

Week 3~5:   인증/테넌시 코어
            - JWT RBAC 인증 시스템
            - 테넌시 관리 CRUD
            - 온보딩 위저드 (5단계)
            - OCI Credential 안전 저장 (Vault 연동)

Week 6~8:   리소스 관리 + 대시보드
            - OCI Client 팩토리 패턴
            - Compute 관리 (조회 + 기본 제어)
            - Network/Storage/DB 조회
            - 통합 대시보드 UI

Week 9~10:  모니터링 + Incident
            - OCI Monitoring API 폴링 (30초)
            - 알람 규칙 + 알림 발송 (Slack/이메일)
            - Incident 라이프사이클
            - SLA 기본 설정

Week 11~12: 감사 로그 + 고도화
            - 감사 로그 시스템
            - Command Palette
            - WebSocket 실시간 업데이트
            - 비용 이상 감지 알림

Week 13~14: 통합 테스트 + 내부 파일럿
            - E2E 테스트 (Playwright)
            - 성능 최적화 (캐싱, 쿼리 튜닝)
            - OKE 배포 구성
            - 내부 엔지니어 파일럿 (2~3개 테넌시)
```

### 코드 품질 기준
| 항목 | 도구/기준 |
|------|----------|
| Python 린팅 | ruff (E, F, I, N, UP, S, B, A) |
| Python 타입 | mypy (strict 모드) |
| 테스트 커버리지 | pytest, 최소 80% |
| OCI SDK 목킹 | `patch("oci.core.ComputeClient")` |
| TS 타입 | TypeScript strict 모드 |
| JS 린팅 | ESLint + Prettier |
| 프론트 테스트 | Vitest (unit) + Playwright (E2E) |

### CI/CD
```
PR → GitHub Actions:
  - ruff + mypy + pytest (백엔드)
  - TypeScript + ESLint + Vitest (프론트)
  - PR merge → OCIR 이미지 빌드
  - dev 브랜치 → OKE staging 자동 배포
  - main 브랜치 → OKE production 수동 트리거
```

---

## 7. 위험 요소 및 대응

| 위험 요소 | 영향도 | 대응 방안 |
|-----------|--------|---------|
| OCI API Rate Limit | 높음 | Redis 캐싱 + 지수 백오프 (Week 1~2 PoC) |
| 멀티 테넌시 Credential 보안 격리 | 매우 높음 | OCI Vault + Fernet, Week 2 설계 확정 |
| Compartment 계층 복잡도 | 높음 | Week 2 PoC로 조기 검증 |
| 대규모 리소스 동기화 지연 | 중간 | 증분 동기화 + 우선순위 큐 |
| 실시간 모니터링 파이프라인 | 중간 | MVP 폴링으로 단순화, Phase 2 스트리밍 |
| OCI API 변경/장애 | 높음 | API 버전 고정 + 폴백, 자체 Observability |

---

## 8. KPI 목표

| 지표 | MVP (14주 후) | Phase 2 | Phase 3 |
|------|-------------|---------|---------|
| 관리 테넌시 수 | 10개 | 30개 | 100개+ |
| 엔지니어 1인 관리 테넌시 | 7개 → **15개** | 20개+ | - |
| 장애 탐지 시간 | <5분 | <3분 | <1분 |
| 온보딩 소요 시간 | <15분 | <10분 | <5분 |
| 자동 복구율 | - | 50% | 80% |
| 월간 리포트 수작업 시간 | - | 0시간 (자동화) | - |
| 고객 만족도 (NPS) | 40+ | 55+ | 70+ |

---

## 9. 즉시 실행 액션 아이템

| 우선순위 | 항목 | 기한 |
|---------|------|------|
| 1 | 비즈니스 모델 최종 확정 (내부 도구 → SaaS 로드맵 경영진 승인) | 이번 주 |
| 2 | 개발팀 구성 확정 (인원, 역할 배정) | 이번 주 |
| 3 | OCI API PoC 착수 (Rate Limit + Compartment + Cross-tenancy) | 2주 이내 |
| 4 | 보안 아키텍처 리뷰 (멀티 테넌시 Credential 격리 방식 확정) | 2주 이내 |
| 5 | 온보딩 플로우 UI 프로토타입 (Figma 또는 코드) | 2주 이내 |
| 6 | "3클릭" 핵심 작업 TOP 10 프로토타입 검증 | 3주 이내 |
| 7 | SLA 티어 정의 + Incident 라이프사이클 설계 완료 | 3주 이내 |

---

## 부록: 개발 커맨드 가이드

```bash
# 로컬 개발 환경 시작
docker-compose up -d

# 백엔드 개발
cd apps/api
uv sync
uv run uvicorn app.main:app --reload --port 8000

# 백엔드 테스트
uv run pytest tests/ -v --cov=app

# 백엔드 린팅
uv run ruff check . && uv run ruff format --check . && uv run mypy app/

# 프론트엔드 개발
cd apps/web
npm install
npm run dev

# 프론트엔드 테스트
npm run type-check && npm run lint && npm test

# DB 마이그레이션
uv run alembic revision --autogenerate -m "description"
uv run alembic upgrade head

# Celery Worker (별도 터미널)
uv run celery -A app.workers.celery_app worker --loglevel=info

# Celery Flower 모니터링
open http://localhost:5555
```
