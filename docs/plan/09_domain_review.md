# OCI MSP Platform - 수석 도메인 기획자 리뷰 보고서

> 검토자: 수석 도메인 기획자 (Chief Domain Architect)
> 검토일: 2026-03-21
> 검토 대상: system-architecture.md, database-design.md, api-design.md, security-design.md, infrastructure-devops.md, 00_index.md, 03_screen_designs.md, 04_components.md
> 문서 버전: 모두 v1.0 (2026-03-21 작성)

---

## 종합 평가 (Executive Summary)

### 전체 점수: 8.1 / 10

이 문서 세트는 OCI 기반 MSP 플랫폼의 설계를 위한 상당히 완성도 높은 청사진을 제공한다. 특히 보안 설계의 깊이(STRIDE 위협 모델, JWT Refresh Token 패밀리 탈취 감지, Fernet 이중 암호화), 데이터베이스 설계의 구체성(SQLAlchemy 모델 + DDL 병기), 그리고 UI/UX의 실용적 컴포넌트 설계가 두드러진다.

### 핵심 강점

1. **보안 설계의 심층성**: STRIDE 매트릭스, JWT 알고리즘 고정, Refresh Token 패밀리 탈취 감지, 90일 자동 Key Rotation까지 프로덕션 수준의 보안 패턴이 적용되어 있다.
2. **DB 설계의 실행 가능성**: SQLAlchemy 모델과 DDL을 병기하여 구현 팀이 즉시 활용 가능한 수준의 구체성을 달성했다.
3. **모듈 경계(Bounded Context)의 명확성**: Tenant Manager, Resource Manager, Monitoring Collector, Incident Manager, Cost Module의 책임과 인터페이스가 명확하게 정의되어 있다.
4. **인프라 IaC 완성도**: Terraform 모듈 구조, Kubernetes 매니페스트, GitHub Actions CI/CD 파이프라인이 실제 배포 가능한 수준으로 작성되어 있다.
5. **UI/UX 개발 우선순위**: Week별 개발 순서와 컴포넌트 의존성 맵이 체계적으로 정리되어 있다.

### 핵심 우려점

1. **MVP 범위 경계의 불명확성**: "조회는 MVP, 변경은 Phase 2" 원칙이 일부 설계서에서 혼재되어 있다. API 설계서에 `PATCH /tenants/{id}` 같은 변경 API가 MVP 범위로 포함된 반면, 인스턴스 시작/중지가 MVP에 포함된다는 명시적 근거가 부족하다.
2. **Redis 단일 장애 점 위험**: Redis를 캐시, Celery 브로커, WebSocket Pub/Sub, Rate Limit 토큰 버킷, JWT 블랙리스트 등 5가지 역할에 동시 사용하면서 Redis 장애 시 전체 플랫폼의 연쇄 장애 시나리오가 다루어지지 않았다.
3. **멀티 리전 복잡성 대비 부족**: 테넌트가 여러 OCI 리전을 사용할 때의 API 라우팅, 캐시 무효화, Rate Limit 계산 방식이 명확하지 않다.
4. **MFA 복구 코드 해시 알고리즘 문제**: 보안 설계서에서 복구 코드 해시에 SHA-256을 사용하면서 "Argon2 권장"이라고 주석을 달았으나 실제 코드는 SHA-256을 사용한다. 이는 보안 설계 결정의 불일치다.
5. **Celery Beat 단일 인스턴스 위험**: Celery Beat를 단일 인스턴스(replicas: 1)로 운영하면서 이중화 전략이 없다.

---

## 문서별 상세 리뷰

---

### 1. 시스템 아키텍처 리뷰 (점수: 8.5 / 10)

#### 긍정 평가

- **전체 컴포넌트 구조의 명확성**: ASCII 다이어그램으로 OCI Load Balancer → API Gateway → OKE → 내부 인프라 → 고객 테넌시까지의 흐름이 한눈에 파악된다.
- **Modular Monolith 전략의 타당성**: 초기에 단일 FastAPI 프로세스로 시작하고 Bounded Context 경계를 미리 정의하여 이후 마이크로서비스 분리를 용이하게 한 접근은 MSP 스타트업 단계에 적합하다.
- **캐싱 전략의 세분화**: OCI 리소스 조회 흐름에서 Cache Hit/Miss 분기, OCI Rate Limit 토큰 확인 후 SDK 호출, 결과 캐시 저장까지의 흐름이 시퀀스 다이어그램으로 명확하게 표현되어 있다.
- **OCI 서비스 목록의 체계성**: MSP 플랫폼에서 사용하는 OCI 서비스 전체 목록과 Phase 2 전환 대상이 구분되어 있다.
- **WebSocket 아키텍처**: Redis Pub/Sub 기반 이벤트 발행 → WebSocket Gateway → 브라우저 전달 흐름이 잘 설계되어 있다.

#### 개선 필요 사항

**[Critical] Redis 다중 역할에 따른 단일 장애점 미처리**

Redis를 (1) API 응답 캐시, (2) Celery 브로커, (3) JWT 블랙리스트, (4) Rate Limit 토큰 버킷, (5) WebSocket Pub/Sub의 5가지 역할로 동시에 사용한다. Redis 장애 시 다음이 모두 동시에 실패한다:
- 모든 인증 토큰 검증 불가 (블랙리스트 조회 실패)
- Celery 태스크 큐잉 중단 (모니터링, 비용 수집 전면 중단)
- WebSocket 실시간 이벤트 전달 불가
- Rate Limit 미적용으로 OCI API 할당량 과소비 위험

