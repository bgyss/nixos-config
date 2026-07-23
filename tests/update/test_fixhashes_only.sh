#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
STUB="$(mktemp -d)"
trap "rm -rf '$STUB'" EXIT

# Stub nix-prefetch-url to return a stable fake hash.
cat > "$STUB/nix-prefetch-url" <<'STUBEOF'
#!/usr/bin/env bash
echo "0000000000000000000000000000000000000000000000000000"
STUBEOF
chmod +x "$STUB/nix-prefetch-url"

# Stub nix commands: return fast without real network calls.
cat > "$STUB/nix" <<'STUBEOF'
#!/usr/bin/env bash
case "$1" in
  hash)
    # nix hash convert: return deterministic SRI that matches stub nix-prefetch-url
    echo "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    exit 0
    ;;
  registry)
    # nix registry list: return empty (no flake registry entries)
    exit 0
    ;;
  *)
    # For any other nix subcommands, call the real nix
    exec /usr/bin/env nix "$@"
    ;;
esac
STUBEOF
chmod +x "$STUB/nix"

# Stub python3 to return fake URL/hash pairs that match the stub nix hash output.
# This ensures that sri_for_url will return the expected SRI, and the comparison will succeed.
# No sed -i will run because actual_hash == current_hash.
cat > "$STUB/python3" <<'STUBEOF'
#!/usr/bin/env bash
# extract_pairs reads the overlay file and prints "url\thash" pairs
# We return dummy URLs with the stub SRI as the hash
# This ensures check_overlay prints the header and returns "ok" without modifying files
echo "https://example.com/dummy	sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
STUBEOF
chmod +x "$STUB/python3"

# Test 1: Verify --only claude-code processes only claude-code
out="$(PATH="$STUB:$PATH" bash "$REPO/apps/aarch64-darwin/fix-hashes" --only claude-code 2>&1)" || true
echo "$out" | grep -q -- "--- 41-claude-code.nix ---" || { echo "FAIL: Test 1 - claude-code not processed"; exit 1; }
echo "$out" | grep -q -- "--- 20-ngrok.nix ---" && { echo "FAIL: Test 1 - ngrok processed despite --only"; exit 1; }
echo "PASS: Test 1 - --only claude-code filters correctly"

# Test 2: Verify --only uv processes only uv
out="$(PATH="$STUB:$PATH" bash "$REPO/apps/aarch64-darwin/fix-hashes" --only uv 2>&1)" || true
echo "$out" | grep -q -- "--- 25-uv.nix ---" || { echo "FAIL: Test 2 - uv not processed"; exit 1; }
echo "$out" | grep -q -- "--- 20-ngrok.nix ---" && { echo "FAIL: Test 2 - ngrok processed despite --only"; exit 1; }
echo "PASS: Test 2 - --only uv filters correctly"

# Test 3: Verify no --only processes all overlays (multiple checks)
out="$(PATH="$STUB:$PATH" bash "$REPO/apps/aarch64-darwin/fix-hashes" 2>&1)" || true
echo "$out" | grep -q -- "--- 20-ngrok.nix ---" || { echo "FAIL: Test 3 - ngrok not in all-overlays"; exit 1; }
echo "$out" | grep -q -- "--- 41-claude-code.nix ---" || { echo "FAIL: Test 3 - claude-code not in all-overlays"; exit 1; }
echo "$out" | grep -q -- "--- 25-uv.nix ---" || { echo "FAIL: Test 3 - uv not in all-overlays"; exit 1; }
echo "$out" | grep -q -- "--- 30-mise.nix ---" || { echo "FAIL: Test 3 - mise not in all-overlays"; exit 1; }
echo "PASS: Test 3 - no --only processes all overlays"

# Test 4: Verify --only with non-existent name is skipped
out="$(PATH="$STUB:$PATH" bash "$REPO/apps/aarch64-darwin/fix-hashes" --only nonexistent 2>&1)" || true
echo "$out" | grep -q "skip: 'nonexistent' not in updates.json" || { echo "FAIL: Test 4 - warning not shown for nonexistent name"; exit 1; }
echo "$out" | grep -q -- "---.*---" && { echo "FAIL: Test 4 - some overlay was still processed"; exit 1; }
echo "PASS: Test 4 - nonexistent name is properly skipped with warning"

# Test 5: Verify --only with name in updates.json but not in PINNED_OVERLAYS is skipped with warning
out="$(PATH="$STUB:$PATH" bash "$REPO/apps/aarch64-darwin/fix-hashes" --only beads 2>&1)" || true
echo "$out" | grep -q "skip: 'beads'" || { echo "FAIL: Test 5 - warning not shown for beads (not in PINNED_OVERLAYS)"; exit 1; }
echo "$out" | grep -q -- "---.*---" && { echo "FAIL: Test 5 - some overlay was still processed"; exit 1; }
echo "PASS: Test 5 - overlay not in PINNED_OVERLAYS is properly skipped with warning"

# Test 6: Verify multiple --only names work (comma-separated)
out="$(PATH="$STUB:$PATH" bash "$REPO/apps/aarch64-darwin/fix-hashes" --only claude-code,uv 2>&1)" || true
echo "$out" | grep -q -- "--- 41-claude-code.nix ---" || { echo "FAIL: Test 6 - claude-code not in multi-filter"; exit 1; }
echo "$out" | grep -q -- "--- 25-uv.nix ---" || { echo "FAIL: Test 6 - uv not in multi-filter"; exit 1; }
echo "$out" | grep -q -- "--- 20-ngrok.nix ---" && { echo "FAIL: Test 6 - ngrok processed despite --only"; exit 1; }
echo "PASS: Test 6 - multiple --only names work"

echo ""
echo "PASS: all tests passed - test_fixhashes_only"
