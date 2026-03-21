#!/usr/bin/env bash
list_compute() {
  local region="$1"
  oci compute instance list --region "$region" --compartment-id "$TENANCY_ID" --compartment-id-in-subtree true --all \
  | jq -c --arg region "$region" '.data[] | {id:.id, name:(.["display-name"] // ""), state:(.["lifecycle-state"] // ""), region:$region}' \
  | while read -r row; do
      local id
      local name
      local state
      local ip
      id=$(echo "$row" | jq -r '.id')
      name=$(echo "$row" | jq -r '.name')
      state=$(echo "$row" | jq -r '.state')
      ip=$(oci compute instance list-vnics --region "$region" --instance-id "$id" 2>/dev/null | jq -r '.data[0]["private-ip"] // "-"')
      printf "%s\t%s\t%s\n" "$name" "$ip" "$state"
      append_state "$(jq -c -n --arg type "vm" --arg region "$region" --arg id "$id" --arg name "$name" --arg state "$state" '{type:$type,region:$region,id:$id,name:$name,state:$state}')"
    done
}
