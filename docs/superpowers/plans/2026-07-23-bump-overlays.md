# Automated Overlay Bump Routine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `nix run .#bump-overlays`, a command that mechanically applies
version bumps for the subset of pinned overlays where a bump is a pure,
verifiable value substitution (7 prebuilt-binary/-npm overlays, the `go`
overlay on patch bumps, and 3 go-source overlays), plus a tutorial documenting
the automated path and what's still manual.

**Architecture:** A single new executable, `apps/aarch64-darwin/bump-overlays`
(matching the existing `fix-hashes`/`check`/`prepare` convention of one
self-contained script per app, sourcing the shared `_common.sh` /
`update-state.sh` / `update-probe.sh` libraries). It reuses
`scripts/check-overlay-versions.sh --json` for detection and the *existing*
`fix-hashes --only <name>` for hash-fixing prebuilt-binary overlays (it
already does exactly the literal-value hash substitution this design calls
for — it just needs three more overlay names added to its list). New code is
therefore small: a version-bump substitution step, a go-source-specific
vendorHash resolution step, and the per-package orchestration
(detect → bump version → verify → commit → continue-on-failure).

**Tech Stack:** bash (existing script conventions), `python3` for anchored
regex substitution (matching `fix-hashes`'s existing `extract_pairs` pattern),
`jq` for JSON/manifest manipulation, `nix-prefetch-url` / `nix hash convert` /
`nix build --impure --expr` (all already used identically elsewhere in this
repo).

## Global Constraints

- Every step that touches `.nix` files must keep `nix fmt` clean and
  `nix flake check` green (`treefmt` + `overlays-manifest` + `darwin-build`).
- Every overlay in `overlays/` must stay listed in `overlays/updates.json`
  (`packages[]` or `skip[]`) — enforced by `scripts/check-overlay-manifest.sh`.
- `overlays/updates.json`'s `current_version` for a package must always
  appear verbatim in that package's overlay file (same manifest check,
  invariant 4) — every task that bumps a version must update both files
  together, never one alone.
- No new test framework: this repo has no `scripts/` test directory or bats
  suite today; `check-overlay-versions.sh`/`fix-hashes` are validated by
  direct invocation. Follow that convention — no new test harness.
- Commit style: `overlays: update <name> to v<version>` (see `git log
  --oneline | grep 'overlays: update'` for precedent), one commit per
  package bump (per the approved design).
- This repo (`~/nixos-config`) has no git remote; its post-commit hook
  mirrors and pushes every commit to the public repo automatically. No
  separate publishing step is needed for any task below.

---

### Task 1: Extend `fix-hashes` to recognize go, dcg, aws-cdk-cli

`apps/aarch64-darwin/fix-hashes`'s hardcoded `PINNED_OVERLAYS` array (lines
89-97) is missing three overlays this plan needs it to hash-fix:
`55-go.nix`, `91-dcg.nix`, `95-aws-cdk-cli.nix`. Without this, `fix-hashes
--only go` (etc.) prints `(skip: 'go' -> '55-go.nix' not in
PINNED_OVERLAYS)` and does nothing — `bump-overlays` would silently fail to
fix hashes for these three packages.

**Files:**
- Modify: `apps/aarch64-darwin/fix-hashes:89-97`

**Interfaces:**
- Consumes: nothing new.
- Produces: `fix-hashes --only go`, `fix-hashes --only dcg`, `fix-hashes
  --only aws-cdk-cli` now work (Task 3 depends on this).

- [ ] **Step 1: Add the three overlay filenames to `PINNED_OVERLAYS`**

Edit `apps/aarch64-darwin/fix-hashes`, changing:

```bash
PINNED_OVERLAYS=(
  "20-ngrok.nix"
  "25-uv.nix"
  "30-mise.nix"
  "40-codex-openai.nix"
  "41-claude-code.nix"
  "50-trailbase.nix"
  "70-igir.nix"
)
```

to:

```bash
PINNED_OVERLAYS=(
  "20-ngrok.nix"
  "25-uv.nix"
  "30-mise.nix"
  "40-codex-openai.nix"
  "41-claude-code.nix"
  "50-trailbase.nix"
  "55-go.nix"
  "70-igir.nix"
  "91-dcg.nix"
  "95-aws-cdk-cli.nix"
)
```

- [ ] **Step 2: Verify the three overlays are now recognized**

Run: `bash apps/aarch64-darwin/fix-hashes --only go,dcg,aws-cdk-cli`
Expected: prints `--- 55-go.nix ---`, `--- 91-dcg.nix ---`, `---
95-aws-cdk-cli.nix ---` sections, each URL checked shows `ok` (all three are
currently pinned to their latest known-good hash), ends with `Checked N
URL(s): 0 updated, 0 error(s).` and exit 0. This also confirms `fix-hashes`'
generic `url`/`hash` extractor already handles these overlays' shapes (single
hash for aws-cdk-cli, 4-platform dict for go and dcg) with no changes needed.

