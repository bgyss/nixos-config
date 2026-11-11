#!/usr/bin/env bash
# Sourced helper: authenticated GitHub API access for the update pipeline.
#
# Unauthenticated api.github.com allows 60 requests/hour per IP, and one daily
# run makes ~35 (one release/commit probe per package plus per-input probes). A
# rate-limited probe is a curl failure, which the callers deliberately treat as
# "no information" — so with a shared IP or a manual re-run the pipeline
# silently saw nothing outdated. A token raises the limit to 5000/hour.
#
# Token source, first hit wins: $GITHUB_TOKEN, $GH_TOKEN, then `gh auth token`
# (read-only lookup of the gh CLI's stored login). It is attached ONLY to
# https://api.github.com/ requests, never to downloads or other hosts, and is
# never printed or logged. No token -> unauthenticated, exactly as before.
#
# Usage: github_api <path-or-url> [extra curl args]   (prints the body)
#        e.g. github_api repos/tmux/tmux/releases/latest

_GH_TOKEN_RESOLVED=""
_gh_token() {
  if [[ -z "$_GH_TOKEN_RESOLVED" ]]; then
    local t="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    if [[ -z "$t" ]] && command -v gh >/dev/null 2>&1; then
      t="$(timeout 10 gh auth token 2>/dev/null || true)"
    fi
    # "none" sentinel so a missing token is looked up once per process, not per call.
    _GH_TOKEN_RESOLVED="${t:-none}"
  fi
  [[ "$_GH_TOKEN_RESOLVED" == "none" ]] && return 1
  printf '%s' "$_GH_TOKEN_RESOLVED"
}

github_api() {
  local target="$1"; shift
  local url="$target"
  [[ "$url" == http* ]] || url="https://api.github.com/${target#/}"
  local -a args=(-sf --max-time 15 -H 'Accept: application/vnd.github+json')
  if [[ "$url" == https://api.github.com/* ]]; then
    local t
    if t="$(_gh_token)"; then args+=(-H "Authorization: Bearer $t"); fi
  fi
  curl "${args[@]}" "$@" "$url"
}
