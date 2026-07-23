#!/usr/bin/env bash
# Check for available updates to pinned overlays.
# Reads overlays/updates.json, queries upstream APIs, prints current vs. latest.
# Exit code 1 if any package is OUTDATED; 0 if all up to date.
set -euo pipefail

JSON=0
[[ "${1:-}" == "--json" ]] && JSON=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_ROOT/overlays/updates.json"

OUTDATED=0
UP_TO_DATE=0
ERRORS=0

# ── Upstream check helpers ────────────────────────────────────────────────────

github_latest() {
  local repo="$1" tag_prefix="${2:-}"
  local tag
  tag=$(curl -sf --max-time 15 \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
    | jq -r '.tag_name // empty') || { printf 'ERROR'; return; }
  [[ -z "$tag" ]] && { printf 'ERROR'; return; }
  printf '%s' "${tag#"$tag_prefix"}"
  # strip leading 'v' if no explicit prefix was given
  [[ -z "$tag_prefix" ]] && printf '%s' "${tag#v}" || printf '%s' "${tag#"$tag_prefix"}"
}

go_dev_latest() {
  curl -sf --max-time 15 "https://go.dev/dl/?mode=json" 2>/dev/null \
    | jq -r 'map(select(.stable)) | .[0].version | ltrimstr("go")' \
    || printf 'ERROR'
}

pypi_latest() {
  local package="$1"
  curl -sf --max-time 15 "https://pypi.org/pypi/${package}/json" 2>/dev/null \
    | jq -r '.info.version // empty' \
    || printf 'ERROR'
}

npm_latest() {
  local package="$1"
  curl -sf --max-time 15 "https://registry.npmjs.org/${package}/latest" 2>/dev/null \
    | jq -r '.version // empty' \
    || printf 'ERROR'
}

github_latest_commit() {
  local repo="$1" branch="${2:-master}"
  curl -sf --max-time 15 \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/commits/${branch}" 2>/dev/null \
    | jq -r '.sha[:12] // empty' \
    || printf 'ERROR'
}

# ngrok publishes no versioned releases, but the "stable" darwin-arm64 CDN URL
# always serves the latest build. Download it and ask the binary its own version.
ngrok_stable_latest() {
  local tmpdir zip
  tmpdir=$(mktemp -d) || { printf 'ERROR'; return; }
  zip="$tmpdir/ngrok.zip"
  if ! curl -sfL --max-time 30 \
      -o "$zip" \
      "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip" 2>/dev/null; then
    rm -rf "$tmpdir"; printf 'ERROR'; return
  fi
  if ! unzip -oq "$zip" -d "$tmpdir" 2>/dev/null; then
    rm -rf "$tmpdir"; printf 'ERROR'; return
  fi
  chmod +x "$tmpdir/ngrok" 2>/dev/null
  local ver
  ver=$("$tmpdir/ngrok" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  rm -rf "$tmpdir"
  [[ -z "$ver" ]] && { printf 'ERROR'; return; }
  printf '%s' "$ver"
}

# ── Output ────────────────────────────────────────────────────────────────────

if [[ $JSON -eq 1 ]]; then
  rows=()
else
  printf '%-22s %-18s %-18s %s\n' "PACKAGE" "CURRENT" "LATEST" "STATUS"
  printf '%s\n' "$(printf '%.0s─' {1..72})"
fi

while IFS= read -r pkg; do
  name=$(    jq -r '.name'           <<<"$pkg")
  current=$( jq -r '.current_version' <<<"$pkg")
  method=$(  jq -r '.check.method'   <<<"$pkg")

  case "$method" in
    github-release)
      repo=$(   jq -r '.check.repo'             <<<"$pkg")
      prefix=$( jq -r '.check.tag_prefix // ""' <<<"$pkg")
      # Strip the prefix, then also strip a leading 'v' if no explicit prefix
      raw=$(curl -sf --max-time 15 \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | jq -r '.tag_name // "ERROR"') || raw="ERROR"
      if [[ "$raw" == "ERROR" || -z "$raw" ]]; then
        latest="ERROR"
      elif [[ -n "$prefix" ]]; then
        latest="${raw#"$prefix"}"
      else
        latest="${raw#v}"
      fi
      ;;
    go-dev)
      latest=$(go_dev_latest)
      ;;
    pypi)
      package=$(jq -r '.check.package' <<<"$pkg")
      latest=$(pypi_latest "$package")
      ;;
    npm)
      package=$(jq -r '.check.package' <<<"$pkg")
      latest=$(npm_latest "$package")
      ;;
    github-commits)
      repo=$(       jq -r '.check.repo'          <<<"$pkg")
      branch=$(     jq -r '.check.branch // "master"' <<<"$pkg")
      current_rev=$(jq -r '.current_rev // ""'   <<<"$pkg")
      latest_sha=$(github_latest_commit "$repo" "$branch")
      if [[ "$latest_sha" == "ERROR" || -z "$latest_sha" ]]; then
        latest="ERROR"
      elif [[ -n "$current_rev" && "$latest_sha" == "${current_rev:0:12}" ]]; then
        latest="$current"
      else
        latest="$latest_sha (commit)"
      fi
      ;;
    ngrok-binary)
      latest=$(ngrok_stable_latest)
      ;;
    manual)
      hint=$(jq -r '.check.hint // ""' <<<"$pkg")
      latest="(manual check)"
      ;;
    *)
      latest="(unknown method)"
      ;;
  esac

  if [[ "$latest" == "ERROR" ]]; then
    status="ERROR"
    ERRORS=$((ERRORS + 1))
  elif [[ "$latest" == *"(manual"* || "$latest" == *"(unknown"* ]]; then
    status="MANUAL"
  elif [[ "$latest" == "$current" ]]; then
    status="✓ up to date"
    UP_TO_DATE=$((UP_TO_DATE + 1))
  else
    status="✗ OUTDATED"
    OUTDATED=$((OUTDATED + 1))
  fi

  case "$status" in
    *OUTDATED*) sc=OUTDATED; od=true ;;
    *"up to date"*) sc=OK; od=false ;;
    ERROR) sc=ERROR; od=false ;;
    *) sc=MANUAL; od=false ;;
  esac
  if [[ $JSON -eq 1 ]]; then
    rows+=("$(jq -nc --arg n "$name" --arg c "$current" --arg l "$latest" \
      --arg s "$sc" --argjson o "$od" \
      '{name:$n,current:$c,latest:($l|sub(" \\(commit\\)$";"")),outdated:$o,status:$s}')")
  else
    printf '%-22s %-18s %-18s %s\n' "$name" "$current" "$latest" "$status"
  fi

done < <(jq -c '.packages[]' "$MANIFEST")

if [[ $JSON -eq 1 ]]; then
  printf '%s\n' "$(printf '%s\n' "${rows[@]}" | jq -sc '.')"
else
  echo ""
  printf 'Summary: %d up to date  |  %d outdated  |  %d errors\n' \
    "$UP_TO_DATE" "$OUTDATED" "$ERRORS"
fi
[[ $OUTDATED -gt 0 ]] && exit 1 || exit 0
