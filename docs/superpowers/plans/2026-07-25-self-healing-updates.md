# Self-Healing Daily Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the daily update pipeline auto-bump every overlay, auto-activate with a health check and auto-rollback, and remember per-version breakage in a quarantine ledger so a human is only involved when the machine cannot route around a failure.

**Architecture:** Two layers joined by one state file. A deterministic shell pipeline (root launchd daemon → bump → build → activate → health check → rollback-on-failure) costs zero tokens and handles the common case. Failures it cannot classify-and-skip escalate to a budgeted headless `claude -p` session that may edit overlays in a throwaway git worktree but never commits or activates — the wrapper re-verifies with its own build and commits only if green. `overlays/quarantine.json` is the seam: layer 1 writes failures, layer 2 writes verdicts.

**Tech Stack:** Bash (the repo's existing app/script convention), `jq` for JSON state, `python3` for anchored regex substitution in `.nix` files, Nix flakes + nix-darwin, launchd, `claude -p` headless.

**Spec:** `docs/superpowers/specs/2026-07-25-self-healing-updates-design.md`

## Global Constraints

- **Target host:** `garmonbozia` (aarch64-darwin) only. `FLAKE_SYSTEM_ATTR` is `darwinConfigurations.garmonbozia.system` (defined in `apps/aarch64-darwin/_common.sh`).
- **Apps are duplicated per system** under `apps/{aarch64-darwin,x86_64-darwin,aarch64-linux,x86_64-linux}/`. Verify with `ls apps/*/` whether the file you are editing exists in more than one system directory; if it does, apply the identical edit to every copy.
- **Repo checkouts:** `~/nixos-config` is the private daily driver (no git remote). `~/src/nixos-config` is the public mirror. A post-commit hook mirrors public-safe files. Work only in `~/nixos-config`.
- **New private notes must be added to `scripts/public-sync-denylist.txt` before committing.** Every file created by this plan is public-safe and must NOT be denylisted, except `logs/*` which is already gitignored.
- **Every overlay must appear in `overlays/updates.json`** (as a `packages[]` pin or a `skip[]` entry) or the `overlays-manifest` check fails.
- **Run `nix fmt` before committing any `.nix` change.** Keep `nix flake check` green (`treefmt` + `overlays-manifest` + `darwin-build`).
- **Test convention (follow exactly):** tests live in `tests/update/test_<name>.sh`, are plain `bash` with `set -euo pipefail`, isolate everything via `PATH`-prepended stub binaries in a `mktemp -d`, print `PASS: test_<name>` on success, and exit non-zero on failure. `tests/update/run.sh` auto-discovers `test_*.sh` — no registration needed.
- **Full test command:** `bash tests/update/run.sh` — expected final line `ALL PASS`.
- **Never let a test touch real state.** Point `UPDATE_STATE_FILE` and `QUARANTINE_FILE` at scratch paths, and use a scratch git repo when a test exercises commits.
- **Existing exit-code contract (do not break):** `bump-overlays` and `prepare` return `0` success/nothing-to-do, `1` real failure, `2` lock contention (benign, caller stays silent), `3` dirty `overlays/`.
- **Timestamps** are UTC ISO-8601 via the existing `now_iso()` helper in `scripts/update-state.sh` (`date -u +%Y-%m-%dT%H:%M:%SZ`).
- **Commit each task separately** with a concise imperative subject.

---

### Task 1: Quarantine ledger helpers

The foundation: a git-tracked JSON ledger plus sourced bash helpers. No other task can proceed without this.

**Files:**
- Create: `overlays/quarantine.json`
- Create: `scripts/quarantine.sh`
- Test: `tests/update/test_quarantine.sh`

**Interfaces:**
- Consumes: `now_iso()` from `scripts/update-state.sh` (sourced separately by callers).
- Produces (all sourced from `scripts/quarantine.sh`):
  - `quarantine_init` → creates/repairs the ledger file. No output.
  - `quarantine_is_blocked <name> <version>` → exit 0 if blocked, 1 if eligible.
  - `quarantine_record <name> <kind> <blocked_version> <known_good_version> <phase> <fingerprint> <retry_policy> <error_excerpt>` → upserts an entry; increments `attempts` and auto-promotes to `frozen` at `attempts >= 3`.
  - `quarantine_clear <name>` → removes the entry (called after a successful bump).
  - `quarantine_field <name> <field>` → prints one field, empty string if absent.
  - `quarantine_should_escalate <name> <fingerprint>` → exit 0 if this `(name, fingerprint)` has not already produced a `gave-up` verdict AND `attempts < 3`.
  - `quarantine_set_escalation <name> <status> <verdict>` → records the escalation result.
  - `quarantine_sanitize` → filter: stdin → stdout, strips `/nix/store/<hash>-` prefixes and truncates to 2000 chars.
  - `QUARANTINE_FILE` env var overrides the default path (`<repo>/overlays/quarantine.json`).

- [ ] **Step 1: Create the empty ledger**

```bash
cat > overlays/quarantine.json <<'EOF'
{
  "comment": "Machine-written quarantine ledger. See docs/superpowers/specs/2026-07-25-self-healing-updates-design.md §2. Do not hand-edit while the daily pipeline may be running; use scripts/quarantine.sh.",
  "entries": []
}
EOF
```

- [ ] **Step 2: Write the failing test**

Create `tests/update/test_quarantine.sh`:

```bash
#!/usr/bin/env bash
# Unit-tests scripts/quarantine.sh against a scratch ledger. Never touches the
# real overlays/quarantine.json: QUARANTINE_FILE is redirected to a temp file.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export QUARANTINE_FILE="$TMP/quarantine.json"

# shellcheck source=/dev/null
source "$REPO/scripts/update-state.sh"
# shellcheck source=/dev/null
source "$REPO/scripts/quarantine.sh"

fail() { echo "FAIL: $1"; exit 1; }

# --- init is idempotent and produces valid JSON -----------------------------
quarantine_init
jq empty "$QUARANTINE_FILE" || fail "init did not produce valid JSON"
quarantine_init
[[ "$(jq '.entries | length' "$QUARANTINE_FILE")" == "0" ]] || fail "init not idempotent"

# --- an unknown package is never blocked -----------------------------------
if quarantine_is_blocked "claude-code" "2.1.221"; then fail "unknown package reported blocked"; fi

# --- next-version-only blocks ONLY the recorded version --------------------
quarantine_record "claude-code" "overlay" "2.1.221" "2.1.220" "package-build" \
  "compile-failure" "next-version-only" "boom"
quarantine_is_blocked "claude-code" "2.1.221" || fail "blocked_version not blocked"
if quarantine_is_blocked "claude-code" "2.1.222"; then fail "newer version wrongly blocked"; fi
[[ "$(quarantine_field claude-code known_good_version)" == "2.1.220" ]] \
  || fail "known_good_version not recorded"
[[ "$(quarantine_field claude-code attempts)" == "1" ]] || fail "attempts != 1"

# --- re-recording the same version increments attempts, does not duplicate --
quarantine_record "claude-code" "overlay" "2.1.221" "2.1.220" "package-build" \
  "compile-failure" "next-version-only" "boom"
[[ "$(jq '.entries | length' "$QUARANTINE_FILE")" == "1" ]] || fail "duplicate entry created"
[[ "$(quarantine_field claude-code attempts)" == "2" ]] || fail "attempts != 2"

# --- attempts >= 3 auto-promotes to frozen, which blocks EVERY version -----
quarantine_record "claude-code" "overlay" "2.1.221" "2.1.220" "package-build" \
  "compile-failure" "next-version-only" "boom"
[[ "$(quarantine_field claude-code retry_policy)" == "frozen" ]] \
  || fail "not auto-promoted to frozen at attempts=3"
quarantine_is_blocked "claude-code" "9.9.9" || fail "frozen did not block a newer version"

# --- retry-after blocks the same version until the window expires ----------
quarantine_record "uv" "overlay" "0.11.33" "0.11.32" "prefetch" \
  "network-error" "retry-after:6" "curl: (6)"
quarantine_is_blocked "uv" "0.11.33" || fail "retry-after did not block inside window"
# Backdate last_attempt past the window; it must become eligible again.
jq '(.entries[] | select(.name=="uv") | .last_attempt) = "2000-01-01T00:00:00Z"' \
  "$QUARANTINE_FILE" > "$TMP/x" && mv "$TMP/x" "$QUARANTINE_FILE"
if quarantine_is_blocked "uv" "0.11.33"; then fail "retry-after did not expire"; fi

# --- clear removes the entry ----------------------------------------------
quarantine_clear "uv"
if quarantine_is_blocked "uv" "0.11.33"; then fail "clear did not remove entry"; fi
[[ -z "$(quarantine_field uv attempts)" ]] || fail "cleared entry still has fields"

# --- escalation dedup -----------------------------------------------------
quarantine_record "yt-dlp" "overlay" "2026.07.19" "2026.07.04" "package-build" \
  "curl_cffi-bound" "next-version-only" "bound"
quarantine_should_escalate "yt-dlp" "curl_cffi-bound" || fail "first escalation refused"
quarantine_set_escalation "yt-dlp" "gave-up" "needs manual review"
if quarantine_should_escalate "yt-dlp" "curl_cffi-bound"; then
  fail "escalated again after gave-up on same fingerprint"
fi
quarantine_should_escalate "yt-dlp" "different-fingerprint" \
  || fail "refused escalation for a NEW fingerprint"
[[ "$(quarantine_field yt-dlp escalation_status)" == "gave-up" ]] \
  || fail "escalation_status not readable"

# --- re-recording must PRESERVE the escalation verdict --------------------
# Regression guard for the groundhog-day brake: upstream ships a newer version,
# the pipeline retries, it fails the same way and re-records. If that upsert
# drops .escalation, the already-refused escalation looks eligible again and
# burns a session every single day.
quarantine_record "yt-dlp" "overlay" "2026.07.26" "2026.07.04" "package-build" \
  "curl_cffi-bound" "next-version-only" "bound again"
[[ "$(quarantine_field yt-dlp escalation_status)" == "gave-up" ]] \
  || fail "re-record wiped the escalation verdict"
if quarantine_should_escalate "yt-dlp" "curl_cffi-bound"; then
  fail "re-record re-enabled escalation for an already-refused fingerprint"
fi
# ...and the ledger must still be intact (not truncated by an empty jq stream).
[[ "$(jq '.entries | length' "$QUARANTINE_FILE")" -ge 1 ]] || fail "ledger truncated by re-record"

# --- recording a BRAND-NEW package must not fail on the missing prior entry
quarantine_record "brand-new-pkg" "overlay" "1.0.0" "0.9.0" "prefetch" \
  "network-error" "retry-after:6" "curl: (6)"
[[ "$(quarantine_field brand-new-pkg blocked_version)" == "1.0.0" ]] \
  || fail "recording a package with no prior entry failed"

# --- sanitize strips store paths and truncates ----------------------------
out="$(printf 'error at /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-foo-1.0/bin/foo\n' | quarantine_sanitize)"
[[ "$out" != *"/nix/store/"* ]] || fail "store path not stripped"
[[ "$out" == *"foo-1.0/bin/foo"* ]] || fail "sanitize destroyed useful content"
long="$(head -c 5000 /dev/zero | tr '\0' 'x' | quarantine_sanitize | wc -c | tr -d ' ')"
[[ "$long" -le 2001 ]] || fail "sanitize did not truncate (got $long chars)"

echo "PASS: test_quarantine"
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash tests/update/test_quarantine.sh`
Expected: FAIL — `scripts/quarantine.sh: No such file or directory`

- [ ] **Step 4: Write the implementation**

Create `scripts/quarantine.sh`:

```bash
#!/usr/bin/env bash
# Sourced helpers for the quarantine ledger (spec §2).
#
# The ledger is AUTHORITATIVE, git-tracked state — unlike .update-state.json,
# which is a deletable cache. It records, per package, which upstream version
# was tried and failed, so the pipeline can skip exactly that version while
# staying eligible for anything newer. That per-version granularity is the
# whole point: a quarantine self-heals the moment upstream ships a fix.
#
# Ledger path: $QUARANTINE_FILE (default <repo>/overlays/quarantine.json).

: "${QUARANTINE_FILE:=}"

# Sourced from varying locations, so anchor on the git toplevel rather than
# BASH_SOURCE (same rationale as scripts/update-state.sh).
_q_file() {
  if [[ -n "${QUARANTINE_FILE:-}" ]]; then printf '%s' "$QUARANTINE_FILE"; return; fi
  local dir; dir="$(git rev-parse --show-toplevel 2>/dev/null)" || dir="$PWD"
  printf '%s/overlays/quarantine.json' "$dir"
}

_q_readable() {
  local f; f="$(_q_file)"
  [[ -f "$f" ]] && jq empty "$f" >/dev/null 2>&1
}

quarantine_init() {
  local f; f="$(_q_file)"
  if ! _q_readable; then
    printf '{"comment":"Machine-written quarantine ledger. See docs/superpowers/specs/2026-07-25-self-healing-updates-design.md §2.","entries":[]}\n' > "$f"
  fi
}

_q_write() { # jq-filter args...
  local f tmp; f="$(_q_file)"; tmp="$(mktemp)"
  if jq "$@" "$f" > "$tmp"; then
    mv "$tmp" "$f"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Print one field of an entry, or empty. `escalation_status` and
# `escalation_verdict` are flattened accessors into the nested escalation
# object so callers never need to know the shape.
quarantine_field() { # <name> <field>
  _q_readable || { printf ''; return 0; }
  local name="$1" field="$2"
  case "$field" in
    escalation_status)
      jq -r --arg n "$name" '.entries[] | select(.name==$n) | .escalation.status // empty' "$(_q_file)" ;;
    escalation_verdict)
      jq -r --arg n "$name" '.entries[] | select(.name==$n) | .escalation.verdict // empty' "$(_q_file)" ;;
    *)
      jq -r --arg n "$name" --arg f "$field" '.entries[] | select(.name==$n) | .[$f] // empty' "$(_q_file)" ;;
  esac
}

# Exit 0 (blocked) / 1 (eligible).
#   frozen            -> blocks every version, forever, until a human clears it
#   next-version-only -> blocks exactly blocked_version
#   retry-after:H     -> blocks blocked_version until last_attempt + H hours
quarantine_is_blocked() { # <name> <version>
  _q_readable || return 1
  local name="$1" version="$2" policy blocked last
  policy="$(quarantine_field "$name" retry_policy)"
  [[ -z "$policy" ]] && return 1
  [[ "$policy" == "frozen" ]] && return 0

  blocked="$(quarantine_field "$name" blocked_version)"
  [[ "$version" != "$blocked" ]] && return 1

  case "$policy" in
    retry-after:*)
      local hours; hours="${policy#retry-after:}"
      last="$(quarantine_field "$name" last_attempt)"
      # date(1) on darwin cannot parse ISO-8601 directly; python3 is already a
      # hard dependency of bump-overlays, so use it rather than adding coreutils.
      local expired
      expired="$(python3 - "$last" "$hours" <<'PYEOF'
import sys, datetime
last, hours = sys.argv[1], float(sys.argv[2])
try:
    t = datetime.datetime.strptime(last, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
except ValueError:
    print("1"); sys.exit(0)   # unparseable timestamp -> treat as expired
now = datetime.datetime.now(datetime.timezone.utc)
print("1" if (now - t).total_seconds() >= hours * 3600 else "0")
PYEOF
)"
      [[ "$expired" == "1" ]] && return 1
      return 0 ;;
    *) return 0 ;;   # next-version-only, and any unknown policy, fail closed
  esac
}

# Upsert. First failure creates the entry (attempts=1); subsequent failures on
# the SAME blocked_version increment attempts. A different blocked_version
# resets the entry, because it is a genuinely new failure.
# attempts >= 3 auto-promotes to frozen (spec §5.5).
quarantine_record() { # <name> <kind> <blocked_version> <known_good> <phase> <fingerprint> <policy> <excerpt>
  local name="$1" kind="$2" blocked="$3" good="$4" phase="$5" fp="$6" policy="$7" excerpt="$8"
  quarantine_init
  local now prev_blocked attempts first
  now="$(now_iso)"
  prev_blocked="$(quarantine_field "$name" blocked_version)"
  if [[ "$prev_blocked" == "$blocked" ]]; then
    attempts="$(quarantine_field "$name" attempts)"
    attempts=$(( ${attempts:-0} + 1 ))
    first="$(quarantine_field "$name" first_failed)"
  else
    attempts=1
    first="$now"
  fi
  [[ $attempts -ge 3 ]] && policy="frozen"

  local safe_excerpt
  safe_excerpt="$(printf '%s' "$excerpt" | quarantine_sanitize)"

  # The upsert MUST preserve any existing .escalation sub-object. Rebuilding
  # the entry as a bare object literal would drop it, and that silently
  # defeats the fingerprint-dedup brake: a package that already produced a
  # `gave-up` verdict would look escalation-free the next time upstream ships
  # a version, and get escalated again every single day.
  _q_write --arg n "$name" --arg k "$kind" --arg b "$blocked" --arg g "$good" \
    --arg p "$phase" --arg fp "$fp" --arg pol "$policy" --arg ex "$safe_excerpt" \
    --arg first "$first" --arg now "$now" --argjson att "$attempts" '
    # map|.[0] rather than .entries[]|select(...): a non-matching select
    # produces an EMPTY stream, and `empty as $x | body` yields no output at
    # all, which would make _q_write truncate the ledger to nothing. .[0] on
    # an empty array is null, which is what we want for "no prior entry".
    (.entries | map(select(.name == $n)) | .[0].escalation) as $prev_esc
    | .entries = ((.entries | map(select(.name != $n))) + [(
        {
          name: $n, kind: $k,
          blocked_version: $b, known_good_version: $g,
          first_failed: $first, last_attempt: $now,
          attempts: $att, phase: $p, fingerprint: $fp,
          error_excerpt: $ex, retry_policy: $pol
        }
        + (if $prev_esc then {escalation: $prev_esc} else {} end)
      )])'
}

quarantine_clear() { # <name>
  _q_readable || return 0
  _q_write --arg n "$1" '.entries = (.entries | map(select(.name != $n)))'
}

# Exit 0 if this (name, fingerprint) pair deserves a Claude escalation.
# Refuses when the same fingerprint already produced a gave-up verdict (the
# groundhog-day brake, spec §5.4) or when the entry is at the attempt ceiling.
quarantine_should_escalate() { # <name> <fingerprint>
  _q_readable || return 0
  local name="$1" fp="$2" attempts prev_fp status
  attempts="$(quarantine_field "$name" attempts)"
  [[ ${attempts:-0} -ge 3 ]] && return 1
  status="$(quarantine_field "$name" escalation_status)"
  prev_fp="$(quarantine_field "$name" fingerprint)"
  [[ "$status" == "gave-up" && "$prev_fp" == "$fp" ]] && return 1
  return 0
}

quarantine_set_escalation() { # <name> <status> <verdict>
  _q_write --arg n "$1" --arg s "$2" --arg v "$3" --arg t "$(now_iso)" '
    (.entries[] | select(.name==$n) | .escalation) = {status:$s, verdict:$v, at:$t}'
}

# Filter: strip /nix/store/<32-char-hash>- prefixes (keeping the readable
# package-name tail) and truncate, so error text is safe for the public mirror.
quarantine_sanitize() {
  sed -E 's#/nix/store/[a-z0-9]{32}-#<store>/#g' | head -c 2000
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/update/test_quarantine.sh`
Expected: `PASS: test_quarantine`

- [ ] **Step 6: Run the full suite to confirm nothing regressed**

Run: `bash tests/update/run.sh`
Expected: final line `ALL PASS`

- [ ] **Step 7: Commit**

```bash
git add overlays/quarantine.json scripts/quarantine.sh tests/update/test_quarantine.sh
git commit -m "feat(update): add per-version quarantine ledger"
```

---

### Task 2: Failure classifier

Maps a build log to a stable fingerprint plus a retry policy, deciding in shell — before any token is spent — whether Claude is needed at all.

**Files:**
- Create: `scripts/classify-failure.sh`
- Test: `tests/update/test_classify_failure.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `classify_failure <logfile>` prints exactly one tab-separated line:
  `<fingerprint>\t<retry_policy>\t<escalate:0|1>\t<remediation:fix-hashes|none>`.
  Also runnable as an executable for ad-hoc use: `bash scripts/classify-failure.sh <logfile>`.

- [ ] **Step 1: Write the failing test**

Create `tests/update/test_classify_failure.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/update/test_classify_failure.sh`
Expected: FAIL — `scripts/classify-failure.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

Create `scripts/classify-failure.sh`:

```bash
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
  local text=""
  [[ -f "$log" ]] && text="$(cat "$log" 2>/dev/null)"

  # 1. Hash mismatch — a re-uploaded upstream artifact. fix-hashes resolves
  #    this without human or model involvement, so never escalate.
  if [[ "$text" == *"hash mismatch in fixed-output derivation"* ]]; then
    printf 'hash-mismatch\tretry-after:6\t0\tfix-hashes\n'; return 0
  fi

  # 2. Transient network/transport trouble. Back off, do not escalate: there is
  #    nothing to repair in the overlay.
  if grep -qiE 'unable to download|couldn.t resolve host|connection (timed out|refused|reset)|HTTP error [45][0-9][0-9]|SSL peer certificate|curl: \([0-9]+\)' <<<"$text"; then
    printf 'network-error\tretry-after:6\t0\tnone\n'; return 0
  fi

  # 3. Nix evaluation errors — a renamed attribute, a moved path, a changed
  #    upstream layout. Mechanically unfixable, and exactly the class Claude is
  #    good at (e.g. the go_1_26 -> go_1_27 attribute rename).
  if grep -qiE "attribute '[^']*' missing|infinite recursion encountered|undefined variable|called without required argument|value is a .* while a .* was expected|syntax error, unexpected" <<<"$text"; then
    printf 'eval-error\tnext-version-only\t1\tnone\n'; return 0
  fi

  # 4. Test failures inside a builder. Checked before the generic compile case
  #    because the remedy differs (usually doCheck = false, not a code change).
  if grep -qiE '^(FAILED|FAIL:|not ok )|[0-9]+ (test|tests) failed|AssertionError|check phase failed' <<<"$text"; then
    printf 'test-failure\tnext-version-only\t1\tnone\n'; return 0
  fi

  # 5. Any other builder failure: a real compile/build break in the new version.
  if grep -qiE "builder for '[^']*' failed|make: \*\*\*|error\[E[0-9]+\]:|undefined: |cannot find package" <<<"$text"; then
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/update/test_classify_failure.sh`
Expected: `PASS: test_classify_failure`

- [ ] **Step 5: Commit**

```bash
git add scripts/classify-failure.sh tests/update/test_classify_failure.sh
git commit -m "feat(update): add build-failure classifier"
```

---

### Task 3: Per-package cadence in the manifest

Adds `cadence_hours` to `packages[]` so the branch-HEAD go packages move weekly instead of chasing HEAD daily, and teaches the manifest check to validate it.

**Files:**
- Modify: `overlays/updates.json` (add `cadence_hours` to `c4` and `hey-cli`)
- Modify: `scripts/check-overlay-manifest.sh`
- Test: `tests/update/test_manifest_cadence.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: an optional integer `cadence_hours` on any `packages[]` entry. Absent means daily (24). Read by Task 4 via `pkg_cadence_hours <name>`.

- [ ] **Step 1: Write the failing test**

Create `tests/update/test_manifest_cadence.sh`:

```bash
#!/usr/bin/env bash
# Asserts (a) the real manifest declares weekly cadence for the branch-HEAD go
# packages, and (b) check-overlay-manifest.sh rejects a non-integer or
# non-positive cadence_hours. The check is run against a scratch COPY of the
# repo so the real tree is never mutated.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MANIFEST="$REPO/overlays/updates.json"

fail() { echo "FAIL: $1"; exit 1; }

# --- real manifest: c4 and hey-cli are weekly ------------------------------
for p in c4 hey-cli; do
  got="$(jq -r --arg n "$p" '.packages[] | select(.name==$n) | .cadence_hours // "unset"' "$MANIFEST")"
  [[ "$got" == "168" ]] || fail "$p cadence_hours is '$got', expected 168"
done

# --- real manifest still passes the check ---------------------------------
bash "$REPO/scripts/check-overlay-manifest.sh" "$REPO" >/dev/null \
  || fail "real manifest no longer passes check-overlay-manifest.sh"

# --- a bad cadence is rejected -------------------------------------------
# Copy the repo's tracked files so the check sees a complete, valid tree.
git -C "$REPO" archive HEAD | tar -x -C "$TMP"
reject() { # <jq-filter> <label>
  jq "$1" "$MANIFEST" > "$TMP/overlays/updates.json"
  if bash "$REPO/scripts/check-overlay-manifest.sh" "$TMP" >/dev/null 2>&1; then
    fail "check accepted $2"
  fi
}
reject '(.packages[] | select(.name=="c4") | .cadence_hours) = "weekly"' "a string cadence_hours"
reject '(.packages[] | select(.name=="c4") | .cadence_hours) = 0' "a zero cadence_hours"
reject '(.packages[] | select(.name=="c4") | .cadence_hours) = -5' "a negative cadence_hours"
# A NUMERIC STRING is the trap: it interpolates identically to the integer, so
# a bash-regex check on the rendered text accepts it. Must be rejected by type.
reject '(.packages[] | select(.name=="c4") | .cadence_hours) = "168"' "a numeric-string cadence_hours"
reject '(.packages[] | select(.name=="c4") | .cadence_hours) = 24.5' "a fractional cadence_hours"
reject '(.packages[] | select(.name=="c4") | .cadence_hours) = null' "a null cadence_hours"

echo "PASS: test_manifest_cadence"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/update/test_manifest_cadence.sh`
Expected: FAIL — `c4 cadence_hours is 'unset', expected 168`

- [ ] **Step 3: Add the cadences to the manifest**

```bash
python3 - <<'PYEOF'
import json, collections
p = "overlays/updates.json"
with open(p) as f:
    data = json.load(f, object_pairs_hook=collections.OrderedDict)
for pkg in data["packages"]:
    if pkg["name"] in ("c4", "hey-cli"):
        pkg["cadence_hours"] = 168
        pkg["notes"] = pkg.get("notes", "") + (
            " Weekly cadence: tracks a branch with no releases, so a daily bump "
            "would chase HEAD with no release gate."
        )
with open(p, "w") as f:
    # ensure_ascii=False is required: without it Python re-escapes the em-dashes
    # and arrows already present in several notes fields into \uXXXX, producing a
    # large spurious diff across packages this change never touched.
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYEOF
```

Verify: `jq -r '.packages[] | select(.name=="c4") | .cadence_hours' overlays/updates.json`
Expected: `168`

- [ ] **Step 4: Read the existing check to find the per-package validation loop**

Run: `grep -n 'packages\[\]' scripts/check-overlay-manifest.sh`

Note the loop that iterates packages and the `fail`/error-reporting helper it uses; the next step must reuse that helper rather than inventing a second error path.

- [ ] **Step 5: Add cadence validation to `scripts/check-overlay-manifest.sh`**

Append this block immediately before the script's final exit/summary, adapting `fail` to whatever the script's existing error helper is named:

```bash
# cadence_hours, when present, must be a positive integer. An absent value means
# "daily" (the default in scripts/update-probe.sh). A malformed one would
# silently disable bumping for that package, so it is a hard error.
# Validate the JSON TYPE in jq, not the rendered text in bash: `"168"` as a
# string interpolates identically to the integer 168, so a bash regex on
# \(.cadence_hours) silently accepts it. This mirrors the existing inputs{}
# cadence check above, which already uses type=="number".
while IFS=$'\t' read -r name cadence; do
  [[ -z "$name" ]] && continue
  err "package '$name' has invalid cadence_hours '$cadence' (want a positive integer)"
done < <(jq -r '
  .packages[]
  | select(has("cadence_hours"))
  | select(
      (.cadence_hours | type) != "number"
      or .cadence_hours <= 0
      or (.cadence_hours | floor) != .cadence_hours
    )
  | "\(.name)\t\(.cadence_hours)"' "$MANIFEST")
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash tests/update/test_manifest_cadence.sh`
Expected: `PASS: test_manifest_cadence`

- [ ] **Step 7: Verify the real check and the full suite**

Run: `bash scripts/check-overlay-manifest.sh . && bash tests/update/run.sh`
Expected: the check exits 0, suite ends `ALL PASS`

- [ ] **Step 8: Commit**

```bash
git add overlays/updates.json scripts/check-overlay-manifest.sh tests/update/test_manifest_cadence.sh
git commit -m "feat(update): add per-package cadence_hours to the overlay manifest"
```

---

### Task 4: Quarantine-aware, cadence-aware `bump-overlays`

Teaches the bumper to skip quarantined versions, honour per-package cadence, record classified failures, and clear entries on success. This is what makes "only gate what breaks" real.

**Files:**
- Modify: `apps/aarch64-darwin/bump-overlays` (check `ls apps/*/bump-overlays` and mirror to every copy)
- Test: `tests/update/test_bump_quarantine.sh`

**Interfaces:**
- Consumes: `quarantine_init`, `quarantine_is_blocked`, `quarantine_record`, `quarantine_clear`, `quarantine_field` (Task 1); `classify_failure` (Task 2); `state_get_overlay_bumped_at`/`state_set_overlay_bumped_at` (added below).
- Produces:
  - `pkg_cadence_hours <name>` → prints the package's cadence in hours (default `24`).
  - `cadence_due <name>` → exit 0 if the package's cadence window has elapsed.
  - `record_bump_failure <name> <new_version> <phase> <logfile>` → classifies and writes a ledger entry; prints the fingerprint.
  - Two new `SKIPPED_REASONS` strings: `quarantined: <fingerprint> blocks <version>` and `cadence: next attempt in <N>h`.
  - New exit-code semantics: unchanged (0/1/2/3).

- [ ] **Step 1: Write the failing test**

Create `tests/update/test_bump_quarantine.sh`:

```bash
#!/usr/bin/env bash
# Exercises bump-overlays' quarantine + cadence gating without any real
# network, nix build, or commit against this checkout.
#
# Isolation strategy (same shape as tests/update/test_bump_mechanical_only.sh):
#   - a scratch git repo stands in for the flake dir, holding a copy of the
#     real scripts/ and apps/ plus a two-package manifest;
#   - `nix` is stubbed: `registry list` fails closed so locate_flake() falls
#     back to `git rev-parse --show-toplevel` (the scratch repo), and
#     `nix build` is stubbed per-case to succeed or fail;
#   - `curl` is stubbed to report a specific "latest" version per package;
#   - fix-hashes is stubbed to a no-op success.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
REAL_NIX="$(command -v nix)"
fail() { echo "FAIL: $1"; exit 1; }

setup_repo() { # -> prints scratch repo path
  local d; d="$(mktemp -d)"
  mkdir -p "$d/overlays" "$d/scripts" "$d/apps/aarch64-darwin" "$d/logs"
  cp "$REPO/scripts/quarantine.sh" "$REPO/scripts/update-state.sh" \
     "$REPO/scripts/classify-failure.sh" "$REPO/scripts/update-probe.sh" \
     "$REPO/scripts/update-notify.sh" "$d/scripts/"
  cp "$REPO/apps/aarch64-darwin/_common.sh" "$REPO/apps/aarch64-darwin/bump-overlays" \
     "$d/apps/aarch64-darwin/"
  # A stub fix-hashes that always succeeds without touching anything.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/apps/aarch64-darwin/fix-hashes"
  chmod +x "$d/apps/aarch64-darwin/fix-hashes"
  # Minimal single-package manifest + overlay.
  cat > "$d/overlays/updates.json" <<'EOF'
{
  "packages": [
    {
      "name": "demo",
      "overlay": "overlays/99-demo.nix",
      "current_version": "1.0.0",
      "check": { "method": "github-release", "repo": "demo/demo" },
      "update_type": "prebuilt-binary",
      "platforms": { "aarch64-darwin": { "url_template": "https://example.com/demo-{version}.tar.gz" } }
    }
  ],
  "skip": [],
  "inputs": {},
  "pinned_inputs": []
}
EOF
  cat > "$d/overlays/99-demo.nix" <<'EOF'
_final: _prev: {
  demo = { version = "1.0.0"; };
}
EOF
  printf '{"comment":"test","entries":[]}\n' > "$d/overlays/quarantine.json"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name Test
  git -C "$d" add -A
  git -C "$d" commit -qm init
  printf '%s' "$d"
}

# Stubs: curl reports `latest`, nix build succeeds or fails per $3.
setup_stubs() { # <stub-dir> <latest-version> <build-outcome ok|broken>
  local stub="$1" latest="$2" outcome="$3"
  cat > "$stub/curl" <<EOF
#!/usr/bin/env bash
printf '{"tag_name":"v%s"}' "$latest"
EOF
  if [[ "$outcome" == "ok" ]]; then
    cat > "$stub/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "registry list") exit 1 ;;
  "build "*|"build") exit 0 ;;
esac
case "\$1" in
  build) exit 0 ;;
  hash) exec "$REAL_NIX" "\$@" ;;
  *) exec "$REAL_NIX" "\$@" ;;
esac
EOF
  else
    cat > "$stub/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "registry list") exit 1 ;;
esac
case "\$1" in
  build) echo "error: builder for '/nix/store/x-demo.drv' failed with exit code 1" >&2; exit 1 ;;
  hash) exec "$REAL_NIX" "\$@" ;;
  *) exec "$REAL_NIX" "\$@" ;;
esac
EOF
  fi
  cat > "$stub/nix-prefetch-url" <<'EOF'
#!/usr/bin/env bash
echo "0000000000000000000000000000000000000000000000000000"
EOF
  chmod +x "$stub/curl" "$stub/nix" "$stub/nix-prefetch-url"
}

# === Case 1: a failing bump writes a classified quarantine entry ============
d="$(setup_repo)"; stub="$(mktemp -d)"
setup_stubs "$stub" "1.1.0" "broken"
( cd "$d" && PATH="$stub:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
    bash apps/aarch64-darwin/bump-overlays --no-public-sync >"$d/out.log" 2>&1 ) && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case1: expected exit 1 on failed bump, got $rc"
got_ver="$(jq -r '.entries[] | select(.name=="demo") | .blocked_version' "$d/overlays/quarantine.json")"
[[ "$got_ver" == "1.1.0" ]] || fail "case1: blocked_version is '$got_ver', expected 1.1.0"
got_fp="$(jq -r '.entries[] | select(.name=="demo") | .fingerprint' "$d/overlays/quarantine.json")"
[[ "$got_fp" == "compile-failure" ]] || fail "case1: fingerprint is '$got_fp', expected compile-failure"
got_good="$(jq -r '.entries[] | select(.name=="demo") | .known_good_version' "$d/overlays/quarantine.json")"
[[ "$got_good" == "1.0.0" ]] || fail "case1: known_good_version is '$got_good', expected 1.0.0"
rm -rf "$d" "$stub"

# === Case 2: a quarantined version is skipped, not retried =================
d="$(setup_repo)"; stub="$(mktemp -d)"
setup_stubs "$stub" "1.1.0" "broken"
jq '.entries = [{name:"demo",kind:"overlay",blocked_version:"1.1.0",
  known_good_version:"1.0.0",first_failed:"2026-01-01T00:00:00Z",
  last_attempt:"2026-01-01T00:00:00Z",attempts:1,phase:"package-build",
  fingerprint:"compile-failure",error_excerpt:"x",retry_policy:"next-version-only"}]' \
  "$d/overlays/quarantine.json" > "$d/q" && mv "$d/q" "$d/overlays/quarantine.json"
# nix build must never be reached; make it fatal if it is.
cat > "$stub/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "registry list") exit 1 ;; esac
case "\$1" in
  build) echo "FATAL: build attempted on a quarantined version" >&2; exit 99 ;;
  *) exec "$REAL_NIX" "\$@" ;;
esac
EOF
chmod +x "$stub/nix"
( cd "$d" && PATH="$stub:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
    bash apps/aarch64-darwin/bump-overlays --no-public-sync >"$d/out.log" 2>&1 ) && rc=0 || rc=$?
grep -qi "quarantined" "$d/out.log" || { cat "$d/out.log"; fail "case2: no 'quarantined' skip reason reported"; }
grep -q "FATAL" "$d/out.log" && fail "case2: build was attempted on a quarantined version"
[[ $rc -eq 0 ]] || fail "case2: a skipped-because-quarantined run must exit 0, got $rc"
rm -rf "$d" "$stub"

# === Case 3: a NEWER version than the quarantined one is attempted =========
d="$(setup_repo)"; stub="$(mktemp -d)"
setup_stubs "$stub" "1.2.0" "ok"
jq '.entries = [{name:"demo",kind:"overlay",blocked_version:"1.1.0",
  known_good_version:"1.0.0",first_failed:"2026-01-01T00:00:00Z",
  last_attempt:"2026-01-01T00:00:00Z",attempts:1,phase:"package-build",
  fingerprint:"compile-failure",error_excerpt:"x",retry_policy:"next-version-only"}]' \
  "$d/overlays/quarantine.json" > "$d/q" && mv "$d/q" "$d/overlays/quarantine.json"
( cd "$d" && PATH="$stub:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
    bash apps/aarch64-darwin/bump-overlays --no-public-sync >"$d/out.log" 2>&1 ) && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/out.log"; fail "case3: expected exit 0, got $rc"; }
[[ "$(jq -r '.packages[0].current_version' "$d/overlays/updates.json")" == "1.2.0" ]] \
  || fail "case3: manifest not bumped to 1.2.0"
# A successful bump must clear the stale entry.
[[ "$(jq '.entries | length' "$d/overlays/quarantine.json")" == "0" ]] \
  || fail "case3: successful bump did not clear the quarantine entry"
rm -rf "$d" "$stub"

# === Case 4: a frozen entry blocks every version ==========================
d="$(setup_repo)"; stub="$(mktemp -d)"
setup_stubs "$stub" "9.9.9" "ok"
jq '.entries = [{name:"demo",kind:"overlay",blocked_version:"1.1.0",
  known_good_version:"1.0.0",first_failed:"2026-01-01T00:00:00Z",
  last_attempt:"2026-01-01T00:00:00Z",attempts:3,phase:"package-build",
  fingerprint:"compile-failure",error_excerpt:"x",retry_policy:"frozen"}]' \
  "$d/overlays/quarantine.json" > "$d/q" && mv "$d/q" "$d/overlays/quarantine.json"
( cd "$d" && PATH="$stub:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
    bash apps/aarch64-darwin/bump-overlays --no-public-sync >"$d/out.log" 2>&1 ) || true
[[ "$(jq -r '.packages[0].current_version' "$d/overlays/updates.json")" == "1.0.0" ]] \
  || fail "case4: frozen entry did not block the bump"
rm -rf "$d" "$stub"

# === Case 5: cadence gating defers an out-of-window package ==============
d="$(setup_repo)"; stub="$(mktemp -d)"
setup_stubs "$stub" "1.1.0" "ok"
jq '(.packages[0].cadence_hours) = 168' "$d/overlays/updates.json" > "$d/m" \
  && mv "$d/m" "$d/overlays/updates.json"
printf '{"overlays":{"demo":{"bumped_at":"%s"}},"inputs":{},"last_gate":null}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$d/.state.json"
( cd "$d" && PATH="$stub:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
    bash apps/aarch64-darwin/bump-overlays --no-public-sync >"$d/out.log" 2>&1 ) || true
grep -qi "cadence" "$d/out.log" || { cat "$d/out.log"; fail "case5: no cadence skip reason"; }
[[ "$(jq -r '.packages[0].current_version' "$d/overlays/updates.json")" == "1.0.0" ]] \
  || fail "case5: cadence did not defer the bump"
rm -rf "$d" "$stub"

echo "PASS: test_bump_quarantine"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/update/test_bump_quarantine.sh`
Expected: FAIL at case 1 — `blocked_version is '', expected 1.1.0` (nothing writes the ledger yet)

- [ ] **Step 3: Add the state helpers for per-package bump timestamps**

Append to `scripts/update-state.sh`, next to the existing `state_get_overlay_known_latest`:

```bash
# Last time a bump was ATTEMPTED for this package (success or failure). Drives
# per-package cadence gating in bump-overlays. Distinct from
# state_set_overlay's known_latest, which records what upstream is offering.
state_get_overlay_bumped_at() {
  _state_readable || { printf ''; return 0; }
  jq -r --arg n "$1" '.overlays[$n].bumped_at // empty' "$(_state_file)"
}
state_set_overlay_bumped_at() {
  _state_write --arg n "$1" --arg t "$2" '.overlays[$n].bumped_at = $t'
}
```

- [ ] **Step 4: Source the new helpers in `bump-overlays`**

In `apps/aarch64-darwin/bump-overlays`, after the existing `source "$FLAKE_DIR/scripts/update-state.sh"` line (near line 21), add:

```bash
# shellcheck source=/dev/null
source "$FLAKE_DIR/scripts/quarantine.sh"
# shellcheck source=/dev/null
source "$FLAKE_DIR/scripts/classify-failure.sh"
```

- [ ] **Step 5: Add the cadence and failure-recording helpers**

Insert into `apps/aarch64-darwin/bump-overlays` immediately before the `# Precondition: never mix with in-progress manual edits.` block:

```bash
# Per-package cadence. Absent cadence_hours means daily. c4/hey-cli declare 168
# because they track a branch with no releases — a daily bump would chase HEAD.
pkg_cadence_hours() { # <name>
  local h
  h="$(jq -r --arg n "$1" '.packages[] | select(.name==$n) | .cadence_hours // 24' "$MANIFEST")"
  [[ "$h" =~ ^[0-9]+$ ]] || h=24
  printf '%s' "$h"
}

# Exit 0 if this package's cadence window has elapsed since the last attempt.
cadence_due() { # <name>
  local name="$1" hours last
  hours="$(pkg_cadence_hours "$name")"
  last="$(state_get_overlay_bumped_at "$name")"
  [[ -z "$last" ]] && return 0
  python3 - "$last" "$hours" <<'PYEOF'
import sys, datetime
last, hours = sys.argv[1], float(sys.argv[2])
try:
    t = datetime.datetime.strptime(last, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
except ValueError:
    sys.exit(0)   # unparseable -> treat as due
due = (datetime.datetime.now(datetime.timezone.utc) - t).total_seconds() >= hours * 3600
sys.exit(0 if due else 1)
PYEOF
}

# Hours remaining before <name> is due again (for the skip message).
cadence_remaining_hours() { # <name>
  local last hours
  last="$(state_get_overlay_bumped_at "$1")"
  hours="$(pkg_cadence_hours "$1")"
  python3 - "$last" "$hours" <<'PYEOF'
import sys, datetime, math
last, hours = sys.argv[1], float(sys.argv[2])
try:
    t = datetime.datetime.strptime(last, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
except ValueError:
    print(0); sys.exit(0)
left = hours * 3600 - (datetime.datetime.now(datetime.timezone.utc) - t).total_seconds()
print(max(0, math.ceil(left / 3600)))
PYEOF
}

# Classify a failed bump and write it to the ledger. Prints the fingerprint so
# the caller can report it. `phase` is one of the spec §2 phase values.
record_bump_failure() { # <name> <new_version> <phase> <logfile>
  local name="$1" new_version="$2" phase="$3" log="$4"
  local fp policy escalate remediation current
  IFS=$'\t' read -r fp policy escalate remediation < <(classify_failure "$log")
  current="$(jq -r --arg n "$name" '.packages[] | select(.name==$n) | .current_version' "$MANIFEST")"
  quarantine_record "$name" "overlay" "$new_version" "$current" "$phase" \
    "$fp" "$policy" "$(tail -40 "$log" 2>/dev/null)"
  printf '%s' "$fp"
}
```

- [ ] **Step 6: Initialise the ledger next to `state_init`**

In `apps/aarch64-darwin/bump-overlays`, change the existing line:

```bash
state_init
```

to:

```bash
state_init
quarantine_init
```

- [ ] **Step 7: Add quarantine + cadence gating to the detection loop**

In `apps/aarch64-darwin/bump-overlays`, inside the `while IFS=$'\t' read -r name latest; do` loop, immediately after the `if [[ -n "$ONLY" ]] ... fi` block and before the `update_type=` assignment, insert:

```bash
  # Quarantine gate: skip exactly the versions known to fail. An entry blocks
  # its own blocked_version (or every version, when frozen), so anything newer
  # is attempted automatically — the self-healing property in spec §2.
  # --only <pkg> is an explicit human override and bypasses this.
  if [[ -z "$ONLY" ]] && quarantine_is_blocked "$name" "$latest"; then
    SKIPPED_NAMES+=("$name")
    SKIPPED_REASONS+=("quarantined: $(quarantine_field "$name" fingerprint) blocks $latest")
    continue
  fi

  # Cadence gate: c4/hey-cli track a branch with no releases and would
  # otherwise be bumped every single day. Also bypassed by --only.
  if [[ -z "$ONLY" ]] && ! cadence_due "$name"; then
    SKIPPED_NAMES+=("$name")
    SKIPPED_REASONS+=("cadence: next attempt in $(cadence_remaining_hours "$name")h")
    continue
  fi
```

- [ ] **Step 8: Record failures and clear successes in the bump loops**

In `apps/aarch64-darwin/bump-overlays`, replace the two dispatch loops (currently `for i in "${!MECH_NAMES[@]}"` and `for name in "${GOSRC_NAMES_TARGET[@]}"`) with:

```bash
mkdir -p "$FLAKE_DIR/logs"
for i in "${!MECH_NAMES[@]}"; do
  name="${MECH_NAMES[$i]}"; new_version="${MECH_VERSIONS[$i]}"
  # Record the attempt regardless of outcome, so cadence advances even on
  # failure and a broken package cannot be retried every few minutes.
  state_set_overlay_bumped_at "$name" "$(now_iso)"
  # Per-package log under logs/ (gitignored), NOT mktemp: scheduled-check's
  # escalation step reads logs/bump-<name>.log to build the brief, and a
  # per-package log is the difference between a precise brief and dumping the
  # whole run log at the model.
  bump_log="$FLAKE_DIR/logs/bump-${name}.log"
  if declare -F bump_mechanical >/dev/null && bump_mechanical "$name" "$new_version" >"$bump_log" 2>&1; then
    cat "$bump_log"
    BUMPED+=("$name")
    quarantine_clear "$name"
  else
    FAILED+=("$name")
    fp="$(record_bump_failure "$name" "$new_version" "package-build" "$bump_log")"
    err "  quarantined $name@$new_version as '$fp'"
  fi
done
for name in "${GOSRC_NAMES_TARGET[@]}"; do
  state_set_overlay_bumped_at "$name" "$(now_iso)"
  new_version="$(jq -r --arg n "$name" '.packages[] | select(.name==$n) | .current_version' "$MANIFEST")"
  bump_log="$FLAKE_DIR/logs/bump-${name}.log"
  if declare -F bump_gosource >/dev/null && bump_gosource "$name" >"$bump_log" 2>&1; then
    cat "$bump_log"
    BUMPED+=("$name")
    quarantine_clear "$name"
  else
    FAILED+=("$name")
    fp="$(record_bump_failure "$name" "$new_version" "package-build" "$bump_log")"
    err "  quarantined $name as '$fp'"
  fi
done
```

Note the removed `rm -f "$bump_log"`: these logs are deliberately kept for the escalation brief. `logs/*` is gitignored and `scheduled-check` truncates its own logs each run, so they do not accumulate meaningfully.

**Note on the redirect-then-`cat` form:** deliberately not `| tee`. Piping would run `bump_mechanical` in a subshell, and its exit status would come from `tee` unless `pipefail` semantics happen to line up. Redirecting to the log and `cat`-ing it afterwards keeps the function in the current shell and makes its `return 1` the value the `if` tests. Do not "simplify" this back to a pipeline.

- [ ] **Step 9: Run the test to verify it passes**

Run: `bash tests/update/test_bump_quarantine.sh`
Expected: `PASS: test_bump_quarantine`

- [ ] **Step 10: Mirror the change to any other system's copy**

Run: `ls apps/*/bump-overlays`

For every path other than `apps/aarch64-darwin/bump-overlays`, apply the identical edits from Steps 4–8. Verify they are byte-identical:

Run: `for f in apps/*/bump-overlays; do md5 -q "$f"; done | sort -u | wc -l`
Expected: `1`

- [ ] **Step 11: Run the full suite**

Run: `bash tests/update/run.sh`
Expected: final line `ALL PASS`

- [ ] **Step 12: Commit**

```bash
git add apps/*/bump-overlays scripts/update-state.sh tests/update/test_bump_quarantine.sh
git commit -m "feat(update): gate overlay bumps on quarantine and per-package cadence"
```

---

### Task 5: Post-activation health check

The gate that decides whether an activated generation is kept or rolled back. Version-matching, not just exit-0, is the point.

**Files:**
- Create: `overlays/health-checks.json`
- Create: `scripts/post-activate-health.sh`
- Modify: `scripts/check-overlay-manifest.sh`
- Test: `tests/update/test_health_check.sh`

**Interfaces:**
- Consumes: `overlays/updates.json` `current_version` values.
- Produces: `bash scripts/post-activate-health.sh [--manifest <path>] [--assertions <path>]` → exit 0 all green, 1 any failure; prints one `OK:`/`FAIL:` line per assertion and a `FAILED: <n>` summary to stderr.
- Produces: `overlays/health-checks.json` schema —
  ```json
  { "assertions": [ { "package": "...", "command": "...", "version_regex": "...", "timeout": 20 },
                    { "package": "...", "skip": "reason" } ],
    "agents": [ "label", ... ] }
  ```

- [ ] **Step 1: Write the failing test**

Create `tests/update/test_health_check.sh`:

```bash
#!/usr/bin/env bash
# Drives scripts/post-activate-health.sh against synthetic assertion files and
# stub binaries, so no real system state is inspected.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
STUB="$TMP/bin"; mkdir -p "$STUB"
fail() { echo "FAIL: $1"; exit 1; }

cat > "$TMP/manifest.json" <<'EOF'
{ "packages": [ { "name": "demo", "current_version": "1.2.3" } ], "skip": [] }
EOF

# demo prints a matching version; brokendemo prints a stale one; hangdemo hangs.
printf '#!/usr/bin/env bash\necho "demo 1.2.3"\n' > "$STUB/demo"
printf '#!/usr/bin/env bash\necho "demo 0.9.0"\n' > "$STUB/brokendemo"
printf '#!/usr/bin/env bash\nsleep 30\n' > "$STUB/hangdemo"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/launchctl"
chmod +x "$STUB"/*

run_health() { # <assertions-json>
  printf '%s' "$1" > "$TMP/assert.json"
  PATH="$STUB:$PATH" bash "$REPO/scripts/post-activate-health.sh" \
    --manifest "$TMP/manifest.json" --assertions "$TMP/assert.json" >"$TMP/out" 2>&1
}

# --- matching version passes ---------------------------------------------
run_health '{"assertions":[{"package":"demo","command":"demo --version","version_regex":"([0-9]+\\.[0-9]+\\.[0-9]+)","timeout":10}],"agents":[]}' \
  || { cat "$TMP/out"; fail "matching version did not pass"; }
grep -q "OK: demo" "$TMP/out" || fail "no OK line for demo"

# --- WRONG version fails (the whole point) -------------------------------
if run_health '{"assertions":[{"package":"demo","command":"brokendemo --version","version_regex":"([0-9]+\\.[0-9]+\\.[0-9]+)","timeout":10}],"agents":[]}'; then
  cat "$TMP/out"; fail "stale version was accepted"
fi
grep -q "FAIL: demo" "$TMP/out" || fail "no FAIL line for stale version"
grep -q "0.9.0" "$TMP/out" || fail "failure message omits the observed version"

# --- a missing binary fails ---------------------------------------------
if run_health '{"assertions":[{"package":"demo","command":"nosuchbinary --version","version_regex":"([0-9]+)","timeout":10}],"agents":[]}'; then
  fail "missing binary was accepted"
fi

# --- a hanging command is killed by the timeout and fails ---------------
start=$(date +%s)
if run_health '{"assertions":[{"package":"demo","command":"hangdemo","version_regex":"([0-9]+)","timeout":2}],"agents":[]}'; then
  fail "hanging command was accepted"
fi
elapsed=$(( $(date +%s) - start ))
[[ $elapsed -lt 15 ]] || fail "timeout not enforced (took ${elapsed}s)"

# --- a skip entry is reported but does not fail -------------------------
run_health '{"assertions":[{"package":"demo","skip":"python library, no CLI"}],"agents":[]}' \
  || { cat "$TMP/out"; fail "skip entry caused a failure"; }
grep -qi "skip" "$TMP/out" || fail "skip not reported"

# --- an unloaded launchd agent fails -----------------------------------
printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/launchctl"; chmod +x "$STUB/launchctl"
if run_health '{"assertions":[],"agents":["com.example.missing"]}'; then
  fail "unloaded agent was accepted"
fi
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/launchctl"; chmod +x "$STUB/launchctl"
run_health '{"assertions":[],"agents":["com.example.present"]}' \
  || fail "loaded agent was rejected"

# --- every pinned package in the REAL manifest has an assertion or a skip
missing=""
while read -r p; do
  [[ -z "$p" ]] && continue
  has="$(jq -r --arg n "$p" '[.assertions[] | select(.package==$n)] | length' "$REPO/overlays/health-checks.json")"
  [[ "$has" == "0" ]] && missing="$missing $p"
done < <(jq -r '.packages[].name' "$REPO/overlays/updates.json")
[[ -z "$missing" ]] || fail "packages with no health assertion:$missing"

echo "PASS: test_health_check"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/update/test_health_check.sh`
Expected: FAIL — `scripts/post-activate-health.sh: No such file or directory`

- [ ] **Step 3: Write the assertions file**

Create `overlays/health-checks.json`. Every package in `overlays/updates.json` `packages[]` needs an entry — either a `command`+`version_regex`, or a `skip` with a reason:

```json
{
  "comment": "Post-activation smoke assertions (spec §3). Every packages[] entry in overlays/updates.json must appear here, with either a command+version_regex or a skip reason — enforced by scripts/check-overlay-manifest.sh. The version_regex must capture a version comparable to that package's current_version; matching the VERSION (not just exit 0) is what catches a silently-wrong binary.",
  "assertions": [
    { "package": "claude-code",  "command": "claude --version",       "version_regex": "([0-9]+\\.[0-9]+\\.[0-9]+)", "timeout": 30 },
    { "package": "codex-openai", "command": "codex --version",        "version_regex": "([0-9]+\\.[0-9]+\\.[0-9]+)", "timeout": 20 },
    { "package": "trailbase",    "command": "trail --version",        "version_regex": "([0-9]+\\.[0-9]+\\.[0-9]+)", "timeout": 20 },
    { "package": "igir",         "command": "igir --version",         "version_regex": "([0-9]+\\.[0-9]+\\.[0-9]+)", "timeout": 30 },
    { "package": "uv",           "command": "uv --version",           "version_regex": "([0-9]+\\.[0-9]+\\.[0-9]+)", "timeout": 20 },
    { "package": "mise",         "command": "mise --version",         "version_regex": "([0-9]+\\.[0-9]+\\.[0-9]+)", "timeout": 20 },
    { "package": "beads",        "command": "bd --version",           "version_regex": "([0-9]+\\.[0-9]+\\.[0-9]+)", "timeout": 20 },
    { "package": "go",           "command": "go version",             "version_regex": "go([0-9]+\\.[0-9]+\\.[0-9]+)", "timeout": 20 },
    { "package": "yt-dlp",       "command": "yt-dlp --version",       "version_regex": "([0-9]{4}\\.[0-9]{2}\\.[0-9]{2})", "timeout": 30 },
    { "package": "yt-dlp-ejs",   "skip": "Python library bundled into yt-dlp; no CLI entrypoint of its own" },
    { "package": "ngrok",        "command": "ngrok version",          "version_regex": "([0-9]+\\.[0-9]+\\.[0-9]+)", "timeout": 20 },
    { "package": "c4",           "command": "c4 --help",              "version_regex": "(c4)", "timeout": 20 },
    { "package": "hey-cli",      "command": "hey --version",          "version_regex": "(.+)", "timeout": 20 },
    { "package": "tmux",         "command": "tmux -V",                "version_regex": "([0-9]+\\.[0-9]+[a-z]?)", "timeout": 20 },
    { "package": "aws-cdk-cli",  "command": "cdk --version",          "version_regex": "([0-9]+\\.[0-9]+\\.[0-9]+)", "timeout": 60 },
    { "package": "dcg",          "command": "dcg --version",          "version_regex": "([0-9]+\\.[0-9]+\\.[0-9]+)", "timeout": 20 }
  ],
  "agents": [
    "nixos-auto-update"
  ]
}
```

**Verify each command and regex against the live system before trusting them** — some tools print a version in an unexpected shape:

```bash
for c in "claude --version" "codex --version" "trail --version" "igir --version" \
         "uv --version" "mise --version" "bd --version" "go version" \
         "yt-dlp --version" "ngrok version" "hey --version" "tmux -V" \
         "cdk --version" "dcg --version"; do
  printf '%-22s -> ' "$c"; timeout 60 $c 2>&1 | head -1
done
```

Adjust any `command` or `version_regex` that does not match the observed output, and use a `skip` entry with a reason for anything not installed on this host. `c4` and `hey-cli` use a loose regex deliberately: their `current_version` is a `0-unstable-<date>` string that no binary reports, so the assertion can only prove the binary runs.

- [ ] **Step 4: Write the health-check script**

Create `scripts/post-activate-health.sh`:

```bash
#!/usr/bin/env bash
# Post-activation smoke check (spec §3). Exit 0 = keep this generation,
# exit 1 = the caller should roll back.
#
# The load-bearing assertion is the VERSION COMPARISON, not exit status: an
# overlay that silently pins the wrong artifact still produces a binary that
# runs fine, and only a version match catches it.
#
# Deliberately does NOT re-run `nix flake check` — that already gated the build.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO/overlays/updates.json"
ASSERTIONS="$REPO/overlays/health-checks.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)   MANIFEST="$2"; shift 2 ;;
    --assertions) ASSERTIONS="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

failures=0

# ── Package version assertions ─────────────────────────────────────────────
while IFS=$'\t' read -r pkg cmd regex tmo skip; do
  [[ -z "$pkg" ]] && continue

  if [[ -n "$skip" && "$skip" != "null" ]]; then
    echo "SKIP: $pkg ($skip)"
    continue
  fi

  expected="$(jq -r --arg n "$pkg" '.packages[] | select(.name==$n) | .current_version' "$MANIFEST")"
  # `timeout` comes from coreutils, which is in this config's systemPackages.
  # Without it a wedged binary would hang the whole daily run.
  out="$(timeout "${tmo:-20}" bash -c "$cmd" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "FAIL: $pkg — '$cmd' exited $rc: $(printf '%s' "$out" | head -1)" >&2
    failures=$((failures + 1))
    continue
  fi

  observed="$(printf '%s' "$out" | grep -oE "$regex" | head -1)"
  if [[ -z "$observed" ]]; then
    echo "FAIL: $pkg — version_regex matched nothing in: $(printf '%s' "$out" | head -1)" >&2
    failures=$((failures + 1))
    continue
  fi

  # A loose regex (c4/hey-cli, whose current_version is a 0-unstable-<date>
  # string no binary reports) can only prove the binary runs. Treat a
  # non-version-shaped expectation as "ran successfully is enough".
  if [[ "$expected" == 0-unstable-* ]]; then
    echo "OK: $pkg (runs; version not self-reported)"
    continue
  fi

  if [[ "$observed" != *"$expected"* && "$expected" != *"$observed"* ]]; then
    echo "FAIL: $pkg — expected version '$expected', binary reports '$observed'" >&2
    failures=$((failures + 1))
    continue
  fi

  echo "OK: $pkg ($observed)"
done < <(jq -r '.assertions[] | [.package, (.command // ""), (.version_regex // ""), (.timeout // 20), (.skip // "")] | @tsv' "$ASSERTIONS")

# ── launchd agents/daemons ────────────────────────────────────────────────
# `launchctl list <label>` exits non-zero when the label is not loaded, which
# is exactly the "activation unloaded my agent and never brought it back" case.
while read -r label; do
  [[ -z "$label" ]] && continue
  if launchctl list "$label" >/dev/null 2>&1; then
    echo "OK: launchd $label loaded"
  else
    echo "FAIL: launchd $label not loaded" >&2
    failures=$((failures + 1))
  fi
done < <(jq -r '.agents[]?' "$ASSERTIONS")

if [[ $failures -gt 0 ]]; then
  echo "FAILED: $failures health assertion(s)" >&2
  exit 1
fi
echo "health: all assertions passed"
```

- [ ] **Step 5: Enforce assertion coverage in the manifest check**

Append to `scripts/check-overlay-manifest.sh`, before its final exit, adapting `fail` to the script's existing error helper and `$1`-derived repo root:

```bash
# Every pinned package must have a health assertion (or an explicit skip), so
# adding a package to the manifest cannot silently ship without a smoke test.
HEALTH="$REPO/overlays/health-checks.json"
if [[ ! -f "$HEALTH" ]]; then
  fail "overlays/health-checks.json is missing"
else
  jq empty "$HEALTH" 2>/dev/null || fail "overlays/health-checks.json is not valid JSON"
  while read -r name; do
    [[ -z "$name" ]] && continue
    n="$(jq -r --arg n "$name" '[.assertions[] | select(.package==$n)] | length' "$HEALTH")"
    if [[ "$n" == "0" ]]; then
      fail "package '$name' has no entry in overlays/health-checks.json (add a command+version_regex, or a skip with a reason)"
    fi
  done < <(jq -r '.packages[].name' "$MANIFEST")
  # And no assertion may name a package that is not pinned.
  while read -r name; do
    [[ -z "$name" ]] && continue
    n="$(jq -r --arg n "$name" '[.packages[] | select(.name==$n)] | length' "$MANIFEST")"
    if [[ "$n" == "0" ]]; then
      fail "health-checks.json references unknown package '$name'"
    fi
  done < <(jq -r '.assertions[].package' "$HEALTH")
fi
```

**Note:** `$REPO` may be named differently in that script (it takes the tree root as `$1`). Check with `head -30 scripts/check-overlay-manifest.sh` and use the existing variable.

- [ ] **Step 6: Run the tests**

Run: `bash tests/update/test_health_check.sh`
Expected: `PASS: test_health_check`

Run: `bash scripts/check-overlay-manifest.sh .`
Expected: exits 0

- [ ] **Step 7: Run the health check for real**

Run: `bash scripts/post-activate-health.sh`
Expected: an `OK:` line per package and `health: all assertions passed`. The `nixos-auto-update` agent does not exist yet, so a `FAIL: launchd nixos-auto-update not loaded` is expected at this point — temporarily empty the `agents` array to confirm everything else is green, then restore it.

- [ ] **Step 8: Run the full suite and commit**

Run: `bash tests/update/run.sh`
Expected: `ALL PASS`

```bash
git add overlays/health-checks.json scripts/post-activate-health.sh \
        scripts/check-overlay-manifest.sh tests/update/test_health_check.sh
git commit -m "feat(update): add post-activation health check with version assertions"
```

---

### Task 6: Claude escalation wrapper and repair skill

The token-spending half. The contract: Claude edits in a throwaway worktree, the *wrapper* verifies and commits.

**Files:**
- Create: `scripts/escalate.sh`
- Create: `.claude/skills/overlay-repair/SKILL.md`
- Test: `tests/update/test_escalate.sh`

**Interfaces:**
- Consumes: `quarantine_should_escalate`, `quarantine_set_escalation`, `quarantine_field` (Task 1); `classify_failure` (Task 2).
- Produces: `bash scripts/escalate.sh --package <name> --version <ver> --phase <phase> --log <logfile> [--max-turns N] [--timeout S]` →
  exit `0` a verified fix was committed, `1` gave up, `2` skipped by dedup/budget.
  Honours `ESCALATE_CLAUDE_BIN` (default `claude`) so tests can stub it, and `ESCALATE_MAX_PER_RUN` (default `3`).

- [ ] **Step 1: Write the failing test**

Create `tests/update/test_escalate.sh`:

```bash
#!/usr/bin/env bash
# Exercises scripts/escalate.sh with a STUB claude binary, so no tokens are
# ever spent and no model is invoked. The stub writes a verdict.json (and
# optionally edits the overlay) to simulate each outcome. The verification
# build is stubbed via a fake `nix`.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
REAL_NIX="$(command -v nix)"
fail() { echo "FAIL: $1"; exit 1; }

setup() { # -> scratch repo path
  local d; d="$(mktemp -d)"
  mkdir -p "$d/overlays" "$d/scripts" "$d/logs"
  cp "$REPO/scripts/quarantine.sh" "$REPO/scripts/update-state.sh" \
     "$REPO/scripts/classify-failure.sh" "$REPO/scripts/escalate.sh" "$d/scripts/"
  cat > "$d/overlays/updates.json" <<'EOF'
{ "packages": [ { "name": "demo", "overlay": "overlays/99-demo.nix",
    "current_version": "1.0.0", "update_type": "prebuilt-binary",
    "check": { "method": "github-release", "repo": "demo/demo" } } ],
  "skip": [] }
EOF
  printf '_final: _prev: { demo = { version = "1.0.0"; }; }\n' > "$d/overlays/99-demo.nix"
  printf '{"comment":"t","entries":[]}\n' > "$d/overlays/quarantine.json"
  printf 'error: builder for /nix/store/x-demo.drv failed with exit code 1\n' > "$d/logs/build.log"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name Test
  git -C "$d" add -A && git -C "$d" commit -qm init
  printf '%s' "$d"
}

# A stub `claude` that edits the overlay and writes a "fixed" verdict.
stub_claude_fixed() { # <stub-dir>
  cat > "$1/claude" <<'EOF'
#!/usr/bin/env bash
# The prompt arrives as the last positional arg; cwd is the worktree.
sed -i.bak 's/1\.0\.0/1.1.0/' overlays/99-demo.nix && rm -f overlays/99-demo.nix.bak
cat > verdict.json <<'JSON'
{"status":"fixed","package":"demo","fingerprint":"compile-failure",
 "verdict":"widened the version bound","files_changed":["overlays/99-demo.nix"]}
JSON
EOF
  chmod +x "$1/claude"
}

stub_claude_gaveup() { # <stub-dir>
  cat > "$1/claude" <<'EOF'
#!/usr/bin/env bash
cat > verdict.json <<'JSON'
{"status":"gave-up","package":"demo","fingerprint":"compile-failure",
 "verdict":"upstream renamed the entrypoint; needs manual review","files_changed":[]}
JSON
EOF
  chmod +x "$1/claude"
}

# A stub claude that LIES: claims fixed but changes nothing that builds.
stub_claude_lies() { # <stub-dir>
  cat > "$1/claude" <<'EOF'
#!/usr/bin/env bash
echo "# cosmetic" >> overlays/99-demo.nix
cat > verdict.json <<'JSON'
{"status":"fixed","package":"demo","fingerprint":"compile-failure",
 "verdict":"definitely fixed, trust me","files_changed":["overlays/99-demo.nix"]}
JSON
EOF
  chmod +x "$1/claude"
}

stub_nix() { # <stub-dir> <ok|broken>
  if [[ "$2" == "ok" ]]; then
    cat > "$1/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "registry list") exit 1 ;; esac
case "\$1" in build) exit 0 ;; *) exec "$REAL_NIX" "\$@" ;; esac
EOF
  else
    cat > "$1/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "registry list") exit 1 ;; esac
case "\$1" in build) echo "error: still broken" >&2; exit 1 ;; *) exec "$REAL_NIX" "\$@" ;; esac
EOF
  fi
  chmod +x "$1/nix"
}

run_escalate() { # <repo> <stub>
  ( cd "$1" && PATH="$2:$PATH" ESCALATE_CLAUDE_BIN="$2/claude" \
      bash scripts/escalate.sh --package demo --version 1.1.0 \
        --phase package-build --log logs/build.log >"$1/esc.log" 2>&1 )
}

# === Case 1: a verified fix is committed ==================================
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_fixed "$stub"; stub_nix "$stub" ok
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/esc.log"; fail "case1: expected exit 0, got $rc"; }
grep -q "1.1.0" "$d/overlays/99-demo.nix" || fail "case1: fix not cherry-picked into the repo"
[[ "$(git -C "$d" log --oneline | wc -l | tr -d ' ')" == "2" ]] \
  || fail "case1: expected exactly one new commit"
[[ "$(cd "$d" && QUARANTINE_FILE="$d/overlays/quarantine.json" bash -c \
  'source scripts/update-state.sh; source scripts/quarantine.sh; quarantine_field demo escalation_status')" == "fixed" ]] \
  || fail "case1: escalation_status not recorded as fixed"
# No worktrees may be left behind.
[[ "$(git -C "$d" worktree list | wc -l | tr -d ' ')" == "1" ]] \
  || fail "case1: worktree leaked"
rm -rf "$d" "$stub"

# === Case 2: gave-up commits nothing and records the verdict =============
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_gaveup "$stub"; stub_nix "$stub" ok
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case2: expected exit 1, got $rc"
[[ "$(git -C "$d" log --oneline | wc -l | tr -d ' ')" == "1" ]] \
  || fail "case2: gave-up produced a commit"
[[ "$(cd "$d" && QUARANTINE_FILE="$d/overlays/quarantine.json" bash -c \
  'source scripts/update-state.sh; source scripts/quarantine.sh; quarantine_field demo escalation_status')" == "gave-up" ]] \
  || fail "case2: gave-up not recorded"
[[ "$(git -C "$d" worktree list | wc -l | tr -d ' ')" == "1" ]] || fail "case2: worktree leaked"
rm -rf "$d" "$stub"

# === Case 3: a LYING verdict is caught by the wrapper's own build ========
# This is the load-bearing test: Claude's claim is never the evidence.
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_lies "$stub"; stub_nix "$stub" broken
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case3: an unverifiable 'fixed' verdict was accepted (exit $rc)"
[[ "$(git -C "$d" log --oneline | wc -l | tr -d ' ')" == "1" ]] \
  || fail "case3: committed a fix whose build failed"
grep -qi "did not reproduce\|verification" "$d/esc.log" \
  || { cat "$d/esc.log"; fail "case3: discrepancy not reported"; }
rm -rf "$d" "$stub"

# === Case 4: a missing verdict.json is treated as gave-up ===============
d="$(setup)"; stub="$(mktemp -d)"; stub_nix "$stub" ok
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/claude"; chmod +x "$stub/claude"
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case4: missing verdict not treated as gave-up (exit $rc)"
rm -rf "$d" "$stub"

# === Case 5: dedup refuses a second escalation on the same fingerprint ===
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_fixed "$stub"; stub_nix "$stub" ok
( cd "$d" && QUARANTINE_FILE="$d/overlays/quarantine.json" bash -c '
  source scripts/update-state.sh; source scripts/quarantine.sh
  quarantine_record demo overlay 1.1.0 1.0.0 package-build compile-failure next-version-only x
  quarantine_set_escalation demo gave-up "already tried"' )
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 2 ]] || fail "case5: expected exit 2 (skipped by dedup), got $rc"
grep -q "1.0.0" "$d/overlays/99-demo.nix" || fail "case5: overlay was modified despite dedup"
rm -rf "$d" "$stub"

echo "PASS: test_escalate"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/update/test_escalate.sh`
Expected: FAIL — `scripts/escalate.sh: No such file or directory`

- [ ] **Step 3: Write the escalation wrapper**

Create `scripts/escalate.sh`:

```bash
#!/usr/bin/env bash
# Escalate a classified overlay failure to a budgeted headless Claude session
# (spec §4).
#
# THE CONTRACT, in one line: Claude may edit; only this wrapper may verify and
# commit. A `fixed` verdict is a hypothesis — the wrapper's own build is the
# evidence. A verdict whose build does not reproduce is recorded as gave-up,
# because a model asserting success is exactly the failure mode to design
# against.
#
# Work happens in a throwaway git worktree, never the daily-driver checkout:
# bump-overlays exits 3 when overlays/ is dirty, so leftover edits from a
# failed repair would silently disable the next day's entire run.
#
# Exit: 0 verified fix committed | 1 gave up | 2 skipped (dedup/budget)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO/scripts/update-state.sh"
# shellcheck source=/dev/null
source "$REPO/scripts/quarantine.sh"
# shellcheck source=/dev/null
source "$REPO/scripts/classify-failure.sh"

CLAUDE_BIN="${ESCALATE_CLAUDE_BIN:-claude}"
MAX_TURNS=40
TIMEOUT=900
PACKAGE=""; VERSION=""; PHASE=""; LOG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package)   PACKAGE="$2"; shift 2 ;;
    --version)   VERSION="$2"; shift 2 ;;
    --phase)     PHASE="$2"; shift 2 ;;
    --log)       LOG="$2"; shift 2 ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --timeout)   TIMEOUT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$PACKAGE" && -n "$VERSION" && -n "$LOG" ]] || {
  echo "usage: escalate.sh --package <n> --version <v> --phase <p> --log <f>" >&2; exit 2; }

MANIFEST="$REPO/overlays/updates.json"
fingerprint="$(classify_failure "$LOG" | cut -f1)"

# ── Budget gates (spec §5) ────────────────────────────────────────────────
if ! quarantine_should_escalate "$PACKAGE" "$fingerprint"; then
  echo "escalate: skipping $PACKAGE — '$fingerprint' already gave up, or attempt ceiling reached"
  exit 2
fi

# ── Assemble the brief ────────────────────────────────────────────────────
# Deliberately small (target <3k tokens) and pre-digested. Handing over the
# repo to explore is where tokens go to die.
ts="$(date -u +%Y%m%dT%H%M%SZ)"
brief="$REPO/logs/escalation-${PACKAGE}-${ts}.md"
mkdir -p "$REPO/logs"

pkg_json="$(jq --arg n "$PACKAGE" '.packages[] | select(.name==$n)' "$MANIFEST")"
overlay_rel="$(jq -r '.overlay' <<<"$pkg_json")"
update_type="$(jq -r '.update_type' <<<"$pkg_json")"
prior="$(quarantine_field "$PACKAGE" escalation_verdict)"

cat > "$brief" <<EOF
Use the overlay-repair skill.

A mechanical overlay bump failed and was rolled back. Repair it, or conclude it
needs a human.

## Package
- name: $PACKAGE
- attempted version: $VERSION
- last known-good version: $(jq -r '.current_version' <<<"$pkg_json")
- overlay file: $overlay_rel
- update_type: $update_type
- failure phase: $PHASE
- classified fingerprint: $fingerprint

## Manifest entry
\`\`\`json
$pkg_json
\`\`\`

## Prior escalation verdict for this package
${prior:-none}

## Build log (tail, store paths collapsed)
\`\`\`
$(tail -80 "$LOG" 2>/dev/null | quarantine_sanitize)
\`\`\`

## What to do
1. Read $overlay_rel and the '$update_type' section of docs/overlay-update-routine.md.
2. Make the minimal edit that could plausibly fix this, bumping the overlay's
   pinned version/hash AND overlays/updates.json's current_version together.
3. Verify with a scoped build:
   nix build --no-link --impure --expr 'let pkgs = import <nixpkgs> { config.allowUnfree = true; overlays = [ (import ./$overlay_rel) ]; }; in pkgs.$PACKAGE'
4. Write verdict.json in the repo root (schema in the skill). Do NOT commit.

If two attempts do not work, write status "gave-up" with a precise diagnosis.
A wrong-but-building overlay is worse than a frozen one.
EOF

# ── Throwaway worktree ────────────────────────────────────────────────────
wt="$(mktemp -d)/repair"
branch="escalate/${PACKAGE}-${ts}"
if ! git -C "$REPO" worktree add -q -b "$branch" "$wt" HEAD; then
  echo "escalate: could not create worktree" >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" "wrapper could not create a git worktree"
  exit 1
fi
cleanup() {
  git -C "$REPO" worktree remove --force "$wt" >/dev/null 2>&1 || true
  git -C "$REPO" branch -D "$branch" >/dev/null 2>&1 || true
  rm -rf "$(dirname "$wt")"
}
trap cleanup EXIT

# ── Run the model ─────────────────────────────────────────────────────────
# Allowed tools ARE the contract: no sudo, no git commit, no git push, no
# network fetch beyond the two prefetch commands.
session_log="$REPO/logs/escalation-${PACKAGE}-${ts}.session.log"
start_epoch="$(date +%s)"
( cd "$wt" && timeout "$TIMEOUT" "$CLAUDE_BIN" -p --model sonnet \
    --max-turns "$MAX_TURNS" \
    --permission-mode acceptEdits \
    --allowedTools 'Read,Edit,Write,Bash(nix build:*),Bash(nix-prefetch-url:*),Bash(nix hash:*),Bash(nix fmt),Bash(git diff:*)' \
    "$(cat "$brief")" ) >"$session_log" 2>&1
claude_rc=$?
duration=$(( $(date +%s) - start_epoch ))

# ── Read the verdict ──────────────────────────────────────────────────────
# A missing or malformed verdict is gave-up, never an implicit success.
status="gave-up"; verdict="no verdict.json produced (claude exited $claude_rc)"
if [[ -f "$wt/verdict.json" ]] && jq empty "$wt/verdict.json" 2>/dev/null; then
  status="$(jq -r '.status // "gave-up"' "$wt/verdict.json")"
  verdict="$(jq -r '.verdict // "no verdict text"' "$wt/verdict.json")"
fi
rm -f "$wt/verdict.json"

printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$PACKAGE" "$status" "$duration" \
  "$(grep -oE '[0-9]+ tokens' "$session_log" 2>/dev/null | tail -1 | tr -d ' tokens')" \
  >> "$REPO/logs/escalation-costs.tsv"

if [[ "$status" != "fixed" ]]; then
  echo "escalate: $PACKAGE gave up — $verdict"
  quarantine_set_escalation "$PACKAGE" "gave-up" "$verdict"
  exit 1
fi

# ── Independent verification — the wrapper's build, not Claude's claim ────
if [[ -z "$(git -C "$wt" status --porcelain)" ]]; then
  echo "escalate: verdict claimed 'fixed' but nothing changed — treating as gave-up" >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" "claimed fixed but produced no diff: $verdict"
  exit 1
fi

overlay_rel_wt="$overlay_rel"
if ! ( cd "$wt" && nix build --no-link --impure --expr \
        "let pkgs = import <nixpkgs> { config.allowUnfree = true; overlays = [ (import ./$overlay_rel_wt) ]; }; in pkgs.${PACKAGE}" ) \
      >>"$session_log" 2>&1; then
  echo "escalate: 'fixed' verdict did not reproduce — scoped build failed. Treating as gave-up." >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" \
    "verdict claimed fixed but the wrapper's scoped build failed to reproduce it: $verdict"
  exit 1
fi

if ! ( cd "$wt" && nix build ".#darwinConfigurations.garmonbozia.system" --no-link ) \
      >>"$session_log" 2>&1; then
  echo "escalate: scoped build passed but the full system build failed. Treating as gave-up." >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" \
    "verification: scoped build passed, full system build failed: $verdict"
  exit 1
fi

# ── Commit in the worktree, cherry-pick into the real checkout ────────────
git -C "$wt" add -A
git -C "$wt" -c core.hooksPath=/dev/null commit -q \
  -m "overlays: repair $PACKAGE bump to $VERSION

Escalated repair, verified by scoped + full system build.
Verdict: $verdict"
fix_sha="$(git -C "$wt" rev-parse HEAD)"

if ! git -C "$REPO" cherry-pick "$fix_sha" >>"$session_log" 2>&1; then
  git -C "$REPO" cherry-pick --abort >/dev/null 2>&1 || true
  echo "escalate: cherry-pick of the verified fix failed" >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" "verified fix could not be cherry-picked cleanly"
  exit 1
fi

quarantine_set_escalation "$PACKAGE" "fixed" "$verdict"
quarantine_clear "$PACKAGE"
echo "escalate: $PACKAGE repaired and committed as $(git -C "$REPO" rev-parse --short HEAD)"
echo "escalate: verdict — $verdict"
exit 0
```

- [ ] **Step 4: Write the repair skill**

Create `.claude/skills/overlay-repair/SKILL.md`:

```markdown
---
name: overlay-repair
description: Use when repairing a failed nixos-config overlay version bump — invoked by scripts/escalate.sh with a prepared brief naming the package, the attempted version, and the classified build failure.
---

# Overlay Repair

You are repairing ONE failed overlay version bump in `~/nixos-config`. The brief
names the package, the attempted version, the overlay file, its `update_type`,
and the classified failure. You are running in a throwaway git worktree.

## Hard rules

- **You cannot commit, push, activate, or sudo.** Those tools are not available
  to you by design. The wrapper commits — and only after independently
  re-running your build. Your claim of success is not evidence.
- **Bump the overlay's pinned version/hash AND `overlays/updates.json`'s
  `current_version` together.** Doing only one leaves the manifest lying about
  what is pinned, which masks the package as up-to-date on every later probe.
- **Two attempts maximum.** If the mechanical path does not work, write
  `gave-up` with a precise diagnosis. A wrong-but-building overlay is worse
  than a frozen one — it ships silently broken software.
- **Do not disable checks to make a build pass** unless the failure is
  demonstrably a sandbox-only test issue, and say so explicitly in the verdict.
- **Do not widen scope.** Repair this one package. Do not refactor, reformat
  unrelated files, or "improve" neighbouring overlays.

## Getting a hash

```bash
# Archives (tar.gz, tar.xz, zip):
nix-prefetch-url --unpack <url>
# Single prebuilt binaries:
nix-prefetch-url <url>
# Then convert to SRI:
nix hash convert --hash-algo sha256 --to sri <raw-hash>
```

For Go/Cargo source builds, blank `vendorHash`/`cargoHash` to `""`, run the
scoped build, and read the expected hash out of the error message.

## Failure playbook by fingerprint

| fingerprint | usual cause | first thing to try |
|---|---|---|
| `eval-error` | upstream renamed something the overlay references | For `go`, a minor bump renames the `go_1_26` attribute — rename it to match. Otherwise read the overlay and fix the reference the error names. |
| `compile-failure` | genuine break in the new version | Check whether upstream changed the artifact layout (a moved binary path, a new archive root). If the code itself is broken, `gave-up`. |
| `test-failure` | sandbox-hostile test suite | Only if clearly sandbox-related (network access, timing), add `doCheck = false;` and say so in the verdict. Otherwise `gave-up`. |
| `hash-mismatch` | should not reach you — `fix-hashes` handles it | If it does, re-prefetch and substitute manually. |
| `unclassified` | unknown | Read the log carefully. If you cannot state a cause in one sentence, `gave-up`. |

## Package-specific knowledge

- **yt-dlp** (`overlays/91-yt-dlp.nix`): the `postPatch` section pins `curl_cffi`
  version bounds that routinely need widening on each release. `yt-dlp-ejs` is
  bundled in the same file and versioned separately (PyPI package `yt_dlp_ejs`).
- **go** (`overlays/55-go.nix`): a minor bump (1.26 → 1.27) requires renaming the
  `go_1_26` attribute as well as the version and hashes.
- **tmux** (`overlays/96-tmux.nix`): `overrideAttrs` with a `fetchFromGitHub` src
  where the tag equals the version (e.g. `3.7b`). `fix-hashes` does not touch it.
- **ngrok** (`overlays/20-ngrok.nix`): stable CDN URLs from `bin.equinox.io`, no
  versioned release pages. Six platform hashes must be fetched.
- **mise** (`overlays/30-mise.nix`): now prebuilt binaries; use raw
  `nix-prefetch-url` (not `--unpack`) per platform.

Full recipes: `docs/overlay-update-routine.md`.

## Verify

```bash
nix build --no-link --impure --expr \
  'let pkgs = import <nixpkgs> { config.allowUnfree = true; overlays = [ (import ./overlays/<file>.nix) ]; }; in pkgs.<attr>'
```

Run `nix fmt` if you changed a `.nix` file.

## Write the verdict

Write `verdict.json` in the worktree root. This is your only output channel:

```json
{
  "status": "fixed",
  "package": "yt-dlp",
  "fingerprint": "compile-failure",
  "verdict": "One paragraph: what was wrong, what you changed, and what you verified. If gave-up, state precisely what a human needs to decide.",
  "files_changed": ["overlays/91-yt-dlp.nix", "overlays/updates.json"]
}
```

`status` is `fixed` or `gave-up`. Claiming `fixed` without a passing scoped
build wastes a whole day of automation — the wrapper will catch it, record the
discrepancy against you, and quarantine the package anyway.
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/update/test_escalate.sh`
Expected: `PASS: test_escalate`

- [ ] **Step 6: Add the cost log to gitignore**

`logs/*` is already gitignored (see `.gitignore`), so `logs/escalation-costs.tsv` needs no new rule. Confirm:

Run: `git check-ignore -v logs/escalation-costs.tsv`
Expected: a line naming `.gitignore` and the `logs/*` pattern

- [ ] **Step 7: Run the full suite and commit**

Run: `bash tests/update/run.sh`
Expected: `ALL PASS`

```bash
git add scripts/escalate.sh .claude/skills/overlay-repair/SKILL.md tests/update/test_escalate.sh
git commit -m "feat(update): add budgeted Claude escalation wrapper and overlay-repair skill"
```

---

### Task 7: Unpin-retry for frozen flake inputs

Makes `pinned_inputs[]` a retryable state rather than a permanent freeze, so the nixpkgs pin gets tested weekly instead of whenever a human remembers.

**Files:**
- Modify: `apps/aarch64-darwin/prepare` (mirror to every `apps/*/prepare`)
- Modify: `overlays/updates.json` (add `retry_cadence_hours` to each `pinned_inputs[]` entry)
- Test: `tests/update/test_unpin_retry.sh`

**Interfaces:**
- Consumes: `quarantine_field`, `quarantine_record`, `quarantine_init` (Task 1).
- Produces: `unpin_retry_due <input-name>` → exit 0 if the pin's retry window has elapsed; `attempt_unpin <input-name>` → exit 0 if the speculative bump built (pin should be removed), 1 if it failed (pin stays, ledger records the attempt).
- Produces: optional `retry_cadence_hours` on `pinned_inputs[]` entries; default `168`.

- [ ] **Step 1: Add retry cadence to the pinned inputs**

```bash
python3 - <<'PYEOF'
import json, collections
p = "overlays/updates.json"
with open(p) as f:
    data = json.load(f, object_pairs_hook=collections.OrderedDict)
for pin in data["pinned_inputs"]:
    pin["retry_cadence_hours"] = 168
with open(p, "w") as f:
    # ensure_ascii=False is required: without it Python re-escapes the em-dashes
    # and arrows already present in several notes fields into \uXXXX, producing a
    # large spurious diff across packages this change never touched.
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYEOF
```

Verify: `jq -r '.pinned_inputs[] | "\(.name) \(.retry_cadence_hours)"' overlays/updates.json`
Expected: three lines, each ending in `168`

- [ ] **Step 2: Write the failing test**

Create `tests/update/test_unpin_retry.sh`:

```bash
#!/usr/bin/env bash
# Tests prepare's unpin-retry gating in isolation by sourcing the helper
# functions out of the real `prepare` script — no nix, no network, no commits.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# Every pinned input declares a retry cadence.
n_pins="$(jq '.pinned_inputs | length' "$REPO/overlays/updates.json")"
n_cad="$(jq '[.pinned_inputs[] | select(has("retry_cadence_hours"))] | length' "$REPO/overlays/updates.json")"
[[ "$n_pins" == "$n_cad" ]] || fail "only $n_cad of $n_pins pinned_inputs declare retry_cadence_hours"

# Extract the helpers from `prepare` without executing its main body. The
# marker comments below must exist in prepare (added in Step 4).
sed -n '/^# ---8<--- unpin-retry helpers ---8<---$/,/^# ---8<--- end unpin-retry helpers ---8<---$/p' \
  "$REPO/apps/aarch64-darwin/prepare" > "$TMP/helpers.sh"
[[ -s "$TMP/helpers.sh" ]] || fail "unpin-retry helper markers not found in prepare"

export QUARANTINE_FILE="$TMP/quarantine.json"
MANIFEST="$REPO/overlays/updates.json"
# shellcheck source=/dev/null
source "$REPO/scripts/update-state.sh"
# shellcheck source=/dev/null
source "$REPO/scripts/quarantine.sh"
# shellcheck source=/dev/null
source "$TMP/helpers.sh"
quarantine_init

# A pin never attempted before is due immediately.
unpin_retry_due nixpkgs || fail "a never-attempted pin was not due"

# A pin attempted just now is not due.
quarantine_record nixpkgs input "unpin-attempt" "af45a5c" "system-build" \
  "unpin-failed" "retry-after:168" "patch OOM"
if unpin_retry_due nixpkgs; then fail "a just-attempted pin was reported due"; fi

# Backdated past the window, it is due again.
jq '(.entries[] | select(.name=="nixpkgs") | .last_attempt) = "2000-01-01T00:00:00Z"' \
  "$QUARANTINE_FILE" > "$TMP/x" && mv "$TMP/x" "$QUARANTINE_FILE"
unpin_retry_due nixpkgs || fail "a stale pin attempt was not due again"

# An unknown input is never due (nothing to unpin).
if unpin_retry_due not-a-real-input; then fail "unknown input reported due"; fi

echo "PASS: test_unpin_retry"
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash tests/update/test_unpin_retry.sh`
Expected: FAIL — `unpin-retry helper markers not found in prepare`

- [ ] **Step 4: Add the helpers to `prepare`**

In `apps/aarch64-darwin/prepare`, after the existing `source "$FLAKE_DIR/scripts/update-probe.sh"` line, add the quarantine source and the helper block. The marker comments are load-bearing — the test extracts between them:

```bash
# shellcheck source=/dev/null
source "$FLAKE_DIR/scripts/quarantine.sh"

MANIFEST="${MANIFEST:-$FLAKE_DIR/overlays/updates.json}"

# ---8<--- unpin-retry helpers ---8<---
# pinned_inputs[] used to be a permanent freeze: nothing ever retried an
# unpin, so nixpkgs stayed pinned until a human remembered to test it. Each
# pin now carries retry_cadence_hours; a due pin gets ONE speculative bump
# attempt per window, and silently re-freezes if it still fails.

# Exit 0 if <input> is a declared pin whose retry window has elapsed.
unpin_retry_due() { # <input-name>
  local name="$1" cadence last
  cadence="$(jq -r --arg n "$name" \
    '.pinned_inputs[] | select(.name==$n) | .retry_cadence_hours // 168' "$MANIFEST")"
  [[ -z "$cadence" || "$cadence" == "null" ]] && return 1   # not a pin at all
  last="$(quarantine_field "$name" last_attempt)"
  [[ -z "$last" ]] && return 0
  python3 - "$last" "$cadence" <<'PYEOF'
import sys, datetime
last, hours = sys.argv[1], float(sys.argv[2])
try:
    t = datetime.datetime.strptime(last, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
except ValueError:
    sys.exit(0)
sys.exit(0 if (datetime.datetime.now(datetime.timezone.utc) - t).total_seconds() >= hours * 3600 else 1)
PYEOF
}

# One speculative unpin attempt: move the input to its tracking ref, build, and
# keep the result only if the build passes. Exit 0 = unpinned successfully.
# Any failure restores flake.nix/flake.lock exactly as they were, because a
# half-unpinned tree would break every later step in the run.
attempt_unpin() { # <input-name>
  local name="$1" log
  log="$(mktemp)"
  warn "==> speculative unpin attempt: $name"
  git -C "$FLAKE_DIR" stash push -q -- flake.nix flake.lock 2>/dev/null || true
  local stashed=$?

  if ! nix flake update "$name" >"$log" 2>&1; then
    warn "  unpin: 'nix flake update $name' failed; staying pinned"
    git -C "$FLAKE_DIR" checkout -- flake.nix flake.lock 2>/dev/null || true
    [[ $stashed -eq 0 ]] && git -C "$FLAKE_DIR" stash pop -q 2>/dev/null || true
    quarantine_record "$name" "input" "unpin-attempt" \
      "$(jq -r --arg n "$name" '.pinned_inputs[] | select(.name==$n) | .pinned_ref' "$MANIFEST")" \
      "flake-update" "unpin-failed" "retry-after:$(jq -r --arg n "$name" '.pinned_inputs[] | select(.name==$n) | .retry_cadence_hours // 168' "$MANIFEST")" \
      "$(tail -40 "$log")"
    rm -f "$log"
    return 1
  fi

  if ! nix build "${FLAKE_DIR}#${FLAKE_SYSTEM_ATTR}" --no-link >>"$log" 2>&1; then
    warn "  unpin: system build still fails; staying pinned"
    git -C "$FLAKE_DIR" checkout -- flake.nix flake.lock 2>/dev/null || true
    [[ $stashed -eq 0 ]] && git -C "$FLAKE_DIR" stash pop -q 2>/dev/null || true
    quarantine_record "$name" "input" "unpin-attempt" \
      "$(jq -r --arg n "$name" '.pinned_inputs[] | select(.name==$n) | .pinned_ref' "$MANIFEST")" \
      "system-build" "unpin-failed" "retry-after:$(jq -r --arg n "$name" '.pinned_inputs[] | select(.name==$n) | .retry_cadence_hours // 168' "$MANIFEST")" \
      "$(tail -40 "$log")"
    rm -f "$log"
    return 1
  fi

  rm -f "$log"
  msg "  unpin: $name builds clean — the pin can be removed"
  quarantine_clear "$name"
  return 0
}
# ---8<--- end unpin-retry helpers ---8<---
```

- [ ] **Step 5: Call the retry loop from `prepare`**

In `apps/aarch64-darwin/prepare`, after `state_set_last_gate "$(now_iso)"` and before the `warn "==> build ..."` line, insert:

```bash
quarantine_init
# Speculative unpin attempts. Each is expensive (a full build against a new
# nixpkgs), so at most ONE per run: the pins are ordered by risk in the
# manifest and unpinning nixpkgs is what unblocks the other two anyway.
UNPINNED=""
while read -r pin; do
  [[ -z "$pin" ]] && continue
  if unpin_retry_due "$pin"; then
    if attempt_unpin "$pin"; then
      UNPINNED="$pin"
      warn "  ACTION NEEDED: remove the '$pin' entry from pinned_inputs[] and"
      warn "  update flake.nix's $pin.url — this run kept the bumped flake.lock."
    fi
    break
  fi
done < <(jq -r '.pinned_inputs[].name' "$MANIFEST")
```

**Note on the deliberate half-step:** a successful unpin leaves the bumped `flake.lock` in place and *reports* that `flake.nix`'s `url` and the `pinned_inputs[]` entry still need editing, rather than rewriting them. Rewriting a `flake.nix` URL and deleting a manifest entry with its `reason`/`risk`/`unpin_when` prose is not a mechanical substitution, and getting it wrong silently discards the documented reason a pin existed. The build-proof is the valuable part; the two-line edit is cheap and belongs to a human.

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash tests/update/test_unpin_retry.sh`
Expected: `PASS: test_unpin_retry`

- [ ] **Step 7: Verify `prepare` still short-circuits correctly**

Run: `bash tests/update/test_prepare_gate.sh`
Expected: `PASS: test_prepare_gate` (this pre-existing test guards the gate short-circuit; if it now fails, the insertion point in Step 5 is wrong — it must be *after* the gate, so a no-op run never attempts an unpin)

- [ ] **Step 8: Mirror to other systems, run the suite, commit**

Run: `ls apps/*/prepare` and apply the identical edits to every copy.

Run: `for f in apps/*/prepare; do md5 -q "$f"; done | sort -u | wc -l`
Expected: `1`

Run: `bash tests/update/run.sh`
Expected: `ALL PASS`

```bash
git add apps/*/prepare overlays/updates.json tests/update/test_unpin_retry.sh
git commit -m "feat(update): retry frozen flake-input pins on a cadence"
```

---

### Task 8: Rewrite `scheduled-check` as the full pipeline

Wires everything together: bump (all overlays), prepare, build, activate, health-check, rollback-on-failure, escalate, mirror.

**Files:**
- Modify: `apps/aarch64-darwin/scheduled-check` (mirror to every `apps/*/scheduled-check`)
- Test: `tests/update/test_scheduled_pipeline.sh`

**Interfaces:**
- Consumes: everything from Tasks 1–7.
- Produces: `scheduled-check [--no-activate]` → exit 0 pipeline completed (with or without changes), 1 a failure was reported, 2 lock contention.
  Honours `SCHEDULED_ACTIVATE=0` to skip the privileged half (used by tests and for a propose-only run).

- [ ] **Step 1: Write the failing test**

Create `tests/update/test_scheduled_pipeline.sh`:

```bash
#!/usr/bin/env bash
# End-to-end test of the scheduled-check pipeline with every dangerous step
# stubbed: no real bump, build, activation, rollback, notification, or mirror
# push. Asserts the ORDERING and the branch decisions, which is what actually
# matters about this script.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
REAL_NIX="$(command -v nix)"
fail() { echo "FAIL: $1"; exit 1; }

setup() { # <bump-outcome> <build-outcome> <health-outcome> -> repo path
  local bump="$1" build="$2" health="$3"
  local d; d="$(mktemp -d)"
  mkdir -p "$d/apps/aarch64-darwin" "$d/scripts" "$d/overlays" "$d/logs"
  cp "$REPO/scripts/update-notify.sh" "$REPO/scripts/update-state.sh" \
     "$REPO/scripts/quarantine.sh" "$REPO/scripts/classify-failure.sh" "$d/scripts/"
  cp "$REPO/apps/aarch64-darwin/_common.sh" \
     "$REPO/apps/aarch64-darwin/scheduled-check" "$d/apps/aarch64-darwin/"
  printf '{"comment":"t","entries":[]}\n' > "$d/overlays/quarantine.json"
  printf '{"packages":[],"skip":[],"inputs":{},"pinned_inputs":[]}\n' > "$d/overlays/updates.json"

  # Every step logs to $d/order.log so the test can assert the sequence.
  local trace="$d/order.log"
  make_stub() { # <name> <exit-code> <extra-body>
    cat > "$d/apps/aarch64-darwin/$1" <<EOF
#!/usr/bin/env bash
echo "$1" >> "$trace"
${3:-}
exit $2
EOF
    chmod +x "$d/apps/aarch64-darwin/$1"
  }
  # bump-overlays: 0 = bumped something (commits), 9 = nothing to do
  if [[ "$bump" == "bumped" ]]; then
    make_stub bump-overlays 0 'git commit -q --allow-empty -m "overlays: update demo to v2"'
  else
    make_stub bump-overlays 0 ''
  fi
  make_stub prepare 0 ''            # prepare: nothing to do (common case)
  make_stub activate 0 ''
  make_stub rollback 0 ''

  # health check
  if [[ "$health" == "ok" ]]; then
    printf '#!/usr/bin/env bash\necho health >> "%s"\nexit 0\n' "$trace" > "$d/scripts/post-activate-health.sh"
  else
    printf '#!/usr/bin/env bash\necho health >> "%s"\necho "FAIL: demo" >&2\nexit 1\n' "$trace" > "$d/scripts/post-activate-health.sh"
  fi
  chmod +x "$d/scripts/post-activate-health.sh"

  printf '#!/usr/bin/env bash\necho sync >> "%s"\nexit 0\n' "$trace" > "$d/scripts/sync-to-public.sh"
  printf '#!/usr/bin/env bash\necho escalate >> "%s"\nexit 1\n' "$trace" > "$d/scripts/escalate.sh"
  chmod +x "$d/scripts/sync-to-public.sh" "$d/scripts/escalate.sh"

  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name Test
  git -C "$d" add -A && git -C "$d" commit -qm init
  printf '%s' "$d"
}

stubs() { # <dir> <build-outcome>
  local s; s="$(mktemp -d)"
  if [[ "$2" == "ok" ]]; then
    cat > "$s/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "registry list") exit 1 ;; esac
case "\$1" in build|store) exit 0 ;; *) exec "$REAL_NIX" "\$@" ;; esac
EOF
  else
    cat > "$s/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "registry list") exit 1 ;; esac
case "\$1" in
  build) echo "error: builder for '/nix/store/x.drv' failed with exit code 1" >&2; exit 1 ;;
  store) exit 0 ;;
  *) exec "$REAL_NIX" "\$@" ;;
esac
EOF
  fi
  cat > "$s/osascript" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$1/notify.log"
EOF
  chmod +x "$s/nix" "$s/osascript"
  printf '%s' "$s"
}

run() { # <repo> <stub>
  ( cd "$1" && PATH="$2:$PATH" UPDATE_STATE_FILE="$1/.state.json" \
      bash apps/aarch64-darwin/scheduled-check >"$1/run.log" 2>&1 )
}

# === Case 1: happy path — bump, build, activate, health, sync ==============
d="$(setup bumped ok ok)"; s="$(stubs "$d" ok)"
run "$d" "$s" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/run.log"; fail "case1: expected exit 0, got $rc"; }
order="$(tr '\n' ' ' < "$d/order.log")"
[[ "$order" == "bump-overlays prepare activate health sync "* ]] \
  || fail "case1: wrong order: $order"
grep -qi "activated" "$d/notify.log" 2>/dev/null || true   # notification optional on success
rm -rf "$d" "$s"

# === Case 2: nothing changed — no activation, no notification =============
d="$(setup nothing ok ok)"; s="$(stubs "$d" ok)"
run "$d" "$s" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || fail "case2: expected exit 0, got $rc"
grep -q "activate" "$d/order.log" && fail "case2: activated with nothing to do"
[[ ! -s "$d/notify.log" ]] || { cat "$d/notify.log"; fail "case2: notified on a no-op run"; }
rm -rf "$d" "$s"

# === Case 3: build fails -> no activation, revision quarantined, notified ==
# A system-build failure after per-package builds passed is a collision or eval
# problem, not one package's fault, so it is NOT escalated (spec §3): it is
# frozen and reported, and the notification names the range to bisect by hand.
d="$(setup bumped broken ok)"; s="$(stubs "$d" broken)"
run "$d" "$s" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case3: expected exit 1, got $rc"
grep -q "activate" "$d/order.log" && fail "case3: activated after a failed build"
grep -q "escalate" "$d/order.log" && fail "case3: escalated a revision-level failure"
grep -q "sync" "$d/order.log" && fail "case3: mirrored a revision that failed to build"
grep -qi "fail" "$d/notify.log" || fail "case3: no failure notification"
[[ "$(jq -r '[.entries[] | select(.kind=="revision")] | length' "$d/overlays/quarantine.json")" == "1" ]] \
  || fail "case3: no revision-kind quarantine entry written"
[[ "$(jq -r '.entries[] | select(.kind=="revision") | .retry_policy' "$d/overlays/quarantine.json")" == "frozen" ]] \
  || fail "case3: revision entry not frozen"
rm -rf "$d" "$s"

# === Case 4: health check fails -> rollback, notify, no mirror ============
d="$(setup bumped ok broken)"; s="$(stubs "$d" ok)"
run "$d" "$s" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case4: expected exit 1, got $rc"
order="$(tr '\n' ' ' < "$d/order.log")"
[[ "$order" == *"activate health rollback"* ]] \
  || fail "case4: rollback did not follow a failed health check: $order"
grep -q "sync" "$d/order.log" && fail "case4: mirrored a revision that failed health"
grep -qi "roll" "$d/notify.log" || { cat "$d/notify.log"; fail "case4: no rollback notification"; }
# The failed revision must be quarantined as a revision-level entry.
[[ "$(jq -r '.entries[] | select(.kind=="revision") | .name' "$d/overlays/quarantine.json")" != "" ]] \
  || fail "case4: no revision-kind quarantine entry written"
rm -rf "$d" "$s"

# === Case 5: --no-activate stays propose-only ============================
d="$(setup bumped ok ok)"; s="$(stubs "$d" ok)"
( cd "$d" && PATH="$s:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
    bash apps/aarch64-darwin/scheduled-check --no-activate >"$d/run.log" 2>&1 ) || true
grep -q "activate" "$d/order.log" && fail "case5: --no-activate still activated"
rm -rf "$d" "$s"

echo "PASS: test_scheduled_pipeline"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/update/test_scheduled_pipeline.sh`
Expected: FAIL at case 1 — the current script never calls `activate` or the health check, so the order assertion fails.

- [ ] **Step 3: Rewrite `apps/aarch64-darwin/scheduled-check`**

Replace the whole file with:

```bash
#!/usr/bin/env bash
# Daily self-healing update pipeline (spec §1). Invoked by the root
# launchd.daemons.nixos-auto-update at 09:00.
#
# bump (all overlays) -> prepare (flake inputs, incl. unpin retry) -> build
# -> activate -> health check -> rollback if unhealthy -> mirror to public.
#
# Design invariants, in priority order:
#   1. A broken package must not block anything else. Failures are attributed
#      per-package, quarantined at that exact version, and the run continues.
#   2. Nothing is activated without a full system build behind it.
#   3. Nothing is mirrored to the public repo until the health check passes on
#      the machine that produced the revision.
#   4. Silence on success. The user should hear from this roughly never.
#
# Exit: 0 completed (changes or not) | 1 a failure was reported | 2 lock contention
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_common.sh"
FLAKE_DIR="$(locate_flake)" || exit 1
# shellcheck source=/dev/null
source "$FLAKE_DIR/scripts/update-notify.sh"
# shellcheck source=/dev/null
source "$FLAKE_DIR/scripts/update-state.sh"
# shellcheck source=/dev/null
source "$FLAKE_DIR/scripts/quarantine.sh"
# shellcheck source=/dev/null
source "$FLAKE_DIR/scripts/classify-failure.sh"
cd "$FLAKE_DIR"

ACTIVATE="${SCHEDULED_ACTIVATE:-1}"
[[ "${1:-}" == "--no-activate" ]] && ACTIVATE=0

# Logs live in the repo (gitignored) so they survive reboots. launchd opens
# StandardOutPath/StandardErrorPath before this runs, so logs/ must already
# exist on disk — a tracked .gitkeep ensures it.
LOG_DIR="$FLAKE_DIR/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
# launchd appends to the same two files forever; truncate per-run rather than
# adding logrotate. Keep these paths in sync with hosts/darwin/default.nix.
: > "$LOG_DIR/nixos-auto-update.out.log" 2>/dev/null || true
: > "$LOG_DIR/nixos-auto-update.err.log" 2>/dev/null || true
RUN_LOG="$LOG_DIR/nixos-scheduled-check.log"
: > "$RUN_LOG"

quarantine_init
exit_code=0

before="$(git rev-parse HEAD 2>/dev/null)" || {
  notify "nixos-config update FAILED" "could not determine git HEAD; check the checkout"
  exit 1
}

# ── 1. Overlay bumps (ALL overlays, not just the mechanical subset) ────────
# The go-source path (bump_gosource) has been implemented and verified by a
# scoped build for a while; --mechanical-only was excluding it only because
# c4/hey-cli track branch HEAD. That is now handled by per-package
# cadence_hours in the manifest, so the flag is no longer needed here.
"$SCRIPT_DIR/bump-overlays" --no-public-sync >>"$RUN_LOG" 2>&1
bump_rc=$?
if [[ $bump_rc -eq 2 ]]; then
  # Another run holds the lock. Benign — that run owns reporting.
  echo "scheduled-check: lock contention, exiting quietly" >>"$RUN_LOG"
  exit 2
fi
after_bump="$(git rev-parse HEAD 2>/dev/null)"

# ── 2. Escalate the packages bump-overlays quarantined this run ────────────
# Budget: at most 3, one per package (spec §5.2). escalate.sh applies its own
# fingerprint dedup, so a package failing the same way daily costs one session
# total, not one per day.
escalated=0
fixed_by_claude=()
while IFS=$'\t' read -r qname qver qphase; do
  [[ -z "$qname" ]] && continue
  [[ $escalated -ge 3 ]] && break
  # Only escalate what the classifier said to escalate.
  esc_flag="$(quarantine_field "$qname" retry_policy)"
  [[ "$esc_flag" == "retry-after:"* ]] && continue   # transient: no repair to make
  pkg_log="$LOG_DIR/bump-${qname}.log"
  [[ -f "$pkg_log" ]] || pkg_log="$RUN_LOG"
  escalated=$((escalated + 1))
  if "$FLAKE_DIR/scripts/escalate.sh" --package "$qname" --version "$qver" \
        --phase "$qphase" --log "$pkg_log" >>"$RUN_LOG" 2>&1; then
    fixed_by_claude+=("$qname")
  fi
done < <(jq -r '.entries[] | select(.kind=="overlay") | select(.escalation.status // "" == "") | "\(.name)\t\(.blocked_version)\t\(.phase)"' \
           "$FLAKE_DIR/overlays/quarantine.json")

# ── 3. Flake inputs (propose) ─────────────────────────────────────────────
"$SCRIPT_DIR/prepare" >>"$RUN_LOG" 2>&1
prepare_rc=$?
if [[ $prepare_rc -eq 2 ]]; then
  echo "scheduled-check: prepare hit lock contention" >>"$RUN_LOG"
elif [[ $prepare_rc -ne 0 ]]; then
  notify "nixos-config update FAILED" "prepare failed — see $RUN_LOG"
  exit_code=1
fi

after="$(git rev-parse HEAD 2>/dev/null)"

# Nothing moved: stay completely silent (invariant 4).
if [[ "$before" == "$after" ]]; then
  echo "scheduled-check: nothing changed" >>"$RUN_LOG"
  exit $exit_code
fi

# ── 4. Full system build as evidence ──────────────────────────────────────
# prepare builds only when it committed something; a bump-only or
# escalation-only run has had nothing but per-package scoped builds, which
# cannot catch a system-level eval error or a file collision. Always build
# here — invariant 2.
build_log="$LOG_DIR/system-build.log"
if ! nix build "${FLAKE_DIR}#${FLAKE_SYSTEM_ATTR}" --out-link ./result >"$build_log" 2>&1; then
  cat "$build_log" >>"$RUN_LOG"
  rm -f ./result
  # A system build that fails after per-package builds passed is a collision
  # or eval problem, not one package's fault. Leave the commits in place (a
  # hard reset could discard unrelated work) and tell the user how to undo.
  fp="$(classify_failure "$build_log" | cut -f1)"
  quarantine_record "revision-${after:0:7}" "revision" "$after" "$before" \
    "system-build" "$fp" "frozen" "$(tail -40 "$build_log")"
  notify "nixos-config update FAILED" \
    "system build failed at ${after:0:7} ($fp) — see $RUN_LOG; 'git reset --hard ${before:0:7}' discards it"
  exit 1
fi
{
  echo "==> closure diff (running system -> proposed)"
  nix store diff-closures /run/current-system ./result || true
} >>"$RUN_LOG" 2>&1
rm -f ./result

if [[ $ACTIVATE -eq 0 ]]; then
  notify "nixos-config update" "revision ${after:0:7} built — run 'nix run .#activate -- ${after:0:7}'"
  exit $exit_code
fi

# ── 5. Activate ───────────────────────────────────────────────────────────
if ! "$SCRIPT_DIR/activate" "$after" >>"$RUN_LOG" 2>&1; then
  notify "nixos-config update FAILED" "activation of ${after:0:7} failed — see $RUN_LOG"
  exit 1
fi

# ── 6. Health check, and roll back if it fails ────────────────────────────
health_log="$LOG_DIR/health.log"
if ! bash "$FLAKE_DIR/scripts/post-activate-health.sh" >"$health_log" 2>&1; then
  cat "$health_log" >>"$RUN_LOG"
  warn "health check failed — rolling back" >>"$RUN_LOG"
  if "$SCRIPT_DIR/rollback" >>"$RUN_LOG" 2>&1; then
    rolled="rolled back"
  else
    rolled="ROLLBACK ALSO FAILED"
  fi
  # Keyed to the revision, not a package: after a multi-package bump the
  # culprit is ambiguous, and the escalation's job is to bisect it.
  quarantine_record "revision-${after:0:7}" "revision" "$after" "$before" \
    "health-check" "health-failure" "frozen" "$(tail -40 "$health_log")"
  notify "nixos-config update FAILED" \
    "${after:0:7} failed health check, $rolled — see $health_log"
  exit 1
fi

# ── 7. Mirror to the public repo (only now — invariant 3) ─────────────────
"$FLAKE_DIR/scripts/sync-to-public.sh" >>"$RUN_LOG" 2>&1 \
  || echo "scheduled-check: public mirror sync failed — see $RUN_LOG" >>"$RUN_LOG"

# ── 8. Report only what needs a human ─────────────────────────────────────
# Success is silent. Two things are not: a Claude-authored fix that landed
# (needs review), and a package promoted to frozen (needs a decision).
if [[ ${#fixed_by_claude[@]} -gt 0 ]]; then
  notify "nixos-config: Claude repaired an overlay" \
    "${fixed_by_claude[*]} — review 'git log -p' for ${after:0:7}"
fi
frozen="$(jq -r '[.entries[] | select(.retry_policy=="frozen") | .name] | join(" ")' \
  "$FLAKE_DIR/overlays/quarantine.json")"
if [[ -n "$frozen" ]]; then
  notify "nixos-config: packages frozen" "$frozen — see overlays/quarantine.json"
fi

echo "scheduled-check: activated ${after:0:7}, healthy" >>"$RUN_LOG"
exit $exit_code
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/update/test_scheduled_pipeline.sh`
Expected: `PASS: test_scheduled_pipeline`

- [ ] **Step 5: Update the pre-existing scheduled-check test**

`tests/update/test_scheduled_check.sh` asserts the OLD propose-only behaviour (notification text `revision <sha> ready`, never activating). Read it and update its expectations to the new pipeline, or delete it if `test_scheduled_pipeline.sh` now covers every case it did. Keep any case the new test lacks — specifically the "broken environment where `git rev-parse HEAD` fails" case and the "exit 2 on lock contention" case.

Run: `bash tests/update/test_scheduled_check.sh`
Expected: `PASS: test_scheduled_check`

- [ ] **Step 6: Dry-run the real pipeline propose-only**

Run: `SCHEDULED_ACTIVATE=0 bash apps/aarch64-darwin/scheduled-check --no-activate; echo "exit=$?"`
Expected: exits 0. Inspect `logs/nixos-scheduled-check.log` and confirm no `activate` ran and `git log --oneline -5` shows only expected commits. If it committed something unwanted, `git reset --hard` back before continuing.

- [ ] **Step 7: Mirror, run the suite, commit**

Run: `ls apps/*/scheduled-check` and apply the identical file to every copy.

Run: `for f in apps/*/scheduled-check; do md5 -q "$f"; done | sort -u | wc -l`
Expected: `1`

Run: `bash tests/update/run.sh`
Expected: `ALL PASS`

```bash
git add apps/*/scheduled-check tests/update/test_scheduled_pipeline.sh tests/update/test_scheduled_check.sh
git commit -m "feat(update): activate and health-check in the scheduled pipeline"
```

---

### Task 9: Root launchd daemon

Replaces the user agent with a root daemon so activation needs no sudoers relaxation.

**Files:**
- Modify: `hosts/darwin/default.nix:99-131`
- Modify: `overlays/health-checks.json` (the `agents` label, once the real one is known)

**Interfaces:**
- Consumes: `scheduled-check` (Task 8), `post-activate-health.sh` (Task 5).
- Produces: a root `launchd.daemons.nixos-auto-update` firing at 09:00.

- [ ] **Step 1: Read the current agent definition**

Run: `sed -n '90,135p' hosts/darwin/default.nix`

Note the exact `user` variable in scope, the log paths, and the `path` attribute — the replacement must keep all three consistent.

- [ ] **Step 2: Replace the user agent with a root daemon**

In `hosts/darwin/default.nix`, replace the `launchd.user.agents.nixos-update-check` block with:

```nix
  # Daily self-healing update pipeline (docs/superpowers/specs/2026-07-25-self-healing-updates-design.md).
  #
  # This is a root DAEMON, not a user agent, specifically to avoid a
  # passwordless-sudo rule for `darwin-rebuild switch`: that rule would convert
  # any code execution as ${user} into silent root, because `switch --flake`
  # runs arbitrary activation scripts as root. Running the pipeline as root and
  # dropping to ${user} for the unprivileged 90% (bump, build, commit, mirror,
  # escalation) keeps the privileged path a root-owned script instead.
  #
  # Root already has /var/root/.ssh/config -> /run/agenix/ssh-key wired up, so
  # it can fetch the private `secrets` flake input.
  launchd.daemons.nixos-auto-update = {
    script = ''
      exec /usr/bin/sudo -u ${user} \
        ${pkgs.nix}/bin/nix run /Users/${user}/nixos-config#scheduled-check
    '';
    serviceConfig = {
      RunAtLoad = false;
      StartCalendarInterval = [
        {
          Hour = 9;
          Minute = 0;
        }
      ];
      # Keep these paths in sync with the truncation in apps/*/scheduled-check.
      StandardErrorPath = "/Users/${user}/nixos-config/logs/nixos-auto-update.err.log";
      StandardOutPath = "/Users/${user}/nixos-config/logs/nixos-auto-update.out.log";
    };
    path = [ config.environment.systemPath ];
  };
```

**Important — the privilege split needs verification.** The line above drops to `${user}` for the *whole* pipeline, which means `scheduled-check`'s `activate` step will invoke `sudo darwin-rebuild switch` as `${user}` and prompt for a password that nobody can type. Two ways to resolve it; pick one and implement it fully:

- **(a) Split the daemon into two steps** — run the unprivileged part as `${user}` and then, still as root, run the activation and health check directly. This requires factoring `scheduled-check` so the privileged tail can be invoked separately (e.g. `scheduled-check --propose-only` writing the proposed sha to `logs/proposed-revision`, then a root-side `activate`+health+rollback). Cleanest, and keeps `activate`'s existing `sudo` usage untouched for interactive use.
- **(b) Make `activate` detect it is already root** and skip its own `sudo` (`if [[ $EUID -eq 0 ]]; then exec darwin-rebuild ...; else exec sudo -- darwin-rebuild ...; fi`), then run the whole pipeline as root and drop to `${user}` only for the git-touching steps. Fewer moving parts, but the bump/build steps then run as root and would write root-owned files into `~/nixos-config`, which breaks later interactive use — so this variant **must** still `sudo -u ${user}` around `bump-overlays`, `prepare`, `escalate.sh`, and `sync-to-public.sh`.

**Recommendation: (a).** It keeps a clean, testable seam at exactly the point where privilege changes, and leaves `activate` usable by hand. Implement it by adding a `--propose-only` flag to `scheduled-check` that exits after Step 4 (the build) having written `$LOG_DIR/proposed-revision`, and a `--activate-only <sha>` mode that runs Steps 5–8. The daemon script then becomes:

```nix
    script = ''
      set -uo pipefail
      REPO=/Users/${user}/nixos-config
      /usr/bin/sudo -u ${user} ${pkgs.nix}/bin/nix run "$REPO#scheduled-check" -- --propose-only
      rc=$?
      [[ $rc -ne 0 ]] && exit $rc
      rev="$(cat "$REPO/logs/proposed-revision" 2>/dev/null)"
      [[ -z "$rev" ]] && exit 0   # nothing proposed; nothing to activate
      exec ${pkgs.nix}/bin/nix run "$REPO#scheduled-check" -- --activate-only "$rev"
    '';
```

Add the two flags to `apps/*/scheduled-check` and extend `tests/update/test_scheduled_pipeline.sh` with a case asserting that `--propose-only` writes `logs/proposed-revision` and never calls `activate`, and that `--activate-only <sha>` calls `activate`, `health`, and `sync` in that order.

- [ ] **Step 3: Format and check**

Run: `nix fmt`
Run: `nix flake check`
Expected: `treefmt`, `overlays-manifest`, and `darwin-build` all pass

- [ ] **Step 4: Update the health check's expected agent label**

nix-darwin may prefix the daemon label. Determine the real label:

Run: `nix eval --raw '.#darwinConfigurations.garmonbozia.config.launchd.daemons.nixos-auto-update.serviceConfig.Label' 2>/dev/null || echo "(no Label attr; label is the attribute name)"`

Set `agents` in `overlays/health-checks.json` to the label that `sudo launchctl list | grep -i auto-update` reports after the first activation. Until then, leave `agents` as `["nixos-auto-update"]` and expect the health check to flag it.

- [ ] **Step 5: Activate and verify the daemon loaded**

Run: `nix run .#build-switch`
Then: `sudo launchctl list | grep -i auto-update`
Expected: one line showing the daemon loaded

Run: `bash scripts/post-activate-health.sh`
Expected: `health: all assertions passed` (fix the `agents` label if the launchd assertion fails)

- [ ] **Step 6: Trigger the daemon once by hand**

Run: `sudo launchctl kickstart -k system/nixos-auto-update` (substitute the real label)
Then: `tail -40 logs/nixos-scheduled-check.log`
Expected: the pipeline runs end to end. If nothing was outdated it should be silent and log `nothing changed`.

- [ ] **Step 7: Commit**

```bash
git add hosts/darwin/default.nix overlays/health-checks.json apps/*/scheduled-check tests/update/test_scheduled_pipeline.sh
git commit -m "feat(darwin): run the update pipeline as a root launchd daemon"
```

---

### Task 10: Documentation

Makes the new model discoverable — CLAUDE.md currently describes the propose-only design in detail, and every one of those paragraphs is now wrong.

**Files:**
- Modify: `CLAUDE.md` (the "Update Workflow (IMPORTANT)" and "Memories" sections)
- Modify: `docs/overlay-update-routine.md` (add a quarantine section)
- Create: `docs/self-healing-updates.md`

- [ ] **Step 1: Write the operator guide**

Create `docs/self-healing-updates.md` covering, with real commands:
- What the daily 09:00 run does, step by step.
- How to read `overlays/quarantine.json` and what each `retry_policy` means.
- How to un-freeze a package: `nix run .#bump-overlays -- --only <pkg>` bypasses the quarantine gate (it is an explicit human override), and clearing an entry by hand.
- How to read `logs/escalation-costs.tsv` and retune the five brakes (name the constants: `ESCALATE_MAX_PER_RUN` / the `3` in scheduled-check's escalation loop, `MAX_TURNS`, `TIMEOUT`, the `attempts >= 3` promotion in `quarantine_record`, and the fingerprint dedup in `quarantine_should_escalate`).
- How to disable the automation: `sudo launchctl bootout system/nixos-auto-update`, and `SCHEDULED_ACTIVATE=0` for a propose-only run.
- How to recover from a bad auto-activation: `nix run .#rollback -- --list`, then `nix run .#rollback -- <gen>`.

- [ ] **Step 2: Rewrite CLAUDE.md's "Update Workflow (IMPORTANT)" section**

Replace the paragraphs describing the propose-only model. The specific claims that are now false and must be corrected:
- "`scheduled-check` … **never activates** — you review and run `nix run .#activate -- <rev>` manually" → it now activates, health-checks, and rolls back automatically.
- "`scheduled-check` … runs `bump-overlays --mechanical-only`" → it now runs `bump-overlays` with no flag; per-package `cadence_hours` handles the branch-HEAD packages.
- "`pinned_inputs[]` entries are always frozen regardless of cadence" → they now get one speculative unpin attempt per `retry_cadence_hours`.
- "the go-source packages (`beads`, `c4`, `hey-cli`) are excluded by `--mechanical-only`" → they are included; `c4`/`hey-cli` are weekly.

Add a short paragraph pointing at `docs/self-healing-updates.md` and `overlays/quarantine.json`.

- [ ] **Step 3: Add a "Memories" entry**

Append to CLAUDE.md's Memories list:

```markdown
- The daily 09:00 root daemon (`nixos-auto-update`) auto-bumps every overlay, builds,
  activates, health-checks, and rolls back on failure. Breakage is recorded per-version in
  `overlays/quarantine.json` — a quarantine blocks exactly the failing version, so anything
  newer is retried automatically. See `docs/self-healing-updates.md`.
```

- [ ] **Step 4: Add a quarantine section to the overlay routine doc**

Append a short section to `docs/overlay-update-routine.md` explaining that a package may be quarantined (so a manual bump attempt needs `--only <pkg>` to bypass the gate), and that after a successful manual bump the entry should be cleared:

```bash
# Clear a quarantine entry after fixing a package by hand:
QUARANTINE_FILE=overlays/quarantine.json bash -c \
  'source scripts/update-state.sh; source scripts/quarantine.sh; quarantine_clear <pkg>'
```

- [ ] **Step 5: Verify and commit**

Run: `nix flake check`
Expected: all three checks pass

Run: `bash tests/update/run.sh`
Expected: `ALL PASS`

```bash
git add CLAUDE.md docs/self-healing-updates.md docs/overlay-update-routine.md
git commit -m "docs: document the self-healing update pipeline"
```

---

## Verification Checklist

Run all of these before considering the plan complete:

- [ ] `bash tests/update/run.sh` → `ALL PASS`
- [ ] `nix fmt` → no diff afterwards (`git diff --quiet`)
- [ ] `nix flake check` → `treefmt`, `overlays-manifest`, `darwin-build` all pass
- [ ] `bash scripts/post-activate-health.sh` → `health: all assertions passed`
- [ ] `sudo launchctl list | grep -i auto-update` → the daemon is loaded
- [ ] `SCHEDULED_ACTIVATE=0 bash apps/aarch64-darwin/scheduled-check --no-activate` → exits 0, activates nothing
- [ ] `git log --oneline -12` → one commit per task, no stray commits
- [ ] Public mirror is in sync: `git -C ~/src/nixos-config log --oneline -3` shows the mirrored commits
- [ ] `jq empty overlays/quarantine.json overlays/health-checks.json overlays/updates.json` → all valid JSON
- [ ] One full live daily run observed: `sudo launchctl kickstart -k system/<label>` then read `logs/nixos-scheduled-check.log`

## Known Deviations From the Spec

- **Revision-level failures notify but do not escalate.** An earlier spec draft had a
  health-check failure escalate with a bisect-and-attribute job. That is deliberately
  deferred: after a multi-package bump the culprit is ambiguous, the machine is already
  rolled back and healthy, and the `frozen` revision entry stops the pipeline from
  re-proposing it. Escalation stays scoped to per-package repair, where the culprit is
  unambiguous by construction. The spec has been corrected to match.

- **§8's "automated `vendorHash` refetch for go-source"** is already implemented (`bump_gosource` in `apps/aarch64-darwin/bump-overlays:170`). Task 4 only removes the `--mechanical-only` exclusion and adds cadence gating. The spec has been corrected.
- **Successful unpin is a half-step (Task 7).** A passing speculative build leaves the bumped `flake.lock` and *reports* that `flake.nix`'s `url` and the `pinned_inputs[]` entry need editing, rather than rewriting them — deleting a pin's `reason`/`risk`/`unpin_when` prose automatically would silently discard the documented reason it existed.
- **The privilege split in Task 9 Step 2 is left as an explicit two-option decision** with a recommendation, because the naive "drop to `${user}` for everything" daemon script cannot activate (it would need a password nobody can type). Implement option (a).
- **Battery-skip is not implemented.** Spec §9 raises "consider skipping activation when on battery" as a *possible* mitigation for the mid-workday-activation risk, not a requirement, so no task implements it. If wanted later it is a three-line guard before Task 8's activate step:

  ```bash
  if [[ "$(pmset -g batt | head -1)" != *"AC Power"* ]]; then
    notify "nixos-config update" "revision ${after:0:7} built; deferring activation (on battery)"
    exit 0
  fi
  ```

  Deliberately left out of the plan: it makes activation non-deterministic day to day, which is worth deciding after seeing how disruptive the 09:00 switch actually is in practice.
