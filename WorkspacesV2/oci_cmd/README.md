# oci_cmd

OCI(Oracle Cloud Infrastructure) 리소스 라이프사이클 자동화 CLI 툴킷입니다.
여러 리전에 걸쳐 VM, DB System, Autonomous DB, GoldenGate 리소스를 조회·시작·중지합니다.

## 요구사항

- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) (`~/.oci/config` 설정 완료)
- [jq](https://stedolan.github.io/jq/)

## 설치

```bash
git clone https://github.com/hiwylee/oci_cmd.git
cd oci_cmd
cp .env.example .env   # 환경 설정
chmod +x main.sh
```

### `.env` 설정

| 변수 | 필수 | 설명 |
|------|:----:|------|
| `TENANCY_ID` | ✅ | Tenancy OCID. Region 자동 감지 및 전체 compartment 검색의 루트 |
| `OCI_PROFILE` | | `~/.oci/config` 프로파일 이름 (기본값: `DEFAULT`) |
| `MAX_RETRIES` | | OCI CLI 실패 시 재시도 횟수 (기본값: `3`) |
| `RETRY_DELAY` | | 재시도 간격(초, 기본값: `2`) |

> `REGIONS`, `COMPARTMENT_ID`는 더 이상 필요하지 않습니다.
> `TENANCY_ID` 하나로 구독된 모든 Region과 하위 Compartment를 자동 탐색합니다.

## 사용법

```
./main.sh <command> [type] [options]
```

### Commands

| 명령 | 설명 |
|------|------|
| `list` | 리소스 조회 및 state.json 갱신 |
| `start` | state.json 기반 리소스 시작 |
| `stop` | state.json 기반 리소스 중지 |
| `compartments` | Compartment 목록 조회 |

### Type

`vm` · `db` · `adb` · `gg` · `all` (기본값)

### Options

| 옵션 | 설명 |
|------|------|
| `--name <name>` | 이름 부분 일치 필터 (대소문자 무시) |
| `--id <ocid>` | OCID 정확히 일치 필터 |

## 예시

```bash
# 전체 리소스 조회 (state.json 갱신)
./main.sh list all

# VM만 조회
./main.sh list vm

# 특정 VM만 조회
./main.sh list vm --name mattermost

# 모든 VM 시작 (state.json 참조)
./main.sh start vm

# 특정 VM만 시작
./main.sh start vm --name mattermost

# OCID로 특정 ADB 중지
./main.sh stop adb --id ocid1.autonomousdatabase.oc1...

# Compartment 목록
./main.sh compartments
```

> `start` / `stop` 실행 전 반드시 `./main.sh list`로 state.json을 최신화하세요.

## 아키텍처

```
main.sh                  # CLI 진입점 · 인자 파싱 · 커맨드 라우팅
├── lib/
│   ├── common.sh        # log · retry · print_table · discover_regions() 유틸
│   ├── state.sh         # state/state.json 읽기·쓰기
│   ├── compute.sh       # OCI Compute (VM)
│   ├── db.sh            # OCI DB System
│   ├── adb.sh           # OCI Autonomous Database
│   ├── gg.sh            # OCI GoldenGate
│   └── action.sh        # process_state() — start/stop 실행
└── state/
    └── state.json       # list 후 생성되는 리소스 스냅샷
```

**Region · Compartment 자동 탐색**

```
list 실행 시
 └─ discover_regions()
     └─ oci iam region-subscription list
         → 구독된 모든 Region 자동 감지
             └─ 각 Region에서 --compartment-id TENANCY_ID
                             --compartment-id-in-subtree true
                → 모든 하위 Compartment 자동 포함
```

**State 흐름**

```
list  →  OCI CLI 조회  →  state.json 저장
start/stop  →  state.json 읽기  →  필터 적용  →  OCI CLI 실행
```

리소스가 이미 목표 상태인 경우(예: 이미 RUNNING인 VM에 start) 자동으로 건너뜁니다.

## 지원 리소스별 동작

| 타입 | start | stop |
|------|-------|------|
| `vm` | `oci compute instance action --action START` | `--action SOFTSTOP` |
| `db` | `oci db node action --action START` (노드 단위) | `--action STOP` |
| `adb` | `oci db autonomous-database start` | `stop` |
| `gg` | `oci goldengate deployment start` | `stop` |

## 라이선스

MIT
