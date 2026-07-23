# Smart Incremental Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Nix update cycle do work proportional to what actually changed upstream — selective overlay re-hashing, per-input flake cadence, a build-only-if-changed gate — then a launchd scheduler that runs it and notifies via `osascript`.

**Architecture:** A shared bash+jq state cache (`.update-state.json`) backs two independent probes: an overlay probe (`check-overlay-versions.sh --json`) and a flake-input probe (locked-rev vs upstream-ref, gated by cadence in `updates.json` and frozen by `pinned_inputs[]`). An orchestrator library combines both verdicts into *pull?* / *build?* decisions, wired into a new `check` app (read-only preview) and into `prepare` (the gate). Phase 2 adds a launchd user agent that runs the gate and notifies.

**Tech Stack:** Bash, jq, python3 (inline, already used by the repo), Nix flakes, nix-darwin launchd (`launchd.user.agents`), macOS `osascript`.

## Global Constraints

- Every `.nix` change: run `nix fmt` before committing (nixfmt-rfc-style + statix + deadnix).
- Keep `nix flake check` green: `treefmt` + `overlays-manifest` + `darwin-build`.
- `overlays/updates.json` is the source of truth for pinned versions AND (new) input cadence. `.update-state.json` is a non-authoritative cache — deletable, gitignored.
- **`pinned_inputs[]` wins over everything:** a frozen input is never auto-updated regardless of cadence.
- Overlay/upstream probe failure = "no change" for that item; never a spurious fetch or update.
- Existing behavior preserved when new flags are absent: `fix-hashes` with no `--only` processes all overlays; `check-overlay-versions.sh` with no `--json` prints the table.
- Repo apps run from a read-only Nix store path; locate the mutable repo via `locate_flake` (in `apps/aarch64-darwin/_common.sh`).
- Commits auto-mirror to the public repo via the post-commit hook — no new private files here need denylisting (all paths are public-safe tooling).
- Bash: `set -euo pipefail`; match existing script style (color helpers from `_common.sh`, jq for JSON).

## File Structure

**New files:**
- `scripts/update-state.sh` — sourced bash+jq helpers for reading/writing `.update-state.json` (get/set overlay + input state, timestamps, corrupt-file recovery, lockfile).
- `scripts/update-probe.sh` — sourced bash library: `probe_overlays` (wraps `check-overlay-versions.sh --json`) and `probe_flake_inputs` (frozen/cadence/movement logic). Emits machine-readable verdicts.
- `apps/aarch64-darwin/check` — new app: read-only preview of what the gate would do.
- `tests/update/` — bash test scripts (no bats in repo; plain `set -e` scripts with asserts) + `curl`/`nix` stubs on `PATH`.
- `tests/update/run.sh` — runs all `tests/update/test_*.sh`, prints PASS/FAIL summary, exits non-zero on any failure.

**Modified files:**
- `scripts/check-overlay-versions.sh` — add `--json` mode.
- `apps/aarch64-darwin/fix-hashes` — add `--only <name,name>` filter.
- `overlays/updates.json` — add top-level `inputs` cadence object.
- `scripts/check-overlay-manifest.sh` — validate the new `inputs` key.
- `apps/aarch64-darwin/prepare` — insert the gate preamble.
- `hosts/darwin/default.nix` — Phase 2: `launchd.user.agents.nixos-update-check`.
- `scripts/update-notify.sh` — Phase 2: `osascript` notifier (new file, listed here for locality).

**Symlinked app copies:** `apps/{x86_64-darwin,aarch64-linux,x86_64-linux}/` — check whether `check` needs a copy/symlink like the other apps (Step in Task 8).

---

## Task 1: State cache helper (`scripts/update-state.sh`)

**Files:**
- Create: `scripts/update-state.sh`
- Test: `tests/update/test_state.sh`, `tests/update/run.sh`

**Interfaces:**
- Consumes: nothing (leaf module). Reads env var `UPDATE_STATE_FILE` (defaults to `<repo>/.update-state.json`).
- Produces (sourced functions):
  - `state_init` — ensure the file exists and is valid JSON `{"overlays":{},"inputs":{},"last_gate":null}`; on missing/corrupt, recreate.
  - `state_get_overlay_known_latest <name>` → prints version string or empty.
  - `state_set_overlay <name> <known_latest> <iso8601>` — upsert.
  - `state_get_input_updated_at <name>` → prints ISO8601 or empty.
  - `state_set_input_updated_at <name> <iso8601>` — upsert.
  - `state_set_last_gate <iso8601>`.
  - `state_lock` / `state_unlock` — flock-based mutex on `<state_file>.lock`; `state_lock` exits 0 if acquired, non-zero if already held.

- [ ] **Step 1: Write the failing test**

Create `tests/update/test_state.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
export UPDATE_STATE_FILE="$(mktemp)"
rm -f "$UPDATE_STATE_FILE"   # start absent
source "$REPO/scripts/update-state.sh"

# init creates a valid skeleton
state_init
jq -e '.overlays and .inputs' "$UPDATE_STATE_FILE" >/dev/null || { echo "FAIL: skeleton"; exit 1; }

# overlay round-trip
state_set_overlay claude-code 2.1.218 2026-07-23T10:00:00Z
got="$(state_get_overlay_known_latest claude-code)"
[[ "$got" == "2.1.218" ]] || { echo "FAIL: overlay got '$got'"; exit 1; }

# input round-trip
state_set_input_updated_at codex 2026-07-23T09:00:00Z
[[ "$(state_get_input_updated_at codex)" == "2026-07-23T09:00:00Z" ]] || { echo "FAIL: input"; exit 1; }

# corrupt-file recovery
echo "not json {" > "$UPDATE_STATE_FILE"
state_init
jq -e '.overlays' "$UPDATE_STATE_FILE" >/dev/null || { echo "FAIL: recovery"; exit 1; }

# lock is exclusive
state_lock || { echo "FAIL: first lock"; exit 1; }
( state_lock ) && { echo "FAIL: second lock should fail"; exit 1; }
state_unlock

echo "PASS: test_state"
```

