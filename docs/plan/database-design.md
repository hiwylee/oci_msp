# OCI MSP 관리 플랫폼 - 데이터베이스 설계서

> 작성: 데이터베이스 아키텍처 설계
> 날짜: 2026-03-21
> 버전: 1.0
> 상태: 확정

---

## 목차

1. [ERD 개요](#1-erd-개요)
2. [테넌시/사용자 도메인](#2-테넌시사용자-도메인)
3. [OCI 리소스 도메인](#3-oci-리소스-도메인)
4. [모니터링 도메인](#4-모니터링-도메인)
5. [비용 도메인](#5-비용-도메인)
6. [작업/감사 도메인](#6-작업감사-도메인)
7. [멀티 테넌트 RLS 정책](#7-멀티-테넌트-rls-정책)
8. [인덱스 전략](#8-인덱스-전략)
9. [데이터 보존 및 아카이빙](#9-데이터-보존-및-아카이빙)
10. [PostgreSQL → OCI ATP 마이그레이션 고려사항](#10-postgresql--oci-atp-마이그레이션-고려사항)

---

## 1. ERD 개요

### 1.1 도메인별 테이블 그룹

| 도메인 | 테이블 | 설명 |
|--------|--------|------|
| **테넌시/사용자** | tenants, tenant_credentials, tenant_sla, sla_measurements, users, roles, user_tenant_roles | 고객사 테넌시 및 사용자 관리 |
| **OCI 리소스** | oci_compartments, oci_resources | OCI 리소스 인벤토리 |
| **모니터링** | alert_rules, alerts, incidents, incident_timeline | 알람/장애 관리 |
| **비용** | cost_records, budget_alerts | OCI 비용 추적 |
| **작업/감사** | jobs, audit_logs | 비동기 작업 및 감사 로그 |
| **시스템** | archive_policies | 데이터 보존 정책 |

### 1.2 핵심 관계 다이어그램

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         TENANCY / USER DOMAIN                                   │
│                                                                                 │
│  ┌──────────┐  1    ┌───────────────────┐      ┌──────────────────┐            │
│  │ tenants  │──────►│ tenant_credentials│      │    tenant_sla    │            │
│  │          │  N    └───────────────────┘      │                  │            │
│  │ (PK: id) │◄──────────────────────────────── │ (FK: tenant_id)  │            │
│  └──────┬───┘  1                               └──────────────────┘            │
│         │                                                                       │
│         │  N    ┌──────────────────┐  N    ┌────────┐  N    ┌────────────┐    │
│         └──────►│ user_tenant_roles│◄──────│ users  │       │   roles    │    │
│                 │ (tenant_id,      │       │        │       │            │    │
│                 │  user_id, role_id│──────►│(PK: id)│       │ (PK: id)   │    │
│                 └──────────────────┘       └────────┘       └────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                          OCI RESOURCE DOMAIN                                    │
│                                                                                 │
│  ┌──────────┐  1    ┌───────────────────┐  1    ┌───────────────────┐         │
│  │ tenants  │──────►│ oci_compartments  │──────►│  oci_resources    │         │
│  │          │  N    │ (self-ref parent)  │  N    │                   │         │
│  └──────────┘       └───────────────────┘       └───────────────────┘         │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                          MONITORING DOMAIN                                      │
│                                                                                 │
│  ┌──────────┐  1    ┌─────────────┐  1    ┌────────────┐  1    ┌───────────┐ │
│  │ tenants  │──────►│ alert_rules │──────►│   alerts   │──────►│ incidents │ │
│  │          │  N    └─────────────┘  N    │            │  N    │           │ │
│  │          │──────────────────────────── │(FK: rule_id│       │(FK:alert) │ │
│  │          │──────────────────────────── │ resource_id│       │           │ │
│  └──────────┘                             └────────────┘       └─────┬─────┘ │
│                                                                       │       │
│                                                          ┌────────────┘       │
│                                                          │ 1                  │
│                                                          ▼ N                  │
│                                                   ┌──────────────────┐        │
│                                                   │ incident_timeline │        │
│                                                   └──────────────────┘        │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                          COST DOMAIN                                            │
│                                                                                 │
│  ┌──────────┐  1    ┌──────────────────────────────────────────────────┐      │
│  │ tenants  │──────►│ cost_records (월별 파티셔닝)                       │      │
│  │          │  N    └──────────────────────────────────────────────────┘      │
│  │          │  1    ┌──────────────┐                                          │
│  │          │──────►│ budget_alerts│                                          │
│  │          │  N    └──────────────┘                                          │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                          JOB / AUDIT DOMAIN                                     │
│                                                                                 │
│  ┌──────────┐  1    ┌──────────────────────────────────────────────────┐      │
│  │ tenants  │──────►│ jobs                                              │      │
│  │          │  N    └──────────────────────────────────────────────────┘      │
│  │          │  1    ┌──────────────────────────────────────────────────┐      │
│  │          │──────►│ audit_logs (월별 파티셔닝)                         │      │
│  │          │  N    └──────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 전체 테이블 관계 요약

```
tenants (1)
  ├── (N) tenant_credentials      -- Vault 참조 보관
  ├── (1) tenant_sla              -- SLA 계약 정보
  ├── (N) sla_measurements        -- 월간 SLA 측정 결과
  ├── (N) user_tenant_roles       -- 사용자-테넌트-역할 매핑
  ├── (N) oci_compartments        -- OCI Compartment 계층
  │         └── (N) oci_resources -- 리소스 인벤토리
  ├── (N) alert_rules             -- 알람 규칙
  │         └── (N) alerts        -- 발생 알람
  │                   └── (N) incidents         -- 장애 티켓
  │                             └── (N) incident_timeline
  ├── (N) cost_records            -- 일별 비용 데이터 (파티션)
  ├── (N) budget_alerts           -- 예산 알람
  ├── (N) jobs                    -- 비동기 작업
  └── (N) audit_logs              -- 감사 로그 (파티션)

users (1)
  ├── (N) user_tenant_roles
  ├── (N) jobs (created_by)
  ├── (N) incidents (assigned_to)
  ├── (N) alerts (acknowledged_by)
  └── (N) incident_timeline
```

---

## 2. 테넌시/사용자 도메인

### 2.1 tenants 테이블

**SQLAlchemy 모델:**

```python
# app/models/tenant.py
import uuid
import enum
from datetime import datetime
from typing import Optional, Any
from sqlalchemy import (
    String, Text, Enum as SAEnum, Boolean, DateTime,
    JSON, Index, UniqueConstraint, CheckConstraint
)
from sqlalchemy.dialects.postgresql import UUID, JSONB, ARRAY
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.db.base import Base


class TenantStatus(str, enum.Enum):
    ONBOARDING = "onboarding"    # 신규 고객사 온보딩 진행 중
    ACTIVE = "active"            # 정상 운영 중
    SUSPENDED = "suspended"      # 일시 정지 (미납, 요청 등)
    OFFBOARDING = "offboarding"  # 계약 해지 절차 진행 중
    TERMINATED = "terminated"    # 계약 완전 종료


class OnboardingStatus(str, enum.Enum):
    PENDING = "pending"
    CREDENTIALS_VERIFIED = "credentials_verified"
    INITIAL_SYNC = "initial_sync"
    COMPLETED = "completed"
    FAILED = "failed"


class SlaTier(str, enum.Enum):
    STANDARD = "standard"
    PREMIUM = "premium"
    ENTERPRISE = "enterprise"


class Tenant(Base):
    __tablename__ = "tenants"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    slug: Mapped[str] = mapped_column(
        String(100), nullable=False, unique=True,
        comment="URL-safe 고객사 식별자 (소문자, 하이픈)"
    )
    status: Mapped[TenantStatus] = mapped_column(
        SAEnum(TenantStatus, name="tenant_status_enum"),
        nullable=False,
        default=TenantStatus.ONBOARDING
    )
    oci_tenancy_ocid: Mapped[Optional[str]] = mapped_column(
        String(500), nullable=True,
        comment="OCI Tenancy OCID (ocid1.tenancy.oc1..)"
    )
    oci_region: Mapped[Optional[str]] = mapped_column(
        String(100), nullable=True,
        comment="홈 리전 (ap-seoul-1 등)"
    )
    oci_regions: Mapped[Optional[dict]] = mapped_column(
        JSONB, nullable=True,
        comment='구독 리전 목록 [{"region": "ap-seoul-1", "is_home": true}]'
    )
    onboarding_status: Mapped[OnboardingStatus] = mapped_column(
        SAEnum(OnboardingStatus, name="onboarding_status_enum"),
        nullable=False,
        default=OnboardingStatus.PENDING
    )
    sla_tier: Mapped[SlaTier] = mapped_column(
        SAEnum(SlaTier, name="sla_tier_enum"),
        nullable=False,
        default=SlaTier.STANDARD
    )
    settings: Mapped[Optional[dict]] = mapped_column(
        JSONB, nullable=True, default=dict,
        comment='알람 채널, 타임존 등 {"timezone": "Asia/Seoul", "notify_channels": []}'
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False,
        server_default=func.now(), onupdate=func.now()
    )

    # Relationships
    credentials: Mapped[list["TenantCredential"]] = relationship(
        back_populates="tenant", cascade="all, delete-orphan"
    )
    sla: Mapped[Optional["TenantSla"]] = relationship(
        back_populates="tenant", uselist=False
    )
    user_roles: Mapped[list["UserTenantRole"]] = relationship(
        back_populates="tenant"
    )

    __table_args__ = (
        Index("ix_tenants_slug", "slug"),
        Index("ix_tenants_status", "status"),
        Index("ix_tenants_oci_tenancy_ocid", "oci_tenancy_ocid"),
    )
```

**DDL:**

```sql
CREATE TYPE tenant_status_enum AS ENUM (
    'onboarding',   -- 신규 고객사 온보딩 진행 중
    'active',       -- 정상 운영 중
    'suspended',    -- 일시 정지 (미납, 요청 등)
    'offboarding',  -- 계약 해지 절차 진행 중
    'terminated'    -- 계약 완전 종료
);
CREATE TYPE onboarding_status_enum AS ENUM (
    'pending', 'credentials_verified', 'initial_sync', 'completed', 'failed'
);
CREATE TYPE sla_tier_enum AS ENUM (
    'standard', 'premium', 'enterprise'
);

CREATE TABLE tenants (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name              VARCHAR(255) NOT NULL,
    slug              VARCHAR(100) NOT NULL UNIQUE,
    status            tenant_status_enum NOT NULL DEFAULT 'onboarding',
    oci_tenancy_ocid  VARCHAR(500),
    oci_region        VARCHAR(100),
    oci_regions       JSONB,
    onboarding_status onboarding_status_enum NOT NULL DEFAULT 'pending',
    sla_tier          sla_tier_enum NOT NULL DEFAULT 'standard',
    settings          JSONB DEFAULT '{}',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE tenants IS '고객사 OCI 테넌시 마스터';
COMMENT ON COLUMN tenants.slug IS 'URL-safe 고객사 식별자 (소문자, 하이픈)';
COMMENT ON COLUMN tenants.oci_regions IS '구독 리전 목록: [{"region": "ap-seoul-1", "is_home": true}]';
COMMENT ON COLUMN tenants.settings IS '알람 채널, 타임존 등 운영 설정';

CREATE INDEX ix_tenants_slug ON tenants(slug);
CREATE INDEX ix_tenants_status ON tenants(status);
CREATE INDEX ix_tenants_oci_tenancy_ocid ON tenants(oci_tenancy_ocid);

-- updated_at 자동 갱신 트리거
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tenants_updated_at
    BEFORE UPDATE ON tenants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

---

### 2.2 tenant_credentials 테이블

> **보안 원칙**: 실제 OCI API Key / Private Key는 절대 DB에 저장하지 않습니다.
> OCI Vault에 저장 후 Secret OCID(참조 ID)만 이 테이블에 보관합니다.

**SQLAlchemy 모델:**

```python
class CredentialType(str, enum.Enum):
    API_KEY = "api_key"
    INSTANCE_PRINCIPAL = "instance_principal"
    RESOURCE_PRINCIPAL = "resource_principal"


class TenantCredential(Base):
    __tablename__ = "tenant_credentials"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False
    )
    vault_secret_id: Mapped[str] = mapped_column(
        String(500), nullable=False,
        comment="OCI Vault Secret OCID (실제 키는 Vault에 저장)"
    )
    credential_type: Mapped[CredentialType] = mapped_column(
        SAEnum(CredentialType, name="credential_type_enum"),
        nullable=False
    )
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    last_verified_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    rotated_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True,
        comment="마지막 Credential 교체 시각"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False,
        server_default=func.now(), onupdate=func.now()
    )

    tenant: Mapped["Tenant"] = relationship(back_populates="credentials")

    __table_args__ = (
        Index("ix_tenant_credentials_tenant_id", "tenant_id"),
        Index("ix_tenant_credentials_active", "tenant_id", "is_active"),
    )
```

**DDL:**

```sql
CREATE TYPE credential_type_enum AS ENUM (
    'api_key', 'instance_principal', 'resource_principal'
);

CREATE TABLE tenant_credentials (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    vault_secret_id   VARCHAR(500) NOT NULL,
    credential_type   credential_type_enum NOT NULL,
    is_active         BOOLEAN     NOT NULL DEFAULT TRUE,
    last_verified_at  TIMESTAMPTZ,
    rotated_at        TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE tenant_credentials IS 'OCI Vault Secret 참조 (실제 키 미저장)';
COMMENT ON COLUMN tenant_credentials.vault_secret_id IS 'OCI Vault Secret OCID';

CREATE INDEX ix_tenant_credentials_tenant_id ON tenant_credentials(tenant_id);
CREATE INDEX ix_tenant_credentials_active ON tenant_credentials(tenant_id, is_active);
```

---

### 2.3 users 테이블

**SQLAlchemy 모델:**

```python
class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    email: Mapped[str] = mapped_column(
        String(255), nullable=False, unique=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    hashed_password: Mapped[Optional[str]] = mapped_column(
        String(255), nullable=True,
        comment="SSO 전용 사용자는 NULL"
    )
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    mfa_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    mfa_secret_encrypted: Mapped[Optional[str]] = mapped_column(
        String(512), nullable=True,
        comment="Fernet 암호화된 TOTP Secret (MFA 미설정 시 NULL)"
    )
    mfa_recovery_codes_hashed: Mapped[Optional[list]] = mapped_column(
        ARRAY(Text), nullable=True,
        comment="Argon2 해시된 복구 코드 배열 (각 8자리)"
    )
    mfa_verified_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True,
        comment="MFA 최초 인증 완료 시각"
    )
    last_login_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    sso_provider: Mapped[Optional[str]] = mapped_column(
        String(50), nullable=True,
        comment="google / microsoft / okta 등"
    )
    sso_subject: Mapped[Optional[str]] = mapped_column(
        String(255), nullable=True,
        comment="SSO 제공자 고유 Subject ID"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False,
        server_default=func.now(), onupdate=func.now()
    )

    tenant_roles: Mapped[list["UserTenantRole"]] = relationship(
        back_populates="user"
    )

    __table_args__ = (
        Index("ix_users_email", "email"),
        Index("ix_users_sso", "sso_provider", "sso_subject"),
    )
```

**DDL:**

```sql
CREATE TABLE users (
    id                          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    email                       VARCHAR(255) NOT NULL UNIQUE,
    name                        VARCHAR(255) NOT NULL,
    hashed_password             VARCHAR(255),
    is_active                   BOOLEAN     NOT NULL DEFAULT TRUE,
    mfa_enabled                 BOOLEAN     NOT NULL DEFAULT FALSE,
    mfa_secret_encrypted        VARCHAR(512),
    mfa_recovery_codes_hashed   TEXT[],
    mfa_verified_at             TIMESTAMPTZ,
    last_login_at               TIMESTAMPTZ,
    sso_provider                VARCHAR(50),
    sso_subject                 VARCHAR(255),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE users IS 'MSP 플랫폼 사용자 (MSP 엔지니어 포함)';
COMMENT ON COLUMN users.hashed_password IS 'bcrypt 해시, SSO 전용 사용자는 NULL';
COMMENT ON COLUMN users.mfa_secret_encrypted IS 'Fernet 암호화된 TOTP Secret (MFA 미설정 시 NULL)';
COMMENT ON COLUMN users.mfa_recovery_codes_hashed IS 'Argon2 해시된 복구 코드 배열 (각 8자리)';
COMMENT ON COLUMN users.mfa_verified_at IS 'MFA 최초 인증 완료 시각';

CREATE INDEX ix_users_email ON users(email);
CREATE UNIQUE INDEX ix_users_sso_unique ON users(sso_provider, sso_subject)
    WHERE sso_provider IS NOT NULL;
```

---

### 2.4 roles 테이블

**SQLAlchemy 모델:**

```python
class RoleName(str, enum.Enum):
    SUPER_ADMIN = "super_admin"       # MSP 플랫폼 전체 관리자
    TENANT_ADMIN = "tenant_admin"     # 고객사 관리자
    OPERATOR = "operator"             # 운영자 (읽기+제한적 쓰기)
    VIEWER = "viewer"                 # 조회 전용


class Role(Base):
    __tablename__ = "roles"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[RoleName] = mapped_column(
        SAEnum(RoleName, name="role_name_enum"),
        nullable=False,
        unique=True
    )
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
```

**DDL:**

```sql
CREATE TYPE role_name_enum AS ENUM (
    'super_admin', 'tenant_admin', 'operator', 'viewer'
);

CREATE TABLE roles (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        role_name_enum NOT NULL UNIQUE,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 초기 데이터
INSERT INTO roles (name, description) VALUES
    ('super_admin',   'MSP 플랫폼 전체 관리 권한'),
    ('tenant_admin',  '특정 고객사 관리 권한'),
    ('operator',      '리소스 조회 및 제한적 운영 권한'),
    ('viewer',        '읽기 전용 권한');
```

---

### 2.5 user_tenant_roles 테이블

**SQLAlchemy 모델:**

```python
class UserTenantRole(Base):
    __tablename__ = "user_tenant_roles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        primary_key=True
    )
    role_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("roles.id", ondelete="RESTRICT"),
        primary_key=True
    )
    granted_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True
    )
    granted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    expires_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True,
        comment="임시 권한 만료 시각 (NULL = 영구)"
    )

    user: Mapped["User"] = relationship(
        back_populates="tenant_roles", foreign_keys=[user_id]
    )
    tenant: Mapped["Tenant"] = relationship(back_populates="user_roles")
    role: Mapped["Role"] = relationship()

    __table_args__ = (
        Index("ix_user_tenant_roles_user_id", "user_id"),
        Index("ix_user_tenant_roles_tenant_id", "tenant_id"),
    )
```

**DDL:**

```sql
CREATE TABLE user_tenant_roles (
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    role_id     UUID        NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
    granted_by  UUID        REFERENCES users(id) ON DELETE SET NULL,
    granted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ,
    PRIMARY KEY (user_id, tenant_id, role_id)
);

COMMENT ON TABLE user_tenant_roles IS '사용자-테넌트-역할 N:M 매핑';

CREATE INDEX ix_user_tenant_roles_user_id ON user_tenant_roles(user_id);
CREATE INDEX ix_user_tenant_roles_tenant_id ON user_tenant_roles(tenant_id);
-- 유효한 역할만 조회하는 부분 인덱스
CREATE INDEX ix_user_tenant_roles_active ON user_tenant_roles(tenant_id, user_id)
    WHERE expires_at IS NULL OR expires_at > NOW();
```

---

### 2.6 tenant_sla 테이블

**SQLAlchemy 모델:**

```python
class TenantSla(Base):
    __tablename__ = "tenant_sla"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False,
        unique=True
    )
    tier: Mapped[SlaTier] = mapped_column(
        SAEnum(SlaTier, name="sla_tier_enum"),
        nullable=False
    )
    availability_target_pct: Mapped[float] = mapped_column(
        Numeric(5, 2), nullable=False, default=99.9,
        comment="가용성 목표 (예: 99.9)"
    )
    response_time_critical_min: Mapped[int] = mapped_column(
        Integer, nullable=False, default=15,
        comment="P1 Critical 응답 시간 목표 (분)"
    )
    response_time_high_min: Mapped[int] = mapped_column(
        Integer, nullable=False, default=60,
        comment="P2 High 응답 시간 목표 (분)"
    )
    response_time_medium_min: Mapped[int] = mapped_column(
        Integer, nullable=False, default=240,
        comment="P3 Medium 응답 시간 목표 (분)"
    )
    violation_notify_channels: Mapped[Optional[dict]] = mapped_column(
        JSONB, nullable=True,
        comment='SLA 위반 알림 채널 [{"type": "slack", "webhook_url": "..."}]'
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False,
        server_default=func.now(), onupdate=func.now()
    )

    tenant: Mapped["Tenant"] = relationship(back_populates="sla")
```

**DDL:**

```sql
CREATE TABLE tenant_sla (
    id                          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   UUID        NOT NULL UNIQUE REFERENCES tenants(id) ON DELETE CASCADE,
    tier                        sla_tier_enum NOT NULL,
    availability_target_pct     NUMERIC(5,2) NOT NULL DEFAULT 99.9,
    response_time_critical_min  INTEGER     NOT NULL DEFAULT 15,
    response_time_high_min      INTEGER     NOT NULL DEFAULT 60,
    response_time_medium_min    INTEGER     NOT NULL DEFAULT 240,
    violation_notify_channels   JSONB,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE tenant_sla IS '고객사별 SLA 계약 조건';
COMMENT ON COLUMN tenant_sla.violation_notify_channels
    IS 'SLA 위반 알림 채널: [{"type": "slack", "webhook_url": "..."}]';
```

---

### 2.7 sla_measurements 테이블

**SQLAlchemy 모델:**

```python
class SlaMeasurement(Base):
    __tablename__ = "sla_measurements"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False
    )
    measurement_period: Mapped[str] = mapped_column(
        String(7), nullable=False,
        comment="측정 기간 (YYYY-MM 형식, 월별 집계)"
    )
    service_availability_pct: Mapped[float] = mapped_column(
        Numeric(6, 3), nullable=False,
        comment="해당 월 서비스 가용성 (예: 99.950)"
    )
    incident_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0,
        comment="해당 월 발생 인시던트 수"
    )
    mttr_minutes: Mapped[Optional[float]] = mapped_column(
        Numeric(10, 2), nullable=True,
        comment="평균 복구 시간 MTTR (분, 인시던트 없으면 NULL)"
    )
    measurement_date: Mapped[datetime] = mapped_column(
        DateTime(timezone=False), nullable=False,
        comment="측정 기준일 (해당 월 1일)"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint("tenant_id", "measurement_period",
                         name="uq_sla_measurements_tenant_period"),
        Index("ix_sla_measurements_tenant_date",
              "tenant_id", "measurement_date"),
    )
```

**DDL:**

```sql
CREATE TABLE sla_measurements (
    id                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    measurement_period       CHAR(7)     NOT NULL,  -- YYYY-MM
    service_availability_pct NUMERIC(6,3) NOT NULL,
    incident_count           INTEGER     NOT NULL DEFAULT 0,
    mttr_minutes             NUMERIC(10,2),
    measurement_date         DATE        NOT NULL,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_sla_measurements_tenant_period
        UNIQUE (tenant_id, measurement_period)
);

COMMENT ON TABLE sla_measurements IS '고객사별 월간 SLA 측정 결과';
COMMENT ON COLUMN sla_measurements.measurement_period IS '측정 기간: YYYY-MM (예: 2026-03)';
COMMENT ON COLUMN sla_measurements.service_availability_pct IS '서비스 가용성 (예: 99.950 = 99.950%)';
COMMENT ON COLUMN sla_measurements.mttr_minutes IS '평균 복구 시간 MTTR (분), 인시던트 없으면 NULL';

CREATE INDEX ix_sla_measurements_tenant_date
    ON sla_measurements(tenant_id, measurement_date DESC);
```

---

## 3. OCI 리소스 도메인

### 3.1 oci_compartments 테이블

**SQLAlchemy 모델:**

```python
class OciCompartment(Base):
    __tablename__ = "oci_compartments"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False
    )
    oci_compartment_id: Mapped[str] = mapped_column(
        String(500), nullable=False,
        comment="OCI Compartment OCID"
    )
    parent_compartment_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("oci_compartments.id", ondelete="SET NULL"),
        nullable=True,
        comment="NULL = 루트 Compartment"
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    path: Mapped[Optional[str]] = mapped_column(
        Text, nullable=True,
        comment="루트부터 전체 경로 (예: /root/prod/app)"
    )
    depth: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0,
        comment="계층 깊이 (루트=0)"
    )
    is_root: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    last_synced_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False,
        server_default=func.now(), onupdate=func.now()
    )

    # Self-referential relationship
    children: Mapped[list["OciCompartment"]] = relationship(
        back_populates="parent"
    )
    parent: Mapped[Optional["OciCompartment"]] = relationship(
        back_populates="children", remote_side="OciCompartment.id"
    )
    resources: Mapped[list["OciResource"]] = relationship(
        back_populates="compartment"
    )

    __table_args__ = (
        UniqueConstraint("tenant_id", "oci_compartment_id",
                         name="uq_oci_compartments_tenant_oci_id"),
        Index("ix_oci_compartments_tenant_id", "tenant_id"),
        Index("ix_oci_compartments_parent", "parent_compartment_id"),
    )
```

**DDL:**

```sql
CREATE TABLE oci_compartments (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id            UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    oci_compartment_id   VARCHAR(500) NOT NULL,
    parent_compartment_id UUID       REFERENCES oci_compartments(id) ON DELETE SET NULL,
    name                 VARCHAR(255) NOT NULL,
    path                 TEXT,
    depth                INTEGER     NOT NULL DEFAULT 0,
    is_root              BOOLEAN     NOT NULL DEFAULT FALSE,
    last_synced_at       TIMESTAMPTZ,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_oci_compartments_tenant_oci_id
        UNIQUE (tenant_id, oci_compartment_id)
);

COMMENT ON TABLE oci_compartments IS 'OCI Compartment 계층 구조 캐시';
COMMENT ON COLUMN oci_compartments.path IS '루트부터 전체 경로 (/root/prod/app)';

CREATE INDEX ix_oci_compartments_tenant_id ON oci_compartments(tenant_id);
CREATE INDEX ix_oci_compartments_parent ON oci_compartments(parent_compartment_id);
CREATE INDEX ix_oci_compartments_root ON oci_compartments(tenant_id, is_root)
    WHERE is_root = TRUE;
```

---

### 3.2 oci_resources 테이블

**SQLAlchemy 모델:**

```python
class OciResourceType(str, enum.Enum):
    # Compute
    INSTANCE = "instance"
    INSTANCE_POOL = "instance_pool"
    # Networking
    VCN = "vcn"
    SUBNET = "subnet"
    LOAD_BALANCER = "load_balancer"
    # Storage
    BLOCK_VOLUME = "block_volume"
    FILE_SYSTEM = "file_system"
    OBJECT_BUCKET = "object_bucket"
    # Database
    AUTONOMOUS_DATABASE = "autonomous_database"
    DB_SYSTEM = "db_system"
    MYSQL_DB_SYSTEM = "mysql_db_system"
    # Container & Functions
    OKE_CLUSTER = "oke_cluster"
    FUNCTION = "function"
    # Security
    VAULT = "vault"
    # Analytics
    DATA_INTEGRATION = "data_integration"


class OciResourceStatus(str, enum.Enum):
    RUNNING = "running"
    STOPPED = "stopped"
    STARTING = "starting"
    STOPPING = "stopping"
    PROVISIONING = "provisioning"
    TERMINATING = "terminating"
    TERMINATED = "terminated"
    UNKNOWN = "unknown"


class SyncStatus(str, enum.Enum):
    SYNCED = "synced"
    SYNCING = "syncing"
    FAILED = "failed"
    STALE = "stale"


class OciResource(Base):
    __tablename__ = "oci_resources"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False
    )
    compartment_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("oci_compartments.id", ondelete="SET NULL"),
        nullable=True
    )
    resource_type: Mapped[OciResourceType] = mapped_column(
        SAEnum(OciResourceType, name="oci_resource_type_enum"),
        nullable=False
    )
    oci_id: Mapped[str] = mapped_column(
        String(500), nullable=False,
        comment="OCI Resource OCID"
    )
    oci_region: Mapped[str] = mapped_column(
        String(100), nullable=False
    )
    display_name: Mapped[str] = mapped_column(String(255), nullable=False)
    status: Mapped[OciResourceStatus] = mapped_column(
        SAEnum(OciResourceStatus, name="oci_resource_status_enum"),
        nullable=False,
        default=OciResourceStatus.UNKNOWN
    )
    lifecycle_state: Mapped[Optional[str]] = mapped_column(
        String(100), nullable=True,
        comment="OCI 원본 lifecycle state 문자열"
    )
    resource_data: Mapped[Optional[dict]] = mapped_column(
        JSONB, nullable=True,
        comment="OCI SDK 응답 원본 (리소스 타입별 스펙)"
    )
    tags: Mapped[Optional[dict]] = mapped_column(
        JSONB, nullable=True,
        comment='OCI Freeform + Defined Tags {"env": "prod"}'
    )
    last_synced_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    sync_status: Mapped[SyncStatus] = mapped_column(
        SAEnum(SyncStatus, name="sync_status_enum"),
        nullable=False,
        default=SyncStatus.SYNCED
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False,
        server_default=func.now(), onupdate=func.now()
    )

    compartment: Mapped[Optional["OciCompartment"]] = relationship(
        back_populates="resources"
    )

    __table_args__ = (
        UniqueConstraint("tenant_id", "oci_id",
                         name="uq_oci_resources_tenant_oci_id"),
        Index("ix_oci_resources_tenant_id", "tenant_id"),
        Index("ix_oci_resources_tenant_type", "tenant_id", "resource_type"),
        Index("ix_oci_resources_tenant_region", "tenant_id", "oci_region"),
        Index("ix_oci_resources_compartment", "compartment_id"),
        Index("ix_oci_resources_status", "tenant_id", "status"),
        Index("ix_oci_resources_tags_gin", "tags",
              postgresql_using="gin"),
        Index("ix_oci_resources_data_gin", "resource_data",
              postgresql_using="gin"),
    )
```

**DDL:**

```sql
CREATE TYPE oci_resource_type_enum AS ENUM (
    'instance', 'instance_pool',
    'vcn', 'subnet', 'load_balancer',
    'block_volume', 'file_system', 'object_bucket',
    'autonomous_database', 'db_system', 'mysql_db_system',
    'oke_cluster', 'function',
    'vault',
    'data_integration'
);
CREATE TYPE oci_resource_status_enum AS ENUM (
    'running', 'stopped', 'starting', 'stopping',
    'provisioning', 'terminating', 'terminated', 'unknown'
);
CREATE TYPE sync_status_enum AS ENUM (
    'synced', 'syncing', 'failed', 'stale'
);

CREATE TABLE oci_resources (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    compartment_id  UUID        REFERENCES oci_compartments(id) ON DELETE SET NULL,
    resource_type   oci_resource_type_enum NOT NULL,
    oci_id          VARCHAR(500) NOT NULL,
    oci_region      VARCHAR(100) NOT NULL,
    display_name    VARCHAR(255) NOT NULL,
    status          oci_resource_status_enum NOT NULL DEFAULT 'unknown',
    lifecycle_state VARCHAR(100),
    resource_data   JSONB,
    tags            JSONB DEFAULT '{}',
    last_synced_at  TIMESTAMPTZ,
    sync_status     sync_status_enum NOT NULL DEFAULT 'synced',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_oci_resources_tenant_oci_id UNIQUE (tenant_id, oci_id)
);

COMMENT ON TABLE oci_resources IS 'OCI 리소스 인벤토리 캐시 (30분 주기 동기화)';
COMMENT ON COLUMN oci_resources.resource_data IS 'OCI SDK 응답 원본 (타입별 스펙 상이)';
COMMENT ON COLUMN oci_resources.tags IS 'OCI Freeform + Defined Tags 병합';

CREATE INDEX ix_oci_resources_tenant_id     ON oci_resources(tenant_id);
CREATE INDEX ix_oci_resources_tenant_type   ON oci_resources(tenant_id, resource_type);
CREATE INDEX ix_oci_resources_tenant_region ON oci_resources(tenant_id, oci_region);
CREATE INDEX ix_oci_resources_compartment   ON oci_resources(compartment_id);
CREATE INDEX ix_oci_resources_status        ON oci_resources(tenant_id, status);
CREATE INDEX ix_oci_resources_tags_gin      ON oci_resources USING gin(tags);
CREATE INDEX ix_oci_resources_data_gin      ON oci_resources USING gin(resource_data);
CREATE INDEX ix_oci_resources_synced_at     ON oci_resources(last_synced_at)
    WHERE sync_status = 'stale';
```

---

## 4. 모니터링 도메인

### 4.1 alert_rules 테이블

**SQLAlchemy 모델:**

```python
class AlertSeverity(str, enum.Enum):
    P1_CRITICAL = "P1"
    P2_HIGH = "P2"
    P3_MEDIUM = "P3"
    P4_LOW = "P4"


class AlertRule(Base):
    __tablename__ = "alert_rules"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    resource_type: Mapped[Optional[str]] = mapped_column(
        String(100), nullable=True,
        comment="적용 대상 리소스 타입 (NULL = 전체)"
    )
    mql_query: Mapped[Optional[str]] = mapped_column(
        Text, nullable=True,
        comment="OCI Monitoring Query Language (MQL) 쿼리"
    )
    namespace: Mapped[Optional[str]] = mapped_column(
        String(255), nullable=True,
        comment="OCI Monitoring Namespace (oci_computeagent 등)"
    )
    condition_operator: Mapped[str] = mapped_column(
        String(20), nullable=False, default="GT",
        comment="GT / LT / GTE / LTE / EQ"
    )
    condition_threshold: Mapped[float] = mapped_column(
        Numeric(15, 4), nullable=False
    )
    evaluation_window_sec: Mapped[int] = mapped_column(
        Integer, nullable=False, default=300,
        comment="평가 윈도우 (초)"
    )
    severity: Mapped[AlertSeverity] = mapped_column(
        SAEnum(AlertSeverity, name="alert_severity_enum"),
        nullable=False
    )
    notification_channels: Mapped[Optional[dict]] = mapped_column(
        JSONB, nullable=True,
        comment='알림 채널 [{"type": "ons", "topic_id": "..."}]'
    )
    maintenance_windows: Mapped[Optional[dict]] = mapped_column(
        JSONB, nullable=True,
        comment='유지보수 윈도우 [{"start": "2026-04-01T00:00Z", "end": "..."}]'
    )
    is_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    oci_alarm_id: Mapped[Optional[str]] = mapped_column(
        String(500), nullable=True,
        comment="OCI Monitoring Alarm OCID (생성 후 저장)"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False,
        server_default=func.now(), onupdate=func.now()
    )

    alerts: Mapped[list["Alert"]] = relationship(back_populates="rule")

    __table_args__ = (
        Index("ix_alert_rules_tenant_id", "tenant_id"),
        Index("ix_alert_rules_enabled", "tenant_id", "is_enabled"),
        CheckConstraint(
            "condition_operator IN ('GT', 'LT', 'GTE', 'LTE', 'EQ')",
            name="chk_alert_rules_condition_operator"
        ),
    )
```

**DDL:**

```sql
CREATE TYPE alert_severity_enum AS ENUM ('P1', 'P2', 'P3', 'P4');

CREATE TABLE alert_rules (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name                    VARCHAR(255) NOT NULL,
    resource_type           VARCHAR(100),
    mql_query               TEXT,
    namespace               VARCHAR(255),
    condition_operator      VARCHAR(20) NOT NULL DEFAULT 'GT'
                                CHECK (condition_operator IN ('GT', 'LT', 'GTE', 'LTE', 'EQ')),
    condition_threshold     NUMERIC(15,4) NOT NULL,
    evaluation_window_sec   INTEGER     NOT NULL DEFAULT 300,
    severity                alert_severity_enum NOT NULL,
    notification_channels   JSONB,
    maintenance_windows     JSONB,
    is_enabled              BOOLEAN     NOT NULL DEFAULT TRUE,
    oci_alarm_id            VARCHAR(500),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON COLUMN alert_rules.mql_query
    IS 'OCI Monitoring Query Language 쿼리 문자열';
COMMENT ON COLUMN alert_rules.maintenance_windows
    IS '알람 억제 기간: [{"start": "ISO8601", "end": "ISO8601"}]';

CREATE INDEX ix_alert_rules_tenant_id ON alert_rules(tenant_id);
CREATE INDEX ix_alert_rules_enabled ON alert_rules(tenant_id, is_enabled);
```

---

### 4.2 alerts 테이블

**SQLAlchemy 모델:**

```python
class AlertStatus(str, enum.Enum):
    FIRING = "FIRING"
    RESOLVED = "RESOLVED"
    ACKNOWLEDGED = "ACKNOWLEDGED"
    SILENCED = "SILENCED"


class Alert(Base):
    __tablename__ = "alerts"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False
    )
    rule_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("alert_rules.id", ondelete="SET NULL"),
        nullable=True
    )
    resource_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("oci_resources.id", ondelete="SET NULL"),
        nullable=True
    )
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    severity: Mapped[AlertSeverity] = mapped_column(
        SAEnum(AlertSeverity, name="alert_severity_enum"),
        nullable=False
    )
    status: Mapped[AlertStatus] = mapped_column(
        SAEnum(AlertStatus, name="alert_status_enum"),
        nullable=False,
        default=AlertStatus.FIRING
    )
    metric_value: Mapped[Optional[float]] = mapped_column(
        Numeric(15, 4), nullable=True,
        comment="알람 트리거 시점 메트릭 값"
    )
    fired_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    resolved_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    acknowledged_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True
    )
    acknowledged_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    rule: Mapped[Optional["AlertRule"]] = relationship(back_populates="alerts")
    incidents: Mapped[list["Incident"]] = relationship(back_populates="alert")

    __table_args__ = (
        Index("ix_alerts_tenant_id", "tenant_id"),
        Index("ix_alerts_tenant_status", "tenant_id", "status"),
        Index("ix_alerts_tenant_severity", "tenant_id", "severity"),
        Index("ix_alerts_fired_at", "tenant_id", "fired_at"),
        Index("ix_alerts_rule_id", "rule_id"),
        Index("ix_alerts_resource_id", "resource_id"),
    )
