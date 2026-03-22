# CHANGES

변경사항은 최신순으로 기록합니다.

---

## [Unreleased]

### 변경 (Changed)
- **진입점 파일명 변경**: `main.sh` → `oci_cmd.sh`
  - 모든 내부 참조(usage 메시지, 에러 메시지, 문서) 동시 업데이트

### 추가 (Added)
- **VM `list`**: Public IP / Private IP 컬럼 분리 표시 (`PUBLIC-IP`, `PRIVATE-IP`)
- **DB `list` / `start` / `stop`**: SCAN IP, Host Public IP, Host Private IP, Service Name 표시
  - SCAN IP: `scan-ip-ids[0]` → `oci network private-ip get` 조회 (없으면 hostname fallback)
  - Host IP: DB Node VNIC → `oci network vnic get` 조회, RAC 멀티노드 시 콤마 구분
  - Service Name: `oci db database list` → `db-unique-name`
- **`start` / `stop` 완료 후 1줄 요약 출력** (모든 리소스 타입)
  - VM: `name  public-ip  private-ip  state`
  - DB: `name  scan-ip  host-pub-ip  host-priv-ip  service-name  state`
  - ADB: `name  private-endpoint-ip  state`
  - GG: `name  public/private-ip  state`

### 수정 (Fixed)
- **`start` / `stop` 시 OCI CLI JSON 전체 출력 억제**
  - 기존: `--wait-for-state` 응답 JSON이 터미널에 그대로 출력됨
  - 수정: 모든 action 명령 stdout/stderr → `/dev/null`, 완료 후 별도 get 호출로 최종 상태 조회

---

## v0.1 — 초기 릴리즈

- OCI 리소스(VM, DB, ADB, GoldenGate) 조회·시작·중지 자동화
- 멀티 리전 지원 (`--region` / `--regions`)
- State 파일 기반 워크플로우 (`list` → `start`/`stop`)
- `--name` / `--id` 필터링
- Profile별 state 디렉터리 분리 (`state/<profile>/`)
- 구독 Region 및 Compartment 자동 탐색 (`TENANCY_ID` 기반)