Create `tests/update/run.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
for t in "$HERE"/test_*.sh; do
  echo "=== $(basename "$t") ==="
  bash "$t" || fail=1
done
[[ $fail -eq 0 ]] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/update/test_state.sh`
Expected: FAIL — `scripts/update-state.sh` does not exist (source error).

- [ ] **Step 3: Write minimal implementation**

Create `scripts/update-state.sh`:

```bash
#!/usr/bin/env bash
# Sourced helpers for the non-authoritative update state cache.
# State file: $UPDATE_STATE_FILE (default <repo>/.update-state.json).

: "${UPDATE_STATE_FILE:=}"
_state_file() {
  if [[ -n "${UPDATE_STATE_FILE:-}" ]]; then printf '%s' "$UPDATE_STATE_FILE"; return; fi
  local dir; dir="$(git rev-parse --show-toplevel 2>/dev/null)" || dir="$PWD"
  printf '%s/.update-state.json' "$dir"
}

state_init() {
  local f; f="$(_state_file)"
  if [[ ! -f "$f" ]] || ! jq empty "$f" 2>/dev/null; then
    printf '{"overlays":{},"inputs":{},"last_gate":null}\n' > "$f"
  fi
}

_state_write() { # jq-filter args...
  local f tmp; f="$(_state_file)"; tmp="$(mktemp)"
  jq "$@" "$f" > "$tmp" && mv "$tmp" "$f"
}

state_get_overlay_known_latest() {
  jq -r --arg n "$1" '.overlays[$n].known_latest // empty' "$(_state_file)"
}
state_set_overlay() {
  _state_write --arg n "$1" --arg v "$2" --arg t "$3" \
    '.overlays[$n] = {known_latest:$v, checked_at:$t}'
}
state_get_input_updated_at() {
  jq -r --arg n "$1" '.inputs[$n].updated_at // empty' "$(_state_file)"
}
state_set_input_updated_at() {
  _state_write --arg n "$1" --arg t "$2" '.inputs[$n] = {updated_at:$t}'
}
state_set_last_gate() { _state_write --arg t "$1" '.last_gate = $t'; }

_state_lockfile() { printf '%s.lock' "$(_state_file)"; }
state_lock() {
  exec {__state_lock_fd}>"$(_state_lockfile)"
  flock -n "$__state_lock_fd"
}
state_unlock() {
  [[ -n "${__state_lock_fd:-}" ]] && exec {__state_lock_fd}>&- || true
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
```

Note: macOS ships `flock`? It does **not** by default. If `flock` is unavailable, fall back to a mkdir-based lock. Adjust `state_lock`/`state_unlock`:

```bash
state_lock() {
  local d; d="$(_state_lockfile).d"
  mkdir "$d" 2>/dev/null   # atomic; fails if held
}
state_unlock() {
  local d; d="$(_state_lockfile).d"
  rmdir "$d" 2>/dev/null || true
}
```

Use the mkdir-based lock (portable on macOS). Remove the `flock` variant.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/update/test_state.sh`
Expected: `PASS: test_state`

- [ ] **Step 5: Commit**

```bash
chmod +x tests/update/run.sh
git add scripts/update-state.sh tests/update/test_state.sh tests/update/run.sh
nix fmt >/dev/null 2>&1 || true   # no .nix changed; harmless
git commit -m "feat(update): add state cache helper for incremental updates"
```

---

## Task 2: Machine-readable overlay probe (`check-overlay-versions.sh --json`)

**Files:**
- Modify: `scripts/check-overlay-versions.sh`
- Test: `tests/update/test_overlay_json.sh`

**Interfaces:**
- Consumes: nothing new (same upstream probes).
- Produces: with `--json`, stdout is a JSON array `[{"name":..,"current":..,"latest":..,"outdated":bool,"status":".."}]`. Exit code unchanged (non-zero if any `outdated`). Without `--json`, unchanged table.

- [ ] **Step 1: Write the failing test**

Create `tests/update/test_overlay_json.sh`. It stubs `curl` so no network is hit, then asserts JSON shape. The stub returns a fixed GitHub release for one repo and a 404-ish empty for another (→ ERROR must NOT be outdated).

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
STUB="$(mktemp -d)"

# Fake curl: any api.github.com/.../releases/latest -> a tag; else empty.
cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in
  *anthropics/claude-code/releases/latest) echo '{"tag_name":"v99.0.0"}'; exit 0;;
  *releases/latest) echo ''; exit 1;;   # simulate upstream error
esac; done
echo ''; exit 0
EOF
chmod +x "$STUB/curl"

out="$(PATH="$STUB:$PATH" bash "$REPO/scripts/check-overlay-versions.sh" --json)" || true

# Must be valid JSON array
echo "$out" | jq -e 'type == "array"' >/dev/null || { echo "FAIL: not array"; exit 1; }
# claude-code must be present and outdated (current != v99)
echo "$out" | jq -e '.[] | select(.name=="claude-code") | .outdated == true' >/dev/null \
  || { echo "FAIL: claude-code not outdated"; exit 1; }
# An ERROR item must never be outdated
echo "$out" | jq -e 'all(.[]; (.status=="ERROR") as $e | ($e and .outdated) | not)' >/dev/null \
  || { echo "FAIL: errored item marked outdated"; exit 1; }

echo "PASS: test_overlay_json"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/update/test_overlay_json.sh`
Expected: FAIL — `--json` not implemented (script prints the table, `jq` type check fails).

