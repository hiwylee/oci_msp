#!/usr/bin/env bash

# process_state ACTION TYPE
#   ACTION : START | STOP
#   TYPE   : vm | db | adb | gg | all
#
# VM  상태 : RUNNING / STOPPED
# ADB 상태 : AVAILABLE / STOPPED
# DB  상태 : AVAILABLE / STOPPED  (실제 start/stop은 DB Node 단위)
# GG  상태 : ACTIVE / INACTIVE

process_state() {
  local action="$1"   # START | STOP
  local type="$2"     # vm | db | adb | gg | all

  if [[ ! -f "$STATE_FILE" ]]; then
    echo "state.json 없음. 먼저 './oci_cmd.sh list' 를 실행하세요." >&2
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
    rtype=$(printf '%s' "$item"  | jq -r '.type')
    region=$(printf '%s' "$item" | jq -r '.region // ""')
    id=$(printf '%s' "$item"     | jq -r '.id')
    name=$(printf '%s' "$item"   | jq -r '.name')
    state=$(printf '%s' "$item"  | jq -r '.state // ""')

    case "$rtype" in
      vm)  _action_vm  "$action" "$region" "$id" "$name" "$state" ;;
      db)  _action_db  "$action" "$region" "$id" "$name" "$state" ;;
      adb) _action_adb "$action" "$region" "$id" "$name" "$state" ;;
      gg)  _action_gg  "$action" "$region" "$id" "$name" "$state" ;;
    esac
  done < <(jq -c "$jq_filter" "$STATE_FILE")
}

# region 이 비어있으면 --region 플래그 생략 (profile 기본 region 사용)
_region_args() {
  local region="$1"
  if [[ -n "$region" ]]; then
    echo "--region" "$region"
  fi
}

# ---------- VM (Compute Instance) ----------
_action_vm() {
  local action="$1" region="$2" id="$3" name="$4" state="$5"
  local _r=(); [[ -n "$region" ]] && _r=(--region "$region")

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
  log "${action} VM: $name${region:+ ($region)}"
  retry oci compute instance action \
    --instance-id "$id" \
    --action "$oci_action" \
    ${_r[@]+"${_r[@]}"} \
    --wait-for-state "$([ "$action" == "START" ] && echo "RUNNING" || echo "STOPPED")" \
    --max-wait-seconds 300 > /dev/null 2>&1 || { log "VM [$name] ${action} 실패 (무시)"; return 0; }

  local vnic_data pub_ip priv_ip final_state
  vnic_data=$(oci compute instance list-vnics ${_r[@]+"${_r[@]}"} --instance-id "$id" 2>/dev/null)
  pub_ip=$(printf '%s' "$vnic_data"  | jq -r '.data[0]["public-ip"] // "-"')
  priv_ip=$(printf '%s' "$vnic_data" | jq -r '.data[0]["private-ip"] // "-"')
  final_state=$(oci compute instance get --instance-id "$id" ${_r[@]+"${_r[@]}"} 2>/dev/null \
    | jq -r '.data["lifecycle-state"] // "'"$state"'"')
  printf "  %-40s  %-16s  %-16s  %s\n" "$name" "$pub_ip" "$priv_ip" "$final_state"
}

# ---------- DB System (Node 단위 start/stop) ----------
_action_db() {
  local action="$1" region="$2" id="$3" name="$4" state="$5"
  local _r=(); [[ -n "$region" ]] && _r=(--region "$region")

  if [[ "$action" == "START" && "$state" == "AVAILABLE" ]]; then
    log "DB [$name] 이미 AVAILABLE — skip"
    return 0
  fi
  if [[ "$action" == "STOP" && ( "$state" == "STOPPED" || "$state" == "STOPPING" ) ]]; then
    log "DB [$name] 이미 STOPPED/STOPPING — skip"
    return 0
  fi

  log "${action} DB System: $name${region:+ ($region)}"
  local oci_node_action
  oci_node_action=$([ "$action" == "START" ] && echo "START" || echo "STOP")

  while IFS= read -r node_id; do
    [[ -z "$node_id" ]] && continue
    log "  DB Node ${oci_node_action}: $node_id"
    retry oci db node action \
      --db-node-id "$node_id" \
      --action "$oci_node_action" \
      ${_r[@]+"${_r[@]}"} > /dev/null 2>&1 || log "  DB Node [$node_id] ${oci_node_action} 실패 (무시)"
  done < <(oci db node list \
              --db-system-id "$id" \
              --compartment-id "$TENANCY_ID" \
              ${_r[@]+"${_r[@]}"} 2>/dev/null \
            | jq -r '.data[].id')

  local db_data final_state scan_ip service_name
  db_data=$(oci db system get --db-system-id "$id" ${_r[@]+"${_r[@]}"} 2>/dev/null)
  final_state=$(printf '%s' "$db_data" | jq -r '.data["lifecycle-state"] // "'"$state"'"')

  # SCAN IP
  local scan_ip_id
  scan_ip_id=$(printf '%s' "$db_data" | jq -r '.data["scan-ip-ids"][0] // ""')
  if [[ -n "$scan_ip_id" ]]; then
    scan_ip=$(oci network private-ip get --private-ip-id "$scan_ip_id" \
      ${_r[@]+"${_r[@]}"} 2>/dev/null | jq -r '.data["ip-address"] // "-"')
  else
    scan_ip=$(printf '%s' "$db_data" | jq -r '.data.hostname // "-"')
  fi

  # Host IPs (DB node VNICs) — public and private
  local host_pub_ips="" host_priv_ips=""
  while IFS= read -r vnic_id; do
    [[ -z "$vnic_id" ]] && continue
    local vnic_data
    vnic_data=$(oci network vnic get --vnic-id "$vnic_id" \
      ${_r[@]+"${_r[@]}"} 2>/dev/null)
    local pub priv
    pub=$(printf '%s' "$vnic_data"  | jq -r '.data["public-ip"] // "-"')
    priv=$(printf '%s' "$vnic_data" | jq -r '.data["private-ip"] // "-"')
    host_pub_ips="${host_pub_ips:+$host_pub_ips,}$pub"
    host_priv_ips="${host_priv_ips:+$host_priv_ips,}$priv"
  done < <(oci db node list \
              --db-system-id "$id" \
              --compartment-id "${COMPARTMENT_ID:-$TENANCY_ID}" \
              ${_r[@]+"${_r[@]}"} 2>/dev/null \
            | jq -r '.data[].["vnic-id"] // empty')
  [[ -z "$host_pub_ips" ]]  && host_pub_ips="-"
  [[ -z "$host_priv_ips" ]] && host_priv_ips="-"

  # Service name
  service_name=$(oci db database list \
    --db-system-id "$id" \
    --compartment-id "${COMPARTMENT_ID:-$TENANCY_ID}" \
    ${_r[@]+"${_r[@]}"} 2>/dev/null \
    | jq -r '.data[0]["db-unique-name"] // "-"')

  printf "  %-40s  %-16s  %-16s  %-20s  %-30s  %s\n" "$name" "$scan_ip" "$host_pub_ips" "$host_priv_ips" "$service_name" "$final_state"
}

