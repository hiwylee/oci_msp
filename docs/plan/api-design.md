# OCI MSP 관리 플랫폼 - REST API 설계서

> 작성: REST API 아키텍처 설계
> 날짜: 2026-03-21
> 버전: 1.0
> 상태: 확정

---

## 목차

1. [API 설계 원칙](#1-api-설계-원칙)
2. [공통 Pydantic 스키마](#2-공통-pydantic-스키마)
3. [인증/인가 API](#3-인증인가-api)
4. [테넌시 관리 API](#4-테넌시-관리-api)
5. [리소스 관리 API](#5-리소스-관리-api)
6. [모니터링 & 알람 API](#6-모니터링--알람-api)
7. [Incident 관리 API](#7-incident-관리-api)
8. [비용 관리 API](#8-비용-관리-api)
9. [작업/감사 API](#9-작업감사-api)
10. [WebSocket API](#10-websocket-api)
11. [FastAPI 의존성 주입](#11-fastapi-의존성-주입)
12. [API 보안](#12-api-보안)

---

## 1. API 설계 원칙

### 1.1 RESTful 네이밍 컨벤션

| 규칙 | 올바른 예 | 잘못된 예 |
|------|-----------|-----------|
| 복수 명사 사용 | `/instances` | `/instance` |
| 케밥케이스 | `/alert-rules` | `/alertRules`, `/alert_rules` |
| 동사 금지 (행위 제외) | `/instances/{id}/actions` | `/startInstance` |
| 계층 구조 최대 3단계 | `/incidents/{id}/timeline` | `/a/b/c/d/e` |
| 버전 prefix | `/api/v1/` | `/api/` |

### 1.2 URL 구조 (테넌시 컨텍스트)

```
# Super Admin: path param으로 테넌트 지정 (전체 테넌트 관리)
GET  /api/v1/tenants/{tenant_id}/summary
GET  /api/v1/tenants/{tenant_id}/compute/instances

# 일반 사용자 (Tenant Admin / Operator / Viewer): X-Tenant-ID 헤더
GET  /api/v1/compute/instances
Headers: X-Tenant-ID: ten_abc123

# Super Admin이 자신의 컨텍스트에서 전체 조회
GET  /api/v1/compute/instances          # tenant_id 쿼리 파라미터로 필터
GET  /api/v1/compute/instances?tenant_id=ten_abc123
```

### 1.3 HTTP 메서드 사용 정책

| 메서드 | 의미 | 멱등성 | 성공 응답 코드 |
|--------|------|--------|---------------|
| `GET` | 리소스 조회 | O | 200 OK |
| `POST` | 리소스 생성 / 비멱등 행위 | X | 201 Created / 202 Accepted |
| `PUT` | 리소스 전체 교체 | O | 200 OK |
| `PATCH` | 리소스 부분 수정 | X | 200 OK |
| `DELETE` | 리소스 삭제 | O | 204 No Content |

**행위 엔드포인트 (POST /resource/{id}/actions)**:
```
POST /api/v1/compute/instances/{instance_id}/actions
Body: {"action": "start" | "stop" | "restart"}
Response: 202 Accepted + JobResponse
```

**비동기 작업 처리 패턴**:
```
1. 클라이언트 → POST /actions → 202 + {job_id: "job_xxx"}
2. 클라이언트 → GET /api/v1/jobs/{job_id} → {status: "running", progress: 45}
3. 완료 → WebSocket 푸시 또는 폴링으로 확인
```

### 1.4 페이지네이션 전략

**Cursor-based (기본 - 실시간 데이터, 대용량 목록)**:
```json
{
  "data": [...],
  "pagination": {
    "cursor": "eyJpZCI6MTIzfQ==",
    "has_next": true,
    "has_prev": false,
    "limit": 20
  }
}
```
쿼리 파라미터: `?cursor=eyJ...&limit=20`

**Offset-based (관리 목록 - 페이지 점프 필요한 경우)**:
```json
{
  "data": [...],
  "pagination": {
    "total": 1523,
    "page": 3,
    "page_size": 20,
    "total_pages": 77
  }
}
```
쿼리 파라미터: `?page=3&page_size=20`

### 1.5 에러 응답 형식 표준

**HTTP 상태 코드 매핑**:

| 코드 | 상황 |
|------|------|
| 400 | 요청 형식 오류, 유효성 검사 실패 |
| 401 | 인증 토큰 없음 / 만료 |
| 403 | 권한 부족 (인증은 됐으나 권한 없음) |
| 404 | 리소스 없음 |
| 409 | 충돌 (중복 생성 등) |
| 422 | Pydantic 유효성 검사 실패 |
| 429 | Rate Limit 초과 |
| 503 | OCI API 연동 실패 / 서비스 불가 |

**에러 코드 체계**:

```
{도메인}_{에러유형}_{세부}

AUTH_001  인증 토큰 없음
AUTH_002  토큰 만료
AUTH_003  토큰 서명 오류
AUTH_004  MFA 필요
AUTH_005  MFA 코드 오류
AUTH_006  계정 잠금

TENANT_001  테넌트 없음
TENANT_002  테넌트 비활성
TENANT_003  OCI 연결 실패
TENANT_004  온보딩 미완료

RESOURCE_001  리소스 없음
RESOURCE_002  리소스 상태 불가
RESOURCE_003  OCI API 오류

PERM_001  테넌트 접근 권한 없음
PERM_002  역할 권한 부족
PERM_003  크로스 테넌트 접근 차단

RATE_001  분당 요청 초과
RATE_002  일일 요청 초과

VALID_001  필수 필드 누락
VALID_002  형식 오류
VALID_003  범위 초과
```

**에러 응답 예시**:
```json
{
  "error": {
    "code": "AUTH_002",
    "message": "Access token has expired",
    "detail": "Token expired at 2026-03-21T10:00:00Z. Please refresh.",
    "request_id": "req_7f3a2b1c",
    "timestamp": "2026-03-21T10:15:00Z"
  }
}
```

---

## 2. 공통 Pydantic 스키마

```python
# app/schemas/common.py

from __future__ import annotations
from typing import Generic, TypeVar, Optional, Any, List
from pydantic import BaseModel, Field
from datetime import datetime
from enum import Enum

T = TypeVar("T")


# ─────────────────────────────────────────────────────────────
# 페이지네이션
# ─────────────────────────────────────────────────────────────

class CursorPagination(BaseModel):
    cursor: Optional[str] = Field(None, description="다음 페이지 커서 (Base64 인코딩)")
    has_next: bool
    has_prev: bool
    limit: int = Field(ge=1, le=100)


class OffsetPagination(BaseModel):
    total: int
    page: int = Field(ge=1)
    page_size: int = Field(ge=1, le=100)
    total_pages: int


class PaginatedResponse(BaseModel, Generic[T]):
    data: List[T]
    pagination: CursorPagination | OffsetPagination

    model_config = {"arbitrary_types_allowed": True}


# ─────────────────────────────────────────────────────────────
# 에러 응답
# ─────────────────────────────────────────────────────────────

class ErrorDetail(BaseModel):
    code: str = Field(description="에러 코드 (예: AUTH_002)")
    message: str = Field(description="사람이 읽을 수 있는 오류 메시지")
    detail: Optional[str] = Field(None, description="기술적 세부사항")
    request_id: str = Field(description="추적용 요청 ID")
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    fields: Optional[dict[str, List[str]]] = Field(
        None, description="필드별 유효성 검사 오류"
    )


class ErrorResponse(BaseModel):
    error: ErrorDetail


# ─────────────────────────────────────────────────────────────
# 비동기 Job
# ─────────────────────────────────────────────────────────────

class JobStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCESS = "success"
    FAILED = "failed"
    CANCELLED = "cancelled"


class JobResponse(BaseModel):
    job_id: str = Field(description="작업 ID (예: job_7f3a2b1c)")
    status: JobStatus
    progress: int = Field(ge=0, le=100, description="진행률 0-100")
    message: Optional[str] = Field(None, description="현재 단계 메시지")
    result: Optional[Any] = Field(None, description="완료 시 결과 데이터")
    error: Optional[str] = Field(None, description="실패 시 오류 메시지")
    created_at: datetime
    updated_at: datetime
    completed_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


# ─────────────────────────────────────────────────────────────
# Health Check
# ─────────────────────────────────────────────────────────────

class ComponentHealth(BaseModel):
    status: str = Field(description="healthy | degraded | unhealthy")
    latency_ms: Optional[float] = None
    message: Optional[str] = None


class HealthResponse(BaseModel):
    status: str = Field(description="healthy | degraded | unhealthy")
    version: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    components: dict[str, ComponentHealth] = Field(
        description="postgresql, redis, oci_api 각 컴포넌트 상태"
    )


# ─────────────────────────────────────────────────────────────
# 공통 필드
# ─────────────────────────────────────────────────────────────

class TimeRange(BaseModel):
    start: datetime
    end: datetime

    def validate_range(self) -> None:
        if self.end <= self.start:
            raise ValueError("end must be after start")


class SortOrder(str, Enum):
    ASC = "asc"
    DESC = "desc"
```

---

## 3. 인증/인가 API

### 3.1 스키마 정의

```python
# app/schemas/auth.py

from pydantic import BaseModel, EmailStr, Field
from typing import Optional
from datetime import datetime
from enum import Enum


class UserRole(str, Enum):
    SUPER_ADMIN = "super_admin"
    TENANT_ADMIN = "tenant_admin"
    OPERATOR = "operator"
    VIEWER = "viewer"


# ── 로그인 ──────────────────────────────────────────────────

class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8)
    mfa_code: Optional[str] = Field(None, pattern=r"^\d{6}$")


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = Field(description="access_token 만료 초 (900 = 15분)")


class LoginResponse(BaseModel):
    user: "UserMe"
    tokens: TokenPair
    mfa_required: bool = False


# ── Refresh ─────────────────────────────────────────────────

class RefreshRequest(BaseModel):
    refresh_token: str


# ── MFA ─────────────────────────────────────────────────────

class MFASetupResponse(BaseModel):
    secret: str = Field(description="TOTP secret key (Base32)")
    qr_code_uri: str = Field(description="otpauth:// URI for QR 생성")
    backup_codes: list[str] = Field(description="일회용 백업 코드 8개")


class MFAVerifyRequest(BaseModel):
    code: str = Field(pattern=r"^\d{6}$")


class MFAVerifyResponse(BaseModel):
    verified: bool
    backup_codes_remaining: int


# ── 현재 사용자 ─────────────────────────────────────────────

class TenantRole(BaseModel):
    tenant_id: str
    tenant_name: str
    role: UserRole


class UserMe(BaseModel):
    id: str
    email: EmailStr
    name: str
    is_super_admin: bool
    mfa_enabled: bool
    tenant_roles: list[TenantRole]
    last_login_at: Optional[datetime]
    created_at: datetime

    model_config = {"from_attributes": True}
```

### 3.2 라우터 구현

```python
# app/routers/auth.py

from fastapi import APIRouter, Depends, HTTPException, status, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.auth import (
    LoginRequest, LoginResponse, RefreshRequest, TokenPair,
    MFASetupResponse, MFAVerifyRequest, MFAVerifyResponse, UserMe
)
from app.schemas.common import ErrorResponse
from app.dependencies import get_db, get_current_user
from app.services.auth import AuthService

router = APIRouter(prefix="/api/v1/auth", tags=["Authentication"])
security = HTTPBearer()


@router.post(
    "/login",
    response_model=LoginResponse,
    responses={
        401: {"model": ErrorResponse, "description": "자격증명 오류"},
        423: {"model": ErrorResponse, "description": "계정 잠금"},
    },
    summary="로그인 (JWT 발급)",
)
async def login(
    body: LoginRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> LoginResponse:
    """
    이메일/패스워드로 로그인 후 JWT Access/Refresh 토큰 발급.

    - MFA 미설정 사용자: 즉시 토큰 반환
    - MFA 설정 사용자: mfa_required=true, mfa_code 없으면 임시 토큰 반환
    - 5회 실패 시 15분 계정 잠금 (AUTH_006)
    """
    svc = AuthService(db)
    return await svc.login(body, ip=request.client.host)


@router.post(
    "/refresh",
    response_model=TokenPair,
    responses={
        401: {"model": ErrorResponse, "description": "Refresh 토큰 유효하지 않음"},
    },
    summary="Access Token 갱신 (Refresh Token Rotation)",
)
async def refresh_token(
    body: RefreshRequest,
    db: AsyncSession = Depends(get_db),
) -> TokenPair:
    """
    Refresh Token으로 새 Access + Refresh 토큰 쌍 발급.
    기존 Refresh Token은 즉시 무효화 (Rotation).
    """
    svc = AuthService(db)
    return await svc.refresh(body.refresh_token)


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="로그아웃 (토큰 블랙리스트)",
)
async def logout(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    current_user: UserMe = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """
    Access Token을 Redis 블랙리스트에 등록, 모든 Refresh Token 무효화.
    """
    svc = AuthService(db)
    await svc.logout(
        user_id=current_user.id,
        access_token=credentials.credentials,
    )


@router.post(
    "/mfa/setup",
    response_model=MFASetupResponse,
    summary="MFA TOTP 설정 초기화",
)
async def setup_mfa(
    current_user: UserMe = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> MFASetupResponse:
    """
    TOTP Secret 생성 및 QR 코드 URI 반환.
    /mfa/verify로 검증 완료 후 실제 활성화.
    """
    svc = AuthService(db)
    return await svc.setup_mfa(current_user.id)


@router.post(
    "/mfa/verify",
    response_model=MFAVerifyResponse,
    summary="MFA 코드 검증 및 활성화",
)
async def verify_mfa(
    body: MFAVerifyRequest,
    current_user: UserMe = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> MFAVerifyResponse:
    svc = AuthService(db)
    return await svc.verify_mfa(current_user.id, body.code)


@router.get(
    "/me",
    response_model=UserMe,
    summary="현재 로그인 사용자 정보",
)
async def get_me(
    current_user: UserMe = Depends(get_current_user),
) -> UserMe:
    return current_user
```

---

## 4. 테넌시 관리 API

### 4.1 스키마 정의

```python
# app/schemas/tenant.py

from pydantic import BaseModel, Field, HttpUrl
from typing import Optional, Literal
from datetime import datetime
from enum import Enum


class TenantStatus(str, Enum):
    onboarding = "onboarding"   # 온보딩 진행 중
    active = "active"           # 정상 운영
    suspended = "suspended"     # 일시 정지 (미납, 정책 위반)
    offboarding = "offboarding" # 해지 진행 중
    terminated = "terminated"   # 완전 해지 (데이터 보존 기간 내)


class OCIRegion(str, Enum):
    AP_SEOUL_1 = "ap-seoul-1"
    AP_CHUNCHEON_1 = "ap-chuncheon-1"
    US_ASHBURN_1 = "us-ashburn-1"
    EU_FRANKFURT_1 = "eu-frankfurt-1"


# ── 테넌트 CRUD ─────────────────────────────────────────────

class TenantCreate(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    display_name: str = Field(min_length=2, max_length=200)
    contact_email: str
    contact_name: str
    contract_start: datetime
    contract_end: Optional[datetime] = None
    sla_tier: Literal["basic", "standard", "premium"] = "standard"
    primary_region: OCIRegion = OCIRegion.AP_SEOUL_1


class TenantUpdate(BaseModel):
    display_name: Optional[str] = Field(None, max_length=200)
    contact_email: Optional[str] = None
    contact_name: Optional[str] = None
    contract_end: Optional[datetime] = None
    sla_tier: Optional[Literal["basic", "standard", "premium"]] = None
    status: Optional[TenantStatus] = None


class TenantResponse(BaseModel):
    id: str
    name: str
    display_name: str
    status: TenantStatus
    contact_email: str
    contact_name: str
    sla_tier: str
    primary_region: str
    onboarding_completed: bool
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


# ── 온보딩 (5단계 위저드) ──────────────────────────────────

class OnboardStep1(BaseModel):
    """Step 1: OCI 테넌시 기본 정보"""
    oci_tenancy_id: str = Field(description="OCI Tenancy OCID")
    oci_tenancy_name: str
    home_region: OCIRegion


class OnboardStep2(BaseModel):
    """Step 2: API Key 자격증명"""
    user_ocid: str = Field(description="OCI User OCID")
    fingerprint: str = Field(pattern=r"^([0-9a-f]{2}:){15}[0-9a-f]{2}$")
    private_key_pem: str = Field(description="RSA Private Key PEM (Vault 저장됨)")


class OnboardStep3(BaseModel):
    """Step 3: Compartment 범위 설정"""
    root_compartment_id: str
    managed_compartment_ids: list[str] = Field(
        description="관리할 Compartment OCID 목록 (빈 리스트 = 전체)"
    )
    excluded_compartment_ids: list[str] = Field(default_factory=list)


class OnboardStep4(BaseModel):
    """Step 4: 모니터링 설정"""
    alert_email: str
    alert_slack_webhook: Optional[str] = None
    monitoring_interval_minutes: int = Field(default=5, ge=1, le=60)
    cost_alert_threshold_usd: Optional[float] = Field(None, gt=0)


class OnboardStep5(BaseModel):
    """Step 5: SLA 및 유지보수 창 확인"""
    sla_response_time_minutes: int = Field(default=60)
    maintenance_window_day: Literal["mon","tue","wed","thu","fri","sat","sun"] = "sun"
    maintenance_window_hour_utc: int = Field(ge=0, le=23, default=2)
    confirm_data_processing_agreement: bool


class OnboardRequest(BaseModel):
    step: Literal[1, 2, 3, 4, 5]
    data: OnboardStep1 | OnboardStep2 | OnboardStep3 | OnboardStep4 | OnboardStep5


class OnboardResponse(BaseModel):
    tenant_id: str
    step: int
    total_steps: int = 5
    completed: bool
    next_step: Optional[int]
    message: str
    job_id: Optional[str] = Field(None, description="Step 2 완료 시 검증 Job ID")


# ── OCI 연결 검증 ────────────────────────────────────────────

class VerifyResponse(BaseModel):
    success: bool
    tenancy_name: Optional[str] = None
    regions_accessible: list[str] = Field(default_factory=list)
    compartments_found: int = 0
    iam_policies_ok: bool = False
    errors: list[str] = Field(default_factory=list)
    latency_ms: float


# ── 테넌트 요약 ──────────────────────────────────────────────

class ResourceCount(BaseModel):
    compute_instances: int
    vcns: int
    block_volumes: int
    databases: int
    object_storage_buckets: int


class TenantSummary(BaseModel):
    tenant: TenantResponse
    resource_counts: ResourceCount
    active_incidents: int
    open_alerts: int
    monthly_cost_usd: float
    budget_utilization_pct: Optional[float]
    last_sync_at: Optional[datetime]
    oci_connection_status: Literal["connected", "degraded", "disconnected"]
```

> ⚠️ **보안 주의**: `OnboardStep2`의 `private_key_pem` 필드는 Private Key PEM을 API 요청 본문으로 직접 전송합니다.
> - HTTPS(TLS 1.3) 강제 적용 필수
> - API Gateway 로그에서 request body 로깅 비활성화 필수
> - 권장: Cross-Tenancy Resource Principal 방식 우선 사용 (private_key_pem 불필요)
> - MVP에서는 API Key 방식도 지원하되, 온보딩 UI에서 Cross-Tenancy 방식을 기본 선택으로 표시

### 4.2 라우터 구현

```python
# app/routers/tenants.py

from fastapi import APIRouter, Depends, Query, Path, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.tenant import (
    TenantCreate, TenantUpdate, TenantResponse,
    OnboardRequest, OnboardResponse,
    VerifyResponse, TenantSummary,
)
from app.schemas.common import PaginatedResponse, OffsetPagination
from app.dependencies import get_db, get_current_user, require_role
from app.schemas.auth import UserMe, UserRole
from app.services.tenant import TenantService

router = APIRouter(prefix="/api/v1/tenants", tags=["Tenants"])


@router.get(
    "",
    response_model=PaginatedResponse[TenantResponse],
    summary="테넌트 목록 조회 (Super Admin 전용)",
)
async def list_tenants(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    status: str = Query(None, description="active | suspended | onboarding"),
    search: str = Query(None, description="이름/이메일 검색"),
    current_user: UserMe = Depends(require_role(UserRole.SUPER_ADMIN)),
    db: AsyncSession = Depends(get_db),
) -> PaginatedResponse[TenantResponse]:
    svc = TenantService(db)
    return await svc.list_tenants(page, page_size, status, search)


@router.post(
    "",
    response_model=TenantResponse,
    status_code=status.HTTP_201_CREATED,
    summary="신규 테넌트 생성 (Super Admin 전용)",
)
async def create_tenant(
    body: TenantCreate,
    current_user: UserMe = Depends(require_role(UserRole.SUPER_ADMIN)),
    db: AsyncSession = Depends(get_db),
) -> TenantResponse:
    svc = TenantService(db)
    return await svc.create_tenant(body, created_by=current_user.id)


@router.get(
    "/{tenant_id}",
    response_model=TenantResponse,
    summary="테넌트 상세 조회",
)
async def get_tenant(
    tenant_id: str = Path(description="테넌트 ID"),
    current_user: UserMe = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> TenantResponse:
    svc = TenantService(db)
    return await svc.get_tenant(tenant_id, current_user)


@router.put(
    "/{tenant_id}",
    response_model=TenantResponse,
    summary="테넌트 정보 수정",
)
async def update_tenant(
    tenant_id: str,
    body: TenantUpdate,
    current_user: UserMe = Depends(require_role(UserRole.TENANT_ADMIN)),
    db: AsyncSession = Depends(get_db),
) -> TenantResponse:
    svc = TenantService(db)
    return await svc.update_tenant(tenant_id, body, current_user)


@router.delete(
    "/{tenant_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="테넌트 삭제 (Super Admin 전용)",
)
async def delete_tenant(
    tenant_id: str,
    current_user: UserMe = Depends(require_role(UserRole.SUPER_ADMIN)),
    db: AsyncSession = Depends(get_db),
) -> None:
    svc = TenantService(db)
    await svc.delete_tenant(tenant_id)


@router.post(
    "/{tenant_id}/onboard",
    response_model=OnboardResponse,
    summary="온보딩 위저드 단계별 처리",
)
async def onboard_tenant(
    tenant_id: str,
    body: OnboardRequest,
    current_user: UserMe = Depends(require_role(UserRole.SUPER_ADMIN)),
    db: AsyncSession = Depends(get_db),
) -> OnboardResponse:
    """
    5단계 온보딩 위저드. 각 단계별 데이터를 순서대로 전송.

    - Step 1: OCI 테넌시 기본 정보 등록
    - Step 2: API Key 등록 → OCI Vault 저장 → 검증 Job 시작
    - Step 3: Compartment 범위 설정
    - Step 4: 모니터링/알람 설정
    - Step 5: SLA 확인 및 온보딩 완료
    """
    svc = TenantService(db)
    return await svc.process_onboard_step(tenant_id, body, current_user.id)


@router.post(
    "/{tenant_id}/verify",
    response_model=VerifyResponse,
    summary="OCI 연결 상태 검증",
)
async def verify_tenant_connection(
    tenant_id: str,
    current_user: UserMe = Depends(require_role(UserRole.TENANT_ADMIN)),
    db: AsyncSession = Depends(get_db),
) -> VerifyResponse:
    """OCI API Key로 실제 연결 테스트 및 IAM 권한 검증."""
    svc = TenantService(db)
    return await svc.verify_oci_connection(tenant_id)


@router.get(
    "/{tenant_id}/summary",
    response_model=TenantSummary,
    summary="테넌트 대시보드 요약",
)
async def get_tenant_summary(
    tenant_id: str,
    current_user: UserMe = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> TenantSummary:
    svc = TenantService(db)
    return await svc.get_summary(tenant_id, current_user)
```

---

## 5. 리소스 관리 API

### 5.1 스키마 정의

```python
# app/schemas/resources.py

from pydantic import BaseModel, Field
from typing import Optional, Literal
from datetime import datetime
from enum import Enum


class InstanceStatus(str, Enum):
    RUNNING = "RUNNING"
    STOPPED = "STOPPED"
    STARTING = "STARTING"
    STOPPING = "STOPPING"
    TERMINATED = "TERMINATED"
    PROVISIONING = "PROVISIONING"


class InstanceShape(BaseModel):
    name: str
    ocpus: float
    memory_gb: float
    is_flex: bool


class InstanceSummary(BaseModel):
    id: str
    oci_id: str = Field(description="OCI OCID")
    tenant_id: str
    display_name: str
    status: InstanceStatus
    shape: InstanceShape
    region: str
    availability_domain: str
    compartment_id: str
    private_ip: Optional[str]
    public_ip: Optional[str]
    image_id: str
    time_created: datetime
    last_synced_at: datetime

    model_config = {"from_attributes": True}


class InstanceDetail(InstanceSummary):
    fault_domain: str
    subnet_id: str
    vnics: list[dict]
    volumes: list[dict]
    tags: dict[str, str] = Field(default_factory=dict)
    metadata: dict[str, str] = Field(default_factory=dict)


class InstanceAction(BaseModel):
    action: Literal["start", "stop", "restart"]


class VCNSummary(BaseModel):
    id: str
    oci_id: str
    tenant_id: str
    display_name: str
    cidr_block: str
    region: str
    dns_label: Optional[str]
    lifecycle_state: str
    time_created: datetime


class SubnetSummary(BaseModel):
    id: str
    oci_id: str
    vcn_id: str
    tenant_id: str
    display_name: str
    cidr_block: str
    availability_domain: Optional[str]
    is_private: bool
    lifecycle_state: str


class BlockVolumeSummary(BaseModel):
    id: str
    oci_id: str
    tenant_id: str
    display_name: str
    size_gb: int
    vpus_per_gb: int
    lifecycle_state: str
    is_attached: bool
    attached_instance_id: Optional[str]
    region: str
    time_created: datetime


class BucketSummary(BaseModel):
    id: str
    tenant_id: str
    name: str
    namespace: str
    compartment_id: str
    storage_tier: Literal["Standard", "Archive", "IntelligentTiering"]
    versioning: str
    object_count: Optional[int]
    size_bytes: Optional[int]
    time_created: datetime


class AutonomousDBSummary(BaseModel):
    id: str
    oci_id: str
    tenant_id: str
    display_name: str
    db_name: str
    workload_type: Literal["OLTP", "DW", "AJD", "APEX"]
    lifecycle_state: str
    cpu_core_count: int
    data_storage_size_gb: int
    is_auto_scaling: bool
    region: str
    time_created: datetime


class DBSystemSummary(BaseModel):
    id: str
    oci_id: str
    tenant_id: str
    display_name: str
    shape: str
    lifecycle_state: str
    node_count: int
    database_edition: str
    region: str
    time_created: datetime
```

### 5.2 Compute 라우터

```python
# app/routers/compute.py

from fastapi import APIRouter, Depends, Query, Path, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.resources import InstanceSummary, InstanceDetail, InstanceAction
from app.schemas.common import PaginatedResponse, JobResponse
from app.dependencies import get_db, get_current_user, get_tenant_context
from app.schemas.auth import UserMe, UserRole
from app.dependencies import require_role
from app.services.compute import ComputeService

router = APIRouter(prefix="/api/v1/compute", tags=["Compute"])


@router.get(
    "/instances",
    response_model=PaginatedResponse[InstanceSummary],
    summary="컴퓨트 인스턴스 목록",
)
async def list_instances(
    # 필터
    tenant_id: Optional[str] = Query(None, description="Super Admin 전용 필터"),
    region: Optional[str] = Query(None, description="예: ap-seoul-1"),
    status: Optional[str] = Query(None, description="RUNNING | STOPPED | ..."),
    search: Optional[str] = Query(None, description="인스턴스명 검색"),
    compartment_id: Optional[str] = Query(None),
    # 페이지네이션
    cursor: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=100),
    # 정렬
    sort_by: str = Query("display_name", description="display_name | time_created | status"),
    sort_order: str = Query("asc", description="asc | desc"),
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
) -> PaginatedResponse[InstanceSummary]:
    """
    테넌트 컨텍스트 내 OCI 컴퓨트 인스턴스 목록.
    - 일반 사용자: X-Tenant-ID 헤더 기준 자동 필터
    - Super Admin: tenant_id 쿼리 파라미터로 특정 테넌트 조회 또는 전체 조회
    """
    svc = ComputeService(db)
    return await svc.list_instances(
        tenant_ctx=tenant_ctx,
        region=region,
        status=status,
        search=search,
        compartment_id=compartment_id,
        cursor=cursor,
        limit=limit,
        sort_by=sort_by,
        sort_order=sort_order,
    )


@router.get(
    "/instances/{instance_id}",
    response_model=InstanceDetail,
    summary="컴퓨트 인스턴스 상세",
)
async def get_instance(
    instance_id: str = Path(description="인스턴스 내부 ID"),
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
) -> InstanceDetail:
    svc = ComputeService(db)
    return await svc.get_instance(instance_id, tenant_ctx)


@router.post(
    "/instances/{instance_id}/actions",
    response_model=JobResponse,
    status_code=status.HTTP_202_ACCEPTED,
    summary="인스턴스 전원 제어 (비동기)",
)
async def instance_action(
    instance_id: str,
    body: InstanceAction,
    current_user: UserMe = Depends(require_role(UserRole.OPERATOR)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
) -> JobResponse:
    """
    start / stop / restart 비동기 실행.
    Celery 작업으로 위임 후 job_id 즉시 반환.
    진행 상황은 GET /jobs/{job_id} 또는 WebSocket으로 확인.
    """
    svc = ComputeService(db)
    return await svc.execute_action(instance_id, body.action, tenant_ctx, current_user.id)
```

### 5.3 Network / Storage / Database 라우터

```python
# app/routers/network.py

from fastapi import APIRouter, Depends, Query
from app.schemas.resources import VCNSummary, SubnetSummary
from app.schemas.common import PaginatedResponse
from app.dependencies import get_db, get_current_user, get_tenant_context

router = APIRouter(prefix="/api/v1/network", tags=["Network"])


@router.get("/vcns", response_model=PaginatedResponse[VCNSummary])
async def list_vcns(
    region: Optional[str] = Query(None),
    cursor: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=100),
    current_user = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db = Depends(get_db),
):
    from app.services.network import NetworkService
    return await NetworkService(db).list_vcns(tenant_ctx, region, cursor, limit)


@router.get("/subnets", response_model=PaginatedResponse[SubnetSummary])
async def list_subnets(
    vcn_id: Optional[str] = Query(None),
    region: Optional[str] = Query(None),
    cursor: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=100),
    current_user = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db = Depends(get_db),
):
    from app.services.network import NetworkService
    return await NetworkService(db).list_subnets(tenant_ctx, vcn_id, region, cursor, limit)


# app/routers/storage.py

router_storage = APIRouter(prefix="/api/v1/storage", tags=["Storage"])


@router_storage.get("/block-volumes", response_model=PaginatedResponse[BlockVolumeSummary])
async def list_block_volumes(
    region: Optional[str] = Query(None),
    is_attached: Optional[bool] = Query(None),
    cursor: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=100),
    current_user = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db = Depends(get_db),
):
    from app.services.storage import StorageService
    return await StorageService(db).list_block_volumes(tenant_ctx, region, is_attached, cursor, limit)


@router_storage.get("/buckets", response_model=PaginatedResponse[BucketSummary])
async def list_buckets(
    region: Optional[str] = Query(None),
    storage_tier: Optional[str] = Query(None),
    cursor: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=100),
    current_user = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db = Depends(get_db),
):
    from app.services.storage import StorageService
    return await StorageService(db).list_buckets(tenant_ctx, region, storage_tier, cursor, limit)


# app/routers/database.py

router_db = APIRouter(prefix="/api/v1/databases", tags=["Database"])


@router_db.get("/autonomous", response_model=PaginatedResponse[AutonomousDBSummary])
async def list_autonomous_dbs(
    region: Optional[str] = Query(None),
    workload_type: Optional[str] = Query(None),
    lifecycle_state: Optional[str] = Query(None),
    cursor: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=100),
    current_user = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db = Depends(get_db),
):
    from app.services.database import DatabaseService
    return await DatabaseService(db).list_autonomous(tenant_ctx, region, workload_type, cursor, limit)


@router_db.get("/db-systems", response_model=PaginatedResponse[DBSystemSummary])
async def list_db_systems(
    region: Optional[str] = Query(None),
    lifecycle_state: Optional[str] = Query(None),
    cursor: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=100),
    current_user = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db = Depends(get_db),
):
    from app.services.database import DatabaseService
    return await DatabaseService(db).list_db_systems(tenant_ctx, region, lifecycle_state, cursor, limit)
```

---

## 6. 모니터링 & 알람 API

### 6.1 스키마 정의

```python
# app/schemas/monitoring.py

from pydantic import BaseModel, Field
from typing import Optional, Literal, List
from datetime import datetime
from enum import Enum


class Severity(str, Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class AlertStatus(str, Enum):
    FIRING = "firing"
    ACKNOWLEDGED = "acknowledged"
    SILENCED = "silenced"
    RESOLVED = "resolved"


# ── 메트릭 조회 ──────────────────────────────────────────────

class MetricPoint(BaseModel):
    timestamp: datetime
    value: float


class MetricSeries(BaseModel):
    metric_name: str
    resource_id: str
    resource_type: str
    unit: str
    dimensions: dict[str, str]
    data_points: List[MetricPoint]


class MetricsRequest(BaseModel):
    resource_ids: List[str] = Field(description="조회할 리소스 ID 목록")
    metric_names: List[str] = Field(
        description="예: CpuUtilization, MemoryUtilization, NetworksBytesIn"
    )
    start_time: datetime
    end_time: datetime
    interval: Literal["1m", "5m", "15m", "1h", "1d"] = "5m"
    statistics: List[Literal["avg", "max", "min", "sum"]] = ["avg"]


class MetricsResponse(BaseModel):
    series: List[MetricSeries]
    query_time_ms: float


# ── 알람 규칙 ────────────────────────────────────────────────

class AlertCondition(BaseModel):
    metric_name: str
    operator: Literal["gt", "gte", "lt", "lte", "eq"]
    threshold: float
    unit: str
    evaluation_window_minutes: int = Field(ge=1, le=1440)
    consecutive_datapoints: int = Field(default=1, ge=1, le=10)


class AlertRuleCreate(BaseModel):
    name: str = Field(min_length=2, max_length=200)
    description: Optional[str] = None
    severity: Severity
    resource_type: Literal["instance", "vcn", "volume", "database", "bucket"]
    resource_filter: dict = Field(description="적용 대상 필터 (tags, compartment_id 등)")
    condition: AlertCondition
    notification_channels: List[str] = Field(description="알림 채널 ID 목록")
    is_enabled: bool = True


class AlertRuleResponse(AlertRuleCreate):
    id: str
    tenant_id: str
    created_by: str
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


# ── 알람 ─────────────────────────────────────────────────────

class AlertResponse(BaseModel):
    id: str
    rule_id: str
    rule_name: str
    tenant_id: str
    resource_id: str
    resource_name: str
    severity: Severity
    status: AlertStatus
    current_value: float
    threshold: float
    fired_at: datetime
    acknowledged_at: Optional[datetime]
    acknowledged_by: Optional[str]
    resolved_at: Optional[datetime]

    model_config = {"from_attributes": True}


class AcknowledgeRequest(BaseModel):
    note: Optional[str] = Field(None, max_length=500)


class SilenceRequest(BaseModel):
    duration_minutes: int = Field(ge=15, le=10080, description="최소 15분, 최대 7일")
    reason: str = Field(min_length=5, max_length=500)


# ── 유지보수 창 ──────────────────────────────────────────────

class MaintenanceWindowCreate(BaseModel):
    name: str
    description: Optional[str] = None
    start_time: datetime
    end_time: datetime
    suppress_alerts: bool = True
    resource_filter: Optional[dict] = None


class MaintenanceWindowResponse(MaintenanceWindowCreate):
    id: str
    tenant_id: str
    status: Literal["scheduled", "active", "completed", "cancelled"]
    created_by: str
    created_at: datetime

    model_config = {"from_attributes": True}
```

### 6.2 라우터 구현

```python
# app/routers/monitoring.py

from fastapi import APIRouter, Depends, Query, Path, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.monitoring import (
    MetricsRequest, MetricsResponse,
    AlertRuleCreate, AlertRuleResponse,
    AlertResponse, AcknowledgeRequest, SilenceRequest,
    MaintenanceWindowCreate, MaintenanceWindowResponse,
)
from app.schemas.common import PaginatedResponse, JobResponse
from app.dependencies import get_db, get_current_user, get_tenant_context, require_role
from app.schemas.auth import UserMe, UserRole

router = APIRouter(prefix="/api/v1", tags=["Monitoring"])


@router.get("/monitoring/metrics", response_model=MetricsResponse)
async def get_metrics(
    resource_ids: List[str] = Query(description="리소스 ID 목록"),
    metric_names: List[str] = Query(description="메트릭 이름 목록"),
    start_time: datetime = Query(),
    end_time: datetime = Query(),
    interval: str = Query("5m"),
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
) -> MetricsResponse:
    """OCI Monitoring 서비스에서 메트릭 시계열 조회."""
    from app.services.monitoring import MonitoringService
    return await MonitoringService(db).get_metrics(
        tenant_ctx, resource_ids, metric_names, start_time, end_time, interval
    )


# ── 알람 규칙 CRUD ────────────────────────────────────────────

@router.get("/alert-rules", response_model=PaginatedResponse[AlertRuleResponse])
async def list_alert_rules(
    is_enabled: Optional[bool] = Query(None),
    severity: Optional[str] = Query(None),
    cursor: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=100),
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.monitoring import MonitoringService
    return await MonitoringService(db).list_alert_rules(tenant_ctx, is_enabled, severity, cursor, limit)


@router.post("/alert-rules", response_model=AlertRuleResponse, status_code=201)
async def create_alert_rule(
    body: AlertRuleCreate,
    current_user: UserMe = Depends(require_role(UserRole.OPERATOR)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.monitoring import MonitoringService
    return await MonitoringService(db).create_alert_rule(body, tenant_ctx, current_user.id)


@router.put("/alert-rules/{rule_id}", response_model=AlertRuleResponse)
async def update_alert_rule(
    rule_id: str,
    body: AlertRuleCreate,
    current_user: UserMe = Depends(require_role(UserRole.OPERATOR)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.monitoring import MonitoringService
    return await MonitoringService(db).update_alert_rule(rule_id, body, tenant_ctx)


@router.delete("/alert-rules/{rule_id}", status_code=204)
async def delete_alert_rule(
    rule_id: str,
    current_user: UserMe = Depends(require_role(UserRole.OPERATOR)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.monitoring import MonitoringService
    await MonitoringService(db).delete_alert_rule(rule_id, tenant_ctx)


# ── 알람 목록/처리 ────────────────────────────────────────────

@router.get("/alerts", response_model=PaginatedResponse[AlertResponse])
async def list_alerts(
    status: Optional[str] = Query(None, description="firing | acknowledged | resolved"),
    severity: Optional[str] = Query(None, description="critical | high | medium | low"),
    tenant_id: Optional[str] = Query(None, description="Super Admin 전용"),
    resource_id: Optional[str] = Query(None),
    cursor: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=100),
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.monitoring import MonitoringService
    return await MonitoringService(db).list_alerts(
        tenant_ctx, status, severity, resource_id, cursor, limit
    )


@router.put("/alerts/{alert_id}/acknowledge", response_model=AlertResponse)
async def acknowledge_alert(
    alert_id: str,
    body: AcknowledgeRequest,
    current_user: UserMe = Depends(require_role(UserRole.OPERATOR)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.monitoring import MonitoringService
    return await MonitoringService(db).acknowledge_alert(
        alert_id, tenant_ctx, current_user.id, body.note
    )


@router.post("/alerts/{alert_id}/silence", response_model=AlertResponse)
async def silence_alert(
    alert_id: str,
    body: SilenceRequest,
    current_user: UserMe = Depends(require_role(UserRole.OPERATOR)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.monitoring import MonitoringService
    return await MonitoringService(db).silence_alert(
        alert_id, tenant_ctx, current_user.id, body.duration_minutes, body.reason
    )


# ── 유지보수 창 ──────────────────────────────────────────────

@router.get("/maintenance-windows", response_model=PaginatedResponse[MaintenanceWindowResponse])
async def list_maintenance_windows(
    status: Optional[str] = Query(None),
    cursor: Optional[str] = Query(None),
    limit: int = Query(20),
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.monitoring import MonitoringService
    return await MonitoringService(db).list_maintenance_windows(tenant_ctx, status, cursor, limit)


@router.post("/maintenance-windows", response_model=MaintenanceWindowResponse, status_code=201)
async def create_maintenance_window(
    body: MaintenanceWindowCreate,
    current_user: UserMe = Depends(require_role(UserRole.OPERATOR)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.monitoring import MonitoringService
    return await MonitoringService(db).create_maintenance_window(body, tenant_ctx, current_user.id)
```

---

## 7. Incident 관리 API

### 7.1 스키마 정의

```python
# app/schemas/incident.py

from pydantic import BaseModel, Field
from typing import Optional, Literal, List
from datetime import datetime
from enum import Enum


class IncidentStatus(str, Enum):
    OPEN = "open"
    INVESTIGATING = "investigating"
    IDENTIFIED = "identified"
    MONITORING = "monitoring"
    RESOLVED = "resolved"
    POST_MORTEM = "post_mortem"


class IncidentPriority(str, Enum):
    P1 = "P1"
    P2 = "P2"
    P3 = "P3"
    P4 = "P4"


class TimelineEventType(str, Enum):
    CREATED = "created"
    STATUS_CHANGED = "status_changed"
    ASSIGNED = "assigned"
    COMMENT = "comment"
    ALERT_LINKED = "alert_linked"
    ESCALATED = "escalated"
    RESOLVED = "resolved"


class IncidentCreate(BaseModel):
    title: str = Field(min_length=5, max_length=300)
    description: str = Field(min_length=10)
    priority: IncidentPriority
    affected_services: List[str] = Field(default_factory=list)
    affected_resource_ids: List[str] = Field(default_factory=list)
    linked_alert_ids: List[str] = Field(default_factory=list)


class IncidentUpdate(BaseModel):
    title: Optional[str] = Field(None, max_length=300)
    description: Optional[str] = None
    priority: Optional[IncidentPriority] = None
    status: Optional[IncidentStatus] = None
    affected_services: Optional[List[str]] = None


class IncidentResponse(BaseModel):
    id: str
    tenant_id: str
    title: str
    description: str
    status: IncidentStatus
    priority: IncidentPriority
    affected_services: List[str]
    affected_resource_ids: List[str]
    assigned_to: Optional[str]
    assignee_name: Optional[str]
    linked_alert_ids: List[str]
    created_by: str
    created_at: datetime
    updated_at: datetime
    resolved_at: Optional[datetime]
    duration_minutes: Optional[int]

    model_config = {"from_attributes": True}


class AssignRequest(BaseModel):
    assignee_user_id: str
    note: Optional[str] = None


class TimelineEntryCreate(BaseModel):
    event_type: TimelineEventType = TimelineEventType.COMMENT
    message: str = Field(min_length=1, max_length=2000)
    is_internal: bool = Field(default=False, description="내부 메모 여부")


class TimelineEntryResponse(TimelineEntryCreate):
    id: str
    incident_id: str
    author_id: str
    author_name: str
    created_at: datetime

    model_config = {"from_attributes": True}


class ResolveRequest(BaseModel):
    resolution_summary: str = Field(min_length=10, max_length=2000)
    root_cause_category: Literal[
        "infrastructure", "application", "network",
        "database", "human_error", "external", "unknown"
    ]
    trigger_rca: bool = Field(default=False, description="RCA 문서 작성 시작 여부")


class RCACreate(BaseModel):
    summary: str
    timeline: str = Field(description="사건 타임라인 마크다운")
    root_cause: str
    contributing_factors: List[str]
    impact_assessment: str
    corrective_actions: List[dict] = Field(
        description="[{action: str, owner: str, due_date: date, status: str}]"
    )
    lessons_learned: str
    prevention_measures: str


class RCAResponse(RCACreate):
    id: str
    incident_id: str
    status: Literal["draft", "review", "approved"]
    created_by: str
    approved_by: Optional[str]
    created_at: datetime
    approved_at: Optional[datetime]

    model_config = {"from_attributes": True}
```

### 7.2 라우터 구현

```python
# app/routers/incidents.py

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.incident import (
    IncidentCreate, IncidentUpdate, IncidentResponse,
    AssignRequest, TimelineEntryCreate, TimelineEntryResponse,
    ResolveRequest, RCACreate, RCAResponse,
)
from app.schemas.common import PaginatedResponse
from app.dependencies import get_db, get_current_user, get_tenant_context, require_role
from app.schemas.auth import UserMe, UserRole

router = APIRouter(prefix="/api/v1/incidents", tags=["Incidents"])


@router.get("", response_model=PaginatedResponse[IncidentResponse])
async def list_incidents(
    status: Optional[str] = Query(None),
    priority: Optional[str] = Query(None, description="P1 | P2 | P3 | P4"),
    assigned_to: Optional[str] = Query(None),
    tenant_id: Optional[str] = Query(None, description="Super Admin 전용"),
    search: Optional[str] = Query(None),
    cursor: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=100),
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.incident import IncidentService
    return await IncidentService(db).list_incidents(
        tenant_ctx, status, priority, assigned_to, search, cursor, limit
    )


@router.post("", response_model=IncidentResponse, status_code=201)
async def create_incident(
    body: IncidentCreate,
    current_user: UserMe = Depends(require_role(UserRole.OPERATOR)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.incident import IncidentService
    return await IncidentService(db).create_incident(body, tenant_ctx, current_user.id)


@router.get("/{incident_id}", response_model=IncidentResponse)
async def get_incident(
    incident_id: str,
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.incident import IncidentService
    return await IncidentService(db).get_incident(incident_id, tenant_ctx)


@router.put("/{incident_id}", response_model=IncidentResponse)
async def update_incident(
    incident_id: str,
    body: IncidentUpdate,
    current_user: UserMe = Depends(require_role(UserRole.OPERATOR)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.incident import IncidentService
    return await IncidentService(db).update_incident(incident_id, body, tenant_ctx)


@router.post("/{incident_id}/assign", response_model=IncidentResponse)
async def assign_incident(
    incident_id: str,
    body: AssignRequest,
    current_user: UserMe = Depends(require_role(UserRole.OPERATOR)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.incident import IncidentService
    return await IncidentService(db).assign_incident(
        incident_id, body, tenant_ctx, current_user.id
    )


@router.post("/{incident_id}/timeline", response_model=TimelineEntryResponse, status_code=201)
async def add_timeline_entry(
    incident_id: str,
    body: TimelineEntryCreate,
    current_user: UserMe = Depends(require_role(UserRole.OPERATOR)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.incident import IncidentService
    return await IncidentService(db).add_timeline_entry(
        incident_id, body, tenant_ctx, current_user.id
    )


@router.post("/{incident_id}/resolve", response_model=IncidentResponse)
async def resolve_incident(
    incident_id: str,
    body: ResolveRequest,
    current_user: UserMe = Depends(require_role(UserRole.OPERATOR)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.incident import IncidentService
    return await IncidentService(db).resolve_incident(
        incident_id, body, tenant_ctx, current_user.id
    )


@router.get("/{incident_id}/rca", response_model=RCAResponse)
async def get_rca(
    incident_id: str,
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.incident import IncidentService
    return await IncidentService(db).get_rca(incident_id, tenant_ctx)


@router.put("/{incident_id}/rca", response_model=RCAResponse)
async def upsert_rca(
    incident_id: str,
    body: RCACreate,
    current_user: UserMe = Depends(require_role(UserRole.OPERATOR)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.incident import IncidentService
    return await IncidentService(db).upsert_rca(incident_id, body, tenant_ctx, current_user.id)
```

---

## 8. 비용 관리 API

### 8.1 스키마 정의

```python
# app/schemas/cost.py

from pydantic import BaseModel, Field
from typing import Optional, Literal, List
from datetime import datetime, date
from enum import Enum


class CostSummaryResponse(BaseModel):
    tenant_id: str
    period_start: date
    period_end: date
    total_cost_usd: float
    currency: str = "USD"
    cost_by_region: dict[str, float]
    cost_by_service: dict[str, float]
    vs_previous_period_pct: float = Field(description="전월 대비 증감율 (%)")
    forecasted_month_end_usd: float


class CostByServiceItem(BaseModel):
    service_name: str
    cost_usd: float
    percentage: float
    resource_count: int
    vs_previous_pct: float


class CostByServiceResponse(BaseModel):
    tenant_id: str
    period_start: date
    period_end: date
    items: List[CostByServiceItem]
    total_usd: float


class CostByTenantItem(BaseModel):
    tenant_id: str
    tenant_name: str
    cost_usd: float
    percentage: float
    budget_utilization_pct: Optional[float]
    vs_previous_pct: float


class CostByTenantResponse(BaseModel):
    """Super Admin 전용: 전체 테넌트 비용 비교"""
    period_start: date
    period_end: date
    items: List[CostByTenantItem]
    total_usd: float


class CostTrendPoint(BaseModel):
    date: date
    cost_usd: float
    forecasted: bool = False


class CostTrendsResponse(BaseModel):
    tenant_id: Optional[str]
    granularity: Literal["daily", "weekly", "monthly"]
    data_points: List[CostTrendPoint]
    trend_direction: Literal["increasing", "decreasing", "stable"]
    avg_daily_usd: float


class CostAnomalyItem(BaseModel):
    id: str
    tenant_id: str
    service_name: str
    detected_at: datetime
    anomaly_date: date
    expected_cost_usd: float
    actual_cost_usd: float
    deviation_pct: float
    severity: Literal["high", "medium", "low"]
    status: Literal["open", "acknowledged", "resolved"]
    description: str


class CostAnomalyResponse(BaseModel):
    items: List[CostAnomalyItem]
    total: int


class BudgetCreate(BaseModel):
    name: str = Field(min_length=2, max_length=200)
    amount_usd: float = Field(gt=0)
    period: Literal["monthly", "quarterly", "annual"]
    alert_thresholds: List[int] = Field(
        default=[50, 80, 100],
        description="알람 발생 임계값 퍼센트 목록",
    )
    scope: Literal["tenant", "service", "compartment"] = "tenant"
    scope_value: Optional[str] = Field(None, description="service명 또는 compartment_id")


class BudgetResponse(BudgetCreate):
    id: str
    tenant_id: str
    current_spend_usd: float
    utilization_pct: float
    status: Literal["on_track", "at_risk", "exceeded"]
    period_start: date
    period_end: date
    created_at: datetime

    model_config = {"from_attributes": True}
```

### 8.2 라우터 구현

```python
# app/routers/costs.py

from fastapi import APIRouter, Depends, Query
from datetime import date
from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.cost import (
    CostSummaryResponse, CostByServiceResponse, CostByTenantResponse,
    CostTrendsResponse, CostAnomalyResponse, BudgetCreate, BudgetResponse,
)
from app.schemas.common import PaginatedResponse
from app.dependencies import get_db, get_current_user, get_tenant_context, require_role
from app.schemas.auth import UserMe, UserRole

router = APIRouter(prefix="/api/v1/costs", tags=["Costs"])
router_budget = APIRouter(prefix="/api/v1/budgets", tags=["Budgets"])


@router.get("/summary", response_model=CostSummaryResponse)
async def get_cost_summary(
    period_start: date = Query(description="조회 시작일 (YYYY-MM-DD)"),
    period_end: date = Query(description="조회 종료일 (YYYY-MM-DD)"),
    tenant_id: Optional[str] = Query(None, description="Super Admin: 특정 테넌트"),
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    """OCI Usage API 기반 테넌트 비용 요약."""
    from app.services.cost import CostService
    return await CostService(db).get_summary(tenant_ctx, period_start, period_end)


@router.get("/by-service", response_model=CostByServiceResponse)
async def get_cost_by_service(
    period_start: date = Query(),
    period_end: date = Query(),
    top_n: int = Query(default=10, ge=1, le=50, description="상위 N개 서비스"),
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.cost import CostService
    return await CostService(db).get_by_service(tenant_ctx, period_start, period_end, top_n)


@router.get("/by-tenant", response_model=CostByTenantResponse)
async def get_cost_by_tenant(
    period_start: date = Query(),
    period_end: date = Query(),
    current_user: UserMe = Depends(require_role(UserRole.SUPER_ADMIN)),
    db: AsyncSession = Depends(get_db),
):
    """Super Admin 전용: 전체 테넌트별 비용 비교."""
    from app.services.cost import CostService
    return await CostService(db).get_by_tenant(period_start, period_end)


@router.get("/trends", response_model=CostTrendsResponse)
async def get_cost_trends(
    period_start: date = Query(),
    period_end: date = Query(),
    granularity: str = Query("daily", description="daily | weekly | monthly"),
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.cost import CostService
    return await CostService(db).get_trends(tenant_ctx, period_start, period_end, granularity)


@router.get("/anomalies", response_model=CostAnomalyResponse)
async def get_cost_anomalies(
    status: Optional[str] = Query(None, description="open | acknowledged | resolved"),
    severity: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=100),
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.cost import CostService
    return await CostService(db).get_anomalies(tenant_ctx, status, severity, limit)


@router_budget.get("", response_model=PaginatedResponse[BudgetResponse])
async def list_budgets(
    cursor: Optional[str] = Query(None),
    limit: int = Query(20),
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.cost import CostService
    return await CostService(db).list_budgets(tenant_ctx, cursor, limit)


@router_budget.post("", response_model=BudgetResponse, status_code=201)
async def create_budget(
    body: BudgetCreate,
    current_user: UserMe = Depends(require_role(UserRole.TENANT_ADMIN)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    from app.services.cost import CostService
    return await CostService(db).create_budget(body, tenant_ctx, current_user.id)
```

---

## 9. 작업/감사 API

### 9.1 스키마 정의

```python
# app/schemas/job_audit.py

from pydantic import BaseModel, Field
from typing import Optional, Any
from datetime import datetime
from enum import Enum
from app.schemas.common import JobStatus


class JobDetailResponse(BaseModel):
    job_id: str
    job_type: str = Field(description="instance_action | tenant_onboard | sync_resources | ...")
    status: JobStatus
    progress: int
    message: Optional[str]
    result: Optional[Any]
    error: Optional[str]
    tenant_id: Optional[str]
    resource_id: Optional[str]
    created_by: str
    created_at: datetime
    updated_at: datetime
    completed_at: Optional[datetime]
    celery_task_id: Optional[str]

    model_config = {"from_attributes": True}


class JobCancelResponse(BaseModel):
    """Job 취소 결과 응답"""
    job_id: str
    status: JobStatus = Field(description="취소 후 상태 (cancelled)")
    message: str = Field(description="취소 처리 결과 메시지")


class AuditLogResponse(BaseModel):
    id: str
    tenant_id: Optional[str]
    user_id: str
    user_email: str
    action: str = Field(description="예: instance.stop, tenant.create, alert_rule.delete")
    resource_type: Optional[str]
    resource_id: Optional[str]
    request_method: str
    request_path: str
    request_body_hash: Optional[str] = Field(description="민감정보 제외 해시")
    response_status: int
    ip_address: str
    user_agent: str
    duration_ms: float
    timestamp: datetime

    model_config = {"from_attributes": True}
```

### 9.2 라우터 구현

```python
# app/routers/jobs.py

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.job_audit import JobDetailResponse, AuditLogResponse
from app.schemas.common import PaginatedResponse
from app.dependencies import get_db, get_current_user, get_tenant_context, require_role
from app.schemas.auth import UserMe, UserRole

router = APIRouter(prefix="/api/v1", tags=["Jobs & Audit"])


@router.get("/jobs", response_model=PaginatedResponse[JobDetailResponse])
async def list_jobs(
    job_type: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    resource_id: Optional[str] = Query(None),
    cursor: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=100),
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    """현재 사용자/테넌트의 비동기 작업 목록."""
    from app.services.job import JobService
    return await JobService(db).list_jobs(tenant_ctx, current_user, job_type, status, resource_id, cursor, limit)


@router.get("/jobs/{job_id}", response_model=JobDetailResponse)
async def get_job(
    job_id: str,
    current_user: UserMe = Depends(get_current_user),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    """특정 Job 상태 조회 (폴링용)."""
    from app.services.job import JobService
    return await JobService(db).get_job(job_id, tenant_ctx, current_user)


@router.post(
    "/jobs/{job_id}/cancel",
    response_model=JobCancelResponse,
    responses={
        200: {"description": "취소 성공 - status: cancelled"},
        409: {"description": "이미 완료된 작업 (completed/failed/cancelled 상태)"},
    },
)
async def cancel_job(
    job_id: str,
    current_user: UserMe = Depends(require_role(UserRole.OPERATOR)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    """
    진행 중인 비동기 작업 취소. pending/running 상태만 취소 가능.
    Celery task revoke 호출.

    - 200: 취소 성공 (status: cancelled)
    - 409: 이미 완료된 작업 취소 시도 (completed / failed / cancelled)
    """
    from app.services.job import JobService
    return await JobService(db).cancel_job(job_id, tenant_ctx, current_user.id)


@router.get("/audit-logs", response_model=PaginatedResponse[AuditLogResponse])
async def list_audit_logs(
    user_id: Optional[str] = Query(None),
    action: Optional[str] = Query(None, description="예: instance.stop"),
    resource_type: Optional[str] = Query(None),
    tenant_id: Optional[str] = Query(None, description="Super Admin 전용"),
    start_time: Optional[datetime] = Query(None),
    end_time: Optional[datetime] = Query(None),
    cursor: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=200),
    current_user: UserMe = Depends(require_role(UserRole.TENANT_ADMIN)),
    tenant_ctx = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
):
    """감사 로그 조회. Tenant Admin 이상 접근 가능."""
    from app.services.audit import AuditService
    return await AuditService(db).list_audit_logs(
        tenant_ctx, current_user, user_id, action, resource_type,
        start_time, end_time, cursor, limit
    )
```

---

## 10. WebSocket API

### 10.1 연결 규격

```
WS /ws/{tenant_id}?token={jwt_access_token}

연결 흐름:
1. 클라이언트 → WS 핸드셰이크 + JWT 검증
2. 서버 → connection_established 메시지
3. 클라이언트 → subscribe 메시지로 관심 채널 구독
4. 서버 → 실시간 이벤트 푸시
5. 클라이언트 → ping / unsubscribe / disconnect
```

### 10.2 메시지 스키마

```python
# app/schemas/websocket.py

from pydantic import BaseModel, Field
from typing import Optional, Any, Literal, List
from datetime import datetime
from enum import Enum


# ── 클라이언트 → 서버 ────────────────────────────────────────

class SubscribeMessage(BaseModel):
    type: Literal["subscribe"] = "subscribe"
    channels: List[str] = Field(
        description="구독 채널 목록",
        examples=[["alerts", "incidents", "jobs", "metrics:inst_xxx"]],
    )


class UnsubscribeMessage(BaseModel):
    type: Literal["unsubscribe"] = "unsubscribe"
    channels: List[str]


class PingMessage(BaseModel):
    type: Literal["ping"] = "ping"
    timestamp: datetime = Field(default_factory=datetime.utcnow)


# ── 서버 → 클라이언트 ────────────────────────────────────────

class ConnectionEstablished(BaseModel):
    type: Literal["connection_established"] = "connection_established"
    tenant_id: str
    user_id: str
    server_time: datetime = Field(default_factory=datetime.utcnow)
    available_channels: List[str] = Field(
        default=["alerts", "incidents", "jobs", "metrics"]
    )


class PongMessage(BaseModel):
    type: Literal["pong"] = "pong"
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class AlertFiredPayload(BaseModel):
    alert_id: str
    rule_id: str
    rule_name: str
    resource_id: str
    resource_name: str
    severity: str
    current_value: float
    threshold: float
    fired_at: datetime
    tenant_id: str


class AlertFiredEvent(BaseModel):
    type: Literal["alert_fired"] = "alert_fired"
    channel: str = "alerts"
    payload: AlertFiredPayload
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class IncidentUpdatedPayload(BaseModel):
    incident_id: str
    title: str
    status: str
    priority: str
    changed_fields: List[str]
    updated_by: str
    tenant_id: str


class IncidentUpdatedEvent(BaseModel):
    type: Literal["incident_updated"] = "incident_updated"
    channel: str = "incidents"
    payload: IncidentUpdatedPayload
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class JobProgressPayload(BaseModel):
    job_id: str
    job_type: str
    status: str
    progress: int = Field(ge=0, le=100)
    message: Optional[str]
    resource_id: Optional[str]
    result: Optional[Any]
    error: Optional[str]


class JobProgressEvent(BaseModel):
    type: Literal["job_progress"] = "job_progress"
    channel: str = "jobs"
    payload: JobProgressPayload
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class MetricUpdatePayload(BaseModel):
    resource_id: str
    resource_type: str
    metric_name: str
    value: float
    unit: str
    timestamp: datetime


class MetricUpdateEvent(BaseModel):
    type: Literal["metric_update"] = "metric_update"
    channel: str  # "metrics" or "metrics:{resource_id}"
    payload: MetricUpdatePayload
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class ErrorEvent(BaseModel):
    type: Literal["error"] = "error"
    code: str
    message: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
```

### 10.3 WebSocket 엔드포인트 구현

```python
# app/routers/websocket.py

import json
import asyncio
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query, Depends
from app.services.auth import AuthService
from app.services.websocket import WebSocketManager

router = APIRouter(tags=["WebSocket"])
ws_manager = WebSocketManager()


@router.websocket("/ws/{tenant_id}")
async def websocket_endpoint(
    websocket: WebSocket,
    tenant_id: str,
    token: str = Query(description="JWT Access Token"),
    db = Depends(get_db),
):
    """
    WebSocket 실시간 이벤트 스트림.

    채널 목록:
    - alerts              : 알람 발생/해제 이벤트
    - incidents           : 인시던트 생성/업데이트 이벤트
    - jobs                : 비동기 작업 진행률
    - metrics             : 메트릭 실시간 스트림 (전체)
    - metrics:{resource_id}: 특정 리소스 메트릭만
    """
    # JWT 검증
    auth_svc = AuthService(db)
    try:
        user = await auth_svc.verify_token(token)
        await auth_svc.check_tenant_access(user, tenant_id)
    except Exception:
        await websocket.close(code=4001, reason="Unauthorized")
        return

    await websocket.accept()
    connection_id = await ws_manager.connect(websocket, user.id, tenant_id)

    # 연결 확인 메시지
    await websocket.send_json({
        "type": "connection_established",
        "tenant_id": tenant_id,
        "user_id": user.id,
        "server_time": datetime.utcnow().isoformat(),
        "available_channels": ["alerts", "incidents", "jobs", "metrics"],
    })

    try:
        while True:
            raw = await asyncio.wait_for(websocket.receive_text(), timeout=60.0)
            msg = json.loads(raw)

            match msg.get("type"):
                case "subscribe":
                    await ws_manager.subscribe(connection_id, msg.get("channels", []))
                case "unsubscribe":
                    await ws_manager.unsubscribe(connection_id, msg.get("channels", []))
                case "ping":
                    await websocket.send_json({"type": "pong", "timestamp": datetime.utcnow().isoformat()})
                case _:
                    await websocket.send_json({"type": "error", "code": "UNKNOWN_MESSAGE_TYPE", "message": f"Unknown type: {msg.get('type')}"})

    except asyncio.TimeoutError:
        # 60초 메시지 없으면 연결 끊기
        await websocket.close(code=1001, reason="Idle timeout")
    except WebSocketDisconnect:
        pass
    finally:
        await ws_manager.disconnect(connection_id)


# ── WebSocket Manager (Redis Pub/Sub 기반) ───────────────────

# app/services/websocket.py

import uuid
import json
import redis.asyncio as aioredis
from fastapi import WebSocket
from typing import dict, set


class WebSocketManager:
    """
    Redis Pub/Sub을 통해 멀티 인스턴스 간 메시지 브로드캐스트.
    채널 구조: ws:{tenant_id}:{channel}
    """

    def __init__(self):
        self.connections: dict[str, WebSocket] = {}       # connection_id → ws
        self.user_channels: dict[str, set[str]] = {}      # connection_id → subscribed channels
        self.redis: aioredis.Redis = None

    async def connect(self, ws: WebSocket, user_id: str, tenant_id: str) -> str:
        connection_id = f"{tenant_id}:{user_id}:{uuid.uuid4().hex[:8]}"
        self.connections[connection_id] = ws
        self.user_channels[connection_id] = set()
        return connection_id

    async def disconnect(self, connection_id: str) -> None:
        self.connections.pop(connection_id, None)
        self.user_channels.pop(connection_id, None)

    async def subscribe(self, connection_id: str, channels: list[str]) -> None:
        if connection_id in self.user_channels:
            self.user_channels[connection_id].update(channels)

    async def unsubscribe(self, connection_id: str, channels: list[str]) -> None:
        if connection_id in self.user_channels:
            self.user_channels[connection_id].difference_update(channels)

    async def broadcast_to_tenant(self, tenant_id: str, channel: str, event: dict) -> None:
        """특정 테넌트의 해당 채널 구독자에게 브로드캐스트."""
        for conn_id, ws in list(self.connections.items()):
            if conn_id.startswith(f"{tenant_id}:"):
                subscribed = self.user_channels.get(conn_id, set())
                if channel in subscribed or channel.split(":")[0] in subscribed:
                    try:
                        await ws.send_json(event)
                    except Exception:
                        await self.disconnect(conn_id)

    async def publish_via_redis(self, tenant_id: str, channel: str, event: dict) -> None:
        """Redis Publish → 모든 백엔드 인스턴스에 전파."""
        redis_channel = f"ws:{tenant_id}:{channel}"
        await self.redis.publish(redis_channel, json.dumps(event))
```

---

## 11. FastAPI 의존성 주입

```python
# app/dependencies.py

from __future__ import annotations
from typing import Optional, Callable
from fastapi import Depends, HTTPException, Header, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from functools import lru_cache
import jwt

from app.db.session import AsyncSessionLocal
from app.schemas.auth import UserMe, UserRole
from app.core.config import settings

security = HTTPBearer()


# ─────────────────────────────────────────────────────────────
# DB 세션
# ─────────────────────────────────────────────────────────────

async def get_db() -> AsyncSession:
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


# ─────────────────────────────────────────────────────────────
# 현재 사용자 추출
# ─────────────────────────────────────────────────────────────

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> UserMe:
    """
    JWT RS256 검증 → 블랙리스트 확인 → DB에서 사용자 조회.
    OCI API Gateway에서 이미 1차 검증 완료; 여기서는 비즈니스 로직 검증.
    """
    token = credentials.credentials
    try:
        payload = jwt.decode(
            token,
            settings.JWT_PUBLIC_KEY,
            algorithms=["RS256"],
            options={"require": ["exp", "iat", "sub", "jti"]},
        )
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "AUTH_002", "message": "Access token has expired"},
        )
    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "AUTH_003", "message": "Invalid token signature"},
        )

    # Redis 블랙리스트 확인
    from app.core.redis import redis_client
    if await redis_client.get(f"blacklist:{payload['jti']}"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "AUTH_002", "message": "Token has been revoked"},
        )

    # DB에서 사용자 조회
    from app.repositories.user import UserRepository
    user = await UserRepository(db).get_by_id(payload["sub"])
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "AUTH_001", "message": "User not found or inactive"},
        )

    return UserMe.model_validate(user)


# ─────────────────────────────────────────────────────────────
# 역할 기반 접근 제어
# ─────────────────────────────────────────────────────────────

ROLE_HIERARCHY = {
    UserRole.SUPER_ADMIN: 4,
    UserRole.TENANT_ADMIN: 3,
    UserRole.OPERATOR: 2,
    UserRole.VIEWER: 1,
}


def require_role(required_role: UserRole) -> Callable:
    """
    지정한 역할 이상의 권한을 가진 사용자만 허용.
    Super Admin은 모든 테넌트에 접근 가능.
    """
    async def _check_role(
        current_user: UserMe = Depends(get_current_user),
        x_tenant_id: Optional[str] = Header(None, alias="X-Tenant-ID"),
    ) -> UserMe:
        if current_user.is_super_admin:
            return current_user

        if not x_tenant_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={"code": "VALID_001", "message": "X-Tenant-ID header required"},
            )

        # 해당 테넌트에서의 역할 확인
        user_role_in_tenant = None
        for tr in current_user.tenant_roles:
            if tr.tenant_id == x_tenant_id:
                user_role_in_tenant = tr.role
                break

        if not user_role_in_tenant:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={"code": "PERM_001", "message": "No access to this tenant"},
            )

        if ROLE_HIERARCHY[user_role_in_tenant] < ROLE_HIERARCHY[required_role]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "code": "PERM_002",
                    "message": f"Required role: {required_role.value}, current: {user_role_in_tenant.value}",
                },
            )

        return current_user

    return _check_role


# ─────────────────────────────────────────────────────────────
# 테넌트 컨텍스트
# ─────────────────────────────────────────────────────────────

class TenantContext:
    def __init__(
        self,
        tenant_id: str,
        is_super_admin: bool,
        user_role: Optional[UserRole],
    ):
        self.tenant_id = tenant_id
        self.is_super_admin = is_super_admin
        self.user_role = user_role


async def get_tenant_context(
    current_user: UserMe = Depends(get_current_user),
    x_tenant_id: Optional[str] = Header(None, alias="X-Tenant-ID"),
    db: AsyncSession = Depends(get_db),
) -> TenantContext:
    """
    X-Tenant-ID 헤더 우선순위 규칙
    1. Super Admin: X-Tenant-ID 헤더 값 사용 (다른 테넌트 접근 허용)
    2. 일반 사용자: JWT tenant_id 클레임 값 사용, X-Tenant-ID와 불일치 시 403 반환
    3. X-Tenant-ID 헤더 없을 경우: JWT tenant_id 사용
    """
    if current_user.is_super_admin:
        effective_tenant_id = x_tenant_id or "all"
        return TenantContext(
            tenant_id=effective_tenant_id,
            is_super_admin=True,
            user_role=UserRole.SUPER_ADMIN,
        )

    if not x_tenant_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"code": "VALID_001", "message": "X-Tenant-ID header is required"},
        )

    # 테넌트 접근 권한 확인
    user_role = None
    for tr in current_user.tenant_roles:
        if tr.tenant_id == x_tenant_id:
            user_role = tr.role
            break

    if not user_role:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "PERM_001", "message": "No access to this tenant"},
        )

    # 테넌트 활성 상태 확인
    from app.repositories.tenant import TenantRepository
    tenant = await TenantRepository(db).get_by_id(x_tenant_id)
    if not tenant or tenant.status not in ("active", "onboarding"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "TENANT_002", "message": "Tenant is not active"},
        )

    return TenantContext(
        tenant_id=x_tenant_id,
        is_super_admin=False,
        user_role=user_role,
    )


# ─────────────────────────────────────────────────────────────
# OCI 클라이언트 팩토리
# ─────────────────────────────────────────────────────────────

class OCIClientFactory:
    """
    테넌트별 OCI SDK 클라이언트 생성 (Vault에서 Credential 로드).
    인스턴스 캐싱으로 재사용.
    """
    def __init__(self, tenant_id: str, credential: dict):
        self.tenant_id = tenant_id
        self._credential = credential
        self._signer = None

    @property
    def signer(self):
        if not self._signer:
            import oci
            self._signer = oci.Signer(
                tenancy=self._credential["tenancy_id"],
                user=self._credential["user_ocid"],
                fingerprint=self._credential["fingerprint"],
                private_key_content=self._credential["private_key_pem"],
            )
        return self._signer

    def compute_client(self, region: str):
        import oci
        config = {"region": region}
        return oci.core.ComputeClient(config, signer=self.signer)

    def network_client(self, region: str):
        import oci
        return oci.core.VirtualNetworkClient({"region": region}, signer=self.signer)

    def monitoring_client(self, region: str):
        import oci
        return oci.monitoring.MonitoringClient({"region": region}, signer=self.signer)


async def get_oci_factory(
    tenant_ctx: TenantContext = Depends(get_tenant_context),
    db: AsyncSession = Depends(get_db),
) -> OCIClientFactory:
    """
    테넌트 OCI Credential을 Vault에서 조회 후 OCIClientFactory 반환.
    Redis 캐시 (TTL 5분)로 Vault 요청 최소화.
    """
    from app.core.redis import redis_client
    from app.services.vault import VaultService
    import json

    cache_key = f"oci_cred:{tenant_ctx.tenant_id}"
    cached = await redis_client.get(cache_key)

    if cached:
        credential = json.loads(cached)
    else:
        vault_svc = VaultService()
        credential = await vault_svc.get_tenant_credential(tenant_ctx.tenant_id)
        await redis_client.setex(cache_key, 300, json.dumps(credential))

    return OCIClientFactory(tenant_ctx.tenant_id, credential)
```

---

## 12. API 보안

### 12.1 Rate Limiting 정책

```python
# app/middleware/rate_limit.py

from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)

# 엔드포인트별 Rate Limit 정책
RATE_LIMITS = {
    # 인증 (엄격)
    "POST /api/v1/auth/login":       "5/minute",     # 브루트포스 방지
    "POST /api/v1/auth/refresh":     "30/minute",
    "POST /api/v1/auth/mfa/verify":  "10/minute",

    # 조회 API (관대)
    "GET /api/v1/compute/instances": "120/minute",
    "GET /api/v1/monitoring/metrics":"60/minute",    # OCI Monitoring 비용

    # 쓰기 API (중간)
    "POST /api/v1/compute/instances/*/actions": "20/minute",
    "POST /api/v1/incidents":        "30/minute",

    # 관리 API
    "POST /api/v1/tenants":          "10/minute",
    "POST /api/v1/tenants/*/onboard":"20/minute",

    # 비용 조회 (OCI Usage API 제한)
    "GET /api/v1/costs/*":           "30/minute",

    # WebSocket
    "WS /ws/*":                      "10/minute",    # 연결 수립 제한
}

# 응답 헤더
# X-RateLimit-Limit: 120
# X-RateLimit-Remaining: 45
# X-RateLimit-Reset: 1711020600
```

**엔드포인트별 Rate Limit 정책 요약**:

| 엔드포인트 | Rate Limit | 버스트 | 비고 |
|-----------|-----------|-------|------|
| POST /auth/login | 10/분 | 20 | IP 기반 |
| POST /auth/refresh | 30/분 | 50 | 토큰 기반 |
| GET /resources/compute/instances | 100/분 | 200 | 테넌트 기반 |
| POST /resources/compute/instances/*/actions | 20/분 | 30 | 테넌트 기반 |
| GET /monitoring/metrics | 60/분 | 100 | 테넌트 기반 |
| 기타 GET | 300/분 | 500 | 테넌트 기반 |
| 기타 POST/PATCH/DELETE | 60/분 | 100 | 테넌트 기반 |

### 12.2 CORS 설정

```python
# app/main.py

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings

app = FastAPI(
    title="OCI MSP Management Platform API",
    version="1.0.0",
    docs_url="/api/docs" if settings.ENVIRONMENT != "production" else None,
    redoc_url="/api/redoc" if settings.ENVIRONMENT != "production" else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,  # ["https://msp.example.com"]
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=[
        "Authorization",
        "Content-Type",
        "X-Tenant-ID",
        "X-Request-ID",
        "X-Forwarded-For",
    ],
    expose_headers=[
        "X-RateLimit-Limit",
        "X-RateLimit-Remaining",
        "X-RateLimit-Reset",
        "X-Request-ID",
    ],
    max_age=600,
)

# 라우터 등록
from app.routers import auth, tenants, compute, monitoring, incidents, costs, jobs
app.include_router(auth.router)
app.include_router(tenants.router)
app.include_router(compute.router)
app.include_router(monitoring.router)
app.include_router(incidents.router)
app.include_router(costs.router)
app.include_router(jobs.router)


# 요청 ID 미들웨어
import uuid
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

class RequestIDMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        request_id = request.headers.get("X-Request-ID") or f"req_{uuid.uuid4().hex[:12]}"
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response

app.add_middleware(RequestIDMiddleware)


# 감사 로그 미들웨어
import time
from app.services.audit import AuditService

class AuditMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start_time = time.time()
        response = await call_next(request)
        duration_ms = (time.time() - start_time) * 1000

        # 쓰기 작업만 감사 로그 기록
        if request.method in ("POST", "PUT", "PATCH", "DELETE"):
            # 비동기로 기록 (요청 응답 지연 없도록)
            import asyncio
            asyncio.create_task(
                AuditService.log_request(request, response, duration_ms)
            )

        return response

app.add_middleware(AuditMiddleware)


# 헬스체크
@app.get("/health", response_model=HealthResponse, tags=["System"])
async def health_check():
    from app.services.health import HealthService
    return await HealthService.check()
```

### 12.3 OCI API Gateway 연동 JWT 검증

```
OCI API Gateway 정책 설정 (Terraform):

resource "oci_apigateway_deployment" "msp_api" {
  specification {
    routes {
      path    = "/api/v1/{path*}"
      methods = ["ANY"]

      request_policies {
        authorization {
          type = "JWT_AUTHENTICATION"
          token_header = "Authorization"
          token_auth_scheme = "Bearer"

          validation_policy {
            type = "REMOTE_JWKS"
            uri  = "https://msp-backend.internal/.well-known/jwks.json"
            is_ssl_verify_disabled = false
            additional_validation_policy {
              audiences = ["msp-platform"]
              issuers   = ["https://msp.example.com"]
              verify_claims {
                key      = "iss"
                is_required = true
              }
            }
          }
        }

        rate_limiting {
          rate_key  = "CLIENT_IP"
          rate_in_requests_per_second = 100
        }
      }
    }

    routes {
      path    = "/ws/{path*}"
      methods = ["GET"]
      # WebSocket: JWT는 쿼리 파라미터로 전달
      request_policies {
        authorization {
          type = "JWT_AUTHENTICATION"
          token_query_param = "token"
        }
      }
    }
  }
}
```

### 12.4 보안 헤더 설정

```python
# app/middleware/security_headers.py

from starlette.middleware.base import BaseHTTPMiddleware

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Cache-Control"] = "no-store"
        response.headers["Content-Security-Policy"] = (
            "default-src 'none'; frame-ancestors 'none'"
        )
        return response
```

### 12.5 API 엔드포인트 권한 매트릭스

| 엔드포인트 | Super Admin | Tenant Admin | Operator | Viewer |
|-----------|------------|--------------|----------|--------|
| GET /tenants | O | X | X | X |
| POST /tenants | O | X | X | X |
| GET /tenants/{id}/summary | O | O | O | O |
| POST /tenants/{id}/onboard | O | X | X | X |
| GET /compute/instances | O | O | O | O |
| POST /compute/instances/{id}/actions | O | O | O | X |
| GET/POST /alert-rules | O | O | O | X |
| DELETE /alert-rules/{id} | O | O | X | X |
| GET /alerts | O | O | O | O |
| PUT /alerts/{id}/acknowledge | O | O | O | X |
| GET/POST /incidents | O | O | O | X (GET만) |
| PUT /incidents/{id} | O | O | O | X |
| POST /incidents/{id}/resolve | O | O | O | X |
| GET /costs/* | O | O | O | O |
| POST /budgets | O | O (자기 테넌트) | X | X |
| GET /audit-logs | O | O | X | X |
| DELETE /jobs/{id} | O | O | O | X |