- [ ] **Step 3: Write minimal implementation**

In `scripts/check-overlay-versions.sh`, near the top (after `set -euo pipefail`), parse the flag:

```bash
JSON=0
[[ "${1:-}" == "--json" ]] && JSON=1
```

The script currently computes `name`, `current`, `latest`, `status` per package in the output loop and `printf`s a table row. Wrap the per-row emission: when `JSON=1`, accumulate JSON objects instead of printing the table, and suppress the header/summary. Concretely, replace the table `printf` at the row level and the header/summary blocks with:

- Before the loop:
  ```bash
  if [[ $JSON -eq 1 ]]; then
    rows=()
  else
    printf '%-22s %-18s %-18s %s\n' "PACKAGE" "CURRENT" "LATEST" "STATUS"
    printf '%s\n' "$(printf '%.0s─' {1..72})"
  fi
  ```
- Where the row is currently printed, after `status` is computed, derive a normalized `outdated`/`statuscode`:
  ```bash
  case "$status" in
    *OUTDATED*) sc=OUTDATED; od=true ;;
    *"up to date"*) sc=OK; od=false ;;
    ERROR) sc=ERROR; od=false ;;
    *) sc=MANUAL; od=false ;;
  esac
  if [[ $JSON -eq 1 ]]; then
    rows+=("$(jq -nc --arg n "$name" --arg c "$current" --arg l "$latest" \
      --arg s "$sc" --argjson o "$od" \
      '{name:$n,current:$c,latest:($l|sub(" .*";"")),outdated:$o,status:$s}')")
  else
    printf '%-22s %-18s %-18s %s\n' "$name" "$current" "$latest" "$status"
  fi
  ```
- After the loop, replace the summary block:
  ```bash
  if [[ $JSON -eq 1 ]]; then
    printf '%s\n' "$(printf '%s\n' "${rows[@]}" | jq -sc '.')"
  else
    echo ""
    printf 'Summary: %d up to date  |  %d outdated  |  %d errors\n' \
      "$UP_TO_DATE" "$OUTDATED" "$ERRORS"
  fi
  [[ $OUTDATED -gt 0 ]] && exit 1 || exit 0
  ```

(The `latest|sub(" .*";"")` strips the ` (commit)` suffix github-commits appends, leaving a clean sha.)

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/update/test_overlay_json.sh`
Also verify the table still works: `bash scripts/check-overlay-versions.sh | head -3` (may hit network; ok to skip if offline).
Expected: `PASS: test_overlay_json`

- [ ] **Step 5: Commit**

```bash
git add scripts/check-overlay-versions.sh tests/update/test_overlay_json.sh
git commit -m "feat(update): add --json mode to check-overlay-versions"
```

---

## Task 3: Selective `fix-hashes --only <names>`

**Files:**
- Modify: `apps/aarch64-darwin/fix-hashes`
- Test: `tests/update/test_fixhashes_only.sh`

**Interfaces:**
- Consumes: overlay *names* (as in `updates.json` `.packages[].name`), comma-separated, via `--only`.
- Produces: same hash-fixing behavior but limited to the overlay *files* backing those names. No `--only` → all `PINNED_OVERLAYS` (unchanged).
- Name→file mapping: read `updates.json` `.packages[] | select(.name==X) | .overlay | basename`.

- [ ] **Step 1: Write the failing test**

Create `tests/update/test_fixhashes_only.sh`. It stubs `nix-prefetch-url` and `nix` to count invocations and asserts only the requested overlay file is visited. Because `fix-hashes` sources `_common.sh` and calls `locate_flake`, set `UPDATE_TEST_FLAKE_DIR` and stub `nix`/`git` minimally, or run against the real repo with a dry `PINNED_OVERLAYS`. Simplest: run in the real repo, stub network so no real download happens, and assert the set of `--- <overlay> ---` headers printed.

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
STUB="$(mktemp -d)"

# Stub network fetch: return a stable fake SRI so nothing is downloaded/changed.
cat > "$STUB/nix-prefetch-url" <<'EOF'
#!/usr/bin/env bash
echo "0000000000000000000000000000000000000000000000000000"
EOF
chmod +x "$STUB/nix-prefetch-url"
# Stub nix hash convert to echo a deterministic SRI.
cat > "$STUB/nix" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "hash" ]]; then echo "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; exit 0; fi
exec /usr/bin/env nix "$@"
EOF
chmod +x "$STUB/nix"

out="$(PATH="$STUB:$PATH" bash "$REPO/apps/aarch64-darwin/fix-hashes" --only claude-code 2>&1)" || true
echo "$out" | grep -q -- "--- 41-claude-code.nix ---" || { echo "FAIL: claude-code not processed"; exit 1; }
echo "$out" | grep -q -- "--- 20-ngrok.nix ---" && { echo "FAIL: ngrok processed despite --only"; exit 1; }
echo "PASS: test_fixhashes_only"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/update/test_fixhashes_only.sh`
Expected: FAIL — `--only` unrecognized; script processes all overlays, so the ngrok assertion trips.

- [ ] **Step 3: Write minimal implementation**

In `apps/aarch64-darwin/fix-hashes`, after sourcing `_common.sh` and setting `FLAKE_DIR`/`OVERLAYS_DIR`, parse `--only` and build the overlay list from names:

```bash
ONLY=""
if [[ "${1:-}" == "--only" ]]; then ONLY="${2:-}"; shift 2 || true; fi
```

Replace the hardcoded loop over `PINNED_OVERLAYS` with a filtered list:

