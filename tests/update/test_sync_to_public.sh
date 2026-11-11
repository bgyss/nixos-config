#!/usr/bin/env bash
# sync-to-public.sh must publish COMMITTED content (HEAD), not the working tree:
# an uncommitted edit to a tracked file must not reach the public repo under
# whichever commit fires the sync, and denylisted files must stay out.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
fail() { echo "FAIL: $1"; exit 1; }

root="$(mktemp -d)"
priv="$root/private"; pub="$root/public"; bare="$root/origin.git"
git init -q --bare "$bare"
mkdir -p "$priv/scripts" "$pub"
cp "$REPO/scripts/sync-to-public.sh" "$priv/scripts/"
git -C "$priv" init -q; git -C "$pub" init -q
for r in "$priv" "$pub"; do git -C "$r" config user.email t@example.com; git -C "$r" config user.name Test; done
git -C "$pub" remote add origin "$bare"

printf 'one\n' > "$priv/a.txt"
printf 'secret\n' > "$priv/private-note.md"
ln -s a.txt "$priv/link"
printf 'scripts/public-sync-denylist.txt\nprivate-note.md\n' > "$priv/scripts/public-sync-denylist.txt"
git -C "$priv" add -A; git -C "$priv" commit -qm "first"

run() { PRIVATE_REPO="$priv" PUBLIC_REPO="$pub" bash "$priv/scripts/sync-to-public.sh" >"$root/out.log" 2>&1; }
run || { cat "$root/out.log"; fail "initial sync failed"; }
[[ "$(cat "$pub/a.txt")" == "one" ]] || fail "a.txt not published"
[[ ! -e "$pub/private-note.md" ]] || fail "denylisted file published"
[[ -L "$pub/link" ]] || fail "symlink not preserved as a symlink"

# Uncommitted edit + a new untracked file: neither may be published.
printf 'two (uncommitted)\n' > "$priv/a.txt"
printf 'draft\n' > "$priv/untracked.txt"
run || { cat "$root/out.log"; fail "second sync failed"; }
[[ "$(cat "$pub/a.txt")" == "one" ]] || fail "uncommitted edit leaked into public ($(cat "$pub/a.txt"))"
[[ ! -e "$pub/untracked.txt" ]] || fail "untracked file leaked into public"
grep -q "no public-safe changes" "$root/out.log" || { cat "$root/out.log"; fail "expected nothing to mirror"; }

# Once committed, it IS published — under its own commit.
git -C "$priv" add a.txt; git -C "$priv" commit -qm "edit a"
run || { cat "$root/out.log"; fail "third sync failed"; }
[[ "$(cat "$pub/a.txt")" == "two (uncommitted)" ]] || fail "committed edit not published"
[[ "$(git -C "$pub" log -1 --format=%s)" == "edit a" ]] || fail "public commit subject mismatch"
[[ ! -e "$pub/untracked.txt" ]] || fail "untracked file leaked after commit"

rm -rf "$root"
echo "PASS: test_sync_to_public"
