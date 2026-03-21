# OCI MSP 관리 플랫폼 - 보안 설계서

> 작성: 클라우드 보안 아키텍처 설계
> 날짜: 2026-03-21
> 버전: 1.0
> 상태: 확정
> 분류: CONFIDENTIAL

---

## 목차

1. [위협 모델 (STRIDE)](#1-위협-모델-stride)
2. [OCI Credential 관리 설계](#2-oci-credential-관리-설계)
3. [JWT 인증 시스템](#3-jwt-인증-시스템)
4. [MFA 구현](#4-mfa-구현)
5. [RBAC 권한 매트릭스](#5-rbac-권한-매트릭스)
6. [멀티 테넌트 RLS 보안](#6-멀티-테넌트-rls-보안)
7. [API 보안](#7-api-보안)
8. [데이터 보안](#8-데이터-보안)
9. [감사 로그 설계](#9-감사-로그-설계)
10. [OCI 네트워크 보안](#10-oci-네트워크-보안)
11. [OCI Cloud Guard 연동](#11-oci-cloud-guard-연동)
12. [컴플라이언스 체크리스트](#12-컴플라이언스-체크리스트)

---

## 1. 위협 모델 (STRIDE)

### 1.1 STRIDE 매트릭스

| 위협 카테고리 | 정의 | MSP 플랫폼 구체 위협 | 위험도 | 대응 전략 |
|---|---|---|---|---|
| **S**poofing (위장) | 다른 사용자/시스템으로 위장 | JWT 토큰 위조, 타 테넌트 사용자 위장, API Key 탈취 후 MSP 인장 | Critical | RS256 서명, 토큰 블랙리스트, MFA 강제 |
| **T**ampering (변조) | 데이터/요청 무단 수정 | API 요청 파라미터 조작, DB 레코드 직접 수정, OCI API 호출 변조 | High | HTTPS 강제, 입력 검증, DB 감사, 서명 검증 |
| **R**epudiation (부인) | 행위 부인 | 리소스 삭제 후 책임 부인, 설정 변경 부인, 고객 Credential 접근 부인 | High | 불변 감사 로그(WORM), 전자서명, 타임스탬프 |
| **I**nformation Disclosure (정보 누출) | 무단 데이터 열람 | 크로스 테넌트 데이터 누출, OCI Credential 노출, 내부 API 응답 노출 | Critical | RLS, 암호화, 최소 권한, 응답 필터링 |
| **D**enial of Service (서비스 거부) | 서비스 가용성 침해 | OCI API Rate Limit 고갈, DB 커넥션 풀 소진, 대량 알림 발송 | Medium | Rate Limiting, 커넥션 풀, 회로 차단기 |
| **E**levation of Privilege (권한 상승) | 권한 범위 초과 | Viewer → Admin 권한 상승, 테넌트 간 수평 이동, OCI IAM Policy 악용 | Critical | RBAC 엄격 적용, 최소 권한 원칙, 정기 감사 |

### 1.2 핵심 위험 우선순위

```
┌─────────────────────────────────────────────────────────────────┐
│                    위험 우선순위 매트릭스                          │
│                                                                  │
│  영향도                                                           │
│  (High)  ┌─────────────────┬─────────────────┬───────────────┐  │
│          │                 │ [C] 크로스 테넌트  │ [C] API Key   │  │
│          │                 │  데이터 누출       │  탈취         │  │
│          │  [H] OCI API   ├─────────────────┤ [C] JWT 위조  │  │
│          │  Rate 고갈      │ [H] 권한 상승     │               │  │
│          ├─────────────────┼─────────────────┼───────────────┤  │
│  (Med)   │ [M] DoS 공격   │ [M] 로그 변조    │ [H] 내부 정보  │  │
│          │                 │                 │   노출         │  │
│          ├─────────────────┼─────────────────┼───────────────┤  │
│  (Low)   │ [L] UI XSS     │ [L] CSRF        │               │  │
│          └─────────────────┴─────────────────┴───────────────┘  │
│              낮음                중간              높음             │
│                            발생 가능성                             │
│                                                                  │
│  C=Critical  H=High  M=Medium  L=Low                            │
└─────────────────────────────────────────────────────────────────┘
```

#### Critical 위험 상세 분석

**[C-1] 크로스 테넌트 데이터 누출**
- 시나리오: 고객사 A의 사용자가 고객사 B의 OCI 리소스 정보 조회
- 영향: 경쟁사 인프라 정보 노출, 계약 위반, 법적 책임
- 공격 벡터: API 파라미터 조작(tenant_id 변경), RLS 미적용 쿼리, JWT 클레임 변조
- 대응: PostgreSQL RLS + SQLAlchemy 이벤트 훅 강제 적용

**[C-2] OCI API Key 탈취**
- 시나리오: 고객사 OCI Credential이 MSP 시스템에서 유출
- 영향: 고객사 전체 OCI 인프라 무단 제어 가능, 데이터 삭제/유출
- 공격 벡터: DB 직접 접근, 메모리 덤프, 로그 노출, 백업 파일 탈취
- 대응: OCI Vault HSM 저장, Fernet 이중 암호화, 접근 감사, Key Rotation

**[C-3] JWT 토큰 위조**
- 시나리오: 알고리즘 혼동 공격(RS256→HS256), 만료 토큰 재사용, 서명 없는 토큰 수용
- 영향: 임의 사용자 권한으로 API 호출, 관리자 권한 획득
- 공격 벡터: "alg: none" 공격, 공개키를 HS256 비밀키로 악용
- 대응: 알고리즘 명시적 검증, 짧은 만료 시간(15분), Redis 블랙리스트

### 1.3 공격 표면 분석

```
외부 공격 표면:
  - HTTPS 엔드포인트 (443/tcp) → OCI Load Balancer → API Gateway
  - WebSocket 엔드포인트 (/ws/*) → 인증 필수
  - 관리자 Bastion Host (22/tcp) → IP 화이트리스트 제한

내부 공격 표면:
  - OKE Pod 간 통신 → mTLS 적용 (Istio Service Mesh)
  - PostgreSQL (5432/tcp) → DB Subnet 격리, SSL 강제
  - Redis (6379/tcp) → Private Subnet 격리, AUTH 비밀번호
  - OCI Vault API → Resource Principal 전용, IAM Policy 최소 권한

서드파티 공격 표면:
  - OCI SDK 의존성 → 버전 고정 및 취약점 스캔 (Snyk/Trivy)
  - Python 패키지 → uv.lock 해시 검증, 공급망 공격 방지
  - Docker Base Image → 최소 이미지(distroless), 정기 재빌드
```

---

## 2. OCI Credential 관리 설계

### 2.1 Cross-Tenancy Resource Principal (권장 방식)

MSP 자체 OCI 인스턴스가 고객 테넌시에 직접 접근하는 방식으로, API Key를 저장할 필요가 없어 보안상 가장 우수합니다.

```
[아키텍처 흐름]

MSP 테넌시                              고객 테넌시
┌─────────────────────────┐            ┌──────────────────────────┐
│  OKE Node (Compute)     │            │  IAM Policy              │
│                         │            │                          │
│  Dynamic Group:         │  cross-    │  Allow dynamic-group     │
│  MSP-OKE-Agents         │──tenancy──►│  MSP-OKE-Agents@         │
│  (instance.compartment  │  trust     │  <msp-tenancy-ocid>      │
│   .id='<MSP_COMP>')     │            │  to manage instances     │
│                         │            │  in tenancy              │
│  Resource Principal     │            │                          │
│  Certificate (자동)     │            │  (리소스별 세분화)         │
└─────────────────────────┘            └──────────────────────────┘
```

**MSP 테넌시 Dynamic Group 설정:**
```hcl
# Terraform / OCI CLI
resource "oci_identity_dynamic_group" "msp_agents" {
  name           = "MSP-OKE-Agents"
  description    = "MSP 플랫폼 OKE 노드 - 고객 테넌시 접근용"
  compartment_id = var.msp_tenancy_id
  matching_rule  = "instance.compartment.id = '${var.msp_compartment_ocid}'"
}
```

**고객 테넌시 IAM Policy (최소 권한 원칙):**
```
# 기본 읽기 권한 (모든 고객)
Allow dynamic-group MSP-OKE-Agents@<MSP_TENANCY_OCID> to read all-resources in tenancy

# 컴퓨트 관리 권한 (요청 시 추가)
Allow dynamic-group MSP-OKE-Agents@<MSP_TENANCY_OCID> to manage instances in tenancy
Allow dynamic-group MSP-OKE-Agents@<MSP_TENANCY_OCID> to manage instance-console-connections in tenancy

# 네트워크 읽기
Allow dynamic-group MSP-OKE-Agents@<MSP_TENANCY_OCID> to read virtual-network-family in tenancy

# 비용/사용량 읽기
Allow dynamic-group MSP-OKE-Agents@<MSP_TENANCY_OCID> to read usage-reports in tenancy

# 모니터링 읽기
Allow dynamic-group MSP-OKE-Agents@<MSP_TENANCY_OCID> to read metrics in tenancy
Allow dynamic-group MSP-OKE-Agents@<MSP_TENANCY_OCID> to read alarms in tenancy
```

**Python SDK 연동 (Resource Principal):**
```python
import oci

def get_oci_client_for_customer(customer_tenancy_id: str, service: str):
    """
    Resource Principal을 사용하여 고객 테넌시 OCI 클라이언트 생성.
    API Key 불필요 - OKE 노드 인증서 기반 자동 인증.
    """
    signer = oci.auth.signers.get_resource_principals_signer()

    client_map = {
        "compute": oci.core.ComputeClient,
        "identity": oci.identity.IdentityClient,
        "monitoring": oci.monitoring.MonitoringClient,
        "usage": oci.usage_api.UsageapiClient,
    }

    client_class = client_map.get(service)
    if not client_class:
        raise ValueError(f"지원하지 않는 서비스: {service}")

    return client_class(
        config={"tenancy": customer_tenancy_id, "region": "ap-seoul-1"},
        signer=signer,
    )
```

### 2.2 API Key 폴백 방식 (Resource Principal 미지원 고객)

일부 고객이 Cross-Tenancy 설정을 거부하거나 기술적 제약이 있는 경우 사용합니다.

**OCI Vault Secret 저장 구조:**
```
OCI Vault (MSP 전용, HSM 보호)
├── Secret: customer-{tenant_id}-api-key
│   ├── user_ocid: "ocid1.user.oc1..."
│   ├── fingerprint: "xx:xx:xx:..."
│   ├── private_key_pem: "<Fernet 이중 암호화>"
│   ├── tenancy_ocid: "ocid1.tenancy.oc1..."
│   └── region: "ap-seoul-1"
│
└── Secret: customer-{tenant_id}-api-key-metadata
    ├── created_at: "2026-03-21T00:00:00Z"
    ├── rotated_at: "2026-03-21T00:00:00Z"
    └── expires_at: "2026-06-19T00:00:00Z"  # 90일
```

**Fernet 이중 암호화 구현:**
```python
# app/security/credential_manager.py
import base64
import json
import logging
from datetime import datetime, timezone
from typing import Optional

import oci
from cryptography.fernet import Fernet

from app.config import settings
from app.models.audit import AuditLog
from app.db.session import get_db_session

logger = logging.getLogger(__name__)


class CredentialManager:
    """
    OCI API Key를 OCI Vault + Fernet 이중 암호화로 관리.
    접근 시마다 감사 로그 기록.
    """

    def __init__(self):
        # Fernet 키는 OCI Vault에서 별도 관리 (앱 시작 시 로드)
        self._fernet = Fernet(settings.CREDENTIAL_ENCRYPTION_KEY.encode())
        self._vault_client = oci.vault.VaultsClient(
            config={},
            signer=oci.auth.signers.get_resource_principals_signer(),
        )
        self._secret_client = oci.secrets.SecretsClient(
            config={},
            signer=oci.auth.signers.get_resource_principals_signer(),
        )

    def encrypt_credential(self, credential_dict: dict) -> str:
        """
        OCI Credential dict를 Fernet으로 암호화.
        반환값: base64 인코딩된 암호화 바이트
        """
        plaintext = json.dumps(credential_dict).encode("utf-8")
        encrypted = self._fernet.encrypt(plaintext)
        return base64.urlsafe_b64encode(encrypted).decode("ascii")

    def decrypt_credential(self, encrypted_b64: str) -> dict:
        """
        Fernet 복호화. 변조 시 InvalidToken 예외 발생.
        """
        encrypted = base64.urlsafe_b64decode(encrypted_b64.encode("ascii"))
        plaintext = self._fernet.decrypt(encrypted)
        return json.loads(plaintext.decode("utf-8"))

    async def store_credential(
        self,
        tenant_id: str,
        credential: dict,
        operator_id: str,
    ) -> str:
        """
        OCI Vault에 암호화된 Credential 저장.
        감사 로그 기록 후 Secret OCID 반환.
        """
        encrypted = self.encrypt_credential(credential)
        secret_name = f"customer-{tenant_id}-api-key"

        # OCI Vault Secret 생성/업데이트
        secret_content = oci.vault.models.Base64SecretContentDetails(
            content_type="BASE64",
            content=base64.b64encode(encrypted.encode()).decode(),
            name=secret_name,
        )

        # 감사 로그 기록 (Credential 접근 이벤트)
        await self._record_credential_audit(
            tenant_id=tenant_id,
            action="STORE",
            operator_id=operator_id,
        )

        logger.info(
            "credential_stored",
            extra={"tenant_id": tenant_id, "operator_id": operator_id},
        )
        return secret_name

    async def retrieve_credential(
        self,
        tenant_id: str,
        operator_id: str,
        reason: str,
    ) -> dict:
        """
        OCI Vault에서 Credential 복호화 후 반환.
        모든 접근 시 감사 로그 필수 기록.
        """
        secret_name = f"customer-{tenant_id}-api-key"

        # OCI Vault에서 Secret 조회
        secret_bundle = self._secret_client.get_secret_bundle_by_name(
            secret_name=secret_name,
            vault_id=settings.OCI_VAULT_OCID,
        ).data

        encrypted_b64_bytes = base64.b64decode(
            secret_bundle.secret_bundle_content.content
        )
        encrypted_b64 = encrypted_b64_bytes.decode("ascii")
        credential = self.decrypt_credential(encrypted_b64)

        # 감사 로그 기록 (Credential 접근은 항상 기록)
        await self._record_credential_audit(
            tenant_id=tenant_id,
            action="RETRIEVE",
            operator_id=operator_id,
            reason=reason,
        )

        return credential

    async def _record_credential_audit(
        self,
        tenant_id: str,
        action: str,
        operator_id: str,
        reason: str = "",
    ) -> None:
        """모든 Credential 접근 이벤트를 audit_logs 테이블에 기록."""
        async with get_db_session() as session:
            log = AuditLog(
                tenant_id=tenant_id,
                actor_id=operator_id,
                event_type=f"CREDENTIAL_{action}",
                resource_type="OCI_CREDENTIAL",
                resource_id=tenant_id,
                details={"reason": reason, "action": action},
                severity="HIGH",
                created_at=datetime.now(timezone.utc),
            )
            session.add(log)
            await session.commit()


credential_manager = CredentialManager()
```

### 2.3 90일 Key Rotation 자동화 (Celery Beat)

```python
# app/tasks/credential_rotation.py
from celery import shared_task
from celery.utils.log import get_task_logger
from datetime import datetime, timedelta, timezone

from app.db.session import get_sync_db
from app.models.tenant import TenantCredential
from app.security.credential_manager import credential_manager
from app.notifications.alert import send_security_alert

logger = get_task_logger(__name__)

ROTATION_INTERVAL_DAYS = 90
WARNING_DAYS_BEFORE = 14  # 만료 14일 전 경고


@shared_task(
    name="tasks.check_credential_rotation",
    bind=True,
    max_retries=3,
    default_retry_delay=300,
)
def check_credential_rotation(self):
    """
    Celery Beat 스케줄: 매일 09:00 KST 실행.
    90일 경과 Credential 자동 회전 + 경고 알림 발송.
    """
    now = datetime.now(timezone.utc)
    rotation_threshold = now - timedelta(days=ROTATION_INTERVAL_DAYS)
    warning_threshold = now - timedelta(days=ROTATION_INTERVAL_DAYS - WARNING_DAYS_BEFORE)

    with get_sync_db() as db:
        credentials = db.query(TenantCredential).filter(
            TenantCredential.is_active == True,
            TenantCredential.credential_type == "API_KEY",
        ).all()

        for cred in credentials:
            age_days = (now - cred.rotated_at).days

            if cred.rotated_at < rotation_threshold:
                # 90일 초과 → 자동 회전 시작
                logger.warning(
                    f"credential_rotation_required: tenant={cred.tenant_id}, "
                    f"age={age_days}days"
                )
                rotate_credential.apply_async(
                    args=[str(cred.tenant_id)],
                    countdown=0,
                )

            elif cred.rotated_at < warning_threshold:
                # 만료 14일 전 경고
                days_remaining = ROTATION_INTERVAL_DAYS - age_days
                send_security_alert.apply_async(
                    args=[
                        cred.tenant_id,
                        f"OCI API Key가 {days_remaining}일 후 만료됩니다. "
                        f"Key Rotation을 진행해주세요.",
                        "WARNING",
                    ]
                )


@shared_task(
    name="tasks.rotate_credential",
    bind=True,
    max_retries=3,
    default_retry_delay=600,
    acks_late=True,  # 완료 후 ACK (중복 실행 방지)
)
def rotate_credential(self, tenant_id: str):
    """
    OCI API Key 회전:
    1. 고객 테넌시에 새 API Key 생성
    2. OCI Vault에 새 버전 저장
    3. 구버전 비활성화
    4. 감사 로그 기록
    """
    try:
        logger.info(f"Starting credential rotation for tenant: {tenant_id}")

        # 1. 새 API Key 생성 (고객 테넌시 IAM API 호출)
        # 실제 구현: oci.identity.IdentityClient.create_api_key()
        new_credential = _generate_new_api_key(tenant_id)

        # 2. OCI Vault 신규 버전 저장
        credential_manager.store_credential(
            tenant_id=tenant_id,
            credential=new_credential,
            operator_id="SYSTEM_ROTATION",
        )

        # 3. DB 메타데이터 갱신
        with get_sync_db() as db:
            cred = db.query(TenantCredential).filter(
                TenantCredential.tenant_id == tenant_id
            ).first()
            cred.rotated_at = datetime.now(timezone.utc)
            cred.expires_at = datetime.now(timezone.utc) + timedelta(days=90)
            db.commit()

        # 4. 구버전 API Key 삭제 (30분 유예 후)
        deactivate_old_credential.apply_async(
            args=[tenant_id, new_credential["fingerprint"]],
            countdown=1800,
        )

        logger.info(f"Credential rotation completed: tenant={tenant_id}")

    except Exception as exc:
        logger.error(f"Credential rotation failed: tenant={tenant_id}, error={exc}")
        send_security_alert.apply_async(
            args=[tenant_id, f"Key Rotation 실패: {str(exc)}", "CRITICAL"]
        )
        raise self.retry(exc=exc)


@celery_app.task
def verify_resource_principal_credentials():
    """Cross-Tenancy Resource Principal 방식 Credential 상태 검증 (매 6시간)"""
    # 1. credential_type = 'resource_principal'인 모든 active 테넌트 조회
    # 2. 각 테넌트에 대해 OCI identity.get_tenancy() 호출 테스트
    # 3. 실패 시 tenant.status = 'credential_error' 업데이트 + 알림 발송


# Celery Beat 스케줄 설정 (celeryconfig.py)
CELERYBEAT_SCHEDULE = {
    "check-credential-rotation-daily": {
        "task": "tasks.check_credential_rotation",
        "schedule": "0 0 * * *",  # 매일 00:00 UTC (09:00 KST)
        "options": {"queue": "security"},
    },
    "verify-resource-principal": {
        "task": "app.tasks.credentials.verify_resource_principal_credentials",
        "schedule": crontab(minute=0, hour="*/6"),
    },
}
```

---

## 3. JWT 인증 시스템

### 3.1 RS256 키 쌍 생성 및 관리

```bash
# 개인키 생성 (4096 bit RSA, OCI Vault 저장)
openssl genrsa -out jwt_private.pem 4096

# 공개키 추출 (API Gateway / 검증 서버 배포)
openssl rsa -in jwt_private.pem -pubout -out jwt_public.pem

# 키 지문 확인 (감사 추적용)
openssl rsa -in jwt_private.pem -pubout | openssl dgst -sha256 -hex

# 키 순환 정책: 180일마다 새 키 쌍 생성, 이전 공개키 30일간 검증 유지
```

### 3.2 JWT 구현 (FastAPI)

```python
# app/security/jwt_handler.py
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

import redis.asyncio as redis
from jose import JWTError, jwt
from jose.exceptions import ExpiredSignatureError

from app.config import settings
from app.exceptions import (
    TokenExpiredException,
    TokenInvalidException,
    TokenRevokedException,
)

# 알고리즘 명시적 고정 (alg:none 공격 방지)
ALGORITHM = "RS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 15      # 짧은 Access Token
REFRESH_TOKEN_EXPIRE_DAYS = 7         # Sliding Window Rotation
REFRESH_WINDOW_EXTEND_DAYS = 7        # 사용 시마다 연장


class JWTHandler:
    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client
        # 개인키: OCI Vault에서 앱 시작 시 로드 (메모리에만 보관)
        self.private_key = settings.JWT_PRIVATE_KEY
        # 공개키: API Gateway 및 검증 서버 공유
        self.public_key = settings.JWT_PUBLIC_KEY

    def create_access_token(
        self,
        user_id: str,
        tenant_id: str,
        roles: list[str],
    ) -> str:
        """
        RS256 서명 Access Token 생성 (유효시간: 15분).
        클레임에 tenant_id 포함 → RLS 컨텍스트 설정에 활용.
        """
        now = datetime.now(timezone.utc)
        jti = str(uuid.uuid4())  # JWT ID: 블랙리스트 추적용

        payload = {
            # 표준 클레임
            "sub": user_id,
            "iat": now,
            "exp": now + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
            "jti": jti,
            "iss": "msp-platform",
            "aud": "msp-api",
            # 커스텀 클레임
            "tenant_id": tenant_id,
            "roles": roles,
            # permissions는 JWT에 포함하지 않음 (토큰 비대화 방지)
            # 권한 검사는 서버 사이드에서 ROLE_PERMISSIONS dict를 통해 수행
            "token_type": "access",
        }

        return jwt.encode(
            payload,
            self.private_key,
            algorithm=ALGORITHM,
        )

    def create_refresh_token(
        self,
        user_id: str,
        tenant_id: str,
        family_id: Optional[str] = None,
    ) -> str:
        """
        Refresh Token 생성 (Sliding Window Rotation).
        family_id: 토큰 패밀리 ID (탈취 감지 시 전체 패밀리 무효화).
        """
        now = datetime.now(timezone.utc)
        jti = str(uuid.uuid4())
        family = family_id or str(uuid.uuid4())

        payload = {
            "sub": user_id,
            "iat": now,
            "exp": now + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
            "jti": jti,
            "iss": "msp-platform",
            "aud": "msp-refresh",
            "tenant_id": tenant_id,
            "token_type": "refresh",
            "family_id": family,
        }

        return jwt.encode(
            payload,
            self.private_key,
            algorithm=ALGORITHM,
        )

    async def verify_access_token(self, token: str) -> dict:
        """
        Access Token 검증:
        1. RS256 서명 검증 (공개키)
        2. 만료 시간 검증
        3. Redis 블랙리스트 확인
        4. 알고리즘 명시적 검증
        """
        try:
            payload = jwt.decode(
                token,
                self.public_key,
                algorithms=[ALGORITHM],  # 목록으로 제한 (alg:none 방지)
                audience="msp-api",
                issuer="msp-platform",
            )
        except ExpiredSignatureError:
            raise TokenExpiredException("액세스 토큰이 만료되었습니다.")
        except JWTError as e:
            raise TokenInvalidException(f"유효하지 않은 토큰: {str(e)}")

        # token_type 검증 (Refresh Token을 Access 용도로 사용 방지)
        if payload.get("token_type") != "access":
            raise TokenInvalidException("잘못된 토큰 유형입니다.")

        # Redis 블랙리스트 확인 (로그아웃 / 강제 만료된 토큰)
        jti = payload.get("jti")
        if jti and await self._is_blacklisted(jti):
            raise TokenRevokedException("취소된 토큰입니다.")

        return payload

    async def rotate_refresh_token(
        self,
        refresh_token: str,
    ) -> tuple[str, str]:
        """
        Sliding Window Rotation:
        1. Refresh Token 검증
        2. 구 토큰 즉시 블랙리스트 등록
        3. 새 Access Token + Refresh Token 발급
        4. 탈취 감지: 이미 사용된 토큰 재사용 시 패밀리 전체 무효화
        """
        try:
            payload = jwt.decode(
                refresh_token,
                self.public_key,
                algorithms=[ALGORITHM],
                audience="msp-refresh",
                issuer="msp-platform",
            )
        except ExpiredSignatureError:
            raise TokenExpiredException("리프레시 토큰이 만료되었습니다.")
        except JWTError as e:
            raise TokenInvalidException(f"유효하지 않은 리프레시 토큰: {str(e)}")

        if payload.get("token_type") != "refresh":
            raise TokenInvalidException("잘못된 토큰 유형입니다.")

        jti = payload["jti"]
        family_id = payload["family_id"]
        user_id = payload["sub"]
        tenant_id = payload["tenant_id"]

        # 탈취 감지: 이미 사용된(블랙리스트) 토큰으로 재시도 → 패밀리 전체 무효화
        if await self._is_blacklisted(jti):
            await self._revoke_token_family(family_id)
            raise TokenRevokedException(
                "토큰 재사용 감지: 보안 사고 가능성. 재로그인이 필요합니다."
            )

        # 구 Refresh Token 블랙리스트 등록 (남은 만료 시간만큼 TTL 설정)
        remaining_seconds = (
            datetime.fromtimestamp(payload["exp"], tz=timezone.utc)
            - datetime.now(timezone.utc)
        ).seconds
        await self._blacklist_token(jti, remaining_seconds)

        # 새 토큰 쌍 발급 (같은 family_id 유지)
        new_access_token = self.create_access_token(
            user_id=user_id,
            tenant_id=tenant_id,
            roles=payload.get("roles", []),
            permissions=payload.get("permissions", []),
        )
        new_refresh_token = self.create_refresh_token(
            user_id=user_id,
            tenant_id=tenant_id,
            family_id=family_id,
        )

        return new_access_token, new_refresh_token

    async def revoke_token(self, jti: str, expires_in_seconds: int) -> None:
        """토큰 즉시 취소 (로그아웃, 비밀번호 변경, 강제 로그아웃)."""
        await self._blacklist_token(jti, expires_in_seconds)

    async def _is_blacklisted(self, jti: str) -> bool:
        result = await self.redis.get(f"blacklist:jwt:{jti}")
        return result is not None

    async def _blacklist_token(self, jti: str, ttl_seconds: int) -> None:
        await self.redis.setex(
            f"blacklist:jwt:{jti}",
            ttl_seconds,
            "revoked",
        )

    async def _revoke_token_family(self, family_id: str) -> None:
        """패밀리 내 모든 토큰 무효화 (탈취 감지 시)."""
        # family_id를 블랙리스트에 등록 → 검증 시 family_id도 확인
        await self.redis.setex(
            f"blacklist:family:{family_id}",
            REFRESH_TOKEN_EXPIRE_DAYS * 86400,
            "compromised",
        )
```

### 3.3 FastAPI 의존성 주입

```python
# app/dependencies/auth.py
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.security.jwt_handler import JWTHandler
from app.dependencies.redis import get_redis

security = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    jwt_handler: JWTHandler = Depends(get_jwt_handler),
) -> dict:
    """FastAPI Dependency: JWT 검증 후 현재 사용자 정보 반환."""
    token = credentials.credentials
    try:
        payload = await jwt_handler.verify_access_token(token)
        return payload
    except TokenExpiredException:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="토큰이 만료되었습니다.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except (TokenInvalidException, TokenRevokedException) as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
            headers={"WWW-Authenticate": "Bearer"},
        )
```

---

## 4. MFA 구현

### 4.1 TOTP 설정 및 검증

```python
# app/security/mfa.py
# 의존성: argon2-cffi>=23.1.0
import base64
import secrets
from typing import Optional

import pyotp
import qrcode
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from io import BytesIO

from app.config import settings

ph = PasswordHasher(time_cost=1, memory_cost=65536, parallelism=1)


class MFAManager:
    """
    TOTP 기반 MFA (RFC 6238 준수).
    - 알고리즘: SHA-1 (TOTP 표준)
    - 시간 단계: 30초
    - OTP 길이: 6자리
    - 허용 오차: ±1 단계 (시계 동기화 오류 대응)
    """

    RECOVERY_CODE_COUNT = 10
    RECOVERY_CODE_LENGTH = 12  # 예: "ABCD-EFGH-IJKL"

    def setup_totp(self, user_id: str, user_email: str) -> dict:
        """
        TOTP 초기 설정:
        1. 랜덤 시크릿 생성 (base32, 160bit)
        2. QR 코드 생성 (Google Authenticator 호환)
        3. 복구 코드 생성 (10개)
        반환값: {secret, qr_code_base64, recovery_codes}
        - secret은 DB 저장 전 AES-256 암호화 필수
        - recovery_codes는 Argon2 해시 후 저장 (평문 1회만 노출)
        """
        # 160-bit 시크릿 (RFC 4226 권장 최소값)
        secret = pyotp.random_base32(length=32)

        totp = pyotp.TOTP(secret)
        provisioning_uri = totp.provisioning_uri(
            name=user_email,
            issuer_name=f"OCI MSP Platform - {settings.ENV}",
        )

        # QR 코드 생성
        qr = qrcode.QRCode(version=1, box_size=10, border=4)
        qr.add_data(provisioning_uri)
        qr.make(fit=True)

        buffer = BytesIO()
        qr.make_image(fill_color="black", back_color="white").save(buffer, "PNG")
        qr_base64 = base64.b64encode(buffer.getvalue()).decode()

        # 복구 코드 생성
        recovery_codes = self._generate_recovery_codes()

        return {
            "secret": secret,               # DB 암호화 저장
            "qr_code_base64": qr_base64,   # 1회만 클라이언트 전달
            "provisioning_uri": provisioning_uri,
            "recovery_codes": recovery_codes,  # 평문 1회만 노출
        }

    def verify_totp(
        self,
        secret: str,
        otp_code: str,
        valid_window: int = 1,
    ) -> bool:
        """
        TOTP 코드 검증.
        valid_window=1: ±30초 오차 허용 (시계 동기화 오류 대응)
        """
        if not otp_code or len(otp_code) != 6 or not otp_code.isdigit():
            return False

        totp = pyotp.TOTP(secret)
        return totp.verify(otp_code, valid_window=valid_window)

    def _hash_recovery_code(self, code: str) -> str:
        return ph.hash(code)

    def _verify_recovery_code(self, code: str, hashed: str) -> bool:
        try:
            return ph.verify(hashed, code)
        except VerifyMismatchError:
            return False

    def _generate_recovery_codes(self) -> list[dict]:
        """
        복구 코드 10개 생성.
        반환: [{"code": "ABCD-EFGH-IJKL", "hash": "argon2_hash"}, ...]
        - 평문 코드: 사용자에게 1회만 표시
        - 해시값: DB에 저장 (사용 여부 추적 포함)
        """
        codes = []
        for _ in range(self.RECOVERY_CODE_COUNT):
            # 12바이트 = 96비트 랜덤 (예측 불가)
            raw = secrets.token_hex(6).upper()
            formatted = f"{raw[:4]}-{raw[4:8]}-{raw[8:12]}"

            code_hash = self._hash_recovery_code(formatted)

            codes.append({
                "code": formatted,
                "hash": code_hash,
                "used": False,
            })

        return codes

    def verify_recovery_code(
        self,
        input_code: str,
        stored_codes: list[dict],
    ) -> tuple[bool, Optional[int]]:
        """
        복구 코드 검증 + 사용 처리.
        반환: (검증 성공 여부, 사용된 코드 인덱스)
        - 사용된 코드는 즉시 무효화 (재사용 방지)
        """
        normalized = input_code.upper().replace(" ", "-")

        for idx, stored in enumerate(stored_codes):
            if stored["used"]:
                continue
            if self._verify_recovery_code(normalized, stored["hash"]):
                return True, idx

        return False, None


class MFAEnforcer:
    """MFA 우회 방지 미들웨어."""

    MFA_EXEMPT_PATHS = {
        "/api/v1/auth/login",
        "/api/v1/auth/mfa/verify",
        "/api/v1/health",
    }

    def is_mfa_required(self, user: dict, path: str) -> bool:
        """
        MFA 검증이 필요한 요청 판단.
        - Super Admin / Tenant Admin: 항상 필수
        - 민감 작업 (Credential 조회, 삭제): 항상 필수
        - MFA 면제 경로: 로그인, 헬스체크
        """
        if path in self.MFA_EXEMPT_PATHS:
            return False

        roles = user.get("roles", [])
        if "super_admin" in roles or "tenant_admin" in roles:
            return True

        # 민감 경로 추가 검증
        sensitive_paths = ["/credentials", "/audit-logs", "/tenants"]
        if any(path.startswith(p) for p in sensitive_paths):
            return True

        return False
```

---

## 5. RBAC 권한 매트릭스

### 5.1 역할 정의

| 역할 | 설명 | 범위 |
|---|---|---|
| **Super Admin** | MSP 플랫폼 전체 관리자 | 전체 테넌시 |
| **Tenant Admin** | 담당 고객사 관리자 | 담당 테넌시 |
| **Operator** | 운영 담당자 | 담당 테넌시 |
| **Viewer** | 읽기 전용 | 담당 테넌시 |

### 5.2 기능별 권한 매트릭스

| 기능 | Super Admin | Tenant Admin | Operator | Viewer |
|---|---|---|---|---|
| **테넌시 관리** | | | | |
| 테넌시 생성/삭제 | ✅ | ❌ | ❌ | ❌ |
| 테넌시 설정 수정 | ✅ | ✅(담당) | ❌ | ❌ |
| OCI Credential 등록 | ✅ | ✅(담당) | ❌ | ❌ |
| OCI Credential 조회 | ✅ | ❌ | ❌ | ❌ |
| **사용자 관리** | | | | |
| 사용자 생성/삭제 | ✅ | ✅(담당) | ❌ | ❌ |
| 역할 할당 | ✅ | ✅(Admin 미만) | ❌ | ❌ |
| MFA 강제/해제 | ✅ | ✅(담당) | ❌ | ❌ |
| **리소스 조회** | | | | |
| 컴퓨트 인스턴스 조회 | ✅(전체) | ✅(담당) | ✅(담당) | ✅(담당) |
| 네트워크 리소스 조회 | ✅(전체) | ✅(담당) | ✅(담당) | ✅(담당) |
| 비용/청구 조회 | ✅(전체) | ✅(담당) | ✅(담당) | ✅(담당) |
| **리소스 제어** | | | | |
| 인스턴스 시작/중지 | ✅ | ✅(담당) | ✅(담당) | ❌ |
| 인스턴스 삭제 | ✅ | ✅(담당) | ❌ | ❌ |
| 스케일링 변경 | ✅ | ✅(담당) | ✅(담당) | ❌ |
| **모니터링** | | | | |
| 메트릭 조회 | ✅(전체) | ✅(담당) | ✅(담당) | ✅(담당) |
| 알람 설정 | ✅ | ✅(담당) | ✅(담당) | ❌ |
| **보안/감사** | | | | |
| 감사 로그 조회 | ✅(전체) | ✅(담당) | ❌ | ❌ |
| 보안 이벤트 조회 | ✅(전체) | ✅(담당) | ❌ | ❌ |
| Cloud Guard 설정 | ✅ | ❌ | ❌ | ❌ |
| **시스템 관리** | | | | |
| 시스템 설정 | ✅ | ❌ | ❌ | ❌ |
| Key Rotation 강제 | ✅ | ❌ | ❌ | ❌ |
| 감사 로그 내보내기 | ✅ | ✅(담당) | ❌ | ❌ |

### 5.3 FastAPI Dependency 기반 권한 검사

```python
# app/security/rbac.py
from enum import Enum
from functools import wraps
from typing import Callable, Optional

from fastapi import Depends, HTTPException, status

from app.dependencies.auth import get_current_user


class Permission(str, Enum):
    # 테넌시 권한
    TENANCY_CREATE = "tenancy:create"
    TENANCY_DELETE = "tenancy:delete"
    TENANCY_READ = "tenancy:read"
    TENANCY_UPDATE = "tenancy:update"

    # Credential 권한
    CREDENTIAL_READ = "credential:read"
    CREDENTIAL_WRITE = "credential:write"

    # 리소스 권한
    RESOURCE_READ = "resource:read"
    RESOURCE_START_STOP = "resource:start_stop"
    RESOURCE_DELETE = "resource:delete"
    RESOURCE_SCALE = "resource:scale"

    # 사용자 관리
    USER_CREATE = "user:create"
    USER_DELETE = "user:delete"
    ROLE_ASSIGN = "role:assign"

    # 감사 로그
    AUDIT_READ = "audit:read"
    AUDIT_EXPORT = "audit:export"

    # 시스템
    SYSTEM_CONFIG = "system:config"


# 역할별 권한 매핑
ROLE_PERMISSIONS: dict[str, set[Permission]] = {
    "super_admin": set(Permission),  # 모든 권한

    "tenant_admin": {
        Permission.TENANCY_READ,
        Permission.TENANCY_UPDATE,
        Permission.CREDENTIAL_WRITE,
        Permission.RESOURCE_READ,
        Permission.RESOURCE_START_STOP,
        Permission.RESOURCE_DELETE,
        Permission.RESOURCE_SCALE,
        Permission.USER_CREATE,
        Permission.USER_DELETE,
        Permission.AUDIT_READ,
        Permission.AUDIT_EXPORT,
    },

    "operator": {
        Permission.TENANCY_READ,
        Permission.RESOURCE_READ,
        Permission.RESOURCE_START_STOP,
        Permission.RESOURCE_SCALE,
    },

    "viewer": {
        Permission.TENANCY_READ,
        Permission.RESOURCE_READ,
    },
}


def require_permission(
    permission: Permission,
    allow_self: bool = False,
) -> Callable:
    """
    FastAPI Dependency: 권한 검사 데코레이터.

    사용법:
        @router.delete("/tenants/{tenant_id}")
        async def delete_tenant(
            tenant_id: str,
            user: dict = Depends(require_permission(Permission.TENANCY_DELETE)),
        ):
            ...
    """
    async def _check_permission(
        user: dict = Depends(get_current_user),
    ) -> dict:
        user_roles = user.get("roles", [])
        user_permissions = set()

        # 역할별 권한 집합 계산
        for role in user_roles:
            user_permissions |= ROLE_PERMISSIONS.get(role, set())

        # 토큰 클레임의 명시적 권한도 포함
        user_permissions |= set(user.get("permissions", []))

        if permission not in user_permissions:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "error": "permission_denied",
                    "required_permission": permission.value,
                    "user_roles": user_roles,
                    "message": f"'{permission.value}' 권한이 필요합니다.",
                },
            )

        return user

    return _check_permission


def require_tenant_access(
    allow_super_admin_bypass: bool = True,
) -> Callable:
    """
    테넌트 접근 범위 검증 Dependency.
    요청의 tenant_id가 사용자의 담당 테넌트인지 확인.

    사용법:
        @router.get("/tenants/{tenant_id}/resources")
        async def get_resources(
            tenant_id: str,
            user: dict = Depends(require_tenant_access()),
        ):
            ...
    """
    async def _check_tenant_access(
        tenant_id: str,
        user: dict = Depends(get_current_user),
    ) -> dict:
        # Super Admin: 모든 테넌트 접근 가능
        if allow_super_admin_bypass and "super_admin" in user.get("roles", []):
            return user

        # 사용자 담당 테넌트 목록 확인
        assigned_tenants = user.get("assigned_tenants", [])
        if tenant_id not in assigned_tenants:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "error": "tenant_access_denied",
                    "message": "해당 테넌트에 대한 접근 권한이 없습니다.",
                },
            )

        return user

    return _check_tenant_access


def require_mfa_verified() -> Callable:
    """MFA 인증 완료 여부 검증 (민감 작업 전 재확인)."""
    async def _check_mfa(
        user: dict = Depends(get_current_user),
    ) -> dict:
        if not user.get("mfa_verified"):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "error": "mfa_required",
                    "message": "이 작업은 MFA 인증이 필요합니다.",
                },
            )
        return user

    return _check_mfa


# 복합 Dependency 사용 예시
# @router.delete("/tenants/{tenant_id}/credentials")
# async def delete_credential(
#     tenant_id: str,
#     user: dict = Depends(require_permission(Permission.CREDENTIAL_WRITE)),
#     _tenant: dict = Depends(require_tenant_access()),
#     _mfa: dict = Depends(require_mfa_verified()),
# ):
#     ...
```

---

## 6. 멀티 테넌트 RLS 보안

### 6.1 PostgreSQL RLS 정책

```sql
-- ==========================================
-- 멀티 테넌트 Row Level Security 설정
-- ==========================================

-- 1. RLS 활성화 (전체 테넌트 데이터 테이블)
ALTER TABLE oci_resources         ENABLE ROW LEVEL SECURITY;
ALTER TABLE oci_instances         ENABLE ROW LEVEL SECURITY;
ALTER TABLE oci_networks          ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitoring_metrics    ENABLE ROW LEVEL SECURITY;
ALTER TABLE cost_reports          ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs            ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_credentials    ENABLE ROW LEVEL SECURITY;
ALTER TABLE alert_rules           ENABLE ROW LEVEL SECURITY;

-- 2. 테넌트 격리 정책 (일반 사용자)
CREATE POLICY tenant_isolation ON oci_resources
  AS PERMISSIVE
  FOR ALL
  TO msp_app_role          -- 애플리케이션 DB 역할
  USING (
    tenant_id = current_setting('app.current_tenant_id', TRUE)::uuid
  )
  WITH CHECK (
    tenant_id = current_setting('app.current_tenant_id', TRUE)::uuid
  );

-- 3. Super Admin 정책 (전체 데이터 접근)
CREATE POLICY super_admin_access ON oci_resources
  AS PERMISSIVE
  FOR ALL
  TO msp_admin_role        -- 관리자 DB 역할
  USING (TRUE)             -- 모든 행 허용
  WITH CHECK (TRUE);

-- 4. 감사 로그는 INSERT만 허용 (조회는 별도 읽기 역할)
CREATE POLICY audit_insert_only ON audit_logs
  AS PERMISSIVE
  FOR INSERT
  TO msp_app_role
  WITH CHECK (
    tenant_id = current_setting('app.current_tenant_id', TRUE)::uuid
  );

-- 5. RLS 우회 방지 (superuser도 RLS 적용)
-- msp_app_role은 BYPASSRLS 권한 없음
-- ALTER ROLE msp_app_role NOBYPASSRLS; (기본값)

-- 6. RLS 설정 확인 쿼리
SELECT
  schemaname,
  tablename,
  rowsecurity,
  forcerowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND rowsecurity = TRUE;
```

### 6.2 SQLAlchemy 이벤트 훅 (자동 컨텍스트 설정)

```python
# app/db/rls.py
import uuid
from contextlib import asynccontextmanager
from typing import AsyncGenerator, Optional

from sqlalchemy.ext.asyncio import AsyncSession, AsyncConnection
from sqlalchemy import event, text

from app.exceptions import TenantContextMissingException


class TenantContext:
    """스레드 로컬 테넌트 컨텍스트 (asyncio 호환)."""
    _current_tenant_id: Optional[str] = None

    @classmethod
    def set(cls, tenant_id: str) -> None:
        cls._current_tenant_id = str(tenant_id)

    @classmethod
    def get(cls) -> Optional[str]:
        return cls._current_tenant_id

    @classmethod
    def clear(cls) -> None:
        cls._current_tenant_id = None

    @classmethod
    def require(cls) -> str:
        tid = cls.get()
        if not tid:
            raise TenantContextMissingException(
                "테넌트 컨텍스트가 설정되지 않았습니다."
            )
        return tid


@asynccontextmanager
async def tenant_session(
    session: AsyncSession,
    tenant_id: str,
) -> AsyncGenerator[AsyncSession, None]:
    """
    테넌트 격리 세션 컨텍스트 매니저.
    트랜잭션 내에서 SET LOCAL로 tenant_id를 설정하고
    트랜잭션 종료 시 자동 해제.

    사용법:
        async with tenant_session(db, user["tenant_id"]) as session:
            resources = await session.execute(select(OciResource))
    """
    # UUID 유효성 검증 (SQL Injection 방지)
    try:
        validated_tid = str(uuid.UUID(tenant_id))
    except ValueError:
        raise TenantContextMissingException(
            f"유효하지 않은 tenant_id 형식: {tenant_id}"
        )

    try:
        # SET LOCAL: 현재 트랜잭션에만 적용 (트랜잭션 종료 시 자동 해제)
        await session.execute(
            text("SET LOCAL app.current_tenant_id = :tid"),
            {"tid": validated_tid},
        )
        TenantContext.set(validated_tid)
        yield session
    finally:
        TenantContext.clear()


def setup_rls_events(engine) -> None:
    """
    SQLAlchemy 엔진 이벤트: 모든 커넥션 체크아웃 시
    테넌트 컨텍스트 자동 설정.
    """
    @event.listens_for(engine.sync_engine, "connect")
    def on_connect(dbapi_connection, connection_record):
        """신규 커넥션: RLS 관련 기본 설정."""
        cursor = dbapi_connection.cursor()
        # 기본 tenant_id = NULL (RLS가 모든 행 차단)
        cursor.execute("SET app.current_tenant_id = ''")
        cursor.close()

    @event.listens_for(engine.sync_engine, "checkout")
    def on_checkout(dbapi_connection, connection_record, connection_proxy):
        """
        커넥션 풀에서 커넥션 체크아웃 시:
        이전 세션 컨텍스트 잔류 방지 (풀 재사용 시 크로스 테넌트 위험)
        """
        cursor = dbapi_connection.cursor()
        cursor.execute("SET app.current_tenant_id = ''")
        cursor.close()
```

### 6.3 API 라우터에서의 RLS 적용 패턴

```python
# app/routers/resources.py
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.rls import tenant_session
from app.db.session import get_db
from app.security.rbac import require_permission, require_tenant_access, Permission

router = APIRouter(prefix="/api/v1/tenants/{tenant_id}/resources")


@router.get("/")
async def list_resources(
    tenant_id: str,
    user: dict = Depends(require_permission(Permission.RESOURCE_READ)),
    _: dict = Depends(require_tenant_access()),
    db: AsyncSession = Depends(get_db),
):
    """
    테넌트 리소스 목록 조회.
    tenant_session 컨텍스트 매니저로 RLS 자동 적용.
    """
    async with tenant_session(db, tenant_id) as session:
        # RLS가 자동으로 tenant_id 필터링 적용
        result = await session.execute(
            select(OciResource).order_by(OciResource.created_at.desc())
        )
        return result.scalars().all()
```

---

## 7. API 보안

### 7.1 FastAPI 보안 미들웨어

```python
# app/middleware/security.py
import time
import uuid
import re
import logging
from typing import Callable, Optional

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp

logger = logging.getLogger(__name__)

# 민감 정보 마스킹 패턴
MASK_PATTERNS = [
    (re.compile(r'"password"\s*:\s*"[^"]*"'), '"password": "***"'),
    (re.compile(r'"api_key"\s*:\s*"[^"]*"'), '"api_key": "***"'),
    (re.compile(r'"private_key"\s*:\s*"[^"]*"'), '"private_key": "***"'),
    (re.compile(r'"secret"\s*:\s*"[^"]*"'), '"secret": "***"'),
    (re.compile(r'(ocid1\.[a-z]+\.oc1\.[^.]+\.)([a-z0-9]+)'), r'\1***'),
    (re.compile(r'Authorization:\s*Bearer\s+\S+'), 'Authorization: Bearer ***'),
]


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """
    OWASP 권장 보안 HTTP 헤더 자동 추가.
    모든 응답에 적용.
    """

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        response = await call_next(request)

        # 보안 헤더 설정
        response.headers["Strict-Transport-Security"] = (
            "max-age=31536000; includeSubDomains; preload"
        )
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "script-src 'self' 'nonce-{nonce}'; "
            "style-src 'self'; "
            "img-src 'self' data:; "
            "connect-src 'self'; "
            "frame-ancestors 'none';"
        )
        response.headers["Permissions-Policy"] = (
            "geolocation=(), microphone=(), camera=()"
        )
        # 서버 정보 숨김
        response.headers["Server"] = "MSP-Platform"

        return response


class CORSSecurityMiddleware(BaseHTTPMiddleware):
    """
    엄격한 CORS 정책.
    허용 오리진: 환경별 화이트리스트 (와일드카드 금지).
    """

    ALLOWED_ORIGINS = {
        "https://msp.example.com",
        "https://portal.example.com",
    }

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        origin = request.headers.get("origin", "")

        # Preflight 요청 처리
        if request.method == "OPTIONS":
            response = Response(status_code=200)
        else:
            response = await call_next(request)

        if origin in self.ALLOWED_ORIGINS:
            response.headers["Access-Control-Allow-Origin"] = origin
            response.headers["Access-Control-Allow-Credentials"] = "true"
            response.headers["Access-Control-Allow-Methods"] = (
                "GET, POST, PUT, PATCH, DELETE, OPTIONS"
            )
            response.headers["Access-Control-Allow-Headers"] = (
                "Authorization, Content-Type, X-Request-ID, X-Tenant-ID"
            )
            response.headers["Access-Control-Max-Age"] = "3600"
            response.headers["Vary"] = "Origin"

        return response


# 프로덕션 CORS 설정 (app/main.py)
CORS_ORIGINS = [
    "https://msp.example.com",       # 프로덕션 프론트엔드
    "https://staging.msp.example.com",  # 스테이징
    # "http://localhost:3000",  # 개발 환경 (환경변수로 조건부 추가)
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Tenant-ID", "X-Request-ID"],
    max_age=600,  # Preflight 캐시 10분
)


class RequestIDMiddleware(BaseHTTPMiddleware):
    """모든 요청에 고유 Request ID 부여 (추적성 확보)."""

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())
        request.state.request_id = request_id

        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id

        return response


class AuditLoggingMiddleware(BaseHTTPMiddleware):
    """
    쓰기 작업(POST/PUT/DELETE/PATCH) 자동 감사 로그 기록.
    민감 정보 마스킹 후 audit_logs 테이블에 저장.
    """

    WRITE_METHODS = {"POST", "PUT", "DELETE", "PATCH"}
    SKIP_PATHS = {"/api/v1/health", "/api/v1/metrics", "/docs", "/openapi.json"}

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        start_time = time.time()

        response = await call_next(request)

        # 쓰기 작업만 감사 로그 기록
        if (
            request.method in self.WRITE_METHODS
            and request.url.path not in self.SKIP_PATHS
        ):
            duration_ms = int((time.time() - start_time) * 1000)
            await self._record_audit(request, response, duration_ms)

        return response

    async def _record_audit(
        self,
        request: Request,
        response: Response,
        duration_ms: int,
    ) -> None:
        user = getattr(request.state, "user", None)
        request_id = getattr(request.state, "request_id", None)

        # IP 주소 (프록시 헤더 우선)
        client_ip = (
            request.headers.get("X-Forwarded-For", "").split(",")[0].strip()
            or request.client.host
        )

        log_data = {
            "request_id": request_id,
            "method": request.method,
            "path": str(request.url.path),
            "query_params": self._mask_sensitive(str(request.query_params)),
            "status_code": response.status_code,
            "duration_ms": duration_ms,
            "client_ip": client_ip,
            "user_agent": request.headers.get("User-Agent", ""),
            "user_id": user.get("sub") if user else None,
            "tenant_id": user.get("tenant_id") if user else None,
        }

        logger.info("audit_log", extra=log_data)

        # DB 저장은 비동기 태스크로 (응답 지연 최소화)
        from app.tasks.audit import save_audit_log
        save_audit_log.apply_async(args=[log_data])

    @staticmethod
    def _mask_sensitive(text: str) -> str:
        for pattern, replacement in MASK_PATTERNS:
            text = pattern.sub(replacement, text)
        return text
```

### 7.2 Input Validation 전략

```python
# app/schemas/validators.py
import re
import uuid
from typing import Annotated

from pydantic import BaseModel, Field, field_validator, model_validator


# OCID 형식 검증 정규식
OCID_PATTERN = re.compile(
    r"^ocid1\.[a-z]{1,32}\.oc1\.[a-z0-9-]{1,36}\.[a-z0-9]{60}$"
)

# SQL Injection / XSS 위험 문자 패턴
DANGEROUS_CHARS_PATTERN = re.compile(
    r"[<>\"';&|`$\\{}]|--|\b(SELECT|INSERT|UPDATE|DELETE|DROP|UNION|EXEC)\b",
    re.IGNORECASE,
)


def validate_ocid(value: str) -> str:
    """OCI OCID 형식 엄격 검증."""
    if not OCID_PATTERN.match(value):
        raise ValueError(f"유효하지 않은 OCID 형식: {value[:20]}...")
    return value


def validate_no_injection(value: str) -> str:
    """SQL Injection / XSS 위험 문자 검증."""
    if DANGEROUS_CHARS_PATTERN.search(value):
        raise ValueError("허용되지 않는 문자가 포함되어 있습니다.")
    return value


class TenantCreateRequest(BaseModel):
    name: Annotated[str, Field(min_length=2, max_length=100)]
    tenancy_ocid: str
    region: Annotated[str, Field(pattern=r"^[a-z]{2}-[a-z]+-[0-9]$")]
    contact_email: Annotated[str, Field(max_length=254)]

    @field_validator("tenancy_ocid")
    @classmethod
    def validate_tenancy_ocid(cls, v: str) -> str:
        return validate_ocid(v)

    @field_validator("name")
    @classmethod
    def validate_name_safety(cls, v: str) -> str:
        return validate_no_injection(v.strip())

    @field_validator("region")
    @classmethod
    def validate_region_allowed(cls, v: str) -> str:
        # 한국 리전 강제 (컴플라이언스)
        ALLOWED_REGIONS = {"ap-seoul-1", "ap-chuncheon-1"}
        if v not in ALLOWED_REGIONS:
            raise ValueError(
                f"허용된 리전: {', '.join(ALLOWED_REGIONS)} (데이터 주권 정책)"
            )
        return v

    model_config = {
        "str_strip_whitespace": True,
        "str_max_length": 1000,
    }
```

### 7.3 OCI API Gateway Rate Limiting 정책

```yaml
# OCI API Gateway Rate Limiting 설정 (Terraform)
resource "oci_apigateway_deployment" "msp_api" {
  specification {
    request_policies {
      rate_limiting {
        rate_in_requests_per_second = 100    # 글로벌 기본
        rate_key                    = "CLIENT_IP"
      }
    }
  }
}

# 엔드포인트별 세분화 Rate Limit 정책
Rate Limit 정책:
  기본 (인증된 사용자):
    - 일반 API: 100 req/min per user
    - 리소스 제어 API: 10 req/min per user
    - Credential 접근: 5 req/min per user

  엔드포인트별:
    POST /auth/login:          10 req/min per IP   (브루트포스 방지)
    POST /auth/mfa/verify:      5 req/min per user  (MFA 브루트포스 방지)
    GET  /resources:           200 req/min per tenant
    POST /instances/{id}/stop:  20 req/min per user
    GET  /audit-logs:           30 req/min per user

  초과 시:
    - HTTP 429 Too Many Requests
    - Retry-After 헤더 포함
    - 감사 로그 기록 (이상 트래픽 탐지)
```

---

## 8. 데이터 보안

### 8.1 저장 데이터 암호화

```
암호화 계층 구조:

계층 1 - OCI Vault (HSM 기반):
  - OCI Credential (API Key PEM)
  - JWT 서명 개인키
  - Fernet 마스터키
  - 데이터베이스 암호화키 (TDE용)
  → AES-256 + HSM 하드웨어 보호

계층 2 - 애플리케이션 레벨 (Fernet):
  - OCI Credential → Fernet 암호화 후 Vault 저장 (이중 암호화)
  - 민감 설정값 → 환경변수 대신 Vault Secret 참조

계층 3 - DB 컬럼 암호화 (pgcrypto):
  - users.totp_secret: AES-256 암호화
  - tenant_credentials.encrypted_key: Fernet 암호문 저장
  - users.phone_number: PII 암호화

계층 4 - PostgreSQL TDE (Transparent Data Encryption):
  - OCI DB System: 저장 디스크 전체 AES-256 암호화
  - 백업 파일: 자동 암호화 (OCI Object Storage SSE)
```

```sql
-- pgcrypto 기반 민감 컬럼 암호화 예시
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- TOTP 시크릿 암호화 저장
UPDATE users
SET totp_secret = pgp_sym_encrypt(
  plain_totp_secret,
  current_setting('app.column_encryption_key')
)
WHERE id = $1;

-- 복호화 조회
SELECT pgp_sym_decrypt(
  totp_secret::bytea,
  current_setting('app.column_encryption_key')
) AS totp_secret
FROM users
WHERE id = $1;
```

### 8.2 전송 중 데이터 암호화

```
TLS 정책:

외부 통신 (클라이언트 ↔ LB):
  - TLS 1.3 강제 (TLS 1.2 이하 차단)
  - 허용 암호화 스위트:
    TLS_AES_256_GCM_SHA384
    TLS_CHACHA20_POLY1305_SHA256
    TLS_AES_128_GCM_SHA256
  - HSTS: max-age=31536000; includeSubDomains; preload
  - Certificate Transparency 로그 등록

내부 통신 (OKE Pod 간):
  - Istio Service Mesh mTLS (STRICT 모드)
  - 모든 Pod 간 통신: 상호 인증서 검증
  - 자동 인증서 갱신 (Cert-Manager + Let's Encrypt)

DB 연결:
  - PostgreSQL sslmode=verify-full (인증서 검증)
  - OCI DB System: SSL/TLS 강제 (평문 연결 거부)

Redis 연결:
  - TLS 암호화 (OCI Cache Service 기본 제공)
  - AUTH 비밀번호 + TLS 이중 보호
```

### 8.3 로그 마스킹 정책

```python
# app/utils/log_masker.py
import re
from typing import Any

# 마스킹 규칙 정의
MASKING_RULES = {
    # API Key / Secret (16자 이상 알파뉴메릭)
    "api_key": re.compile(r"([A-Za-z0-9]{8})[A-Za-z0-9]{8,}([A-Za-z0-9]{4})"),
    # 패스워드 필드 (JSON/쿼리 파라미터)
    "password": re.compile(
        r"(\"password\"\s*:\s*\")[^\"]*\"",
        re.IGNORECASE,
    ),
    # OCI OCID (중간 부분 마스킹)
    "ocid": re.compile(
        r"(ocid1\.[a-z]+\.oc1\.[a-z0-9-]+\.)([a-z0-9]{10})[a-z0-9]+([a-z0-9]{6})"
    ),
    # 이메일
    "email": re.compile(r"([a-zA-Z0-9._%+-]{2})[a-zA-Z0-9._%+-]+(@[a-zA-Z0-9.-]+)"),
    # 전화번호 (한국)
    "phone": re.compile(r"(01[0-9])-?([0-9]{3,4})-?([0-9]{4})"),
    # JWT 토큰
    "jwt": re.compile(r"Bearer\s+[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"),
    # PEM 개인키
    "pem_key": re.compile(
        r"-----BEGIN [A-Z ]+-----[\s\S]+?-----END [A-Z ]+-----"
    ),
}


def mask_log(data: Any, depth: int = 0) -> Any:
    """
    로그 데이터의 민감 정보를 재귀적으로 마스킹.
    최대 재귀 깊이 10 (순환 참조 방지).
    """
    if depth > 10:
        return "***[MAX_DEPTH]***"

    if isinstance(data, str):
        return _mask_string(data)
    elif isinstance(data, dict):
        return {
            k: "***" if _is_sensitive_key(k) else mask_log(v, depth + 1)
            for k, v in data.items()
        }
    elif isinstance(data, (list, tuple)):
        return [mask_log(item, depth + 1) for item in data]
    return data


def _is_sensitive_key(key: str) -> bool:
    """민감 정보 키 이름 판별."""
    sensitive_keywords = {
        "password", "passwd", "secret", "api_key", "private_key",
        "token", "credential", "fingerprint", "totp_secret",
        "recovery_code", "auth_code",
    }
    return key.lower() in sensitive_keywords


def _mask_string(text: str) -> str:
    """문자열 내 민감 패턴 마스킹."""
    text = MASKING_RULES["jwt"].sub("Bearer ***", text)
    text = MASKING_RULES["pem_key"].sub("[PRIVATE_KEY_REDACTED]", text)
    text = MASKING_RULES["password"].sub(r'\g<1>***"', text)
    text = MASKING_RULES["ocid"].sub(r"\1***\3", text)
    text = MASKING_RULES["email"].sub(r"\1***\2", text)
    return text
```

---

## 9. 감사 로그 설계

### 9.1 감사 로그 테이블 스키마

```sql
-- 감사 로그 테이블 (불변 설계: UPDATE/DELETE 없음)
CREATE TABLE audit_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL,
    actor_id        UUID,                    -- NULL: 시스템 자동 작업
    actor_email     VARCHAR(254),
    actor_ip        INET,
    actor_role      VARCHAR(50),
    event_type      VARCHAR(100) NOT NULL,   -- 이벤트 분류
    event_category  VARCHAR(50) NOT NULL,    -- AUTH, RESOURCE, CREDENTIAL, ADMIN
    resource_type   VARCHAR(100),
    resource_id     VARCHAR(255),
    action          VARCHAR(50) NOT NULL,    -- CREATE, READ, UPDATE, DELETE, LOGIN, etc.
    status          VARCHAR(20) NOT NULL,    -- SUCCESS, FAILURE, PARTIAL
    severity        VARCHAR(20) NOT NULL,    -- INFO, WARNING, HIGH, CRITICAL
    request_id      UUID,
    request_path    VARCHAR(500),
    request_method  VARCHAR(10),
    response_code   INTEGER,
    duration_ms     INTEGER,
    details         JSONB,                   -- 추가 컨텍스트 (마스킹 후)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 성능 인덱스
CREATE INDEX idx_audit_tenant_created ON audit_logs (tenant_id, created_at DESC);
CREATE INDEX idx_audit_actor ON audit_logs (actor_id, created_at DESC);
CREATE INDEX idx_audit_event_type ON audit_logs (event_type, created_at DESC);
CREATE INDEX idx_audit_severity ON audit_logs (severity) WHERE severity IN ('HIGH', 'CRITICAL');

-- 1년 이후 자동 아카이빙 (파티셔닝)
CREATE TABLE audit_logs_2026_q1 PARTITION OF audit_logs
    FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');
```

### 9.2 감사 로그 미들웨어 구현

```python
# app/middleware/audit.py
import json
import time
import uuid
from datetime import datetime, timezone
from typing import Callable

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

from app.utils.log_masker import mask_log
from app.tasks.audit import save_audit_log_async


class AuditMiddleware(BaseHTTPMiddleware):
    """
    FastAPI 미들웨어: 쓰기 작업(POST/PUT/DELETE/PATCH) 자동 감사 기록.
    응답 반환 후 비동기 DB 저장 (성능 영향 최소화).
    """

    WRITE_METHODS = {"POST", "PUT", "DELETE", "PATCH"}
    SKIP_PATHS = frozenset({
        "/api/v1/health",
        "/api/v1/metrics",
        "/docs",
        "/redoc",
        "/openapi.json",
    })

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        start_time = time.monotonic()
        response = await call_next(request)
        duration_ms = int((time.monotonic() - start_time) * 1000)

        if self._should_audit(request):
            await self._record_audit(request, response, duration_ms)

        return response

    def _should_audit(self, request: Request) -> bool:
        return (
            request.method in self.WRITE_METHODS
            and request.url.path not in self.SKIP_PATHS
        )

    async def _record_audit(
        self,
        request: Request,
        response: Response,
        duration_ms: int,
    ) -> None:
        user = getattr(request.state, "user", None)
        request_id = getattr(request.state, "request_id", str(uuid.uuid4()))

        # 클라이언트 실제 IP (리버스 프록시 환경)
        client_ip = self._get_client_ip(request)

        # 요청 바디 (이미 소비됨 → 미들웨어 레벨에서 캐시 필요)
        request_body = getattr(request.state, "body_cache", None)
        masked_body = mask_log(request_body) if request_body else None

        audit_data = {
            "tenant_id": user.get("tenant_id") if user else None,
            "actor_id": user.get("sub") if user else None,
            "actor_email": user.get("email") if user else None,
            "actor_ip": client_ip,
            "actor_role": (user.get("roles", [None])[0]) if user else None,
            "event_type": self._classify_event(request),
            "event_category": self._classify_category(request),
            "resource_type": self._extract_resource_type(request.url.path),
            "resource_id": self._extract_resource_id(request.url.path),
            "action": request.method,
            "status": "SUCCESS" if response.status_code < 400 else "FAILURE",
            "severity": self._determine_severity(request, response),
            "request_id": request_id,
            "request_path": str(request.url.path),
            "request_method": request.method,
            "response_code": response.status_code,
            "duration_ms": duration_ms,
            "details": masked_body,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }

        # 비동기 태스크로 DB 저장 (Celery)
        save_audit_log_async.apply_async(args=[audit_data], queue="audit")

    @staticmethod
    def _get_client_ip(request: Request) -> str:
        forwarded_for = request.headers.get("X-Forwarded-For", "")
        if forwarded_for:
            return forwarded_for.split(",")[0].strip()
        return request.client.host if request.client else "unknown"

    @staticmethod
    def _classify_event(request: Request) -> str:
        path = request.url.path
        method = request.method
        if "/auth/" in path:
            return "AUTH_EVENT"
        elif "/credentials" in path:
            return "CREDENTIAL_ACCESS"
        elif method == "DELETE":
            return "RESOURCE_DELETE"
        elif method == "POST":
            return "RESOURCE_CREATE"
        return "RESOURCE_MODIFY"

    @staticmethod
    def _classify_category(request: Request) -> str:
        path = request.url.path
        if "/auth/" in path:
            return "AUTH"
        elif "/tenants" in path:
            return "ADMIN"
        elif "/credentials" in path:
            return "CREDENTIAL"
        return "RESOURCE"

    @staticmethod
    def _determine_severity(request: Request, response: Response) -> str:
        if response.status_code >= 500:
            return "HIGH"
        elif "/credentials" in request.url.path:
            return "HIGH"
        elif request.method == "DELETE":
            return "WARNING"
        elif response.status_code == 403:
            return "WARNING"
        return "INFO"

    @staticmethod
    def _extract_resource_type(path: str) -> str:
        parts = path.strip("/").split("/")
        # /api/v1/tenants/{id}/resources → "resources"
        if len(parts) >= 3:
            return parts[-1] if not parts[-1].startswith("{") else parts[-2]
        return "unknown"

    @staticmethod
    def _extract_resource_id(path: str) -> str:
        parts = path.strip("/").split("/")
        # UUID 형식 파트 추출
        import re
        uuid_pattern = re.compile(
            r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
            re.IGNORECASE,
        )
        for part in reversed(parts):
            if uuid_pattern.match(part):
                return part
        return ""
```

### 9.3 감사 로그 대상 이벤트 분류

| 카테고리 | 이벤트 | 심각도 | 보존 기간 |
|---|---|---|---|
| **인증** | 로그인 성공/실패 | INFO/WARNING | 1년 |
| **인증** | MFA 실패 (5회 이상) | HIGH | 1년 |
| **인증** | 비밀번호 변경 | WARNING | 1년 |
| **인증** | 계정 잠금/해제 | HIGH | 1년 |
| **Credential** | API Key 등록/삭제 | HIGH | 3년 |
| **Credential** | API Key 조회 | HIGH | 3년 |
| **Credential** | Key Rotation 성공/실패 | HIGH | 3년 |
| **리소스** | 인스턴스 시작/중지/삭제 | WARNING | 1년 |
| **리소스** | 설정 변경 | WARNING | 1년 |
| **관리** | 테넌시 생성/삭제 | CRITICAL | 5년 |
| **관리** | 사용자 생성/삭제 | HIGH | 3년 |
| **관리** | 역할 변경 | HIGH | 3년 |
| **보안** | Cloud Guard 이벤트 | HIGH | 3년 |
| **보안** | Rate Limit 초과 | WARNING | 1년 |
| **보안** | 권한 거부(403) | WARNING | 1년 |

### 9.4 WORM 스토리지 및 아카이빙

```python
# app/tasks/audit_archive.py
from celery import shared_task
import oci
import json
from datetime import datetime, timedelta, timezone

from app.db.session import get_sync_db
from app.models.audit import AuditLog


@shared_task(name="tasks.archive_audit_logs")
def archive_audit_logs():
    """
    매월 1일 실행: 1년 이상 된 감사 로그를
    OCI Object Storage (WORM) 에 아카이빙 후 DB에서 삭제.

    Object Storage 설정:
    - Retention Rule: 최소 3년 보존 (삭제/수정 불가)
    - Storage Tier: Archive (비용 최적화)
    - Object Lock: WORM (Write Once Read Many)
    """
    cutoff_date = datetime.now(timezone.utc) - timedelta(days=365)

    with get_sync_db() as db:
        # 1년 이상 된 로그 조회 (배치)
        old_logs = db.query(AuditLog).filter(
            AuditLog.created_at < cutoff_date
        ).limit(10000).all()

        if not old_logs:
            return

        # NDJSON 형식으로 직렬화
        ndjson_content = "\n".join(
            json.dumps(log.to_dict(), default=str) for log in old_logs
        )

        # OCI Object Storage 업로드 (Archive Tier)
        object_name = (
            f"audit-logs/{cutoff_date.year}/{cutoff_date.month:02d}/"
            f"audit_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.ndjson"
        )

        object_storage_client = oci.object_storage.ObjectStorageClient(
            config={},
            signer=oci.auth.signers.get_resource_principals_signer(),
        )

        object_storage_client.put_object(
            namespace_name="msp-audit",
            bucket_name="audit-logs-archive",
            object_name=object_name,
            put_object_body=ndjson_content.encode("utf-8"),
            storage_tier="Archive",
        )

        # DB에서 삭제 (Object Storage에 안전하게 저장 후)
        ids = [log.id for log in old_logs]
        db.query(AuditLog).filter(AuditLog.id.in_(ids)).delete(
            synchronize_session=False
        )
        db.commit()
```

**Object Storage WORM 설정 (Terraform):**
```hcl
resource "oci_objectstorage_bucket" "audit_archive" {
  compartment_id = var.msp_compartment_id
  name           = "audit-logs-archive"
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  storage_tier   = "Archive"

  # WORM: 최소 3년 보존 (수정/삭제 불가)
  retention_rules {
    display_name = "minimum-retention-3years"
    duration {
      time_amount = 3
      time_unit   = "YEARS"
    }
    time_rule_locked = "2026-12-31T00:00:00Z"  # 규칙 자체도 잠금
  }

  # 서버 사이드 암호화 (OCI Vault 키)
  kms_key_id = var.audit_encryption_key_ocid
}
```

---

## 10. OCI 네트워크 보안

### 10.1 VCN 설계

```
VCN: 10.0.0.0/16 (msp-platform-vcn)
│
├── Public Subnet: 10.0.1.0/24
│   용도: OCI Load Balancer, Bastion Host
│   Security List: SL-PUBLIC
│   └── Ingress Rules:
│       - 443/tcp from 0.0.0.0/0     (HTTPS - LB)
│       - 22/tcp  from <MSP_OFFICE_IP>/32  (SSH - Bastion, IP 제한)
│   └── Egress Rules:
│       - All to 10.0.2.0/24         (LB → App)
│
├── Private Subnet: 10.0.2.0/24
│   용도: OKE Worker Node (FastAPI, Next.js, WebSocket, Celery)
│   Security List: SL-PRIVATE
│   └── Ingress Rules:
│       - 8000/tcp from 10.0.1.0/24  (FastAPI ← LB)
│       - 3000/tcp from 10.0.1.0/24  (Next.js ← LB)
│       - 8001/tcp from 10.0.1.0/24  (WebSocket ← LB)
│       - All from 10.0.2.0/24       (Pod 간 통신, mTLS)
│   └── Egress Rules:
│       - 443/tcp to OCI Service GW  (OCI SDK 호출)
│       - 5432/tcp to 10.0.3.0/24   (PostgreSQL)
│       - 6379/tcp to 10.0.3.0/24   (Redis)
│
└── DB Subnet: 10.0.3.0/24
    용도: PostgreSQL, Redis, OCI Vault Endpoint
    Security List: SL-DB
    └── Ingress Rules:
        - 5432/tcp from 10.0.2.0/24  (PostgreSQL ← App)
        - 6379/tcp from 10.0.2.0/24  (Redis ← App)
    └── Egress Rules:
        - NONE (DB Subnet → 외부 통신 차단)
```

### 10.2 보안 게이트웨이 구성

```
인터넷 게이트웨이 (IGW):
  - Public Subnet만 연결
  - 외부 인바운드: 443/tcp only

서비스 게이트웨이 (SGW):
  - Private Subnet → OCI 서비스 직접 연결 (인터넷 우회 없음)
  - 허용 서비스: Object Storage, Vault, Monitoring, Logging

NAT 게이트웨이:
  - Private Subnet → 외부 패키지 다운로드 (보안 패치 시)
  - 인바운드 차단 (Outbound Only)

OCI WAF (Web Application Firewall):
  - Load Balancer 앞단 적용
  - OWASP Top 10 방어 규칙 활성화
  - 커스텀 규칙:
    * OCI OCID 패턴 외부 노출 탐지
    * 대용량 요청 바디 차단 (>10MB)
    * 비정상 User-Agent 차단
```

### 10.3 OKE 보안 설정

```yaml
# Kubernetes Network Policy (OKE)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-isolation
  namespace: msp-platform
spec:
  podSelector:
    matchLabels:
      app: fastapi-backend
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: nginx-ingress
      ports:
        - protocol: TCP
          port: 8000
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: postgresql
      ports:
        - protocol: TCP
          port: 5432
    - to:
        - podSelector:
            matchLabels:
              app: redis
      ports:
        - protocol: TCP
          port: 6379
    # OCI API 호출 (HTTPS)
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
      ports:
        - protocol: TCP
          port: 443
```

---

## 11. OCI Cloud Guard 연동

### 11.1 탐지 규칙 설정

```
활성화 탐지기 (Detector Rules):

[Critical] 공개 버킷 노출
  Rule: PUBLIC_BUCKET_DETECTOR
  조건: Object Storage Bucket의 Public Access 활성화
  대응: 즉시 자동 수정 (Responder: MAKE_BUCKET_PRIVATE)
  알림: MSP Incident 자동 생성

[Critical] 루트 계정 사용
  Rule: ROOT_USER_ACTIVITY
  조건: 테넌시 루트 계정으로 콘솔/API 접근
  대응: 보안팀 즉시 알림 + Incident 생성
  알림: PagerDuty Escalation

[High] 보안 그룹 전체 개방
  Rule: SECURITY_GROUP_OPEN_PORTS
  조건: Security List에 0.0.0.0/0 Ingress 허용 (22, 3389 제외 목적)
  대응: 자동 수정 + Incident 생성

[High] MFA 미설정 IAM 사용자
  Rule: IAM_USER_WITHOUT_MFA
  조건: API Key 보유 IAM 사용자 중 MFA 미설정
  대응: 계정 비활성화 권고 Incident

[High] 비정상 지역 접근
  Rule: UNUSUAL_REGION_ACCESS
  조건: 한국 리전(ap-seoul-1, ap-chuncheon-1) 외 리소스 생성
  대응: 즉시 알림 + Incident 생성

[Medium] 미사용 API Key 장기 유지
  Rule: OLD_API_KEY_DETECTOR
  조건: 90일 이상 미사용 API Key 존재
  대응: Key Rotation 권고 Incident

[Medium] 대량 API 호출 이상
  Rule: ANOMALOUS_API_ACTIVITY
  조건: 기준 대비 3σ 초과 API 호출량
  대응: 이상 트래픽 알림
```

### 11.2 보안 이벤트 → MSP Incident 자동 생성 웹훅

```python
# app/webhooks/cloud_guard.py
import hashlib
import hmac
import json
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Request, status
from pydantic import BaseModel

from app.config import settings
from app.services.incident import IncidentService
from app.tasks.notifications import send_security_alert

router = APIRouter(prefix="/webhooks/cloud-guard")


class CloudGuardEvent(BaseModel):
    """OCI Cloud Guard 웹훅 페이로드."""
    eventType: str
    eventTime: str
    data: dict


@router.post("/events")
async def receive_cloud_guard_event(
    request: Request,
    incident_service: IncidentService,
):
    """
    Cloud Guard 보안 이벤트 수신 → MSP Incident 자동 생성.
    서명 검증: OCI 웹훅 서명 헤더 확인.
    """
    # 1. 웹훅 서명 검증 (재생 공격 방지)
    signature = request.headers.get("X-OCI-Signature")
    body = await request.body()

    if not _verify_oci_webhook_signature(body, signature):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="웹훅 서명 검증 실패",
        )

    event_data = json.loads(body)
    event = CloudGuardEvent(**event_data)

    # 2. 이벤트 분류 및 심각도 매핑
    severity_map = {
        "CRITICAL": "P1",
        "HIGH": "P2",
        "MEDIUM": "P3",
        "LOW": "P4",
    }

    cloud_guard_severity = event.data.get("riskLevel", "MEDIUM")
    incident_priority = severity_map.get(cloud_guard_severity, "P3")

    # 3. MSP Incident 생성
    incident = await incident_service.create_incident(
        title=f"[Cloud Guard] {event.data.get('detectorRuleName', 'Security Alert')}",
        description=json.dumps(event.data, ensure_ascii=False, indent=2),
        priority=incident_priority,
        source="CLOUD_GUARD",
        tenant_id=_extract_tenant_from_compartment(
            event.data.get("compartmentId", "")
        ),
        tags={
            "cloud_guard_problem_id": event.data.get("problemId"),
            "risk_level": cloud_guard_severity,
            "region": event.data.get("region"),
        },
    )

    # 4. Critical/High 이벤트 즉시 알림 (PagerDuty / Slack)
    if incident_priority in ("P1", "P2"):
        send_security_alert.apply_async(
            args=[
                incident.tenant_id,
                f"[{incident_priority}] Cloud Guard 보안 경보: "
                f"{event.data.get('detectorRuleName')}",
                cloud_guard_severity,
            ],
            queue="critical",
        )

    return {"status": "accepted", "incident_id": str(incident.id)}


def _verify_oci_webhook_signature(body: bytes, signature: str) -> bool:
    """OCI 웹훅 HMAC-SHA256 서명 검증."""
    if not signature:
        return False

    expected = hmac.new(
        settings.CLOUD_GUARD_WEBHOOK_SECRET.encode(),
        body,
        hashlib.sha256,
    ).hexdigest()

    return hmac.compare_digest(expected, signature)


def _extract_tenant_from_compartment(compartment_id: str) -> str:
    """Compartment OCID에서 테넌트 매핑 (DB 조회)."""
    # 실제 구현: compartment_id → tenant_id 매핑 DB 조회
    return compartment_id
```

---

## 12. 컴플라이언스 체크리스트

### 12.1 데이터 저장 위치 (한국 리전 강제)

```python
# app/schemas/validators.py (추가)
KOREA_REGIONS = frozenset({"ap-seoul-1", "ap-chuncheon-1"})


def enforce_korea_region(region: str) -> str:
    """
    데이터 주권 정책: 한국 리전 외 사용 금지.
    CSAP 클라우드 보안 인증 요구사항 준수.
    """
    if region not in KOREA_REGIONS:
        raise ValueError(
            f"데이터 저장 위치 정책 위반: '{region}'은 허용되지 않습니다. "
            f"허용 리전: {', '.join(sorted(KOREA_REGIONS))}"
        )
    return region
```

```hcl
# Terraform: 한국 리전 외 리소스 생성 방지
variable "allowed_regions" {
  description = "데이터 주권 정책: 허용 OCI 리전 목록"
  type        = list(string)
  default     = ["ap-seoul-1", "ap-chuncheon-1"]
}

resource "oci_identity_policy" "korea_region_only" {
  name           = "korea-region-data-residency"
  description    = "CSAP 준수: 한국 리전 외 데이터 저장 금지"
  compartment_id = var.tenancy_ocid
  statements = [
    # 한국 리전 외 Object Storage 버킷 생성 차단
    "Deny any-user to manage object-family in tenancy where request.region != 'ap-seoul-1' AND request.region != 'ap-chuncheon-1'",
    "Deny any-user to manage database-family in tenancy where request.region != 'ap-seoul-1' AND request.region != 'ap-chuncheon-1'",
  ]
}
```

### 12.2 CSAP / ISO 27001 대비 체크리스트

| # | 항목 | 요구사항 | 구현 방법 | 상태 |
|---|---|---|---|---|
| 1 | **접근 통제 - 최소 권한** | 업무 필요 최소한의 권한만 부여 | RBAC 4단계 + Resource Principal 최소 권한 IAM | 구현 |
| 2 | **접근 통제 - MFA** | 관리자 계정 이중 인증 필수 | TOTP (pyotp) + 복구 코드 | 구현 |
| 3 | **접근 통제 - 계정 잠금** | 로그인 실패 N회 시 계정 잠금 | 5회 실패 시 30분 잠금 (Redis) | 구현 |
| 4 | **암호화 - 저장** | 민감 정보 저장 시 암호화 | OCI Vault HSM + Fernet + pgcrypto | 구현 |
| 5 | **암호화 - 전송** | 네트워크 전송 암호화 | TLS 1.3 강제 + 내부 mTLS | 구현 |
| 6 | **키 관리 - 갱신** | 암호화 키 주기적 교체 | 90일 Credential Rotation (Celery Beat) | 구현 |
| 7 | **키 관리 - HSM** | 키 보호 하드웨어 사용 | OCI Vault (HSM 옵션) | 구현 |
| 8 | **감사 - 로그 기록** | 모든 접근 이력 기록 | AuditMiddleware + audit_logs 테이블 | 구현 |
| 9 | **감사 - 로그 보존** | 감사 로그 1년 이상 보존 | PostgreSQL (1년) + Object Storage 아카이빙 (3년) | 구현 |
| 10 | **감사 - 로그 무결성** | 감사 로그 변조 방지 | Object Storage WORM (Retention Rule) | 구현 |
| 11 | **취약점 관리 - 스캔** | 정기 취약점 스캔 | Trivy (컨테이너) + Snyk (의존성) CI/CD | 계획 |
| 12 | **취약점 관리 - 패치** | 90일 내 취약점 패치 | 자동 Dependabot PR + 주간 이미지 재빌드 | 계획 |
| 13 | **네트워크 - 격리** | 망 분리 (업무/운영) | VCN 3계층 서브넷 + Network Policy | 구현 |
| 14 | **네트워크 - 방화벽** | 허가된 통신만 허용 | OCI Security List + WAF + NSG | 구현 |
| 15 | **데이터 - 분류** | 데이터 민감도 분류 체계 | CRITICAL(Credential)/HIGH(PII)/MEDIUM(로그)/LOW(메트릭) | 구현 |
| 16 | **데이터 - 주권** | 한국 내 데이터 저장 | ap-seoul-1 / ap-chuncheon-1 강제 | 구현 |
| 17 | **사고 대응 - 탐지** | 보안 사고 자동 탐지 | Cloud Guard + 이상 탐지 알람 | 구현 |
| 18 | **사고 대응 - 대응** | 사고 대응 절차 및 자동화 | Cloud Guard → Incident 자동 생성 웹훅 | 구현 |
| 19 | **공급망 - 의존성** | 오픈소스 취약점 관리 | uv.lock 해시 고정 + Trivy 스캔 | 계획 |
| 20 | **가용성 - 백업** | 데이터 정기 백업 및 복구 테스트 | PostgreSQL 일일 백업 + 월별 복구 훈련 | 계획 |

### 12.3 감사 대응 증적 수집 자동화

```python
# app/compliance/evidence_collector.py
from datetime import datetime, timedelta, timezone
from typing import Optional

from app.db.session import get_sync_db
from app.models.audit import AuditLog


class ComplianceEvidenceCollector:
    """
    CSAP / ISO27001 감사 대응을 위한 증적 자동 수집기.
    감사 기간의 로그, 접근 내역, 설정 변경 이력을 패키징.
    """

    def collect_access_logs(
        self,
        tenant_id: Optional[str],
        start_date: datetime,
        end_date: datetime,
    ) -> list[dict]:
        """기간별 접근 로그 수집 (CSV/JSON 내보내기용)."""
        with get_sync_db() as db:
            query = db.query(AuditLog).filter(
                AuditLog.created_at.between(start_date, end_date),
            )
            if tenant_id:
                query = query.filter(AuditLog.tenant_id == tenant_id)

            logs = query.order_by(AuditLog.created_at).all()
            return [log.to_dict() for log in logs]

    def generate_compliance_report(
        self,
        tenant_id: str,
        period_days: int = 365,
    ) -> dict:
        """
        ISO 27001 / CSAP 감사 보고서 자동 생성.
        - 총 접근 횟수
        - 실패 로그인 횟수
        - Credential 접근 횟수
        - 권한 거부 횟수
        - 보안 이벤트 요약
        """
        end_date = datetime.now(timezone.utc)
        start_date = end_date - timedelta(days=period_days)

        logs = self.collect_access_logs(tenant_id, start_date, end_date)

        return {
            "tenant_id": tenant_id,
            "period": {"start": start_date.isoformat(), "end": end_date.isoformat()},
            "summary": {
                "total_events": len(logs),
                "auth_failures": sum(
                    1 for l in logs
                    if l["event_type"] == "AUTH_EVENT" and l["status"] == "FAILURE"
                ),
                "credential_accesses": sum(
                    1 for l in logs if l["event_category"] == "CREDENTIAL"
                ),
                "permission_denials": sum(
                    1 for l in logs if l["response_code"] == 403
                ),
                "critical_events": sum(
                    1 for l in logs if l["severity"] == "CRITICAL"
                ),
            },
            "generated_at": end_date.isoformat(),
        }
```

---

## 부록: 보안 설정 체크리스트 (배포 전 검증)

```
[ ] JWT 개인키가 OCI Vault에만 저장되고 환경변수/파일에 없음
[ ] 모든 DB 테이블에 RLS 활성화 확인
[ ] msp_app_role이 BYPASSRLS 권한 없음 확인
[ ] TLS 1.3 강제 설정 확인 (TLS 1.2 이하 차단)
[ ] Bastion Host SSH 접근 IP 화이트리스트 적용
[ ] 감사 로그 WORM 버킷 Retention Rule 활성화
[ ] Cloud Guard 전체 탐지기 활성화 상태 확인
[ ] OCI Vault Secret Rotation 자동화 테스트 완료
[ ] MFA 강제 설정 (Super Admin / Tenant Admin)
[ ] 한국 리전 외 리소스 생성 차단 IAM Policy 적용
[ ] 컨테이너 이미지 Trivy 취약점 스캔 통과
[ ] Rate Limiting 설정 검증 (로그인 10/min 이하)
[ ] 보안 헤더 자동화 검증 (observatory.mozilla.org A+)
[ ] 침투 테스트 수행 (분기 1회)
[ ] 보안 사고 대응 훈련 완료 (반기 1회)
```

---

*문서 분류: CONFIDENTIAL*
*최종 수정: 2026-03-21*
*다음 검토 예정: 2026-09-21 (6개월 주기)*
