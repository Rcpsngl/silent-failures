# Git, worktrees, and parallel work

Git is unusually good at reporting errors and unusually bad at telling you it did the
wrong correct thing. Every entry here is a command that succeeded.

---

### 5. `git worktree remove` empties the main repo through a junction

**Symptom.** `git worktree remove --force` reports success. Minutes later, in a
*different* checkout that you did not touch, `'craco' is not recognized`.

Triggered four times across 2026-08-24 and 08-25 before the pattern was understood.

**Reality.** The worktree's `frontend/node_modules` was not a copy. It was a Windows
junction pointing at the **main** repository's `node_modules`. The removal followed the
link and emptied the target: 946 packages → 0.

**Why it wasn't caught.** Four compounding reasons:

- `git status` is clean, because `node_modules` is gitignored. The dependency of the
  worktree on the main tree is invisible to git.
- Git reports the worktree as successfully removed. From its point of view, it was.
- The directory still **exists** — it is merely empty — so it does not look deleted.
- The symptom is delayed and appears in an unrelated checkout, so the first instinct is
  to blame whatever you were doing at the time.

The deleting-tool list is not limited to `rm -rf`. **Any deletion tool that follows the
junction is in this class**, `git worktree remove --force` included.

Why junctions get created at all: a real copy is ~1 GB and takes minutes, so tooling
quietly reaches for the link.

**Guardrail.**

```bash
ls -la <worktree>/frontend/node_modules      # link, or directory?
```

Correct order when tearing a worktree down:

1. Remove the **link** first — `rmdir` / `cmd //c rmdir`, never `rm -rf`.
2. Verify the main repo's package count against a known-good number.
3. *Then* `git worktree remove`.

Repair is not finished when `yarn install` returns. A dev server that was running during
the deletion survives with a poisoned module graph and a poisoned cache. Full repair:
`yarn install` → **kill the old process** → `rm -rf node_modules/.cache` → restart.
The first build after that is cold and slow; that is expected.

---

### 6. `git stash` in a shared working copy swallows other people's work

**Symptom.** A bare `git stash`, run to clear the decks. It succeeds.

**Reality.** It captured six files of *uncommitted work belonging to other agents*
running in the same working copy. The later `git stash pop` hit a conflict, aborted, and
the files were gone until they were recovered by hand.

**Why it wasn't caught.** `git stash` operates on the **working tree**, not on your
changes. There is no notion of "mine". Everyone's uncommitted work goes into a single
stash entry, and if the pop conflicts, all of it is suspended at once.

`git checkout -- .` and `git reset --hard` carry the identical risk for the identical
reason.

**Guardrail.** In any working copy where more than one process might be writing, these
three are banned outright:

```
git stash          (bare)
git checkout -- .
git reset --hard
```

Use path-scoped forms (`git stash push -- <path>`) or just commit. State the ban
explicitly in agent prompts — an agent will not infer it.

And do not trust a recovery report. Verify:

```bash
git stash list
git diff --stat            # are the expected changes actually back in the files?
```

---

### 7. A failed `git checkout` silently produces the wrong base

**Symptom.** The branch was created. Commits landed. Everything succeeded.

**Reality.** `git checkout <branch>` failed — the target branch was checked out in
another worktree and therefore locked. The work continued from the tip of whatever
branch was already checked out. The new branch was based two files behind its intended
base.

2026-08-19. Caught by review, not by tooling. The same wrong-base trap had previously
carried a regression into production.

**Why it wasn't caught.** The checkout error scrolls past in a long transcript, and
every command *after* it succeeds. Nothing downstream re-asks "am I where I think I am?"
The commits are real, the diff is real; only the base is wrong, and the base is the one
thing nobody prints.

**Guardrail.** Never branch from your current position. Branch from the remote, and
verify the base **before the first commit**:

```bash
git fetch
git checkout -b <new> origin/<target>
git merge-base --is-ancestor origin/<target> HEAD || echo "WRONG BASE — stop"
```

If it cannot be verified, stop and ask. Do not commit.

---

### 8. `--merged` answers a different question than the one you asked

**Symptom.** Eight dead artifact branches to clean up. `git branch --merged <main-dev>`
lists **none** of them. Read literally: "not merged, don't delete."

**Reality.** All eight pointed at the same commit, which was reachable from another
living branch and from its remote. Deleting them would have dropped nothing.

**Why it wasn't caught.** The empty output *was* a correct answer. The question was
wrong. `--merged <branch>` asks only "is this an ancestor of that one branch". In a repo
where more than one line of history is alive, it misleads in both directions: it
preserves branches that are perfectly reachable elsewhere, and it can wave through a
branch that exists nowhere else.

**Guardrail.** The right question is **reachability**, not merged-ness:

```bash
git branch -a --contains <branch>            # what else contains this commit?
git merge-base --is-ancestor <sha> main && echo "lives on main"
git ls-remote --heads origin | grep <sha>    # does it exist on the remote?
```

If at least one **living ref other than the branch itself** contains the commit —
especially an `origin/*` — `git branch -D` is safe. If not, don't delete; establish
separately that those commits are genuinely unwanted.

---

### 15. A worktree isolates the code, not the database

**Symptom.** Two agents working in parallel, one in the main checkout and one in a
separate worktree. "We used separate worktrees" was treated as proof of isolation. The
verification run came back green.

2026-08-18.

**Reality.** Both runs used the **same test database**. A worktree isolates the *working
tree*; the database name came from the environment, which both inherited. The green
result was luck. Had the runs collided, the outcome would have been meaningless — and
nothing would have indicated it.

**Why it wasn't caught.** Because the isolation was real, just narrower than assumed.
Worktrees solve file contention so completely that they get treated as general-purpose
isolation, and nobody re-asks what else is shared. Test fixtures that clean up with broad
`delete_many` calls will happily delete another run's rows, and the resulting pass or
fail carries no information either way.

**Guardrail.** Before running database-backed tests in a worktree, check whether another
run is live. If it might be, give the run its own database:

```bash
DB_NAME=app_test_wt2 pytest tests/
```

More generally, when you isolate something, enumerate what is still shared: the database,
the cache, the ports, `node_modules`, the dev server, temp directories, the package
registry. A worktree covers exactly one of those.

---

## The rule these five share

> A git command returning success means the command ran. It says nothing about whether
> it did what you wanted.

Before a destructive git operation, ask what the command actually operates on: the
working tree (`stash`), the link target (`worktree remove`), one line of ancestry
(`--merged`), or your current position (`checkout`). Four of the five failures above are
cases where that scope was wider or narrower than assumed — and the fifth is the same
mistake about a worktree.
