# The catalog

Fifteen confirmed silent failures. Each one exited `0`, produced a plausible result,
and surfaced later somewhere unrelated.

## Index

| # | Failure | Domain |
|---|---|---|
| 1 | [Jest collects zero tests and exits successfully](tests.md#1-jest-collects-zero-tests-and-exits-successfully) | Tests |
| 2 | [Tests skipped for an unmet precondition, suite still green](tests.md#2-tests-skipped-for-an-unmet-precondition-suite-still-green) | Tests |
| 3 | [Wall-clock assertions go red as the suite grows](tests.md#3-wall-clock-assertions-go-red-as-the-suite-grows) | Tests |
| 4 | [The dev server never reloaded your fix](tests.md#4-the-dev-server-never-reloaded-your-fix) | Tests |
| 5 | [`git worktree remove` empties the main repo through a junction](git-and-worktrees.md#5-git-worktree-remove-empties-the-main-repo-through-a-junction) | Git |
| 6 | [`git stash` in a shared working copy swallows other people's work](git-and-worktrees.md#6-git-stash-in-a-shared-working-copy-swallows-other-peoples-work) | Git |
| 7 | [A failed `git checkout` silently produces the wrong base](git-and-worktrees.md#7-a-failed-git-checkout-silently-produces-the-wrong-base) | Git |
| 8 | [`--merged` answers a different question than the one you asked](git-and-worktrees.md#8---merged-answers-a-different-question-than-the-one-you-asked) | Git |
| 15 | [A worktree isolates the code, not the database](git-and-worktrees.md#15-a-worktree-isolates-the-code-not-the-database) | Git |
| 9 | [Parallel agents in one working copy clobber each other's index](agents.md#9-parallel-agents-in-one-working-copy-clobber-each-others-index) | Agents |
| 10 | [Polling a running subagent costs more than the work](agents.md#10-polling-a-running-subagent-costs-more-than-the-work) | Agents |
| 11 | [An absence verdict from a single file](agents.md#11-an-absence-verdict-from-a-single-file) | Agents |
| 12 | [A quoted heredoc collapses backslashes in the script it writes](tooling.md#12-a-quoted-heredoc-collapses-backslashes-in-the-script-it-writes) | Tooling |
| 13 | [`ProtectHome=yes` makes a running service look stopped](tooling.md#13-protecthomeyes-makes-a-running-service-look-stopped) | Tooling |
| 14 | [A cheap-looking periodic measurement burns a core](tooling.md#14-a-cheap-looking-periodic-measurement-burns-a-core) | Tooling |
| + | [Four ways a session-memory bridge goes stale](memory.md) | Memory |

## The format

Every entry has four beats, in this order:

**Symptom** — the reassuring output, quoted exactly.
**Reality** — what was actually happening.
**Why it wasn't caught** — the mechanism of the silence. This is the part that generalizes.
**Guardrail** — a command or a rule. Never "be careful".

## Reading the third beat

If you only read one section per entry, read *Why it wasn't caught*. The specific tools
here will change; some of these bugs will be fixed. The reasons failures stay invisible
do not change:

- **A negative result and an unasked question look identical.** Zero tests collected and
  zero tests failing print nearly the same thing. An empty `grep` means "not here", never
  "not anywhere". `--merged` returning nothing is an answer to a question you didn't ask.
- **Hardening and isolation close read paths, and most tools read "closed" as "empty".**
  Sandboxes, `Protect*` directives, containers.
- **Layers that transform text on the way through.** Heredocs, line endings, glob
  escaping. Syntax stays valid; meaning does not.
- **Anything that measures time or resource use measures the machine, not the code.**
- **A memory of a state is not the state.** Notes, bridges, handoff summaries — all
  freeze at the moment of writing and keep sounding current afterwards.
