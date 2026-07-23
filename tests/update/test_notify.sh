#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
STUB="$(mktemp -d)"; log="$(mktemp)"
cat > "$STUB/osascript" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$log"
EOF
chmod +x "$STUB/osascript"
source "$REPO/scripts/update-notify.sh"
PATH="$STUB:$PATH" notify "nixos-config" "revision abc123 ready"
grep -q "abc123" "$log" || { echo "FAIL: osascript not called with message"; exit 1; }
echo "PASS: test_notify"
