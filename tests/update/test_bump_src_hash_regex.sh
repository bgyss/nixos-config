#!/usr/bin/env bash
# Exercises the fetchFromGitHub hash extractor embedded in bump-overlays'
# go-source path. The extractor is an inline `python3 -c` snippet, so this test
# pulls that exact snippet out of the shipped script (no copy to drift) and runs
# it against fixture overlays.
#
# Regression: an overlay whose rev is interpolated (`rev = "v${version}"`)
# contains a `}` inside the fetchFromGitHub block, so a `[^}]*?` scan stops
# early and finds no hash — bump-overlays then aborted every beads bump with
# "could not locate current fetchFromGitHub hash".
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
fail=0

scratch="$(mktemp -d)"

# Extract the extractor: the python3 -c '...' block assigned to current_src_hash.
python3 - "$REPO/apps/aarch64-darwin/bump-overlays" "$scratch/extract.py" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"current_src_hash=\"\$\(python3 -c '\n(.*?)\n' ", text, re.DOTALL)
if not m:
    sys.exit("could not extract the current_src_hash python snippet from bump-overlays")
open(sys.argv[2], "w").write(m.group(1) + "\n")
PY

check() { # name, expected-hash, file
  local got
  got="$(python3 "$scratch/extract.py" "$3")"
  if [[ "$got" != "$2" ]]; then
    echo "FAIL: $1: expected '$2', got '$got'"
    fail=1
  fi
}

# Interpolated rev — the regression case.
cat > "$scratch/interp.nix" <<'EOF'
final: prev:
let
  version = "1.1.0";
  src = final.fetchFromGitHub {
    owner = "gastownhall";
    repo = "beads";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
in
{ }
EOF
check "interpolated rev" "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" "$scratch/interp.nix"

# Literal rev — the commit-tracked overlays (c4, hey-cli).
cat > "$scratch/literal.nix" <<'EOF'
final: prev:
let
  src = final.fetchFromGitHub {
    owner = "acme";
    repo = "thing";
    rev = "0123456789abcdef0123456789abcdef01234567";
    hash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
  };
in
{ }
EOF
check "literal rev" "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=" "$scratch/literal.nix"

# A later, unrelated fetch block must not shadow the first one's hash.
cat > "$scratch/two.nix" <<'EOF'
final: prev:
let
  version = "2.0.0";
  src = final.fetchFromGitHub {
    owner = "acme";
    repo = "thing";
    rev = "v${version}";
    hash = "sha256-CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=";
  };
  other = final.fetchurl {
    url = "https://example.invalid/x.tar.gz";
    hash = "sha256-DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD=";
  };
in
{ }
EOF
check "first block wins" "sha256-CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=" "$scratch/two.nix"

# Every real go-source overlay in this repo must be readable by the extractor.
for f in "$REPO"/overlays/*.nix; do
  grep -q "fetchFromGitHub" "$f" || continue
  got="$(python3 "$scratch/extract.py" "$f")"
  if [[ -z "$got" ]]; then
    echo "FAIL: no hash extracted from $(basename "$f")"
    fail=1
  fi
done

rm -rf "$scratch"
[[ $fail -eq 0 ]] && echo "PASS: test_bump_src_hash_regex" || exit 1