OCI Cache(Redis)의 SLA와 장애 시 각 기능별 Graceful Degradation 전략이 문서에 없다.

**[High] 멀티 리전 캐시 무효화 전략 부재**

`tenants.oci_regions` JSONB 필드로 복수 리전을 지원하지만, `"oci:compute:{tenant}:{comp}"` 형태의 캐시 키가 리전 정보를 포함하지 않는다. 고객사가 ap-seoul-1과 us-ashburn-1 두 리전의 Compute 인스턴스를 조회할 때 캐시 키 설계가 불완전하다.

**[High] OCIClientFactory 싱글톤 메모리 누수 가능성**

`OCIClientFactory`가 테넌트별 OCI 클라이언트를 싱글톤으로 관리한다고 명시했으나, 테넌트 수가 증가하거나 Credential 교체 시 기존 클라이언트 제거 전략이 불명확하다. 100개 이상의 테넌트를 관리하는 MSP 환경에서 OKE Pod의 메모리 제한(2Gi)과 충돌할 수 있다.

**[Medium] Celery Beat 단일 인스턴스 운영 위험**

`msp-beat: replicas: 1`로 설정되어 있다. OKE Node 장애나 Pod 재시작 시 30초~수 분간 모니터링 폴링이 중단될 수 있다. RedBeat 스케줄러를 사용한다고 명시되어 있으나 이중화 방안이 없다.

**[Medium] WebSocket Sticky Session과 HPA 충돌**

WebSocket 연결은 OCI LB의 Sticky Session으로 유지하고 있는데, `msp-api-hpa`가 최대 10개 Pod까지 스케일 아웃되면 기존 WebSocket 연결이 끊기는 상황이 발생한다. Kubernetes에서 WebSocket을 처리하는 별도 WS Gateway Pod(Port 8001)가 있지만 해당 Pod의 HPA 설정이 명시되지 않았다.

#### 구체적 수정 권고

1. Redis 역할을 최소 2개 인스턴스로 분리 권고: (A) JWT 블랙리스트 + Rate Limit 전용 (소용량, 고내구성), (B) 캐시 + Pub/Sub 전용. 또는 Redis Sentinel/Cluster 구성 필수.
2. 캐시 키 설계에 리전 정보 포함: `"oci:compute:{tenant_id}:{region}:{compartment_id}"`.
3. OCIClientFactory에 TTL 기반 클라이언트 만료 및 LRU 제거 로직 추가.
4. Celery Beat HA 방안 명시: RedBeat의 분산 락 메커니즘 또는 별도 K8s CronJob 대안 검토.

---

### 2. 데이터베이스 설계 리뷰 (점수: 8.8 / 10)

#### 긍정 평가

- **SQLAlchemy 모델과 DDL 병기**: 구현 가능한 수준의 코드와 DDL이 함께 제공되어 개발팀의 이해도와 생산성을 높인다.
- **RLS 설계 원칙**: 모든 테이블에 `tenant_id`를 명시적으로 포함하는 원칙이 일관적으로 적용되어 있다.
- **인덱스 전략의 충실함**: GIN 인덱스(tags, resource_data), 부분 인덱스(sync_status='stale'), 복합 인덱스를 적절히 활용했다.
- **파티셔닝 적용**: `cost_records`와 `audit_logs`에 월별 파티셔닝을 적용하여 대용량 데이터 관리에 대비했다.
- **Credential 보안 원칙 명시**: `tenant_credentials` 테이블 상단에 "실제 OCI API Key는 절대 DB에 저장하지 않습니다"라는 원칙이 명확하게 명시되어 있다.
- **임시 권한 만료**: `user_tenant_roles.expires_at`로 시간 제한 권한 부여 패턴을 지원한다.

#### 개선 필요 사항

**[Critical] PostgreSQL RLS 정책 구현 불완전**

문서 목차에 "7. 멀티 테넌트 RLS 정책"이 있지만 실제 RLS 구현 코드(`ALTER TABLE ... ENABLE ROW LEVEL SECURITY`, `CREATE POLICY`)가 DB 설계서 어디에도 나타나지 않는다. CLAUDE.md에서 "PostgreSQL RLS"를 핵심 보안 원칙으로 명시했으나, RLS가 실제 PostgreSQL 레벨에서 활성화되어 있지 않으면 애플리케이션 레벨 필터링에만 의존하게 되어 SQL Injection 또는 ORM 우회 공격에 취약해진다.

**[High] oci_resources.resource_data JSONB 컬럼의 크기 제한 없음**

OCI SDK 응답 원본을 JSONB로 저장하는데, OCI 리소스에 따라 응답 크기가 수십 KB에 달할 수 있다. 고객사에 1,000개 이상의 리소스가 있을 경우 테이블 크기가 기하급수적으로 증가한다. GIN 인덱스(`resource_data`)도 이 문제를 악화시킨다. 리소스 상세 데이터를 별도 테이블로 분리하거나, 핵심 필드만 정형 컬럼으로 추출하고 나머지를 선택적으로 저장하는 전략이 필요하다.

**[High] alert_rules.condition_operator 검증 부재**

