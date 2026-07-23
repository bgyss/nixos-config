#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
STUB="$(mktemp -d)"

# curl: hermetic stand-in for every upstream check `probe_overlays` might make.
# Rather than hardcoding per-package expected values (which would need
# updating every time overlays/updates.json changes), this reflects each
# package's OWN current_version back as "latest" by inspecting the request
# URL and looking the package up in the real manifest — so every overlay
# reports up to date regardless of what's actually pinned right now.
# Anything unrecognized (e.g. the ngrok binary CDN, which isn't a JSON API)
# fails closed (`exit 1`), matching a real network failure -> ERROR, never
# "outdated".
cat > "$STUB/curl" <<EOF
#!/usr/bin/env bash
MANIFEST="$REPO/overlays/updates.json"
url=""
for a in "\$@"; do
  case "\$a" in http*) url="\$a" ;; esac
done
case "\$url" in
  */repos/*/releases/latest)
    repo="\${url#*api.github.com/repos/}"; repo="\${repo%/releases/latest}"
    pkg=\$(jq -c --arg r "\$repo" '.packages[] | select(.check.repo==\$r and .check.method=="github-release")' "\$MANIFEST")
    cur=\$(jq -r '.current_version' <<<"\$pkg")
    prefix=\$(jq -r '.check.tag_prefix // ""' <<<"\$pkg")
    if [[ -n "\$prefix" ]]; then tag="\${prefix}\${cur}"; else tag="v\${cur}"; fi
    printf '{"tag_name":"%s"}' "\$tag"; exit 0 ;;
  */repos/*/commits/*)
    repo="\${url#*api.github.com/repos/}"; repo="\${repo%/commits/*}"
    pkg=\$(jq -c --arg r "\$repo" '.packages[] | select(.check.repo==\$r and .check.method=="github-commits")' "\$MANIFEST")
    rev=\$(jq -r '.current_rev // empty' <<<"\$pkg")
    [[ -z "\$rev" ]] && exit 1
    printf '{"sha":"%s"}' "\$rev"; exit 0 ;;
  */pypi.org/pypi/*/json)
    package="\${url#*pypi.org/pypi/}"; package="\${package%/json}"
    pkg=\$(jq -c --arg p "\$package" '.packages[] | select(.check.package==\$p and .check.method=="pypi")' "\$MANIFEST")
    cur=\$(jq -r '.current_version' <<<"\$pkg")
    printf '{"info":{"version":"%s"}}' "\$cur"; exit 0 ;;
  */registry.npmjs.org/*/latest)
    package="\${url#*registry.npmjs.org/}"; package="\${package%/latest}"
    pkg=\$(jq -c --arg p "\$package" '.packages[] | select(.check.package==\$p and .check.method=="npm")' "\$MANIFEST")
    cur=\$(jq -r '.current_version' <<<"\$pkg")
    printf '{"version":"%s"}' "\$cur"; exit 0 ;;
  */go.dev/dl/*)
    pkg=\$(jq -c '.packages[] | select(.check.method=="go-dev")' "\$MANIFEST")
    cur=\$(jq -r '.current_version' <<<"\$pkg")
    printf '[{"stable":true,"version":"go%s"}]' "\$cur"; exit 0 ;;
  *)
    exit 1 ;;
esac
EOF
chmod +x "$STUB/curl"

# nix: metadata returns no github inputs (so the input probe has nothing to
# chase upstream); flake lock is a no-op. Anything else falls through to the
# REAL nix binary (captured by absolute path below — falling through via a
# PATH-based lookup like `env nix` would resolve back to this very stub,
# since $STUB is prepended to PATH for the whole test, and recurse forever;
# `locate_flake`'s `nix registry list` call hits exactly this fallback path).
REAL_NIX="$(command -v nix)"
cat > "$STUB/nix" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "flake" && "\$2" == "metadata" ]]; then echo '{"locks":{"nodes":{}}}'; exit 0; fi
if [[ "\$1" == "flake" && "\$2" == "lock" ]]; then exit 0; fi
# Fail closed on "registry list" so _common.sh's locate_flake() falls back to
# its git-toplevel path, resolving to THIS checkout — not whatever repo path
# happens to be registered as "nixos-config" on the host running the test.
if [[ "\$1" == "registry" && "\$2" == "list" ]]; then exit 1; fi
exec "$REAL_NIX" "\$@"
EOF
chmod +x "$STUB/nix"

export UPDATE_STATE_FILE="$(mktemp)"; rm -f "$UPDATE_STATE_FILE"
out="$(PATH="$STUB:$PATH" bash "$REPO/apps/aarch64-darwin/check" 2>&1)" || true
rm -rf "$STUB"
echo "$out" | grep -qi "nothing to do" || { echo "FAIL: expected nothing-to-do"; echo "$out"; exit 1; }
echo "PASS: test_check_app"
