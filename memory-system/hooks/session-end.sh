#!/usr/bin/env bash
# SessionEnd — if this session did real work but wrote nothing to memory, leave a
# marker. The next SessionStart picks it up and injects it as a warning.
#
# Why this exists: the format validator cannot detect a file that is simply OLD.
# One session ran for hours, landed 23 commits, and skipped the memory step; the
# bridge then worked flawlessly and presented finished work as pending. Valid
# file, wrong answer. See catalog/memory.md, mode 2.
#
# Why the criterion is COMMITS and not prompt count: prompt count measures
# conversation, commits measure work. A session that talked and changed nothing
# has nothing worth remembering, and warning about it is noise. If code changed,
# at minimum the question "why did we do it that way" now exists.
#
# Note: state files are truncated, not deleted. Same effect, less to go wrong.
set -u

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HOOK_DIR/_common.sh"

PROJECT_DIR=$(resolve_project_dir)
MEM_DIR=$(resolve_memory_dir)
STATE_DIR="$HOOK_DIR/.state"
mkdir -p "$STATE_DIR"

START=0
# `read` returns 1 on a file with no trailing newline but still fills the
# variable. Swallow the status and let the numeric check below do the validating.
[ -s "$STATE_DIR/session_start_time" ] && { read -r START < "$STATE_DIR/session_start_time" || :; }
START=$(sanitize_num "$START")
[ "$START" -eq 0 ] && exit 0        # no start stamp, nothing to measure against

# 1. Did this session do any work? --all so that branches created inside a
#    worktree are counted too.
COMMITS=$(git -C "$PROJECT_DIR" log --all --since="@$START" --oneline 2>/dev/null | wc -l | tr -d ' ')
COMMITS=$(sanitize_num "$COMMITS")
[ "$COMMITS" -eq 0 ] && { : > "$STATE_DIR/session_start_time"; exit 0; }

# 2. Was memory touched?
WROTE=0
for f in "$MEM_DIR"/*.md; do
  [ -f "$f" ] || continue
  FM=$(sanitize_num "$(mtime_of "$f")")
  # -ge rather than -gt: stat has one-second resolution, so a file written in the
  # same second the session started would slip past -gt. The safe direction to be
  # wrong in is "don't warn".
  [ "$FM" -ge "$START" ] && { WROTE=1; break; }
done

if [ "$WROTE" -eq 0 ]; then
  printf '%s commit(s) landed, nothing written to memory. Session ended: %s\n' \
    "$COMMITS" "$(date '+%Y-%m-%d %H:%M')" > "$STATE_DIR/needs_memory_review"
  cp "$STATE_DIR/needs_memory_review" "$STATE_DIR/needs_reflection" 2>/dev/null || :
fi

: > "$STATE_DIR/session_start_time"
: > "$STATE_DIR/prompt_count"
exit 0