`condition_operator` 컬럼이 `VARCHAR(20) NOT NULL DEFAULT 'GT'`로 정의되어 있지만, CHECK 제약이나 PostgreSQL Enum 타입으로 유효한 값(GT/LT/GTE/LTE/EQ)을 강제하지 않는다. SQLAlchemy 모델에도 Enum 타입이 적용되지 않았다.

**[High] tenant_sla와 SLA 실제 측정값 분리 부재**

`tenant_sla` 테이블은 SLA 목표값(target)을 저장하지만, 실제 측정된 가용성(actual availability %)을 기록하는 별도 테이블이 없다. SLA 위반 감지를 위해서는 실측 데이터와 목표값의 비교가 필요하며, 이를 위한 `sla_measurements` 테이블이 필요하다.

**[Medium] jobs 테이블 스키마 미제공**

ERD 개요와 도메인 설명에 `jobs` 테이블이 언급되어 있지만, 해당 테이블의 DDL과 SQLAlchemy 모델이 문서에 없다. API 설계서에서 `JobResponse`와 `JobStatus` 스키마가 참조되므로 이 테이블은 핵심이다.

**[Medium] audit_logs 파티션 테이블 DDL 미제공**

`audit_logs`의 월별 파티셔닝이 언급되지만, 파티션 테이블 생성 DDL과 자동 파티션 생성(pg_partman 사용 여부 등)이 명시되지 않았다.

**[Medium] users 테이블의 TOTP secret 저장 위치 불명확**

MFA 설계서에서 TOTP secret을 "DB 암호화 저장"이라고 명시했으나, `users` 테이블에 `mfa_secret` 컬럼이 없다. 별도 테이블인지, `users` 테이블 확장인지 명시가 필요하다.

#### 구체적 수정 권고

1. 누락된 PostgreSQL RLS 정책 DDL 추가 필수. 최소 `tenants`, `oci_resources`, `alerts`, `incidents`, `cost_records`, `audit_logs` 테이블에 적용.
2. `oci_resources.resource_data`는 핵심 필드만 JSONB에 저장하고, 리소스 유형별 상세 스펙은 별도 파티션 테이블로 분리.
3. `alert_rules.condition_operator`에 `CHECK (condition_operator IN ('GT', 'LT', 'GTE', 'LTE', 'EQ'))` 제약 추가.
4. `jobs` 테이블 DDL과 `sla_measurements` 테이블 신규 설계 필요.
5. `users` 테이블에 `mfa_secret_encrypted`, `mfa_recovery_codes_hashed`, `mfa_verified_at` 컬럼 명시.

---

### 3. API 설계 리뷰 (점수: 8.0 / 10)

#### 긍정 평가

- **RESTful 네이밍 원칙의 명확한 정의**: 케밥케이스, 복수 명사, 동사 금지, 3단계 계층 제한 등의 원칙이 구체적인 예시와 함께 제시되어 있다.
- **이중 페이지네이션 전략**: Cursor-based(실시간/대용량)와 Offset-based(관리 목록) 구분이 사용 케이스에 맞게 설계되어 있다.
- **에러 코드 체계**: `AUTH_001` ~ `VALID_003`까지의 도메인별 에러 코드가 체계적이다.
- **비동기 작업 패턴**: POST → 202 + job_id → GET /jobs/{id} 폴링 → WebSocket 완료 알림의 패턴이 명확하다.
- **MFA 흐름 설계**: 로그인 → MFA 미설정 분기 → MFA 코드 검증 → 최종 토큰 발급의 흐름이 적절하다.
- **Pydantic 스키마 Generic 활용**: `PaginatedResponse[T]`처럼 제네릭 타입을 활용한 공통 응답 스키마가 잘 설계되어 있다.

#### 개선 필요 사항

**[Critical] MVP vs Phase 2 구분 혼재**

온보딩 Step 2에서 `OnboardStep2.private_key_pem`을 직접 요청 바디로 받는다. 이는 Private Key PEM이 HTTPS를 통해 전송된다는 의미인데, TLS 가로채기 또는 로그 노출 위험이 있다. Cross-Tenancy Resource Principal 방식이 "권장"이라고 명시했으나, MVP에서 두 방식 모두 지원하는 것인지 명확하지 않다. Private Key를 API 요청 바디로 직접 받는 방식은 보안 설계 원칙과 상충된다.

**[High] X-Tenant-ID 헤더와 JWT 클레임 테넌트 ID 이중성**

JWT 클레임에 `tenant_id`가 포함되어 있고, 일반 사용자는 `X-Tenant-ID` 헤더를 추가로 전송한다. 두 값이 다를 경우의 처리 방침이 명시되지 않았다. Super Admin이 다른 테넌트의 리소스를 조회할 때 `tenant_id` 클레임을 무시하고 헤더를 우선하는 로직이 보안 취약점이 될 수 있다.

**[High] API 버전 관리 전략 부재**

현재 `/api/v1/` 프리픽스만 있을 뿐, v1 → v2 마이그레이션 전략, Deprecation 정책, 하위 호환성 유지 기간 등이 명시되지 않았다. MSP 플랫폼 특성상 고객사별 클라이언트 통합이 있을 수 있어 버전 관리가 중요하다.

**[High] 비동기 작업 취소(Cancel) API 부재**

