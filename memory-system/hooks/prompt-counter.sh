#!/usr/bin/env bash
# UserPromptSubmit — counts prompts and drops a single memory reminder once the
# session has clearly become a long one.
#
# Fires exactly once, at prompt 15. A reminder that repeats gets tuned out, and
# an agent that is being nagged every turn starts writing memory entries to
# satisfy the nag rather than because there is something worth keeping.
set -u

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HOOK_DIR/_common.sh"

STATE_DIR="$HOOK_DIR/.state"
mkdir -p "$STATE_DIR"

COUNT=0
# `read` returns 1 on a file with no trailing newline but still fills the
# variable; the numeric check below is what actually validates it.
[ -s "$STATE_DIR/prompt_count" ] && { read -r COUNT < "$STATE_DIR/prompt_count" || :; }
COUNT=$(sanitize_num "$COUNT")
COUNT=$((COUNT + 1))
printf '%s\n' "$COUNT" > "$STATE_DIR/prompt_count"

if [ "$COUNT" -eq 15 ]; then
  emit_context "UserPromptSubmit" \
    "[Memory] This session has run long. Before it ends, update memory/Last-Session.md and memory/Threads.md."
fi
exit 0