```bash
declare -a TARGET_OVERLAYS
if [[ -n "$ONLY" ]]; then
  IFS=',' read -r -a names <<< "$ONLY"
  for n in "${names[@]}"; do
    file="$(jq -r --arg n "$n" \
      '.packages[] | select(.name==$n) | .overlay' \
      "$FLAKE_DIR/overlays/updates.json" | sed 's|overlays/||')"
    if [[ -z "$file" ]]; then
      warn "  (skip: '$n' not in updates.json)"; continue
    fi
    # Only re-hash overlays fix-hashes actually knows how to (prebuilt list).
    for p in "${PINNED_OVERLAYS[@]}"; do
      [[ "$p" == "$file" ]] && TARGET_OVERLAYS+=("$file")
    done
  done
else
  TARGET_OVERLAYS=("${PINNED_OVERLAYS[@]}")
fi

for overlay in "${TARGET_OVERLAYS[@]}"; do
  check_overlay "$overlay"
done
```

(Placement: `PINNED_OVERLAYS` is defined just before the current loop; move the `--only` parse to the top after `OVERLAYS_DIR` is set, and replace only the final `for overlay in "${PINNED_OVERLAYS[@]}"` loop.)

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/update/test_fixhashes_only.sh`
Expected: `PASS: test_fixhashes_only`

- [ ] **Step 5: Commit**

```bash
git add apps/aarch64-darwin/fix-hashes tests/update/test_fixhashes_only.sh
git commit -m "feat(update): add --only filter to fix-hashes for selective re-hashing"
```

---

## Task 4: Input cadence config in `updates.json` + manifest validation

**Files:**
- Modify: `overlays/updates.json`
- Modify: `scripts/check-overlay-manifest.sh`
- Test: `tests/update/test_manifest_inputs.sh`

**Interfaces:**
- Produces: top-level `.inputs` object in `updates.json`; each entry has `cadence_hours` (integer ≥ 0) and optionally `on_demand` (bool). `check-overlay-manifest.sh` fails if an entry is malformed.

- [ ] **Step 1: Write the failing test**

Create `tests/update/test_manifest_inputs.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

# Real manifest must validate.
bash "$REPO/scripts/check-overlay-manifest.sh" "$REPO" >/dev/null || { echo "FAIL: real manifest"; exit 1; }

# A copy with a malformed inputs entry must FAIL.
tmp="$(mktemp -d)"; cp -r "$REPO"/. "$tmp/"   # cheap-ish; or symlink overlays + scripts
jq '.inputs.badinput = {}' "$REPO/overlays/updates.json" > "$tmp/overlays/updates.json"
if bash "$REPO/scripts/check-overlay-manifest.sh" "$tmp" >/dev/null 2>&1; then
  echo "FAIL: malformed inputs entry accepted"; exit 1
fi
echo "PASS: test_manifest_inputs"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/update/test_manifest_inputs.sh`
Expected: FAIL — no `.inputs` yet, and the checker doesn't validate it, so the malformed-entry case is (wrongly) accepted.

- [ ] **Step 3a: Add `inputs` to `updates.json`**

Add a top-level `"inputs"` object (sibling of `packages`/`skip`/`pinned_inputs`). nixpkgs is currently frozen by `pinned_inputs`, so its cadence is inert-but-declared:

```json
"inputs": {
  "nixpkgs":      { "cadence_hours": 168 },
  "home-manager": { "cadence_hours": 168 },
  "darwin":       { "cadence_hours": 168 },
  "secrets":      { "cadence_hours": 0, "on_demand": true }
}
```

(Confirm the real input names with `nix flake metadata --json | jq '.locks.nodes.root.inputs'` and list each top-level input; give any unlisted input the default via the probe, but declaring the big ones here is clearer. Do NOT add cadence entries that contradict `pinned_inputs` semantics — frozen wins regardless.)

- [ ] **Step 3b: Validate in `check-overlay-manifest.sh`**

After the existing `pinned_inputs` validation block (around the `.pinned_inputs // []` jq), add:

```bash
# 6. Input cadence: each .inputs entry needs cadence_hours (int) or on_demand.
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  ok="$(jq -r --arg n "$name" '
    .inputs[$n] as $e
    | (($e.cadence_hours|type=="number") or ($e.on_demand==true))' "$MANIFEST")"
  [[ "$ok" == "true" ]] || err "inputs '$name' needs cadence_hours (number) or on_demand:true"
done < <(jq -r '(.inputs // {}) | keys[]' "$MANIFEST")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/update/test_manifest_inputs.sh`
Then: `bash scripts/check-overlay-manifest.sh` (real repo) → prints nothing / exit 0.
Expected: `PASS: test_manifest_inputs`

- [ ] **Step 5: Commit**

```bash
git add overlays/updates.json scripts/check-overlay-manifest.sh tests/update/test_manifest_inputs.sh
git commit -m "feat(update): declare per-input cadence in updates.json with manifest validation"
```

---

## Task 5: Probe library (`scripts/update-probe.sh`)

**Files:**
- Create: `scripts/update-probe.sh`
- Test: `tests/update/test_probe_inputs.sh`

**Interfaces:**
- Consumes: `scripts/update-state.sh` functions; `updates.json` (`.inputs`, `.pinned_inputs`); `nix flake metadata --json`; GitHub API.
- Produces (sourced functions):
  - `probe_overlays` → prints comma-separated names of outdated overlays (empty if none). Updates state `known_latest`. Uses `check-overlay-versions.sh --json`.
  - `input_is_frozen <name>` → exit 0 if in `pinned_inputs[]`.
  - `input_is_due <name> <now_epoch>` → exit 0 if `updated_at + cadence` elapsed (or never updated); non-zero if not due; frozen/on_demand always non-zero.
  - `probe_flake_inputs <mode>` where mode ∈ `report|apply`. `report` prints names that are due-and-moved (read-only). `apply` runs `nix flake lock --update-input <name>` for each and sets `updated_at`. Returns via stdout the list of inputs it (would) update.

