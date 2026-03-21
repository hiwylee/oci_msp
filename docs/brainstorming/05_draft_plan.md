# OCI MSP 관리 플랫폼 - 초안 기획서 (브레인스토밍 취합본)

> 작성: 기획/서비스/UI/개발 에이전트 협업 결과
> 날짜: 2026-03-21
> 상태: 초안 (기획팀장 리뷰 전)

---

## 1. 프로젝트 개요

### 비전
**"OCI를 운영하는 MSP 엔지니어가 하루 업무의 80%를 단 하나의 플랫폼에서 완료할 수 있는 세상"**

### 핵심 가치
- **직관성**: 3클릭 이내 핵심 작업 완료
- **통합성**: 다수 고객사 OCI 테넌시를 단일 창구에서 관리
- **신뢰성**: 실수 방지 UX + 완전한 감사 이력
- **확장성**: MVP에서 출발해 AI 기반 자동화까지

### 타겟 사용자
| 페르소나 | 역할 | 핵심 니즈 |
|----------|------|----------|
| MSP 운영 엔지니어 | 내부, 주요 사용자 | 다수 테넌시 통합 관리, 빠른 장애 대응 |
| MSP 서비스 관리자 | 내부, 관리자 | SLA 추적, 팀 현황, 고객 관계 |
| 고객사 IT 담당자 | 외부, 셀프 포털 | 실시간 현황 파악, 비용 확인, SR 등록 |

---

## 2. 서비스 범위 및 로드맵

### Phase 1: MVP (3~4개월)
**목표**: MSP 엔지니어가 실제 업무에 바로 투입 가능한 최소 기능

| 기능 | 상세 |
|------|------|
| 멀티 테넌시 관리 | 고객사 테넌시 등록/조회, 빠른 전환, 권한 분리 |
| 통합 대시보드 | 전체 고객사 상태 요약, KPI 카드, 커스터마이즈 위젯 |
| Compute 관리 | 인스턴스 목록/상세, 시작/중지/재시작, 콘솔 연결 |
| Network 관리 | VCN/서브넷/보안목록 조회, 게이트웨이 현황 |
| Storage 관리 | Block Volume, Object Storage 기본 관리 |
| DB 관리 | Autonomous DB, DB System 상태 조회 |
| 모니터링 & 알림 | OCI Monitoring 연동, 임계값 알림, Slack/이메일 |
| 감사 로그 | 모든 작업 자동 기록, OCI Audit Log 연동 |
| RBAC | 역할 기반 접근 제어, MFA 지원 |

**MVP 완료 기준**
- [ ] 10개 이상 고객사 테넌시 동시 관리
- [ ] 주요 리소스 조회 및 기본 제어
- [ ] 알림 5분 내 담당자 수신
- [ ] 모든 작업 이력 기록 및 조회

### Phase 2: 운영 효율화 (4~6개월)
- 고객 포털 (고객사 셀프서비스)
- 비용 관리 & 자동 청구서 생성
- SR 티켓 관리 (ITSM)
- 보안 모니터링 (Cloud Guard 연동)
- 자동화 스케줄링 (시작/중지/백업)
- 모니터링 고도화 (로그 통합, 토폴로지 맵)

### Phase 3: 지능화 (6개월+)
- AI 기반 이상 탐지 및 예측
- 자동 복구 (Runbook 자동화)
- 비용 최적화 엔진
- IaC 관리 (Terraform 자동 생성)
- 챗봇 (OCI GenAI 활용, 자연어 질의)

### Phase 4: 확장 (지속)
- 멀티 클라우드 지원 (AWS, Azure 기본 연동)
- 파트너 API
- 국제화

---

## 3. 기술 아키텍처

### 기술 스택

| 레이어 | 기술 | 근거 |
|--------|------|------|
| 백엔드 | FastAPI + Python 3.12 | OCI 공식 SDK, asyncio, ML 생태계 |
| 프론트엔드 | Next.js 15 + TypeScript | SSR 성능, App Router |
| UI 라이브러리 | shadcn/ui + Tailwind CSS | 커스터마이징 용이, 접근성(Radix UI) |
| Primary DB | OCI ATP (PostgreSQL mode) | OCI 네이티브, 자동 백업/스케일링 |
| 캐시/세션 | OCI Cache (Redis 호환) | API 캐싱, Rate Limit 버퍼 |
| 메시징 | OCI Streaming (Kafka 호환) | 모니터링 이벤트, 실시간 알림 |
| 비동기 작업 | Celery + Redis | OCI 장기 작업 처리 |
| 컨테이너 | OKE (Kubernetes) | OCI 네이티브, 자동 스케일링 |
| 패키지 | uv (Python), npm | 속도 최적화 |

### 시스템 아키텍처 개요
```
사용자 브라우저
    │ HTTPS
OCI API Gateway (JWT 검증 + WAF + Rate Limit)
    ├── Next.js Frontend (SSR)
    ├── FastAPI Backend (Modular Monolith)
    │       ├── Tenant Manager
    │       ├── Resource Manager
    │       └── Monitoring Collector
    ├── WebSocket Gateway (실시간 알림)
    │
    ├── OCI ATP (Primary DB)
    ├── OCI Cache (Redis)
    ├── OCI Streaming (이벤트)
    └── 고객 OCI 테넌시들 (Multi-Tenant)
```

