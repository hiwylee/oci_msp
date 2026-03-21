#!/usr/bin/env bash

# 구독된 region 목록을 OCI API로 동적 획득
# TENANCY_ID 환경변수 필요
discover_regions() {
  oci iam region-subscription list \
    --tenancy-id "$TENANCY_ID" \
    | jq -r '.data[] | select(.status == "READY") | .region-name'
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

  if [[ -z "${rows//[$'\t'\n' ']/}" ]]; then
    return 0
  fi

  echo
  echo "=== $title ==="
  {
    printf "NAME\tIP\tSTATE\n"
    printf "%s\n" "$rows"
  } | column -t -s $'\t'
}