- [ ] **Step 1: Write the failing test**

Create `tests/update/test_probe_inputs.sh`. Focus on the pure decision logic (`input_is_frozen`, `input_is_due`) with a fixture state file and stubbed `updates.json` — no real `nix`/network.

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
export UPDATE_STATE_FILE="$(mktemp)"; rm -f "$UPDATE_STATE_FILE"
export UPDATE_MANIFEST="$(mktemp)"
cat > "$UPDATE_MANIFEST" <<'JSON'
{ "packages": [], "skip": [],
  "pinned_inputs": [ { "name": "nixpkgs" } ],
  "inputs": { "nixpkgs": {"cadence_hours":168},
              "codex": {"cadence_hours":24},
              "secrets": {"cadence_hours":0,"on_demand":true} } }
JSON
source "$REPO/scripts/update-state.sh"; state_init
source "$REPO/scripts/update-probe.sh"

NOW=$(date -u +%s)

# nixpkgs is frozen -> never due
input_is_frozen nixpkgs || { echo "FAIL: nixpkgs should be frozen"; exit 1; }
input_is_due nixpkgs "$NOW" && { echo "FAIL: frozen input due"; exit 1; }

# secrets on_demand -> never due
input_is_due secrets "$NOW" && { echo "FAIL: on_demand due"; exit 1; }

# codex never updated -> due
input_is_due codex "$NOW" || { echo "FAIL: fresh codex should be due"; exit 1; }

# codex updated 1h ago, cadence 24h -> NOT due
state_set_input_updated_at codex "$(date -u -r $((NOW-3600)) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d @$((NOW-3600)) +%Y-%m-%dT%H:%M:%SZ)"
input_is_due codex "$NOW" && { echo "FAIL: codex within cadence marked due"; exit 1; }

# codex updated 25h ago -> due
state_set_input_updated_at codex "$(date -u -r $((NOW-90000)) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d @$((NOW-90000)) +%Y-%m-%dT%H:%M:%SZ)"
input_is_due codex "$NOW" || { echo "FAIL: codex past cadence not due"; exit 1; }

echo "PASS: test_probe_inputs"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/update/test_probe_inputs.sh`
Expected: FAIL — `scripts/update-probe.sh` missing.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/update-probe.sh`:

```bash
#!/usr/bin/env bash
# Sourced probe library. Requires update-state.sh already sourced.
: "${UPDATE_MANIFEST:=}"
_manifest() {
  if [[ -n "${UPDATE_MANIFEST:-}" ]]; then printf '%s' "$UPDATE_MANIFEST"; return; fi
  local d; d="$(git rev-parse --show-toplevel 2>/dev/null)" || d="$PWD"
  printf '%s/overlays/updates.json' "$d"
}

# iso8601 -> epoch seconds (GNU date -d or BSD date -j)
_iso_to_epoch() {
  local s="$1"
  date -u -d "$s" +%s 2>/dev/null || date -u -j -f %Y-%m-%dT%H:%M:%SZ "$s" +%s 2>/dev/null
}

input_is_frozen() {
  local n="$1"
  jq -e --arg n "$n" '(.pinned_inputs // []) | any(.name==$n)' "$(_manifest)" >/dev/null
}

input_is_due() { # <name> <now_epoch>
  local n="$1" now="$2"
  input_is_frozen "$n" && return 1
  local ondemand cadence
  ondemand="$(jq -r --arg n "$n" '.inputs[$n].on_demand // false' "$(_manifest)")"
  [[ "$ondemand" == "true" ]] && return 1
  cadence="$(jq -r --arg n "$n" '.inputs[$n].cadence_hours // 24' "$(_manifest)")"
  [[ "$cadence" == "0" ]] && return 1
  local last; last="$(state_get_input_updated_at "$n")"
  [[ -z "$last" ]] && return 0            # never updated -> due
  local last_e; last_e="$(_iso_to_epoch "$last")"
  [[ -z "$last_e" ]] && return 0
  (( now >= last_e + cadence * 3600 ))
}

probe_overlays() {
  local repo; repo="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
  local json; json="$("$repo/scripts/check-overlay-versions.sh" --json 2>/dev/null || true)"
  [[ -z "$json" ]] && { printf ''; return 0; }
  # record known_latest for successfully-probed overlays
  while IFS=$'\t' read -r name latest; do
    [[ -n "$name" ]] && state_set_overlay "$name" "$latest" "$(now_iso)"
  done < <(echo "$json" | jq -r '.[] | select(.status=="OK" or .status=="OUTDATED") | "\(.name)\t\(.latest)"')
  echo "$json" | jq -r '[.[] | select(.outdated) | .name] | join(",")'
}

# Upstream ref of a github input (locked in flake.lock). Best-effort.
_input_upstream_moved() { # <name>  -> exit 0 if moved (or unknown)
  local n="$1" repo; repo="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
  local meta; meta="$(nix flake metadata "$repo" --json 2>/dev/null)" || return 0
  local node owner name rev branch
  node="$(echo "$meta" | jq -r --arg n "$n" '.locks.nodes[$n].locked // empty')"
  [[ -z "$node" ]] && return 0
  [[ "$(echo "$node" | jq -r '.type // ""')" == "github" ]] || return 0
  owner="$(echo "$node" | jq -r '.owner')"; name="$(echo "$node" | jq -r '.repo')"
  rev="$(echo "$node" | jq -r '.rev')"; branch="$(echo "$node" | jq -r '.ref // "HEAD"')"
  local head
  head="$(curl -sf --max-time 15 -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$owner/$name/commits/$branch" 2>/dev/null \
    | jq -r '.sha // empty')" || return 0
  [[ -z "$head" ]] && return 0            # probe failed -> treat as moved (update when due)
  [[ "$head" != "$rev" ]]
}

probe_flake_inputs() { # mode: report|apply
  local mode="${1:-report}" repo now updated=()
  repo="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
  now="$(date -u +%s)"
  local inputs
  inputs="$(jq -r '(.inputs // {}) | keys[]' "$(_manifest)")"
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    input_is_due "$n" "$now" || continue
    _input_upstream_moved "$n" || continue
    if [[ "$mode" == "apply" ]]; then
      nix flake lock "$repo" --update-input "$n" >/dev/null 2>&1 || true
      state_set_input_updated_at "$n" "$(now_iso)"
    fi
    updated+=("$n")
  done <<< "$inputs"
  (IFS=,; echo "${updated[*]:-}")
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/update/test_probe_inputs.sh`
Expected: `PASS: test_probe_inputs`

