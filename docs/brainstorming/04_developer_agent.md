# 개발자 에이전트 - 브레인스토밍 결과

## 1. 프로젝트 구조

### 모노레포 채택 (초기 단계)
- 빠른 개발 속도, TypeScript 타입 공유, 코드 재사용 용이

```
cloud-msp/
├── apps/
│   ├── api/            # FastAPI 백엔드
│   └── web/            # Next.js 프론트엔드
├── packages/
│   ├── shared-types/   # 공통 TypeScript 타입
│   └── oci-client/     # OCI SDK 래퍼 (Python)
├── infrastructure/
│   ├── terraform/      # OCI IaC
│   ├── docker/
│   └── k8s/            # Kubernetes 매니페스트
├── docker-compose.yml
└── Makefile
```

### 백엔드 구조 (FastAPI)
```
apps/api/app/
├── api/v1/             # API 라우터 (auth, tenants, compute, network, storage, database, monitoring, costs, jobs)
├── core/               # 보안, RBAC, 예외처리
├── services/
│   ├── oci/            # OCI SDK 래퍼 (compute, network, storage, database, monitoring, cost)
│   └── ...             # 비즈니스 서비스
├── models/             # SQLAlchemy ORM
├── schemas/            # Pydantic 스키마
├── repositories/       # DB 접근 레이어
├── workers/            # Celery 비동기 작업
└── db/                 # 세션, 마이그레이션
```

---

## 2. 핵심 데이터 모델

### Tenant
```python
class Tenant(BaseModel):
    name, slug, status          # 기본 정보
    oci_tenancy_ocid            # OCI 테넌시 OCID
    oci_region, oci_regions     # 단일/멀티 리전
    oci_credentials             # 암호화된 API Key (Vault 연동)
    settings, metadata          # 커스텀 설정
```

### User/Role (RBAC)
```python
class UserRole(Enum):
    SUPER_ADMIN    # 플랫폼 전체
    TENANT_ADMIN   # 테넌트 관리
    OPERATOR       # 생성/수정
    VIEWER         # 읽기 전용

PERMISSIONS = {
    SUPER_ADMIN:  ["*"],
    TENANT_ADMIN: ["tenant:read", "user:*", "resource:*", "monitoring:*"],
    OPERATOR:     ["resource:*", "monitoring:read", "cost:read"],
    VIEWER:       ["resource:read", "monitoring:read", "cost:read"]
}
```

### OCIResource (추상화)
```python
class OCIResource(BaseModel):
    tenant_id, resource_type    # 테넌트 귀속
    oci_id (OCID), oci_compartment_id, oci_region
    status, lifecycle_state
    resource_data               # JSONB: 원본 OCI 응답
    tags, custom_tags           # OCI 태그 + MSP 커스텀 태그
    last_synced_at              # 동기화 시간
```

### Alert / AlertRule
```python
class AlertRule:
    mql_query                   # OCI Monitoring Query Language
    condition_operator, condition_threshold
    evaluation_window, severity
    notification_channels       # [email, slack, pagerduty, sms]

class Alert:
    rule_id, resource_id
    severity, status            # FIRING | RESOLVED | ACKNOWLEDGED
    oci_alarm_id, metric_value
    fired_at, resolved_at, acknowledged_by
```

### Cost / Budget
```python
class CostRecord:
    usage_date, usage_month
    service_name, oci_resource_id
    cost_amount, usage_amount, usage_unit

class BudgetAlert:
    monthly_budget, alert_threshold_pct (기본 80%)
    notification_channels
```

### Job (비동기 작업)
```python
class Job:
    job_type, status            # PENDING|RUNNING|COMPLETED|FAILED
    parameters, result
    celery_task_id
    progress (0-100), progress_message
    oci_work_request_id         # OCI Work Request 추적
    retry_count, max_retries
```

---

## 3. OCI 연동 구현 패턴

