#!/usr/bin/env bash
list_compute() {
  local region="${1:-}"
  local _r=()
  [[ -n "$region" ]] && _r=(--region "$region")
  oci compute instance list ${_r[@]+"${_r[@]}"} \
    --compartment-id "${COMPARTMENT_ID:-$TENANCY_ID}" --all \
  | jq -c --arg region "$region" \
      '.data[] | {id:.id, name:(.["display-name"] // ""),
                  state:(.["lifecycle-state"] // ""), region:$region}' \
  | while read -r row; do
      local id name state vnic_data pub_ip priv_ip
      id=$(printf '%s' "$row"    | jq -r '.id')
      name=$(printf '%s' "$row"  | jq -r '.name')
      state=$(printf '%s' "$row" | jq -r '.state')
      vnic_data=$(oci compute instance list-vnics ${_r[@]+"${_r[@]}"} \
             --instance-id "$id" 2>/dev/null)
      pub_ip=$(printf '%s' "$vnic_data"  | jq -r '.data[0]["public-ip"] // "-"')
      priv_ip=$(printf '%s' "$vnic_data" | jq -r '.data[0]["private-ip"] // "-"')
      printf "%s\t%s\t%s\t%s\n" "$name" "$pub_ip" "$priv_ip" "$state"
      append_state "vm" \
        "$(jq -c -n \
            --arg region "$region" --arg id "$id" \
            --arg name "$name"     --arg state "$state" \
            --arg pub_ip "$pub_ip" --arg priv_ip "$priv_ip" \
            '{type:"vm",region:$region,id:$id,name:$name,state:$state,pub_ip:$pub_ip,priv_ip:$priv_ip}')"
    done
}