```

**DDL:**

```sql
CREATE TYPE alert_status_enum AS ENUM (
    'FIRING', 'RESOLVED', 'ACKNOWLEDGED', 'SILENCED'
);

CREATE TABLE alerts (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    rule_id         UUID        REFERENCES alert_rules(id) ON DELETE SET NULL,
    resource_id     UUID        REFERENCES oci_resources(id) ON DELETE SET NULL,
    title           VARCHAR(500) NOT NULL,
    message         TEXT,
    severity        alert_severity_enum NOT NULL,
    status          alert_status_enum NOT NULL DEFAULT 'FIRING',
    metric_value    NUMERIC(15,4),
    fired_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at     TIMESTAMPTZ,
    acknowledged_by UUID        REFERENCES users(id) ON DELETE SET NULL,
    acknowledged_at TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_alerts_tenant_id       ON alerts(tenant_id);
CREATE INDEX ix_alerts_tenant_status   ON alerts(tenant_id, status);
CREATE INDEX ix_alerts_tenant_severity ON alerts(tenant_id, severity);
CREATE INDEX ix_alerts_fired_at        ON alerts(tenant_id, fired_at DESC);
CREATE INDEX ix_alerts_rule_id         ON alerts(rule_id);
CREATE INDEX ix_alerts_resource_id     ON alerts(resource_id);
-- 현재 발화 중인 알람 전용 부분 인덱스
CREATE INDEX ix_alerts_firing ON alerts(tenant_id, severity, fired_at)
    WHERE status = 'FIRING';
```

---

### 4.3 incidents 테이블

**SQLAlchemy 모델:**

```python
class IncidentStatus(str, enum.Enum):
    OPEN = "OPEN"
    INVESTIGATING = "INVESTIGATING"
    MITIGATING = "MITIGATING"
    RESOLVED = "RESOLVED"
    CLOSED = "CLOSED"


class Incident(Base):
    __tablename__ = "incidents"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False
    )
    alert_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("alerts.id", ondelete="SET NULL"),
        nullable=True
    )
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    severity: Mapped[AlertSeverity] = mapped_column(
        SAEnum(AlertSeverity, name="alert_severity_enum"),
        nullable=False
    )
    status: Mapped[IncidentStatus] = mapped_column(
        SAEnum(IncidentStatus, name="incident_status_enum"),
        nullable=False,
        default=IncidentStatus.OPEN
    )
    assigned_to: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True
    )
    rca_summary: Mapped[Optional[str]] = mapped_column(
        Text, nullable=True,
        comment="Root Cause Analysis 요약"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    resolved_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False,
        server_default=func.now(), onupdate=func.now()
    )

    alert: Mapped[Optional["Alert"]] = relationship(back_populates="incidents")
    timeline: Mapped[list["IncidentTimeline"]] = relationship(
        back_populates="incident", order_by="IncidentTimeline.created_at"
    )

    __table_args__ = (
        Index("ix_incidents_tenant_id", "tenant_id"),
        Index("ix_incidents_tenant_status", "tenant_id", "status"),
        Index("ix_incidents_created_at", "tenant_id", "created_at"),
        Index("ix_incidents_assigned_to", "assigned_to"),
    )
