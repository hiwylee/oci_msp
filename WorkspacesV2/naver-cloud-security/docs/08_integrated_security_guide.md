# OCI 보안 서비스 지원 범위 및 통합 설정 가이드

## 1. 서비스별 지원 범위 (Support Scope)

---

### 1.1 WAF (Web Application Firewall)

| 구분 | 지원 항목 | 비고 |
|------|----------|------|
| **동작 모드** | Regional WAF (OCI LB 연동), Edge WAF (CDN/글로벌) | 고객 환경은 Regional 권장 |
| **보호 규칙** | OWASP Top 10 (SQLi, XSS, LFI, RFI, RCE 등) | OCI Managed Rule Set 제공 |
| **커스텀 규칙** | IP 허용/차단, 국가(Geo) 차단, URL 패턴, HTTP 헤더 기반 | 최대 100개 규칙 |
| **봇 관리** | 봇 크롤러 탐지, CAPTCHA 챌린지, JS 챌린지 | Edge 모드에서 더 강력 |
| **Rate Limiting** | IP당 요청 수 제한 | DDoS 완화 용도 |
| **연동 대상** | OCI Load Balancer, OCI API Gateway | 직접 VM에는 미연동 |
| **로그** | WAF Access Log, WAF Audit Log → OCI Logging 서비스 연동 | |
| **TLS** | TLS 1.2 / 1.3 지원, 취약 Cipher Suite 차단 가능 | |

**운영 모드**

| 모드 | 동작 |
|------|------|
| `DETECTION` | 탐지만 하고 차단 안 함 (로그 기록) |
| `PREVENTION` | 탐지 즉시 차단 |

> 초기 운영은 반드시 `DETECTION` → 2주 이상 False Positive 검토 → `PREVENTION` 전환

---

### 1.2 DB 접근통제

#### MySQL HeatWave

| 구분 | 지원 항목 | 비고 |
|------|----------|------|
| **네트워크 통제** | NSG / Security List로 포트(3306) 제어 | |
| **암호화 전송** | TLS 1.2 기본 활성화 | 강제(require_secure_transport) 설정 가능 |
| **암호화 저장** | AES-256 기본 활성화 (OCI 관리 키) | CMK(고객 관리 키) 적용 가능 |
| **사용자 권한** | DB/Schema/Table 단위 GRANT | 최소 권한 원칙 적용 |
| **감사 로그** | Audit Log → OCI Logging 연동 | `audit_log_policy` 설정 필요 |
| **백업 암호화** | 자동 백업 AES-256 암호화 | |
| **IAM 인증** | OCI IAM 토큰 기반 DB 인증 (제한적 지원) | |

#### PostgreSQL (OCI Database with PostgreSQL)

| 구분 | 지원 항목 | 비고 |
|------|----------|------|
| **네트워크 통제** | NSG / Security List로 포트(5432) 제어 | |
| **암호화 전송** | SSL/TLS 기본 활성화 | `sslmode=require` 강제 적용 권장 |
| **암호화 저장** | AES-256 (OCI 관리 키), CMK 적용 가능 | |
| **사용자 권한** | Role 기반 접근 제어 (RBAC) | Schema/Table 단위 |
| **감사 로그** | `pgaudit` 확장 모듈 (OCI 관리형에서는 제한적) | OCI Logging 연동 |
| **접속 소스 제한** | pg_hba.conf 상당 → NSG로 대체 통제 | |

#### OpenSearch (OCI OpenSearch Service)

| 구분 | 지원 항목 | 비고 |
|------|----------|------|
| **네트워크 통제** | NSG로 포트(9200/9300) 제어, Private Endpoint 전용 | 공인 IP 노출 불가 (보안 강점) |
| **인증** | HTTP Basic Auth, Fine-Grained Access Control (FGAC) | 내부 사용자 DB 또는 외부 IdP |
| **암호화 전송** | HTTPS(TLS 1.2+) 기본 활성화 | |
| **암호화 저장** | AES-256 기본 활성화 | |
| **접근 제어** | 인덱스/필드/도큐먼트 단위 권한 제어 (FGAC) | 역할(Role) 기반 |
| **감사 로그** | Audit Logging 활성화 가능 | OpenSearch Dashboard에서 설정 |

