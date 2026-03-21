# OCI MSP 관리 플랫폼 - 시스템 아키텍처 설계서

> 작성: 시스템 아키텍처 설계 (최종 기획서 07_final_plan.md 기반)
> 날짜: 2026-03-21
> 버전: 1.0
> 상태: 확정

---

## 목차

1. [전체 시스템 아키텍처 다이어그램](#1-전체-시스템-아키텍처-다이어그램)
2. [모듈 구성 설계](#2-모듈-구성-설계)
3. [데이터 흐름 설계](#3-데이터-흐름-설계)
4. [캐싱 전략](#4-캐싱-전략)
5. [OCI Rate Limit 대응 전략](#5-oci-rate-limit-대응-전략)
6. [WebSocket 아키텍처](#6-websocket-아키텍처)
7. [확장성 고려사항](#7-확장성-고려사항)

---

## 1. 전체 시스템 아키텍처 다이어그램

### 1.1 최상위 컴포넌트 구조

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                          MSP Engineer / Customer Portal User                     │
│                               Browser (HTTPS)                                    │
└─────────────────────────────────┬────────────────────────────────────────────────┘
                                  │ HTTPS 443
                                  ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│                        OCI Load Balancer (Flexible Shape)                        │
│                   SSL Termination / Health Check / Sticky Session                │
└──────┬───────────────────────────────────────────────────────┬───────────────────┘
       │ HTTP                                                   │ WS
       ▼                                                        ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│                         OCI API Gateway                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  - JWT RS256 검증 (Authorization 헤더)                                   │    │
│  │  - WAF (SQL Injection, XSS, OWASP Top 10 방어)                          │    │
│  │  - Rate Limit (IP 기반, 테넌트 기반)                                     │    │
│  │  - CORS 정책 적용                                                        │    │
│  │  - Request Routing (경로별 백엔드 분기)                                  │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
└──────┬────────────────────────────────┬────────────────────────┬─────────────────┘
       │ /api/*                         │ /*                     │ /ws/*
       ▼                                ▼                        ▼
┌──────────────┐              ┌─────────────────┐     ┌──────────────────┐
│  FastAPI     │              │   Next.js 15     │     │  WebSocket       │
│  Backend     │◄────────────►│   Frontend       │     │  Gateway         │
│  (OKE Pod)   │  Internal    │   (OKE Pod)      │     │  (OKE Pod)       │
│              │  API Call    │                  │     │                  │
│  Port 8000   │              │  Port 3000       │     │  Port 8001       │
└──────┬───────┘              └─────────────────┘     └────────┬─────────┘
       │                                                        │
       │                 ┌──────────────────────────────────────┤
       │                 │                                      │
       ▼                 ▼                                      ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│                              내부 인프라 레이어 (OCI Private Subnet)              │
│                                                                                  │
│  ┌─────────────────────┐   ┌─────────────────────┐   ┌──────────────────────┐  │
│  │  PostgreSQL 16       │   │  Redis 7             │   │  OCI Vault           │  │
│  │  (Primary + Replica) │   │  (OCI Cache)         │   │  (HSM 암호화)        │  │
│  │                      │   │                      │   │                      │  │
│  │  - 멀티 테넌트 데이터 │   │  - API 응답 캐시     │   │  - OCI API Key       │  │
│  │  - Row Level Security│   │  - Celery 브로커     │   │  - 고객 Credential   │  │
│  │  - 감사 로그         │   │  - 세션 저장         │   │  - 암호화 키 관리    │  │
│  │  - Streaming Repl.  │   │  - Rate Limit 버킷   │   │                      │  │
│  └─────────────────────┘   │  - Pub/Sub (WS)      │   └──────────────────────┘  │
│                             └─────────────────────┘                              │
│  ┌──────────────────────────────────────────────┐                                │
│  │  Celery Worker Pool (OKE Deployment)          │                                │
│  │                                              │                                │
│  │  worker-1 │ worker-2 │ worker-3 │ worker-N   │                                │
│  │  ┌──────┐  ┌──────┐   ┌──────┐   ┌──────┐  │                                │
│  │  │OCI   │  │Monit.│   │Cost  │   │Sync  │  │                                │
│  │  │Tasks │  │Tasks │   │Tasks │   │Tasks │  │                                │
│  │  └──────┘  └──────┘   └──────┘   └──────┘  │                                │
│  │                                              │                                │
│  │  Celery Beat (스케줄러 - Single Instance)    │                                │
│  └──────────────────────────────────────────────┘                                │
└──────────────────────────────────┬───────────────────────────────────────────────┘
                                   │ Cross-Tenancy / API Key
                                   ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│                         고객 OCI 테넌시들 (Multi-Tenant)                         │
│                                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │
│  │  Customer A      │  │  Customer B      │  │  Customer C      │              │
│  │  Tenancy         │  │  Tenancy         │  │  Tenancy         │  ...         │
│  │                  │  │                  │  │                  │              │
│  │  - Compute       │  │  - Compute       │  │  - Compute       │              │
│  │  - Network       │  │  - Network       │  │  - Network       │              │
│  │  - Storage       │  │  - Storage       │  │  - Storage       │              │
│  │  - ATP/DB        │  │  - ATP/DB        │  │  - ATP/DB        │              │
│  │  - Monitoring    │  │  - Monitoring    │  │  - Monitoring    │              │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘              │
└──────────────────────────────────────────────────────────────────────────────────┘

Platform Observability (MSP 자체 플랫폼 모니터링):
  FastAPI/Worker → OpenTelemetry Collector → OCI Logging Analytics
                                           → OCI APM (Trace/Span)
                                           → OCI Monitoring (자체 메트릭)
```

### 1.2 OCI 네트워크 토폴로지

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  OCI Region: ap-seoul-1                                                       │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐     │
│  │  VCN: msp-platform-vcn (10.0.0.0/16)                                │     │
│  │                                                                      │     │
│  │  ┌──────────────────────────────────┐                                │     │
│  │  │  Public Subnet (10.0.1.0/24)     │                                │     │
│  │  │  - OCI Load Balancer             │                                │     │
│  │  │  - OCI API Gateway               │                                │     │
│  │  │  - NAT Gateway                   │                                │     │
│  │  └────────────────┬─────────────────┘                                │     │
│  │                   │ Private Link                                      │     │
│  │  ┌────────────────▼─────────────────┐                                │     │
│  │  │  Private Subnet - App (10.0.2.0/24)│                              │     │
│  │  │  - OKE Node Pool (FastAPI Pod)   │                                │     │
│  │  │  - OKE Node Pool (Next.js Pod)   │                                │     │
│  │  │  - OKE Node Pool (Worker Pod)    │                                │     │
│  │  │  - OKE Node Pool (WS Gateway)    │                                │     │
│  │  └────────────────┬─────────────────┘                                │     │
│  │                   │                                                   │     │
│  │  ┌────────────────▼─────────────────┐                                │     │
│  │  │  Private Subnet - Data (10.0.3.0/24)│                             │     │
│  │  │  - PostgreSQL (VM + Block Volume) │                               │     │
│  │  │  - Redis (OCI Cache)             │                                │     │
│  │  │  - OCI Vault (엔드포인트)        │                                │     │
│  │  └──────────────────────────────────┘                                │     │
│  │                                                                      │     │
│  └─────────────────────────────────────────────────────────────────────┘     │
│                                                                               │
│  DR Region: ap-chuncheon-1 (Standby)                                          │
│  - PostgreSQL Streaming Replication 대상                                       │
│  - OKE Cluster (Standby, 최소 구성)                                            │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 WebSocket을 포함한 전체 요청 흐름

```
클라이언트 (브라우저)
    │
    ├─[1] HTTPS 요청 (REST API)
    │      GET /api/v1/tenants/{id}/compute/instances
    │
    │      OCI LB → API Gateway (JWT 검증) → FastAPI
    │      → Cache Hit? → Redis 응답 반환
    │      → Cache Miss? → OCI SDK → 고객 테넌시 API
    │                   → Redis 캐시 저장 → 응답 반환
    │
    ├─[2] WebSocket 연결 수립
    │      WSS /ws/v1?token=<JWT>
    │
    │      OCI LB (Sticky Session) → WS Gateway
    │      → JWT 검증 → tenant_id 추출
    │      → Redis SUBSCRIBE msp:ws:user:{user_id}
    │      → 연결 유지 (Ping/Pong 30초)
    │
    └─[3] 실시간 이벤트 수신
           ← WS Gateway ← Redis Pub/Sub
               ← Celery Worker (모니터링/Job 완료/알람)

Celery Beat (30초 주기)
    │
    ├─ monitoring_task: OCI Monitoring API 폴링
    │   → 임계값 초과 감지
    │   → Alert 레코드 생성 → Incident 자동 생성
    │   → Redis PUBLISH msp:ws:tenant:{id} {alert_event}
    │   → WebSocket Gateway → 해당 테넌트 연결 사용자에게 전송
    │
    └─ sync_task: OCI 리소스 동기화
        → OCIResource DB 업데이트
        → 캐시 무효화
```

### 1.4 OCI 서비스 위치 정리

```
┌─────────────────────────────────────────────────────────────────────┐
│  MSP 플랫폼에서 사용하는 OCI 서비스 전체 목록                        │
│                                                                     │
│  [인그레스/보안]                                                     │
│  - OCI Load Balancer       : 엔트리포인트, SSL 종료                  │
│  - OCI API Gateway         : JWT 검증, WAF, Rate Limit              │
│  - OCI WAF                 : OWASP Top 10 보호                      │
│  - OCI Vault               : Credential 암호화 저장 (HSM)           │
│                                                                     │
│  [컴퓨팅/컨테이너]                                                   │
│  - OCI OKE                 : FastAPI, Next.js, Worker 배포          │
│  - OCI Container Registry  : Docker 이미지 저장 (OCIR)              │
│                                                                     │
│  [데이터]                                                            │
│  - OCI Cache (Redis)       : 캐시, 브로커, Pub/Sub                  │
│  - OCI Block Volume        : PostgreSQL 스토리지                    │
│  - OCI Object Storage      : 로그 아카이브, 리포트 PDF              │
│  → Phase 2: OCI ATP        : PostgreSQL 대체                        │
│                                                                     │
│  [메시지/스트리밍]                                                   │
│  → Phase 2: OCI Streaming  : 실시간 모니터링 (Kafka 호환)           │
│                                                                     │
│  [관찰가능성]                                                        │
│  - OCI Logging Analytics   : 중앙 로그 수집/분석                   │
│  - OCI APM                 : 분산 트레이싱                          │
│  - OCI Monitoring          : 플랫폼 자체 메트릭                     │
│  - OCI Notifications       : 알림 발송 (이메일, SMS, Slack)         │
│                                                                     │
│  [고객 테넌시 접근 - Cross-Tenancy]                                  │
│  - OCI IAM Resource Principal : MSP→고객 테넌시 위임 접근           │
│  - OCI Compute API             : 인스턴스 관리                      │
│  - OCI VCN API                 : 네트워크 조회                      │
│  - OCI Monitoring API          : 메트릭 수집                        │
│  - OCI Usage/Cost API          : 비용 데이터 수집                   │
│  - OCI Audit API               : 감사 로그 수집                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. 모듈 구성 설계

### 2.1 FastAPI 백엔드 전체 모듈 구조

```
apps/api/app/
│
├── api/v1/                          # HTTP 라우터 레이어
│   ├── auth.py                      # 인증/토큰 엔드포인트
│   ├── tenants.py                   # 테넌트 CRUD + 온보딩
│   ├── compute.py                   # Compute 인스턴스 관리
│   ├── network.py                   # VCN/서브넷/SG 조회
│   ├── storage.py                   # Block/Object Storage 조회
│   ├── database.py                  # ATP/DB System 조회
│   ├── monitoring.py                # 메트릭 조회 + 알람 규칙
│   ├── incidents.py                 # Incident CRUD
│   ├── costs.py                     # 비용 조회 + 이상 감지
│   ├── jobs.py                      # 비동기 작업 상태 조회
│   ├── audit.py                     # 감사 로그 조회
│   └── admin.py                     # 플랫폼 관리 (Super Admin)
│
├── core/                            # 공통 인프라 (모듈 독립)
│   ├── security.py                  # JWT RS256 생성/검증
│   ├── rbac.py                      # RBAC 권한 검사 데코레이터
│   ├── exceptions.py                # 커스텀 예외 계층
│   ├── middleware.py                # 감사 로그, 요청 추적, OTEL
│   ├── config.py                    # pydantic-settings 환경 변수
│   └── deps.py                      # FastAPI Depends 공통 의존성
│
├── modules/                         # 핵심 비즈니스 모듈 (Bounded Context)
│   ├── tenant/                      # [Tenant Manager]
│   │   ├── service.py
│   │   ├── onboarding.py
│   │   └── credential.py
│   ├── resource/                    # [Resource Manager]
│   │   ├── service.py
│   │   ├── sync.py
│   │   └── factory.py               # OCIClientFactory
│   ├── monitoring/                  # [Monitoring Collector]
│   │   ├── collector.py
│   │   ├── alert_evaluator.py
│   │   └── notification.py
│   ├── incident/                    # [Incident Manager]
│   │   ├── service.py
│   │   ├── lifecycle.py
│   │   └── escalation.py
│   └── cost/                        # [Cost Module]
│       ├── service.py
│       ├── anomaly.py
│       └── report.py
│
├── services/oci/                    # OCI SDK 래퍼 (인프라 어댑터)
│   ├── base.py                      # 기본 클라이언트 + 재시도 로직
│   ├── compute_service.py
│   ├── network_service.py
│   ├── storage_service.py
│   ├── monitoring_service.py
│   └── cost_service.py
│
├── models/                          # SQLAlchemy ORM 모델
├── schemas/                         # Pydantic 입출력 스키마
├── repositories/                    # DB 접근 레이어 (Repository Pattern)
└── workers/                         # Celery 비동기 작업
    ├── celery_app.py
    ├── oci_tasks.py                  # 리소스 동기화, 제어 작업
    ├── monitoring_tasks.py           # 메트릭 수집, 알람 평가
    └── cost_tasks.py                 # 비용 동기화, 리포트 생성
```

### 2.2 모듈별 책임과 인터페이스

#### Tenant Manager (`modules/tenant/`)

```
책임:
  - 고객 테넌시 등록/수정/삭제/상태 관리
  - 5단계 온보딩 위저드 오케스트레이션
  - OCI Credential 안전 저장/조회 (Vault 연동)
  - 테넌시 권한 정책 자동 생성 안내

핵심 인터페이스:
  TenantService.create_tenant(dto) → Tenant
  TenantService.onboard_tenant(tenant_id, step, data) → OnboardingState
  TenantService.verify_credentials(tenant_id) → VerificationResult
  TenantService.get_oci_client_config(tenant_id) → OCIConfig  # Vault 복호화

외부 의존성:
  - OCI Vault API (Credential 암호화/복호화)
  - OCI IAM API (Policy 검증)
  - PostgreSQL (테넌트 메타데이터)

다른 모듈과의 통신:
  → Resource Manager: 테넌트 활성화 시 초기 리소스 동기화 트리거
  → Monitoring Collector: 온보딩 완료 시 폴링 스케줄 등록
  → (이벤트 방식: Celery 비동기 태스크로 결합 완화)
```

#### Resource Manager (`modules/resource/`)

```python
# OCIClientFactory에 TTL 기반 만료 및 LRU 제거 추가
from cachetools import TTLCache

class OCIClientFactory:
    def __init__(self):
        # 최대 200개 테넌트, TTL 1시간 (Credential 교체 반영)
        self._clients: TTLCache = TTLCache(maxsize=200, ttl=3600)
```

> **메모리 참고**: OKE Pod 메모리 2Gi 기준 최대 200개 테넌트 클라이언트 캐싱 가능

```
책임:
  - OCI 리소스 조회/캐싱/DB 동기화
  - OCIClientFactory: 테넌트별 OCI SDK 클라이언트 생성/관리 (싱글톤)
  - Compute 인스턴스 제어 (시작/중지/재시작)
  - 리소스 메타데이터 표준화 (OCI 응답 → 내부 스키마)

핵심 인터페이스:
  OCIClientFactory.get_compute_client(tenant_id) → ComputeClient
  OCIClientFactory.get_network_client(tenant_id) → VirtualNetworkClient
  ResourceService.list_instances(tenant_id, compartment_id) → List[Instance]
  ResourceService.control_instance(tenant_id, instance_id, action) → Job
  ResourceSyncService.sync_all(tenant_id) → SyncResult  # Celery 태스크

외부 의존성:
  - OCI Compute/Network/Storage/DB API
  - Redis (캐시 읽기/쓰기)
  - PostgreSQL (OCIResource 테이블)
  - OCI Vault (Credential 조회, Tenant Manager 경유)

다른 모듈과의 통신:
  → Incident Manager: 리소스 상태 변경 감지 시 알람 생성 트리거
  → Job 모듈: 비동기 제어 작업 Job 레코드 생성
```

#### Monitoring Collector (`modules/monitoring/`)

```
책임:
  - OCI Monitoring API 폴링 (30초 주기, Celery Beat)
  - 알람 규칙 평가 (임계값 초과 감지)
  - 알림 채널 발송 (이메일, Slack, SMS)
  - Maintenance Window 적용 (무음 처리)
  - 알람 그루핑 (알림 피로도 방지)

핵심 인터페이스:
  MonitoringCollector.collect_metrics(tenant_id) → MetricBatch  # Celery 태스크
  AlertEvaluator.evaluate(metric_batch, rules) → List[Alert]
  NotificationService.send(alert, channels) → None
  AlertEvaluator.is_silenced(alert, windows) → bool

외부 의존성:
  - OCI Monitoring API (MQL 쿼리)
  - OCI Notifications (발송 채널)
  - Redis (메트릭 최신값 캐시, Pub/Sub 발행)
  - PostgreSQL (AlertRule, Alert 테이블)

다른 모듈과의 통신:
  → Incident Manager: Alert 생성 시 자동 Incident 생성 트리거
  → WebSocket: Redis Pub/Sub을 통한 실시간 알람 이벤트 발행
```

#### Incident Manager (`modules/incident/`)

```
책임:
  - Incident 라이프사이클 관리 (발생→배정→조치→RCA→종료)
  - Alert → Incident 자동 생성 (중복 방지, 그루핑)
  - On-call 담당자 배정 및 에스컬레이션
  - SLA 위반 감지 및 알림
  - RCA(Root Cause Analysis) 기록 관리

핵심 인터페이스:
  IncidentService.create_from_alert(alert_id) → Incident
  IncidentService.assign(incident_id, user_id) → Incident
  IncidentService.update_status(incident_id, status, note) → Incident
  IncidentService.close_with_rca(incident_id, rca_dto) → Incident
  EscalationService.check_and_escalate(incident_id) → None  # Celery 주기 실행

외부 의존성:
  - PostgreSQL (Incident, Alert, TenantSLA 테이블)
  - OCI Notifications / Slack (에스컬레이션 알림)
  - Redis (Pub/Sub, 실시간 상태 변경 발행)

다른 모듈과의 통신:
  ← Monitoring Collector: Alert 이벤트 수신 (Celery 태스크로 연결)
  → WebSocket: Incident 상태 변경 실시간 발행
```

#### Cost Module (`modules/cost/`)

```
책임:
  - OCI Usage/Cost API 일별 비용 수집 (매일 새벽 2시, Celery Beat)
  - 비용 이상 감지 (전일 대비 N% 증가)
  - 예산 초과 알림 (BudgetAlert)
  - 월간 리포트 자동 생성 (PDF → OCI Object Storage)
  - 테넌트별 비용 집계 및 서비스별 분석

핵심 인터페이스:
  CostService.sync_daily_costs(tenant_id) → CostSyncResult  # Celery 태스크
  AnomalyDetector.detect(tenant_id, date) → List[CostAnomaly]
  ReportService.generate_monthly(tenant_id, year, month) → ReportURL

외부 의존성:
  - OCI UsageAPI (Cost 데이터)
  - OCI Object Storage (리포트 PDF 저장)
  - PostgreSQL (CostRecord, BudgetAlert 테이블)
  - Redis (이상 감지 임시 캐시)

다른 모듈과의 통신:
  → Incident Manager: 비용 이상 감지 시 P2 Alert 생성
  → WebSocket: 예산 초과 알림 실시간 발행
```

### 2.3 모듈 간 의존성 다이어그램

```
                    ┌─────────────────┐
                    │   HTTP API 레이어 │  ← 요청 진입점
                    │  (api/v1/*.py)   │
                    └────────┬────────┘
                             │ 호출
          ┌──────────────────┼──────────────────┐
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│  Tenant Manager │ │ Resource Manager│ │  Cost Module    │
│                 │ │                 │ │                 │
│  테넌트 관리     │ │  OCI 리소스     │ │  비용 수집/분석  │
│  온보딩 위저드   │ │  동기화/제어    │ │  이상 감지       │
└────────┬────────┘ └────────┬────────┘ └────────┬────────┘
         │                   │                    │
         │ Credential 제공    │ Alert 트리거        │ Alert 트리거
         ▼                   ▼                    ▼
         │          ┌─────────────────┐           │
         │          │Monitoring       │           │
         │          │Collector        │           │
         │          │                 │           │
         └─────────►│  메트릭 수집     │◄──────────┘
                    │  알람 평가       │
                    │  알림 발송       │
                    └────────┬────────┘
                             │ Alert → Incident
                             ▼
                    ┌─────────────────┐
                    │ Incident Manager│
                    │                 │
                    │  라이프사이클    │
                    │  에스컬레이션    │
                    └────────┬────────┘
                             │ Pub/Sub
                             ▼
                    ┌─────────────────┐
                    │  Redis Pub/Sub  │
                    │  ↓              │
                    │  WebSocket GW   │  → 브라우저 실시간 알림
                    └─────────────────┘

공통 인프라 (모든 모듈이 의존):
  - core/security.py   : JWT 검증
  - core/rbac.py       : 권한 검사
  - services/oci/      : OCI SDK 래퍼
  - repositories/      : DB 접근
  - Redis              : 캐시/브로커
```

### 2.4 마이크로서비스 분리 시 Bounded Context 경계

```
현재: Modular Monolith (단일 FastAPI 프로세스)
향후: 각 모듈을 독립 마이크로서비스로 분리 가능

분리 우선순위 및 경계:

Priority 1 - Monitoring Service (Phase 2)
  이유: 폴링 → Streaming 전환 시 독립적 스케일링 필요
        트래픽 패턴이 다름 (시간 기반 배치 vs 요청 기반)
  분리 경계:
    IN : Alert 규칙, 테넌트 설정 (이벤트로 수신)
    OUT: Alert 이벤트 (Kafka/OCI Streaming으로 발행)
    DB : 별도 TimeSeries DB 또는 ATP 고려

Priority 2 - Cost Service (Phase 2)
  이유: 외부 MSP 제공 시 과금 서비스 분리 필요
        데이터 볼륨이 커질수록 독립 스케일링 이점
  분리 경계:
    IN : 비용 수집 스케줄 (Kafka Consumer)
    OUT: 비용 이상 이벤트 (Kafka 발행)
    DB : 별도 OLAP 저장소 (OCI Data Flow + Object Storage)

Priority 3 - Tenant Service (Phase 3, SaaS 전환 시)
  이유: SaaS 확장 시 테넌시 관리가 플랫폼의 핵심 서비스가 됨
  분리 경계:
    IN : 테넌시 등록/변경 요청
    OUT: 테넌시 프로비저닝 완료 이벤트
    DB : 전용 테넌시 레지스트리 DB

분리 시 통신 방식 전환:
  현재: 함수 호출 (동일 프로세스)
  분리: REST API (동기) 또는 OCI Streaming/Kafka (비동기)
  권장: 알람/이벤트성 → 비동기 메시지, 조회성 → REST
```

---

## 3. 데이터 흐름 설계

### 3.1 OCI 리소스 조회 흐름

```
사용자                  FastAPI                  Redis              OCI API
  │                       │                        │                   │
  │ GET /compute/instances │                        │                   │
  ├──────────────────────►│                        │                   │
  │                       │ cache_key =            │                   │
  │                       │  "oci:compute:         │                   │
  │                       │   {tenant}:{region}:   │                   │
  │                       │   {comp}"              │                   │
  │                       │                        │                   │
  │                       │ GET cache_key          │                   │
  │                       ├───────────────────────►│                   │
  │                       │                        │                   │
  │             [Cache Hit]│◄───────────────────────│                  │
  │◄──────────────────────│ 캐시된 응답 즉시 반환   │                   │
  │  (P99 < 5ms)          │                        │                   │
  │                       │                        │                   │
  │            [Cache Miss]│ (nil 반환)             │                   │
  │                       │                        │                   │
  │                       │ OCI Rate Limit 토큰 확인│                   │
  │                       ├───────────────────────►│                   │
  │                       │◄───────────────────────│ 토큰 차감 성공     │
  │                       │                        │                   │
  │                       │ list_instances()       │                   │
  │                       ├───────────────────────────────────────────►│
  │                       │                        │                   │
  │                       │◄───────────────────────────────────────────│
  │                       │ OCI 응답 수신           │                   │
  │                       │                        │                   │
  │                       │ 응답 정규화 (_normalize)│                   │
  │                       │                        │                   │
  │                       │ SET cache_key, TTL=300s│                   │
  │                       ├───────────────────────►│                   │
  │                       │                        │                   │
  │◄──────────────────────│ 정규화된 응답 반환      │                   │
  │                       │                        │                   │

캐시 키 네이밍 규칙:
  oci:{service}:{tenant_id}:{region}:{compartment_id}[:{resource_id}]
  # 리전별 캐시 격리: 동일 테넌트의 다른 리전 리소스가 충돌하지 않도록

예시:
  oci:compute:ocid1.tenancy.A:ap-seoul-1:ocid1.compartment.X         → 인스턴스 목록 (TTL: 5분)
  oci:compute:ocid1.tenancy.A:ap-seoul-1:ocid1.compartment.X:inst-1  → 인스턴스 상세 (TTL: 2분)
  oci:network:ocid1.tenancy.A:ap-seoul-1:*                           → VCN 목록 (TTL: 10분)
```

### 3.2 모니터링 데이터 수집 흐름

```
Celery Beat                 Celery Worker          OCI Monitoring    Redis         WebSocket GW    Browser
(30초 주기)                  (monitoring_tasks)       API               (Pub/Sub)
    │                            │                      │                │               │             │
    │ monitoring.collect_metrics │                      │                │               │             │
    │ 태스크 발행 (모든 활성 테넌트)│                      │                │               │             │
    ├───────────────────────────►│                      │                │               │             │
    │                            │                      │                │               │             │
    │                            │ query_metrics(MQL)   │                │               │             │
    │                            ├─────────────────────►│                │               │             │
    │                            │◄─────────────────────│                │               │             │
    │                            │ 메트릭 응답 수신       │                │               │             │
    │                            │                      │                │               │             │
    │                            │ [임계값 평가]          │                │               │             │
    │                            │ AlertEvaluator.eval() │               │               │             │
    │                            │                      │                │               │             │
    │                            │ [정상] HMSET metric:{tenant}:{metric} │               │             │
    │                            ├──────────────────────────────────────►│               │             │
    │                            │                      │                │               │             │
    │                            │ [임계값 초과]          │                │               │             │
    │                            │ Alert 레코드 DB 생성  │                │               │             │
    │                            │                      │                │               │             │
    │                            │ PUBLISH msp:ws:tenant:{id}            │               │             │
    │                            │  {type:"alert", severity:"P1", ...}  │               │             │
    │                            ├──────────────────────────────────────►│               │             │
    │                            │                      │                │               │             │
    │                            │ Incident 자동 생성 태스크 발행         │               │             │
    │                            │ (incident.create_from_alert)          │               │             │
    │                            │                      │                │               │             │
    │                            │                      │      ┌─────────┤               │             │
    │                            │                      │      │ SUBSCRIBE│               │             │
    │                            │                      │      │ msp:ws:  │               │             │
    │                            │                      │      │ tenant:* │               │             │
    │                            │                      │      └─────────►│               │             │
    │                            │                      │                │ 이벤트 수신    │             │
    │                            │                      │                │───────────────►│             │
    │                            │                      │                │               │ WS 메시지    │
    │                            │                      │                │               │────────────►│
    │                            │                      │                │               │ {alarm발생} │

메트릭 저장 전략:
  - 최신값: Redis HMSET (TTL 5분, 대시보드 즉시 조회용)
  - 이력: PostgreSQL (Alert/Incident 연결 이력만)
  - 시계열: Phase 2에서 OCI Monitoring 장기 보관 또는 별도 TSDB 고려
```

### 3.3 비동기 작업 흐름 (Compute 인스턴스 중지 예시)

```
Browser           FastAPI              PostgreSQL    Redis(Broker)    Celery Worker    OCI API
  │                  │                     │              │                │               │
  │ POST /compute/   │                     │              │                │               │
  │  instances/{id}/ │                     │              │                │               │
  │  actions/stop    │                     │              │                │               │
  ├─────────────────►│                     │              │                │               │
  │                  │ Job 레코드 생성      │              │                │               │
  │                  │ (status=PENDING)    │              │                │               │
  │                  ├────────────────────►│              │                │               │
  │                  │◄────────────────────│              │                │               │
  │                  │ job_id 반환         │              │                │               │
  │                  │                     │              │                │               │
  │                  │ AuditLog 기록 (미들웨어)            │                │               │
  │                  │                     │              │                │               │
  │◄─────────────────│                     │              │                │               │
  │ 202 Accepted     │                     │              │                │               │
  │ {job_id: "xxx"}  │                     │              │                │               │
  │                  │                     │              │                │               │
  │                  │ oci_tasks.stop_instance.delay()    │                │               │
  │                  ├──────────────────────────────────►│                │               │
  │                  │                     │              │                │               │
  │                  │                     │              │ 태스크 수신     │               │
  │                  │                     │              │────────────────►│               │
  │                  │                     │              │                │               │
  │                  │                     │              │                │ instance_action│
  │                  │                     │              │                │ (STOP)        │
  │                  │                     │              │                ├──────────────►│
  │                  │                     │              │                │◄──────────────│
  │                  │                     │              │                │ work_request_id│
  │                  │                     │              │                │               │
  │                  │                     │ Job 업데이트  │                │               │
  │                  │                     │ (status=RUNNING,              │               │
  │                  │                     │  oci_work_request_id=xxx)     │               │
  │                  │                     │◄──────────────────────────────│               │
  │                  │                     │              │                │               │
  │                  │                     │              │                │ [Work Request 폴링 루프]
  │                  │                     │              │                │ get_work_req() │
  │                  │                     │              │                ├──────────────►│
  │                  │                     │              │                │◄──────────────│
  │                  │                     │              │                │ status=InProgress (progress=40%)
  │                  │                     │              │                │               │
  │                  │                     │              │                │ Job progress 업데이트
  │                  │                     │              │                │               │
  │                  │                     │              │                │ PUBLISH job_progress
  │                  │                     │    Redis ◄───────────────────│               │
  │ ◄──── WebSocket ─────────────────────────────────────│               │               │
  │ {job_id, progress: 40}                 │              │                │               │
  │                  │                     │              │                │               │
  │                  │                     │              │                │ get_work_req() │
  │                  │                     │              │                ├──────────────►│
  │                  │                     │              │                │◄──────────────│
  │                  │                     │              │                │ status=Succeeded
  │                  │                     │              │                │               │
  │                  │                     │ Job 최종 업데이트             │               │
  │                  │                     │ (status=COMPLETED, result)    │               │
  │                  │                     │◄──────────────────────────────│               │
  │                  │                     │              │                │               │
  │                  │                     │              │                │ 캐시 무효화    │
  │                  │                     │              │                │ DEL oci:compute:{tenant}:{region}:*
  │                  │                     │              │ Redis ◄────────│               │
  │                  │                     │              │                │               │
  │                  │                     │              │                │ PUBLISH job_complete
  │ ◄──── WebSocket ─────────────────────────────────────│               │               │
  │ {job_id, status:"COMPLETED", instance_state:"STOPPED"}│               │               │
```

### 3.4 알람 → Incident 자동 생성 흐름

```
Monitoring Collector              Incident Manager             On-call 담당자
(Celery Worker)                   (Celery Worker)
      │                                  │                           │
      │ Alert 발생 감지                   │                           │
      │ (CPU > 90%, 3분 연속)             │                           │
      │                                  │                           │
      │ Alert 레코드 생성                 │                           │
      │ (status=FIRING, severity=P2)     │                           │
      │                                  │                           │
      │ incident.create_from_alert       │                           │
      │ 태스크 발행                       │                           │
      ├─────────────────────────────────►│                           │
      │                                  │                           │
      │                                  │ [중복 체크]                │
      │                                  │ 동일 테넌트 + 동일 리소스의│
      │                                  │ OPEN 상태 Incident 있는가?│
      │                                  │                           │
      │                                  │ [없음] 새 Incident 생성    │
      │                                  │ (priority = alert.severity)│
      │                                  │ (sla_tier → 응답 시간 계산)│
      │                                  │                           │
      │                                  │ [있음] 기존 Incident에 Alert│
      │                                  │ 추가 (그루핑)              │
      │                                  │                           │
      │                                  │ On-call 담당자 조회        │
      │                                  │ (테넌트 배정 엔지니어,     │
      │                                  │  SLA 티어 기반 에스컬 규칙)│
      │                                  │                           │
      │                                  │ 알림 발송 (Slack/SMS/이메일)
      │                                  ├──────────────────────────►│
      │                                  │                           │
      │                                  │ Redis PUBLISH             │
      │                                  │ msp:ws:incident:{id}      │
      │                                  │ {type:"incident_created"} │
      │                                  │                           │
      │                                  │ SLA 타이머 시작            │
      │                                  │ (응답 시간 임박 시 에스컬) │
      │                                  │                           │
      │                    ┌─────────────┘                           │
      │                    │ 30분 후 (SLA=Standard, P2 미응답)       │
      │                    │                                         │
      │                    │ EscalationService.check()               │
      │                    │ 상위 관리자에게 에스컬레이션 알림        │
      │                    └────────────────────────────────────────►│
                                                                     │
Alert 해결 시:
  Monitoring Collector → alert.status = RESOLVED
  → Incident에 연결된 Alert 모두 RESOLVED?
    → Yes: Incident.status = RESOLVED_PENDING_RCA (자동 전환)
    → No: 계속 OPEN 유지
```

---

## 4. 캐싱 전략

### Redis 장애 시 Graceful Degradation 전략

Redis를 5가지 역할(캐시/Celery 브로커/JWT 블랙리스트/Rate Limit/WebSocket Pub/Sub)로 사용하므로
Redis 장애 시 전체 플랫폼 연쇄 장애 위험이 있다. 각 기능별 Degradation 전략:

| 기능 | Redis 장애 시 동작 | 위험도 |
|------|------------------|--------|
| API 응답 캐시 | OCI SDK 직접 호출 (응답 지연 증가, Rate Limit 소비 주의) | Medium |
| Celery 브로커 | 태스크 큐잉 불가 → 동기 처리 또는 실패 응답 | High |
| JWT 블랙리스트 | 로그아웃된 토큰도 만료까지 유효 (15분) → 보안 허용 범위 내 | Medium |
| Rate Limit | OCI SDK 직접 Rate Limit 적용 → OCI 기본 제한에 의존 | Medium |
| WebSocket Pub/Sub | 실시간 이벤트 전달 불가 → 클라이언트 폴링 폴백 | High |

**권고**: OCI Cache with Redis는 OCI 관리형 Redis로 자체 고가용성(Multi-AZ) 지원.
Redis Sentinel 또는 OCI Cache Cluster 모드 사용 시 단일 장애점 제거 가능.

### 4.1 Redis 캐시 계층 설계

```
┌──────────────────────────────────────────────────────────────────┐
│                    Redis 캐시 네임스페이스 구조                    │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [1] OCI API 응답 캐시                                            │
│  oci:{service}:{tenant_id}:{region}:{compartment_id}[:{resource_id}] │
│                                                                  │
│  [2] 세션/인증                                                    │
│  session:{user_id}:{session_id}                                  │
│  refresh_token:{user_id}:{token_hash}                            │
│  blacklist:token:{jti}  (로그아웃된 토큰)                        │
│                                                                  │
│  [3] Rate Limit 토큰 버킷                                         │
│  ratelimit:oci:{service}:{tenant_id}                             │
│  ratelimit:api:{ip_or_user_id}                                   │
│                                                                  │
│  [4] 모니터링 최신값                                              │
│  metric:{tenant_id}:{resource_id}:{metric_name}                  │
│                                                                  │
│  [5] Celery 작업 결과                                             │
│  celery-task-meta-{task_id}  (Celery 기본)                       │
│                                                                  │
│  [6] Pub/Sub 채널 (휘발성, 저장 없음)                             │
│  msp:ws:tenant:{tenant_id}                                       │
│  msp:ws:user:{user_id}                                           │
│  msp:ws:incident:{incident_id}                                   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 4.2 TTL 정책 (리소스 종류별)

```
┌──────────────────────────────────────────────────────────────────┐
│  캐시 유형                        TTL      근거                   │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [OCI API 응답 캐시]                                              │
│  Compute 인스턴스 목록            300s     잦은 상태 변화 주의    │
│  Compute 인스턴스 상세            120s     개별 제어 후 무효화    │
│  VCN/서브넷 목록                  600s     변경 빈도 낮음         │
│  Block Volume 목록               300s     -                      │
│  Object Storage 버킷             1800s    거의 변경 없음         │
│  ATP/DB System 목록              600s     -                      │
│  Compartment 목록                3600s    변경 매우 드묾         │
│  OCI Tenancy 정보                7200s    거의 고정              │
│  IAM Policy 검증 결과             300s     -                      │
│                                                                  │
│  [비용 데이터]                                                    │
│  일별 비용 집계                   3600s    하루 한 번 수집        │
│  월간 비용 요약                   1800s    -                      │
│                                                                  │
│  [모니터링]                                                       │
│  메트릭 최신값                    60s      폴링 주기와 동일       │
│  알람 규칙 목록                   300s     변경 후 명시적 무효화  │
│                                                                  │
│  [인증/세션]                                                      │
│  JWT Access Token 블랙리스트      900s     토큰 만료(15분)와 동일│
│  Refresh Token                   604800s  7일                    │
│  사용자 세션 정보                 3600s    -                      │
│                                                                  │
│  [Rate Limit]                                                    │
│  OCI API 토큰 버킷                -        서비스별 윈도우 단위   │
│  플랫폼 API Rate Limit            60s      슬라이딩 윈도우        │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 4.3 캐시 무효화 전략

```
전략 1: TTL 만료 (기본)
  - 모든 캐시에 TTL 적용
  - 캐시 미스 시 OCI API 재조회 → 재저장

전략 2: 이벤트 기반 명시적 무효화 (중요 작업 후)
  발동 시점 → 무효화 키 패턴:

  인스턴스 시작/중지/재시작 완료
    → DEL oci:compute:{tenant_id}:{region}:{compartment_id}
    → DEL oci:compute:{tenant_id}:{region}:{compartment_id}:{instance_id}

  테넌트 설정 변경
    → DEL oci:*:{tenant_id}:*  (테넌트 전체 캐시 삭제)

  알람 규칙 수정
    → DEL alert_rules:{tenant_id}

  온보딩 완료 (최초 동기화)
    → 캐시 없음, 즉시 OCI API 조회 후 캐시 적재

전략 3: 백그라운드 리프레시 (선제적 갱신)
  - Celery Beat가 5분마다 전체 리소스 동기화 시
    → 캐시도 함께 갱신 (조회 지연 없이 항상 최신)
  - 모니터링 폴링(30초) → metric:{} 키 갱신

전략 4: 캐시 태깅 (향후)
  - 태그 기반 그룹 무효화를 위해 Redis 태그 구조 설계
  - 예: {tenant_id}:{compartment_id} 태그로 관련 키 일괄 삭제

구현 예시:
  async def invalidate_compute_cache(tenant_id: str, region: str, compartment_id: str):
      pattern = f"oci:compute:{tenant_id}:{region}:{compartment_id}*"
      keys = await redis.keys(pattern)  # SCAN으로 대체 권장
      if keys:
          await redis.delete(*keys)
```

---

## 5. OCI Rate Limit 대응 전략

### 5.1 OCI 서비스별 Rate Limit 현황

```
┌──────────────────────────────────────────────────────────────────────┐
│  OCI 서비스별 Rate Limit 정보 (2026 기준, 변동 가능)                  │
├────────────────────┬─────────────────────────┬───────────────────────┤
│  서비스             │  Rate Limit              │  비고                 │
├────────────────────┼─────────────────────────┼───────────────────────┤
│  Identity IAM      │  50 req/sec (per tenancy)│  정책 조회 빈번        │
│  Compute           │  50 req/sec (per region) │  인스턴스 관리 핵심   │
│  Virtual Network   │  50 req/sec (per region) │  -                    │
│  Block Volume      │  50 req/sec (per region) │  -                    │
│  Object Storage    │  100 req/sec             │  상대적 여유           │
│  Monitoring        │  20 req/sec (per region) │  가장 제한적          │
│  Usage/Cost API    │  10 req/min              │  매우 제한적           │
│  Audit             │  20 req/sec              │  -                    │
│  Vault             │  25 req/sec              │  Credential 조회 주의 │
├────────────────────┴─────────────────────────┴───────────────────────┤
│  * 429 Too Many Requests 응답 시 Retry-After 헤더 확인 필수           │
│  * 멀티 테넌시에서 각 테넌시의 Rate Limit은 독립적                     │
│  * Monitoring API가 가장 제한적 → 특별 관리 필요                      │
└──────────────────────────────────────────────────────────────────────┘
```

### 5.2 토큰 버킷 알고리즘 구현

```python
# 개념 구조 (Redis Lua Script 기반 원자적 실행)

# 토큰 버킷 파라미터 (서비스별 설정)
RATE_LIMITS = {
    "monitoring": {"capacity": 20, "refill_rate": 20, "window": 1},  # 20/sec
    "compute":    {"capacity": 50, "refill_rate": 50, "window": 1},  # 50/sec
    "cost":       {"capacity": 10, "refill_rate": 10, "window": 60}, # 10/min
    "identity":   {"capacity": 50, "refill_rate": 50, "window": 1},  # 50/sec
    "vault":      {"capacity": 25, "refill_rate": 25, "window": 1},  # 25/sec
}

# Redis 키: ratelimit:oci:{service}:{tenant_id}
# 저장값: {tokens: float, last_refill: timestamp}

# Lua 스크립트 (원자적 토큰 소비)
TOKEN_BUCKET_SCRIPT = """
local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local refill_rate = tonumber(ARGV[2])
local window = tonumber(ARGV[3])
local now = tonumber(ARGV[4])
local requested = tonumber(ARGV[5])

local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
local tokens = tonumber(bucket[1]) or capacity
local last_refill = tonumber(bucket[2]) or now

-- 경과 시간 기반 토큰 보충
local elapsed = now - last_refill
local refilled = math.min(capacity, tokens + (elapsed * refill_rate / window))

if refilled >= requested then
    redis.call('HMSET', key, 'tokens', refilled - requested, 'last_refill', now)
    redis.call('EXPIRE', key, window * 2)
    return 1  -- 성공
else
    return 0  -- Rate Limit 초과
end
"""

# 지수 백오프 재시도 전략
async def call_oci_with_retry(
    service: str,
    tenant_id: str,
    func: Callable,
    max_retries: int = 5,
    base_delay: float = 1.0,
    max_delay: float = 60.0,
):
    for attempt in range(max_retries):
        # 토큰 획득 대기
        while not await acquire_token(service, tenant_id):
            await asyncio.sleep(0.1)  # 100ms 대기 후 재확인

        try:
            return await func()

        except oci.exceptions.ServiceError as e:
            if e.status == 429:
                retry_after = int(e.headers.get("Retry-After", base_delay))
                wait_time = min(
                    max(retry_after, base_delay * (2 ** attempt)),
                    max_delay
                )
                # 지터 추가 (Thundering Herd 방지)
                wait_time += random.uniform(0, wait_time * 0.1)
                await asyncio.sleep(wait_time)
            else:
                raise
    raise MaxRetriesExceeded(f"{service} 최대 재시도 초과")
```

### 5.3 멀티 테넌시 동시 요청 처리

```
문제:
  - N개 테넌시 × 30초 폴링 = 동시 N개 OCI API 요청
  - 특정 OCI 리전 서비스에서 Rate Limit 초과 가능
  - (예: 20개 테넌시 × Monitoring 폴링 = 동시 20 req)

해결 전략 1: 세마포어 기반 동시성 제어 (서비스별)

  # 서비스별 최대 동시 요청 수 제한
  CONCURRENCY_LIMITS = {
      "monitoring": asyncio.Semaphore(15),  # 20 req/sec의 75%만 사용
      "compute":    asyncio.Semaphore(35),  # 50 req/sec의 70%만 사용
      "cost":       asyncio.Semaphore(5),   # 10 req/min 보수적 제한
  }

  async def controlled_api_call(service, tenant_id, func):
      async with CONCURRENCY_LIMITS[service]:
          return await call_oci_with_retry(service, tenant_id, func)

해결 전략 2: 폴링 태스크 순차 분산 (Jitter 적용)

  # Celery Beat 스케줄: 모든 테넌트를 한 번에 실행하지 않음
  # 대신 각 테넌트별 태스크를 0~30초 내 랜덤 지연으로 분산

  @celery.task
  def schedule_monitoring_collection():
      tenants = get_active_tenants()
      for i, tenant in enumerate(tenants):
          # 테넌트당 (30초 / 테넌트수) 간격으로 분산
          delay = (30 / len(tenants)) * i
          collect_metrics.apply_async(
              args=[tenant.id],
              countdown=delay
          )

해결 전략 3: 우선순위 큐 (P1 알람 발생 시)

  Celery 큐 우선순위:
    high_priority    → 인시던트, P1/P2 알람 평가, 즉시 제어 작업
    default          → 일반 리소스 조회, 메트릭 수집
    low_priority     → 전체 동기화, 비용 수집, 리포트 생성

  # 긴급 상황에서 low_priority 태스크는 대기
  # Worker는 high_priority → default → low_priority 순서로 소비

해결 전략 4: 서킷 브레이커

  상태: CLOSED → OPEN → HALF_OPEN

  CLOSED  : 정상 동작, 실패 카운트 추적
  OPEN    : 연속 5회 실패 시, 30초간 OCI API 호출 차단
            → 캐시 데이터 제공, 실패 응답 대신 "데이터 지연" 표시
  HALF_OPEN: 30초 후 단건 시도, 성공 시 CLOSED 복귀

  구현: Redis에 circuit:{service}:{tenant_id} = {state, failure_count, opened_at}
```

---

## 6. WebSocket 아키텍처

### 6.1 WebSocket 이벤트 유형 및 구조

```
실시간 알림 대상:

  [1] Alert 이벤트
  {
    "type": "alert",
    "event": "fired" | "resolved" | "acknowledged",
    "data": {
      "alert_id": "...",
      "tenant_id": "...",
      "resource_id": "...",
      "severity": "P1" | "P2" | "P3" | "P4",
      "title": "CPU Usage Critical",
      "metric_value": 95.3,
      "threshold": 90.0,
      "fired_at": "2026-03-21T10:30:00Z"
    }
  }

  [2] Incident 이벤트
  {
    "type": "incident",
    "event": "created" | "assigned" | "updated" | "resolved",
    "data": {
      "incident_id": "...",
      "tenant_id": "...",
      "priority": "P1" | "P2" | "P3" | "P4",
      "title": "...",
      "status": "OPEN" | "IN_PROGRESS" | "RESOLVED",
      "assigned_to": "engineer@msp.com"
    }
  }

  [3] Job 진행률 이벤트
  {
    "type": "job",
    "event": "progress" | "completed" | "failed",
    "data": {
      "job_id": "...",
      "job_type": "instance_stop",
      "tenant_id": "...",
      "progress": 75,
      "progress_message": "Waiting for instance to stop...",
      "result": null | {...}
    }
  }

  [4] 모니터링 메트릭 (대시보드 실시간 업데이트)
  {
    "type": "metric",
    "event": "update",
    "data": {
      "tenant_id": "...",
      "resource_id": "...",
      "metrics": {
        "cpu_utilization": 45.2,
        "memory_utilization": 62.8,
        "timestamp": "2026-03-21T10:30:00Z"
      }
    }
  }
```

### 6.2 수평 확장: Redis Pub/Sub 기반 아키텍처

```
OKE Pod 수평 확장 시 WebSocket 상태 공유 문제 해결:

┌─────────────────────────────────────────────────────────────────┐
│  클라이언트                                                      │
│  user_A → WS Gateway Pod-1                                      │
│  user_B → WS Gateway Pod-2 (다른 Pod)                          │
└──────────────┬──────────────┬──────────────────────────────────┘
               │              │
               ▼              ▼
┌─────────────────────────────────────────────────────────────────┐
│  WebSocket Gateway Pod-1        WebSocket Gateway Pod-2         │
│                                                                 │
│  connections = {                connections = {                 │
│    user_A: [ws_conn]              user_B: [ws_conn]             │
│  }                              }                               │
│                                                                 │
│  SUBSCRIBE                       SUBSCRIBE                      │
│  msp:ws:tenant:T1  ◄────────────────────────────────────────── │
│  msp:ws:user:A                                                  │
│                                                   msp:ws:tenant:T1
│                                                   msp:ws:user:B │
└──────────────┬──────────────┬──────────────────────────────────┘
               │              │
               ▼              ▼
       ┌──────────────────────────┐
       │  Redis (Pub/Sub 허브)    │
       │                          │
       │  PUBLISH 발신자:          │
       │  Celery Worker (모니터링) │
       │  FastAPI (Incident 변경) │
       └──────────────────────────┘

이벤트 발행 흐름:
  Celery Worker → redis.publish("msp:ws:tenant:T1", event_json)
  → Pod-1 SUBSCRIBE 수신 → user_A에게 WebSocket 전송
  → Pod-2 SUBSCRIBE 수신 → user_B에게 WebSocket 전송

구독 채널 전략:
  - msp:ws:tenant:{tenant_id}   : 해당 테넌트 권한 있는 모든 사용자
  - msp:ws:user:{user_id}       : 특정 사용자 전용 (개인 Job 완료 등)
  - msp:ws:incident:{incident_id}: 특정 Incident 담당자들
```

### 6.3 연결 관리 (인증, 재연결, Timeout)

```python
# WebSocket Gateway 연결 관리 설계

class WebSocketManager:

    # [1] 연결 수립 시 인증
    async def connect(websocket: WebSocket, token: str):
        try:
            payload = jwt.decode(token, RS256_PUBLIC_KEY)
            user_id = payload["sub"]
            tenant_ids = payload["tenants"]  # RBAC 권한 있는 테넌트 목록

        except jwt.ExpiredSignatureError:
            await websocket.close(code=4001, reason="Token expired")
            return

        except jwt.InvalidTokenError:
            await websocket.close(code=4003, reason="Invalid token")
            return

        # 연결 등록 (메모리)
        connection_id = generate_connection_id()
        connections[user_id].append(connection_id)

        # Redis 구독 (해당 사용자의 테넌트 채널)
        pubsub = redis.pubsub()
        channels = [f"msp:ws:tenant:{tid}" for tid in tenant_ids]
        channels.append(f"msp:ws:user:{user_id}")
        await pubsub.subscribe(*channels)

        return WebSocketSession(user_id, connection_id, pubsub)

    # [2] Ping/Pong (연결 유지 확인)
    # 서버 → 클라이언트: 30초 주기로 PING
    # 클라이언트 응답 없음 → 60초 후 연결 종료

    async def heartbeat_loop(session: WebSocketSession):
        while True:
            await asyncio.sleep(30)
            try:
                await session.websocket.send_json({"type": "ping"})
            except WebSocketDisconnect:
                await cleanup(session)
                break

    # [3] 클라이언트 재연결 전략 (프론트엔드)
    # - 지수 백오프: 1s → 2s → 4s → 8s → 최대 30s
    # - 재연결 시 최신 JWT로 재인증
    # - 재연결 성공 시 missed_events 요청
    #   (서버는 최근 5분 이벤트를 Redis에 임시 보관)

    # [4] 연결 수 제한
    MAX_CONNECTIONS_PER_USER = 5  # 동일 계정 다중 탭 지원
    MAX_TOTAL_CONNECTIONS = 10000  # Pod당 최대

    # [5] 연결 정리 (정상/비정상 종료)
    async def cleanup(session: WebSocketSession):
        connections[session.user_id].remove(session.connection_id)
        await session.pubsub.unsubscribe()
        await session.pubsub.close()
```

### 6.4 WebSocket OKE 배포 고려사항

```
[Sticky Session 설정]
  OCI Load Balancer → Cookie 기반 Sticky Session
  이유: WebSocket 연결은 HTTP Upgrade 후 동일 Pod에 유지되어야 함
  설정: AWSALB 쿠키 또는 OCI LB 세션 퍼시스턴스

[OKE HPA (수평 확장) 설정]
  Deployment: websocket-gateway
  replicas: 2 → 10 (자동 스케일)
  HPA 기준: 연결 수 기반 메트릭 (커스텀 메트릭)
  Pod당 최대 연결: 10,000개

[Pod Disruption Budget]
  minAvailable: 1
  이유: 롤링 배포 시 항상 최소 1개 Pod 유지
  + 클라이언트 자동 재연결로 무중단 전환

[리소스 요청]
  resources:
    requests:
      memory: "256Mi"
      cpu: "250m"
    limits:
      memory: "512Mi"
      cpu: "500m"
```

---

## 7. 확장성 고려사항

### 7.1 단계별 아키텍처 변화

```
Phase 1 (MVP): Modular Monolith
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  [단일 FastAPI 프로세스]
  + PostgreSQL (단독 VM, Block Volume)
  + Redis (OCI Cache 단일 인스턴스)
  + Celery Worker (2~4 프로세스)
  + OKE (소규모: 3 Node, VM.Standard.E4.Flex 2 OCPU/8GB)

  지원 규모: 테넌시 10~20개, 동시 사용자 50명
  비용 예상: ~$300-500/월 (OCI 환경)

Phase 2: 모듈 분리 + 인프라 고도화
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  변경 1: PostgreSQL → OCI ATP (Autonomous Transaction Processing)
    이유: 자동 스케일링, 자동 백업, Data Guard 내장
    전환 방법: Alembic 마이그레이션 + ATP 호환 연결

  변경 2: 모니터링 폴링 → OCI Streaming (Kafka 호환)
    이유: 테넌시 30개+ 시 30초 폴링의 OCI API Rate Limit 부담
    아키텍처:
      - 고객 테넌시에 OCI Connector Hub 설정
        → 고객 OCI Monitoring Alarm → MSP OCI Streaming 토픽
      - Celery Beat 폴링 대신 OCI Streaming Consumer로 전환
      - 지연 시간: 30초 → <5초

  변경 3: Monitoring Module → 독립 서비스
    - 별도 OKE Deployment 분리
    - OCI Streaming Consumer 전담
    - TimeSeries 저장소 검토 (InfluxDB on VM 또는 OCI Monitoring 장기 보관)

  변경 4: Redis Sentinel → Redis Cluster
    이유: 고가용성 및 수평 분산
    구성: 3 Master + 3 Replica, OCI Cache 클러스터 옵션 활용

  지원 규모: 테넌시 30~50개, 동시 사용자 200명

Phase 3: 마이크로서비스 + AI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  변경 1: Cost Service 독립화
    - OCI Data Flow (Spark)로 대규모 비용 분석
    - OCI Object Storage에 Parquet 형식 장기 보관

  변경 2: Tenant Service 독립화 (SaaS 전환)
    - 별도 테넌시 레지스트리 DB
    - 프로비저닝 자동화 API

  변경 3: AI/ML 파이프라인 추가
    - OCI Data Science (이상 탐지 모델)
    - OCI GenAI (자연어 쿼리, Runbook 생성)

  지원 규모: 테넌시 100개+, 동시 사용자 500명+
```

### 7.2 모니터링 폴링 → OCI Streaming 전환 시점과 방법

```
전환 트리거 (둘 중 하나 충족 시):
  1. 관리 테넌시 수 >= 25개 (Monitoring API Rate Limit 임박)
  2. 모니터링 지연 SLA 요구사항 < 10초 (폴링으로는 불가)

전환 방법 (무중단):

Step 1: OCI Streaming 인프라 준비 (병행 운영)
  - MSP OCI 테넌시에 Streaming Stream Pool 생성
  - 토픽: msp-monitoring-events (파티션 수: 테넌시 수 × 2)
  - Connector Hub (고객 테넌시별 설정):
    Source: OCI Monitoring Alarms
    Target: MSP Streaming (Cross-Tenancy 권한)

Step 2: Dual Consumer 운영 (2주)
  - 기존 Celery 폴링 유지
  - 신규 Streaming Consumer 추가 (OKE 별도 Pod)
  - 두 경로의 Alert 중복 처리 (idempotent insert)

Step 3: 폴링 비율 단계적 감소
  - 테넌트 20% → Streaming 전환, 80% 폴링 유지
  - 이상 없으면 100% Streaming 전환
  - Celery Beat 모니터링 태스크 비활성화

Step 4: 폴링 롤백 플랜
  - Feature Flag (Redis)로 테넌트별 전환/롤백 즉시 가능
  - Streaming 장애 시 자동으로 폴링 모드로 fallback
```

### 7.3 수평 확장 병목 지점 및 해결 방안

```
┌──────────────────────────────────────────────────────────────────┐
│  병목 1: OCI API Rate Limit                                       │
│                                                                  │
│  증상: 429 에러 증가, 데이터 신선도 저하                            │
│  해결:                                                            │
│   - Redis 토큰 버킷으로 사전 제어 (섹션 5 참고)                    │
│   - 폴링 주기 동적 조정 (Rate Limit 여유에 따라 30초→60초)         │
│   - Phase 2: OCI Streaming으로 완전 해결                          │
├──────────────────────────────────────────────────────────────────┤
│  병목 2: PostgreSQL 쓰기 부하                                     │
│                                                                  │
│  증상: 감사 로그 INSERT 지연, 동기화 지연                           │
│  해결:                                                            │
│   - 감사 로그: Buffered Write (배치 INSERT, 5초 모아서)            │
│   - Read Replica: 조회 쿼리는 Replica로 분산 (SQLAlchemy 설정)    │
│   - Phase 2: ATP 전환 (자동 스케일링, Read Pool)                  │
│   - Connection Pool: PgBouncer (트랜잭션 모드, OKE 사이드카)      │
├──────────────────────────────────────────────────────────────────┤
│  병목 3: Redis 메모리 부족                                        │
│                                                                  │
│  증상: OOM, 캐시 히트율 급락                                       │
│  해결:                                                            │
│   - maxmemory-policy: allkeys-lru (가장 오래된 캐시 자동 삭제)    │
│   - 대용량 테넌시는 캐시 키 분리 + 별도 Redis DB (0~15 번호)      │
│   - Phase 2: Redis Cluster (OCI Cache 클러스터 옵션)              │
├──────────────────────────────────────────────────────────────────┤
│  병목 4: Celery Worker 처리 지연                                  │
│                                                                  │
│  증상: 태스크 큐 적체, Job 완료 지연                               │
│  해결:                                                            │
│   - OKE HPA: Worker Pod 자동 스케일 (큐 깊이 기반 커스텀 메트릭)  │
│   - 큐 분리: high/default/low 우선순위 큐                         │
│   - Worker 전문화: 모니터링 전용 Worker vs 일반 Worker            │
│   - KEDA (Kubernetes Event-driven Autoscaler):                   │
│     Redis 큐 깊이 기반 Worker Pod 자동 스케일                     │
├──────────────────────────────────────────────────────────────────┤
│  병목 5: WebSocket 연결 집중                                      │
│                                                                  │
│  증상: WS Pod 메모리 과부하, 이벤트 전달 지연                       │
│  해결:                                                            │
│   - OKE HPA: 연결 수 기반 커스텀 메트릭으로 Pod 자동 스케일        │
│   - OCI LB Sticky Session으로 연결 균등 분산                      │
│   - 이벤트 배치 전송: 100ms 내 동일 사용자 이벤트를 묶어 전송      │
│   - 비활성 연결 정리: 60초 Ping 무응답 시 자동 종료               │
└──────────────────────────────────────────────────────────────────┘
```

### 7.4 관찰가능성 (Observability) 설계

```
플랫폼 자체를 모니터링하는 스택:

┌────────────────────────────────────────────────────────────────┐
│  계층              도구                    수집 대상            │
├────────────────────────────────────────────────────────────────┤
│  메트릭            OCI Monitoring          OKE Pod CPU/MEM      │
│                   (커스텀 메트릭)          Redis 연결/메모리     │
│                                           Celery 큐 깊이        │
│                                           OCI API 응답 시간     │
│                                           캐시 히트율           │
├────────────────────────────────────────────────────────────────┤
│  트레이싱          OCI APM                 FastAPI 요청 추적     │
│                   (OpenTelemetry)         OCI SDK 호출 추적     │
│                                           Celery 태스크 추적    │
│                                           DB 쿼리 추적          │
├────────────────────────────────────────────────────────────────┤
│  로그              OCI Logging Analytics  애플리케이션 로그      │
│                   (구조화 JSON)           감사 로그 (1년 보관)  │
│                                           OCI Audit API 로그   │
├────────────────────────────────────────────────────────────────┤
│  알람              OCI Notifications      플랫폼 이상 감지       │
│                                           (CPU > 80%, 큐 적체) │
└────────────────────────────────────────────────────────────────┘

핵심 대시보드 (OCI Logging Analytics):
  - 테넌트별 OCI API 호출 수 및 Rate Limit 소진율
  - Celery 태스크 성공/실패율 및 처리 시간
  - WebSocket 연결 수 추이
  - 캐시 히트율 (목표: > 80%)
  - 엔드포인트별 P95/P99 응답 시간 (목표: P95 < 500ms)
```

---

## 부록 A: 보안 아키텍처 요약

```
┌─────────────────────────────────────────────────────────────────┐
│  보안 레이어                설계                                  │
├─────────────────────────────────────────────────────────────────┤
│  Credential 저장            OCI Vault (HSM), DB에 Vault Secret  │
│                             ID만 저장. Fernet 추가 암호화.       │
├─────────────────────────────────────────────────────────────────┤
│  고객 테넌시 접근            Cross-Tenancy Resource Principal    │
│                             (권장): MSP Dynamic Group → 고객    │
│                             IAM Policy 허용. API Key 방식은      │
│                             Key를 Vault에 저장.                  │
├─────────────────────────────────────────────────────────────────┤
│  인증                       JWT RS256. Access 15분, Refresh 7일  │
│                             Rotation. 로그아웃 시 JTI 블랙리스트 │
├─────────────────────────────────────────────────────────────────┤
│  RBAC                       4단계 (Super Admin/Tenant Admin/     │
│                             Operator/Viewer). FastAPI Depends   │
│                             데코레이터로 엔드포인트별 적용.       │
├─────────────────────────────────────────────────────────────────┤
│  데이터 격리                 PostgreSQL RLS (Row Level Security) │
│                             모든 쿼리에 tenant_id 필터 강제.     │
├─────────────────────────────────────────────────────────────────┤
│  감사 로그                   HTTP 미들웨어 자동 기록. 민감정보    │
│                             마스킹. 1년 보존 (OCI Object         │
│                             Storage 아카이브).                   │
├─────────────────────────────────────────────────────────────────┤
│  네트워크                    VCN Private Subnet 분리.            │
│                             OCI Security List + NSG 최소 권한.  │
│                             고객 테넌시 접근은 OCI IAM으로만.    │
└─────────────────────────────────────────────────────────────────┘
```

## 부록 B: 핵심 설계 결정 근거

| 결정 항목 | 선택 | 근거 |
|-----------|------|------|
| Modular Monolith | MVP 선택 | 초기 팀 규모(소규모)에서 마이크로서비스는 운영 오버헤드가 ROI를 초과. 모듈 경계를 명확히 하여 추후 분리 용이. |
| PostgreSQL → ATP | 순차 전환 | MVP에서 ATP는 비용 대비 효과 낮음. 규모 성장(테넌시 30개+, 데이터 수십GB)에서 ATP 자동 스케일이 가치 발생. |
| Redis Pub/Sub (WebSocket) | 채택 | OKE 수평 확장 시 WebSocket 상태 공유 문제를 가장 단순하게 해결. Kafka 대비 MVP 복잡도 낮음. |
| 폴링 → Streaming 순차 전환 | 채택 | OCI Streaming 설정에는 고객 테넌시 Connector Hub 구성이 필요. MVP 온보딩 복잡도를 낮추기 위해 폴링 우선. |
| 토큰 버킷 (Redis Lua) | 채택 | OCI Rate Limit은 서비스별, 테넌시별 독립. Redis Lua Script로 원자적 처리 → 분산 환경에서 정확한 제어. |
| Cross-Tenancy Resource Principal | 권장 | API Key 방식은 Key 로테이션, 분실 위험. Resource Principal은 OCI IAM 정책으로 관리되어 더 안전하고 감사 추적 용이. |
| Row Level Security | 채택 | 애플리케이션 레벨 tenant_id 필터만으로는 코드 버그 시 데이터 노출 위험. DB 레벨 RLS를 추가 방어선으로 적용. |
