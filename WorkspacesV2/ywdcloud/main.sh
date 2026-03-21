#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$BASE_DIR/.env"
export OCI_CLI_PROFILE="${OCI_PROFILE:-DEFAULT}"
export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
source "$BASE_DIR/lib/common.sh"
source "$BASE_DIR/lib/state.sh"
source "$BASE_DIR/lib/compute.sh"
source "$BASE_DIR/lib/db.sh"
source "$BASE_DIR/lib/adb.sh"
source "$BASE_DIR/lib/gg.sh"
source "$BASE_DIR/lib/action.sh"

CMD="${1:-}"
TYPE="${2:-all}"
FILTER_NAME=""
FILTER_ID=""

# CMD, TYPE 이후 남은 옵션 파싱 (--name, --id)
shift 2 2>/dev/null || shift "$#" 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) shift; FILTER_NAME="${1:-}" ;;
    --id)   shift; FILTER_ID="${1:-}"   ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift || true
done

usage() {
  echo "Usage:"
  echo "./main.sh list  [vm|db|adb|gg|all] [--name <name>|--id <ocid>]"
  echo "./main.sh start [vm|db|adb|gg|all] [--name <name>|--id <ocid>]"
  echo "./main.sh stop  [vm|db|adb|gg|all] [--name <name>|--id <ocid>]"
}

validate_type() {
  case "$1" in
    vm|db|adb|gg|all) return 0 ;;
    *) return 1 ;;
  esac
}

# list 출력 rows를 --name / --id 기준으로 필터링
# --id는 state.json에서 name을 역조회한 뒤 name 필터로 처리
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

case "$CMD" in
  list)
    log "Starting resource discovery..."
    require_env "COMPARTMENT_ID"
    if ! validate_type "$TYPE"; then
      usage
      exit 1
    fi

    vm_rows=""
    db_rows=""
    adb_rows=""
    gg_rows=""

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

    init_state
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
    finalize_state

    vm_rows="$(apply_filter "$vm_rows")"
    db_rows="$(apply_filter "$db_rows")"
    adb_rows="$(apply_filter "$adb_rows")"
    gg_rows="$(apply_filter "$gg_rows")"

    case "$TYPE" in
      vm)  print_section "VM" "$vm_rows" ;;
      db)  print_section "DB" "$db_rows" ;;
      adb) print_section "ADB" "$adb_rows" ;;
      gg)  print_section "GG" "$gg_rows" ;;
      all)
        print_section "VM" "$vm_rows"
        print_section "DB" "$db_rows"
        print_section "ADB" "$adb_rows"
        print_section "GG" "$gg_rows"
        ;;
    esac

    log "Discovery complete."
    ;;

  start)
    if ! validate_type "$TYPE"; then
      usage
      exit 1
    fi
    log "Starting resources: $TYPE${FILTER_NAME:+ name=$FILTER_NAME}${FILTER_ID:+ id=$FILTER_ID}"
    process_state "START" "$TYPE"
    ;;

  stop)
    if ! validate_type "$TYPE"; then
      usage
      exit 1
    fi
    log "Stopping resources: $TYPE${FILTER_NAME:+ name=$FILTER_NAME}${FILTER_ID:+ id=$FILTER_ID}"
    process_state "STOP" "$TYPE"
    ;;

  *)
    usage
    exit 1
    ;;
esac