```

**DDL:**

```sql
CREATE TYPE incident_status_enum AS ENUM (
    'OPEN', 'INVESTIGATING', 'MITIGATING', 'RESOLVED', 'CLOSED'
);

CREATE TABLE incidents (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    alert_id    UUID        REFERENCES alerts(id) ON DELETE SET NULL,
    title       VARCHAR(500) NOT NULL,
    description TEXT,
    severity    alert_severity_enum NOT NULL,
    status      incident_status_enum NOT NULL DEFAULT 'OPEN',
    assigned_to UUID        REFERENCES users(id) ON DELETE SET NULL,
    rca_summary TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON COLUMN incidents.rca_summary IS 'Root Cause Analysis 요약 (장애 종료 후 작성)';

CREATE INDEX ix_incidents_tenant_id     ON incidents(tenant_id);
CREATE INDEX ix_incidents_tenant_status ON incidents(tenant_id, status);
CREATE INDEX ix_incidents_created_at    ON incidents(tenant_id, created_at DESC);
CREATE INDEX ix_incidents_assigned_to   ON incidents(assigned_to);
-- 미해결 장애 전용 부분 인덱스
CREATE INDEX ix_incidents_open ON incidents(tenant_id, severity, created_at)
    WHERE status NOT IN ('RESOLVED', 'CLOSED');
```

---

### 4.4 incident_timeline 테이블

**SQLAlchemy 모델:**

```python
class IncidentTimeline(Base):
    __tablename__ = "incident_timeline"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    incident_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("incidents.id", ondelete="CASCADE"),
        nullable=False
    )
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        comment="NULL = 시스템 자동 이벤트"
    )
    event_type: Mapped[str] = mapped_column(
        String(100), nullable=False,
        comment="status_changed / comment / assigned / alert_linked 등"
    )
    message: Mapped[str] = mapped_column(Text, nullable=False)
    metadata: Mapped[Optional[dict]] = mapped_column(
        JSONB, nullable=True,
        comment='이전/이후 상태 {"from": "OPEN", "to": "INVESTIGATING"}'
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    incident: Mapped["Incident"] = relationship(back_populates="timeline")

    __table_args__ = (
        Index("ix_incident_timeline_incident_id", "incident_id"),
        Index("ix_incident_timeline_created_at",
              "incident_id", "created_at"),
    )
```

**DDL:**

```sql
CREATE TABLE incident_timeline (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id UUID        NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
    user_id     UUID        REFERENCES users(id) ON DELETE SET NULL,
    event_type  VARCHAR(100) NOT NULL,
    message     TEXT        NOT NULL,
    metadata    JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON COLUMN incident_timeline.user_id IS 'NULL = 시스템 자동 이벤트';
COMMENT ON COLUMN incident_timeline.event_type
    IS 'status_changed / comment / assigned / alert_linked / escalated';

CREATE INDEX ix_incident_timeline_incident_id ON incident_timeline(incident_id);
CREATE INDEX ix_incident_timeline_created_at
    ON incident_timeline(incident_id, created_at ASC);
```

---

## 5. 비용 도메인

### 5.1 cost_records 테이블 (월별 파티셔닝)

**SQLAlchemy 모델:**

```python
class CostRecord(Base):
    __tablename__ = "cost_records"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False
    )
    usage_date: Mapped[datetime] = mapped_column(
        DateTime(timezone=False), nullable=False,
        comment="비용 발생일 (날짜 정밀도)"
    )
    usage_month: Mapped[str] = mapped_column(
        String(6), nullable=False,
        comment="파티션 키 (YYYYMM 형식, 예: 202603)"
    )
    service_name: Mapped[str] = mapped_column(
        String(255), nullable=False,
        comment="OCI 서비스명 (Compute, Object Storage 등)"
    )
    resource_type: Mapped[Optional[str]] = mapped_column(
        String(255), nullable=True
    )
    oci_resource_id: Mapped[Optional[str]] = mapped_column(
        String(500), nullable=True,
        comment="OCI Resource OCID (비용 항목에 매핑된 경우)"
    )
    cost_amount: Mapped[float] = mapped_column(
        Numeric(15, 6), nullable=False,
        comment="비용 금액 (통화 단위)"
    )
    currency: Mapped[str] = mapped_column(
        String(10), nullable=False, default="USD"
    )
    usage_amount: Mapped[Optional[float]] = mapped_column(
        Numeric(15, 6), nullable=True,
        comment="사용량 수치"
    )
    usage_unit: Mapped[Optional[str]] = mapped_column(
        String(100), nullable=True,
        comment="OCPU Hours, GB-Month 등"
    )
    region: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    compartment_id: Mapped[Optional[str]] = mapped_column(
        String(500), nullable=True,
        comment="OCI Compartment OCID (비용 귀속)"
    )
    raw_data: Mapped[Optional[dict]] = mapped_column(
        JSONB, nullable=True,
        comment="OCI Cost Report 원본 행 데이터"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        Index("ix_cost_records_tenant_month", "tenant_id", "usage_month"),
        Index("ix_cost_records_tenant_date", "tenant_id", "usage_date"),
        Index("ix_cost_records_service", "tenant_id", "usage_month", "service_name"),
        # 파티셔닝은 DDL에서 PARTITION BY RANGE(usage_month)로 설정
    )
```

**DDL (파티셔닝 포함):**

```sql
-- 파티션 테이블 생성
CREATE TABLE cost_records (
    id              UUID        NOT NULL DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    usage_date      DATE        NOT NULL,
    usage_month     CHAR(6)     NOT NULL,   -- YYYYMM (파티션 키)
    service_name    VARCHAR(255) NOT NULL,
    resource_type   VARCHAR(255),
    oci_resource_id VARCHAR(500),
    cost_amount     NUMERIC(15,6) NOT NULL,
    currency        VARCHAR(10) NOT NULL DEFAULT 'USD',
    usage_amount    NUMERIC(15,6),
    usage_unit      VARCHAR(100),
    region          VARCHAR(100),
    compartment_id  VARCHAR(500),
    raw_data        JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (usage_month);

COMMENT ON TABLE cost_records IS 'OCI 일별 비용 데이터 (월별 파티셔닝)';
COMMENT ON COLUMN cost_records.usage_month IS '파티션 키: YYYYMM (예: 202603)';

-- 월별 파티션 생성 (Celery Beat Job으로 매월 자동 생성)
CREATE TABLE cost_records_202601 PARTITION OF cost_records
    FOR VALUES FROM ('202601') TO ('202602');
CREATE TABLE cost_records_202602 PARTITION OF cost_records
    FOR VALUES FROM ('202602') TO ('202603');
CREATE TABLE cost_records_202603 PARTITION OF cost_records
    FOR VALUES FROM ('202603') TO ('202604');
-- ... 이후 월별 자동 생성

-- 파티션 테이블 PK (파티션 키 포함 필수)
ALTER TABLE cost_records ADD PRIMARY KEY (id, usage_month);

-- 인덱스 (파티션별 자동 생성됨)
CREATE INDEX ix_cost_records_tenant_month   ON cost_records(tenant_id, usage_month);
CREATE INDEX ix_cost_records_tenant_date    ON cost_records(tenant_id, usage_date);
CREATE INDEX ix_cost_records_service        ON cost_records(tenant_id, usage_month, service_name);
CREATE INDEX ix_cost_records_region         ON cost_records(tenant_id, usage_month, region);

-- 다음 달 파티션 자동 생성 함수
CREATE OR REPLACE FUNCTION create_next_month_cost_partition()
RETURNS VOID AS $$
DECLARE
    next_month      CHAR(6);
    next_next_month CHAR(6);
    partition_name  TEXT;
BEGIN
    next_month      := TO_CHAR(NOW() + INTERVAL '1 month', 'YYYYMM');
    next_next_month := TO_CHAR(NOW() + INTERVAL '2 months', 'YYYYMM');
    partition_name  := 'cost_records_' || next_month;

    IF NOT EXISTS (
        SELECT FROM pg_tables
        WHERE tablename = partition_name
    ) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF cost_records FOR VALUES FROM (%L) TO (%L)',
            partition_name, next_month, next_next_month
        );
        RAISE NOTICE 'Created partition: %', partition_name;
    END IF;
END;
$$ LANGUAGE plpgsql;
```

---

### 5.2 budget_alerts 테이블

**SQLAlchemy 모델:**

```python
class BudgetAlert(Base):
    __tablename__ = "budget_alerts"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    monthly_budget: Mapped[float] = mapped_column(
        Numeric(15, 2), nullable=False,
        comment="월 예산 한도 (USD 기준)"
    )
    alert_threshold_pct: Mapped[float] = mapped_column(
        Numeric(5, 2), nullable=False, default=80.0,
        comment="알람 임계값 (예: 80 = 예산의 80% 도달 시)"
    )
    is_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    notification_channels: Mapped[Optional[dict]] = mapped_column(
        JSONB, nullable=True
    )
    last_triggered_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False,
        server_default=func.now(), onupdate=func.now()
    )

    __table_args__ = (
        Index("ix_budget_alerts_tenant_id", "tenant_id"),
    )
