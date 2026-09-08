# Multi-agent orchestration

Running several agents against one repository introduces failure modes that have no
single-agent equivalent. All three below produced plausible, confident reports.

---

### 9. Parallel agents in one working copy clobber each other's index

**Symptom.** Two agents worked in parallel in the same directory. Both reported success.
Both sets of commits exist.

2026-08-19. Two agents captured each other's staged changes twice; one of them rewrote
a commit trying to repair it.

**Reality.** `git add` is directory-wide, not agent-scoped. Agent A stages its files;
agent B runs `git add` and picks up A's staged work too; B commits. No code is lost —
which is exactly why it goes unnoticed — but you are left with a history where **commit
messages don't describe their contents**.

**Why it wasn't caught.** Nothing errors. Nothing is missing from the tree. The
corruption is in the *mapping* between message and content, and the only way to see it
is to read a diff against its own message — which nobody does after a green run.

This holds even when the two agents' file sets don't overlap. `git add` doesn't care
whose file it is.

**Guardrail.** Every agent that will run in parallel gets its **own worktree**. In
Claude Code that is `isolation: "worktree"` on the Agent call. A single agent doesn't
need it.

If isolation isn't available, serialize the commits: agents write, the coordinator
stages and commits, one at a time.

Audit afterwards:

```bash
git log --oneline --stat -10        # does each message match its own diff?
```

---

### 10. Polling a running subagent costs more than the work

**Symptom.** The coordinator starts a subagent, then loops:
`git status` → "Waiting." → `git log` → "Waiting." → `TaskOutput` → "Waiting."

2026-09-01: one turn spun for **42 minutes** and burned roughly **247k tokens**.
Nothing was wrong. The subagent was working the whole time.

**Reality.** The harness already wakes the coordinator when a subagent finishes. Every
poll was pure overhead — and each one re-sent the entire context.

**Why it wasn't caught.** Because it looks like diligence. The transcript reads as an
attentive supervisor checking on progress. There is no error, no failure, and the work
does eventually complete correctly. The only casualty is money and wall-clock time, and
neither shows up in the output.

This is the one entry here where the silent thing is **cost**, not correctness. It
belongs in the same family: an expense you never priced, multiplied by a loop count you
never counted.

**Guardrail.**

- **Waiting means ending your turn.** Start the subagents, write one sentence, stop.
  Call no tools until the notification arrives.
- **Never poll.** Not `git log`, not `git status`, not `TaskOutput`. Writing "waiting"
  and then calling a tool is not waiting; it is a loop.
- **Start independent subagents in a single message.** Launching them one at a time and
  waiting for each multiplies the number of wake-ups.

Cost comes from **how many times you wake up**, not from how much you write. This applies
to any periodic check you're tempted to add — see also
[#14](tooling.md#14-a-cheap-looking-periodic-measurement-burns-a-core), which is the
same mistake at the infrastructure layer.

---

### 11. An absence verdict from a single file

**Symptom.** An instruction written for another agent stated, flatly: *"this project
uses no custom fonts, system font only — do not add fonts this round."* The evidence was
a search for `useFonts|loadAsync|expo-font` in the app's root layout, which came back
empty.

2026-08-27.

**Reality.** Two custom fonts were already loaded — from a different file. The agent
executing the instruction worked from a false premise for the entire round.

**Why it wasn't caught.** An empty search result is genuinely ambiguous, and the
ambiguity resolves the wrong way by default. Finding something is evidence about the
codebase. *Not* finding something is evidence about **where you looked**.

The compounding problem is specific to multi-agent work: once an absence verdict is
written into an instruction and handed to someone else, it stops being a claim and
becomes a premise. The recipient does not re-derive it. It propagates.

**Guardrail.** Before asserting that something does not exist:

```bash
grep -rn "<pattern>" .            # the whole repo, not the file you had open
cat package.json requirements.txt # if it could be a dependency, check the manifest
```

Both steps are mandatory if the verdict is going into an instruction or a report. If
you can't do both, soften the language — *"I didn't find it where I looked; verify"* —
and never state it as fact. A hedge costs one clause. A wrong premise costs a round.

---

## Two more rules, without incidents attached

These are not silent failures; they are the coordination rules that prevent them.
They live here because they're the other half of the same practice.

**Delegate per file, never per finding.** When a round produces many findings, group
them by the file they touch and open one agent per group. Two agents must never enter
the same file: each rebuilds context from scratch, reads the same 2000-line file cold,
and the second overwrites the first. Parallelism is bounded by file-set disjointness,
not by finding count.

The exception is worth stating: a second round triggered by a *reviewer or tester*
finding the first fix incomplete is not waste. That round closes a real gap. What you
cut is duplicated delegation, not verification.

**Scope lock.** The list you were given is the entire scope. An agent that notices an
unrelated problem reports it **as prose at the end**, never as code. The single
exception is the same bug's copy in another file — that is in scope, but gets its own
commit and an explicit "out of scope, same bug class" label.

At the end of a round, check `git status`. Uncommitted changes you did not create are
someone else's work in progress: don't touch them, ask.