---

### 1.3 암호화 키 관리 (OCI Vault / KMS)

| 구분 | 지원 항목 | 비고 |
|------|----------|------|
| **Vault 유형** | Default Shared Vault, Virtual Private Vault (전용 HSM) | Virtual = FIPS 140-2 Level 3 |
| **키 알고리즘** | AES (128/192/256-bit), RSA (2048/3072/4096-bit), ECDSA (P-256/P-384/P-521) | |
| **보호 방식** | HSM 보호 (권장), Software 보호 | HSM = 키가 HSM 외부로 나가지 않음 |
| **통합 서비스** | Block Volume, Boot Volume, File Storage, Object Storage, MySQL HeatWave, ExaCS, Streaming, Functions | |
| **시크릿 관리** | DB 비밀번호, API Key, TLS 인증서 저장 및 자동 갱신 | |
| **키 회전** | 수동/자동 회전, 버전별 관리 | 이전 버전으로 복호화 가능 |
| **키 가져오기** | BYOK (Bring Your Own Key) 지원 | RSA 래핑 방식 |
| **감사** | 모든 키 사용 이력 OCI Audit 자동 기록 | |

---

### 1.4 CVE 취약점 점검 (Vulnerability Scanning Service)

| 구분 | 지원 항목 | 비고 |
|------|----------|------|
| **지원 OS** | Oracle Linux 7/8/9, CentOS 7/8, Ubuntu 18.04/20.04/22.04, Windows Server 2016/2019/2022 | RHEL은 제한적 |
| **스캔 유형** | OS 패키지 CVE 점검, CIS 벤치마크, 포트 스캔 | |
| **에이전트** | Oracle Cloud Agent (Run Command 플러그인과 동일 에이전트) | |
| **스캔 주기** | Daily, Weekly, 수동 트리거 | |
| **취약점 DB** | NVD(National Vulnerability Database) 기반 CVE | |
| **심각도 분류** | Critical / High / Medium / Low / Info (CVSS 기반) | |
| **컨테이너 이미지** | OCI Container Registry(OCIR) 이미지 스캔 지원 | |
| **Cloud Guard 연동** | 취약점 발견 시 Cloud Guard Problem 자동 생성 | |
| **결과 보고** | 인스턴스별 Risk Score, 취약점 목록, 수정 방법 제공 | |

---

### 1.5 OCI Run Command (Compute Run Command / Prov2)

| 구분 | 지원 항목 | 비고 |
|------|----------|------|
| **지원 OS** | Oracle Linux, CentOS, Ubuntu (Linux 전반), Windows Server | |
| **실행 방식** | Oracle Cloud Agent의 Run Command 플러그인 경유 | SSH 불필요 |
| **스크립트 유형** | Shell script (Linux), PowerShell (Windows), 인라인 텍스트 | |
| **스크립트 소스** | 인라인 텍스트, Object Storage URI | |
| **출력 대상** | 직접 텍스트 반환, Object Storage 저장 | |
| **실행 시간 제한** | 최대 3600초 (1시간) | |
| **동시 실행** | 복수 인스턴스 동시 실행 가능 (개별 Command 생성 필요) | |
| **인증** | IAM Policy 기반 (누가 어떤 인스턴스에 명령 실행 가능한지 제어) | |
| **감사** | 모든 실행 명령 OCI Audit 기록 (`CreateInstanceAgentCommand`) | |
| **네트워크 요건** | OCI Service Gateway 또는 인터넷 경유 OCI Control Plane 통신 필요 | |

---

### 1.6 Cloud Guard

| 구분 | 지원 항목 | 비고 |
|------|----------|------|
| **Detector 유형** | Configuration, Threat, Activity, Log Insight | |
| **커버 범위** | Compute, Network, Storage, IAM, Database, Vault, Streaming 등 전 서비스 | |
| **OS 보안 탐지** | CVE 발견, 패치 미적용, SSH 공인 노출, Root 로그인 허용, Agent 미실행, 공인 IP 직접 노출 | VSS/OS Mgmt 연동 필요 |
| **위협 탐지** | 비정상 로그인, 비정상 API 호출 패턴, 데이터 유출 징후 | Threat Detector |
| **자동 대응** | 공인 IP 제거, 인스턴스 중지, 버킷 비공개 전환, NSG 규칙 추가 | Responder Recipe |
| **알림** | OCI Notifications → Email, Slack, PagerDuty, OCI Functions | |
| **리포트** | 보안 점수(Security Score), 리전별/서비스별 현황 | |
| **SIEM 연동** | OCI Streaming → Splunk, QRadar 등 외부 SIEM | |