```

**DDL:**

```sql
CREATE TABLE budget_alerts (
    id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id             UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name                  VARCHAR(255) NOT NULL,
    monthly_budget        NUMERIC(15,2) NOT NULL,
    alert_threshold_pct   NUMERIC(5,2) NOT NULL DEFAULT 80.0,
    is_enabled            BOOLEAN     NOT NULL DEFAULT TRUE,
    notification_channels JSONB,
    last_triggered_at     TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_budget_threshold CHECK (
        alert_threshold_pct BETWEEN 0 AND 150
    )
);

CREATE INDEX ix_budget_alerts_tenant_id ON budget_alerts(tenant_id);
CREATE INDEX ix_budget_alerts_enabled ON budget_alerts(tenant_id, is_enabled)
    WHERE is_enabled = TRUE;
```

---

## 6. 작업/감사 도메인

### 6.1 jobs 테이블

**SQLAlchemy 모델:**

```python
class JobType(str, enum.Enum):
    # Compute
    INSTANCE_START = "instance_start"
    INSTANCE_STOP = "instance_stop"
    INSTANCE_REBOOT = "instance_reboot"
    INSTANCE_TERMINATE = "instance_terminate"
    INSTANCE_RESIZE = "instance_resize"
    INSTANCE_CREATE = "instance_create"
    # Storage
    VOLUME_ATTACH = "volume_attach"
    VOLUME_DETACH = "volume_detach"
    VOLUME_BACKUP = "volume_backup"
    # Networking
    LB_BACKEND_ADD = "lb_backend_add"
    LB_BACKEND_REMOVE = "lb_backend_remove"
    # Database
    ADB_START = "adb_start"
    ADB_STOP = "adb_stop"
    ADB_SCALE = "adb_scale"
    # Sync
    RESOURCE_SYNC = "resource_sync"
    COMPARTMENT_SYNC = "compartment_sync"
    # Cost
    COST_REPORT_FETCH = "cost_report_fetch"
    # Monitoring
    ALARM_SYNC = "alarm_sync"
    # OKE
    NODE_POOL_SCALE = "node_pool_scale"
    # Generic
    CUSTOM_OPERATION = "custom_operation"


