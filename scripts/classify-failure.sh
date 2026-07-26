#!/usr/bin/env bash
# Classify a failed build log into a stable fingerprint + retry policy, so the
# deterministic layer can decide whether to self-heal, back off, or escalate to
# Claude (spec §2 "Failure classification").
#
# This table is the main thing keeping token spend near zero: anything it can
# match is handled in shell. `unclassified` fingerprints are the worklist for
# growing it — grep the ledger for them.
#
# Output: <fingerprint>\t<retry_policy>\t<escalate 0|1>\t<remediation>
#
# Order is significant. A log can match several patterns at once (a hash
# mismatch also produces a builder failure); the first match wins, so the
# cheapest self-healing remediation must be checked first.
#
# Sourced for `classify_failure`, or run directly: classify-failure.sh <log>

classify_failure() { # <logfile>
  local log="${1:-}"
  [[ -f "$log" && -r "$log" && -s "$log" ]] || { printf 'unclassified\tnext-version-only\t1\tnone\n'; return 0; }

  # 1. Hash mismatch — a re-uploaded upstream artifact. fix-hashes resolves
  #    this without human or model involvement, so never escalate.
  if grep -qF -m1 'hash mismatch in fixed-output derivation' "$log"; then
    printf 'hash-mismatch\tretry-after:6\t0\tfix-hashes\n'; return 0
  fi

  # 2. Transient network/transport trouble. Back off, do not escalate: there is
  #    nothing to repair in the overlay.
  if grep -qiE -m1 'unable to download|couldn.t resolve host|connection (timed out|refused|reset)|HTTP error [45][0-9][0-9]|SSL peer certificate|curl: \([0-9]+\)' "$log"; then
    printf 'network-error\tretry-after:6\t0\tnone\n'; return 0
  fi

  # 3. Nix evaluation errors — a renamed attribute, a moved path, a changed
  #    upstream layout. Mechanically unfixable, and exactly the class Claude is
  #    good at (e.g. the go_1_26 -> go_1_27 attribute rename).
  if grep -qiE -m1 "attribute '[^']*' missing|infinite recursion encountered|undefined variable|called without required argument|value is a .* while a .* was expected|syntax error, unexpected" "$log"; then
    printf 'eval-error\tnext-version-only\t1\tnone\n'; return 0
  fi

  # 4. Test failures inside a builder. Checked before the generic compile case
  #    because the remedy differs (usually doCheck = false, not a code change).
  if grep -qiE -m1 '^(FAILED|FAIL:|not ok )|[0-9]+ (test|tests) failed|AssertionError|check phase failed' "$log"; then
    printf 'test-failure\tnext-version-only\t1\tnone\n'; return 0
  fi

  # 5. Any other builder failure: a real compile/build break in the new version.
  if grep -qiE -m1 "builder for '[^']*' failed|make: \*\*\*|error\[E[0-9]+\]:|undefined: |cannot find package" "$log"; then
    printf 'compile-failure\tnext-version-only\t1\tnone\n'; return 0
  fi

  # 6. Unknown. Fail closed: block this version and escalate, so the failure is
  #    seen rather than silently retried forever.
  printf 'unclassified\tnext-version-only\t1\tnone\n'
}

# Direct invocation support.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  classify_failure "${1:-}"
fi
