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
  [[ -f "$f" ]] || return 1
  if ! jq empty "$f" >/dev/null 2>&1; then
    echo "quarantine: ledger at $f is not valid JSON — treating as empty (quarantines will NOT be honored)" >&2
    return 1
  fi
  return 0
}

quarantine_init() {
  local f; f="$(_q_file)"
  if ! _q_readable; then
    printf '{"comment":"Machine-written quarantine ledger. See docs/superpowers/specs/2026-07-25-self-healing-updates-design.md §2. Do not hand-edit while the daily pipeline may be running; use scripts/quarantine.sh.","entries":[]}\n' > "$f"
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