class JobStatus(str, enum.Enum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCESS = "success"
    FAILED = "failed"
    CANCELLED = "cancelled"
    RETRYING = "retrying"


class Job(Base):
    __tablename__ = "jobs"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="CASCADE"),
        nullable=False
    )
    created_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        comment="NULL = 시스템 스케줄 작업"
    )
    job_type: Mapped[JobType] = mapped_column(
        SAEnum(JobType, name="job_type_enum"),
        nullable=False
    )
    status: Mapped[JobStatus] = mapped_column(
        SAEnum(JobStatus, name="job_status_enum"),
        nullable=False,
        default=JobStatus.PENDING
    )
    resource_id: Mapped[Optional[str]] = mapped_column(
        String(500), nullable=True,
        comment="대상 OCI 리소스 OCID"
    )
    resource_type: Mapped[Optional[str]] = mapped_column(
        String(100), nullable=True,
        comment="대상 리소스 타입 (instance, volume 등)"
    )
    action_params: Mapped[Optional[dict]] = mapped_column(
        JSONB, nullable=True,
        comment="작업 액션 파라미터 (리소스 OCID, 변경값 등)"
    )
    result: Mapped[Optional[dict]] = mapped_column(
        JSONB, nullable=True,
        comment="작업 결과 (성공 시)"
    )
    error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    celery_task_id: Mapped[Optional[str]] = mapped_column(
        String(255), nullable=True,
        comment="Celery Task UUID"
    )
    oci_work_request_id: Mapped[Optional[str]] = mapped_column(
        String(500), nullable=True,
        comment="OCI Work Request OCID (OCI 비동기 작업)"
    )
    progress: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0,
        comment="0-100 진행률"
    )
    progress_message: Mapped[Optional[str]] = mapped_column(
        String(500), nullable=True
    )
    started_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    completed_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    retry_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    max_retries: Mapped[int] = mapped_column(Integer, nullable=False, default=3)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False,
        server_default=func.now(), onupdate=func.now()
    )

    __table_args__ = (
        Index("ix_jobs_tenant_id", "tenant_id"),
        Index("ix_jobs_tenant_status", "tenant_id", "status"),
        Index("ix_jobs_celery_task_id", "celery_task_id"),
        Index("ix_jobs_created_by", "created_by"),
        Index("ix_jobs_created_at", "tenant_id", "created_at"),
        CheckConstraint("progress BETWEEN 0 AND 100", name="chk_jobs_progress"),
    )
```

**DDL:**

```sql
CREATE TYPE job_type_enum AS ENUM (
    'instance_start', 'instance_stop', 'instance_reboot',
    'instance_terminate', 'instance_resize', 'instance_create',
    'volume_attach', 'volume_detach', 'volume_backup',
    'lb_backend_add', 'lb_backend_remove',
    'adb_start', 'adb_stop', 'adb_scale',
    'resource_sync', 'compartment_sync',
    'cost_report_fetch', 'alarm_sync',
    'node_pool_scale', 'custom_operation'
);
CREATE TYPE job_status_enum AS ENUM (
    'pending', 'running', 'success', 'failed', 'cancelled', 'retrying'
);

CREATE TABLE jobs (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id            UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    created_by           UUID        REFERENCES users(id) ON DELETE SET NULL,
    job_type             job_type_enum NOT NULL,
    status               job_status_enum NOT NULL DEFAULT 'pending',
    resource_id          VARCHAR(500),
    resource_type        VARCHAR(100),
    action_params        JSONB,
    result               JSONB,
    error_message        TEXT,
    celery_task_id       VARCHAR(255),
    oci_work_request_id  VARCHAR(500),
    progress             INTEGER     NOT NULL DEFAULT 0
                             CHECK (progress BETWEEN 0 AND 100),
    progress_message     VARCHAR(500),
    started_at           TIMESTAMPTZ,
    completed_at         TIMESTAMPTZ,
    retry_count          INTEGER     NOT NULL DEFAULT 0,
    max_retries          INTEGER     NOT NULL DEFAULT 3,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE jobs IS 'Celery 비동기 작업 추적 (OCI 장기 작업 포함)';
COMMENT ON COLUMN jobs.resource_id IS '대상 OCI 리소스 OCID';
COMMENT ON COLUMN jobs.resource_type IS '대상 리소스 타입 (instance, volume 등)';
COMMENT ON COLUMN jobs.action_params IS '작업 액션 파라미터 (변경값, 옵션 등)';
COMMENT ON COLUMN jobs.oci_work_request_id IS 'OCI Work Request OCID (폴링으로 완료 감지)';

CREATE INDEX ix_jobs_tenant_id      ON jobs(tenant_id);
CREATE INDEX ix_jobs_tenant_status  ON jobs(tenant_id, status);
CREATE INDEX ix_jobs_tenant_created ON jobs(tenant_id, created_at DESC);
CREATE INDEX ix_jobs_celery_task_id ON jobs(celery_task_id);
CREATE INDEX ix_jobs_created_by     ON jobs(created_by);
CREATE INDEX ix_jobs_created_at     ON jobs(tenant_id, created_at DESC);
-- 진행 중인 작업 전용 부분 인덱스
CREATE INDEX ix_jobs_running ON jobs(tenant_id, created_at)
    WHERE status IN ('pending', 'running', 'retrying');
```

---

### 6.2 audit_logs 테이블 (월별 파티셔닝)

**SQLAlchemy 모델:**

```python
class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    tenant_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tenants.id", ondelete="SET NULL"),
        nullable=True,
        comment="NULL = 플랫폼 레벨 작업 (로그인 등)"
    )
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        comment="NULL = 시스템/익명 작업"
    )
    action: Mapped[str] = mapped_column(
        String(255), nullable=False,
        comment="동사_명사 형식 (instance_stop, alert_rule_create 등)"
    )
    resource_type: Mapped[Optional[str]] = mapped_column(
        String(100), nullable=True
    )
    resource_id: Mapped[Optional[str]] = mapped_column(
        String(500), nullable=True
    )
    ip_address: Mapped[Optional[str]] = mapped_column(
        String(45), nullable=True,
        comment="IPv4 / IPv6 지원"
    )
    user_agent: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="success",
        comment="success / failure / error"
    )
    error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    request_payload: Mapped[Optional[dict]] = mapped_column(
        JSONB, nullable=True,
        comment="민감 정보 마스킹 후 저장"
    )
    response_summary: Mapped[Optional[dict]] = mapped_column(
        JSONB, nullable=True
    )
    duration_ms: Mapped[Optional[int]] = mapped_column(
        Integer, nullable=True,
        comment="API 응답 소요 시간 (밀리초)"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        Index("ix_audit_logs_tenant_id", "tenant_id"),
        Index("ix_audit_logs_user_id", "user_id"),
        Index("ix_audit_logs_action", "action"),
        Index("ix_audit_logs_created_at", "tenant_id", "created_at"),
        # 파티셔닝은 DDL에서 PARTITION BY RANGE(created_at)
    )