If any show `stale` or `fetch failed`, stop and investigate before
continuing — Task 3 depends on this baseline being clean.

- [ ] **Step 3: Commit**

```bash
git add apps/aarch64-darwin/fix-hashes
git commit -m "fix(update): recognize go, dcg, aws-cdk-cli in fix-hashes --only"
```

---

### Task 2: `bump-overlays` skeleton — detection, precondition, dry-run, flake wiring

Build the command's scaffolding first: argument parsing, the dirty-tree
precondition, detection (reusing `check-overlay-versions.sh --json` joined
with `update_type` from `overlays/updates.json`), classification into
mechanical / go-source / skipped, and `--dry-run` output. No mutation yet —
Tasks 3 and 4 fill in the two bump paths. This task is independently
testable: `--dry-run` against the live repo (uv and aws-cdk-cli are
currently outdated) must print a correct plan and touch nothing.

**Files:**
- Create: `apps/aarch64-darwin/bump-overlays`
- Modify: `flake.nix` (add `"bump-overlays" = mkApp "bump-overlays" system;`
  to `mkDarwinApps`)

**Interfaces:**
- Consumes: `scripts/check-overlay-versions.sh --json` (existing, output
  shape `[{name,current,latest,outdated,status}]`); `overlays/updates.json`
  `.packages[].update_type` / `.overlay` / `.name`; `_common.sh`'s
  `locate_flake`, `msg`, `warn`, `err`.
- Produces: for Task 3/4 to fill in — a `bump_package "$name" "$overlay_file"
  "$update_type" "$new_version"` function stub that Tasks 3/4 implement the
  body of; a `classify_targets` step that produces three bash arrays:
  `MECH_TARGETS` (name/new_version pairs for the prebuilt-binary family, incl.
  `go` only when patch-level), `GOSRC_TARGETS` (beads/c4/hey-cli), and
  `SKIPPED` (name + reason, for the summary).

- [ ] **Step 1: Write the script skeleton**

Create `apps/aarch64-darwin/bump-overlays`:

