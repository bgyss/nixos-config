#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
STUB="$(mktemp -d)"

# Fake curl: any api.github.com/.../releases/latest -> a tag; else empty.
cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in
  *anthropics/claude-code/releases/latest) echo '{"tag_name":"v99.0.0"}'; exit 0;;
  *releases/latest) echo ''; exit 1;;   # simulate upstream error
esac; done
echo ''; exit 0
EOF
chmod +x "$STUB/curl"

rc=0
out="$(PATH="$STUB:$PATH" bash "$REPO/scripts/check-overlay-versions.sh" --json)" || rc=$?

# Must be valid JSON array
echo "$out" | jq -e 'type == "array"' >/dev/null || { echo "FAIL: not array"; exit 1; }
# claude-code must be present and outdated (current != v99)
echo "$out" | jq -e '.[] | select(.name=="claude-code") | .outdated == true' >/dev/null \
  || { echo "FAIL: claude-code not outdated"; exit 1; }
# An ERROR item must never be outdated
echo "$out" | jq -e 'all(.[]; (.status=="ERROR") as $e | ($e and .outdated) | not)' >/dev/null \
  || { echo "FAIL: errored item marked outdated"; exit 1; }
# Exit code must be non-zero since claude-code is outdated
[[ $rc -ne 0 ]] || { echo "FAIL: expected non-zero exit code (outdated package present)"; exit 1; }

echo "PASS: test_overlay_json"