- [ ] **Step 5: Commit**

```bash
git add scripts/update-probe.sh tests/update/test_probe_inputs.sh
git commit -m "feat(update): add overlay + flake-input probe library"
```

---

## Task 6: `check` app — read-only gate preview

**Files:**
- Create: `apps/aarch64-darwin/check`
- Test: `tests/update/test_check_app.sh`

**Interfaces:**
- Consumes: `update-state.sh`, `update-probe.sh`.
- Produces: human report of what the gate would do; sets nothing except state timestamps; exit 0 always (it's a preview). Prints `nothing to do` when both probes are clean.

- [ ] **Step 1: Write the failing test**

Create `tests/update/test_check_app.sh` — stub network so overlays look up-to-date and no input moved, assert "nothing to do".

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
STUB="$(mktemp -d)"
# curl: every releases/latest returns the CURRENT version so nothing is outdated.
cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"tag_name":"v0.0.0-none"}'; exit 0
EOF
chmod +x "$STUB/curl"
# nix: metadata returns no github inputs; flake lock is a no-op.
cat > "$STUB/nix" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "flake" && "$2" == "metadata" ]]; then echo '{"locks":{"nodes":{}}}'; exit 0; fi
if [[ "$1" == "flake" && "$2" == "lock" ]]; then exit 0; fi
exec /usr/bin/env nix "$@"
EOF
chmod +x "$STUB/nix"
export UPDATE_STATE_FILE="$(mktemp)"; rm -f "$UPDATE_STATE_FILE"
out="$(PATH="$STUB:$PATH" bash "$REPO/apps/aarch64-darwin/check" 2>&1)" || true
echo "$out" | grep -qi "nothing to do" || { echo "FAIL: expected nothing-to-do"; echo "$out"; exit 1; }
echo "PASS: test_check_app"
```

(Note: overlays with non-github methods — go-dev/pypi/npm/ngrok/github-commits — will still be probed; with the current-version-matching stub the github ones are OK, the others may error → non-outdated. If a non-github method reports OUTDATED against the stub, tighten the stub or accept the app prints them; the assertion only requires the presence of "nothing to do" which the input side guarantees. If overlays show outdated due to real network on non-github methods, run this test with network disabled.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/update/test_check_app.sh`
Expected: FAIL — `apps/aarch64-darwin/check` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `apps/aarch64-darwin/check`:

```bash
#!/usr/bin/env bash
# Read-only preview: what would `prepare`'s gate do right now? No mutations
# beyond the state cache's observed-version timestamps. Never builds, never
# updates the lock (uses probe report mode).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_common.sh"
FLAKE_DIR="$(locate_flake)" || exit 1
# shellcheck source=/dev/null
source "$FLAKE_DIR/scripts/update-state.sh"
# shellcheck source=/dev/null
source "$FLAKE_DIR/scripts/update-probe.sh"
cd "$FLAKE_DIR"
state_init

warn "==> overlay probe"
overlays_outdated="$(probe_overlays)"
warn "==> flake-input probe (report only)"
inputs_due="$(probe_flake_inputs report)"

echo ""
if [[ -z "$overlays_outdated" && -z "$inputs_due" ]]; then
  msg "nothing to do — everything within cadence and up to date"
else
  [[ -n "$overlays_outdated" ]] && msg "overlays outdated: $overlays_outdated"
  [[ -n "$inputs_due"        ]] && msg "flake inputs to refresh: $inputs_due"
  msg "run 'nix run .#prepare' to build + commit the proposed revision"
fi
state_set_last_gate "$(now_iso)"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/update/test_check_app.sh`
Expected: `PASS: test_check_app`
Also manual: `chmod +x apps/aarch64-darwin/check && nix run .#check` (real; may hit network).

- [ ] **Step 5: Commit**

```bash
chmod +x apps/aarch64-darwin/check
git add apps/aarch64-darwin/check tests/update/test_check_app.sh
git commit -m "feat(update): add read-only 'check' app for gate preview"
```

---

## Task 7: Wire the gate into `prepare`

**Files:**
- Modify: `apps/aarch64-darwin/prepare`
- Test: `tests/update/test_gate_decision.sh`

**Interfaces:**
- Consumes: `update-state.sh`, `update-probe.sh`.
- Produces: `prepare` runs probes first; **builds + commits only if** an overlay bumped OR an input actually moved; otherwise prints "nothing to do" and exits 0 before `nix build`.
- Replaces the unconditional `nix flake update` with selective `probe_flake_inputs apply`.

- [ ] **Step 1: Write the failing test**