POST /actions로 인스턴스 시작/중지를 요청하고 job_id를 받지만, 진행 중인 작업을 취소하는 `DELETE /jobs/{job_id}` 또는 `POST /jobs/{job_id}/cancel` API가 없다. 긴 작업(예: 대량 스냅샷 생성)이 잘못 트리거된 경우 대응 방법이 없다.

**[Medium] TenantStatus Enum 불일치**

DB 설계서의 `TenantStatus`는 `(active, suspended, offboarding, terminated)` 4가지인데, API 설계서의 `TenantStatus` Enum은 `(onboarding, active, suspended, offboarding)` 4가지로 값이 다르다. `terminated`가 API 스키마에 없고, `onboarding`이 DB에 없는 등 불일치가 있다.

**[Medium] Rate Limit 세부 설정 미명시**

API 보안 섹션에 Rate Limit이 언급되어 있지만, 엔드포인트별 Rate Limit 정책(예: /auth/login은 분당 10회, /compute/instances는 분당 100회)이 명시되지 않았다. OCI API Gateway 설정과의 연계 방식도 불명확하다.

**[Medium] Webhook 아웃바운드 API 부재**

고객사가 MSP 플랫폼의 알람/인시던트 이벤트를 자체 ITSM(예: PagerDuty, Jira)과 연동할 수 있는 Webhook 설정 API가 없다. MSP 플랫폼에서 이는 핵심 요구사항이 될 가능성이 높다.

#### 구체적 수정 권고

1. `OnboardStep2`에서 Private Key PEM을 직접 받는 대신, 서명된 업로드 URL(Pre-signed URL)을 통해 전송하거나 Cross-Tenancy 방식을 MVP 기본으로 강제.
2. `X-Tenant-ID` 헤더와 JWT `tenant_id` 클레임의 우선순위 규칙을 API 설계 원칙에 명시.
3. DB 스키마와 API 스키마의 `TenantStatus` Enum 값 통일.
4. `POST /jobs/{job_id}/cancel` 엔드포인트 추가.
5. 엔드포인트별 Rate Limit 정책 표 추가.

---

### 4. 보안 설계 리뷰 (점수: 9.0 / 10)

#### 긍정 평가

- **STRIDE 위협 모델 적용**: MSP 플랫폼 특유의 위협(크로스 테넌트 데이터 누출, OCI API Key 탈취, JWT 위조)이 구체적으로 분석되어 있다.
- **JWT RS256 + Token Family Rotation**: Refresh Token 탈취 시 동일 패밀리 전체 무효화 로직이 코드 수준으로 구현되어 있다. `alg: none` 공격 방지를 위한 알고리즘 명시적 고정도 올바르다.
- **Fernet 이중 암호화**: OCI Vault에 Fernet 암호화된 값을 저장하는 이중 보안 구조는 적절하다.
- **90일 Key Rotation 자동화**: Celery Beat 기반 자동 회전과 14일 전 경고 알림이 구현 수준으로 제시되어 있다.
- **RBAC 권한 매트릭스**: 역할별 기능 권한이 세분화되어 있고, FastAPI Dependency 패턴으로 강제 적용하는 방법이 명시되어 있다.
- **감사 로그의 불변성 원칙**: 모든 Credential 접근 시 감사 로그를 기록하는 패턴이 코드에 반영되어 있다.

#### 개선 필요 사항

**[Critical] MFA 복구 코드 해시 알고리즘 불일치**

`MFAManager._generate_recovery_codes()`에서 SHA-256으로 복구 코드를 해시하면서 주석에 "Argon2 권장"이라고 적혀 있다. SHA-256은 단순 해시 함수로 GPU 공격에 취약하며, 비밀번호/복구코드 해시에는 Argon2, bcrypt, scrypt 등의 Key Derivation Function(KDF)을 사용해야 한다. 설계 문서와 구현 코드 간의 불일치는 미래 개발자가 이 문제를 인식하지 못하고 그대로 배포할 위험이 있다.

**[High] Cross-Tenancy Resource Principal 구성의 고객사 의존성 미처리**

Cross-Tenancy 방식은 고객사 OCI 테넌시에서 MSP Dynamic Group을 신뢰하는 IAM Policy를 직접 추가해야 한다. 고객사가 이 설정을 거부하거나 정책을 임의로 변경/삭제할 경우의 감지 및 알림 메커니즘이 없다. `last_verified_at` 컬럼이 있으나, 정기적인 Credential 상태 검증 스케줄이 API Key 방식에만 집중되어 있고 Resource Principal 방식의 건강성 확인이 누락되어 있다.

**[High] JWT 클레임에 permissions 목록 포함에 따른 토큰 비대화**

`create_access_token()`에서 `roles`와 `permissions` 목록을 모두 JWT 클레임에 포함한다. 역할별 권한 매핑이 서버 메모리(ROLE_PERMISSIONS dict)에도 있고 JWT에도 있어 이중 관리가 된다. 권한이 많을수록 토큰 크기가 증가하며, 권한 변경 시 기존 Access Token(15분 유효)에는 반영되지 않는 일관성 문제가 발생한다.

**[Medium] Super Admin의 크로스 테넌트 접근 감사 강화 필요**

Super Admin은 모든 테넌트 데이터에 접근 가능하다. 감사 로그가 존재하지만, Super Admin이 특정 테넌트의 Credential에 접근할 때 해당 테넌트 관리자에게 알림을 보내는 메커니즘이 없다. 법적/계약적 요구사항이 될 수 있다.

