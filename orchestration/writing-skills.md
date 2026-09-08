# Writing a skill that doesn't rot

A *skill* — a reusable procedure an agent loads on demand — is worth writing only if it
captures something a transcript wouldn't. This page is the checklist that produced the
useful ones and rejected the rest.

---

## The principle

**Capture the trap, not the commands.**

Commands are already in your shell history. What makes a procedure worth writing down is
the thing that was learned painfully. Two real examples, verbatim from working skills:

> *"Use `backend/venv`, not the root `venv/` — the root one is missing `jinja2` and
> collection blows up."*

> *"The suite is red at baseline — read the test NAMES, not the count."*

Without lines like those, a skill is a document you could have regenerated. With them,
it is the reason you don't walk into the same wall twice.

---

## Is this worth a skill?

At least **two** must hold:

- [ ] The procedure has been run before, or will clearly be run again
- [ ] At least one trap surfaced along the way (a wrong path, a missing precondition, a
      misleading output)
- [ ] **Order matters** — doing the steps out of sequence causes damage
- [ ] There is a verification step (how do we know it worked?)

If none hold, **don't write one.** An unnecessary skill is not neutral: it loads, it
consumes context, and one day it applies stale instructions. Two lines in `CLAUDE.md`
are the right size for a one-off.

---

## What goes in

Pull these out of the session, in this order of value:

- **Traps.** The largest section. Wrong turns, missing preconditions, misleading output.
- **Preconditions.** What had to be running (a database, a server, a virtualenv, network)
  and how to check.
- **Baseline.** What "normal" looks like. *"The suite is already 22 red, don't panic"* is
  worth more than a page of correct instructions.
- **Verification.** How we knew it worked. Not the exit code — the number.
- **What not to do.** Paths that were tried and abandoned, **and why**.

That last one is the most skipped and the most valuable. Without it, the next session
walks down the same dead end and rediscovers it at full price.

---

## Prohibitions

**1. No state.** Commit hashes, branch names, "we're on phase 3", test counts. These go
stale and the skill starts issuing confident wrong instructions. Things that don't change
(a file path, a command, a server address) go in; things that change get replaced with
*"check with `git log`"*.

The test: **will this still be true in a week?**

**2. Nothing written without approval.** Show the draft — name, scope, trigger phrases,
the list of traps as headings — and ask. No exceptions. This one was a deliberate
decision: an earlier proposal for an automatic skill/memory writer was rejected, because
plausible auto-generated content gets trusted precisely because nobody remembers writing
it.

**3. No invented commands.** Only commands that actually ran and actually worked. If a
step was never verified, mark it *"unverified"* rather than presenting it as procedure.

**4. Don't restate `CLAUDE.md`.** Reference it in one line.

**5. Don't pad.** Past ~200 lines it is usually two skills, or half of it is filler.

---

## The description field is the trigger

The model selects a skill by reading its description. Write it with **the phrases the
user actually says**, not your own terminology:

> *"Use when the user says 'ship it', 'deploy', 'push to prod', 'put it on the server'."*

Not:

> *"Handles production deployment orchestration."*

The second is a better sentence and a worse trigger.

---

## Body shape

```markdown
# <Title>

<One sentence: what job, which repo or server.>

## Preconditions
<What must be running, and how to check it.>

## Steps
### 1. <name>
```bash
<a command that actually ran>
```
⚠️ **<trap>** — <one sentence of reasoning>

## Expected output / baseline
<What normal looks like. Call out misleading green or red here.>

## Verification
<How we know it worked. A number, not a color.>

## Don't
<Paths tried and abandoned, with reasons.>
```

---

## Verify after writing

Check that the frontmatter actually closes:

```bash
awk 'NR==1 && !/^---$/ { print "ERROR: line 1 is not ---"; exit }
     NR>1 && /^---$/   { print "frontmatter closes at line " NR; exit }' SKILL.md
```

⚠️ **Do not count with `grep -c '^---$'`.** Horizontal rules in the body are also `---`,
so the count always exceeds 2 and the check raises a false alarm. It counted 11 once — on
the skill that documents this. Look only at the **first** pair.

If the skill doesn't appear in the list, check in order: directory name ≠ `name:` in the
frontmatter, the frontmatter doesn't close, the file isn't named `SKILL.md`.

---

## Updating an existing skill

Same flow, but read it first and **show the diff**.

When a skill goes stale — the command changed, the path moved, the trap was fixed
upstream — **correct it, don't delete it.** A deleted trap gets rediscovered at full
price.

When you remove a step, write one line saying why. Otherwise the next session reads it as
an omission and puts it back.
