#!/usr/bin/env bash
# Post-activation smoke check (spec §3). Exit 0 = keep this generation,
# exit 1 = the caller should roll back.
#
# The load-bearing assertion is the VERSION COMPARISON, not exit status: an
# overlay that silently pins the wrong artifact still produces a binary that
# runs fine, and only a version match catches it.
#
# Deliberately does NOT re-run `nix flake check` — that already gated the build.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO/overlays/updates.json"
ASSERTIONS="$REPO/overlays/health-checks.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)   MANIFEST="$2"; shift 2 ;;
    --assertions) ASSERTIONS="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

failures=0

# ── Package version assertions ─────────────────────────────────────────────
# NOTE: deliberately NOT using `jq -r '... | @tsv'` here — @tsv escapes
# backslashes in its output, which corrupts every version_regex containing
# `\.` (i.e. all of them). Instead each assertion is emitted as one compact
# JSON object per line and its fields are re-extracted with jq, so escaping
# round-trips correctly.
while IFS= read -r row; do
  [[ -z "$row" ]] && continue
  pkg="$(jq -r '.package // ""' <<<"$row")"
  cmd="$(jq -r '.command // ""' <<<"$row")"
  regex="$(jq -r '.version_regex // ""' <<<"$row")"
  tmo="$(jq -r '.timeout // 20' <<<"$row")"
  skip="$(jq -r '.skip // ""' <<<"$row")"
  [[ -z "$pkg" ]] && continue

  if [[ -n "$skip" && "$skip" != "null" ]]; then
    echo "SKIP: $pkg ($skip)"
    continue
  fi

  expected="$(jq -r --arg n "$pkg" '.packages[] | select(.name==$n) | .current_version' "$MANIFEST")"
  # `timeout` comes from coreutils, which is in this config's systemPackages.
  # Without it a wedged binary would hang the whole daily run.
  out="$(timeout "${tmo:-20}" bash -c "$cmd" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "FAIL: $pkg — '$cmd' exited $rc: $(printf '%s' "$out" | head -1)" >&2
    failures=$((failures + 1))
    continue
  fi

  observed="$(printf '%s' "$out" | grep -oE "$regex" | head -1)"
  if [[ -z "$observed" ]]; then
    echo "FAIL: $pkg — version_regex matched nothing in: $(printf '%s' "$out" | head -1)" >&2
    failures=$((failures + 1))
    continue
  fi

  # A loose regex (c4/hey-cli, whose current_version is a 0-unstable-<date>
  # string no binary reports) can only prove the binary runs. Treat a
  # non-version-shaped expectation as "ran successfully is enough".
  if [[ "$expected" == 0-unstable-* ]]; then
    echo "OK: $pkg (runs; version not self-reported)"
    continue
  fi

  # EXACT equality, deliberately not a substring test. Substring matching
  # false-passes on any prefix relationship, and this manifest has live cases:
  # mise and yt-dlp pin date-shaped versions where the day component varies in
  # width, so expected 2026.7.1 would "match" observed 2026.7.14 — two
  # different releases. Ditto tmux 3.7 vs 3.7b. This check is the sole gate
  # deciding whether to roll back an activated system; it cannot be loose.
  if [[ "$observed" != "$expected" ]]; then
    echo "FAIL: $pkg — expected version '$expected', binary reports '$observed'" >&2
    failures=$((failures + 1))
    continue
  fi

  echo "OK: $pkg ($observed)"
done < <(jq -c '.assertions[]' "$ASSERTIONS")

# ── launchd agents/daemons ────────────────────────────────────────────────
# `launchctl list <label>` exits non-zero when the label is not loaded, which
# is exactly the "activation unloaded my agent and never brought it back" case.
while read -r label; do
  [[ -z "$label" ]] && continue
  if launchctl list "$label" >/dev/null 2>&1; then
    echo "OK: launchd $label loaded"
  else
    echo "FAIL: launchd $label not loaded" >&2
    failures=$((failures + 1))
  fi
done < <(jq -r '.agents[]?' "$ASSERTIONS")

if [[ $failures -gt 0 ]]; then
  echo "FAILED: $failures health assertion(s)" >&2
  exit 1
fi
echo "health: all assertions passed"