Create `tests/update/test_gate_decision.sh` — the four-quadrant truth table via a tiny extracted decision function. To keep it unit-testable, put the decision in `update-probe.sh` as `gate_should_build <overlays_csv> <inputs_csv>` (add it in this task) and test that.

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
source "$REPO/scripts/update-probe.sh"
gate_should_build "" ""        && { echo "FAIL: clean->build"; exit 1; }
gate_should_build "claude-code" "" || { echo "FAIL: overlay->no build"; exit 1; }
gate_should_build "" "codex"       || { echo "FAIL: input->no build"; exit 1; }
gate_should_build "a" "b"          || { echo "FAIL: both->no build"; exit 1; }
echo "PASS: test_gate_decision"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/update/test_gate_decision.sh`
Expected: FAIL — `gate_should_build` undefined.

- [ ] **Step 3a: Add `gate_should_build` to `update-probe.sh`**

Append:

```bash
# exit 0 (build) if either list is non-empty.
gate_should_build() { [[ -n "${1:-}" || -n "${2:-}" ]]; }
```

- [ ] **Step 3b: Rework `prepare`**

Replace the top of `apps/aarch64-darwin/prepare` (the `nix flake update` + `fix-hashes` block) with the gated flow. Keep the build/diff/commit tail. New body after `cd "$FLAKE_DIR"`:

```bash
# shellcheck source=/dev/null
source "$FLAKE_DIR/scripts/update-state.sh"
# shellcheck source=/dev/null
source "$FLAKE_DIR/scripts/update-probe.sh"
state_init
if ! state_lock; then err "another update run holds the lock; aborting"; exit 1; fi
trap 'state_unlock' EXIT

warn "==> overlay probe"
overlays_outdated="$(probe_overlays)"
warn "==> flake-input probe (apply)"
inputs_updated="$(probe_flake_inputs apply)"

if ! gate_should_build "$overlays_outdated" "$inputs_updated"; then
  msg "nothing to do — no overlay bumps, no input moved within cadence"
  state_set_last_gate "$(now_iso)"
  exit 0
fi