### 보안 설계
- OCI Vault: 고객사 API Key/자격증명 HSM 암호화 저장
- JWT RS256: Access 15분 / Refresh 7일 (Rotation)
- RBAC: Super Admin → Tenant Admin → Operator → Viewer
- 감사 로그: 모든 쓰기 작업 자동 기록 (HTTP 미들웨어)
- Cross-Tenancy 접근: Cross-Tenancy Resource Principal (권장)

### 고가용성
- Primary: ap-seoul-1 / DR: ap-chuncheon-1
- OKE HPA 자동 스케일링
- RTO < 30분, RPO < 5분

---

## 4. 핵심 데이터 모델

```
Tenant          # 고객사 테넌시 (OCI Credential 포함)
User/Role       # RBAC (Super Admin/Tenant Admin/Operator/Viewer)
OCIResource     # OCI 리소스 추상화 (타입별 JSONB 저장)
AlertRule       # 알람 규칙 (MQL 쿼리, 임계값, 알림 채널)
Alert           # 알람 발생/해결 이력
CostRecord      # 일별 비용 기록 (서비스/리소스별)
BudgetAlert     # 예산 초과 알림 정책
Job             # 비동기 작업 이력 (Celery + Work Request)
```

---

## 5. UI/UX 핵심 설계

### 레이아웃
- 좌측 고정 사이드바 (240px→72px→56px 축소, [Ctrl+B] 토글)
- 상단 전역 검색 바
- 주요 메뉴: Overview / Customers / Resources / Monitoring / Billing / Settings

### 차별화 UX 포인트
1. **Command Palette** ([Cmd+K]): 고객사/리소스/작업 통합 검색
2. **Side Sheet 드릴다운**: 목록 컨텍스트 유지하며 상세 조회
3. **비동기 작업 센터**: 우하단 고정, 진행률 실시간 표시
4. **위험 작업 분류**: Low/Med/High별 차별화된 확인 흐름
5. **다크/라이트 모드**: 기본 다크 (딥 네이비, OCI 브랜드 연계)

### 차트/데이터 라이브러리
- 모니터링 차트: Apache ECharts (Canvas 기반, 대용량 성능)
- 소형 차트: Recharts (스파크라인, 도넛)
- 테이블: TanStack Table v8 + Virtual (수천 행 가상화)
- 대시보드 레이아웃: React Grid Layout (드래그앤드롭)

---

## 6. 개발 계획

### 모노레포 구조
```
cloud-msp/
├── apps/api/     # FastAPI
├── apps/web/     # Next.js
├── packages/     # 공유 타입, OCI 클라이언트
├── infrastructure/  # Terraform, k8s
└── docker-compose.yml
```

### MVP 12주 스프린트
```
1-3주:  프로젝트 기반 (Docker Compose, DB 모델, 인증, 테넌트 관리)
4-6주:  OCI 리소스 관리 (Compute, Storage, 동기화, 대시보드)
7-9주:  모니터링/알림/비용/WebSocket 실시간
10-12주: Network, 비용 분석, E2E 테스트, OKE 배포
```

### 코드 품질
- 백엔드: ruff(린팅) + mypy(strict 타입) + pytest(커버리지 80%+)
- 프론트: TypeScript strict + ESLint + Vitest + Playwright(E2E)
- CI/CD: GitHub Actions → OCIR → OKE

### OCI SDK 테스트 전략
- 단위 테스트: `patch("oci.core.ComputeClient")` 모킹
- 통합 테스트: httpx.AsyncClient + DB 트랜잭션 롤백
- E2E: Playwright (로그인 → 조작 → 상태 확인)

---

## 7. 위험 요소 및 대응

| 위험 요소 | 영향도 | 대응 방안 |
|-----------|--------|---------|
| OCI API Rate Limit | 높음 | Redis 캐싱 + 지수 백오프 |
| 고객사 Credential 보안 | 매우 높음 | OCI Vault + Fernet 암호화 |
| 멀티 테넌트 데이터 격리 | 높음 | Row Level Security + 철저한 테스트 |
| 대규모 리소스 동기화 지연 | 중간 | 증분 동기화 + 우선순위 큐 |
| WebSocket 수평 확장 | 중간 | Redis Pub/Sub 기반 |
| OCI API 변경/장애 | 높음 | API 버전 고정 + 폴백 메커니즘 |

---

## 8. KPI 목표

| 지표 | MVP | Phase 2 | Phase 3 |
|------|-----|---------|---------|
| 관리 테넌시 수 | 10개 | 30개 | 100개+ |
| 장애 탐지 시간 | <5분 | <3분 | <1분 |
| 자동 복구율 | - | 50% | 80% |
| 엔지니어 업무 효율 | +30% | +60% | +80% |
| 수동 리포팅 제거율 | 30% | 90% | 100% |
| 고객 만족도 (NPS) | 40+ | 55+ | 70+ |
