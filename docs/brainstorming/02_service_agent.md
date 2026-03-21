# 서비스 에이전트 - 브레인스토밍 결과

## 1. 기술 스택 추천

### 최종 추천 스택

| 레이어 | 기술 | 선택 이유 |
|--------|------|---------|
| 백엔드 | **FastAPI + Python 3.12** | OCI 공식 SDK 완전 지원, asyncio 비동기 |
| 프론트엔드 | **Next.js 15 (App Router)** | SSR 성능, 풍부한 생태계 |
| Primary DB | **OCI ATP (PostgreSQL mode)** | OCI 네이티브, 자동 스케일링, 자동 백업 |
| 캐싱/세션 | **OCI Cache (Redis 호환)** | API 캐싱, Rate Limit 버퍼 |
| 메시징 | **OCI Streaming (Kafka 호환)** | 모니터링 이벤트, 실시간 알림 |
| 비동기 작업 | **OCI Queue (SQS 호환) + Celery** | 프로비저닝, 리포트 생성 |

### 백엔드 비교
| 항목 | Python FastAPI | Node.js NestJS | Go |
|------|--------------|----------------|-----|
| OCI SDK | **공식 완전 지원** | 비공식 | 비공식 |
| 개발 생산성 | **높음** | 높음 | 중간 |
| ML/데이터 생태계 | **최고** | 제한적 | 제한적 |
| **결정** | **✅ 선택** | | |

---

## 2. OCI SDK/API 통합 전략

### 인증 방식
```
MSP 플랫폼 자체: Instance Principal (OCI Compute 배포 시)

고객 테넌시 접근:
Option 1: API Key (Cross-tenancy) - 하위 호환
Option 2: Cross-Tenancy Resource Principal - 권장 (Key 관리 불필요)
```

### Credential 안전한 저장
```
OCI Vault (HSM 기반 암호화) → 고객 API Key 저장
OCI ATP (TDE) → Credential 메타데이터 (참조 ID만)

절대 금지:
❌ Private Key 원문 DB 직접 저장
❌ 환경변수로 Credential 주입
❌ 코드 하드코딩
```

### Rate Limiting 대응
- Redis 기반 토큰 버킷 알고리즘
- 지수 백오프 + 지터 (OCI 429 오류 시)
- 서비스별 한도: Compute 100 req/min, Identity 60 req/min

---

## 3. 서비스 아키텍처

### 아키텍처 결정: 모듈러 모놀리스 → 점진적 마이크로서비스

**초기 단계**: Modular Monolith (빠른 MVP)
**성장 후**: 모니터링 수집기, 비용 분석 엔진, 알림 서비스 분리

### 전체 시스템 구성
```
사용자 → OCI API Gateway (JWT 검증, WAF, Rate Limit)
       → Next.js Frontend
       → FastAPI Backend
         → Tenant Manager Module
         → Resource Manager Module
         → Monitoring Collector Module
       → OCI ATP (Primary DB)
       → OCI Cache (Redis)
       → OCI Streaming (Kafka)
       → 고객 OCI 테넌시 (Multi-Tenant)
```

### 비동기 작업 처리
- Celery + Redis 브로커
- 우선순위 큐 3단계: critical / default / low
- Work Request 폴링 (OCI 장기 작업 추적)
- WebSocket으로 진행 상태 실시간 업데이트

---

## 4. 보안 아키텍처

### JWT 토큰 전략
- Access Token: 15분
- Refresh Token: 7일 (Sliding Window Rotation)
- RS256 알고리즘 (비대칭 키)
- Redis 블랙리스트 (토큰 취소)

### 감사 로그
- HTTP 미들웨어로 모든 쓰기 작업 자동 기록
- 기록 항목: 행위자, IP, 대상 리소스, 결과, 소요시간
- 민감정보 마스킹 후 저장

---

## 5. OCI 인프라 구성 (Production)

### 고가용성
- Region: ap-seoul-1 (Primary) + ap-chuncheon-1 (DR)
- AD 분산 배포 (AD-1, AD-2)
- OKE (Kubernetes) 기반, HPA 자동 스케일링
- OCI Load Balancer (Active-Active)

### RTO/RPO 목표
- RTO: < 30분
- RPO: < 5분

### 백업 전략
- OCI ATP 자동 백업 (60일 보존, PITR 지원)
- Object Storage 수명주기: Standard(30일) → Infrequent(90일) → Archive
- GitOps: Kubernetes 설정 + Terraform → OCI DevOps Git
