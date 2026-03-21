#!/usr/bin/env bash
STATE_FILE="state/state.json"
TMP_FILE="state/state.tmp.json"

init_state() {
  mkdir -p state
  echo "[]" > "$TMP_FILE"
}

append_state() {
  local entry="$1"
  jq ". += [$entry]" "$TMP_FILE" > "${TMP_FILE}.new" && mv "${TMP_FILE}.new" "$TMP_FILE"
}

finalize_state() {
  mv "$TMP_FILE" "$STATE_FILE"
}
