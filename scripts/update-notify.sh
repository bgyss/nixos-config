#!/usr/bin/env bash
# Sourced. notify <title> <message> -> macOS notification (no-op elsewhere).
notify() {
  local title="$1" message="$2"
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${message//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1 || true
  else
    echo "[notify] $title: $message"
  fi
}
