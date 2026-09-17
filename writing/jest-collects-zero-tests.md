# Jest can collect zero tests and still tell you it passed

*It takes two reasonable decisions to turn a loud bug into a silent one. This is a
walkthrough of a suite that reported success while running nothing at all — what it
actually took to get there, and the guardrail that catches the whole class.*

---

## The report

An agent finished a round of frontend work and wrote:

> All frontend tests pass.

That statement was, narrowly, true. Nothing had failed. Nothing had failed because
nothing had run.

The suite collected **zero test files**, printed a summary that looked like every other
summary, and exited. No red. No warning. No stack trace. The reviewer downstream read
"tests pass." The deploy gate read the exit code. Both were reading an artifact that
described an empty set.

## What it looked like

The giveaway was a single line, and it is easy to scroll past (paths anonymized; the
verbatim output of a clean reproduction is further down):

```
524 files checked.
  testMatch: C:/Users/me/project\.claude/worktrees/x/frontend/src/**/*.{spec,test}.js - 0 matches
  testPathIgnorePatterns: \\node_modules\\ - 1 match
```

Look at the `testMatch` path. Every separator has been normalized to a forward slash —
except one. `project\.claude` kept its backslash. The glob is therefore looking for a
directory literally named `.claude` preceded by an escape, which matches nothing on
disk, so the pattern matches nothing, so zero files are collected.

`524 files checked` reads like work happened. It is the count of files jest *looked at*
and rejected.

## The cause is one line

The whole thing comes down to a single function in `jest-util`, at
`build/replacePathSepForGlob.js`:

```js
function replacePathSepForGlob(path) {
  return path.replace(/\\(?![{}()+?.^$])/g, '/');
}
```

It converts Windows backslashes into forward slashes so the path can be used inside a
glob — but the negative lookahead deliberately *skips* any backslash followed by
`{ } ( ) + ? . ^ $`, because in glob syntax those sequences are escapes and converting
them would change their meaning.

That exception is correct in isolation. It is also exactly what a Windows path
containing a dot-directory looks like. `...\.claude\...` puts a `\` immediately before
a `.`, the lookahead fires, that one separator survives, and the resulting glob is
structurally broken while looking entirely plausible in the output.

The trigger is not a worktree, and it is not `.claude` specifically. It is **any
directory in the path whose name begins with a dot** — or with `{}()+?^$`. Dot-prefixed
tool directories are simply the ones you are most likely to be standing in.

I checked the source in two installed versions:

```
jest-util 27.5.1  →  path.replace(/\\(?![{}()+?.^$])/g, '/')
jest-util 29.7.0  →  path.replace(/\\(?![{}()+?.^$])/g, '/')
```

Byte-identical. This is not an old-version story.

## Minimal reproduction

Two directories, same test file, one difference in the path:

```bash
mkdir -p ".dotdir/proj/__tests__" "plaindir/proj/__tests__"
echo "test('math', () => { expect(1 + 1).toBe(2); });" \
  | tee ".dotdir/proj/__tests__/sample.test.js" \
        "plaindir/proj/__tests__/sample.test.js"
```

Control — a path with no dot-directory:

```
$ jest --rootDir "C:\...\plaindir\proj" --testMatch "<rootDir>/__tests__/**/*.test.js"
Tests:       1 passed, 1 total
exit=0
```

The same command, one directory renamed:

```
$ jest --rootDir "C:\...\.dotdir\proj" --testMatch "<rootDir>/__tests__/**/*.test.js"
  testMatch: C:/.../scratchpad\.dotdir/proj/__tests__/**/*.test.js - 0 matches