---

## 2. 통합 보안 설정 가이드 (Holistic Security Configuration)

보안을 **방어 계층(Defense in Depth)** 관점에서 외부 → 내부 순으로 설정합니다.

```
[인터넷]
    │
[Layer 1] WAF          ← L7 공격 차단
    │
[Layer 2] Load Balancer / API Gateway
    │
[Layer 3] NSG / Security List  ← 네트워크 접근 통제
    │
[Layer 4] Bastion Service     ← 관리 접속 통제
    │
[Layer 5] Compute Instance    ← OS 보안 (CVE, Run Command)
    │
[Layer 6] DB (MySQL/PostgreSQL/OpenSearch)  ← DB 접근통제
    │
[Layer 7] Data (Block Volume / Object Storage)  ← 암호화 (Vault/KMS)

[횡단] Cloud Guard    ← 전 계층 지속 모니터링
[횡단] Audit / Logging ← 전 계층 감사 기록
```

---

### Step 1. Vault 및 암호화 키 사전 생성 (최우선)

모든 서비스의 암호화 설정보다 먼저 Vault와 Master Key를 준비합니다.

```bash
# 1-1. Vault 생성
oci kms management vault create \
  --compartment-id <compartment-ocid> \
  --display-name "prod-vault" \
  --vault-type DEFAULT

# Vault Management Endpoint 저장
MGMT_EP=$(oci kms management vault get \
  --vault-id <vault-ocid> \
  --query 'data."management-endpoint"' --raw-output)

# 1-2. AES-256 마스터 키 생성 (블록볼륨/오브젝트스토리지용)
oci kms management key create \
  --compartment-id <compartment-ocid> \
  --display-name "prod-cmk-aes256" \
  --key-shape '{"algorithm":"AES","length":32}' \
  --protection-mode HSM \
  --endpoint $MGMT_EP

# 1-3. DB 비밀번호를 Vault Secret으로 저장
SECRET_VAL=$(echo -n "YourDBPassword!" | base64)
oci vault secret create-base64 \
  --compartment-id <compartment-ocid> \
  --vault-id <vault-ocid> \
  --key-id <key-ocid> \
  --secret-name "prod-mysql-admin-password" \
  --secret-content-content "$SECRET_VAL"
```

---

### Step 2. 네트워크 보안 설정

#### 2-1. NSG 구성 원칙

```
[Web Tier NSG]   인바운드: 80/443 (0.0.0.0/0) → WAF/LB에만 적용
[App Tier NSG]   인바운드: 8080 (Web Subnet CIDR만)
[DB Tier NSG]    인바운드: 3306/5432/9200 (App Subnet + Bastion Subnet만)
[Bastion NSG]    인바운드: 22 (OCI Bastion Service CIDR만, 직접 오픈 금지)
```

```bash
# DB NSG에 MySQL 인바운드 규칙 (App Subnet에서만)
oci network nsg-rules add \
  --nsg-id <db-nsg-ocid> \
  --ingress-security-rules '[{
    "protocol":"6",
    "source":"<app-subnet-cidr>",
    "sourceType":"CIDR_BLOCK",
    "tcpOptions":{"destinationPortRange":{"min":3306,"max":3306}},
    "description":"MySQL from App Subnet only"
  }]'
```

#### 2-2. WAF Policy 생성 및 LB 연결

```bash
# WAF Policy 생성 (Detection 모드로 시작)
oci waf web-app-firewall-policy create \
  --compartment-id <compartment-ocid> \
  --display-name "prod-waf-policy"

# LB에 WAF 연결
oci waf web-app-firewall create-for-load-balancer \
  --compartment-id <compartment-ocid> \
  --load-balancer-id <lb-ocid> \
  --web-app-firewall-policy-id <policy-ocid> \
  --display-name "prod-waf-lb"
```

