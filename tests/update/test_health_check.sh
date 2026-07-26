#!/usr/bin/env bash
# Drives scripts/post-activate-health.sh against synthetic assertion files and
# stub binaries, so no real system state is inspected.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
STUB="$TMP/bin"; mkdir -p "$STUB"
fail() { echo "FAIL: $1"; exit 1; }

cat > "$TMP/manifest.json" <<'EOF'
{ "packages": [ { "name": "demo", "current_version": "1.2.3" } ], "skip": [] }
EOF

# demo prints a matching version; brokendemo prints a stale one; hangdemo hangs.
printf '#!/usr/bin/env bash\necho "demo 1.2.3"\n' > "$STUB/demo"
printf '#!/usr/bin/env bash\necho "demo 0.9.0"\n' > "$STUB/brokendemo"
printf '#!/usr/bin/env bash\nsleep 30\n' > "$STUB/hangdemo"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/launchctl"
chmod +x "$STUB"/*

run_health() { # <assertions-json>
  printf '%s' "$1" > "$TMP/assert.json"
  PATH="$STUB:$PATH" bash "$REPO/scripts/post-activate-health.sh" \
    --manifest "$TMP/manifest.json" --assertions "$TMP/assert.json" >"$TMP/out" 2>&1
}

# --- matching version passes ---------------------------------------------
run_health '{"assertions":[{"package":"demo","command":"demo --version","version_regex":"([0-9]+\\.[0-9]+\\.[0-9]+)","timeout":10}],"agents":[]}' \
  || { cat "$TMP/out"; fail "matching version did not pass"; }
grep -q "OK: demo" "$TMP/out" || fail "no OK line for demo"

# --- WRONG version fails (the whole point) -------------------------------
if run_health '{"assertions":[{"package":"demo","command":"brokendemo --version","version_regex":"([0-9]+\\.[0-9]+\\.[0-9]+)","timeout":10}],"agents":[]}'; then
  cat "$TMP/out"; fail "stale version was accepted"
fi
grep -q "FAIL: demo" "$TMP/out" || fail "no FAIL line for stale version"
grep -q "0.9.0" "$TMP/out" || fail "failure message omits the observed version"

# --- a missing binary fails ---------------------------------------------
if run_health '{"assertions":[{"package":"demo","command":"nosuchbinary --version","version_regex":"([0-9]+)","timeout":10}],"agents":[]}'; then
  fail "missing binary was accepted"
fi

# --- a hanging command is killed by the timeout and fails ---------------
start=$(date +%s)
if run_health '{"assertions":[{"package":"demo","command":"hangdemo","version_regex":"([0-9]+)","timeout":2}],"agents":[]}'; then
  fail "hanging command was accepted"
fi
elapsed=$(( $(date +%s) - start ))
[[ $elapsed -lt 15 ]] || fail "timeout not enforced (took ${elapsed}s)"

# --- a skip entry is reported but does not fail -------------------------
run_health '{"assertions":[{"package":"demo","skip":"python library, no CLI"}],"agents":[]}' \
  || { cat "$TMP/out"; fail "skip entry caused a failure"; }
grep -qi "skip" "$TMP/out" || fail "skip not reported"

# --- an unloaded launchd agent fails -----------------------------------
printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/launchctl"; chmod +x "$STUB/launchctl"
if run_health '{"assertions":[],"agents":["com.example.missing"]}'; then
  fail "unloaded agent was accepted"
fi
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/launchctl"; chmod +x "$STUB/launchctl"
run_health '{"assertions":[],"agents":["com.example.present"]}' \
  || fail "loaded agent was rejected"

# --- every pinned package in the REAL manifest has an assertion or a skip
missing=""
while read -r p; do
  [[ -z "$p" ]] && continue
  has="$(jq -r --arg n "$p" '[.assertions[] | select(.package==$n)] | length' "$REPO/overlays/health-checks.json")"
  [[ "$has" == "0" ]] && missing="$missing $p"
done < <(jq -r '.packages[].name' "$REPO/overlays/updates.json")
[[ -z "$missing" ]] || fail "packages with no health assertion:$missing"

echo "PASS: test_health_check"
