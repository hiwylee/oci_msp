# OCI MSP 플랫폼 - 인프라/DevOps 설계서

> **버전**: v1.0 | **최종 수정**: 2026-03-21

---

## 목차

1. [전체 인프라 구성도](#1-전체-인프라-구성도)
2. [Terraform 모듈 구조](#2-terraform-모듈-구조)
3. [Kubernetes 매니페스트](#3-kubernetes-매니페스트)
4. [Dockerfile (멀티스테이지)](#4-dockerfile-멀티스테이지)
5. [Docker Compose (로컬 개발)](#5-docker-compose-로컬-개발)
6. [GitHub Actions CI/CD](#6-github-actions-cicd)
7. [Observability](#7-observability)
8. [PostgreSQL HA + WAL 아카이빙](#8-postgresql-ha--wal-아카이빙)
9. [DR 페일오버 (RTO < 30분)](#9-dr-페일오버-rto--30분)
10. [비용 최적화](#10-비용-최적화)
11. [환경별 설정 관리](#11-환경별-설정-관리)
12. [부록: 운영 커맨드](#부록-운영-커맨드)

---

## 1. 전체 인프라 구성도

```
PRIMARY: ap-seoul-1
  VCN: msp-prod-vcn (10.0.0.0/16)
  ├── Public Subnet  10.0.1.0/24  → OCI Load Balancer, Bastion
  ├── Private Subnet 10.0.2.0/24  → OKE Node Pool (E4.Flex 4OCPU/64GB, min3~max10)
  └── DB Subnet      10.0.3.0/24  → PostgreSQL Primary + Standby (E4.Flex 2OCPU/32GB)

DR: ap-chuncheon-1  (Warm Standby, VCN 10.1.0.0/16 미러 구성)
  └── OKE 평시 0 replicas, PostgreSQL Streaming Standby 상시 유지

OCI Services: Vault | Object Storage | OCIR | APM | Logging Analytics | Monitoring
OCI Traffic Management: DNS Failover (TTL=30s, Health Check 10s 간격)
```

---

## 2. Terraform 모듈 구조

```
terraform/
├── shared/backend.tf              # OCI Object Storage remote state
├── environments/{dev,staging,prod,dr}/
│   ├── main.tf
│   ├── variables.tf
│   └── terraform.tfvars
└── modules/
    ├── network/    VCN, Subnet, Security List, NSG, LB
    ├── oke/        Cluster, Node Pool (VM.Standard.E4.Flex)
    ├── database/   PostgreSQL VM, 백업 설정
    ├── vault/      OCI Vault, Dynamic Group, Policy
    └── monitoring/ APM, Logging Analytics, Alarm, Budget
```

**Remote State (OCI Object Storage S3 호환)**
```hcl
# terraform/shared/backend.tf
terraform {
  backend "s3" {
    bucket   = "msp-terraform-state"
    key      = "${terraform.workspace}/terraform.tfstate"
    region   = "ap-seoul-1"
    endpoint = "https://<namespace>.compat.objectstorage.ap-seoul-1.oraclecloud.com"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}
```

**VCN + Subnet 모듈 핵심**
```hcl
# terraform/modules/network/main.tf (핵심 발췌)
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  cidr_blocks    = [var.vcn_cidr]          # "10.0.0.0/16"
  display_name   = "${var.project}-${var.env}-vcn"
}

resource "oci_core_subnet" "private" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.private_subnet_cidr
  prohibit_public_ip_on_vnic = true
  security_list_ids          = [oci_core_security_list.private.id]
  route_table_id             = oci_core_route_table.private.id  # NAT GW 경유
}

resource "oci_core_security_list" "db" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  # Private Subnet + DR Subnet만 5432 허용
  ingress_security_rules {
    protocol = "6"; source = var.private_subnet_cidr
    tcp_options { min = 5432; max = 5432 }
  }
  ingress_security_rules {
    protocol = "6"; source = var.dr_private_subnet_cidr
    tcp_options { min = 5432; max = 5432 }
  }
  egress_security_rules { protocol = "all"; destination = "0.0.0.0/0" }
}
```

**OKE Cluster + Node Pool**
```hcl
# terraform/modules/oke/main.tf
resource "oci_containerengine_cluster" "main" {
  compartment_id     = var.compartment_id
  kubernetes_version = "v1.30.1"
  name               = "${var.project}-${var.env}-oke"
  vcn_id             = var.vcn_id
  endpoint_config {
    is_public_ip_enabled = false
    subnet_id            = var.private_subnet_id
  }
  options {
    service_lb_subnet_ids = [var.public_subnet_id]
    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
  }
}

resource "oci_containerengine_node_pool" "main" {
  cluster_id     = oci_containerengine_cluster.main.id
  compartment_id = var.compartment_id
  name           = "${var.project}-${var.env}-nodepool"
  node_shape     = "VM.Standard.E4.Flex"
  node_shape_config {
    ocpus         = var.node_ocpus          # prod=4, dev=2
    memory_in_gbs = var.node_memory_in_gbs  # prod=64, dev=16
  }
  node_config_details {
    size = var.node_count   # prod=3, staging=2, dev=1
    dynamic "placement_configs" {
      for_each = var.availability_domains
      content { availability_domain = placement_configs.value; subnet_id = var.private_subnet_id }
    }
  }
}
```

**OCI Vault + Dynamic Group + Policy**
```hcl
# terraform/modules/vault/main.tf
resource "oci_kms_vault" "main" {
  compartment_id = var.compartment_id
  display_name   = "${var.project}-${var.env}-vault"
  vault_type     = "DEFAULT"
}

resource "oci_identity_dynamic_group" "oke_nodes" {
  compartment_id = var.tenancy_ocid
  name           = "${var.project}-${var.env}-oke-nodes"
  matching_rule  = "Any {instance.compartment.id = '${var.compartment_id}'}"
}

resource "oci_identity_policy" "vault_access" {
  compartment_id = var.compartment_id
  name           = "${var.project}-${var.env}-vault-policy"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.oke_nodes.name} to read secret-bundles in compartment id ${var.compartment_id}",
    "Allow dynamic-group ${oci_identity_dynamic_group.oke_nodes.name} to use keys in compartment id ${var.compartment_id}",
  ]
}
```

**OCI Budget ($3,000/월)**
```hcl
# terraform/modules/monitoring/budget.tf
resource "oci_budget_budget" "main" {
  compartment_id = var.tenancy_ocid
  amount         = 3000
  reset_period   = "MONTHLY"
  target_type    = "COMPARTMENT"
  targets        = [var.compartment_id]
}

resource "oci_budget_alert_rule" "warning" {
  budget_id      = oci_budget_budget.main.id
  type           = "ACTUAL"
  threshold      = 80
  threshold_type = "PERCENTAGE"
  recipients     = var.alert_email
}

resource "oci_budget_alert_rule" "critical" {
  budget_id      = oci_budget_budget.main.id
  type           = "ACTUAL"
  threshold      = 100
  threshold_type = "PERCENTAGE"
  recipients     = var.alert_email
}
```

---

## 3. Kubernetes 매니페스트

**Namespace**: `msp-prod`, `msp-staging`, `msp-dev`

### 3.1 API Deployment

```yaml
# k8s/prod/deployment-api.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: msp-api
  namespace: msp-prod
spec:
  replicas: 3
  selector:
    matchLabels:
      app: msp-api
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxUnavailable: 0, maxSurge: 1 }
  template:
    metadata:
      labels:
        app: msp-api
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
      containers:
        - name: api
          image: ap-seoul-1.ocir.io/<namespace>/msp-api:${IMAGE_TAG}  # IMAGE_TAG=${{ github.sha }}
          ports: [{containerPort: 8000}]
          resources:
            requests: {cpu: "500m", memory: "512Mi"}
            limits:   {cpu: "2000m", memory: "2Gi"}
          envFrom:
            - configMapRef: {name: msp-config}
            - secretRef:    {name: msp-secrets}
          livenessProbe:
            httpGet: {path: /health, port: 8000}
            initialDelaySeconds: 30; periodSeconds: 10
          readinessProbe:
            httpGet: {path: /health/ready, port: 8000}
            initialDelaySeconds: 10; periodSeconds: 5
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels: {app: msp-api}
```

### 3.2 Worker / Beat / Web Deployment (핵심 차이점)

| Deployment | replicas | image | command |
|------------|----------|-------|---------|
| msp-worker | 2 | msp-api:${{ github.sha }} | `celery -A app.workers.celery_app worker --concurrency=4` |
| msp-beat   | 1 | msp-api:${{ github.sha }} | `celery -A app.workers.celery_app beat --scheduler=redbeat.RedBeatScheduler` |
| msp-web    | 2 | msp-web:${{ github.sha }} | (기본 CMD: `node server.js`) |

> **Celery Beat 고가용성**: 기본적으로 단일 인스턴스로 운영(중복 태스크 방지).
> RedBeat 스케줄러 사용 시 Redis 기반 분산 락으로 다중 Beat 인스턴스 운영 가능.
> Pod 재시작 시 최대 30초 모니터링 폴링 중단은 허용 범위로 판단.
> Phase 2에서 RedBeat HA 구성 검토 예정.

> **이미지 태그 정책**: `latest` 태그 사용 금지. 항상 git SHA 기반 태그(`${{ github.sha }}`) 사용.
> 스테이징 참조용으로 `staging-latest` 브랜치 태그 추가 부착 가능:
> `docker tag image:$SHA image:staging-latest`

### 3.3 HPA

```yaml
# k8s/prod/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: msp-api-hpa
  namespace: msp-prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: msp-api
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: {type: Utilization, averageUtilization: 70}
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
    scaleUp:
      stabilizationWindowSeconds: 60
---
# msp-worker-hpa: minReplicas=1, maxReplicas=8, CPU 70%
```

> **WebSocket Gateway HPA**: WebSocket Gateway는 현재 API Pod와 동일 Deployment에서 운영되며
> `msp-api-hpa` HPA를 공유한다. OCI Load Balancer의 Sticky Session(쿠키 기반)으로
> 동일 사용자의 WebSocket 연결이 동일 Pod로 라우팅되도록 보장.
> Phase 2에서 WS Gateway를 별도 Deployment로 분리 시 독립 HPA 적용 예정:
> `msp-ws-hpa: minReplicas=2, maxReplicas=20, CPU 60%` (연결 수 기반 커스텀 메트릭 병행)

### 3.4 External Secrets (OCI Vault → K8s Secret)

```yaml
# k8s/prod/external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: oci-vault-store
  namespace: msp-prod
spec:
  provider:
    oracle:
      region: ap-seoul-1
      vault: <vault-ocid>
      auth:
        instancePrincipal: {}
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: msp-secrets
  namespace: msp-prod
spec:
  refreshInterval: 1h
  secretStoreRef: {name: oci-vault-store, kind: SecretStore}
  target: {name: msp-secrets, creationPolicy: Owner}
  data:
    - {secretKey: DATABASE_URL,  remoteRef: {key: msp-prod-database-url}}
    - {secretKey: REDIS_URL,     remoteRef: {key: msp-prod-redis-url}}
    - {secretKey: SECRET_KEY,    remoteRef: {key: msp-prod-secret-key}}
```

### 3.5 PodDisruptionBudget + ConfigMap

```yaml
# PDB: minAvailable=1 (api, worker 각각)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: msp-api-pdb, namespace: msp-prod}
spec:
  minAvailable: 1
  selector:
    matchLabels: {app: msp-api}
---
# ConfigMap: 환경별 앱 설정 (민감 정보 제외)
apiVersion: v1
kind: ConfigMap
metadata: {name: msp-config, namespace: msp-prod}
data:
  ENVIRONMENT: "production"
  LOG_LEVEL: "INFO"
  OCI_REGION: "ap-seoul-1"
  OBJECT_STORAGE_BUCKET: "msp-prod-storage"
  CORS_ORIGINS: "https://msp.example.com"
  OTEL_SERVICE_NAME: "msp-api"
  OTEL_EXPORTER_OTLP_ENDPOINT: "http://otel-collector:4317"
```

---

## 4. Dockerfile (멀티스테이지)

### 4.1 FastAPI (python:3.12-slim + uv, non-root)

```dockerfile
# Dockerfile.api
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 UV_SYSTEM_PYTHON=1
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY app/ ./app/
RUN groupadd -r appuser && useradd -r -g appuser appuser \
    && chown -R appuser:appuser /app
USER appuser

FROM base AS development
RUN uv sync --frozen
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]

FROM base AS production
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
```

> Celery Worker/Beat: 동일 이미지 사용, K8s Deployment의 `command`로 CMD 오버라이드

### 4.2 Next.js (node:20-alpine, standalone output)

```dockerfile
# Dockerfile.web
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build   # next.config.js: output: 'standalone' 필수

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder --chown=appuser:appgroup /app/.next/standalone ./
COPY --from=builder --chown=appuser:appgroup /app/.next/static ./.next/static
COPY --from=builder --chown=appuser:appgroup /app/public ./public
USER appuser
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD wget -qO- http://localhost:3000/api/health || exit 1
CMD ["node", "server.js"]
```

---

## 5. Docker Compose (로컬 개발)

```yaml
# docker-compose.yml
services:
  api:
    build: {context: ., dockerfile: Dockerfile.api, target: development}
    ports: ["8000:8000"]
    volumes: ["./app:/app/app:ro"]
    env_file: [.env.example]
    depends_on:
      db:    {condition: service_healthy}
      redis: {condition: service_healthy}

  web:
    build: {context: ./frontend, dockerfile: Dockerfile.web, target: development}
    ports: ["3000:3000"]
    environment:
      NEXT_PUBLIC_API_URL: http://localhost:8000

  worker:
    build: {context: ., dockerfile: Dockerfile.api, target: development}
    command: ["celery", "-A", "app.workers.celery_app", "worker", "--loglevel=debug", "--concurrency=2"]
    env_file: [.env.example]
    depends_on: [redis, db]

  beat:
    build: {context: ., dockerfile: Dockerfile.api, target: development}
    command: ["celery", "-A", "app.workers.celery_app", "beat", "--loglevel=debug"]
    env_file: [.env.example]
    depends_on: [redis]

  flower:
    build: {context: ., dockerfile: Dockerfile.api, target: development}
    command: ["celery", "-A", "app.workers.celery_app", "flower", "--port=5555", "--basic_auth=admin:admin"]
    ports: ["5555:5555"]
    depends_on: [redis]

  db:
    image: postgres:16-alpine
    ports: ["5432:5432"]
    environment:
      POSTGRES_USER: msp_user
      POSTGRES_PASSWORD: msp_password
      POSTGRES_DB: msp_dev
    volumes: ["postgres_data:/var/lib/postgresql/data"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U msp_user -d msp_dev"]
      interval: 10s; timeout: 5s; retries: 5

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
    command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes: ["redis_data:/data"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s; timeout: 5s; retries: 3

volumes:
  postgres_data:
  redis_data:
```

```bash
# .env.example
ENVIRONMENT=development
DATABASE_URL=postgresql+asyncpg://msp_user:msp_password@db:5432/msp_dev
REDIS_URL=redis://redis:6379/0
SECRET_KEY=dev-secret-key-change-in-production
CELERY_BROKER_URL=redis://redis:6379/0
CELERY_RESULT_BACKEND=redis://redis:6379/1
OCI_REGION=ap-seoul-1
LOG_LEVEL=DEBUG
```

---

## 6. GitHub Actions CI/CD

### 6.1 CI (PR 시)

```yaml
# .github/workflows/ci.yml
name: CI
on:
  pull_request:
    branches: [main, dev]

jobs:
  test-api:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env: {POSTGRES_USER: test_user, POSTGRES_PASSWORD: test_password, POSTGRES_DB: test_db}
        options: --health-cmd pg_isready --health-interval 10s --health-retries 5
        ports: ["5432:5432"]
      redis:
        image: redis:7-alpine
        options: --health-cmd "redis-cli ping" --health-interval 10s
        ports: ["6379:6379"]
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v4
      - run: uv sync --frozen
      - run: uv run ruff check app/ tests/
      - run: uv run mypy app/
      - name: pytest
        env:
          DATABASE_URL: postgresql+asyncpg://test_user:test_password@localhost:5432/test_db
          REDIS_URL: redis://localhost:6379/0
          SECRET_KEY: test-secret-key
          ENVIRONMENT: test
        run: uv run pytest tests/ --cov=app --cov-report=xml --cov-fail-under=80

  test-web:
    runs-on: ubuntu-latest
    defaults:
      run: {working-directory: ./frontend}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: {node-version: "20", cache: "npm", cache-dependency-path: frontend/package-lock.json}
      - run: npm ci
      - run: npx tsc --noEmit
      - run: npm run lint
      - run: npm run test:ci  # vitest --run --coverage

  security:
    runs-on: ubuntu-latest
    needs: [test-api, test-web]
    steps:
      - uses: actions/checkout@v4
      - run: docker build -f Dockerfile.api --target production -t msp-api:scan .
      - uses: aquasecurity/trivy-action@master
        with:
          image-ref: "msp-api:scan"
          format: sarif
          output: trivy-results.sarif
          severity: CRITICAL,HIGH
          exit-code: "1"
```

### 6.2 Deploy Staging (dev 브랜치 push)

```yaml
# .github/workflows/deploy-staging.yml
name: Deploy Staging
on:
  push:
    branches: [dev]

jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      OCIR_REPO: ap-seoul-1.ocir.io/${{ secrets.OCI_NAMESPACE }}/msp
      K8S_NS: msp-staging
    steps:
      - uses: actions/checkout@v4
      - uses: oracle-actions/configure-oci-credentials@v1
        with:
          user: ${{ secrets.OCI_USER_OCID }}
          fingerprint: ${{ secrets.OCI_FINGERPRINT }}
          tenancy: ${{ secrets.OCI_TENANCY_OCID }}
          region: ap-seoul-1
          key_content: ${{ secrets.OCI_PRIVATE_KEY }}
      - name: Login to OCIR
        run: |
          echo "${{ secrets.OCI_AUTH_TOKEN }}" | docker login ap-seoul-1.ocir.io \
            -u "${{ secrets.OCI_NAMESPACE }}/${{ secrets.OCI_USERNAME }}" --password-stdin
      - name: Build & Push
        run: |
          SHA=${{ github.sha }}
          docker build -f Dockerfile.api --target production \
            -t "${{ env.OCIR_REPO }}-api:${SHA}" . && docker push "${{ env.OCIR_REPO }}-api:${SHA}"
          docker build -f Dockerfile.web --target runner \
            -t "${{ env.OCIR_REPO }}-web:${SHA}" ./frontend && docker push "${{ env.OCIR_REPO }}-web:${SHA}"
      - name: Run DB Migrations
        run: |
          # 마이그레이션 전용 K8s Job 실행
          kubectl apply -f k8s/jobs/db-migrate.yaml
          kubectl wait --for=condition=complete job/db-migrate --timeout=300s
          kubectl delete job db-migrate
      - name: Deploy & Rollout
        run: |
          oci ce cluster create-kubeconfig --cluster-id ${{ secrets.OKE_STAGING_CLUSTER_ID }} \
            --region ap-seoul-1 --token-version 2.0.0
          SHA=${{ github.sha }}
          kubectl set image deployment/msp-api    api="${{ env.OCIR_REPO }}-api:${SHA}" -n ${{ env.K8S_NS }}
          kubectl set image deployment/msp-worker worker="${{ env.OCIR_REPO }}-api:${SHA}" -n ${{ env.K8S_NS }}
          kubectl set image deployment/msp-web    web="${{ env.OCIR_REPO }}-web:${SHA}"  -n ${{ env.K8S_NS }}
          kubectl rollout status deployment/msp-api -n ${{ env.K8S_NS }} --timeout=300s
      - name: Smoke test
        run: |
          LB_IP=$(kubectl get svc msp-api-svc -n ${{ env.K8S_NS }} \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
          curl -sf "http://${LB_IP}:8000/health" | jq '.status' | grep -q "ok"
```

### 6.3 Deploy Production (main 브랜치, 수동 승인)

```yaml
# .github/workflows/deploy-prod.yml
name: Deploy Production
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production  # GitHub Environment 수동 승인
    env:
      OCIR_REPO: ap-seoul-1.ocir.io/${{ secrets.OCI_NAMESPACE }}/msp
      K8S_NS: msp-prod
    steps:
      - uses: actions/checkout@v4
      - uses: oracle-actions/configure-oci-credentials@v1
        with:
          user: ${{ secrets.OCI_USER_OCID }}
          fingerprint: ${{ secrets.OCI_FINGERPRINT }}
          tenancy: ${{ secrets.OCI_TENANCY_OCID }}
          region: ap-seoul-1
          key_content: ${{ secrets.OCI_PRIVATE_KEY }}
      - name: Tag prod images
        run: |
          SHA=${{ github.sha }}; SHORT=${SHA:0:8}; DATE=$(date +%Y%m%d)
          TAG="prod-${DATE}-${SHORT}"
          echo "PROD_TAG=${TAG}" >> $GITHUB_ENV
          for svc in api web; do
            docker pull "${{ env.OCIR_REPO }}-${svc}:${SHA}" 2>/dev/null || \
              docker build -f "Dockerfile.${svc}" --target $([ "$svc"=web ] && echo runner || echo production) \
                -t "${{ env.OCIR_REPO }}-${svc}:${SHA}" $([ "$svc"=web ] && echo ./frontend || echo .)
            docker tag "${{ env.OCIR_REPO }}-${svc}:${SHA}" "${{ env.OCIR_REPO }}-${svc}:${TAG}"
            docker push "${{ env.OCIR_REPO }}-${svc}:${TAG}"
          done
      - name: Run DB Migrations
        run: |
          # 마이그레이션 전용 K8s Job 실행
          kubectl apply -f k8s/jobs/db-migrate.yaml
          kubectl wait --for=condition=complete job/db-migrate --timeout=300s
          kubectl delete job db-migrate
      - name: Deploy OKE
        run: |
          oci ce cluster create-kubeconfig --cluster-id ${{ secrets.OKE_PROD_CLUSTER_ID }} \
            --region ap-seoul-1 --token-version 2.0.0
          TAG=${{ env.PROD_TAG }}
          kubectl set image deployment/msp-api    api="${{ env.OCIR_REPO }}-api:${TAG}" -n ${{ env.K8S_NS }}
          kubectl set image deployment/msp-worker worker="${{ env.OCIR_REPO }}-api:${TAG}" -n ${{ env.K8S_NS }}
          kubectl set image deployment/msp-beat   beat="${{ env.OCIR_REPO }}-api:${TAG}" -n ${{ env.K8S_NS }}
          kubectl set image deployment/msp-web    web="${{ env.OCIR_REPO }}-web:${TAG}"  -n ${{ env.K8S_NS }}
          kubectl rollout status deployment/msp-api -n ${{ env.K8S_NS }} --timeout=600s
          kubectl rollout status deployment/msp-web -n ${{ env.K8S_NS }} --timeout=600s
      - name: Health check
        run: sleep 15 && curl -sf "https://msp.example.com/health" | grep -q "ok"
```

### 6.4 DB 마이그레이션 K8s Job 매니페스트

```yaml
# k8s/jobs/db-migrate.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: migrate
        image: OCIR_HOST/msp/api:${IMAGE_TAG}
        command: ["alembic", "upgrade", "head"]
        envFrom:
        - secretRef:
            name: msp-secrets
```

---

## 7. Observability

### 7.1 OpenTelemetry FastAPI 계측

```python
# app/telemetry.py
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.sdk.resources import Resource
import os

def setup_telemetry(app):
    resource = Resource.create({
        "service.name": os.getenv("OTEL_SERVICE_NAME", "msp-api"),
        "deployment.environment": os.getenv("ENVIRONMENT", "development"),
    })
    provider = TracerProvider(resource=resource)
    provider.add_span_processor(BatchSpanProcessor(
        OTLPSpanExporter(endpoint=os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317"))
    ))
    trace.set_tracer_provider(provider)
    FastAPIInstrumentor.instrument_app(app)
    SQLAlchemyInstrumentor().instrument()
    RedisInstrumentor().instrument()
```

### 7.2 구조화 로그 (loguru, JSON)

```python
# app/logging_config.py
import sys
from loguru import logger

def setup_logging(environment: str = "production"):
    logger.remove()
    if environment == "production":
        logger.configure(handlers=[{
            "sink": sys.stdout, "serialize": True, "level": "INFO"
        }])
    else:
        logger.add(sys.stdout, colorize=True, level="DEBUG",
            format="<green>{time:HH:mm:ss}</green> | <level>{level: <8}</level> | {message}")
    return logger
```

### 7.3 OCI Monitoring 알람

| 알람 | 조건 | 심각도 |
|------|------|--------|
| API 에러율 | > 5% (5분 평균) | CRITICAL |
| OKE Node CPU | > 85% (5분 평균) | WARNING |
| PostgreSQL Disk | > 80% | CRITICAL |

```hcl
# terraform/modules/monitoring/alarms.tf (핵심 발췌)
resource "oci_monitoring_alarm" "api_error_rate" {
  compartment_id        = var.compartment_id
  display_name          = "msp-api-error-rate-critical"
  namespace             = "oci_apm_synthetics"
  query                 = "ErrorRate[5m].mean() > 5"
  severity              = "CRITICAL"
  destinations          = [oci_ons_notification_topic.alerts.id]
  is_enabled            = true
  metric_compartment_id = var.compartment_id
}
```

---

## 8. PostgreSQL HA + WAL 아카이빙

### 8.1 postgresql.conf 핵심 설정

```ini
# RPO < 5분을 위한 핵심 설정
wal_level               = replica
max_wal_senders         = 5
wal_keep_size           = 1GB
hot_standby             = on
synchronous_commit      = remote_write    # RPO 보장

# WAL 아카이빙 → OCI Object Storage
archive_mode            = on
archive_command         = 'oci os object put --bucket-name msp-prod-wal-archive \
                           --name "wal/%f" --file %p --auth instance_principal && echo "archived %f"'
archive_timeout         = 60             # 최대 60초 내 WAL 아카이빙 (RPO 핵심)

# 성능 (VM.Standard.E4.Flex 2OCPU/32GB 기준)
shared_buffers          = 8GB
effective_cache_size    = 24GB
work_mem                = 64MB
max_connections         = 200
```

### 8.2 pg_dump CronJob (K8s, 매일 02:00 KST)

```yaml
# k8s/prod/cronjob-pg-backup.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: msp-prod
spec:
  schedule: "0 17 * * *"   # 02:00 KST = 17:00 UTC
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: pg-backup
              image: postgres:16-alpine
              command:
                - /bin/sh
                - -c
                - |
                  DATE=$(date +%Y%m%d-%H%M%S)
                  pg_dump "$DATABASE_URL" | gzip > "/tmp/msp-prod-${DATE}.sql.gz"
                  oci os object put --bucket-name msp-prod-db-backup \
                    --name "daily/msp-prod-${DATE}.sql.gz" \
                    --file "/tmp/msp-prod-${DATE}.sql.gz" \
                    --auth instance_principal
              env:
                - name: DATABASE_URL
                  valueFrom:
                    secretKeyRef: {name: msp-secrets, key: DATABASE_URL}
              resources:
                limits: {cpu: "500m", memory: "512Mi"}
```

**백업 보존**: Daily 30일 | Weekly 12주 | WAL 아카이브 7일

---

## 9. DR 페일오버 (RTO < 30분)

### 9.1 OCI Traffic Management

```hcl
resource "oci_dns_steering_policy" "failover" {
  compartment_id          = var.compartment_id
  template                = "FAILOVER"
  health_check_monitor_id = oci_health_checks_http_monitor.api.id
  ttl                     = 30   # 빠른 DNS 전파
  # primary pool → dr pool 자동 전환
}

resource "oci_health_checks_http_monitor" "api" {
  compartment_id      = var.compartment_id
  interval_in_seconds = 10   # 10초 간격 헬스체크
  targets             = [var.primary_lb_ip]
  path                = "/health"
  protocol            = "HTTPS"
  timeout_in_seconds  = 5
}
```

### 9.2 페일오버 단계 (총 ~25분)

```
단계 1: Primary 장애 감지       ~2분  (Health Check 3회 실패 + PagerDuty 트리거)
단계 2: DR PostgreSQL 승격      ~5분  (pg_ctl promote + recovery 확인)
단계 3: DR ConfigMap 업데이트   ~8분  (DB URL 변경 + rollout restart)
단계 4: 서비스 배포 완료 대기   ~5분  (rollout status --timeout=300s)
단계 5: DNS 전환                ~3분  (Traffic Management Primary 풀 비활성화)
단계 6: 검증                    ~2분  (헬스체크 + smoke test)
                              ─────
합계                           ~25분  ← RTO < 30분 충족
```

### 9.3 failover.sh (자동화 스크립트 개요)

```bash
#!/bin/bash
# scripts/failover.sh - 7단계 DR 페일오버 자동화
set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/msp-failover.log; }

# 1. DR kubeconfig 설정
oci ce cluster create-kubeconfig --cluster-id "$DR_CLUSTER_ID" \
  --region ap-chuncheon-1 --token-version 2.0.0

# 2. PostgreSQL Standby 승격
kubectl exec -n msp-prod msp-postgres-dr-0 -- pg_ctl promote -D /var/lib/postgresql/data
sleep 10

# 3. ConfigMap DB 주소 업데이트
kubectl patch configmap msp-config -n msp-prod --type merge \
  -p '{"data":{"DATABASE_HOST":"msp-postgres-dr-0.msp-prod.svc.cluster.local"}}'

# 4. Pod 재기동
for d in msp-api msp-worker msp-beat msp-web; do
  kubectl rollout restart deployment/$d -n msp-prod
done
kubectl rollout status deployment/msp-api -n msp-prod --timeout=300s

# 5. DNS 전환 (Primary 풀 비활성화)
oci dns steering-policy update --steering-policy-id "$TRAFFIC_POLICY_ID" \
  --rules '[{"ruleType":"HEALTH","cases":[{"answerData":[{"answerCondition":"answer.pool == '\''dr'\''","value":1}],"count":1}]}]'

# 6~7. 검증 + PagerDuty 완료 알림
sleep 30
curl -sf "https://msp.example.com/health" | grep -q "ok" && \
  log "DR 페일오버 완료" || { log "헬스체크 실패"; exit 1; }
```

---

## 10. 비용 최적화

### 10.1 Preemptible Instance (Spot) - Worker ~70% 절감

```hcl
# Worker 전용 Spot Node Pool
resource "oci_containerengine_node_pool" "spot_workers" {
  name       = "${var.project}-${var.env}-spot-workers"
  node_shape = "VM.Standard.E4.Flex"
  # Preemptible 설정은 node_source_details 내 preemptible_node_config 사용
  initial_node_labels {
    key = "node-type"; value = "spot-worker"
  }
}
```

Worker Deployment에 Toleration 추가:
```yaml
tolerations:
  - {key: "spot", operator: "Equal", value: "true", effect: "NoSchedule"}
nodeSelector:
  node-type: "spot-worker"
```

### 10.2 Dev 환경 야간 스케일 다운 (OCI Scheduler)

```bash
# 평일 20:00 KST: Node Pool 크기 0으로 (비용 최소화)
oci ce node-pool update --node-pool-id "$DEV_NODE_POOL_ID" --size 0
# 평일 09:00 KST: Node Pool 복원
oci ce node-pool update --node-pool-id "$DEV_NODE_POOL_ID" --size 1
```

### 10.3 KEDA ScaledObject (Redis 큐 기반 Worker 스케일)

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: msp-worker-scaler
  namespace: msp-prod
spec:
  scaleTargetRef: {name: msp-worker}
  minReplicaCount: 1
  maxReplicaCount: 8
  cooldownPeriod: 120
  triggers:
    - type: redis
      metadata:
        address: msp-redis:6379
        listName: celery
        listLength: "5"    # 큐 5개당 Worker 1개
        databaseIndex: "0"
```

### 10.4 예상 월 비용 (prod)

| 리소스 | 사양 | 월 비용(USD) |
|--------|------|-------------|
| OKE Node Pool (On-demand, 3노드) | E4.Flex 4OCPU/64GB | ~$420 |
| OKE Spot Node Pool (Worker, 평균 2노드) | E4.Flex 4OCPU/32GB | ~$84 |
| PostgreSQL Primary+Standby | E4.Flex 2OCPU/32GB × 2 | ~$280 |
| OCI LB + Object Storage + APM | - | ~$124 |
| **합계** | | **~$908** |

OCI Budget 알람: $3,000/월 기준 80%($2,400) WARNING, 100%($3,000) CRITICAL

---

## 11. 환경별 설정 관리

### 11.1 비밀 정보 흐름

```
OCI Vault Secret
    │ Instance Principal (1시간마다 갱신)
    ▼
External Secrets Operator
    │ K8s Secret 생성/동기화
    ▼
K8s Secret (msp-secrets)
    │ envFrom.secretRef
    ▼
Pod 환경변수
```

**원칙**: 민감 정보는 절대 ConfigMap/Git에 저장하지 않음. 모두 Vault → ESO → Secret 경로 사용.

### 11.2 환경 분기

```python
# app/config.py
from pydantic_settings import BaseSettings
from functools import lru_cache

class Settings(BaseSettings):
    environment: str = "development"
    database_url: str
    redis_url: str
    secret_key: str
    oci_region: str = "ap-seoul-1"

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    class Config:
        env_file = ".env.example"

@lru_cache
def get_settings() -> Settings:
    return Settings()
```

환경 분기는 `ENVIRONMENT` 변수 하나로 처리. 별도 feature flag 시스템 없음.

### 11.3 Vault Secret 명명 규칙

```
msp-{env}-{key}
예: msp-prod-database-url, msp-staging-redis-url, msp-dev-secret-key
```

---

## 부록: 운영 커맨드

```bash
# OKE kubeconfig 설정
oci ce cluster create-kubeconfig --cluster-id $CLUSTER_ID --region ap-seoul-1 --token-version 2.0.0

# 배포 상태 확인
kubectl rollout status deployment/msp-api -n msp-prod

# 배포 롤백 (직전 버전)
kubectl rollout undo deployment/msp-api -n msp-prod

# Worker 수동 스케일
kubectl scale deployment/msp-worker --replicas=5 -n msp-prod

# HPA 상태
kubectl get hpa -n msp-prod

# Celery 큐 상태 확인
kubectl exec -n msp-prod deploy/msp-api -- celery -A app.workers.celery_app inspect active

# PostgreSQL 복제 상태 확인
kubectl exec -n msp-prod msp-postgres-0 -- psql -U msp_user -c "SELECT * FROM pg_stat_replication;"

# PostgreSQL 복제 지연 확인 (DR Standby)
kubectl exec -n msp-prod msp-postgres-dr-0 -- \
  psql -U msp_user -c "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;"

# 백업 수동 실행
kubectl create job --from=cronjob/postgres-backup manual-backup-$(date +%Y%m%d) -n msp-prod

# 최근 백업 목록 확인
oci os object list --bucket-name msp-prod-db-backup --prefix "daily/" \
  --auth instance_principal | jq '.data[] | {name, "time-created": ."time-created"}'

# API 에러 로그 필터 (JSON 구조화 로그)
kubectl logs deploy/msp-api -n msp-prod | jq 'select(.level == "ERROR")'

# Pod 내부 접속 (디버깅)
kubectl exec -it deploy/msp-api -n msp-prod -- /bin/sh
```

---

*이 문서는 OCI MSP 플랫폼 v1.0 기준. 인프라 변경 시 문서를 함께 업데이트하세요.*
