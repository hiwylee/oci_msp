#!/usr/bin/env bash

# 구독된 region 목록 반환 (home region으로 IAM 호출)
discover_regions() {
  local home_region
  home_region=$(get_home_region)
  local _r=()
  [[ -n "$home_region" ]] && _r=(--region "$home_region")
  oci iam region-subscription list ${_r[@]+"${_r[@]}"} \
    --tenancy-id "$TENANCY_ID" \
    | jq -r '.data[] | select(.status == "READY") | .["region-name"]'
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

retry() {
  local n=0
  local max=$MAX_RETRIES
  local delay=$RETRY_DELAY

  until "$@"; do
    n=$((n+1))
    if [[ $n -ge $max ]]; then
      log "Command failed after $n attempts: $*"
      return 1
    fi
    log "Retrying ($n/$max)..."
    sleep $delay
  done
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required env: $name" >&2
    exit 1
  fi
}

print_section() {
  local title="$1"
  local rows="${2:-}"
  local header="${3:-NAME\tIP\tSTATE}"

  if [[ -z "${rows//[$'\t'\n' ']/}" ]]; then
    return 0
  fi

  echo
  echo "=== $title ==="
  {
    printf '%b\n' "$header"
    printf "%s\n" "$rows"
  } | column -t -s $'\t'
}
