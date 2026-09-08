# Tests and test suites — the false-green family

Four ways a suite tells you it passed when it never ran the thing you cared about.

These are the most dangerous entries in the catalog, because a green suite is the
artifact everyone downstream trusts. A reviewer reads "tests pass". A deploy gate reads
the exit code. An agent writes "all tests pass" in its report and it is, narrowly, true.

---

### 1. Jest collects zero tests and exits successfully

**Symptom.** `yarn test` prints `524 files checked, 0 matches` and exits `0`.
No red, no warning. In an agent report this becomes "frontend tests pass".

Found 2026-08-24, running a suite from inside `.claude/worktrees/<name>/frontend`.

**Reality.** Jest collected zero test files. The suite did not run.

**Why it wasn't caught.** Traced to source — `jest-util/build/replacePathSepForGlob.js`:

```js
path.replace(/\\(?![{}()+?.^$])/g, '/')
```

It converts backslashes to forward slashes for globbing, *except* when the next
character is one of `{ } ( ) + ? . ^ $`, which it treats as a glob escape. A Windows
path containing `...\.claude\...` hits that exception exactly: every other separator
becomes `/`, that one stays `\.`, and the resulting glob matches nothing.

The trap is **not** specific to worktrees. The trigger is any directory in `rootDir`
whose name starts with a dot — or with `{}()+?^$`. `.claude/worktrees/` is just the
one you'll meet first.

And zero-collected looks almost exactly like zero-failing.

**Guardrail.**

```bash
# Gate on the count, not the exit code.
yarn test --listTests | wc -l          # how many files were actually collected?
```

Read the `Tests:` line. If it is absent or says 0, the suite did not run — do not
record a pass. In CI, add a floor: if collected tests fall below a known minimum, exit
non-zero. Verify the floor with a control experiment (set it above the real count and
confirm the command actually goes red).

Avoidance: run frontend tests from the main checkout, not from a worktree under a
dot-directory.

---

### 2. Tests skipped for an unmet precondition, suite still green

**Symptom.** `python -m pytest` — green. "No new failures."

**Reality.** Two separate populations of tests never executed:

- 27 integration tests requiring a live HTTP server, `pytest.skip`-ed because no server
  was running. These were the tests that proved a set of correctness fixes.
- 6 tests importing `mongomock`, which was never added to `requirements.txt` and is not
  installed in the canonical virtualenv. Skipped on every run, for months, while
  "regression clean" was being reported on their behalf.

**Why it wasn't caught.** `pytest` prints skips in a summary line most people scan past,
and *no new failures* is not the same claim as *the same tests ran*. Skip counts drift
silently because nothing forces you to justify a change in them. Three independent
sources produce them — an unavailable service, an env flag, and a missing dependency —
and only the third leaves any trace in the repo at all.

There is a nastier variant. When the integration tests *were* finally run without
propagating the same `JWT_SECRET` to both the server and the pytest process, they failed
with `401`. That looks exactly like a bug in the auth code. It cost a full debugging
round before the cause turned out to be the environment.

**Guardrail.**

```bash
pytest -q -rs        # -rs prints the reason for every skip
```

Read the skip count as carefully as the failure count. If it changed, find out why
before you record a pass. When a suite depends on a service, assert the precondition
and **fail** rather than skip — a skipped test is a test whose absence you have agreed
in advance not to notice.

Corollary: when integration tests fail on auth, check that both processes share the
same secret before you touch the auth code.

---

### 3. Wall-clock assertions go red as the suite grows

**Symptom.** An untouched test starts failing. Regex unchanged, data unchanged, code
unchanged. A ReDoS test with a 5000 ms budget measured 7129 ms.

The trigger, 2026-08-21: dead suites were revived, so the total test count went
816 → 904, and jest ran more workers in parallel.

**Reality.** The threshold was measuring machine load, not the property under test.

**Why it wasn't caught.** Because it *did* go red — but for a reason with no relationship
to the assertion, which is its own kind of silence. The suite is now lying in both
directions: it just produced a false red, and a real regression hiding under a generous
threshold would produce a false green that nobody would ever see.

**"Make it load-independent by asserting a growth ratio instead" does not fix it.**
This was measured, not assumed: doubling the input size grew runtime ~3.3x unloaded and
**21x** under full suite parallelism. The cause isn't algorithmic — 183K-character
strings processed across 16 workers hit memory and GC pressure that penalizes the large
measurement disproportionately. The load effect is not proportional, so the ratio is
not load-resistant either.

**Guardrail.** Ask what the test actually asserts. For ReDoS the claim is
*"not exponential"*, and exponential blowup takes minutes, not milliseconds — so the
right fix was to raise the thresholds crudely (500 → 5000 ms, 5000 → 30000 ms, plus an
explicit jest timeout, since jest's 5 s default would kill the measurement before it
finished).

Prefer an assertion that doesn't involve a clock: operation counts, complexity bounds,
a hard timeout that only trips on a real hang.

Verify stability across **consecutive** runs, not one. Six full runs were needed here;
a version that came back green three times in a row went red on the fourth.

---

### 4. The dev server never reloaded your fix

**Symptom.** The fix is correct. The behavior does not change. So you go back and
re-read your logic.

2026-08-25. The lost time was entirely spent looking in the wrong place.

**Reality.** `uvicorn --reload` had not picked up the change. The old code was still
being served.

**Why it wasn't caught.** Nothing failed. The process was up, the endpoint answered,
the response was merely stale. Trust in the tool exceeded trust in the thing it measured.

Same family, different layer: after a `node_modules` directory was emptied underneath a
running dev server, the server kept answering `HTTP 200` while printing
`Module not found` for absolute paths that existed on disk. What was dead was not the
tree on disk — it was that process's in-memory module graph. `HTTP 200` is not a health
check.

**Guardrail.** When a fix appears to have no effect, **suspect the tool first, the code
second.**

1. Restart the process. Do this before re-reading a single line.
2. Prove the running code is the code you edited — a log line, a version string, a
   deliberate syntax error that *should* crash it.
3. Compare the process start time against the moment you edited:

```bash
ps -o lstart= -p <pid>
```

If it started before your edit, the process is stale and everything it tells you is
about the old code.

---

## The rule these four share

> Green output is not coverage. **The count is the evidence.**

Tests collected. Skips explained. Runs repeated. Process restarted. Each entry above is
that one sentence, specialized to a tool.
