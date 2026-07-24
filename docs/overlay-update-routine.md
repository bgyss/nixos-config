# Overlay Update Routine

Goal: check all version-pinned overlays for new upstream releases, apply updates, verify the
build, and commit. Originally written for the scheduled Claude Code overlay-update routine
(see [AGENTS.md](../AGENTS.md)), but equally useful as a manual reference.

**Packages in the automated subset can be bumped with `nix run
.#bump-overlays` instead of following this by hand** — see
[docs/overlay-bump-tutorial.md](overlay-bump-tutorial.md) for which
packages qualify. This document remains the source of truth for every
pinned overlay, including the ones `bump-overlays` doesn't touch.

---

## Step 1 — Run the version check

```bash
bash scripts/check-overlay-versions.sh
```

This queries GitHub Releases, go.dev, PyPI, GitHub commit history (for untagged repos like
c4 and hey-cli), and the ngrok stable CDN binary itself, and prints a table of `current` vs
`latest` versions. If all packages are up to date the script exits 0 and you are done —
nothing to commit.

If any packages are `OUTDATED`, continue to Step 2.

The manifest at `overlays/updates.json` is the authoritative list of which overlays are
version-pinned and how to check/update each one. Read it before making any changes.

---

## Step 2 — Apply updates by overlay type

### Prebuilt binary overlays (`update_type: "prebuilt-binary"` or `"prebuilt-binary-multiplatform"`)

These overlays fetch pre-built binaries directly from upstream. The update procedure is:

1. Update the `version` string in the overlay file.
2. For each platform listed in `updates.json`, expand the `url_template` by replacing
   `{version}` with the new version string.
3. Fetch the new hash for each URL:
   ```bash
   # For archives (tar.gz, zip):
   nix-prefetch-url --unpack <URL> 2>/dev/null \
     | xargs nix hash convert --hash-algo sha256 --to sri

   # For plain binaries (no archive, like claude-code):
   nix-prefetch-url <URL> 2>/dev/null \
     | xargs nix hash convert --hash-algo sha256 --to sri
   ```
4. Replace `hash =`, `sha256 =`, or the per-platform `hash =` fields in the overlay with the
   new SRI hashes.

**claude-code** (`overlays/41-claude-code.nix`): single aarch64-darwin binary (not an archive
— use `nix-prefetch-url` without `--unpack`).

**codex-openai** (`overlays/40-codex-openai.nix`): single aarch64-darwin archive. The GitHub
release tag is `rust-vX.Y.Z`; the version field in the overlay is `X.Y.Z`.

**uv** (`overlays/25-uv.nix`): single aarch64-darwin archive. GitHub tag is `X.Y.Z` (no `v`
prefix).

**trailbase** (`overlays/50-trailbase.nix`): three-platform overlay (aarch64-darwin,
x86_64-darwin, x86_64-linux). Update all three hashes.

**igir** (`overlays/70-igir.nix`): four-platform overlay. Update all four hashes.

**tmux** (`overlays/96-tmux.nix`): single GitHub source archive (`fetchFromGitHub`), pinned
ahead of the next nixpkgs bump. Update the `tag` and `hash`.

**go** (`overlays/55-go.nix`): four-platform overlay fetched from go.dev. Check latest stable
via:
```bash
curl -sf 'https://go.dev/dl/?mode=json' | jq -r 'map(select(.stable)) | .[0].version | ltrimstr("go")'
```
When the **minor version** changes (e.g. `1.26` → `1.27`), also rename the `go_1_26`
attribute to `go_1_27` throughout the overlay.

---

### Cargo source overlays (`update_type: "cargo-source"`)

**mise** (`overlays/30-mise.nix`): Built from source with Rust/Cargo. Takes ~15 min to build —
do NOT wait for the build to finish in a single session. Procedure:

1. Update `version` in the overlay.
2. Fetch the new source hash:
   ```bash
   nix-prefetch-url --unpack \
     "https://github.com/jdx/mise/archive/refs/tags/v${NEW_VERSION}.tar.gz" 2>/dev/null \
     | xargs nix hash convert --hash-algo sha256 --to sri
   ```
3. Update the `hash =` inside the `fetchFromGitHub` block.
4. Set `cargoHash = "";` (blank string, not `null`).
5. Commit these changes with message `overlays: update mise to vX.Y.Z (cargo hash pending)`.
6. Do NOT attempt to resolve the cargo hash automatically in a scheduled run — the user will
   run `nix run .#build-switch` locally to get the correct cargo hash from the build error,
   then update it.

---

