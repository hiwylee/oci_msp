#!/usr/bin/env bash

list_domains() {
  local region="${1:-}"
  # Identity Domain 은 IAM 리소스 — region 미지정 시 home region 사용
  local _r=()
  if [[ -n "$region" ]]; then
    _r=(--region "$region")
  else
    local home_region
    home_region=$(get_home_region)
    [[ -n "$home_region" ]] && _r=(--region "$home_region")
  fi

  oci iam domain list ${_r[@]+"${_r[@]}"} \
    --compartment-id "$TENANCY_ID" \
    --all 2>/dev/null \
  | jq -c --arg region "${_r[1]:-}" \
      '.data[] | {id:.id,
                  name:(.["display-name"] // ""),
                  state:(.["lifecycle-state"] // ""),
                  dtype:(.type // ""),
                  home_region:(.["home-region"] // ""),
                  region:$region}' \
  | while read -r row; do
      local id name state dtype home_region region_val
      id=$(printf '%s' "$row"          | jq -r '.id')
      name=$(printf '%s' "$row"        | jq -r '.name')
      state=$(printf '%s' "$row"       | jq -r '.state')
      dtype=$(printf '%s' "$row"       | jq -r '.dtype')
      home_region=$(printf '%s' "$row" | jq -r '.home_region')
      region_val=$(printf '%s' "$row"  | jq -r '.region')
      printf "%s\t%s\t%s\t%s\n" "$name" "$dtype" "$home_region" "$state"
      append_state "domain" \
        "$(jq -c -n \
            --arg region "$region_val" --arg id "$id" \
            --arg name "$name"         --arg state "$state" \
            --arg dtype "$dtype"       --arg home_region "$home_region" \
            '{type:"domain",region:$region,id:$id,name:$name,
              state:$state,dtype:$dtype,home_region:$home_region}')"
    done
}