```

**DDL (파티셔닝 포함):**

```sql
CREATE TABLE audit_logs (
    id               UUID        NOT NULL DEFAULT gen_random_uuid(),
    tenant_id        UUID        REFERENCES tenants(id) ON DELETE SET NULL,
    user_id          UUID        REFERENCES users(id) ON DELETE SET NULL,
    action           VARCHAR(255) NOT NULL,
    resource_type    VARCHAR(100),
    resource_id      VARCHAR(500),
    ip_address       VARCHAR(45),
    user_agent       TEXT,
    status           VARCHAR(20) NOT NULL DEFAULT 'success',
    error_message    TEXT,
    request_payload  JSONB,
    response_summary JSONB,
    duration_ms      INTEGER,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (created_at);

COMMENT ON TABLE audit_logs IS '모든 API 작업 감사 로그 (월별 파티셔닝, 1년 보존)';
COMMENT ON COLUMN audit_logs.request_payload IS '민감 정보(password, token) 마스킹 후 저장';

-- 월별 파티션 생성
CREATE TABLE audit_logs_2026_01 PARTITION OF audit_logs
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE audit_logs_2026_02 PARTITION OF audit_logs
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE audit_logs_2026_03 PARTITION OF audit_logs
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

-- 파티션 PK (파티션 키 포함 필수)
ALTER TABLE audit_logs ADD PRIMARY KEY (id, created_at);

-- 인덱스 (파티션별 자동 생성)
CREATE INDEX ix_audit_logs_tenant_created ON audit_logs(tenant_id, created_at DESC);
CREATE INDEX ix_audit_logs_user_id        ON audit_logs(user_id, created_at DESC);
CREATE INDEX ix_audit_logs_action         ON audit_logs(action, created_at DESC);
CREATE INDEX ix_audit_logs_ip             ON audit_logs(ip_address, created_at DESC);

-- 다음 달 파티션 자동 생성 함수
CREATE OR REPLACE FUNCTION create_next_month_audit_partition()
RETURNS VOID AS $$
DECLARE
    next_month_start TIMESTAMPTZ;
    next_month_end   TIMESTAMPTZ;
    partition_name   TEXT;
BEGIN
    next_month_start := DATE_TRUNC('month', NOW() + INTERVAL '1 month');
    next_month_end   := next_month_start + INTERVAL '1 month';
    partition_name   := 'audit_logs_' || TO_CHAR(next_month_start, 'YYYY_MM');

    IF NOT EXISTS (
        SELECT FROM pg_tables WHERE tablename = partition_name
    ) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF audit_logs FOR VALUES FROM (%L) TO (%L)',
            partition_name, next_month_start, next_month_end
        );
        RAISE NOTICE 'Created partition: %', partition_name;
    END IF;
END;
$$ LANGUAGE plpgsql;
```

---

## 7. 멀티 테넌트 RLS 정책

### 7.1 PostgreSQL RLS 활성화

```sql
-- ============================================================
-- 1. RLS 활성화 (테넌트 격리 대상 테이블)
-- ============================================================
ALTER TABLE tenants                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_credentials      ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_sla              ENABLE ROW LEVEL SECURITY;
ALTER TABLE sla_measurements        ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_tenant_roles       ENABLE ROW LEVEL SECURITY;
ALTER TABLE oci_compartments        ENABLE ROW LEVEL SECURITY;
ALTER TABLE oci_resources           ENABLE ROW LEVEL SECURITY;
ALTER TABLE alert_rules             ENABLE ROW LEVEL SECURITY;
ALTER TABLE alerts                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE incidents               ENABLE ROW LEVEL SECURITY;
ALTER TABLE incident_timeline       ENABLE ROW LEVEL SECURITY;
ALTER TABLE cost_records            ENABLE ROW LEVEL SECURITY;
ALTER TABLE budget_alerts           ENABLE ROW LEVEL SECURITY;
ALTER TABLE jobs                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs              ENABLE ROW LEVEL SECURITY;

-- Super Admin도 RLS 정책의 영향을 받도록 강제
-- (BYPASSRLS 권한 없는 msp_app 역할이 super_admin 정책을 통해 접근)
-- FORCE ROW LEVEL SECURITY: 테이블 소유자도 RLS 적용
ALTER TABLE tenants                 FORCE ROW LEVEL SECURITY;
ALTER TABLE oci_resources           FORCE ROW LEVEL SECURITY;
ALTER TABLE alerts                  FORCE ROW LEVEL SECURITY;
ALTER TABLE incidents               FORCE ROW LEVEL SECURITY;
ALTER TABLE cost_records            FORCE ROW LEVEL SECURITY;
ALTER TABLE audit_logs              FORCE ROW LEVEL SECURITY;
ALTER TABLE oci_compartments        FORCE ROW LEVEL SECURITY;
ALTER TABLE alert_rules             FORCE ROW LEVEL SECURITY;
ALTER TABLE jobs                    FORCE ROW LEVEL SECURITY;

-- ============================================================
-- 2. 애플리케이션 DB 사용자 (BYPASSRLS 권한 없음)
-- ============================================================
CREATE ROLE msp_app LOGIN PASSWORD 'strong-password';
GRANT CONNECT ON DATABASE msp_db TO msp_app;
GRANT USAGE ON SCHEMA public TO msp_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO msp_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO msp_app;

-- 관리 작업용 슈퍼유저 (마이그레이션, 배치 작업) - BYPASSRLS로 RLS 우회 가능
CREATE ROLE msp_admin LOGIN PASSWORD 'admin-password' BYPASSRLS;
```

### 7.2 RLS Policy 정의

```sql
-- ============================================================
-- 헬퍼: 현재 세션의 tenant_id 반환
-- ============================================================
CREATE OR REPLACE FUNCTION current_tenant_id()
RETURNS UUID AS $$
BEGIN
    -- app.current_tenant_id가 설정되지 않으면 NULL 반환 → 아무것도 보이지 않음
    RETURN NULLIF(current_setting('app.current_tenant_id', true), '')::UUID;
EXCEPTION
    WHEN invalid_text_representation THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- tenants
-- ============================================================
CREATE POLICY tenant_isolation ON tenants
    USING (id = current_tenant_id());

-- super_admin: 모든 테넌트 조회 허용
CREATE POLICY tenant_super_admin_bypass ON tenants
    USING (
        current_setting('app.current_tenant_id', true) IS NULL
        OR EXISTS (
            SELECT 1 FROM user_tenant_roles utr
            JOIN roles r ON r.id = utr.role_id
            WHERE utr.user_id = current_setting('app.current_user_id', true)::UUID
              AND r.name = 'super_admin'
        )
    );

-- ============================================================
-- tenant_credentials
-- ============================================================
CREATE POLICY tenant_credentials_isolation ON tenant_credentials
    USING (tenant_id = current_tenant_id());

-- ============================================================
-- tenant_sla
-- ============================================================
CREATE POLICY tenant_sla_isolation ON tenant_sla
    USING (tenant_id = current_tenant_id());

-- ============================================================
-- sla_measurements
-- ============================================================
CREATE POLICY sla_measurements_isolation ON sla_measurements
    USING (tenant_id = current_tenant_id());

-- ============================================================
-- user_tenant_roles
-- ============================================================
CREATE POLICY user_tenant_roles_isolation ON user_tenant_roles
    USING (tenant_id = current_tenant_id());

-- ============================================================
-- oci_compartments
-- ============================================================
CREATE POLICY oci_compartments_isolation ON oci_compartments
    USING (tenant_id = current_tenant_id());

-- ============================================================
-- oci_resources
-- ============================================================
CREATE POLICY oci_resources_isolation ON oci_resources
    USING (tenant_id = current_tenant_id());

-- ============================================================
-- alert_rules
-- ============================================================
CREATE POLICY alert_rules_isolation ON alert_rules
    USING (tenant_id = current_tenant_id());

-- ============================================================
-- alerts
-- ============================================================
CREATE POLICY alerts_isolation ON alerts
    USING (tenant_id = current_tenant_id());

-- ============================================================
-- incidents
-- ============================================================
CREATE POLICY incidents_isolation ON incidents
    USING (tenant_id = current_tenant_id());

-- ============================================================
-- incident_timeline (incidents를 통해 tenant_id 확인)
-- ============================================================
CREATE POLICY incident_timeline_isolation ON incident_timeline
    USING (
        EXISTS (
            SELECT 1 FROM incidents i
            WHERE i.id = incident_timeline.incident_id
              AND i.tenant_id = current_tenant_id()
        )
    );

-- ============================================================
-- cost_records
-- ============================================================
CREATE POLICY cost_records_isolation ON cost_records
    USING (tenant_id = current_tenant_id());

-- ============================================================
-- budget_alerts
-- ============================================================
CREATE POLICY budget_alerts_isolation ON budget_alerts
    USING (tenant_id = current_tenant_id());

-- ============================================================
-- jobs
-- ============================================================
CREATE POLICY jobs_isolation ON jobs
    USING (tenant_id = current_tenant_id());

-- ============================================================
-- audit_logs
-- ============================================================
CREATE POLICY audit_logs_isolation ON audit_logs
    USING (tenant_id = current_tenant_id());

-- ============================================================
-- super_admin: 모든 테넌트 데이터 접근 (별도 Role)
-- ============================================================
-- super_admin 사용자는 BYPASSRLS 역할을 부여하거나
-- 별도 Policy로 처리
CREATE POLICY super_admin_bypass ON oci_resources
    USING (
        EXISTS (
            SELECT 1 FROM user_tenant_roles utr
            JOIN roles r ON r.id = utr.role_id
            WHERE utr.user_id = current_setting('app.current_user_id', true)::UUID
              AND r.name = 'super_admin'
        )
    );
```

### 7.3 SQLAlchemy에서 RLS 적용 패턴

```python
# app/db/session.py
from contextlib import asynccontextmanager
from typing import AsyncGenerator, Optional
import uuid
from sqlalchemy.ext.asyncio import (
    AsyncSession, create_async_engine, async_sessionmaker
)
from sqlalchemy import text

from app.core.config import settings

engine = create_async_engine(
    settings.DATABASE_URL,
    pool_size=20,
    max_overflow=40,
    pool_pre_ping=True,
    echo=settings.DB_ECHO,
)

AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


@asynccontextmanager
async def get_tenant_session(
    tenant_id: uuid.UUID,
    user_id: Optional[uuid.UUID] = None,
) -> AsyncGenerator[AsyncSession, None]:
    """
    테넌트 격리 세션: SET LOCAL로 RLS 컨텍스트 설정.
    트랜잭션 내에서만 유효 (SET LOCAL은 트랜잭션 경계에서 리셋).
    """
    async with AsyncSessionLocal() as session:
        async with session.begin():
            # RLS 컨텍스트 설정 (트랜잭션 범위)
            await session.execute(
                text("SET LOCAL app.current_tenant_id = :tenant_id"),
                {"tenant_id": str(tenant_id)}
            )
            if user_id:
                await session.execute(
                    text("SET LOCAL app.current_user_id = :user_id"),
                    {"user_id": str(user_id)}
                )
            yield session
        # 트랜잭션 종료 시 SET LOCAL 값 자동 초기화


