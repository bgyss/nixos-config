# Agent Guide — nixos-config

This file is the primary reference for automated agents (e.g. scheduled Claude Code routines).
Human guidelines and codebase documentation live in [CLAUDE.md](./CLAUDE.md).

---

## Daily Overlay Update Routine

Goal: check all version-pinned overlays for new upstream releases, apply updates, verify the build, and commit.

### Step 1 — Run the version check

```bash
bash scripts/check-overlay-versions.sh
```

This queries GitHub Releases, go.dev, and PyPI and prints a table of `current` vs `latest` versions. If all packages are up to date the script exits 0 and you are done — nothing to commit.

If any packages are `OUTDATED`, continue to Step 2.

The manifest at `overlays/updates.json` is the authoritative list of which overlays are version-pinned and how to check/update each one. Read it before making any changes.

---

### Step 2 — Apply updates by overlay type

#### Prebuilt binary overlays (`update_type: "prebuilt-binary"` or `"prebuilt-binary-multiplatform"`)

These overlays fetch pre-built binaries directly from upstream. The update procedure is:

1. Update the `version` string in the overlay file.
2. For each platform listed in `updates.json`, expand the `url_template` by replacing `{version}` with the new version string.
3. Fetch the new hash for each URL:
   ```bash
   # For archives (tar.gz, zip):
   nix-prefetch-url --unpack <URL> 2>/dev/null \
     | xargs nix hash convert --hash-algo sha256 --to sri

   # For plain binaries (no archive, like claude-code):
   nix-prefetch-url <URL> 2>/dev/null \
     | xargs nix hash convert --hash-algo sha256 --to sri
   ```
4. Replace `hash =`, `sha256 =`, or the per-platform `hash =` fields in the overlay with the new SRI hashes.

**claude-code** (`overlays/41-claude-code.nix`): single aarch64-darwin binary (not an archive — use `nix-prefetch-url` without `--unpack`).

**codex-openai** (`overlays/40-codex-openai.nix`): single aarch64-darwin archive. The GitHub release tag is `rust-vX.Y.Z`; the version field in the overlay is `X.Y.Z`.

**uv** (`overlays/25-uv.nix`): single aarch64-darwin archive. GitHub tag is `X.Y.Z` (no `v` prefix).

**trailbase** (`overlays/50-trailbase.nix`): three-platform overlay (aarch64-darwin, x86_64-darwin, x86_64-linux). Update all three hashes.

**igir** (`overlays/70-igir.nix`): four-platform overlay. Update all four hashes.

**go** (`overlays/55-go.nix`): four-platform overlay fetched from go.dev. Check latest stable via:
```bash
curl -sf 'https://go.dev/dl/?mode=json' | jq -r 'map(select(.stable)) | .[0].version | ltrimstr("go")'
```
When the **minor version** changes (e.g. `1.26` → `1.27`), also rename the `go_1_26` attribute to `go_1_27` throughout the overlay.

---

#### Cargo source overlays (`update_type: "cargo-source"`)

**mise** (`overlays/30-mise.nix`): Built from source with Rust/Cargo. Takes ~15 min to build — do NOT wait for the build to finish in a single session. Procedure:

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
6. Do NOT attempt to resolve the cargo hash automatically in a scheduled run — the user will run `nix run .#build-switch` locally to get the correct cargo hash from the build error, then update it.

---

#### Go source overlays (`update_type: "go-source"`)

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

**c4** (`overlays/56-c4.nix`): Tracks latest commit on master (no tags). Check for new commits:
```bash
curl -sf -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/Avalanche-io/c4/commits/master" | jq -r '.sha'
```
Update `rev`, the `version` date string (`0-unstable-YYYY-MM-DD`), and `hash`. Then blank `vendorHash` and get it from a build attempt (same as beads above, but using `56-c4.nix`).

---

#### Python overlays (`update_type: "python-override"`)

**yt-dlp + yt-dlp-ejs** (`overlays/91-yt-dlp.nix`): This is the most complex overlay. Do not auto-update without reading the overlay carefully.

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
4. Review the `postPatch` block in the overlay — the `curl_cffi` version bounds in `_curlcffi.py` sometimes need updating when yt-dlp changes its supported range. Check the yt-dlp release notes.
5. Update versions and hashes, then commit: `overlays: update yt-dlp to YYYY.MM.DD`.

---

#### Manual overlays — do not auto-update

**ngrok** (`overlays/20-ngrok.nix`): Uses stable CDN URLs (`bin.equinox.io`) without versioned paths. Updating requires knowing the new version number from the ngrok website, then fetching 6 platform hashes. Skip in automated runs.

**Skip list** (build fixes, not version-pinned — never modify in automated runs):
- `10-feather-font.nix` — intentionally pinned to v1.0
- `80-llm.nix`, `82-fmt.nix`, `83-deno.nix` — `doCheck = false` workarounds
- `81-python313-disable-checks.nix` — Python sandbox test suppression
- `82-python313-httpcore.nix` — neutralized stub
- `90-svg-term-cli.nix` — npm package with vendored lock file
- `92-lmstudio.nix` — macOS codesign workaround
- `93-direnv.nix` — CGO build fix

---

### Step 3 — Verify

After updating overlays, run a quick syntax check:

```bash
# Check nix syntax on modified files (fast):
nix-instantiate --parse overlays/MODIFIED_OVERLAY.nix > /dev/null

# Optional: test build for prebuilt-binary overlays on this machine:
nix build --impure --expr \
  'let pkgs = import <nixpkgs> { overlays = [ (import ./overlays/OVERLAY.nix) ]; }; in pkgs.PACKAGE'
```

Do NOT run `nix run .#build-switch` in a remote/cloud session — that requires root on the local machine.

---

### Step 4 — Commit

Group all overlay updates in a single commit:

```
overlays: update <pkg1> to vX.Y, <pkg2> to vA.B, <pkg3> to vC.D
```

Mirror the style of recent commits (see `git log --oneline -5`). Do not include updated `flake.lock` in the same commit as overlay changes.

---

## flake.lock Updates

To update nixpkgs and other flake inputs:

```bash
nix flake update
```

Commit with: `flake.lock: Update`

Do not mix lock file updates with overlay version bumps.

---

## Repo Layout Quick Reference

```
overlays/            # Nix overlays (auto-loaded by modules/shared/default.nix)
overlays/updates.json  # Machine-readable manifest for automated version checks
scripts/             # Developer/agent utility scripts
  check-overlay-versions.sh  # Query upstream APIs, report OUTDATED packages
apps/                # nix run .#<cmd> entry points (build-switch, apply, rollback)
modules/shared/      # Cross-platform home-manager and system config
modules/darwin/      # macOS-specific config
hosts/darwin/        # Host-level macOS config
flake.nix            # Flake inputs, outputs, overlay loading
```

## Build Commands (local machine only)

```bash
nix run .#build-switch   # Full rebuild + activate (requires sudo)
nix run .#apply          # Apply without rebuilding
nix run .#rollback       # Roll back to previous generation
```
