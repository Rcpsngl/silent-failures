# Session memory

If you give an agent memory across sessions, you have built a new thing that can be
silently wrong. This one is worth its own page because it failed **four different ways**,
each one defeating the guardrail built for the previous.

The setup: a `SessionStart` hook reads a handoff file and injects "here is where you left
off" into the next session's context. Useful. Also an excellent liar, because injected
context arrives pre-trusted — it is not something the model went and fetched, it is
simply *there*, indistinguishable from fact.

The working implementation, with all four guardrails, is in
[`../memory-system/`](../memory-system/).

---

### Mode 1 — the file is malformed, and the extractor lands on the wrong block

2026-08-20. The bridge injected the **previous day's** session. The morning began with a
task list of work that had already been finished.

**Root cause.** The handoff file documented its own format, and the documentation
contained the marker strings literally. When the new session block was appended, it was
matched against those literal markers and landed *inside the documentation block*. The
real heading ended up nested inside a blockquote, so the line-anchored pattern
(`^## Session:`) never matched it, and `sed` fell through to the previous block.

A second, independent bug in the same incident: the thread list was truncated with
`head -12`, which happened to be exactly 6 threads. The actual active work was 7th. It
was never shown at all.

**Why it wasn't caught.** Both produced perfectly well-formed output. There is no error
condition for "you extracted the wrong paragraph". And the feedback loop was a full day
long: the file was corrupted one evening and the consequence appeared the next morning
as a wrong task list.

**Guardrails.**

- Never write marker strings literally inside the file the parser reads. Format
  documentation lives in a README, not in the data.
- Append after a **unique** anchor (`# Last Session`), never by matching a repeating
  pattern.
- A `PostToolUse` hook that validates the format after every write — see
  `memory-system/hooks/memory-guard.sh`. This is the important one: it turns a
  one-day feedback loop into a one-second one. The session that breaks the file learns
  about it while it is still there to fix.
- Truncation must announce itself. If N of M threads were shown, say so, in the injected
  text.

---

### Mode 2 — the file isn't malformed, it was never written

2026-08-22. A long round ran in a separate session, finished about 80% of the work, 23
commits. The end-of-session memory step was skipped. The handoff file had last been
touched at 16:37; the work continued until 21:04.

The bridge worked flawlessly and presented **finished work as pending**.

**Why it wasn't caught.** The format validator cannot see this. The file is entirely
valid. It is just old. **A guard that checks structure does not check freshness.**

**Guardrails.**

- Compare the bridge's date against today, and say the difference out loud in the
  injected context: *"bridge date: 2026-09-06 (today is 2026-09-08 — 2 days ago).
  There may be unrecorded sessions."*
- A `SessionEnd` hook that leaves a marker when a session did real work (commits exist)
  but wrote nothing to memory. The next session start surfaces it as a warning.
  See `memory-system/hooks/session-end.sh`.
- Note the criterion: **commits, not prompt count.** Prompt count measures conversation;
  commits measure work. A session that talked and changed nothing has nothing to
  remember, and warning about it is noise.

---

### Mode 3 — the memory isn't wrong, it's *early*

2026-08-24. The bridge said a branch was unreviewed and the round was half-finished.
The truth: the work had completed **31 minutes after the memory was written**.

Memory written 21:19. The commit landed at 21:42, the merge at 21:50.

**Why it wasn't caught.** This one defeats both previous guardrails at once. The file is
well-formed, so the validator is clean. The date is yesterday's, so the freshness check
passes. And it is still wrong.

The realization underneath it: **writing the end-of-session note is not the end of the
session.** The note freezes at the moment you *think* you are done, and work continues
past it.

**Guardrail.** Never turn the bridge directly into a task list, even when the date is
current. Run a cheap git check first:

```bash
git log --all --pretty='%h %ci %d %s' -8
git reflog --date=iso -15
```

The reflog shows *when* commits were actually made. Compare that against the memory
block's timestamp and the question "did anything happen after this was written?" closes
in seconds.

The general form, learned over three of these rounds:

> **Git knows the state. Memory knows the decisions.**
> Read decisions from memory. Verify state from the source.

---

### Mode 4 — the stale thing isn't the memory system at all

2026-08-28. A hand-written handoff summary said two directories were uncommitted and
sitting untracked on disk. In fact a commit had included both. The note was written
first, the commit came after, the note was never updated.

Structurally identical to mode 3 — but the source was a manually written summary, and
**the guard never sees that file at all.**

**Guardrail.** Verify the **status claims** of any note you inherit — including one you
wrote yourself. Was it committed, was it pushed, how many commits ahead, is the service
up. These take seconds:

```bash
git show --name-only <sha>
git rev-list --count origin/<branch>..HEAD
```

Trust the **decision** parts of a note. Distrust the **status** parts. That distinction
is the whole lesson of this page, and it applies to every note, not just to memory files
a hook manages.

---

## What this generalizes to

Any persisted note about a system is a claim about a moment that has already passed. The
four modes are the four ways that claim goes wrong:

| Mode | The note is | Detected by |
|---|---|---|
| 1 | malformed | format validator, run on write |
| 2 | missing | freshness check + end-of-session marker |
| 3 | premature | cross-check against git |
| 4 | outside the system | the habit, not the tooling |

Guardrails 1 and 2 are mechanical and belong in code. Guardrails 3 and 4 cannot be
automated, because they require comparing the note against a source of truth that the
note itself does not know about.

Which is the actual conclusion:

> **A memory system can verify its own format. It can never verify its own truth.**
