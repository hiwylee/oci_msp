#!/usr/bin/env bash
list_gg() {
  local region="${1:-}"
  local _r=()
  [[ -n "$region" ]] && _r=(--region "$region")
  oci goldengate deployment list ${_r[@]+"${_r[@]}"} \
    --compartment-id "${COMPARTMENT_ID:-$TENANCY_ID}" --all \
  | jq -c --arg region "$region" \
      '.data.items[] | {id:.id, name:(.["display-name"] // ""),
                        state:(.["lifecycle-state"] // ""),
                        ip:(.["public-ip-address"] // .["private-ip-address"] // "-"),
                        region:$region}' \
  | while read -r row; do
      local id name state ip
      id=$(printf '%s' "$row"    | jq -r '.id')
      name=$(printf '%s' "$row"  | jq -r '.name')
      state=$(printf '%s' "$row" | jq -r '.state')
      ip=$(printf '%s' "$row"    | jq -r '.ip')
      printf "%s\t%s\t%s\n" "$name" "$ip" "$state"
      append_state "gg" \
        "$(jq -c -n \
            --arg region "$region" --arg id "$id" \
            --arg name "$name"     --arg state "$state" \
            '{type:"gg",region:$region,id:$id,name:$name,state:$state}')"
    done
}