### Go source overlays (`update_type: "go-source"`)

**beads** (`overlays/60-beads.nix`): Built from source with Go.

1. Update `version` in the overlay.
2. Fetch the new source hash:
   ```bash
   nix-prefetch-url --unpack \
     "https://github.com/gastownhall/beads/archive/refs/tags/v${NEW_VERSION}.tar.gz" 2>/dev/null \
     | xargs nix hash convert --hash-algo sha256 --to sri
   ```
3. Update `hash =` inside `fetchFromGitHub`.
4. Set `vendorHash = "";`.
5. Run a quick build attempt to obtain the expected hash from the error output:
   ```bash
   nix build --impure --expr \
     'let pkgs = import <nixpkgs> { overlays = [ (import ./overlays/60-beads.nix) ]; }; in pkgs.beads' \
     2>&1 | grep 'got:' | awk '{print $2}'
   ```
6. Update `vendorHash` with the printed `sha256-...` value.
7. Commit: `overlays: update beads to vX.Y.Z`.

**c4** (`overlays/56-c4.nix`): Tracks latest commit on master (no tags). Step 1 already checks
this automatically (`github-commits` method against `current_rev` in `updates.json`); if it
reports outdated:
```bash
curl -sf -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/Avalanche-io/c4/commits/master" | jq -r '.sha'
```
Update `rev`, the `version` date string (`0-unstable-YYYY-MM-DD`), and `hash`. Then blank
`vendorHash` and get it from a build attempt (same as beads above, but using `56-c4.nix`).
Also update `current_rev` in `overlays/updates.json` to the new full commit SHA.

**hey-cli** (`overlays/94-hey-cli.nix`): Tracks latest commit on `main` (no tags). Step 1
checks this the same way as c4 (`github-commits` against `current_rev`). If outdated:
```bash
curl -sf -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/basecamp/hey-cli/commits/main" | jq -r '.sha'
```
Update `rev`, the `version` date string (`0-unstable-YYYY-MM-DD`), and `hash`. Then blank
`vendorHash` and get it from a build attempt (same pattern as beads/c4, using
`94-hey-cli.nix`). Also update `current_rev` in `overlays/updates.json`.

---

### Python overlays (`update_type: "python-override"`)

**yt-dlp + yt-dlp-ejs** (`overlays/91-yt-dlp.nix`): This is the most complex overlay. Do not
auto-update without reading the overlay carefully.

1. Check latest yt-dlp on GitHub: `yt-dlp/yt-dlp` releases (tag format: `YYYY.MM.DD`).
2. Check latest yt-dlp-ejs on PyPI: `https://pypi.org/pypi/yt_dlp_ejs/json`.
3. Fetch new hashes:
   ```bash
   # yt-dlp source (fetchFromGitHub):
   nix-prefetch-url --unpack \
     "https://github.com/yt-dlp/yt-dlp/archive/refs/tags/${NEW_VERSION}.tar.gz" 2>/dev/null \
     | xargs nix hash convert --hash-algo sha256 --to sri

   # yt-dlp-ejs source (fetchPypi):
   nix-prefetch-url --unpack \
     "https://files.pythonhosted.org/packages/source/y/yt_dlp_ejs/yt_dlp_ejs-${NEW_EJS_VERSION}.tar.gz" 2>/dev/null \
     | xargs nix hash convert --hash-algo sha256 --to sri
   ```
4. Review the `postPatch` block in the overlay — the `curl_cffi` version bounds in
   `_curlcffi.py` sometimes need updating when yt-dlp changes its supported range. Check the
   yt-dlp release notes.
5. Update versions and hashes, then commit: `overlays: update yt-dlp to YYYY.MM.DD`.

---

### Semi-automated overlays — detection is automatic, applying updates is not

**ngrok** (`overlays/20-ngrok.nix`): Uses stable CDN URLs (`bin.equinox.io`) without versioned
release pages, but the darwin-arm64 "stable" URL always serves the latest build. Step 1
downloads it and runs `ngrok version` to detect the current upstream version automatically
(`ngrok-binary` check method). If it reports outdated, update all 6 platform hashes:
```bash
for plat in linux-386 linux-amd64 linux-arm linux-arm64 darwin-amd64 darwin-arm64; do
  ext=tgz; [[ "$plat" == darwin-* ]] && ext=zip
  url="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-${plat}.${ext}"
  nix-prefetch-url --unpack "$url" 2>/dev/null | xargs nix hash convert --hash-algo sha256 --to sri
done
```
Update the `version` and `sha256` fields for each platform entry in the overlay, and bump
`current_version` in `overlays/updates.json`. Skip auto-applying in automated runs — do this
step manually.