# app/api/dependencies.py
from fastapi import Depends, Request
from app.core.security import verify_jwt_token
from app.db.session import get_tenant_session

async def get_db_with_tenant(
    request: Request,
    token_payload: dict = Depends(verify_jwt_token),
):
    """
    FastAPI 의존성: 현재 요청의 tenant_id를 RLS에 적용한 세션 반환.
    """
    tenant_id = uuid.UUID(token_payload["tenant_id"])
    user_id = uuid.UUID(token_payload["sub"])

    async with get_tenant_session(tenant_id, user_id) as session:
        yield session


# app/workers/base_task.py (Celery Task에서 RLS 적용)
from celery import Task
from app.db.session import AsyncSessionLocal

class TenantAwareTask(Task):
    """
    Celery Task Base Class: 비동기 DB 세션에 RLS 적용.
    사용법: @celery_app.task(base=TenantAwareTask)
    """
    async def get_tenant_db(self, tenant_id: uuid.UUID) -> AsyncSession:
        session = AsyncSessionLocal()
        await session.execute(
            text("SET LOCAL app.current_tenant_id = :tenant_id"),
            {"tenant_id": str(tenant_id)}
        )
        return session


# app/db/rls_event.py
# SQLAlchemy 이벤트 훅: 세션 생성 시 app.current_tenant_id 자동 설정
from sqlalchemy import event
from sqlalchemy.ext.asyncio import AsyncSession


def register_rls_event_hooks(session_factory):
    """
    async_sessionmaker에 이벤트 훅을 등록해 매 트랜잭션 시작 시
    세션 info 딕셔너리의 tenant_id / user_id를 PostgreSQL 세션 변수로 자동 주입.

    사용법:
        AsyncSessionLocal = async_sessionmaker(engine, ...)
        register_rls_event_hooks(AsyncSessionLocal)
    """
    @event.listens_for(session_factory, "after_transaction_create")
    def set_tenant_context(session, transaction):
        tenant_id = session.info.get("tenant_id")
        user_id = session.info.get("user_id")
        if tenant_id:
            session.execute(
                text("SET LOCAL app.current_tenant_id = :tenant_id"),
                {"tenant_id": str(tenant_id)}
            )
        if user_id:
            session.execute(
                text("SET LOCAL app.current_user_id = :user_id"),
                {"user_id": str(user_id)}
            )


# 사용 예시: 세션 생성 시 info 딕셔너리에 tenant_id 전달
# async with AsyncSessionLocal() as session:
#     session.info["tenant_id"] = tenant_id
#     session.info["user_id"] = user_id
#     # 이후 쿼리는 RLS 자동 적용
```

### 7.4 RLS 성능 영향 및 인덱스 대응

```
RLS Policy 평가 시 발생하는 추가 조건이 쿼리 플래너에 영향을 미칩니다.

문제: WHERE tenant_id = current_tenant_id() 조건이 매 쿼리에 추가됨
대응:
  1. 모든 테넌트 격리 테이블에 (tenant_id, ...) 복합 인덱스 필수
  2. current_tenant_id() 함수를 STABLE로 선언 → 쿼리 내 캐싱
  3. EXPLAIN (ANALYZE, BUFFERS) 로 Index Scan 확인

성능 목표:
  - tenant_id 조건 포함 쿼리: Index Scan (Seq Scan 금지)
  - RLS 오버헤드: < 1ms per query
```

```sql
-- RLS 동작 확인 쿼리
SET app.current_tenant_id = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx';
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
    SELECT * FROM oci_resources
    WHERE resource_type = 'instance' AND status = 'running';
-- RLS 정책이 tenant_id 조건을 자동 추가하는지 확인
```

---

## 8. 인덱스 전략

### 8.1 핵심 쿼리 패턴별 인덱스

```sql
-- ============================================================
-- 패턴 1: 테넌트별 리소스 목록 (가장 빈번한 조회)
-- ============================================================
-- Query: SELECT * FROM oci_resources
--        WHERE tenant_id = ? AND resource_type = ? AND status != 'terminated'
CREATE INDEX ix_oci_resources_tenant_type_status
    ON oci_resources(tenant_id, resource_type, status)
    WHERE status != 'terminated';

-- ============================================================
-- 패턴 2: 활성 알람 대시보드
-- ============================================================
-- Query: SELECT * FROM alerts
--        WHERE tenant_id = ? AND status = 'FIRING'
--        ORDER BY fired_at DESC LIMIT 50
CREATE INDEX ix_alerts_dashboard
    ON alerts(tenant_id, fired_at DESC)
    WHERE status = 'FIRING';

-- ============================================================
-- 패턴 3: 비용 월별 집계
-- ============================================================
-- Query: SELECT service_name, SUM(cost_amount)
--        FROM cost_records
--        WHERE tenant_id = ? AND usage_month = '202603'
--        GROUP BY service_name
CREATE INDEX ix_cost_records_agg
    ON cost_records(tenant_id, usage_month, service_name);

-- ============================================================
-- 패턴 4: OCI 태그 기반 리소스 검색
-- ============================================================
-- Query: SELECT * FROM oci_resources
--        WHERE tenant_id = ? AND tags @> '{"env": "prod"}'
CREATE INDEX ix_oci_resources_tags_gin
    ON oci_resources USING gin(tags);

-- Query: JSONB 내부 경로 검색
CREATE INDEX ix_oci_resources_data_gin
    ON oci_resources USING gin(resource_data jsonb_path_ops);

-- ============================================================
-- 패턴 5: 감사 로그 사용자별 조회
-- ============================================================
-- Query: SELECT * FROM audit_logs
--        WHERE tenant_id = ? AND user_id = ?
--        AND created_at >= NOW() - INTERVAL '7 days'
--        ORDER BY created_at DESC
CREATE INDEX ix_audit_logs_user_created
    ON audit_logs(tenant_id, user_id, created_at DESC);

-- ============================================================
-- 패턴 6: Celery 작업 상태 폴링
-- ============================================================
-- Query: SELECT * FROM jobs WHERE celery_task_id = ?
CREATE INDEX ix_jobs_celery_task_id ON jobs(celery_task_id);

-- Query: OCI Work Request 완료 확인
CREATE INDEX ix_jobs_oci_work_request ON jobs(oci_work_request_id)
    WHERE oci_work_request_id IS NOT NULL AND status = 'running';

-- ============================================================
-- 패턴 7: 미해결 인시던트 + SLA 계산
-- ============================================================
-- Query: SELECT * FROM incidents
--        WHERE tenant_id = ? AND status NOT IN ('RESOLVED', 'CLOSED')
--        AND created_at < NOW() - (response_time_critical_min || ' minutes')::INTERVAL
CREATE INDEX ix_incidents_sla_check
    ON incidents(tenant_id, severity, created_at)
    WHERE status NOT IN ('RESOLVED', 'CLOSED');

-- ============================================================
-- 패턴 8: Compartment 계층 탐색
-- ============================================================
-- Query: SELECT * FROM oci_compartments WHERE parent_compartment_id = ?
CREATE INDEX ix_oci_compartments_parent_tenant
    ON oci_compartments(parent_compartment_id, tenant_id);

-- ============================================================
-- 패턴 9: 비용 추세 분석 (최근 6개월)
-- ============================================================
CREATE INDEX ix_cost_records_trend
    ON cost_records(tenant_id, usage_date DESC, service_name);
```

### 8.2 JSONB 인덱스 전략

```sql
-- GIN 인덱스: @> 연산자 (포함 검색)
CREATE INDEX ix_oci_resources_tags_gin ON oci_resources
    USING gin(tags);

-- jsonb_path_ops: 경로 기반 검색 최적화 (용량 절약)
CREATE INDEX ix_oci_resources_data_path ON oci_resources
    USING gin(resource_data jsonb_path_ops);

-- 특정 JSONB 키의 일반 인덱스 (카디널리티 높은 경우)
CREATE INDEX ix_oci_resources_region_tag ON oci_resources
    ((resource_data->>'region'));

-- 알람 규칙의 OCI alarm ID 조회
CREATE INDEX ix_alert_rules_oci_alarm ON alert_rules(oci_alarm_id)
    WHERE oci_alarm_id IS NOT NULL;
```

### 8.3 파티션 프루닝 최적화

```sql
-- cost_records 파티션 프루닝 활성화 확인
SET enable_partition_pruning = on;  -- 기본값 on

-- 효과적인 파티션 프루닝 쿼리 패턴
-- 반드시 usage_month (파티션 키)를 WHERE 조건에 포함
SELECT service_name, SUM(cost_amount)
FROM cost_records
WHERE tenant_id = $1
  AND usage_month = '202603'  -- 파티션 프루닝 적용
GROUP BY service_name;

-- 범위 쿼리: 직전 3개월
SELECT *
FROM cost_records
WHERE tenant_id = $1
  AND usage_month BETWEEN '202601' AND '202603';  -- 3개 파티션만 스캔
```

---

## 9. 데이터 보존 및 아카이빙

### 9.1 보존 정책 테이블

```python
class ArchivePolicy(Base):
    __tablename__ = "archive_policies"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    table_name: Mapped[str] = mapped_column(
        String(100), nullable=False, unique=True
    )
    retention_days: Mapped[int] = mapped_column(
        Integer, nullable=False,
        comment="DB 보존 기간 (일)"
    )
    archive_days: Mapped[Optional[int]] = mapped_column(
        Integer, nullable=True,
        comment="Object Storage 보존 기간 (일, NULL=영구)"
    )
    archive_bucket: Mapped[Optional[str]] = mapped_column(
        String(255), nullable=True,
        comment="OCI Object Storage 버킷명"
    )
    is_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    last_archived_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False,
        server_default=func.now(), onupdate=func.now()
    )
