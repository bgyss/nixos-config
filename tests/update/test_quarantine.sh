#!/usr/bin/env bash
# Unit-tests scripts/quarantine.sh against a scratch ledger. Never touches the
# real overlays/quarantine.json: QUARANTINE_FILE is redirected to a temp file.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export QUARANTINE_FILE="$TMP/quarantine.json"

# shellcheck source=/dev/null
source "$REPO/scripts/update-state.sh"
# shellcheck source=/dev/null
source "$REPO/scripts/quarantine.sh"

fail() { echo "FAIL: $1"; exit 1; }

# --- init is idempotent and produces valid JSON -----------------------------
quarantine_init
jq empty "$QUARANTINE_FILE" || fail "init did not produce valid JSON"
quarantine_init
[[ "$(jq '.entries | length' "$QUARANTINE_FILE")" == "0" ]] || fail "init not idempotent"

# --- an unknown package is never blocked -----------------------------------
if quarantine_is_blocked "claude-code" "2.1.221"; then fail "unknown package reported blocked"; fi

# --- next-version-only blocks ONLY the recorded version --------------------
quarantine_record "claude-code" "overlay" "2.1.221" "2.1.220" "package-build" \
  "compile-failure" "next-version-only" "boom"
quarantine_is_blocked "claude-code" "2.1.221" || fail "blocked_version not blocked"
if quarantine_is_blocked "claude-code" "2.1.222"; then fail "newer version wrongly blocked"; fi
[[ "$(quarantine_field claude-code known_good_version)" == "2.1.220" ]] \
  || fail "known_good_version not recorded"
[[ "$(quarantine_field claude-code attempts)" == "1" ]] || fail "attempts != 1"

# --- re-recording the same version increments attempts, does not duplicate --
quarantine_record "claude-code" "overlay" "2.1.221" "2.1.220" "package-build" \
  "compile-failure" "next-version-only" "boom"
[[ "$(jq '.entries | length' "$QUARANTINE_FILE")" == "1" ]] || fail "duplicate entry created"
[[ "$(quarantine_field claude-code attempts)" == "2" ]] || fail "attempts != 2"

# --- attempts >= 3 auto-promotes to frozen, which blocks EVERY version -----
quarantine_record "claude-code" "overlay" "2.1.221" "2.1.220" "package-build" \
  "compile-failure" "next-version-only" "boom"
[[ "$(quarantine_field claude-code retry_policy)" == "frozen" ]] \
  || fail "not auto-promoted to frozen at attempts=3"
quarantine_is_blocked "claude-code" "9.9.9" || fail "frozen did not block a newer version"

# --- retry-after blocks the same version until the window expires ----------
quarantine_record "uv" "overlay" "0.11.33" "0.11.32" "prefetch" \
  "network-error" "retry-after:6" "curl: (6)"
quarantine_is_blocked "uv" "0.11.33" || fail "retry-after did not block inside window"
# Backdate last_attempt past the window; it must become eligible again.
jq '(.entries[] | select(.name=="uv") | .last_attempt) = "2000-01-01T00:00:00Z"' \
  "$QUARANTINE_FILE" > "$TMP/x" && mv "$TMP/x" "$QUARANTINE_FILE"
if quarantine_is_blocked "uv" "0.11.33"; then fail "retry-after did not expire"; fi

# --- clear removes the entry ----------------------------------------------
quarantine_clear "uv"
if quarantine_is_blocked "uv" "0.11.33"; then fail "clear did not remove entry"; fi
[[ -z "$(quarantine_field uv attempts)" ]] || fail "cleared entry still has fields"

# --- escalation dedup -----------------------------------------------------
quarantine_record "yt-dlp" "overlay" "2026.07.19" "2026.07.04" "package-build" \
  "curl_cffi-bound" "next-version-only" "bound"
quarantine_should_escalate "yt-dlp" "curl_cffi-bound" || fail "first escalation refused"
quarantine_set_escalation "yt-dlp" "gave-up" "needs manual review"
if quarantine_should_escalate "yt-dlp" "curl_cffi-bound"; then
  fail "escalated again after gave-up on same fingerprint"
fi
quarantine_should_escalate "yt-dlp" "different-fingerprint" \
  || fail "refused escalation for a NEW fingerprint"
[[ "$(quarantine_field yt-dlp escalation_status)" == "gave-up" ]] \
  || fail "escalation_status not readable"

# --- re-recording must PRESERVE the escalation verdict --------------------
# Regression guard for the groundhog-day brake: upstream ships a newer version,
# the pipeline retries, it fails the same way and re-records. If that upsert
# drops .escalation, the already-refused escalation looks eligible again and
# burns a session every single day.
quarantine_record "yt-dlp" "overlay" "2026.07.26" "2026.07.04" "package-build" \
  "curl_cffi-bound" "next-version-only" "bound again"
[[ "$(quarantine_field yt-dlp escalation_status)" == "gave-up" ]] \
  || fail "re-record wiped the escalation verdict"
if quarantine_should_escalate "yt-dlp" "curl_cffi-bound"; then
  fail "re-record re-enabled escalation for an already-refused fingerprint"
fi
# ...and the ledger must still be intact (not truncated by an empty jq stream).
[[ "$(jq '.entries | length' "$QUARANTINE_FILE")" -ge 1 ]] || fail "ledger truncated by re-record"

# --- recording a BRAND-NEW package must not fail on the missing prior entry
quarantine_record "brand-new-pkg" "overlay" "1.0.0" "0.9.0" "prefetch" \
  "network-error" "retry-after:6" "curl: (6)"
[[ "$(quarantine_field brand-new-pkg blocked_version)" == "1.0.0" ]] \
  || fail "recording a package with no prior entry failed"

# --- sanitize strips store paths and truncates ----------------------------
out="$(printf 'error at /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-foo-1.0/bin/foo\n' | quarantine_sanitize)"
[[ "$out" != *"/nix/store/"* ]] || fail "store path not stripped"
[[ "$out" == *"foo-1.0/bin/foo"* ]] || fail "sanitize destroyed useful content"
long="$(head -c 5000 /dev/zero | tr '\0' 'x' | quarantine_sanitize | wc -c | tr -d ' ')"
[[ "$long" -le 2001 ]] || fail "sanitize did not truncate (got $long chars)"

# --- a CORRUPT ledger warns on stderr; an ABSENT one is silent -----------
printf 'not json at all' > "$QUARANTINE_FILE"
warn_out="$(quarantine_field demo attempts 2>&1 >/dev/null)"
[[ "$warn_out" == *"not valid JSON"* ]] || fail "corrupt ledger did not warn on stderr"
rm -f "$QUARANTINE_FILE"
silent_out="$(quarantine_field demo attempts 2>&1 >/dev/null)"
[[ -z "$silent_out" ]] || fail "absent ledger warned when it should be silent: $silent_out"
quarantine_init

echo "PASS: test_quarantine"
