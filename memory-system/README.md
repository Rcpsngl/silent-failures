# Cross-session memory that fails loudly

Four Claude Code hooks that carry context between sessions, plus the validation
that exists because this system lied one morning and the day started with the
wrong task list.

The memory part is easy. The interesting part is `validate_memory()` — and the
reason it's interesting is timing, not cleverness.

---

## The problem it solves

Injected context arrives **pre-trusted**. It is not something the model went and
fetched and can weigh; it is simply *there* at the top of the conversation,
indistinguishable from fact. So when a memory system is wrong, nothing downstream
questions it.

And a memory system has no natural failure signal. If it serves the wrong block, it
serves it with the same confidence as the right one. The full account of the four
distinct ways this went wrong is in [`../catalog/memory.md`](../catalog/memory.md).

The short version:

| Mode | The bridge is | Caught by |
|---|---|---|
| 1 | malformed | `memory-guard.sh`, on every write |
| 2 | missing | freshness line + `session-end.sh` marker |
| 3 | premature | you, cross-checking git |
| 4 | outside the system | habit |

---

## The files

```
hooks/
  _common.sh          shared helpers + validate_memory()
  session-start.sh    SessionStart     — inject bridge, threads, warnings
  memory-guard.sh     PostToolUse      — re-validate after every Write/Edit
  session-end.sh      SessionEnd       — flag work that left no memory
  prompt-counter.sh   UserPromptSubmit — one reminder at prompt 15
templates/
  Last-Session.md     the handoff file
  Threads.md          ongoing storylines
settings.example.json how to wire it up
```

No `jq`, no `python`. Runs on Git Bash under Windows and on POSIX shells; path
conversion goes through `cygpath` when it exists.

---

## Install

1. Copy `hooks/` into `.claude/hooks/` in your project.
2. Copy `templates/*.md` into `<project>/memory/` (or set `AGENT_MEMORY_DIR`).
3. Merge `settings.example.json` into `.claude/settings.json`.
4. Verify — see below. Do not skip this step; the entire point of the repository
   is that "it seems to work" is not evidence.

---

## Verify it

A guardrail you have not seen fail is not a guardrail. Break the file deliberately
and confirm the check goes loud:

```bash
# clean fixture -> must print nothing
bash -c '. .claude/hooks/_common.sh; validate_memory memory'

# now break it on purpose, in the way that actually happened:
printf '\n> Format: write it as "## Session: <date>".\n' >> memory/Last-Session.md

bash -c '. .claude/hooks/_common.sh; validate_memory memory'
# -> Last-Session.md: session marker also appears mid-text (2 occurrences /
#    1 at line start) — the wedged-block trap
```

Then undo the edit and confirm it goes quiet again. All five failure paths
(marker leaked into prose, duplicate heading, reversed order, closed thread left
active, file missing) were checked this way, plus the clean case, before this was
committed.

---

## The markers

The parser is anchored to line starts. **Each of these must appear exactly once
per file, at the beginning of its line:**

- `Last-Session.md` — a session heading (`## Session:` + date) and a
  `## Previous Sessions` heading
- `Threads.md` — `## Active Threads` and `## Closed Threads`, with each thread as
  `### Thread:` and a `**Status:**` line

They are documented **here** and not inside the data files, deliberately. That is
not tidiness. A block was once appended by matching those strings, landed inside a
file's own format documentation, and the parser served the previous day without
erroring. Format documentation lives in the README; the data file gets a unique
`# Last Session` anchor to append below.

To translate the system, change the markers in `_common.sh`, `session-start.sh`,
and the templates together — they must match.

---

## Design notes

**Warnings go at the top of the injected context, not the bottom.** A warning
under 70 lines of stale summary is a warning nobody acts on.

**Truncation announces itself.** Both the session block and the thread list say
how much was cut and where to read the rest. The original silent `head -12`
happened to be exactly 6 threads; the one that mattered was 7th and simply never
appeared. Nothing indicated anything was missing.

**Staleness is stated in days, in words.** *"Bridge date: 2026-09-06 (today is
2026-09-08 — 2 days ago). THERE MAY BE UNRECORDED SESSIONS."* A date alone gets
skimmed; an arithmetic result does not.

**`session-end.sh` keys on commits, not prompt count.** Prompt count measures
conversation. Commits measure work. A session that talked and changed nothing has
nothing to remember, and warning about it trains you to ignore the warning.

**The hook never writes memory files.** It leaves markers; the model and the human
write. An automatic memory writer produces plausible entries nobody approved, and a
wrong memory is worse than a missing one — it gets trusted for years.

**`-ge` not `-gt` on mtime comparisons.** `stat` has one-second resolution, so a
file written in the same second the session started slips past `-gt`. When a
comparison can be wrong in either direction, pick the direction whose failure is
"don't warn" rather than "warn falsely".

---

## What it cannot do

It validates **format**, never **truth**.

Modes 2, 3 and 4 all produce structurally perfect files. A note frozen at the
moment you thought you were finished looks exactly like a correct one — and in the
sharpest case, the work finished 31 minutes *after* the memory was written. Valid
file, current date, still wrong.

So the habit has to carry the rest:

> **Git knows the state. Memory knows the decisions.**
> Read decisions from the bridge. Verify state from the source.

```bash
git log --all --pretty='%h %ci %d %s' -8
git reflog --date=iso -15
```

The reflog shows when commits were actually made. Compare that against the memory
block's timestamp, and "did anything happen after this was written?" closes in
seconds.
