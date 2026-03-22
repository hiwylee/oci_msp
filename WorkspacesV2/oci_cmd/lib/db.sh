#!/usr/bin/env bash
list_db() {
  local region="${1:-}"
  local _r=()
  [[ -n "$region" ]] && _r=(--region "$region")
  oci db system list ${_r[@]+"${_r[@]}"} \
    --compartment-id "${COMPARTMENT_ID:-$TENANCY_ID}" --all \
  | jq -c --arg region "$region" \
      '.data[] | {id:.id, name:(.["display-name"] // ""),
                  state:(.["lifecycle-state"] // ""),
                  scan_ip_id:(.["scan-ip-ids"][0] // ""),
                  hostname:(.hostname // ""), region:$region}' \
  | while read -r row; do
      local id name state scan_ip_id scan_ip host_ips service_name
      id=$(printf '%s' "$row"          | jq -r '.id')
      name=$(printf '%s' "$row"        | jq -r '.name')
      state=$(printf '%s' "$row"       | jq -r '.state')
      scan_ip_id=$(printf '%s' "$row"  | jq -r '.scan_ip_id')

      # SCAN IP
      if [[ -n "$scan_ip_id" ]]; then
        scan_ip=$(oci network private-ip get --private-ip-id "$scan_ip_id" \
          ${_r[@]+"${_r[@]}"} 2>/dev/null | jq -r '.data["ip-address"] // "-"')
      else
        scan_ip=$(printf '%s' "$row" | jq -r '.hostname // "-"')
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

      printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$name" "$scan_ip" "$host_pub_ips" "$host_priv_ips" "$service_name" "$state"
      append_state "db" \
        "$(jq -c -n \
            --arg region "$region" --arg id "$id" \
            --arg name "$name"     --arg state "$state" \
            --arg scan_ip "$scan_ip" \
            --arg host_pub_ips "$host_pub_ips" --arg host_priv_ips "$host_priv_ips" \
            --arg service_name "$service_name" \
            '{type:"db",region:$region,id:$id,name:$name,state:$state,scan_ip:$scan_ip,host_pub_ips:$host_pub_ips,host_priv_ips:$host_priv_ips,service_name:$service_name}')"
    done
}
