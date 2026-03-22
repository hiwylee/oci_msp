#!/usr/bin/env bash

# STATE_DIR / STATE_FILE 은 main.sh 에서 setup_state_dir() 호출 후 결정됨
STATE_DIR=""
STATE_FILE=""

setup_state_dir() {
  local profile="${OCI_CLI_PROFILE:-DEFAULT}"
  STATE_DIR="state/$profile"
  STATE_FILE="$STATE_DIR/state.json"
}

# 리소스 유형별 상태 파일 초기화 (빈 배열)
init_type_state() {
  local type="$1"
  mkdir -p "$STATE_DIR"
  echo "[]" > "$STATE_DIR/${type}.tmp.json"
}

# 항목 추가: append_state TYPE JSON_ENTRY
append_state() {
  local type="$1"
  local entry="$2"
  local tmp="$STATE_DIR/${type}.tmp.json"
  jq --argjson e "$entry" '. += [$e]' "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"
}

# tmp → 최종 파일로 확정
finalize_type_state() {
  local type="$1"
  mv "$STATE_DIR/${type}.tmp.json" "$STATE_DIR/${type}.json"
}

# vm/db/adb/gg.json 을 합쳐 state.json 생성 (action.sh 용)
build_combined_state() {
  local files=()
  for t in vm db adb gg domain; do
    [[ -f "$STATE_DIR/${t}.json" ]] && files+=("$STATE_DIR/${t}.json")
  done
  if [[ ${#files[@]} -gt 0 ]]; then
    jq -s 'add // []' "${files[@]}" > "$STATE_FILE"
  else
    echo "[]" > "$STATE_FILE"
  fi
}

# 최초 실행 시 profile 부트스트랩:
#   home region → 구독 regions → compartments → meta.json 저장
# 이미 meta.json 있으면 skip
init_profile() {
  local profile="${OCI_CLI_PROFILE:-DEFAULT}"
  local state_dir="state/$profile"

  # meta.json 이 있고, home_region 이 이미 채워져 있으면 skip
  if [[ -f "$state_dir/meta.json" ]]; then
    local saved_home
    saved_home=$(jq -r '.home_region // ""' "$state_dir/meta.json")
    # HOME_REGION(.env) 설정 시: meta 가 비어있으면 재초기화, 아니면 skip
    if [[ -n "$saved_home" ]]; then
      return 0
    fi
    [[ -z "${HOME_REGION:-}" ]] && return 0
    log "Re-initializing profile [$profile] with HOME_REGION=$HOME_REGION ..."
  fi

  mkdir -p "$state_dir"
  log "Initializing profile [$profile]..."

  # IAM 호출용 region: HOME_REGION(.env) 우선, 없으면 profile 기본
  local _iam_r=()
  [[ -n "${HOME_REGION:-}" ]] && _iam_r=(--region "$HOME_REGION")

  # 1. 구독 regions 조회 (is-home-region 포함)
  local regions_raw
  regions_raw=$(oci iam region-subscription list ${_iam_r[@]+"${_iam_r[@]}"} \
    --tenancy-id "$TENANCY_ID" 2>/dev/null || echo '{"data":[]}')

  # 2. home region name 결정
  local home_region
  home_region=$(printf '%s' "$regions_raw" \
    | jq -r '.data[] | select(.["is-home-region"] == true) | .["region-name"]' 2>/dev/null || echo "")
  # HOME_REGION(.env) 설정 값이 있으면 그것을 우선
  [[ -z "$home_region" && -n "${HOME_REGION:-}" ]] && home_region="$HOME_REGION"

  # 3. meta.json 저장
  jq -n \
    --arg profile    "$profile" \
    --arg tenancy_id "$TENANCY_ID" \
    --arg home_region "$home_region" \
    --arg init_time  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{profile:$profile, tenancy_id:$tenancy_id,
      home_region:$home_region, init_time:$init_time}' \
    > "$state_dir/meta.json"

  # 4. regions.json 저장
  printf '%s' "$regions_raw" \
    | jq '[.data[] | select(.status == "READY")
           | {name:.["region-name"], home:.["is-home-region"]}]' \
    > "$state_dir/regions.json"
  local region_count
  region_count=$(jq 'length' "$state_dir/regions.json")
  log "  Regions: $region_count subscribed, home: ${home_region:-unknown}"

  # 5. compartments.json 저장 (home region으로 IAM 호출)
  local _hr=()
  [[ -n "$home_region" ]] && _hr=(--region "$home_region")
  oci iam compartment list ${_hr[@]+"${_hr[@]}"} \
    --compartment-id "$TENANCY_ID" \
    --compartment-id-in-subtree true \
    --all 2>/dev/null \
  | jq '[.data[] | select(.["lifecycle-state"] == "ACTIVE")
         | {name:.name, id:.id}]' \
  > "$state_dir/compartments.json" \
  || echo "[]" > "$state_dir/compartments.json"

  local comp_count
  comp_count=$(jq 'length' "$state_dir/compartments.json")
  log "  Compartments: $comp_count found"
  log "Profile [$profile] initialized → $state_dir/"
}

# meta.json 에서 home region 반환
get_home_region() {
  local meta="$STATE_DIR/meta.json"
  if [[ -n "${HOME_REGION:-}" ]]; then
    echo "$HOME_REGION"
  elif [[ -f "$meta" ]]; then
    jq -r '.home_region // ""' "$meta"
  else
    echo ""
  fi
}