# ---------- Autonomous Database ----------
_action_adb() {
  local action="$1" region="$2" id="$3" name="$4" state="$5"
  local _r=(); [[ -n "$region" ]] && _r=(--region "$region")

  if [[ "$action" == "START" && "$state" == "AVAILABLE" ]]; then
    log "ADB [$name] 이미 AVAILABLE — skip"
    return 0
  fi
  if [[ "$action" == "STOP" && ( "$state" == "STOPPED" || "$state" == "STOPPING" ) ]]; then
    log "ADB [$name] 이미 STOPPED/STOPPING — skip"
    return 0
  fi

  log "${action} ADB: $name${region:+ ($region)}"
  local sub_cmd
  sub_cmd=$([ "$action" == "START" ] && echo "start" || echo "stop")
  retry oci db autonomous-database "$sub_cmd" \
    --autonomous-database-id "$id" \
    ${_r[@]+"${_r[@]}"} \
    --wait-for-state "$([ "$action" == "START" ] && echo "AVAILABLE" || echo "STOPPED")" \
    --max-wait-seconds 600 > /dev/null 2>&1 || { log "ADB [$name] ${action} 실패 (무시)"; return 0; }

  local adb_data final_state ip
  adb_data=$(oci db autonomous-database get --autonomous-database-id "$id" ${_r[@]+"${_r[@]}"} 2>/dev/null)
  final_state=$(printf '%s' "$adb_data" | jq -r '.data["lifecycle-state"] // "'"$state"'"')
  ip=$(printf '%s' "$adb_data" | jq -r '.data["private-endpoint-ip"] // .data["private-endpoint"] // "-"')
  printf "  %-40s  %-16s  %s\n" "$name" "$ip" "$final_state"
}

# ---------- GoldenGate Deployment ----------
_action_gg() {
  local action="$1" region="$2" id="$3" name="$4" state="$5"
  local _r=(); [[ -n "$region" ]] && _r=(--region "$region")

  if [[ "$action" == "START" && "$state" == "ACTIVE" ]]; then
    log "GG [$name] 이미 ACTIVE — skip"
    return 0
  fi
  if [[ "$action" == "STOP" && ( "$state" == "INACTIVE" || "$state" == "UPDATING" ) ]]; then
    log "GG [$name] 이미 INACTIVE/UPDATING — skip"
    return 0
  fi

  log "${action} GoldenGate: $name${region:+ ($region)}"
  local sub_cmd
  sub_cmd=$([ "$action" == "START" ] && echo "start" || echo "stop")
  retry oci goldengate deployment "$sub_cmd" \
    --deployment-id "$id" \
    ${_r[@]+"${_r[@]}"} \
    --wait-for-state "$([ "$action" == "START" ] && echo "ACTIVE" || echo "INACTIVE")" \
    --max-wait-seconds 300 > /dev/null 2>&1 || { log "GG [$name] ${action} 실패 (무시)"; return 0; }

  local gg_data final_state ip
  gg_data=$(oci goldengate deployment get --deployment-id "$id" ${_r[@]+"${_r[@]}"} 2>/dev/null)
  final_state=$(printf '%s' "$gg_data" | jq -r '.data["lifecycle-state"] // "'"$state"'"')
  ip=$(printf '%s' "$gg_data" | jq -r '.data["public-ip-address"] // .data["private-ip-address"] // "-"')
  printf "  %-40s  %-16s  %s\n" "$name" "$ip" "$final_state"
}
