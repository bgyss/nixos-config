#!/usr/bin/env bash
# Table-driven test for scripts/classify-failure.sh. Each case writes a
# realistic snippet of nix build output to a temp log and asserts the full
# 4-field classification line.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# shellcheck source=/dev/null
source "$REPO/scripts/classify-failure.sh"

check() { # <case-name> <expected-line> <log-content>
  local name="$1" expected="$2" content="$3"
  printf '%s\n' "$content" > "$TMP/log"
  local got; got="$(classify_failure "$TMP/log")"
  if [[ "$got" != "$expected" ]]; then
    echo "FAIL: $name"
    echo "  expected: $expected"
    echo "  got:      $got"
    exit 1
  fi
}

check "hash-mismatch" \
  "hash-mismatch	retry-after:6	0	fix-hashes" \
  "error: hash mismatch in fixed-output derivation '/nix/store/x-source.drv':
         specified: sha256-AAAA
            got:    sha256-BBBB"

check "network" \
  "network-error	retry-after:6	0	none" \
  "error: unable to download 'https://github.com/foo/bar': Couldn't resolve host name (6)"

check "http-404" \
  "network-error	retry-after:6	0	none" \
  "error: unable to download 'https://example.com/x.tar.gz': HTTP error 404"

check "missing-attribute" \
  "eval-error	next-version-only	1	none" \
  "error: attribute 'go_1_26' missing at /nix/store/x/overlays/55-go.nix:12:5"

check "eval-infinite-recursion" \
  "eval-error	next-version-only	1	none" \
  "error: infinite recursion encountered at «string»:1:1"

check "compile-failure" \
  "compile-failure	next-version-only	1	none" \
  "go: downloading github.com/foo/bar
./main.go:12:2: undefined: SomeSymbol
error: builder for '/nix/store/x-beads-1.1.0.drv' failed with exit code 1"

check "test-failure" \
  "test-failure	next-version-only	1	none" \
  "running tests
FAILED tests/test_thing.py::test_x - AssertionError
error: builder for '/nix/store/x.drv' failed with exit code 1"

check "unclassified" \
  "unclassified	next-version-only	1	none" \
  "error: something nobody has ever seen before"

# A missing or empty log must still classify, never crash the caller.
: > "$TMP/empty"
[[ "$(classify_failure "$TMP/empty")" == "unclassified	next-version-only	1	none" ]] \
  || { echo "FAIL: empty log"; exit 1; }
[[ "$(classify_failure "$TMP/does-not-exist")" == "unclassified	next-version-only	1	none" ]] \
  || { echo "FAIL: missing log"; exit 1; }

# Ordering matters: a log containing BOTH a hash mismatch and a builder failure
# must classify as the hash mismatch, because fix-hashes can resolve it.
check "hash-mismatch-wins" \
  "hash-mismatch	retry-after:6	0	fix-hashes" \
  "error: hash mismatch in fixed-output derivation '/nix/store/x.drv':
error: builder for '/nix/store/y.drv' failed with exit code 1"

echo "PASS: test_classify_failure"