### OCI Client 팩토리
```python
class OCIClientFactory:
    # 테넌트별 싱글톤, Credential을 Vault에서 복호화
    def compute_client() -> ComputeClient
    def network_client() -> VirtualNetworkClient
    def monitoring_client() -> MonitoringClient
    def usage_client() -> UsageapiClient
```

### CRUD 패턴 (Compute 예시)
```python
async def list_instances(compartment_id):
    # oci.pagination.list_call_get_all_results() 사용
    # OCI 응답 → 표준화된 dict 변환 (_normalize_instance)

async def create_instance(params):
    # LaunchInstanceDetails 빌드 → 응답 Work Request ID 반환

# 에러 핸들링: OCI ServiceError → 앱 커스텀 예외 변환
# 404 → OCIResourceError, 429 → OCIQuotaError, 401 → OCIAuthError
```

### 비동기 작업 전략
```
단기 작업: Work Request 폴링 (Celery 재시도, 최대 10분)
  → 완료 시 Job 상태 업데이트 + WebSocket으로 UI 알림

장기 동기화: 주기적 배치 (Celery Beat)
  → 5분마다 전체 리소스 동기화
  → 1분마다 메트릭 수집
  → 매일 새벽 2시 비용 동기화
```

---

## 4. 개발 환경

### Docker Compose 서비스
```
db:      PostgreSQL 16
redis:   Redis 7 (캐시 + Celery 브로커)
api:     FastAPI (uvicorn --reload)
worker:  Celery Worker (concurrency=4)
beat:    Celery Beat (스케줄러)
web:     Next.js (npm run dev)
flower:  Celery 모니터링 UI (port 5555)
```

### 환경별 설정 (pydantic-settings)
```python
class Settings(BaseSettings):
    ENVIRONMENT: dev | staging | production
    DATABASE_URL, REDIS_URL
    SECRET_KEY, ACCESS_TOKEN_EXPIRE_MINUTES
    OCI_CREDENTIALS_ENCRYPTION_KEY  # Fernet 키
    CORS_ORIGINS, CELERY_BROKER_URL
```

### CI/CD (GitHub Actions)
```yaml
test-api:   ruff lint → mypy → pytest --cov
test-web:   type-check → eslint → vitest
deploy:     OCIR push → OKE kubectl set image (dev 브랜치)
```

---

## 5. 테스트 전략

### 단위 테스트 (OCI SDK 모킹)
```python
@pytest.fixture
def mock_oci_compute_client():
    with patch("oci.core.ComputeClient") as mock:
        # 인스턴스 목록, 상세, 생성 응답 모킹
        yield mock

# 커버리지 목표: 80% 이상
```

### API 통합 테스트
```python
# httpx.AsyncClient 사용
# DB 세션은 트랜잭션 롤백으로 격리
# 인증 헤더, 권한별 시나리오 테스트
```

### E2E 테스트 (Playwright)
```typescript
// 로그인 → 목록 조회 → 시작/중지 → WebSocket 상태 변경 확인
```

---

## 6. 기능별 구현 난이도 및 우선순위

| 기능 | 난이도 | 기간 |
|------|--------|------|
| 인증/RBAC | 중 | 1주 |
| 테넌트 관리 | 중 | 1주 |
| OCI Client 팩토리 | 중 | 3일 |
| Compute 관리 | 중 | 1주 |
| Network 관리 | 높 | 2주 |
| 모니터링 대시보드 | 높 | 2주 |
| 비용 분석 | 높 | 2주 |
| 알림 시스템 | 중 | 1주 |

### MVP 개발 12주 계획
```
1-3주:  기반 인프라 (DB 모델, 인증, 테넌트 관리, OCI 연결)
4-6주:  핵심 OCI 리소스 (Compute, Storage, 동기화, 대시보드)
7-9주:  모니터링, 알림, 비용, WebSocket 실시간
10-12주: 네트워크 관리, 비용 분석, E2E 테스트, OKE 배포
```

### 코드 품질 도구
```toml
[tool.ruff]           # 린팅 + 포맷팅
[tool.mypy]           # strict 타입 체크
[tool.pytest]         # asyncio_mode=auto, cov-fail-under=80
```