---

### Step 3. 접근 통제 — Bastion Service

```bash
# Bastion 생성 (사무실 IP만 허용)
oci bastion bastion create \
  --compartment-id <compartment-ocid> \
  --bastion-type STANDARD \
  --name "prod-bastion" \
  --target-subnet-id <private-subnet-ocid> \
  --client-cidr-list '["<office-public-ip>/32"]'
```

---

### Step 4. DB 접근통제 + 암호화 적용

#### MySQL HeatWave CMK 적용

```bash
# MySQL DB System에 CMK 적용 (생성 시)
oci mysql db-system create \
  --compartment-id <compartment-ocid> \
  --availability-domain <ad> \
  --shape-name MySQL.VM.Standard.E4.1.8GB \
  --subnet-id <db-subnet-ocid> \
  --admin-username admin \
  --admin-password "$(oci secrets secretbundle get \
      --secret-id <secret-ocid> \
      --query 'data."secret-bundle-content".content' \
      --raw-output | base64 --decode)" \
  --kms-key-id <key-ocid> \
  --display-name "prod-mysql"
```

#### TLS 강제 적용 (MySQL)

Bastion Port Forwarding 세션을 통해 접속 후:

```sql
-- TLS 강제 설정 확인
SHOW VARIABLES LIKE 'require_secure_transport';
-- OFF면 SET GLOBAL require_secure_transport = ON;

-- 감사 로그 활성화
SET GLOBAL audit_log_policy = 'ALL';
```

#### OpenSearch FGAC 활성화

```bash
# OpenSearch 클러스터 생성 시 FGAC 활성화 (콘솔 권장)
# Bastion Port Forwarding 후 관리자 비밀번호 즉시 변경
curl -XPUT "https://<opensearch-ep>:9200/_plugins/_security/api/internalusers/admin" \
  -H 'Content-Type: application/json' \
  -u admin:oldpassword --insecure \
  -d '{"password": "NewStrongPassword!","backend_roles":["admin"]}'
```

---

### Step 5. CVE 취약점 점검 활성화

```bash
# 5-1. Oracle Cloud Agent Run Command + Vulnerability Scanning 플러그인 활성화
oci compute instance update \
  --instance-id <instance-ocid> \
  --agent-config '{
    "plugins-config": [
      {"name": "Vulnerability Scanning", "desired-state": "ENABLED"},
      {"name": "Run Command",            "desired-state": "ENABLED"},
      {"name": "OS Management Service Agent", "desired-state": "ENABLED"}
    ]
  }'

# 5-2. Scan Recipe 생성 (Weekly Standard)
oci vulnerability-scanning host-scan-recipe create \
  --compartment-id <compartment-ocid> \
  --display-name "prod-weekly-scan" \
  --schedule '{"type":"WEEKLY","dayOfWeek":"SUNDAY"}' \
  --agent-settings '{"scanLevel":"STANDARD","agentConfigurationDefined":true}'

# 5-3. Scan Target 생성 (Compartment 전체)
oci vulnerability-scanning host-scan-target create \
  --compartment-id <compartment-ocid> \
  --display-name "prod-all-instances" \
  --host-scan-recipe-id <recipe-ocid> \
  --target-compartment-id <compartment-ocid>
```

---

### Step 6. Cloud Guard 활성화 및 연동

```bash
# 6-1. Cloud Guard 활성화
oci cloud-guard configuration update \
  --compartment-id <tenancy-ocid> \
  --status ENABLED \
  --reporting-region ap-seoul-1

# 6-2. Root Compartment 대상 Target 생성
oci cloud-guard target create \
  --compartment-id <tenancy-ocid> \
  --display-name "prod-root-target" \
  --target-resource-type COMPARTMENT \
  --target-resource-id <tenancy-ocid>
```

---

### Step 7. Run Command로 보안 초기 설정 자동화

전체 인스턴스에 보안 초기 설정을 일괄 적용합니다.

