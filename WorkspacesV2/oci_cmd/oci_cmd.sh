#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$BASE_DIR/.env"
export OCI_CLI_CONFIG_FILE="${OCI_CONFIG_FILE:-./.oci/config}"
# 상대경로면 BASE_DIR 기준 절대경로로 변환
[[ "$OCI_CLI_CONFIG_FILE" != /* ]] && OCI_CLI_CONFIG_FILE="${BASE_DIR}/${OCI_CLI_CONFIG_FILE#./}"
export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
source "$BASE_DIR/lib/common.sh"
source "$BASE_DIR/lib/state.sh"
source "$BASE_DIR/lib/compute.sh"
source "$BASE_DIR/lib/db.sh"
source "$BASE_DIR/lib/adb.sh"
source "$BASE_DIR/lib/gg.sh"
source "$BASE_DIR/lib/action.sh"
source "$BASE_DIR/lib/compartment.sh"
source "$BASE_DIR/lib/domain.sh"

CMD="${1:-}"
TYPE="${2:-all}"
FILTER_NAME=""
FILTER_ID=""
TENANCY_OVERRIDE=""
# COMPARTMENT_ID 는 .env 에서 로드된 값 유지 (--compartment-id arg로 덮어쓰기 가능)
REGIONS_ARG=()

# CMD, TYPE 이후 남은 옵션 파싱
shift 2 2>/dev/null || shift "$#" 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)       shift; FILTER_NAME="${1:-}" ;;
    --id)         shift; FILTER_ID="${1:-}"   ;;
    --tenancy-id) shift; TENANCY_OVERRIDE="${1:-}" ;;
    --region)     shift; REGIONS_ARG=("${1:-}") ;;
    --regions)    shift; IFS=',' read -r -a REGIONS_ARG <<< "${1:-}" ;;
    --profile)        shift; export OCI_CLI_PROFILE="${1:-}" ;;
    --compartment-id) shift; COMPARTMENT_ID="${1:-}" ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift || true
done

# --profile 미지정 시 OCI_PROFILE(.env) 사용, 둘 다 없으면 unset (OCI CLI 자체 DEFAULT)
if [[ -z "${OCI_CLI_PROFILE:-}" && -n "${OCI_PROFILE:-}" ]]; then
  export OCI_CLI_PROFILE="$OCI_PROFILE"
fi

setup_state_dir

usage() {
  cat <<'EOF'
Usage:
  ./oci_cmd.sh list  <type> [options]
  ./oci_cmd.sh start <type> [options]
  ./oci_cmd.sh stop  <type> [options]

Types:
  list   : vm | db | adb | gg | all | regions | domains | compartments
  start  : vm | db | adb | gg | all
  stop   : vm | db | adb | gg | all

Options:
  --profile        <name>      OCI config profile (default: config [DEFAULT])
  --region         <region>    Single region (default: profile region)
  --regions        <r1,r2,...> Comma-separated regions
  --compartment-id <ocid>      Compartment OCID (default: .env COMPARTMENT_ID or TENANCY_ID)
  --tenancy-id     <ocid>      Tenancy OCID override (list compartments only)
  --name           <name>      Filter by resource name (partial, case-insensitive)
  --id             <ocid>      Filter by resource OCID

Examples:
  ./oci_cmd.sh list all
  ./oci_cmd.sh list adb --compartment-id ocid1.compartment.oc1..xxx
  ./oci_cmd.sh list vm  --region ap-osaka-1
  ./oci_cmd.sh list all --regions ap-seoul-1,ap-osaka-1
  ./oci_cmd.sh list domains
  ./oci_cmd.sh list regions
  ./oci_cmd.sh list compartments
  ./oci_cmd.sh list compartments --tenancy-id ocid1.tenancy.oc1..xxx
  ./oci_cmd.sh start adb --name mydb
  ./oci_cmd.sh stop  vm  --id ocid1.instance.oc1..xxx
EOF
}

validate_type() {
  case "$1" in
    vm|db|adb|gg|all|regions|domains|compartments) return 0 ;;
    *) return 1 ;;
  esac
}

# list 출력 rows를 --name / --id 기준으로 필터링
apply_filter() {
  local rows="$1"
  local name_pat="$FILTER_NAME"

  if [[ -z "$name_pat" && -n "$FILTER_ID" && -f "$STATE_FILE" ]]; then
    name_pat=$(jq -r --arg id "$FILTER_ID" '.[] | select(.id == $id) | .name' "$STATE_FILE")
  fi

  if [[ -z "$name_pat" || -z "$rows" ]]; then
    printf '%s' "$rows"
    return 0
  fi

  printf '%s\n' "$rows" | grep -i "^${name_pat}"$'\t' || true
}

append_rows() {
  local current="$1"
  local extra="$2"
  if [[ -z "${extra:-}" ]]; then
    printf "%s" "$current"
    return 0
  fi
  if [[ -z "${current:-}" ]]; then
    printf "%s" "$extra"
    return 0
  fi
  printf "%s\n%s" "$current" "$extra"
}

case "$CMD" in
  list)
    require_env "TENANCY_ID"
    if ! validate_type "$TYPE"; then
      usage; exit 1
    fi

    # 최초 실행 시 profile 부트스트랩 (meta/regions/compartments 저장)
    init_profile

    # list regions: 구독 region 목록 조회 및 갱신
    if [[ "$TYPE" == "regions" ]]; then
      log "Discovering subscribed regions..."
      discovered=()
      while IFS= read -r r; do discovered+=("$r"); done < <(discover_regions)
      # regions.json 갱신
      printf '%s\n' "${discovered[@]}" \
        | jq -Rn '[inputs | {name:., home:false}]' \
        > "$STATE_DIR/regions.json"
      log "Saved ${#discovered[@]} region(s) → $STATE_DIR/regions.json"
      printf '%s\n' "${discovered[@]}"
      exit 0
    fi

    # list domains: IAM 1회 조회 (region 루프 없음)
    if [[ "$TYPE" == "domains" ]]; then
      init_type_state "domain"
      domain_rows=""
      domain_rows=$(list_domains "${REGIONS_ARG[0]:-}")
      finalize_type_state "domain"
      if [[ -n "$domain_rows" ]]; then
        echo
        echo "=== DOMAINS ==="
        { printf "NAME\tTYPE\tHOME-REGION\tSTATE\n"; printf "%s\n" "$domain_rows"; } \
          | column -t -s $'\t'
      fi
      log "Discovery complete. State → $STATE_DIR/domain.json"
      exit 0
    fi

    # list compartments: IAM 1회 조회
    if [[ "$TYPE" == "compartments" ]]; then
      {
        printf "NAME\tID\tSTATE\n"
        list_compartments "${TENANCY_OVERRIDE:-$TENANCY_ID}"
      } | column -t -s $'\t'
      exit 0
    fi

    log "Starting resource discovery... [profile: ${OCI_CLI_PROFILE:-DEFAULT}]"

    # --region/--regions 미지정 시 빈 문자열 하나 (profile 기본 region)
    if [[ ${#REGIONS_ARG[@]} -eq 0 ]]; then
      REGIONS=("")
    else
      REGIONS=("${REGIONS_ARG[@]}")
    fi
    log "Regions: ${REGIONS[*]:-<profile default>}"

    # 조회할 유형별 상태 파일 초기화
    case "$TYPE" in
      vm)  init_type_state "vm" ;;
      db)  init_type_state "db" ;;
      adb) init_type_state "adb" ;;
      gg)  init_type_state "gg" ;;
      all) for t in vm db adb gg; do init_type_state "$t"; done ;;
    esac

    vm_rows="" db_rows="" adb_rows="" gg_rows=""

    for region in "${REGIONS[@]}"; do
      case "$TYPE" in
        vm)  vm_rows="$(append_rows "$vm_rows" "$(list_compute "$region")")" ;;
        db)  db_rows="$(append_rows "$db_rows" "$(list_db "$region")")" ;;
        adb) adb_rows="$(append_rows "$adb_rows" "$(list_adb "$region")")" ;;
        gg)  gg_rows="$(append_rows "$gg_rows" "$(list_gg "$region")")" ;;
        all)
          vm_rows="$(append_rows "$vm_rows" "$(list_compute "$region")")"
          db_rows="$(append_rows "$db_rows" "$(list_db "$region")")"
          adb_rows="$(append_rows "$adb_rows" "$(list_adb "$region")")"
          gg_rows="$(append_rows "$gg_rows" "$(list_gg "$region")")"
          ;;
      esac
    done

    # 유형별 파일 확정 + combined state.json 생성
    case "$TYPE" in
      vm)  finalize_type_state "vm" ;;
      db)  finalize_type_state "db" ;;
      adb) finalize_type_state "adb" ;;
      gg)  finalize_type_state "gg" ;;
      all) for t in vm db adb gg; do finalize_type_state "$t"; done ;;
    esac
    build_combined_state

    vm_rows="$(apply_filter "$vm_rows")"
    db_rows="$(apply_filter "$db_rows")"
    adb_rows="$(apply_filter "$adb_rows")"
    gg_rows="$(apply_filter "$gg_rows")"

    case "$TYPE" in
      vm)  print_section "VM"  "$vm_rows" "NAME\tPUBLIC-IP\tPRIVATE-IP\tSTATE" ;;
      db)  print_section "DB"  "$db_rows" "NAME\tSCAN-IP\tHOST-PUB-IP\tHOST-PRIV-IP\tSERVICE-NAME\tSTATE" ;;
      adb) print_section "ADB" "$adb_rows" ;;
      gg)  print_section "GG"  "$gg_rows" ;;
      all)
        print_section "VM"  "$vm_rows" "NAME\tPUBLIC-IP\tPRIVATE-IP\tSTATE"
        print_section "DB"  "$db_rows" "NAME\tSCAN-IP\tHOST-PUB-IP\tHOST-PRIV-IP\tSERVICE-NAME\tSTATE"
        print_section "ADB" "$adb_rows"
        print_section "GG"  "$gg_rows"
        ;;
    esac

    log "Discovery complete. State → $STATE_DIR/"
    ;;

  start)
    if ! validate_type "$TYPE"; then usage; exit 1; fi
    log "Starting resources: $TYPE${FILTER_NAME:+ name=$FILTER_NAME}${FILTER_ID:+ id=$FILTER_ID}"
    process_state "START" "$TYPE"
    ;;

  stop)
    if ! validate_type "$TYPE"; then usage; exit 1; fi
    log "Stopping resources: $TYPE${FILTER_NAME:+ name=$FILTER_NAME}${FILTER_ID:+ id=$FILTER_ID}"
    process_state "STOP" "$TYPE"
    ;;

  *)
    usage; exit 1
    ;;
esac