**Skip list** (build fixes, not version-pinned — never modify in automated runs):
- `10-feather-font.nix` — intentionally pinned to v1.0
- `80-llm.nix`, `82-fmt.nix`, `83-deno.nix` — `doCheck = false` workarounds
- `81-python313-disable-checks.nix` — Python sandbox test suppression
- `82-python313-httpcore.nix` — neutralized stub
- `90-svg-term-cli.nix` — npm package with vendored lock file
- `92-lmstudio.nix` — macOS codesign workaround
- `93-direnv.nix` — CGO build fix

---

## Step 3 — Verify

After updating overlays, run a quick syntax check:

```bash
# Check nix syntax on modified files (fast):
nix-instantiate --parse overlays/MODIFIED_OVERLAY.nix > /dev/null

# Optional: test build for prebuilt-binary overlays on this machine:
nix build --impure --expr \
  'let pkgs = import <nixpkgs> { overlays = [ (import ./overlays/OVERLAY.nix) ]; }; in pkgs.PACKAGE'
```

Do NOT run `nix run .#build-switch` in a remote/cloud session — that requires root on the
local machine.

---

## Step 4 — Commit

Group all overlay updates in a single commit:

```
overlays: update <pkg1> to vX.Y, <pkg2> to vA.B, <pkg3> to vC.D
```

Mirror the style of recent commits (see `git log --oneline -5`). Do not include updated
`flake.lock` in the same commit as overlay changes.

---

## flake.lock Updates

To update nixpkgs and other flake inputs:

```bash
nix flake update
```

Commit with: `flake.lock: Update`

Do not mix lock file updates with overlay version bumps.

---

## Smart Incremental Updates (Automated)

The repository includes a **smart incremental update system** that automates detection of
changes in both overlays and flake inputs, respecting per-input update cadence and frozen
`pinned_inputs[]` — but it only *auto-applies* flake-input movement. Overlay version bumps are
always detected automatically but never auto-applied; you still run the manual routine above to
actually bump one.

- `nix run .#check` — read-only gate that probes upstream sources (GitHub, PyPI, etc.) and
  caches results in `.update-state.json` (a gitignored, deletable file). Reports which
  packages/inputs have new versions available. Never mutates anything.
- `nix run .#prepare` — probes flake inputs and overlays, but **gates its build/commit
  decision on flake-input movement only**. If a due flake input has actually moved upstream, it
  updates just that input, builds the resulting system as evidence, and commits. If overlays
  are outdated, `prepare` prints them (e.g. `overlays outdated (not auto-updated — see
  docs/overlay-update-routine.md): claude-code, uv`) but takes no action on them — it never
  calls `fix-hashes`, never rewrites an overlay `.nix` file, and never touches
  `overlays/updates.json`. This is intentional: bumping a pinned overlay's version requires
  rewriting the overlay's pinned version/hash *and* `updates.json`'s `current_version`
  together (exactly what the manual routine above does) — auto-applying only the latter would
  leave the manifest permanently lying about what's actually pinned, and would mask the
  package as "up to date" on every subsequent probe without the underlying artifact ever
  having changed. Use the manual routine above to actually bump an outdated overlay.
- If `prepare` can't acquire its lock (another `prepare` run — manual or scheduled — is already
  in progress), it exits with status `2` rather than the general failure status `1`.
  `scheduled-check` (below) treats that specific exit code as benign lock contention and stays
  silent, rather than sending a failure notification.
- Per-input update cadence is configured in `overlays/updates.json` under `inputs.*`, e.g.:
  ```json
  "inputs": {
    "nixpkgs": { "cadence_hours": 168 },
    "home-manager": { "cadence_hours": 168 }
  }
  ```
- `pinned_inputs[]` entries (e.g., `"nixpkgs"` today) are always frozen regardless of cadence
  and never auto-update.
- A daily **launchd agent** (`nixos-update-check`) runs `scheduled-check`, which runs `prepare`
  itself (propose only: build + commit, no privileged switch) and notifies you via macOS
  notification of the proposed revision, but never activates. You review and run
  `nix run .#activate -- <rev>` manually.

This design separates cheap, safe read-only checks (and flake-input auto-updates, which are
low-risk and easily reverted) from privileged system activation and from overlay version bumps
(which require rewriting pinned hashes and so stay a deliberate, manual action). The manual
overlay update routine above still works unchanged — it's the only way overlay bumps happen now,
automated or not.