```

```sql
CREATE TABLE archive_policies (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name        VARCHAR(100) NOT NULL UNIQUE,
    retention_days    INTEGER     NOT NULL,
    archive_days      INTEGER,
    archive_bucket    VARCHAR(255),
    is_enabled        BOOLEAN     NOT NULL DEFAULT TRUE,
    last_archived_at  TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 기본 보존 정책 초기 데이터
INSERT INTO archive_policies (table_name, retention_days, archive_days, archive_bucket) VALUES
    ('audit_logs',   365,  2555, 'msp-archive-audit-logs'),    -- DB 1년, Object Storage 7년
    ('cost_records', 730,  3650, 'msp-archive-cost-records'),  -- DB 2년, Object Storage 10년
    ('alerts',       180,   365, 'msp-archive-alerts'),        -- DB 6개월, Object Storage 1년
    ('jobs',          90,   365, 'msp-archive-jobs'),          -- DB 3개월, Object Storage 1년
    ('incident_timeline', 365, 2555, 'msp-archive-incidents'); -- DB 1년, Object Storage 7년
```

### 9.2 Object Storage 아카이빙 절차

```python
# app/workers/archiving_tasks.py
import json
import gzip
from datetime import datetime, timedelta
import oci
from celery import shared_task
from sqlalchemy import text
from app.db.session import AsyncSessionLocal
from app.core.config import settings


@shared_task(name="archive.audit_logs_monthly")
async def archive_audit_logs_monthly():
    """
    매월 1일 실행: 보존 기간 초과 audit_logs 파티션을
    OCI Object Storage로 아카이빙 후 파티션 DROP.
    """
    cutoff_month = datetime.now() - timedelta(days=365)
    partition_name = f"audit_logs_{cutoff_month.strftime('%Y_%m')}"
    object_name = f"audit_logs/{cutoff_month.strftime('%Y/%m')}/dump.jsonl.gz"

    async with AsyncSessionLocal() as session:
        # 1. 파티션 데이터 추출
        result = await session.execute(
            text(f"SELECT row_to_json(t) FROM {partition_name} t")
        )
        rows = result.fetchall()

        # 2. JSONL GZ 압축
        content = gzip.compress(
            b"\n".join(json.dumps(row[0]).encode() for row in rows)
        )

        # 3. OCI Object Storage 업로드
        object_storage_client = oci.object_storage.ObjectStorageClient(
            config=settings.OCI_CONFIG
        )
        namespace = object_storage_client.get_namespace().data
        object_storage_client.put_object(
            namespace_name=namespace,
            bucket_name="msp-archive-audit-logs",
            object_name=object_name,
            put_object_body=content,
            content_type="application/x-gzip",
        )

        # 4. 파티션 DROP
        await session.execute(
            text(f"DROP TABLE IF EXISTS {partition_name}")
        )
        await session.commit()

    # 5. archive_policies.last_archived_at 갱신
    async with AsyncSessionLocal() as session:
        await session.execute(
            text("""
                UPDATE archive_policies
                SET last_archived_at = NOW()
                WHERE table_name = 'audit_logs'
            """)
        )
        await session.commit()


@shared_task(name="archive.cost_records_monthly")
async def archive_cost_records_monthly():
    """cost_records 파티션 아카이빙 (2년 초과분)."""
    cutoff_month = (datetime.now() - timedelta(days=730)).strftime('%Y%m')
    partition_name = f"cost_records_{cutoff_month}"
    # ... 위와 동일한 패턴
```

### 9.3 Alembic 마이그레이션 네이밍 컨벤션

```python
# alembic/env.py 설정
from alembic import context

# 네이밍 컨벤션 적용 (PostgreSQL 제약조건명 충돌 방지)
from sqlalchemy import MetaData

NAMING_CONVENTION = {
    "ix": "ix_%(table_name)s_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}

metadata = MetaData(naming_convention=NAMING_CONVENTION)
```

```
# 마이그레이션 파일 네이밍 규칙
alembic/versions/
├── 20260101_0001_create_tenants_and_users.py
├── 20260101_0002_create_oci_resources.py
├── 20260101_0003_create_monitoring.py
├── 20260101_0004_create_cost_domain.py
├── 20260101_0005_create_jobs_and_audit.py
├── 20260101_0006_enable_rls_policies.py
├── 20260101_0007_create_indexes.py
└── 20260201_0001_add_incident_timeline_metadata.py

# 형식: YYYYMMDD_NNNN_동사_대상.py
# 예시:
#   20260315_0001_add_tenant_sla_table.py
#   20260320_0001_add_index_oci_resources_tags.py
#   20260401_0001_create_cost_records_202604_partition.py
```

```python
# 마이그레이션 파일 템플릿
# alembic/versions/20260321_0001_add_incident_rca_field.py

"""Add rca_summary to incidents

Revision ID: 20260321_0001
Revises: 20260101_0005
Create Date: 2026-03-21 09:00:00.000000
"""
from alembic import op
import sqlalchemy as sa

revision = '20260321_0001'
down_revision = '20260101_0005'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'incidents',
        sa.Column('rca_summary', sa.Text(), nullable=True,
                  comment='Root Cause Analysis 요약')
    )


def downgrade() -> None:
    op.drop_column('incidents', 'rca_summary')
```

---

## 10. PostgreSQL → OCI ATP 마이그레이션 고려사항

### 10.1 주요 차이점 및 대응 방안

| 항목 | PostgreSQL | OCI ATP (Oracle) | 대응 방안 |
|------|-----------|-------------------|-----------|
| **ENUM 타입** | `CREATE TYPE ... AS ENUM` | `VARCHAR2` + CHECK | SQLAlchemy에서 String으로 전환, CHECK 제약 추가 |
| **UUID** | `UUID` native | `RAW(16)` 또는 `VARCHAR2(36)` | `mapped_column(String(36))` 전환 |
| **JSONB** | JSONB (바이너리 JSON) | JSON (텍스트 저장) | JSON 연산자 호환 확인 필요 |
| **TIMESTAMPTZ** | 타임존 포함 | `TIMESTAMP WITH TIME ZONE` | 호환 |
| **파티셔닝** | RANGE 파티셔닝 | 지원 (문법 동일) | 호환 |
| **RLS** | Row Level Security | VPD (Virtual Private Database) | VPD 정책으로 재구현 필요 |
| **asyncpg** | 지원 | 미지원 → `cx_Oracle` / `python-oracledb` | 드라이버 전환 필요 |
| **gen_random_uuid()** | 기본 함수 | `SYS_GUID()` | `default=uuid.uuid4` (Python 생성) |
| **NUMERIC** | 완전 호환 | `NUMBER(p,s)` | 호환 |
| **BOOLEAN** | 지원 | `NUMBER(1)` (0/1) | SQLAlchemy Boolean 타입으로 추상화 |

### 10.2 SQLAlchemy 추상화 레이어

```python
# app/db/types.py
# DB 종류에 따라 적절한 타입 선택하는 추상화

import uuid
from sqlalchemy import String, Text
from sqlalchemy.dialects.postgresql import UUID as PG_UUID, JSONB as PG_JSONB
from sqlalchemy.types import TypeDecorator, VARCHAR, Text as SAText
from app.core.config import settings


class PortableUUID(TypeDecorator):
    """PostgreSQL UUID ↔ Oracle VARCHAR2(36) 호환 타입."""
    impl = VARCHAR(36)
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == 'postgresql':
            return dialect.type_descriptor(PG_UUID())
        return dialect.type_descriptor(VARCHAR(36))

    def process_bind_param(self, value, dialect):
        if value is None:
            return value
        if dialect.name == 'postgresql':
            return value
        return str(value) if isinstance(value, uuid.UUID) else value

    def process_result_value(self, value, dialect):
        if value is None:
            return value
        return uuid.UUID(str(value))


class PortableJSON(TypeDecorator):
    """PostgreSQL JSONB ↔ Oracle JSON 호환 타입."""
    impl = SAText
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == 'postgresql':
            return dialect.type_descriptor(PG_JSONB())
        return dialect.type_descriptor(SAText())

    def process_bind_param(self, value, dialect):
        if value is None:
            return value
        if dialect.name == 'postgresql':
            return value
        import json
        return json.dumps(value, ensure_ascii=False)

    def process_result_value(self, value, dialect):
        if value is None:
            return value
        if isinstance(value, (dict, list)):
            return value
        import json
        return json.loads(value)
```

### 10.3 OCI ATP VPD (Virtual Private Database) 구현

```sql
-- Oracle ATP에서의 멀티 테넌트 격리 (VPD 방식)
-- PostgreSQL RLS를 대체

-- VPD 정책 함수
CREATE OR REPLACE FUNCTION msp_tenant_policy(
    schema_name IN VARCHAR2,
    table_name  IN VARCHAR2
) RETURN VARCHAR2 AS
    tenant_id VARCHAR2(36);
BEGIN
    tenant_id := SYS_CONTEXT('MSP_CTX', 'TENANT_ID');
    IF tenant_id IS NULL THEN
        RETURN '1=0';  -- 테넌트 미설정 시 아무것도 조회 불가
    END IF;
    RETURN 'tenant_id = ''' || tenant_id || '''';
END;
/

-- VPD 정책 등록
BEGIN
    DBMS_RLS.ADD_POLICY(
        object_schema   => 'MSP',
        object_name     => 'OCI_RESOURCES',
        policy_name     => 'TENANT_ISOLATION',
        function_schema => 'MSP',
        policy_function => 'MSP_TENANT_POLICY',
        statement_types => 'SELECT, INSERT, UPDATE, DELETE',
        update_check    => TRUE
    );
END;
/

-- SQLAlchemy에서 Oracle Application Context 설정
-- (PostgreSQL의 SET LOCAL app.current_tenant_id 대체)
from sqlalchemy import event
from sqlalchemy.ext.asyncio import AsyncSession

@event.listens_for(AsyncSession, "after_begin")
def set_oracle_tenant_context(session, transaction, connection):
    tenant_id = getattr(session.info, 'tenant_id', None)
    if tenant_id:
        connection.execute(
            "BEGIN DBMS_SESSION.SET_CONTEXT('MSP_CTX', 'TENANT_ID', :1); END;",
            [str(tenant_id)]
        )
```

### 10.4 마이그레이션 실행 계획

```
Phase 1: 병렬 운영 (PostgreSQL Primary)
  - PostgreSQL에서 운영
  - OCI ATP 인스턴스 프로비저닝 및 스키마 생성
  - SQLAlchemy 모델 portable 타입으로 전환

Phase 2: 데이터 마이그레이션
  - OCI Database Migration Service (DMS) 사용
  - 실시간 CDC (Change Data Capture) 복제
  - 테넌트별 순차 전환 (트래픽 분리)

Phase 3: OCI ATP 전환
  - DATABASE_URL 환경변수 변경
  - asyncpg → python-oracledb 드라이버 교체
  - VPD 정책 활성화 검증

Phase 4: PostgreSQL 인스턴스 종료
  - 30일 모니터링 후 철거

전환 시 체크리스트:
  [ ] PortableUUID / PortableJSON 타입 전환 완료
  [ ] ENUM → VARCHAR + CHECK 제약 전환
  [ ] gen_random_uuid() → Python uuid.uuid4() 전환
  [ ] RLS Policy → VPD Policy 전환
  [ ] asyncpg → python-oracledb 드라이버 전환
  [ ] 연결 문자열 형식 변경 (postgresql+asyncpg:// → oracle+oracledb://)
  [ ] 파티셔닝 문법 검증
  [ ] 성능 테스트 (부하 동일 조건)
```

### 10.5 환경별 DATABASE_URL 설정

```bash
# PostgreSQL (개발/MVP)
DATABASE_URL=postgresql+asyncpg://msp_app:password@localhost:5432/msp_db

# OCI ATP (운영)
DATABASE_URL=oracle+oracledb://msp_app:password@(description=(address=(protocol=tcps)(host=xxx.adb.ap-seoul-1.oraclecloud.com)(port=1522))(connect_data=(service_name=xxx_high.adb.oraclecloud.com))(security=(ssl_server_dn_match=yes)))

# OCI ATP Wallet 경로
TNS_ADMIN=/opt/oracle/wallet
```

---

## 부록: 전체 초기화 스크립트 실행 순서

```bash
# 1. DB 생성
createdb msp_db

# 2. Alembic 초기 마이그레이션
cd apps/api
uv run alembic upgrade head

# 3. 기본 데이터 삽입 (roles, archive_policies)
uv run python -m app.db.seed

# 4. RLS 정책 적용
psql -d msp_db -f infrastructure/db/rls_policies.sql

# 5. 파티션 초기 생성 (향후 6개월)
psql -d msp_db -f infrastructure/db/create_partitions.sql

# 6. 파티션 자동 생성 Celery Beat 스케줄 등록
# (celerybeat_schedule에 monthly partition creation task 등록)
```

---

> **문서 버전 이력**
>
> | 버전 | 날짜 | 변경 사항 |
> |------|------|-----------|
> | 1.0  | 2026-03-21 | 최초 작성 (전체 도메인 설계 확정) |
> | 1.1  | 2026-03-21 | TenantStatus에 onboarding 추가, jobs 테이블에 resource_id/resource_type/action_params 컬럼 추가, sla_measurements 테이블 신설, users 테이블에 MFA 컬럼 추가, alert_rules.condition_operator CHECK 제약 추가, RLS 섹션에 tenants/sla_measurements/FORCE ROW LEVEL SECURITY/SQLAlchemy 이벤트 훅 패턴 추가 |
