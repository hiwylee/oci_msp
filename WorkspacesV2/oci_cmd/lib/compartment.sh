#!/usr/bin/env bash

# compartments 조회 후 화면 출력용 TSV 반환
# state/<PROFILE>/compartments.json 도 갱신
list_compartments() {
  local tenancy_id="${1:-$TENANCY_ID}"
  local home_region
  home_region=$(get_home_region)
  local _r=()
  [[ -n "$home_region" ]] && _r=(--region "$home_region")

  local result
  result=$(oci iam compartment list ${_r[@]+"${_r[@]}"} \
    --compartment-id "$tenancy_id" \
    --compartment-id-in-subtree true \
    --all \
  | jq '[.data[] | select(.["lifecycle-state"] == "ACTIVE")
         | {name:.name, id:.id}]')

  # STATE_DIR 에 저장
  mkdir -p "$STATE_DIR"
  printf '%s' "$result" > "$STATE_DIR/compartments.json"

  # TSV 출력 (main.sh 에서 column 처리)
  printf '%s' "$result" | jq -r '.[] | [.name, .id, "ACTIVE"] | @tsv'
}
