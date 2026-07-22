#!/usr/bin/env bash
#
# sync-to-public.sh — mirror public-safe files from the private daily-driver
# checkout (~/nixos-config) into the public mirror (~/src/nixos-config), then
# commit and push.
#
# The set of files published = every git-tracked file in the private repo MINUS
# the paths listed in scripts/public-sync-denylist.txt. Anything tracked in the
# public repo that is NOT in that set is removed — so a denylisted (private)
# file can never linger in public, and deletions propagate.
#
# Safe to run by hand; also invoked from scripts/git-hooks/post-commit after
# every commit in the private repo. A commit that only touched denylisted files
# produces no public commit.
#
# Overridable via env: PRIVATE_REPO, PUBLIC_REPO.
set -euo pipefail

# --- Locate repos -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIVATE_REPO="${PRIVATE_REPO:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
PUBLIC_REPO="${PUBLIC_REPO:-$HOME/src/nixos-config}"
DENYLIST="$PRIVATE_REPO/scripts/public-sync-denylist.txt"

log() { printf 'sync-to-public: %s\n' "$*"; }

if [[ ! -d "$PUBLIC_REPO/.git" ]]; then
  log "public repo not found at $PUBLIC_REPO — skipping."
  exit 0
fi

# --- Build the denylist matcher ---------------------------------------------
deny_exact=()   # exact file paths
deny_prefix=()  # directory prefixes (entries ending in '/')
if [[ -f "$DENYLIST" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"                 # strip inline/full comments
    line="${line#"${line%%[![:space:]]*}"}"  # ltrim
    line="${line%"${line##*[![:space:]]}"}"   # rtrim
    [[ -z "$line" ]] && continue
    if [[ "$line" == */ ]]; then
      deny_prefix+=("$line")
    else
      deny_exact+=("$line")
    fi
  done < "$DENYLIST"
fi

is_denied() {
  local f="$1" e
  for e in "${deny_exact[@]}"; do [[ "$f" == "$e" ]] && return 0; done
  for e in "${deny_prefix[@]}"; do [[ "$f" == "$e"* ]] && return 0; done
  return 1
}

# --- Compute the public set (private tracked files minus denylist) ----------
public_set="$(mktemp)"
public_tracked="$(mktemp)"
trap 'rm -f "$public_set" "$public_tracked"' EXIT

while IFS= read -r f; do
  is_denied "$f" || printf '%s\n' "$f"
done < <(git -C "$PRIVATE_REPO" ls-files) | sort > "$public_set"

git -C "$PUBLIC_REPO" ls-files | sort > "$public_tracked"

# --- Surface files being published for the FIRST time (denylist safety) -----
new_files="$(comm -13 "$public_tracked" "$public_set")"
if [[ -n "$new_files" ]]; then
  log "Publishing NEW files (first time public — deny in public-sync-denylist.txt if unintended):"
  printf '  + %s\n' $new_files
fi

# --- Copy the public set into the public repo -------------------------------
while IFS= read -r f; do
  mkdir -p "$PUBLIC_REPO/$(dirname "$f")"
  # -P: copy symlinks as symlinks (don't follow, e.g. apps/aarch64-linux).
  # -f: replace an existing file/symlink at the destination.
  cp -Ppf "$PRIVATE_REPO/$f" "$PUBLIC_REPO/$f"
done < "$public_set"

# --- Remove anything tracked in public but not in the public set ------------
# (covers deletions in private AND any denylisted file that reached public)
comm -23 "$public_tracked" "$public_set" | while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  git -C "$PUBLIC_REPO" rm -q --ignore-unmatch -- "$f" >/dev/null
done

# --- Commit & push if anything changed --------------------------------------
git -C "$PUBLIC_REPO" add -A
if git -C "$PUBLIC_REPO" diff --cached --quiet; then
  log "no public-safe changes to mirror."
  exit 0
fi

subject="$(git -C "$PRIVATE_REPO" log -1 --format=%s 2>/dev/null || echo 'sync from daily driver')"
git -C "$PUBLIC_REPO" commit -q -m "$subject"
log "committed to public: $subject"

if git -C "$PUBLIC_REPO" push -q origin HEAD; then
  log "pushed to origin."
else
  log "WARNING: push failed (offline?). Commit is local in $PUBLIC_REPO — push manually later."
fi
