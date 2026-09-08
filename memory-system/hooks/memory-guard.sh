#!/usr/bin/env bash
# PostToolUse (Write|Edit) — re-validates the memory files after every write.
#
# This is the highest-value hook in the set, and the reason is timing rather than
# cleverness. The original corruption was written one evening and only surfaced
# the next morning, as a wrong task list. The feedback loop was A FULL DAY long.
# This hook makes it about a second: the session that breaks the file is told
# while it is still there to fix it.
#
# Stays quiet when there is nothing wrong: no output, no blocking, exit 0.
#
# See catalog/memory.md, mode 1.
set -u

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HOOK_DIR/_common.sh"

MEM_DIR=$(resolve_memory_dir)
[ -d "$MEM_DIR" ] || exit 0

PROBLEMS=$(validate_memory "$MEM_DIR" 2>/dev/null || :)
[ -n "$PROBLEMS" ] || exit 0

MSG="[!! MEMORY FORMAT BROKEN — fix it now, before this session ends !!]
${PROBLEMS}

This failure is silent: it raises no error. It surfaces tomorrow morning, as the
bridge serving the WRONG block. Rule: append a new session block AFTER the unique
'# Last Session' anchor. Never write by matching the marker strings themselves —
they also appear in this file's own documentation, and that is exactly how a
block once got wedged into the wrong place."

emit_context "PostToolUse" "$MSG"
exit 0