**[Medium] CORS 정책 구체성 부재**

`CORS_ORIGINS=["http://localhost:3000"]`이 환경 변수 예시로만 제시되어 있고, 프로덕션 CORS 정책(허용 출처, 허용 메서드, 허용 헤더, Preflight 캐시 시간)이 보안 설계서에 명시되지 않았다.

**[Low] TOTP 허용 오차 보안 고려**

`valid_window=1` 설정은 ±30초 오차를 허용한다. 이는 표준적이지만, 고보안 환경에서는 NTP 동기화와 함께 `valid_window=0`을 사용하거나 시간 동기화 요구사항을 명시할 필요가 있다.

#### 구체적 수정 권고

1. `_generate_recovery_codes()`의 해시를 즉시 `argon2-cffi`로 교체하거나, 설계 결정을 SHA-256으로 확정하고 그 이유를 문서화.
2. Resource Principal 방식의 정기 Credential 검증 태스크(예: 매 6시간) Celery Beat 스케줄에 추가.
3. JWT 클레임에서 `permissions` 목록을 제거하고 서버 사이드 권한 검사만 사용하여 토큰 크기 최소화.
4. Super Admin의 크로스 테넌트 Credential 접근 시 해당 테넌트 관리자 알림 정책 추가.

---

### 5. 인프라/DevOps 리뷰 (점수: 8.3 / 10)

#### 긍정 평가

- **Terraform 모듈 구조**: `network`, `oke`, `database`, `vault`, `monitoring` 모듈 분리가 관심사별로 적절하다.
- **멀티스테이지 Dockerfile**: development/production 타겟 분리, non-root 사용자, distroless 지향 설계가 보안 모범 사례를 따른다.
- **GitHub Actions 3단계 파이프라인**: CI(PR) → Deploy Staging(dev 브랜치) → Deploy Production(main, 수동 승인)의 구조가 명확하다.
- **OpenTelemetry 계측**: FastAPI, SQLAlchemy, Redis 자동 계측이 적용되어 있어 분산 트레이싱이 가능하다.
- **DR 설계**: ap-chuncheon-1 Warm Standby와 DNS Failover(TTL=30초)를 통한 RTO < 30분 목표가 명시되어 있다.
- **PodDisruptionBudget**: `minAvailable: 1` 설정으로 롤링 업데이트 중 최소 가용성을 보장한다.
- **External Secrets Operator**: OCI Vault → K8s Secret 자동 동기화가 설계되어 있어 비밀 관리가 체계적이다.

#### 개선 필요 사항

**[High] Celery Beat HA(고가용성) 전략 없음**

인프라 설계서에 `msp-beat: replicas: 1`로 명시되어 있고, 복수 Beat 인스턴스를 방지하는 이유(중복 태스크 실행 방지)는 이해하지만, Pod 재시작 시 약 30초~수 분간 모니터링 폴링이 중단된다. RedBeat Scheduler를 사용하면 Redis 기반 분산 락으로 다중 Beat 인스턴스 운영이 가능한데, 이 옵션이 검토되지 않았다.

**[High] 프로덕션 배포에서 latest 태그 사용 금지 필요**

K8s 매니페스트에 `image: ap-seoul-1.ocir.io/<namespace>/msp-api:latest`가 사용되어 있다. 프로덕션 환경에서 `latest` 태그는 재현 불가능한 배포를 만들고 롤백을 어렵게 한다. CI/CD 파이프라인에서는 SHA 기반 태그를 사용하지만 K8s 매니페스트 기본값이 `latest`로 되어 있어 혼란을 줄 수 있다.

**[High] DB 마이그레이션 전략 부재**

Alembic 마이그레이션이 CLAUDE.md에 언급되어 있지만, 인프라 설계서에 배포 파이프라인과 Alembic 마이그레이션의 실행 시점이 명시되어 있지 않다. Kubernetes 환경에서 DB 마이그레이션은 일반적으로 Init Container 또는 K8s Job으로 처리하는데, 이 패턴이 없다.

**[High] OCI Budget $3,000 하드코딩**

`oci_budget_budget.main.amount = 3000`이 하드코딩되어 있다. MSP 플랫폼의 규모가 커질수록 인프라 비용도 증가하므로, 이는 변수로 관리되어야 하며 환경별(dev/staging/prod)로 다른 값이 적용되어야 한다.

**[Medium] Staging 환경의 Smoke Test 취약성**

`curl -sf "http://${LB_IP}:8000/health" | jq '.status' | grep -q "ok"`가 Smoke Test의 전부다. /health 엔드포인트가 성공하더라도 DB 연결, Redis 연결, OCI SDK 인증이 정상인지 확인하지 않는다. `HealthResponse.components`에 postgresql, redis, oci_api 상태가 포함되어 있으므로 이를 검증하는 Smoke Test가 필요하다.

**[Medium] E2E 테스트 파이프라인 누락**

프론트엔드 CLAUDE.md에서 Playwright E2E 테스트가 언급되어 있지만 CI/CD 파이프라인에 E2E 테스트 단계가 없다. Staging 배포 후 E2E 테스트를 실행하는 단계가 추가되어야 한다.

**[Medium] 비용 최적화 섹션 내용 부재**