```bash
#!/usr/bin/env bash
# Mechanically apply version bumps for overlays where doing so is a pure,
# verifiable value substitution: fetch a new hash, substitute a literal
# value, verify with a scoped build, commit. Everything else — mise,
# yt-dlp, ngrok, tmux, and `go` on a minor-version bump — stays manual.
# See docs/overlay-bump-tutorial.md and docs/overlay-update-routine.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_common.sh"
FLAKE_DIR="$(locate_flake)" || exit 1
# shellcheck source=/dev/null
source "$FLAKE_DIR/scripts/update-state.sh"
cd "$FLAKE_DIR"

MANIFEST="$FLAKE_DIR/overlays/updates.json"

DRY_RUN=0
ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    *) err "unknown argument: $1"; exit 1 ;;
  esac
done

# Overlay update_types this script knows how to bump mechanically via
# version-substitution + `fix-hashes --only` (Task 3).
MECHANICAL_TYPES=("prebuilt-binary" "prebuilt-binary-multiplatform" "prebuilt-npm")
# Packages with bespoke go-source handling (Task 4), regardless of update_type.
GOSRC_NAMES=("beads" "c4" "hey-cli")

# Precondition: never mix with in-progress manual edits.
if [[ -n "$(git status --porcelain -- overlays/)" ]]; then
  err "overlays/ has uncommitted changes — commit or stash before running bump-overlays"
  exit 1
fi

# ── Detect ──────────────────────────────────────────────────────────────────
json="$(bash "$FLAKE_DIR/scripts/check-overlay-versions.sh" --json)"

declare -a MECH_NAMES=() MECH_VERSIONS=()
declare -a GOSRC_NAMES_TARGET=()
declare -a SKIPPED_NAMES=() SKIPPED_REASONS=()

while IFS=$'\t' read -r name latest; do
  [[ -z "$name" ]] && continue
  if [[ -n "$ONLY" ]] && [[ ",$ONLY," != *",$name,"* ]]; then
    continue
  fi
  update_type="$(jq -r --arg n "$name" '.packages[] | select(.name==$n) | .update_type' "$MANIFEST")"
  is_gosrc=0
  for g in "${GOSRC_NAMES[@]}"; do [[ "$g" == "$name" ]] && is_gosrc=1 && break; done

  if [[ $is_gosrc -eq 1 ]]; then
    GOSRC_NAMES_TARGET+=("$name")
  elif [[ "$name" == "go" ]]; then
    current="$(jq -r --arg n "$name" '.packages[] | select(.name==$n) | .current_version' "$MANIFEST")"
    cur_mm="${current%.*}"; new_mm="${latest%.*}"
    if [[ "$cur_mm" != "$new_mm" ]]; then
      SKIPPED_NAMES+=("$name"); SKIPPED_REASONS+=("minor/major version change ($current -> $latest) needs manual go_1_XX attribute rename")
      continue
    fi
    MECH_NAMES+=("$name"); MECH_VERSIONS+=("$latest")
  else
    is_mech=0
    for t in "${MECHANICAL_TYPES[@]}"; do [[ "$t" == "$update_type" ]] && is_mech=1 && break; done
    if [[ $is_mech -eq 1 ]]; then
      MECH_NAMES+=("$name"); MECH_VERSIONS+=("$latest")
    else
      SKIPPED_NAMES+=("$name"); SKIPPED_REASONS+=("update_type '$update_type' not automated — see docs/overlay-update-routine.md")
    fi
  fi
done < <(echo "$json" | jq -r '.[] | select(.outdated) | "\(.name)\t\(.latest)"')

if [[ ${#MECH_NAMES[@]} -eq 0 && ${#GOSRC_NAMES_TARGET[@]} -eq 0 ]]; then
  msg "Nothing to bump."
  if [[ ${#SKIPPED_NAMES[@]} -gt 0 ]]; then
    warn "Outdated but not automated:"
    for i in "${!SKIPPED_NAMES[@]}"; do
      warn "  ${SKIPPED_NAMES[$i]}: ${SKIPPED_REASONS[$i]}"
    done
  fi
  exit 0
fi

msg "Planned mechanical bumps: ${MECH_NAMES[*]:-none}"
msg "Planned go-source bumps: ${GOSRC_NAMES_TARGET[*]:-none}"
if [[ ${#SKIPPED_NAMES[@]} -gt 0 ]]; then
  warn "Skipped (not automated):"
  for i in "${!SKIPPED_NAMES[@]}"; do
    warn "  ${SKIPPED_NAMES[$i]}: ${SKIPPED_REASONS[$i]}"
  done
fi

if [[ $DRY_RUN -eq 1 ]]; then
  msg "--dry-run: no files touched, nothing built, nothing committed."
  exit 0
fi

BUMPED=() FAILED=()

# Task 3 fills in bump_mechanical(); Task 4 fills in bump_gosource().
for i in "${!MECH_NAMES[@]}"; do
  name="${MECH_NAMES[$i]}"; new_version="${MECH_VERSIONS[$i]}"
  if declare -F bump_mechanical >/dev/null && bump_mechanical "$name" "$new_version"; then
    BUMPED+=("$name")
  else
    FAILED+=("$name")
  fi
done
for name in "${GOSRC_NAMES_TARGET[@]}"; do
  if declare -F bump_gosource >/dev/null && bump_gosource "$name"; then
    BUMPED+=("$name")
  else
    FAILED+=("$name")
  fi
done

echo ""
msg "Bumped: ${#BUMPED[@]} (${BUMPED[*]:-none})"
[[ ${#FAILED[@]} -gt 0 ]] && err "Failed: ${#FAILED[@]} (${FAILED[*]}) — see docs/overlay-update-routine.md"
msg "Skipped: ${#SKIPPED_NAMES[@]} (${SKIPPED_NAMES[*]:-none})"
[[ ${#FAILED[@]} -eq 0 ]]
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x apps/aarch64-darwin/bump-overlays
```

- [ ] **Step 3: Wire it into `flake.nix`**

In `flake.nix`, inside `mkDarwinApps` (around the existing `"fix-hashes" =
mkApp "fix-hashes" system;` line), add:

```nix
          "fix-hashes" = mkApp "fix-hashes" system;
          # Mechanical overlay version bumps (fetch + substitute + verify +
          # commit) for the subset where that's fully safe — see
          # docs/overlay-bump-tutorial.md. Everything else stays manual.
          "bump-overlays" = mkApp "bump-overlays" system;
```

- [ ] **Step 4: Run `nix fmt` and verify the flake still evaluates**

Run: `nix fmt && nix flake check --no-build 2>&1 | tail -20`
Expected: no formatting diff beyond what `nix fmt` itself applies; flake
evaluates without error (full `darwin-build` check may still run — that's
fine, just confirm no eval-time error referencing `bump-overlays`).

- [ ] **Step 5: Dry-run against the live repo**

Run: `nix run .#bump-overlays -- --dry-run`
Expected output includes (uv and aws-cdk-cli are the two currently-outdated
mechanical packages from the earlier `nix run .#check`):

```
Planned mechanical bumps: uv aws-cdk-cli
Planned go-source bumps: none
--dry-run: no files touched, nothing built, nothing committed.
```

(Order of `uv`/`aws-cdk-cli` may vary — both must appear.) Confirm with `git
status` that nothing changed.

- [ ] **Step 6: Commit**

```bash
git add apps/aarch64-darwin/bump-overlays flake.nix
git commit -m "feat(overlays): add bump-overlays detection skeleton"
```

---

### Task 3: Mechanical bump path (prebuilt-binary family + go patch bumps)

Implement `bump_mechanical()`, called by the Task 2 skeleton for each
package in `MECH_NAMES`. This is the path for claude-code, codex-openai, uv,
trailbase, igir, dcg, aws-cdk-cli, and `go` (patch-level only).

