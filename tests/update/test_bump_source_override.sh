#!/usr/bin/env bash
# bump-overlays' source-override path (tmux/btop/llama-cpp/tmux-resurrect):
# version + tag/rev substitution, then every fixed-output hash (`hash`, and
# `npmDepsHash` when present) resolved by blanking it and reading `got:` from
# the build error. Stubbed nix/curl, scratch repo, no network or real build.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
REAL_NIX="$(command -v nix)"
fail() { echo "FAIL: $1"; exit 1; }

setup_repo() { # <overlay-file-content> <manifest-entry-json>
  local d; d="$(mktemp -d)"
  mkdir -p "$d/overlays" "$d/scripts" "$d/apps/aarch64-darwin" "$d/logs"
  cp "$REPO"/scripts/{quarantine,update-state,classify-failure,update-probe,update-notify,check-overlay-versions,github-api}.sh "$d/scripts/"
  cp "$REPO/apps/aarch64-darwin/_common.sh" "$REPO/apps/aarch64-darwin/bump-overlays" "$d/apps/aarch64-darwin/"
  printf '%s\n' "$1" > "$d/overlays/99-demo.nix"
  printf '{"packages":[%s],"skip":[],"inputs":{},"pinned_inputs":[]}\n' "$2" > "$d/overlays/updates.json"
  printf '{"comment":"test","entries":[]}\n' > "$d/overlays/quarantine.json"
  : > "$d/flake.nix"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name Test
  git -C "$d" add -A
  git -C "$d" commit -qm init
  printf '%s' "$d"
}

# nix stub: a build "fails with a hash mismatch" while any hash is blank, naming
# a distinct expected hash per field, and succeeds once none is blank.
make_stubs() { # <stub-dir> <repo> <latest-tag>
  local stub="$1" d="$2" tag="$3"
  cat > "$stub/curl" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *releases/latest*) printf '{"tag_name":"%s"}' "$tag" ;;
  *) printf '{"sha":"2222222222222222222222222222222222222222"}' ;;
esac
EOF
  cat > "$stub/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "registry list") exit 1 ;; esac
case "\$1" in
  build)
    f="$d/overlays/99-demo.nix"
    if grep -qE '(^|[^A-Za-z])hash = "";' "\$f"; then
      echo "error: hash mismatch in fixed-output derivation '/nix/store/x-src.drv':"
      echo "         specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
      echo "            got:    sha256-SRCSRCSRCSRCSRCSRCSRCSRCSRCSRCSRCSRCSRCSRCS="
      exit 1
    fi
    if grep -q 'npmDepsHash = "";' "\$f"; then
      echo "error: hash mismatch in fixed-output derivation '/nix/store/x-npm.drv':"
      echo "            got:    sha256-NPMNPMNPMNPMNPMNPMNPMNPMNPMNPMNPMNPMNPMNPMN="
      exit 1
    fi
    exit 0 ;;
  *) exec "$REAL_NIX" "\$@" ;;
esac
EOF
  chmod +x "$stub/curl" "$stub/nix"
}

run_bump() { # <repo> <stub>
  ( cd "$1" && PATH="$2:$PATH" GITHUB_TOKEN=test UPDATE_STATE_FILE="$1/.state.json" \
      bash apps/aarch64-darwin/bump-overlays --no-public-sync >"$1/out.log" 2>&1 ) && return 0 || return 1
}

# === Case 1: tag-tracked, prefixed tag, TWO hashes (llama-cpp shape) ========
d="$(setup_repo 'final: prev: {
  demo = prev.demo.overrideAttrs (old: rec {
    version = "100";
    src = prev.fetchFromGitHub {
      owner = "acme";
      repo = "demo";
      tag = "b100";
      hash = "sha256-OLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDO=";
    };
    npmDepsHash = "sha256-OLDNPMOLDNPMOLDNPMOLDNPMOLDNPMOLDNPMOLDNPM=";
  });
}' '{"name":"demo","overlay":"overlays/99-demo.nix","current_version":"100","check":{"method":"github-release","repo":"acme/demo","tag_prefix":"b"},"update_type":"source-override"}')"
stub="$(mktemp -d)"; make_stubs "$stub" "$d" "b200"
run_bump "$d" "$stub" || { cat "$d/out.log"; fail "case1: bump failed"; }
f="$d/overlays/99-demo.nix"
grep -q 'version = "200";' "$f" || fail "case1: version not bumped"
grep -q 'tag = "b200";' "$f" || fail "case1: tag not bumped (prefix lost?)"
grep -q 'hash = "sha256-SRCSRC' "$f" || fail "case1: src hash not resolved"
grep -q 'npmDepsHash = "sha256-NPMNPM' "$f" || fail "case1: npmDepsHash not resolved"
[[ "$(jq -r '.packages[0].current_version' "$d/overlays/updates.json")" == "200" ]] || fail "case1: manifest not bumped"
[[ "$(jq '.entries | length' "$d/overlays/quarantine.json")" == "0" ]] || fail "case1: unexpectedly quarantined"
[[ -z "$(git -C "$d" status --porcelain -- overlays/)" ]] || fail "case1: left overlays/ dirty"
rm -rf "$d" "$stub"

