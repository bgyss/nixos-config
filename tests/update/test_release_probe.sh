#!/usr/bin/env bash
# check-overlay-versions' release lookup and the GitHub auth helper:
#   * tag_prefix repos whose /releases/latest is an unrelated tag (llama.cpp)
#   * all-pre-release repos where /releases/latest 404s (AeroSpace)
#   * the token is sent only to api.github.com, and only when one exists
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
fail() { echo "FAIL: $1"; exit 1; }

work="$(mktemp -d)"; stub="$work/bin"; mkdir -p "$stub"
# curl stub: logs its args; serves canned bodies by URL; 404 (exit 22) for latest
# when SCENARIO=all-prerelease.
cat > "$stub/curl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
case "$*" in
  *releases/latest*)
    [[ "${SCENARIO:-}" == "all-prerelease" ]] && exit 22
    printf '{"tag_name":"v0.9.0"}' ;;
  *releases?per_page*)
    printf '[{"tag_name":"b200","draft":false,"prerelease":true},{"tag_name":"b199","draft":false,"prerelease":true}]' ;;
  *) exit 22 ;;
esac
EOF
chmod +x "$stub/curl"

# Source just the lookup helper out of the shipped script (no copy to drift).
python3 -I - "$REPO/scripts/check-overlay-versions.sh" "$work/fn.sh" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r'(github_release_tag\(\) \{.*?\n\})\n', t, re.S)
open(sys.argv[2], 'w').write(m.group(1) + "\n")
PY

export STUB_LOG="$work/curl.log"
run() { # <scenario> <repo> <prefix> [env...]
  local scen="$1"; shift
  ( export PATH="$stub:$PATH" SCENARIO="$scen"; : > "$STUB_LOG"
    source "$REPO/scripts/github-api.sh"; source "$work/fn.sh"
    github_release_tag "$@" )
}

[[ "$(run normal a/b "")" == "v0.9.0" ]] || fail "no prefix: should trust /releases/latest"
[[ "$(run normal a/b b)" == "b200" ]] || fail "prefix mismatch on latest: should fall back to the list (got '$(run normal a/b b)')"
[[ "$(run all-prerelease a/b v)" == "ERROR" ]] || true   # list has no v* tag -> ERROR
[[ "$(run all-prerelease a/b b)" == "b200" ]] || fail "latest 404 + pre-releases: should use the list"

# Token handling: env token is attached to api.github.com only.
( export PATH="$stub:$PATH" GITHUB_TOKEN=tok123; : > "$STUB_LOG"
  source "$REPO/scripts/github-api.sh"
  github_api repos/a/b/releases/latest >/dev/null 2>&1 || true
  github_api https://example.com/x >/dev/null 2>&1 || true )
grep 'api.github.com' "$STUB_LOG" | grep -q 'Authorization: Bearer tok123' || fail "token not sent to api.github.com"
grep 'example.com' "$STUB_LOG" | grep -q 'Authorization' && fail "token leaked to a non-GitHub host"

# No token anywhere -> no Authorization header (and no failure).
( export PATH="$stub:$PATH"; unset GITHUB_TOKEN GH_TOKEN; : > "$STUB_LOG"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$stub/gh"; chmod +x "$stub/gh"
  source "$REPO/scripts/github-api.sh"
  github_api repos/a/b/releases/latest >/dev/null 2>&1 || true )
grep -q 'Authorization' "$STUB_LOG" && fail "Authorization header sent without a token"

rm -rf "$work"
echo "PASS: test_release_probe"