```bash
# 보안 초기 설정 스크립트 (예시)
cat > /tmp/security-baseline.sh << 'EOF'
#!/bin/bash
# SSH 비밀번호 인증 비활성화
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl reload sshd

# Root 직접 로그인 비활성화
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# OS 패키지 보안 업데이트 적용
yum update --security -y 2>/dev/null || apt-get upgrade -y 2>/dev/null

# 불필요한 서비스 비활성화 (예시)
systemctl disable telnet 2>/dev/null
systemctl disable rsh 2>/dev/null

echo "Security baseline applied: $(date)"
EOF

# Object Storage에 스크립트 업로드 후 Run Command로 실행
oci os object put \
  --namespace <namespace> \
  --bucket-name prod-scripts \
  --name security-baseline.sh \
  --file /tmp/security-baseline.sh

oci compute instance-agent command create \
  --compartment-id <compartment-ocid> \
  --instance-id <instance-ocid> \
  --display-name "security-baseline-$(date +%Y%m%d)" \
  --execution-time-out-in-seconds 600 \
  --content '{
    "source": {
      "sourceType": "OBJECT_STORAGE_URI",
      "uri": "https://objectstorage.<region>.oraclecloud.com/n/<namespace>/b/prod-scripts/o/security-baseline.sh"
    },
    "output": {"outputType": "TEXT"}
  }'
```

---

## 3. 서비스 간 연동 매트릭스

| 이벤트 | 생성 서비스 | 연동 서비스 | 결과 |
|--------|-----------|-----------|------|
| CVE 발견 | Vulnerability Scanning | Cloud Guard | Problem 자동 생성 |
| 패치 미적용 | OS Management Service | Cloud Guard | Problem 자동 생성 |
| SSH 공인 노출 | Cloud Guard (Config Detector) | Notifications | 알림 발송 |
| WAF 공격 탐지 | WAF | OCI Logging | 로그 기록 |
| 키 사용 | Vault/KMS | OCI Audit | 모든 사용 기록 |
| Run Command 실행 | Compute Agent | OCI Audit | 실행 이력 기록 |
| DB 무단 접근 시도 | MySQL Audit Log | OCI Logging | 로그 기록 |

---

## 4. IAM Policy 통합 설정

```
# 보안 관리자 그룹
Allow group security-admins to manage cloud-guard-family in tenancy
Allow group security-admins to manage vaults in compartment prod-compartment
Allow group security-admins to manage keys in compartment prod-compartment
Allow group security-admins to manage bastion-family in compartment prod-compartment
Allow group security-admins to manage vulnerability-scan-family in compartment prod-compartment
Allow group security-admins to manage waf-family in compartment prod-compartment

# 운영자 그룹 (읽기 + Run Command 실행)
Allow group ops-team to read cloud-guard-family in compartment prod-compartment
Allow group ops-team to use bastion-sessions in compartment prod-compartment
Allow group ops-team to manage instance-agent-command-family in compartment prod-compartment
Allow group ops-team to read secret-family in compartment prod-compartment

# 인스턴스 Dynamic Group (Run Command + Secret 조회)
Allow dynamic-group prod-instances to use instance-agent-command-execution-family in compartment prod-compartment
Allow dynamic-group prod-instances to read secret-family in compartment prod-compartment
Allow dynamic-group prod-instances to use keys in compartment prod-compartment
```

---

## 5. 설정 완료 검증 체크리스트

```bash
# WAF 연결 확인
oci waf web-app-firewall list --compartment-id <cid> --output table

# Cloud Guard 활성화 확인
oci cloud-guard configuration get --compartment-id <tenancy-ocid> --query 'data.status'

# Vault 키 상태 확인
oci kms management key list --compartment-id <cid> --endpoint $MGMT_EP --output table

# Scan Target 활성 확인
oci vulnerability-scanning host-scan-target list --compartment-id <cid> --output table

# Bastion 상태 확인
oci bastion bastion list --compartment-id <cid> --output table

# Cloud Guard 미해결 Problem (HIGH 이상)
oci cloud-guard problem list \
  --compartment-id <tenancy-ocid> \
  --compartment-id-in-subtree true \
  --risk-level HIGH \
  --lifecycle-state OPEN \
  --output table
```
