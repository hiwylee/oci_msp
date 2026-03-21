#!/usr/bin/env bash

# process_state ACTION TYPE
#   ACTION : START | STOP
#   TYPE   : vm | db | adb | gg | all
#
# state.json 항목 예시:
#   {"type":"vm","region":"ap-seoul-1","id":"ocid1...","name":"myvm","state":"RUNNING"}
#
# VM  상태 : RUNNING / STOPPED
# ADB 상태 : AVAILABLE / STOPPED
# DB  상태 : AVAILABLE / STOPPED  (실제 start/stop은 DB Node 단위)
# GG  상태 : ACTIVE / INACTIVE

process_state() {
  local action="$1"   # START | STOP
  local type="$2"     # vm | db | adb | gg | all

  if [[ ! -f "$STATE_FILE" ]]; then
    echo "state.json 없음. 먼저 './main.sh list' 를 실행하세요." >&2
    exit 1
  fi

  local jq_filter
  if [[ "$type" == "all" ]]; then
    jq_filter=".[]"
  else
    jq_filter=".[] | select(.type == \"$type\")"
  fi

  # --id 가 지정되면 OCID 정확히 일치, --name 이면 대소문자 무시 부분 일치
  if [[ -n "${FILTER_ID:-}" ]]; then
    jq_filter+=" | select(.id == \"${FILTER_ID}\")"
  elif [[ -n "${FILTER_NAME:-}" ]]; then
    local name_lower
    name_lower=$(printf '%s' "${FILTER_NAME}" | tr '[:upper:]' '[:lower:]')
    jq_filter+=" | select(.name | ascii_downcase | contains(\"${name_lower}\"))"
  fi

  while IFS= read -r item; do
    local rtype region id name state
    rtype=$(printf '%s' "$item" | jq -r '.type')
    region=$(printf '%s' "$item" | jq -r '.region')
    id=$(printf '%s' "$item"    | jq -r '.id')
    name=$(printf '%s' "$item"  | jq -r '.name')
    state=$(printf '%s' "$item" | jq -r '.state // ""')

    case "$rtype" in
      vm)  _action_vm  "$action" "$region" "$id" "$name" "$state" ;;
      db)  _action_db  "$action" "$region" "$id" "$name" "$state" ;;
      adb) _action_adb "$action" "$region" "$id" "$name" "$state" ;;
      gg)  _action_gg  "$action" "$region" "$id" "$name" "$state" ;;
    esac
  done < <(jq -c "$jq_filter" "$STATE_FILE")
}

# ---------- VM (Compute Instance) ----------
_action_vm() {
  local action="$1" region="$2" id="$3" name="$4" state="$5"

  if [[ "$action" == "START" && "$state" == "RUNNING" ]]; then
    log "VM [$name] 이미 RUNNING — skip"
    return 0
  fi
  if [[ "$action" == "STOP" && ( "$state" == "STOPPED" || "$state" == "STOPPING" ) ]]; then
    log "VM [$name] 이미 STOPPED/STOPPING — skip"
    return 0
  fi

  local oci_action
  oci_action=$([ "$action" == "START" ] && echo "START" || echo "SOFTSTOP")
  log "${action} VM: $name ($region)"
  retry oci compute instance action \
    --instance-id "$id" \
    --action "$oci_action" \
    --region "$region" \
    --wait-for-state "$([ "$action" == "START" ] && echo "RUNNING" || echo "STOPPED")" \
    --max-wait-seconds 300 2>/dev/null || log "VM [$name] ${action} 실패 (무시)"
}

# ---------- DB System (Node 단위 start/stop) ----------
_action_db() {
  local action="$1" region="$2" id="$3" name="$4" state="$5"

  if [[ "$action" == "START" && "$state" == "AVAILABLE" ]]; then
    log "DB [$name] 이미 AVAILABLE — skip"
    return 0
  fi
  if [[ "$action" == "STOP" && ( "$state" == "STOPPED" || "$state" == "STOPPING" ) ]]; then
    log "DB [$name] 이미 STOPPED/STOPPING — skip"
    return 0
  fi

  log "${action} DB System: $name ($region)"
  local oci_node_action
  oci_node_action=$([ "$action" == "START" ] && echo "START" || echo "STOP")

  while IFS= read -r node_id; do
    [[ -z "$node_id" ]] && continue
    log "  DB Node ${oci_node_action}: $node_id"
    retry oci db node action \
      --db-node-id "$node_id" \
      --action "$oci_node_action" \
      --region "$region" 2>/dev/null || log "  DB Node [$node_id] ${oci_node_action} 실패 (무시)"
  done < <(oci db node list \
              --db-system-id "$id" \
              --compartment-id "$COMPARTMENT_ID" \
              --region "$region" 2>/dev/null \
            | jq -r '.data[].id')
}

# ---------- Autonomous Database ----------
_action_adb() {
  local action="$1" region="$2" id="$3" name="$4" state="$5"

  if [[ "$action" == "START" && "$state" == "AVAILABLE" ]]; then
    log "ADB [$name] 이미 AVAILABLE — skip"
    return 0
  fi
  if [[ "$action" == "STOP" && ( "$state" == "STOPPED" || "$state" == "STOPPING" ) ]]; then
    log "ADB [$name] 이미 STOPPED/STOPPING — skip"
    return 0
  fi

  log "${action} ADB: $name ($region)"
  local sub_cmd
  sub_cmd=$([ "$action" == "START" ] && echo "start" || echo "stop")
  retry oci db autonomous-database "$sub_cmd" \
    --autonomous-database-id "$id" \
    --region "$region" \
    --wait-for-state "$([ "$action" == "START" ] && echo "AVAILABLE" || echo "STOPPED")" \
    --max-wait-seconds 600 2>/dev/null || log "ADB [$name] ${action} 실패 (무시)"
}

# ---------- GoldenGate Deployment ----------
_action_gg() {
  local action="$1" region="$2" id="$3" name="$4" state="$5"

  if [[ "$action" == "START" && "$state" == "ACTIVE" ]]; then
    log "GG [$name] 이미 ACTIVE — skip"
    return 0
  fi
  if [[ "$action" == "STOP" && ( "$state" == "INACTIVE" || "$state" == "UPDATING" ) ]]; then
    log "GG [$name] 이미 INACTIVE/UPDATING — skip"
    return 0
  fi

  log "${action} GoldenGate: $name ($region)"
  local sub_cmd
  sub_cmd=$([ "$action" == "START" ] && echo "start" || echo "stop")
  retry oci goldengate deployment "$sub_cmd" \
    --deployment-id "$id" \
    --region "$region" \
    --wait-for-state "$([ "$action" == "START" ] && echo "ACTIVE" || echo "INACTIVE")" \
    --max-wait-seconds 300 2>/dev/null || log "GG [$name] ${action} 실패 (무시)"
}
