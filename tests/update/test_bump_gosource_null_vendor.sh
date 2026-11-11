#!/usr/bin/env bash
# Regression: a go-source overlay with `vendorHash = null` (no vendored deps —
# c4) must bump mechanically. bump_gosource used to blank the null to "" and
# then scrape a `got:` hash from the build error; with no dependencies the
# build fails with "vendor folder is empty" and prints no `got:` line, so every
# c4 bump was quarantined and handed to a Claude repair session.
#
# Isolation: same shape as test_bump_quarantine.sh — scratch git repo, stubbed
# nix / curl / nix-prefetch-url, no network and no real build.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
REAL_NIX="$(command -v nix)"
fail() { echo "FAIL: $1"; exit 1; }

OLD_REV="1111111111111111111111111111111111111111"
NEW_REV="2222222222222222222222222222222222222222"
OLD_HASH="sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="

d="$(mktemp -d)"; stub="$(mktemp -d)"
mkdir -p "$d/overlays" "$d/scripts" "$d/apps/aarch64-darwin" "$d/logs"
cp "$REPO/scripts/quarantine.sh" "$REPO/scripts/update-state.sh" \
   "$REPO/scripts/classify-failure.sh" "$REPO/scripts/update-probe.sh" \
   "$REPO/scripts/update-notify.sh" "$REPO/scripts/check-overlay-versions.sh" \
   "$d/scripts/"
cp "$REPO/apps/aarch64-darwin/_common.sh" "$REPO/apps/aarch64-darwin/bump-overlays" \
   "$d/apps/aarch64-darwin/"
cat > "$d/overlays/updates.json" <<EOF
{
  "packages": [
    {
      "name": "c4",
      "overlay": "overlays/56-c4.nix",
      "current_version": "0-unstable-2020-01-01",
      "current_rev": "$OLD_REV",
      "check": { "method": "github-commits", "repo": "acme/c4", "branch": "master" },
      "update_type": "go-source"
    }
  ],
  "skip": [],
  "inputs": {},
  "pinned_inputs": []
}
EOF
cat > "$d/overlays/56-c4.nix" <<EOF
final: prev: {
  c4 = final.buildGo127Module rec {
    pname = "c4";
    version = "0-unstable-2020-01-01";
    src = prev.fetchFromGitHub {
      owner = "acme";
      repo = "c4";
      rev = "$OLD_REV";
      hash = "$OLD_HASH";
    };
    vendorHash = null;
  };
}
EOF
printf '{"comment":"test","entries":[]}\n' > "$d/overlays/quarantine.json"
: > "$d/flake.nix"
git -C "$d" init -q
git -C "$d" config user.email t@example.com
git -C "$d" config user.name Test
git -C "$d" add -A
git -C "$d" commit -qm init

# curl: both the version probe (.sha[:12]) and github_full_sha (.sha) hit the
# commits endpoint.
cat > "$stub/curl" <<EOF
#!/usr/bin/env bash
printf '{"sha":"%s"}' "$NEW_REV"
EOF
# nix build: succeeds only if the overlay still says `vendorHash = null`. A
# blanked vendorHash reproduces the real failure — an error with no `got:`.
cat > "$stub/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "registry list") exit 1 ;; esac
case "\$1" in
  build)
    echo "build \$*" >> "$d/build.log"
    if grep -q 'vendorHash = null;' "$d/overlays/56-c4.nix"; then exit 0; fi
    echo "error: vendor folder is empty, please set 'vendorHash = null;' in your expression" >&2
    exit 1 ;;
  *) exec "$REAL_NIX" "\$@" ;;
esac
EOF
cat > "$stub/nix-prefetch-url" <<'EOF'
#!/usr/bin/env bash
echo "0000000000000000000000000000000000000000000000000000"
EOF
chmod +x "$stub/curl" "$stub/nix" "$stub/nix-prefetch-url"

( cd "$d" && PATH="$stub:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
    bash apps/aarch64-darwin/bump-overlays --no-public-sync >"$d/out.log" 2>&1 ) && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/out.log"; fail "expected exit 0, got $rc"; }
grep -q "rev = \"$NEW_REV\";" "$d/overlays/56-c4.nix" || { cat "$d/overlays/56-c4.nix"; fail "rev not bumped"; }
grep -q 'vendorHash = null;' "$d/overlays/56-c4.nix" || fail "vendorHash = null was rewritten"
grep -q "$OLD_HASH" "$d/overlays/56-c4.nix" && fail "src hash not updated"
[[ "$(jq -r '.packages[0].current_rev' "$d/overlays/updates.json")" == "$NEW_REV" ]] \
  || fail "manifest current_rev not bumped"
[[ "$(jq '.entries | length' "$d/overlays/quarantine.json")" == "0" ]] \
  || { jq . "$d/overlays/quarantine.json"; fail "a null-vendorHash bump was quarantined"; }
# Exactly one build: the verification build. No throwaway hash-scraping build.
[[ "$(wc -l < "$d/build.log" | tr -d ' ')" == "1" ]] \
  || { cat "$d/build.log"; fail "expected exactly 1 nix build (verification only)"; }
[[ -z "$(git -C "$d" status --porcelain -- overlays/)" ]] || fail "run left overlays/ dirty"
rm -rf "$d" "$stub"

echo "PASS: test_bump_gosource_null_vendor"