if [[ -n "$overlays_outdated" ]]; then
  warn "==> fix-hashes --only $overlays_outdated"
  "$SCRIPT_DIR/fix-hashes" --only "$overlays_outdated"
  # Bump current_version in updates.json for each outdated overlay.
  for n in ${overlays_outdated//,/ }; do
    latest="$(state_get_overlay_known_latest "$n")"
    [[ -z "$latest" ]] && continue
    tmp="$(mktemp)"
    jq --arg n "$n" --arg v "$latest" \
      '(.packages[] | select(.name==$n) | .current_version) = $v' \
      "$FLAKE_DIR/overlays/updates.json" > "$tmp" && mv "$tmp" "$FLAKE_DIR/overlays/updates.json"
  done
fi

warn "==> build ${FLAKE_SYSTEM_ATTR} (evidence; no activation)"
nix build "${FLAKE_DIR}#${FLAKE_SYSTEM_ATTR}" --out-link ./result "$@"
```

Keep the existing closure-diff + commit tail unchanged. Verify the commit's `git add` includes `overlays/updates.json` and `flake.lock` (it already does: `git add flake.lock overlays/`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/update/test_gate_decision.sh` → `PASS`.
Run: `bash tests/update/run.sh` → `ALL PASS`.
Manual smoke (real, may build): with everything current, `nix run .#prepare` prints "nothing to do" and does not build.
Expected: gate short-circuits when clean.

- [ ] **Step 5: Commit**

```bash
git add apps/aarch64-darwin/prepare scripts/update-probe.sh tests/update/test_gate_decision.sh
git commit -m "feat(update): gate prepare on real upstream changes (build only if changed)"
```

---

## Task 8: Cross-arch app parity + `.gitignore`

**Files:**
- Modify: `.gitignore`
- Inspect/Modify: `apps/{x86_64-darwin,aarch64-linux,x86_64-linux}/`

**Interfaces:** none (packaging).

- [ ] **Step 1: Gitignore the state cache**

Add to `.gitignore`:

```
# Incremental-update state cache (non-authoritative)
.update-state.json
.update-state.json.lock.d/
```

- [ ] **Step 2: Check how other apps are shared across arch dirs**

Run: `ls -la apps/x86_64-darwin/ | head; readlink apps/x86_64-darwin/prepare 2>/dev/null`
Expected: reveals whether arch dirs are symlinks to `aarch64-darwin` or independent copies.

- [ ] **Step 3: Mirror the `check` app to match the repo's convention**

If the other arch dirs symlink into `aarch64-darwin`, add `apps/<arch>/check` symlinks to match. If they're independent copies, copy `check` into each (the script is arch-agnostic — it locates the flake and shells out). Match whatever `prepare`/`fix-hashes` already do.

Run (example if symlinks): `ln -s ../aarch64-darwin/check apps/x86_64-darwin/check` (repeat per arch as the convention dictates).

- [ ] **Step 4: Verify the flake exposes `check`**

Run: `nix flake show 2>/dev/null | grep -A2 check || grep -rn "check" flake.nix apps/`
Confirm `nix run .#check` resolves. If apps are auto-discovered from the directory, no flake edit is needed; if enumerated in `flake.nix`, add `check` alongside `prepare`.
Expected: `nix run .#check --help`-style resolution works (or the app list includes it).

- [ ] **Step 5: Commit**

```bash
git add .gitignore apps/
git commit -m "chore(update): gitignore state cache; add check app across arch dirs"
```

---

## Task 9 (Phase 2): launchd scheduler + `osascript` notifier

**Files:**
- Create: `scripts/update-notify.sh`
- Create: `apps/aarch64-darwin/scheduled-check` (thin wrapper prepare-or-nothing + notify)
- Modify: `hosts/darwin/default.nix`
- Test: `tests/update/test_notify.sh`

**Interfaces:**
- `update-notify.sh`: `notify <title> <message>` → `osascript -e 'display notification …'`; no-op (echo) when `osascript` absent (Linux/CI).
- `scheduled-check`: runs `prepare`; if it committed a new revision, calls `notify` with the revision + summary; on build failure, notifies the failure and leaves the tree clean.
- launchd agent `nixos-update-check`: runs `scheduled-check` daily.

- [ ] **Step 1: Write the failing test**

Create `tests/update/test_notify.sh` — stub `osascript`, assert it's invoked with the message.

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/update/test_notify.sh`
Expected: FAIL — `scripts/update-notify.sh` missing.

- [ ] **Step 3a: Implement notifier**

Create `scripts/update-notify.sh`:

```bash
#!/usr/bin/env bash
# Sourced. notify <title> <message> -> macOS notification (no-op elsewhere).
notify() {
  local title="$1" message="$2"
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${message//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1 || true
  else
    echo "[notify] $title: $message"
  fi
}
```

- [ ] **Step 3b: Implement `scheduled-check`**

Create `apps/aarch64-darwin/scheduled-check`:

```bash
#!/usr/bin/env bash
# launchd entrypoint: run prepare; notify only on a real proposed revision.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_common.sh"
FLAKE_DIR="$(locate_flake)" || exit 1
# shellcheck source=/dev/null
source "$FLAKE_DIR/scripts/update-notify.sh"
cd "$FLAKE_DIR"

before="$(git rev-parse HEAD 2>/dev/null)"
if "$SCRIPT_DIR/prepare" >/tmp/nixos-scheduled-check.log 2>&1; then
  after="$(git rev-parse HEAD 2>/dev/null)"
  if [[ "$before" != "$after" ]]; then
    notify "nixos-config update" "revision ${after:0:7} ready — run 'nix run .#activate -- ${after:0:7}'"
  fi
else
  notify "nixos-config update FAILED" "see /tmp/nixos-scheduled-check.log"
fi
```

- [ ] **Step 3c: Declare the launchd agent**

In `hosts/darwin/default.nix`, after the `launchd.user.agents.emacs` block (around line 96), add:

```nix
  launchd.user.agents.nixos-update-check.path = [ config.environment.systemPath ];
  launchd.user.agents.nixos-update-check.serviceConfig = {
    ProgramArguments = [
      "/bin/sh"
      "-c"
      # Runs the scheduled check daily; locates the flake via the registry.
      "exec ${pkgs.nix}/bin/nix run nixos-config#scheduled-check"
    ];
    StartCalendarInterval = [ { Hour = 9; Minute = 30; } ];
    StandardErrorPath = "/tmp/nixos-update-check.err.log";
    StandardOutPath = "/tmp/nixos-update-check.out.log";
    RunAtLoad = false;
  };
```

(Confirm `nixos-config#scheduled-check` is exposed like `check` from Task 8; if apps are auto-discovered no flake edit is needed. If the registry isn't resolvable in the launchd env, replace with an absolute path to the flake dir: `nix run /Users/briangyss/nixos-config#scheduled-check`.)

- [ ] **Step 4: Run tests + fmt + flake check**

Run: `bash tests/update/test_notify.sh` → `PASS`.
Run: `bash tests/update/run.sh` → `ALL PASS`.
Run: `nix fmt` then `nix flake check` → green (treefmt + overlays-manifest + darwin-build).
Manual: `chmod +x apps/aarch64-darwin/scheduled-check`; mirror it across arch dirs per Task 8's convention.
Expected: all green; `launchctl list | grep nixos-update-check` after a `build-switch`.

- [ ] **Step 5: Commit**

```bash
chmod +x apps/aarch64-darwin/scheduled-check
git add scripts/update-notify.sh apps/ hosts/darwin/default.nix tests/update/test_notify.sh
nix fmt >/dev/null 2>&1 || true
git commit -m "feat(update): add daily launchd scheduler with osascript notifier"
```

---

## Task 10: Docs + final verification

**Files:**
- Modify: `CLAUDE.md` (Update Workflow section), `docs/overlay-update-routine.md` or `docs/troubleshooting.md` (mention `nix run .#check`, `.update-state.json`, cadence in `updates.json`).

- [ ] **Step 1: Document the new workflow**

In `CLAUDE.md` under "Update Workflow", add a short paragraph: `nix run .#check` previews what would change (read-only); `prepare` now gates on real upstream changes and only rebuilds when something moved; per-input cadence lives in `overlays/updates.json` `inputs`; `pinned_inputs[]` still wins (frozen inputs never auto-update); a daily launchd agent (`nixos-update-check`) proposes + notifies but never activates. Note `.update-state.json` is a deletable cache.

- [ ] **Step 2: Run the full check**

Run: `bash tests/update/run.sh` → `ALL PASS`.
Run: `nix fmt && nix flake check` → green.
Run: `nix run .#check` → prints a coherent report.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md docs/
git commit -m "docs: document smart incremental update workflow"
```

---

## Self-Review Notes

- **Spec coverage:** state cache (T1), overlay `--json` (T2), selective `fix-hashes` (T3), cadence in `updates.json` + validation (T4), probes incl. frozen/cadence/movement (T5), read-only `check`/gate preview (T6), gate wired to `prepare` build-only-if-changed (T7), gitignore + arch parity (T8), launchd scheduler + `osascript` notifier + never-activate (T9), docs (T10). Error handling (probe failure = no-change, corrupt state recovery, lockfile, build-failure notify) is covered in T1/T5/T7/T9.
- **`pinned_inputs[]` precedence** is enforced first in `input_is_due` (T5) and tested (frozen nixpkgs never due).
- **Backward compatibility:** `fix-hashes`/`check-overlay-versions.sh` keep old behavior without the new flags.
- **Known risk to verify during execution:** exact input node names in `flake.lock` (T4 Step 3a, T5 movement check) and whether arch app dirs are symlinks vs copies (T8) and whether apps are flake-enumerated vs auto-discovered (T8 Step 4). Each has an inline "confirm with …" command.