목차에 "10. 비용 최적화"가 있지만 실제 내용이 OCI Budget 설정 외에 제공되지 않았다. OKE Node Pool 스팟 인스턴스 사용 가능성, 개발 환경 야간/주말 자동 스케일다운, 불필요한 스냅샷 정리 정책 등의 내용이 필요하다.

#### 구체적 수정 권고

1. K8s 매니페스트에서 `latest` 태그를 `${IMAGE_TAG:-latest}`로 변경하고, CI/CD 파이프라인에서 항상 SHA 태그로 오버라이드.
2. DB 마이그레이션용 K8s Job 또는 Init Container 패턴 추가.
3. RedBeat 기반 Celery Beat 다중 인스턴스 운영 가이드 추가.
4. Staging Smoke Test에 DB/Redis/OCI 연결 상태 검증 포함.
5. `oci_budget_budget.amount`를 `var.monthly_budget_usd`로 변수화.

---

### 6. UI/UX 설계 리뷰 (점수: 7.8 / 10)

*검토 대상: 00_index.md, 03_screen_designs.md, 04_components.md*

#### 긍정 평가

- **컴포넌트 의존성 맵**: shadcn/ui → 공통 컴포넌트 → 기능 컴포넌트의 레이어가 명확히 정의되어 있다.
- **위험도별 UX 패턴**: LOW/MED/HIGH/CRITICAL 4단계 구분이 실제 MSP 운영 상황에 맞는 접근이다.
- **ResourceTable의 완성도**: TanStack Table + Virtual 조합의 구현이 실제 운영 가능한 수준으로 작성되어 있다. ARIA 속성, 밀도 설정, 열 가시성 토글 등의 접근성 고려도 돋보인다.
- **3클릭 이내 주요 작업 원칙**: 핵심 운영 작업의 최소 클릭 경로가 명시되어 있어 UX 목표가 구체적이다.
- **주간 개발 순서**: Week 3~12의 개발 우선순위가 백엔드 API 완성 순서와 연계되어 있다.
- **TanStack Query 캐시 정책**: realtime/medium/slow/static 4단계 구분이 데이터 성격에 맞게 설계되어 있다.

#### 개선 필요 사항

**[High] 온보딩 위저드 중간 저장 전략 미완성**

와이어프레임에 "[저장하고 나중에 계속]" 버튼이 있지만, 중간 저장된 온보딩 데이터(특히 Step 2의 API Key PEM)의 보안 처리 방식이 불명확하다. 브라우저 세션에 임시 저장하는지, 서버 DB에 저장하는지, 저장 시 암호화 방식이 무엇인지 명시되어야 한다.

**[High] 멀티 테넌시 전환 시 캐시 초기화 전략 부재**

사이드바 테넌트 스위처로 테넌트를 전환할 때 TanStack Query 캐시와 Zustand 상태를 어떻게 초기화하는지 명시되지 않았다. 이전 테넌트의 캐시된 데이터가 새 테넌트 컨텍스트에 잠시 표시될 수 있는 UX 버그가 발생할 수 있다.

**[Medium] ResourceTable의 서버 사이드 필터링 미지원**

`ResourceTableProps`에 서버 사이드 페이지네이션(`pageCount`, `pageIndex`, `onPageChange`)은 있지만 서버 사이드 필터링 props가 없다. 대규모 MSP 환경(고객사 1개에 수천 개 인스턴스)에서 클라이언트 사이드 정렬/필터링은 실용적이지 않다. `onFilterChange` 콜백 Props 추가가 필요하다.

**[Medium] KPICard의 delta 부호 처리 불완전**

`delta.positive ?? delta.value > 0` 로직에서 비용 KPI 카드는 증가(+)가 부정적인 의미이지만, 기본적으로 `positive`로 처리된다. 비용 지표와 가용성 지표의 긍정/부정 방향이 다른데, `positive?: boolean` 옵션이 있지만 기본값이 항상 `delta.value > 0`이므로 비용 증가가 녹색으로 표시될 수 있다.

**[Medium] 대시보드 위젯 레이아웃 서버 저장 구현 누락**

`handleLayoutChange`에서 `saveLayoutToServer(allLayouts)` 함수를 호출하지만, 해당 API 엔드포인트가 API 설계서에 없다. `PATCH /api/v1/users/me/dashboard-layout` 같은 엔드포인트가 필요하다.

**[Low] 다크 모드 전용 설계의 접근성 리스크**

기본 테마를 다크 모드 전용으로 설계했으나, 일부 사용자(시각 장애, 특정 모니터 환경)에게는 라이트 모드가 필요할 수 있다. `next-themes`가 의존성 목록에 있으나 "다크 모드" 기본값이 강하게 명시되어 있어 라이트 모드 지원 수준이 불명확하다.

#### 구체적 수정 권고

1. 온보딩 중간 저장 데이터의 보안 처리 방식을 명시 (브라우저 저장 금지, 서버 임시 저장 + TTL).
2. 테넌트 전환 시 `queryClient.clear()` 또는 `queryClient.resetQueries()` 호출 패턴을 상태 관리 설계에 명시.
3. `ResourceTableProps`에 `onFilterChange`, `filters` Props 추가.
4. `KPICard`의 `delta.positive` 기본값을 컨텍스트 의존적으로 처리하는 방안 명시.
5. 대시보드 레이아웃 저장 API 엔드포인트 추가.

