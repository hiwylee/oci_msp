#!/usr/bin/env bash
list_gg() {
  local region="$1"
  oci goldengate deployment list --region "$region" --compartment-id "$TENANCY_ID" --compartment-id-in-subtree true --all \
  | jq -c --arg region "$region" '.data.items[] | {id:.id, name:(.["display-name"] // ""), state:(.["lifecycle-state"] // ""), ip:(.["public-ip-address"] // .["private-ip-address"] // "-"), region:$region}' \
  | while read -r row; do
      local id
      local name
      local state
      local ip
      id=$(echo "$row" | jq -r '.id')
      name=$(echo "$row" | jq -r '.name')
      state=$(echo "$row" | jq -r '.state')
      ip=$(echo "$row" | jq -r '.ip')
      printf "%s\t%s\t%s\n" "$name" "$ip" "$state"
      append_state "$(jq -c -n --arg type "gg" --arg region "$region" --arg id "$id" --arg name "$name" --arg state "$state" '{type:$type,region:$region,id:$id,name:$name,state:$state}')"
    done
}