exit=1
```

Same file. Same assertion. Zero collected.

## Why `<rootDir>` is in that command

Plain `jest` with default settings does **not** trip this, and that is worth
understanding, because it is why the bug hides in real projects rather than in
minimal ones.

Jest's default `testMatch` is relative (`**/__tests__/**/*.[jt]s?(x)`). A relative glob
never has your absolute path inside it, so there is no separator to mangle.

Frameworks are what put it there. Create React App's generated config, for example:

```js
testMatch: [
  '<rootDir>/src/**/__tests__/**/*.{js,jsx,ts,tsx}',
  '<rootDir>/src/**/*.{spec,test}.{js,jsx,ts,tsx}',
],
```

`<rootDir>` is expanded to the absolute path during config normalization, *then* handed
to the backslash replacement. So the projects most exposed are the ones using a
batteries-included setup — CRA, craco, and anything else that anchors its globs to
`<rootDir>`. The bare tool looks fine; the framework on top of it is where you live.

## It takes a second decision to go silent

Here is the part I got wrong at first, and it is the most useful thing in this post.

The bug above, on its own, is **loud**. Look at the reproduction again: `exit=1`. Jest
says "No tests found" and fails. A CI job would go red. That is a working alarm.

To get an exit code of 0 you need one more ingredient, and it is one almost everybody
has already added for unrelated and perfectly good reasons:

```
$ jest --rootDir "C:\...\.dotdir\proj" --testMatch "<rootDir>/__tests__/**/*.test.js" --passWithNoTests
No tests found, exiting with code 0
exit=0
```

`--passWithNoTests` exists because in a monorepo a package with no tests yet should not
break the build. That is a sound reason. It is also a standing instruction to convert
this specific alarm into a success.

Neither decision is a mistake by itself:

- The lookahead in `replacePathSepForGlob` protects glob escapes.
- `--passWithNoTests` keeps a monorepo green while packages are still empty.

Put them in the same pipeline and they compose into a suite that certifies an empty set.
**Silent failures are usually not one bug. They are two defensible decisions whose
overlap nobody owns.**

## Knowing about it does not help

This is not an undiscovered bug. It is filed as
[jestjs/jest#15132](https://github.com/jestjs/jest/issues/15132), a duplicate of
[#8520](https://github.com/jestjs/jest/issues/8520),
[#9032](https://github.com/jestjs/jest/issues/9032) and
[#9258](https://github.com/jestjs/jest/issues/9258) — open since 2019, reproduced on
29.7.0, still open as of this writing.

And that is the point. Being documented in a tracker does nothing for you at 2am,
because **nothing in your pipeline is looking**. You do not read the `testMatch` line
when the summary is green. Neither does your reviewer, your CI gate, or the agent
writing your commit message.

The structural problem is this:

> **Zero collected looks exactly like zero failing.**

Both print a summary. Both exit 0. The difference is a number nobody is reading.

## The guardrail

Do not gate on the exit code. Gate on the count.

```bash
# How many test files were actually collected?
jest --listTests | wc -l
```

In CI, assert a floor:

```bash
COLLECTED=$(jest --listTests | wc -l)
MINIMUM=40
if [ "$COLLECTED" -lt "$MINIMUM" ]; then
  echo "Collected $COLLECTED test files, expected >= $MINIMUM. Suite did not run."
  exit 1
fi
```

Three notes on making that floor real rather than decorative:

1. **Verify it with a control experiment.** Set `MINIMUM` above your true count and
   confirm the job actually goes red. An untested guardrail is another green light.
2. **Ratchet it.** The floor should move up as the suite grows, otherwise it silently
   stops meaning anything.
3. **Reconsider `--passWithNoTests` per package.** A package that genuinely has no tests
   can keep it. A package with 400 tests should never pass with none.

The reading habit that goes with it is smaller and works today: when a suite comes back
green, find the number. `Tests: N passed`. If the line is missing, or `N` is 0, or `N`
dropped since last week, you have not been told that your code is correct. You have been
told nothing, in a format that resembles good news.

---

> **A green output is not evidence. A number is evidence.**

This entry is part of [silent-failures](https://github.com/Rcpsngl/silent-failures), a
field catalog of the ways AI coding agents and their tooling fail without telling you —
each with the measurement that exposes it and the guardrail that makes it loud.