---

## 문서 간 일관성 검토

### 충돌하거나 불일치하는 부분

| 번호 | 위치 | 불일치 내용 |
|------|------|-------------|
| 1 | DB 설계서 vs API 설계서 | `TenantStatus` Enum: DB에는 `(active, suspended, offboarding, terminated)`, API 스키마에는 `(onboarding, active, suspended, offboarding)`. `terminated`와 `onboarding` 값이 서로에게 없음 |
| 2 | DB 설계서 vs API 설계서 | `sla_tier` 값: DB에는 `(standard, premium, enterprise)`, API `OnboardStep4`에서 언급 없고 `TenantCreate.sla_tier`는 `(basic, standard, premium)`. `enterprise`와 `basic`이 서로에게 없음 |
| 3 | 보안 설계서 | MFA 복구 코드 주석("Argon2 권장")과 실제 구현(SHA-256) 불일치 |
| 4 | 시스템 아키텍처 vs 인프라 설계서 | 아키텍처 다이어그램에서 `WebSocket Gateway`를 별도 Pod(Port 8001)로 표시했으나, K8s 매니페스트에 WS Gateway 전용 Deployment가 없음 |
| 5 | CLAUDE.md vs API 설계서 | CLAUDE.md의 모듈 구조에 `app/api/v1/`가 있고 API 설계서에 `app/routers/auth.py` 경로가 혼재. 실제 파일 경로 일관성 필요 |
| 6 | DB 설계서 vs 보안 설계서 | `users` 테이블에 TOTP secret 저장 컬럼이 없으나, 보안 설계서에서 "DB 암호화 저장"을 명시 |
| 7 | CLAUDE.md vs DB 설계서 | CLAUDE.md의 모델 목록에 `oci_resource`(단수)가 있으나, DB 설계서에는 `oci_resources`(복수) 테이블로 명시 |

### 누락된 연결고리

1. **API 설계서 → DB 설계서**: `jobs` 테이블이 API 설계서에서 참조되지만 DB 설계서에 상세 스키마 없음
2. **보안 설계서 → DB 설계서**: RLS 정책 DDL이 보안 설계서에도, DB 설계서에도 없음 (목차에는 존재)
3. **UI/UX → API 설계서**: 대시보드 위젯 레이아웃 저장, Command Palette 검색 API 엔드포인트 미정의
4. **인프라 설계서 → DB 설계서**: Alembic 마이그레이션 실행 파이프라인 연계 미명시
5. **시스템 아키텍처 → 보안 설계서**: OCI API Gateway JWT 검증과 FastAPI 내부 JWT 검증의 중복 여부 및 처리 순서 미명시
6. **DB 설계서 → 인프라 설계서**: PostgreSQL Streaming Replication 설정 상세(wal_level, max_wal_senders 등) 누락

---

## 최우선 수정 사항 (Top 10 Action Items)

| 순위 | 항목 | 해당 문서 | 심각도 | 예상 작업량 |
|------|------|-----------|--------|-------------|
| 1 | PostgreSQL RLS 정책 DDL 추가 (모든 다중 테넌트 테이블) | database-design.md | Critical | 3일 |
| 2 | MFA 복구 코드 해시를 Argon2로 교체하거나 설계 결정 명확화 | security-design.md | Critical | 1일 |
| 3 | TenantStatus Enum 값을 DB 설계서와 API 설계서 간에 통일 | database-design.md, api-design.md | Critical | 0.5일 |
| 4 | `jobs` 테이블 DDL과 SQLAlchemy 모델 추가 | database-design.md | High | 1일 |
| 5 | Redis 단일 장애점 대응: 역할 분리 또는 Redis Sentinel 설정 추가 | system-architecture.md, infrastructure-devops.md | High | 2일 |
| 6 | WebSocket Gateway K8s Deployment 매니페스트 추가 | infrastructure-devops.md | High | 1일 |
| 7 | DB 마이그레이션 K8s Init Container / Job 패턴 추가 | infrastructure-devops.md | High | 1일 |
| 8 | 캐시 키에 리전 정보 포함 방안 명시 | system-architecture.md | High | 0.5일 |
| 9 | OnboardStep2의 Private Key PEM 직접 전송 방식 재검토 | api-design.md, security-design.md | High | 2일 |
| 10 | SLA 실측값 저장 테이블(`sla_measurements`) 설계 추가 | database-design.md | Medium | 1일 |

---

## MVP 범위 최종 검증

> "조회는 MVP, 변경은 Phase 2" 원칙 적용 현황

### 원칙이 잘 반영된 부분

- OCI 리소스 목록 조회(GET)가 MVP 핵심으로 명확히 포지셔닝됨
- Phase 2 전환 목록(OCI ATP, OCI Streaming, 마이크로서비스 분리)이 명확히 구분됨
- DB 설계에 `sync_status`, `last_synced_at`를 두어 읽기 전용 캐시 구조를 기반으로 설계됨

### 원칙이 불명확한 부분

