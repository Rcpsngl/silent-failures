# Silent Failures

**A field catalog of the ways AI coding agents fail without telling you — and the guardrails that make them loud.**

Most agent tooling advice is about making agents *do more*. This repository is about
the opposite problem, which nobody writes down: agents routinely report success while
having accomplished nothing, and the tools they run cooperate by exiting `0`.

Every entry here was found the hard way, in production work, over roughly a year of
running Claude Code as the primary development surface across a Python/FastAPI backend,
a React web app, an Expo mobile app, and a small fleet of Linux servers.

---

## The failure class

A **silent failure** has all three of these properties:

1. **No error.** Exit code 0. No stack trace. No red.
2. **A plausible-looking result.** Green test suite, "Successfully resized", `HTTP 200`,
   `worktree removed`, a confident agent report.
3. **A delayed, misattributed symptom.** The damage surfaces hours or days later,
   somewhere unrelated, and you debug the wrong thing.

Property 3 is what makes this class expensive. A loud failure costs you the fix.
A silent failure costs you the fix *plus* every hour spent looking in the wrong place.

Confirmed members so far:

| Tool | Says | Actually |
|---|---|---|
| Jest on a path containing a dot-directory | `0 matches`, exits **0** | Collected zero tests |
| pytest with an unmet precondition | Suite green | Silently skipped the tests that mattered |
| `uvicorn --reload` | Running | Serving the pre-edit code |
| `git worktree remove --force` | `worktree removed` | Emptied the *main* repo's `node_modules` |
| `git branch --merged` | Empty | Answered a different question than you asked |
| `pm2 jlist` under `ProtectHome=yes` | `[]` | Can't read `/root/.pm2`; service is up |
| Browser `resize_window` on a maximized window | `Successfully resized` | Viewport unchanged |
| A quoted heredoc writing a shell script | `bash -n` clean | Backslashes collapsed; behavior changed |
| A session-memory hook | Injects "last session" | Injects a *day-old* session |
| An agent | "Done, all tests pass" | Ran the tests in a directory with no tests |
| An unset `APP_ENV` | Nothing | Every guard behind it stayed permissive |
| One DNS resolver | "Records are correct" | The old nameserver was still answering everyone else |

---

## The one rule

> **A green output is not evidence. A number is evidence.**

Tests *collected*. Rows *returned*. Records *written*. Packages *present*.
Every guardrail in this repository is a mechanical restatement of that rule for
one specific tool.

The corollary matters just as much:

> **When a fix appears to have no effect, suspect the tool before the code.**

The single most expensive debugging session behind this repo was a correct fix that
appeared not to work, because the process serving it had never reloaded. Hours went
into re-reading logic that was right the whole time.

---

## What's in here

### [`catalog/`](catalog/) — the failure modes

Eighteen documented silent failures, grouped by domain, each in a fixed format:
**Symptom → Reality → Why it wasn't caught → Guardrail.** Root causes are traced to
actual source where it was possible to trace them (the Jest one bottoms out in a
regex in `jest-util`).

- [Tests and test suites](catalog/tests.md) — the false-green family
- [Git, worktrees, and parallel work](catalog/git-and-worktrees.md)
- [Multi-agent orchestration](catalog/agents.md)
- [Tooling, environments, and servers](catalog/tooling.md)
- [Configuration and data](catalog/config-and-data.md)
- [Session memory](catalog/memory.md)

### [`memory-system/`](memory-system/) — cross-session memory that fails loudly

A working set of Claude Code hooks that carry context between sessions, plus the
validator that exists because this system silently served a day-old session bridge
one morning and the day started with the wrong task list.

The interesting part is not the memory. It's `validate_memory()` — the format checker
that turned a one-day feedback loop into a one-second one.

### [`orchestration/`](orchestration/) — running a team of agents without corrupting your repo

The coordination rules, each attached to the incident that produced it:

- **Never poll a running subagent.** One turn of `tool call → "waiting…" → tool call`
  burned 42 minutes and ~247k tokens. Cost scales with *how many times you wake up*,
  not how much you write.
- **Delegate per file, not per finding.** Two agents in the same file re-read it cold
  and overwrite each other.
- **Parallel agents get separate worktrees.** `git add` is directory-wide; two agents
  committing in one working copy clobber each other's index and you end up with a
  history where messages don't match contents.
- **Branch from `origin/<target>`, and verify the base before the first commit.**
  A failed `git checkout` leaves you on whatever branch you were already on, and the
  work continues from the wrong base without a word.
- **Scope lock.** The list you were given is the entire scope. Extra problems get
  reported as prose, not fixed as code.

Also: [how to write a skill that doesn't rot](orchestration/writing-skills.md) —
the short version is that skills must contain *traps*, never *state*.

---

## How to use this

Two ways, roughly:

**As a reading.** Skim the catalog. If you run agents on real work, you have hit at
least four of these and attributed at least one of them to something else. The entries
are written to be recognizable, not merely correct.

**As code.** The hooks in `memory-system/hooks/` run as-is on Claude Code (Windows/Git
Bash and POSIX both — no `jq`, no `python`). Copy them, point them at a directory,
adjust the markers.

---

## What this is not

Not a prompt collection. Not an "awesome list". Not a dotfiles dump.
There is no configuration here that will make your agent smarter — only checks that
make it stop lying to you about what it did.

---

## Provenance

Written by [Recep Şengül](https://github.com/Rcpsngl). Every incident is real and
dated. Project-specific details — repository names, hostnames, business logic, client
data — have been removed; the mechanisms and the reasoning are intact.

Corrections and additions welcome, especially new confirmed members of the family.
See [CONTRIBUTING.md](CONTRIBUTING.md).

MIT licensed.
