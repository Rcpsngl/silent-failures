# Orchestration

Rules for running a team of agents against one repository without corrupting it.
Every one of them is here because something went wrong first.

- [`coordinator.md`](coordinator.md) — a coordinator agent definition you can adapt,
  with the reasoning attached to each rule
- [`writing-skills.md`](writing-skills.md) — how to write a reusable procedure that
  doesn't rot

---

## The five rules

**1. Parallel agents get separate worktrees.**
`git add` is directory-wide. Two agents committing in one working copy capture each
other's staged files and you end up with a history where messages don't describe their
contents — no code lost, which is exactly why nobody notices.
[Incident](../catalog/agents.md#9-parallel-agents-in-one-working-copy-clobber-each-others-index)

**2. Never poll a running subagent.**
The harness wakes you when it finishes. One turn of `tool call → "waiting…" → tool call`
ran 42 minutes and ~247k tokens. Cost scales with **how many times you wake up**, not
with how much you write. Waiting means ending your turn.
[Incident](../catalog/agents.md#10-polling-a-running-subagent-costs-more-than-the-work)

**3. Delegate per file, never per finding.**
Group findings by the file they touch, one agent per group. Two agents in the same file
each read it cold and the second overwrites the first. Parallelism is bounded by file-set
disjointness, not finding count.

**4. Branch from `origin/<target>` and verify the base before the first commit.**
A `git checkout` that fails — because the branch is locked in another worktree — leaves
you where you already were, and everything after it succeeds from the wrong base.
[Incident](../catalog/git-and-worktrees.md#7-a-failed-git-checkout-silently-produces-the-wrong-base)

**5. Scope lock.**
The list you were given is the whole scope. Extra problems are reported as prose, not
fixed as code. The one exception is the same bug's copy in another file — in scope, but
its own commit, labeled.

---

## The rule underneath all five

> **An agent reporting "done" is a claim, not a result.**

A coordinator's job is not to relay reports. It is to check them. `git log`, `git status`,
the test count, the diff — cheap, seconds, and the only thing standing between a
confident summary and a wrong one.

This is also why the coordinator should not do the work itself. An agent that both
implements and verifies has no independent view of its own output, and the verification
collapses into a restatement.

---

## On memory candidates

A coordinator that ends every round with a list of things worth remembering is useful.
One that *writes* them is not.

The rule that came out of this: **the coordinator proposes, the human approves.** No
memory file is created or updated without explicit approval. An automatic memory writer
produces plausible entries nobody vetted, and a wrong memory outlives a missing one —
it gets trusted for years.

Only two classes qualify as candidates:

| Class | What it is |
|---|---|
| **decision** | A path was chosen and an alternative eliminated — *with the reason* |
| **trap** | A behavior that silently produces wrong results, plus its root cause |

And one class is permanently disqualified: **state.** Branch names, commit hashes, test
counts, "phase 3 is done", "feature X doesn't exist yet". Git already tracks these, and
in memory they become false at the next commit.

The test is one question:

> **Will this sentence still be true in a week?**

If no, it is not a candidate. And when a round produces nothing worth keeping — which is
most rounds — the correct output is *"nothing memorable this round"*. Never fill the
section to have filled it. A fabricated candidate is far more expensive than a missed
one: it gets approved, written, and then misleads for years.