| 항목 | 현황 | 권고 |
|------|------|------|
| 인스턴스 시작/중지 | API 설계서에 `POST /actions` MVP 포함으로 보임 | MVP 포함 근거 명시 필요. 변경 작업이 MVP에 포함된다면 "조회는 MVP" 원칙 예외 케이스 명시 |
| 테넌트 PATCH API | `PATCH /tenants/{id}` MVP 포함으로 보임 | 테넌트 관리 변경은 MSP 운영에 필수이므로 MVP 포함이 타당하나 원칙과의 관계 설명 필요 |
| 알람 규칙 생성/수정 | MVP인지 Phase 2인지 불명확 | 기본 알람 규칙은 온보딩 시 자동 생성하고 수동 편집은 Phase 2로 명시 권고 |
| Incident 수동 생성 | MVP인지 Phase 2인지 불명확 | Alert 자동 생성만 MVP, 수동 Incident 생성은 Phase 2로 명시 권고 |
| 월간 비용 리포트 PDF | API 설계서에 언급됨 | PDF 리포트 생성은 Phase 2로 연기하고 MVP는 화면 내 조회로 제한 권고 |

### 권고 사항

"조회는 MVP" 원칙을 다음과 같이 구체화할 것을 권고한다:

- **MVP 포함 변경 작업**: 테넌트 온보딩/설정, 인스턴스 시작/중지/재시작 (MSP 핵심 운영 기능)
- **Phase 2로 이연할 변경 작업**: 인스턴스 삭제, 스케일링 변경, 알람 규칙 수동 편집, 비용 리포트 PDF 생성, On-call 스케줄 관리

---

## 기술 부채 위험 평가

### 위험도 High - 조기 해결 권고

**[TD-1] JSONB 과용에 따른 스키마 표류(Schema Drift)**

`oci_resources.resource_data`, `tenants.settings`, `tenants.oci_regions`, `alert_rules.notification_channels`, `alert_rules.maintenance_windows`, `tenant_sla.violation_notify_channels` 등 다수의 JSONB 컬럼이 사용된다. JSONB는 유연하지만, 스키마가 암묵적으로 변화하고 타입 검증이 애플리케이션 레벨에서만 이루어진다. OCI SDK 응답 형식이 변경될 때 하위 호환성 유지가 어려워지고, 필드 조회 쿼리의 성능 예측이 어렵다.

**권고**: 자주 접근하는 필드는 정형 컬럼으로 추출하고, JSONB는 진정으로 구조가 불확실한 메타데이터에만 사용.

**[TD-2] Celery + Redis 결합도에 따른 이식성 문제**

Celery 브로커로 Redis만 설계되어 있다. Phase 2에서 OCI Streaming(Kafka 호환)으로 전환을 언급했으나, Celery는 Kafka 브로커를 네이티브로 지원하지 않는다. Celery에서 confluent-kafka로의 마이그레이션은 모든 태스크 코드를 재작성해야 하는 대규모 리팩토링이 된다.

**권고**: Phase 2 전환 시 Celery 태스크를 순수 함수로 유지하고, 브로커 의존성을 추상화 레이어로 감싸는 패턴 도입.

**[TD-3] OCIClientFactory 싱글톤 패턴의 테스트 어려움**

싱글톤 팩토리는 테스트 격리를 어렵게 만든다. `patch("oci.core.ComputeClient")`로 목킹한다고 명시했으나, 팩토리 레벨의 목킹은 테스트 환경에서 복잡성을 증가시킨다.

**권고**: OCIClientFactory를 프로토콜(Protocol) 기반 인터페이스로 추상화하여 테스트에서 FakeOCIClientFactory를 주입 가능하도록 설계.

### 위험도 Medium - Phase 2 이전에 해결 권고

**[TD-4] 단일 PostgreSQL 인스턴스의 Streaming Replication 지연**

DR 리전(ap-chuncheon-1)의 Standby가 Streaming Replication으로 유지된다. MSP 특성상 고객사 수가 늘어나면 쓰기 부하가 증가하고, Replication Lag가 RTO에 영향을 미친다. 현재 Lag 모니터링이나 허용 한계치 정의가 없다.

**[TD-5] 감사 로그의 검색 성능**

`audit_logs`는 월별 파티션으로 관리되지만, 파티션 수가 늘어날수록 전체 기간 조회의 성능이 저하된다. 감사 로그는 장기 보존과 빠른 검색이 동시에 요구되므로, 초기부터 OCI Logging Analytics로 스트리밍하고 DB는 최근 3개월만 유지하는 Two-Tier 전략이 필요하다.

**[TD-6] 프론트엔드 라이브러리 중복 (ECharts + Recharts)**

ECharts(모니터링 시계열)와 Recharts(스파크라인)를 동시 사용한다. 두 라이브러리 합산 번들 크기가 약 400KB 이상이 될 수 있다. 초기 로딩 성능에 영향을 줄 수 있으며, 한 라이브러리로 통일하거나 Code Splitting을 통한 지연 로딩 전략이 필요하다.

**[TD-7] 멀티 테넌트 환경에서의 OCI Rate Limit 공유 위험**

모든 테넌트의 OCI API 호출이 MSP 플랫폼의 단일 OCI 계정(Resource Principal)을 통해 이루어질 경우, 특정 테넌트의 대량 요청이 다른 테넌트의 OCI API 할당량을 고갈시킬 수 있다. Redis 토큰 버킷이 설계되어 있으나 테넌트별 OCI API 할당량 배분 정책이 명시되지 않았다.

---

*리뷰 작성 완료: 2026-03-21 | 검토된 설계 문서 총 8개*
*다음 리뷰 권고 시점: 각 Critical/High 항목 수정 완료 후*