**Files:**
- Modify: `apps/aarch64-darwin/bump-overlays` (add `bump_mechanical()` above
  the detection block, since bash requires function definitions before
  first use in this script's straight-line execution)

**Interfaces:**
- Consumes: `MANIFEST` (from Task 2, already in scope); `fix-hashes --only
  <name>` (Task 1, exit 0 on success); `nix-prefetch-url` / `nix hash
  convert` are NOT needed here — `fix-hashes` already does the hash fetch
  and fix internally.
- Produces: `bump_mechanical(name, new_version)` — returns 0 on a
  successful, committed bump; returns 1 (and leaves the tree exactly as it
  was before the call) on any failure.

- [ ] **Step 1: Write the version-substitution helper and `bump_mechanical`**

Insert this block into `apps/aarch64-darwin/bump-overlays`, directly above
the `# Precondition:` comment (i.e., before it's first called):

```bash
# Substitute the literal `version = "OLD";` assignment for `version = "NEW";`.
# Aborts (prints to stderr, returns 1) unless exactly one such assignment is
# found — never guesses, never touches comment text that happens to mention
# the version number (e.g. 55-go.nix's header comment).
bump_version_string() {
  local file="$1" old="$2" new="$3"
  python3 - "$file" "$old" "$new" <<'PYEOF'
import re, sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
pattern = re.compile(r'(version\s*=\s*")' + re.escape(old) + r'(")')
matches = list(pattern.finditer(text))
if len(matches) != 1:
    print(f"expected exactly 1 version assignment matching {old!r} in {path}, found {len(matches)}", file=sys.stderr)
    sys.exit(1)
open(path, "w").write(pattern.sub(r'\g<1>' + new + r'\g<2>', text))
PYEOF
}

bump_mechanical() {
  local name="$1" new_version="$2"
  local overlay_rel overlay_file current_version
  overlay_rel="$(jq -r --arg n "$name" '.packages[] | select(.name==$n) | .overlay' "$MANIFEST")"
  overlay_file="$FLAKE_DIR/$overlay_rel"
  current_version="$(jq -r --arg n "$name" '.packages[] | select(.name==$n) | .current_version' "$MANIFEST")"

  msg "-- $name: $current_version -> $new_version"

  if ! bump_version_string "$overlay_file" "$current_version" "$new_version"; then
    err "  version substitution failed, leaving $overlay_rel untouched"
    return 1
  fi

  if ! bash "$SCRIPT_DIR/fix-hashes" --only "$name" >/tmp/bump-overlays-fixhashes.$$.log 2>&1; then
    err "  fix-hashes --only $name failed:"
    cat /tmp/bump-overlays-fixhashes.$$.log >&2
    rm -f /tmp/bump-overlays-fixhashes.$$.log
    git checkout -- "$overlay_rel"
    return 1
  fi
  rm -f /tmp/bump-overlays-fixhashes.$$.log

  if ! nix build --no-link --impure --expr \
      "let pkgs = import <nixpkgs> { overlays = [ (import ./$overlay_rel) ]; }; in pkgs.${name}" \
      >/tmp/bump-overlays-build.$$.log 2>&1; then
    err "  verification build failed:"
    tail -30 /tmp/bump-overlays-build.$$.log >&2
    rm -f /tmp/bump-overlays-build.$$.log
    git checkout -- "$overlay_rel"
    return 1
  fi
  rm -f /tmp/bump-overlays-build.$$.log

  jq --arg n "$name" --arg v "$new_version" \
    '(.packages[] | select(.name==$n) | .current_version) = $v' \
    "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

  git add "$overlay_rel" "$MANIFEST"
  git commit -q -m "overlays: update $name to v$new_version"
  msg "  committed: overlays: update $name to v$new_version"
  return 0
}
```

- [ ] **Step 2: Verify the tree is clean, then dry-run once more to confirm the plan is unchanged**

Run: `git status --porcelain overlays/` (expect empty), then `nix run
.#bump-overlays -- --dry-run` (expect same output as Task 2 Step 5).

- [ ] **Step 3: Live run against the two currently-outdated mechanical packages**

Run: `nix run .#bump-overlays`
Expected: two new commits appear (`overlays: update uv to v0.11.32`,
`overlays: update aws-cdk-cli to v2.1133.0` — exact versions depend on
upstream at run time, check with `nix run .#check` immediately before if you
want the exact expected numbers), final summary line `Bumped: 2 (uv
aws-cdk-cli)`, `Skipped: 0`. Verify with:

```bash
git log --oneline -3
git show --stat HEAD~1 HEAD
```

Each commit should touch exactly the overlay file + `overlays/updates.json`.

- [ ] **Step 4: Confirm `nix run .#check` now reports both up to date**

Run: `rm -f .update-state.json && nix run .#check`
Expected: no `overlays outdated` line (or it lists neither `uv` nor
`aws-cdk-cli`).

- [ ] **Step 5: Confirm the manifest invariant still holds**

Run: `bash scripts/check-overlay-manifest.sh`
Expected: exits 0, no `FAIL:` lines.

(Step 3 already produced real commits — no separate commit step for this
task. If Step 3's live run fails for either package, fix the root cause
before proceeding to Task 4, since Task 4 builds on the same `bump-overlays`
file.)

---

### Task 4: go-source bump path (beads, c4, hey-cli)

Implement `bump_gosource()`. Two shapes: **beads** is tag-based
(`update_type` doesn't matter here — it's dispatched by name, see Task 2's
`GOSRC_NAMES`), using the same `check-overlay-versions.sh` `latest` value as
a real version string. **c4** and **hey-cli** are commit-tracked
(`github-commits` method) — `check-overlay-versions.sh --json`'s `latest`
field for these is a *truncated 12-char* SHA (existing script behavior, see
`scripts/check-overlay-versions.sh:129-136` and its `sub(" \\(commit\\)$";
"")` in the JSON branch), so this task re-fetches the full 40-char SHA
directly rather than relying on that truncated value.

Since beads/c4/hey-cli are all currently up to date (Task 1 confirmed this
indirectly, and none appeared in Task 2/3's outdated lists), this task is
verified with **fixture files**, not a live run — matching the design spec's
testing section.

**Files:**
- Modify: `apps/aarch64-darwin/bump-overlays` (add `bump_gosource()` and its
  two helper functions, next to `bump_mechanical()`)
- Test fixtures (scratch, not committed): copies of `overlays/60-beads.nix`
  and `overlays/56-c4.nix` used only for the Step 2/4 verification below.

**Interfaces:**
- Consumes: `MANIFEST`, `FLAKE_DIR`, `bump_version_string()` (Task 3).
- Produces: `bump_gosource(name)` — same contract as `bump_mechanical`:
  returns 0 and leaves a committed bump, or returns 1 and leaves the tree
  untouched.

- [ ] **Step 1: Write the go-source helpers and `bump_gosource`**

Insert this block into `apps/aarch64-darwin/bump-overlays`, directly below
`bump_mechanical()`:

```bash
# Substitute a single anchored `field = "OLD";` assignment. Same
# exactly-one-match safety net as bump_version_string, generalized to any
# field name (used for `hash`, `rev`, `vendorHash`).
bump_field_string() {
  local file="$1" field="$2" old="$3" new="$4"
  python3 - "$file" "$field" "$old" "$new" <<'PYEOF'
import re, sys
path, field, old, new = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
text = open(path).read()
pattern = re.compile(re.escape(field) + r'(\s*=\s*")' + re.escape(old) + r'(")')
matches = list(pattern.finditer(text))
if len(matches) != 1:
    print(f"expected exactly 1 {field!r} assignment matching {old!r} in {path}, found {len(matches)}", file=sys.stderr)
    sys.exit(1)
open(path, "w").write(pattern.sub(field + r'\g<1>' + new + r'\g<2>', text))
PYEOF
}

# vendorHash is sometimes `null` (bare, unquoted) rather than a string (c4's
# current state) — normalize it to an empty string first so bump_field_string
# has a quoted literal to anchor on.
normalize_vendor_hash_to_blank() {
  local file="$1"
  python3 - "$file" <<'PYEOF'
import re, sys
path = sys.argv[1]
text = open(path).read()
text, n = re.subn(r'vendorHash\s*=\s*null\s*;', 'vendorHash = "";', text)
if n == 0:
    text, n2 = re.subn(r'vendorHash\s*=\s*"[^"]*"\s*;', 'vendorHash = "";', text)
    if n2 != 1:
        print(f"expected exactly 1 vendorHash assignment in {path}, found {n2}", file=sys.stderr)
        sys.exit(1)
open(path, "w").write(text)
PYEOF
}

resolve_vendor_hash() {
  local overlay_rel="$1" name="$2" got
  got="$(nix build --no-link --impure --expr \
    "let pkgs = import <nixpkgs> { overlays = [ (import ./$overlay_rel) ]; }; in pkgs.${name}" \
    2>&1 | grep 'got:' | awk '{print $2}' | head -1)"
  [[ -n "$got" ]] || return 1
  printf '%s' "$got"
}

github_full_sha() {
  local repo="$1" branch="$2"
  curl -sf --max-time 15 -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${repo}/commits/${branch}" 2>/dev/null \
    | jq -r '.sha // empty'
}

bump_gosource() {
  local name="$1"
  local overlay_rel overlay_file
  overlay_rel="$(jq -r --arg n "$name" '.packages[] | select(.name==$n) | .overlay' "$MANIFEST")"
  overlay_file="$FLAKE_DIR/$overlay_rel"

  local new_version new_hash_url current_version current_rev new_rev
  local check_method repo branch
  check_method="$(jq -r --arg n "$name" '.packages[] | select(.name==$n) | .check.method' "$MANIFEST")"
  repo="$(jq -r --arg n "$name" '.packages[] | select(.name==$n) | .check.repo' "$MANIFEST")"
  current_version="$(jq -r --arg n "$name" '.packages[] | select(.name==$n) | .current_version' "$MANIFEST")"

  if [[ "$check_method" == "github-release" ]]; then
    # beads: tag-based release.
    new_version="$(echo "$json" | jq -r --arg n "$name" '.[] | select(.name==$n) | .latest')"
    new_hash_url="https://github.com/${repo}/archive/refs/tags/v${new_version}.tar.gz"
    msg "-- $name: $current_version -> $new_version"
    bump_version_string "$overlay_file" "$current_version" "$new_version" || return 1
  else
    # c4 / hey-cli: commit-tracked, no tags.
    branch="$(jq -r --arg n "$name" '.packages[] | select(.name==$n) | .check.branch' "$MANIFEST")"
    current_rev="$(jq -r --arg n "$name" '.packages[] | select(.name==$n) | .current_rev' "$MANIFEST")"
    new_rev="$(github_full_sha "$repo" "$branch")"
    if [[ -z "$new_rev" ]]; then
      err "  could not fetch latest commit SHA for $repo@$branch"
      return 1
    fi
    if [[ "$new_rev" == "$current_rev" ]]; then
      msg "-- $name: already at latest commit ($current_rev), nothing to do"
      return 0
    fi
    new_version="0-unstable-$(date -u +%Y-%m-%d)"
    new_hash_url="https://github.com/${repo}/archive/${new_rev}.tar.gz"
    msg "-- $name: $current_rev -> $new_rev ($current_version -> $new_version)"
    bump_field_string "$overlay_file" "rev" "$current_rev" "$new_rev" || return 1
    bump_version_string "$overlay_file" "$current_version" "$new_version" || { git checkout -- "$overlay_rel"; return 1; }
  fi

  local current_src_hash new_src_hash_raw new_src_hash
  current_src_hash="$(python3 -c '
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"fetchFromGitHub\s*\{[^}]*?hash\s*=\s*\"([^\"]+)\"", text, re.DOTALL)
print(m.group(1) if m else "")
' "$overlay_file")"
  if [[ -z "$current_src_hash" ]]; then
    err "  could not locate current fetchFromGitHub hash in $overlay_rel"
    git checkout -- "$overlay_rel"
    return 1
  fi
  new_src_hash_raw="$(nix-prefetch-url --unpack "$new_hash_url" 2>/dev/null)" || {
    err "  nix-prefetch-url failed for $new_hash_url"
    git checkout -- "$overlay_rel"
    return 1
  }
  new_src_hash="$(nix hash convert --hash-algo sha256 --to sri "$new_src_hash_raw")"
  bump_field_string "$overlay_file" "hash" "$current_src_hash" "$new_src_hash" || { git checkout -- "$overlay_rel"; return 1; }

  normalize_vendor_hash_to_blank "$overlay_file" || { git checkout -- "$overlay_rel"; return 1; }
  local vendor_hash
  vendor_hash="$(resolve_vendor_hash "$overlay_rel" "$name")"
  if [[ -z "$vendor_hash" ]]; then
    err "  could not resolve vendorHash from build error for $name"
    git checkout -- "$overlay_rel"
    return 1
  fi
  bump_field_string "$overlay_file" "vendorHash" "" "$vendor_hash" || { git checkout -- "$overlay_rel"; return 1; }

  if ! nix build --no-link --impure --expr \
      "let pkgs = import <nixpkgs> { overlays = [ (import ./$overlay_rel) ]; }; in pkgs.${name}" \
      >/tmp/bump-overlays-gosrc.$$.log 2>&1; then
    err "  verification build failed after vendorHash resolution:"
    tail -30 /tmp/bump-overlays-gosrc.$$.log >&2
    rm -f /tmp/bump-overlays-gosrc.$$.log
    git checkout -- "$overlay_rel"
    return 1
  fi
  rm -f /tmp/bump-overlays-gosrc.$$.log

  jq --arg n "$name" --arg v "$new_version" \
    '(.packages[] | select(.name==$n) | .current_version) = $v' \
    "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
  if [[ "$check_method" != "github-release" ]]; then
    jq --arg n "$name" --arg r "$new_rev" \
      '(.packages[] | select(.name==$n) | .current_rev) = $r' \
      "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
  fi

  git add "$overlay_rel" "$MANIFEST"
  git commit -q -m "overlays: update $name to v$new_version"
  msg "  committed: overlays: update $name to v$new_version"
  return 0
}
```

- [ ] **Step 2: Fixture-test the beads (tag-based) path's substitution logic**

This validates `bump_version_string` + the `fetchFromGitHub` hash regex +
`bump_field_string` against beads' real shape, without touching the repo or
running a network fetch:

```bash
cp overlays/60-beads.nix /tmp/beads-fixture.nix
python3 - /tmp/beads-fixture.nix <<'PYEOF'
import re, sys
path = sys.argv[1]
text = open(path).read()
pattern = re.compile(r'(version\s*=\s*")1\.1\.0(")')
assert len(pattern.findall(text)) == 1, "fixture assumption broken: version 1.1.0 not found exactly once"
text = pattern.sub(r'\g<1>9.9.9\g<2>', text)
open(path, "w").write(text)
PYEOF
grep -n 'version = "9.9.9"' /tmp/beads-fixture.nix
rm /tmp/beads-fixture.nix
```

Expected: the `grep` prints the `version = "9.9.9";` line — confirms the
same substitution `bump_version_string` performs works correctly against the
real beads.nix shape. (This directly exercises the same regex the shell
function uses; it's inlined here rather than sourcing the function because
`bump-overlays` isn't meant to be sourced as a library — see the Global
Constraints note about no new test harness.)

- [ ] **Step 3: Fixture-test the c4/hey-cli (commit-tracked) path's substitution logic**

```bash
cp overlays/56-c4.nix /tmp/c4-fixture.nix
OLD_REV="136d74d1bb6b889ef7eb160b3c7529cbde02c45d"
NEW_REV="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
python3 - /tmp/c4-fixture.nix "$OLD_REV" "$NEW_REV" <<'PYEOF'
import re, sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
pattern = re.compile(r'(rev\s*=\s*")' + re.escape(old) + r'(")')
assert len(pattern.findall(text)) == 1, "fixture assumption broken: rev not found exactly once"
text = pattern.sub(r'\g<1>' + new + r'\g<2>', text)
# vendorHash = null normalization
text2, n = re.subn(r'vendorHash\s*=\s*null\s*;', 'vendorHash = "";', text)
assert n == 1, f"expected 1 vendorHash=null, found {n}"
open(path, "w").write(text2)
PYEOF
grep -n 'rev = "aaaa\|vendorHash = ""' /tmp/c4-fixture.nix
rm /tmp/c4-fixture.nix
```

Expected: both the new `rev` line and `vendorHash = "";` are present —
confirms the rev substitution and the `vendorHash = null` → `""`
normalization both work against c4's real shape (the one overlay in scope
that uses bare `null` rather than a string for `vendorHash`).

- [ ] **Step 4: Full dry-run sanity check (no live gosource bump — nothing is outdated)**

Run: `nix run .#bump-overlays -- --dry-run`
Expected: `Planned go-source bumps: none` (beads/c4/hey-cli are all current
per Task 1's baseline check) — confirms the detection/classification wiring
from Task 2 correctly routes these three names to `GOSRC_NAMES_TARGET` when
they *are* outdated, without asserting anything about right-now upstream
state. This is the practical limit of testing this path without waiting for
a real upstream bump; the live end-to-end path (steps through
`resolve_vendor_hash` and the final verification build) will get its first
real exercise the next time one of these three actually goes outdated —
note this explicitly in the tutorial (Task 5).

- [ ] **Step 5: `nix fmt` and commit**

```bash
nix fmt
git add apps/aarch64-darwin/bump-overlays
git commit -m "feat(overlays): add go-source bump path (beads, c4, hey-cli)"
```

---

### Task 5: Tutorial doc + pointer from the manual routine

Write the tutorial the user asked for, and add a short pointer at the top of
the existing manual routine doc so anyone landing there first is redirected
to try the automated command for in-scope packages.

**Files:**
- Create: `docs/overlay-bump-tutorial.md`
- Modify: `docs/overlay-update-routine.md:1-6` (add pointer after the title)
- Modify: `CLAUDE.md` (add `bump-overlays` to the Quick Start command list
  and a one-line mention in the Overlays section, so the top-level project
  doc stays accurate)

**Interfaces:** none (documentation only).

- [ ] **Step 1: Write the tutorial**

Create `docs/overlay-bump-tutorial.md`:

```markdown
# Overlay Bump Tutorial

This repo pins ~16 overlays to specific upstream versions (see
`overlays/updates.json`). Keeping them current has three tiers of
automation — knowing which tier a package is in tells you which command to
reach for.

## The three tiers

1. **Detection only, everything** — `nix run .#check` (read-only) probes
   every pinned overlay and every cadence-gated flake input, and prints
   what's outdated. Nothing is ever changed by this command.
2. **Detection + application, mechanical subset** — `nix run .#bump-overlays`
   actually applies the bump for the overlays where doing so is a pure,
   verifiable value substitution: fetch a new hash, substitute a literal
   version/hash string, verify with a scoped `nix build`, commit. In scope
   today: **claude-code, codex-openai, uv, trailbase, igir, dcg,
   aws-cdk-cli** (prebuilt binaries), **go** (only on a patch-level bump —
   a minor bump needs a manual attribute rename, see below), and
   **beads, c4, hey-cli** (Go-source overlays; one extra automated step to
   resolve `vendorHash` from a build-error probe).
3. **Detection automated, application manual** — everything else:
   **mise** (cargo hash needs a real ~15 min local build),
   **yt-dlp/yt-dlp-ejs** (needs human review of `curl_cffi` version bounds
   in release notes), **ngrok** (no structured per-platform URL data in
   `updates.json` — the 6 URLs only exist as shell in the manual routine),
   **tmux** (different shape — `overrideAttrs` + `fetchFromGitHub` tag, not
   automated), and **go on a minor bump** (renaming `go_1_26` →
   `go_1_27` throughout the overlay is a structural edit, not a
   substitution). For all of these, follow
   `docs/overlay-update-routine.md` by hand.

## Day-to-day usage

```bash
nix run .#bump-overlays -- --dry-run   # preview: what would be bumped, no writes
nix run .#bump-overlays                # apply — one commit per successfully bumped package
git log --oneline -5                   # review what landed
nix run .#build-switch                 # actually switch the running system to the new binaries
```

`bump-overlays`'s own verification (`nix build --impure --expr
'...pkgs.PACKAGE'`) only proves the package builds in isolation — it does
**not** switch your running system. Run `nix run .#build-switch` afterward
to actually pick up the new binaries, same as after any other overlay
change.

`--only <name>[,<name>...]` restricts a run to specific packages, e.g. `nix
run .#bump-overlays -- --only uv,aws-cdk-cli`.

## When it reports a skip or a failure

- **Skipped** — the package's `update_type` isn't in the automated subset
  (tier 3 above), or it's `go` on a minor-version move. The summary line
  names the package and points here. Follow the matching recipe in
  `docs/overlay-update-routine.md`.
- **Failed** — something in the mechanical path itself broke: a hash fetch
  404'd, the version-substitution safety net found zero or more than one
  match (it never guesses), or the verification build failed. The script
  reverts that package's overlay file with `git checkout --` before moving
  to the next package, so a failure never leaves a half-edited file behind
  and never blocks other packages in the same run. Re-run with `--only
  <name>` after investigating, or fall back to the manual routine for that
  one package.

## Extending the automation later

A package can move from "manual" (tier 3) to "mechanical" (tier 2) once it
has, in `overlays/updates.json`, a `platforms{}.url_template` entry (single
or multi-platform) **and** its overlay file has exactly one `version =
"X";` assignment plus exactly one `hash =`/`sha256 =` field per platform
(these are the two invariants `bump-overlays`'s safety net checks). ngrok is
the clearest current candidate — it would need its 6 platform URLs added to
`updates.json` as real `platforms{}` entries (they currently only exist as
shell in the manual routine doc).

## Relationship to the daily launchd job

`bump-overlays` is a separate, manually-triggered command. It is **not**
wired into the daily `scheduled-check` launchd job — that job still only
proposes flake-input moves (via `prepare`) and *reports* (never applies)
outdated overlays, unchanged by this tutorial.
```

- [ ] **Step 2: Add the pointer to the manual routine doc**

In `docs/overlay-update-routine.md`, after line 5 (`used for the scheduled
Claude Code overlay-update routine (see [AGENTS.md](../AGENTS.md)), but
equally useful as a manual reference.`) and before the `---`, add:

```markdown

**Packages in the automated subset can be bumped with `nix run
.#bump-overlays` instead of following this by hand** — see
[docs/overlay-bump-tutorial.md](overlay-bump-tutorial.md) for which
packages qualify. This document remains the source of truth for every
pinned overlay, including the ones `bump-overlays` doesn't touch.
```

- [ ] **Step 3: Update `CLAUDE.md`**

In `CLAUDE.md`'s Quick Start block, after the `nix run .#update` line, add:

```
nix run .#bump-overlays  # Mechanically bump the automated-subset overlays (see docs/overlay-bump-tutorial.md)
```

In the "Overlays" section, after the existing bullet list of pinned
overlays, add one sentence: `claude-code, codex-openai, uv, trailbase, igir,
dcg, aws-cdk-cli, go (patch bumps), beads, c4, and hey-cli can be bumped
automatically with `nix run .#bump-overlays` — see
[docs/overlay-bump-tutorial.md](docs/overlay-bump-tutorial.md); everything
else still follows the manual routine.`

- [ ] **Step 4: Commit**

```bash
git add docs/overlay-bump-tutorial.md docs/overlay-update-routine.md CLAUDE.md
git commit -m "docs: add overlay bump tutorial and cross-links"
```

---

## Post-plan verification

After Task 5, run the full local gate once more to confirm nothing broke
across the whole sequence:

```bash
nix fmt
nix flake check
bash scripts/check-overlay-manifest.sh
```

All three must be clean/green. `nix flake check`'s `darwin-build` check in
particular re-builds the full system closure with every overlay change from
Tasks 1-4 applied — the strongest available confirmation that the live bumps
from Task 3 didn't just build in isolation but integrate cleanly.
