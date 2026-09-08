#!/usr/bin/env bash
# SessionStart — injects the previous session's handoff, the active threads, and
# any warnings into the new session's context.
#
# This hook once served a DAY-OLD block without erroring, and the morning started
# with a task list of already-finished work. Two independent silent failures were
# involved:
#   (a) the new block had been wedged into the file's own format documentation,
#       so the line-anchored pattern missed it and sed fell through to the
#       previous block;
#   (b) the thread list was cut with `head -12`, which was exactly 6 threads —
#       the one that mattered was 7th and never appeared.
# Neither errored. Both presented a wrong answer as a right one.
#
# Everything below exists to make that class loud: suspect state prints a warning
# at the TOP of the injected context, staleness is stated in days, and any
# truncation announces itself.
#
# See catalog/memory.md.
set -u

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HOOK_DIR/_common.sh"

PROJECT_DIR=$(resolve_project_dir)
MEM_DIR=$(resolve_memory_dir)
STATE_DIR="$HOOK_DIR/.state"
mkdir -p "$STATE_DIR"

date +%s > "$STATE_DIR/session_start_time"
printf '0\n' > "$STATE_DIR/prompt_count"

MAX_SESSION_LINES=70
MAX_THREAD_LINES=60

# --- 1. Format validation ----------------------------------------------------
PROBLEMS=$(validate_memory "$MEM_DIR" 2>/dev/null || :)

# --- 2. Previous session block ----------------------------------------------
LAST_SESSION=""
FRESHNESS=""
if [ -f "$MEM_DIR/Last-Session.md" ]; then
  BLOCK=$(sed -n '/^## Session:/,/^## Previous Sessions/p' "$MEM_DIR/Last-Session.md" 2>/dev/null | sed '$d')
  if [ -n "$BLOCK" ]; then
    NLINES=$(printf '%s\n' "$BLOCK" | wc -l | tr -d ' ')
    LAST_SESSION=$(printf '%s\n' "$BLOCK" | head -"$MAX_SESSION_LINES")

    # Truncation must announce itself. Silent truncation is how the thread that
    # mattered went missing.
    if [ "${NLINES:-0}" -gt "$MAX_SESSION_LINES" ]; then
      LAST_SESSION="${LAST_SESSION}"$'\n'"[...] block is ${NLINES} lines, TRUNCATED at ${MAX_SESSION_LINES} — read memory/Last-Session.md for the rest."
    fi

    # Staleness: compare the date in the heading against today. A well-formed
    # file can still be two days old; the format validator cannot see that.
    BDATE=$(printf '%s\n' "$BLOCK" | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
    TODAY=$(date +%Y-%m-%d)
    if [ -n "${BDATE:-}" ]; then
      T_NOW=$(date -d "$TODAY" +%s 2>/dev/null || echo 0)
      T_BLK=$(date -d "$BDATE" +%s 2>/dev/null || echo 0)
      if [ "$T_NOW" -gt 0 ] && [ "$T_BLK" -gt 0 ]; then
        DIFF=$(( (T_NOW - T_BLK) / 86400 ))
        case "$DIFF" in
          0) FRESHNESS="Bridge date: $BDATE (today)." ;;
          1) FRESHNESS="Bridge date: $BDATE (today is $TODAY — 1 day ago)." ;;
          *) FRESHNESS="Bridge date: $BDATE (today is $TODAY — $DIFF days ago). THERE MAY BE UNRECORDED SESSIONS; verify state before acting on this." ;;
        esac
      fi
    else
      FRESHNESS="No date in the bridge heading — freshness could not be checked."
    fi
  else
    PROBLEMS="${PROBLEMS}"$'\n'"Last-Session.md: the session block came back EMPTY; no bridge could be built."
  fi
fi

# --- 3. Active threads -------------------------------------------------------
# Headings alone are not enough: status sentences run over several lines and used
# to be cut mid-sentence. Take the Status line plus the two lines that follow it.
THREADS=""
if [ -f "$MEM_DIR/Threads.md" ]; then
  T_ALL=$(awk '
    /^## Active Threads/ { inz=1; next }
    /^## Closed Threads/ { inz=0 }
    !inz { next }
    /^### Thread:/     { print; want=0; next }
    /^\*\*Status:\*\*/ { print; want=2; next }
    want>0 && NF>0     { print; want--; next }
    { want=0 }
  ' "$MEM_DIR/Threads.md" 2>/dev/null)

  T_TOTAL=$(printf '%s\n' "$T_ALL" | grep -c '^### Thread:' || :)
  THREADS=$(printf '%s\n' "$T_ALL" | head -"$MAX_THREAD_LINES")
  T_SHOWN=$(printf '%s\n' "$THREADS" | grep -c '^### Thread:' || :)

  if [ "${T_SHOWN:-0}" -lt "${T_TOTAL:-0}" ]; then
    THREADS="${THREADS}"$'\n'"[...] showed ${T_SHOWN} of ${T_TOTAL} active threads, $(( T_TOTAL - T_SHOWN )) TRUNCATED — read memory/Threads.md."
  fi
fi

# --- 4. Warning left by the previous session --------------------------------
REFLECTION=""
if [ -s "$STATE_DIR/needs_reflection" ]; then
  MARKER=""
  read -r MARKER < "$STATE_DIR/needs_reflection" || :
  REFLECTION="WARNING: the previous session ended without updating memory (${MARKER}). If anything meaningful happened, the bridge above is incomplete."
  : > "$STATE_DIR/needs_reflection"   # consumed
fi

# --- 5. Assemble — warnings go FIRST ----------------------------------------
CTX=""
if [ -n "$PROBLEMS" ]; then
  CTX="${CTX}[!! MEMORY BRIDGE SUSPECT — do NOT trust what follows; read the files yourself !!]"$'\n'
  CTX="${CTX}${PROBLEMS}"$'\n'
  CTX="${CTX}Fix these before starting work, and tell the user."$'\n\n'
fi
[ -n "$REFLECTION" ]   && CTX="${CTX}${REFLECTION}"$'\n\n'
[ -n "$FRESHNESS" ]    && CTX="${CTX}[Memory — freshness] ${FRESHNESS}"$'\n\n'
[ -n "$LAST_SESSION" ] && CTX="${CTX}[Memory — previous session]"$'\n'"${LAST_SESSION}"$'\n\n'
[ -n "$THREADS" ]      && CTX="${CTX}[Memory — active threads]"$'\n'"${THREADS}"$'\n\n'
CTX="${CTX}[Memory] Read DECISIONS from this bridge; verify STATE from git. Update memory/Last-Session.md and memory/Threads.md before the session ends."

emit_context "SessionStart" "$CTX"
exit 0
