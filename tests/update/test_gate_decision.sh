#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
source "$REPO/scripts/update-probe.sh"
gate_should_build "" ""        && { echo "FAIL: clean->build"; exit 1; }
gate_should_build "claude-code" "" || { echo "FAIL: overlay->no build"; exit 1; }
gate_should_build "" "codex"       || { echo "FAIL: input->no build"; exit 1; }
gate_should_build "a" "b"          || { echo "FAIL: both->no build"; exit 1; }
echo "PASS: test_gate_decision"
