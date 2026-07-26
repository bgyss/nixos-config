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

# --- prefix versions must NOT pass (exact equality, not substring) --------
# mise/yt-dlp pin date versions where the day width varies, so a substring
# check would treat 2026.7.1 and 2026.7.14 as the same release.
printf '#!/usr/bin/env bash\necho "demo 1.2.34"\n' > "$STUB/prefixdemo"
chmod +x "$STUB/prefixdemo"
if run_health '{"assertions":[{"package":"demo","command":"prefixdemo --version","version_regex":"[0-9]+\\.[0-9]+\\.[0-9]+","timeout":10}],"agents":[]}'; then
  cat "$TMP/out"; fail "observed 1.2.34 wrongly accepted against expected 1.2.3"
fi

# --- closure-resolved binary is used, not the first hit on ambient PATH ---
# Reproduces the real ngrok situation: a Homebrew cask shadows the nix
# binary on PATH. Two stub binaries share the name "shadowed" in different
# dirs — a "wrong" one (simulating the Homebrew cask, put first on PATH) and
# a "right" one (simulating /run/current-system/sw/bin, resolved via
# --bin-dirs). The check must run the closure one, not the PATH one.
SWDIR="$TMP/sw-bin"; mkdir -p "$SWDIR"
printf '#!/usr/bin/env bash\necho "shadowed 1.2.3"\n' > "$SWDIR/shadowed"
chmod +x "$SWDIR/shadowed"
printf '#!/usr/bin/env bash\necho "shadowed 9.9.9"\n' > "$STUB/shadowed"
chmod +x "$STUB/shadowed"
cat > "$TMP/manifest-shadowed.json" <<'EOF'
{ "packages": [ { "name": "demo", "current_version": "1.2.3" } ], "skip": [] }
EOF
printf '%s' '{"assertions":[{"package":"demo","command":"shadowed --version","version_regex":"([0-9]+\\.[0-9]+\\.[0-9]+)","timeout":10}],"agents":[]}' \
  > "$TMP/assert-shadowed.json"
PATH="$STUB:$PATH" bash "$REPO/scripts/post-activate-health.sh" \
  --manifest "$TMP/manifest-shadowed.json" --assertions "$TMP/assert-shadowed.json" \
  --bin-dirs "$SWDIR" >"$TMP/out-shadowed" 2>&1
rc=$?
[[ $rc -eq 0 ]] || { cat "$TMP/out-shadowed"; fail "closure-resolved binary was not preferred over ambient PATH"; }
grep -q "OK: demo (1.2.3)" "$TMP/out-shadowed" \
  || { cat "$TMP/out-shadowed"; fail "did not observe the closure binary's version"; }

# A binary present on ambient PATH only (not in --bin-dirs) still falls back
# to PATH resolution — the documented fallback, not a hard failure.
printf '%s' '{"assertions":[{"package":"demo","command":"prefixdemo --version","version_regex":"[0-9]+\\.[0-9]+\\.[0-9]+","timeout":10}],"agents":[]}' \
  > "$TMP/assert-fallback.json"
if PATH="$STUB:$PATH" bash "$REPO/scripts/post-activate-health.sh" \
  --manifest "$TMP/manifest.json" --assertions "$TMP/assert-fallback.json" \
  --bin-dirs "$SWDIR" >"$TMP/out-fallback" 2>&1; then
  cat "$TMP/out-fallback"; fail "fallback case unexpectedly passed (1.2.34 != 1.2.3)"
fi
grep -q "1.2.34" "$TMP/out-fallback" \
  || { cat "$TMP/out-fallback"; fail "PATH fallback did not resolve prefixdemo at all"; }

# --- every pinned package in the REAL manifest has an assertion or a skip
missing=""
while read -r p; do
  [[ -z "$p" ]] && continue
  has="$(jq -r --arg n "$p" '[.assertions[] | select(.package==$n)] | length' "$REPO/overlays/health-checks.json")"
  [[ "$has" == "0" ]] && missing="$missing $p"
done < <(jq -r '.packages[].name' "$REPO/overlays/updates.json")
[[ -z "$missing" ]] || fail "packages with no health assertion:$missing"

echo "PASS: test_health_check"