# === Case 2: bare tag, one hash, version with a letter suffix (tmux shape) ==
d="$(setup_repo 'final: prev: {
  demo = prev.demo.overrideAttrs (old: {
    version = "3.7b";
    src = prev.fetchFromGitHub {
      owner = "acme";
      repo = "demo";
      tag = "3.7b";
      hash = "sha256-OLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDO=";
    };
  });
}' '{"name":"demo","overlay":"overlays/99-demo.nix","current_version":"3.7b","check":{"method":"github-release","repo":"acme/demo"},"update_type":"source-override"}')"
stub="$(mktemp -d)"; make_stubs "$stub" "$d" "3.8"
run_bump "$d" "$stub" || { cat "$d/out.log"; fail "case2: bump failed"; }
f="$d/overlays/99-demo.nix"
grep -q 'version = "3.8";' "$f" && grep -q 'tag = "3.8";' "$f" || { cat "$f"; fail "case2: version/tag not bumped"; }
grep -q 'hash = "sha256-SRCSRC' "$f" || fail "case2: src hash not resolved"
rm -rf "$d" "$stub"

# === Case 3: commit-tracked (rev), custom attr (tmux-resurrect shape) =======
d="$(setup_repo 'final: prev: {
  demo = prev.demo.overrideAttrs (old: {
    version = "0-unstable-2023-03-06";
    src = prev.fetchFromGitHub {
      owner = "acme";
      repo = "demo";
      rev = "1111111111111111111111111111111111111111";
      hash = "sha256-OLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDO=";
    };
  });
}' '{"name":"demo","attr":"plugins.demo","overlay":"overlays/99-demo.nix","current_version":"0-unstable-2023-03-06","current_rev":"1111111111111111111111111111111111111111","check":{"method":"github-commits","repo":"acme/demo","branch":"master"},"update_type":"source-override"}')"
stub="$(mktemp -d)"; make_stubs "$stub" "$d" "unused"
run_bump "$d" "$stub" || { cat "$d/out.log"; fail "case3: bump failed"; }
f="$d/overlays/99-demo.nix"
grep -q 'rev = "2222222222222222222222222222222222222222";' "$f" || fail "case3: rev not bumped"
[[ "$(jq -r '.packages[0].current_rev' "$d/overlays/updates.json")" == "2222222222222222222222222222222222222222" ]] \
  || fail "case3: manifest current_rev not bumped"
rm -rf "$d" "$stub"

# === Case 4: a build that never produces `got:` is quarantined, tree restored
d="$(setup_repo 'final: prev: {
  demo = prev.demo.overrideAttrs (old: {
    version = "1";
    src = prev.fetchFromGitHub {
      owner = "acme";
      repo = "demo";
      tag = "1";
      hash = "sha256-OLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDO=";
    };
  });
}' '{"name":"demo","overlay":"overlays/99-demo.nix","current_version":"1","check":{"method":"github-release","repo":"acme/demo"},"update_type":"source-override"}')"
stub="$(mktemp -d)"; make_stubs "$stub" "$d" "2"
cat > "$stub/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "registry list") exit 1 ;; esac
case "\$1" in build) echo "error: evaluation failed: attribute 'demo' missing" >&2; exit 1 ;; *) exec "$REAL_NIX" "\$@" ;; esac
EOF
run_bump "$d" "$stub" && fail "case4: expected failure exit"
grep -q 'version = "1";' "$d/overlays/99-demo.nix" || fail "case4: overlay not restored"
[[ "$(jq -r '.entries[0].blocked_version' "$d/overlays/quarantine.json")" == "2" ]] || fail "case4: not quarantined at the attempted version"
rm -rf "$d" "$stub"

echo "PASS: test_bump_source_override"
