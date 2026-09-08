#!/usr/bin/env bash
# Shared helpers. All four hooks source this file.
#
# Portable across Git Bash on Windows and POSIX shells: no jq, no python.
# Path normalization goes through cygpath when it is available.

# --- Paths -------------------------------------------------------------------

# Project root. Claude Code hands CLAUDE_PROJECT_DIR over in native format
# (C:\... on Windows); convert it to a POSIX path so the rest of the script can
# use it. Falls back to the current directory.
resolve_project_dir() {
  local p="${CLAUDE_PROJECT_DIR:-$PWD}"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$p" 2>/dev/null || printf '%s' "$p"
  else
    printf '%s' "$p"
  fi
}

# Where the memory files live. Override with AGENT_MEMORY_DIR if you keep them
# somewhere other than <project>/memory.
resolve_memory_dir() {
  if [ -n "${AGENT_MEMORY_DIR:-}" ]; then
    printf '%s' "$AGENT_MEMORY_DIR"
  else
    printf '%s/memory' "$(resolve_project_dir)"
  fi
}

# --- Small utilities ---------------------------------------------------------

# Pure-bash JSON string escape. Order matters: backslashes first, or you double
# the escapes you just introduced.
#
# NOTE: do not write this function through a shell heredoc. Backslashes collapse
# on the way in, bash -n stays clean, and the function silently starts doing a
# different job. See catalog/tooling.md#12.
json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\r'/}
  s=${s//$'\t'/\\t}
  s=${s//$'\n'/\\n}
  printf '"%s"' "$s"
}

# File mtime as a unix epoch. GNU stat uses -c, BSD uses -f; try both.
mtime_of() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# Keep digits only; anything else becomes 0.
sanitize_num() {
  case "$1" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$1" ;; esac
}

# Emit a Claude Code hook result carrying additional context.
emit_context() {
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":%s}}\n' \
    "$1" "$(json_escape "$2")"
}

# --- Format validation -------------------------------------------------------
#
# Why this exists: a session block was once appended into the middle of the
# file's own format documentation, where the literal marker strings happened to
# live. The real heading ended up nested in a blockquote, the line-anchored
# pattern stopped matching, and the hook served a DAY-OLD block without any
# error. See catalog/memory.md, mode 1.
#
# This function converts that silent class into a loud one. It prints one line
# per problem and nothing at all when the files are clean, so callers can just
# test whether the output is empty.
#
# It checks four things per file:
#   1. each marker appears exactly once at the start of a line
#   2. each marker appears nowhere else in the text (the trap above)
#   3. the markers are in the right order
#   4. the current block is not empty
validate_memory() {
  local mem_dir=$1
  local f n_anchor n_loose n_prev n_prev_loose ln_a ln_p closed

  # --- Last-Session.md ---
  f="$mem_dir/Last-Session.md"
  if [ ! -f "$f" ]; then
    printf 'Last-Session.md not found (%s)\n' "$f"
  else
    n_anchor=$(grep -c     '^## Session:'        "$f" 2>/dev/null || :)
    n_loose=$(grep -c      '## Session:'         "$f" 2>/dev/null || :)
    n_prev=$(grep -c       '^## Previous Sessions' "$f" 2>/dev/null || :)
    n_prev_loose=$(grep -c '## Previous Sessions'  "$f" 2>/dev/null || :)

    [ "${n_anchor:-0}" -eq 1 ] || \
      printf 'Last-Session.md: %s line-anchored session headings (expected 1)\n' "${n_anchor:-0}"
    [ "${n_prev:-0}" -eq 1 ] || \
      printf 'Last-Session.md: %s line-anchored previous-sessions headings (expected 1)\n' "${n_prev:-0}"
    [ "${n_loose:-0}" -eq "${n_anchor:-0}" ] || \
      printf 'Last-Session.md: session marker also appears mid-text (%s occurrences / %s at line start) — the wedged-block trap\n' "${n_loose:-0}" "${n_anchor:-0}"
    [ "${n_prev_loose:-0}" -eq "${n_prev:-0}" ] || \
      printf 'Last-Session.md: previous-sessions marker also appears mid-text (%s / %s)\n' "${n_prev_loose:-0}" "${n_prev:-0}"

    if [ "${n_anchor:-0}" -eq 1 ] && [ "${n_prev:-0}" -eq 1 ]; then
      ln_a=$(grep -n '^## Session:'          "$f" | head -1 | cut -d: -f1)
      ln_p=$(grep -n '^## Previous Sessions' "$f" | head -1 | cut -d: -f1)
      if [ "$ln_a" -lt "$ln_p" ]; then
        # Only meaningful when the order is right; otherwise the subtraction is
        # negative and the message is noise on top of a real error.
        [ $((ln_p - ln_a)) -gt 2 ] || \
          printf 'Last-Session.md: current session block looks empty (%s lines)\n' "$((ln_p - ln_a))"
      else
        printf 'Last-Session.md: session heading (line %s) comes AFTER previous-sessions (line %s) — the extracted block will be empty\n' "$ln_a" "$ln_p"
      fi
    fi
  fi

  # --- Threads.md ---
  f="$mem_dir/Threads.md"
  if [ ! -f "$f" ]; then
    printf 'Threads.md not found (%s)\n' "$f"
  else
    n_anchor=$(grep -c     '^## Active Threads' "$f" 2>/dev/null || :)
    n_loose=$(grep -c      '## Active Threads'  "$f" 2>/dev/null || :)
    n_prev=$(grep -c       '^## Closed Threads' "$f" 2>/dev/null || :)
    n_prev_loose=$(grep -c '## Closed Threads'  "$f" 2>/dev/null || :)

    [ "${n_anchor:-0}" -eq 1 ] || \
      printf 'Threads.md: %s line-anchored active headings (expected 1)\n' "${n_anchor:-0}"
    [ "${n_prev:-0}" -eq 1 ] || \
      printf 'Threads.md: %s line-anchored closed headings (expected 1)\n' "${n_prev:-0}"
    [ "${n_loose:-0}" -eq "${n_anchor:-0}" ] || \
      printf 'Threads.md: active marker also appears mid-text (%s / %s)\n' "${n_loose:-0}" "${n_anchor:-0}"
    [ "${n_prev_loose:-0}" -eq "${n_prev:-0}" ] || \
      printf 'Threads.md: closed marker also appears mid-text (%s / %s)\n' "${n_prev_loose:-0}" "${n_prev:-0}"

    if [ "${n_anchor:-0}" -eq 1 ] && [ "${n_prev:-0}" -eq 1 ]; then
      ln_a=$(grep -n '^## Active Threads' "$f" | head -1 | cut -d: -f1)
      ln_p=$(grep -n '^## Closed Threads' "$f" | head -1 | cut -d: -f1)
      [ "$ln_a" -lt "$ln_p" ] || \
        printf 'Threads.md: active heading (line %s) comes AFTER closed heading (line %s)\n' "$ln_a" "$ln_p"
    fi

    # A closed thread left in the active section makes finished work look open
    # on the following morning.
    closed=$(sed -n '/^## Active Threads/,/^## Closed Threads/p' "$f" 2>/dev/null \
             | grep -cE '^\*\*Status:\*\* *(DONE|Done|Closed|CLOSED)' || :)
    [ "${closed:-0}" -eq 0 ] || \
      printf 'Threads.md: %s CLOSED thread(s) still in the active section — move them down\n' "${closed:-0}"
  fi
}
