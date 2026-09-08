# Tooling, environments, and servers

Three failures where the layer between you and the machine changed the meaning of what
passed through it.

---

### 12. A quoted heredoc collapses backslashes in the script it writes

**Symptom.** A shell function written into a file via `<<'EOF'`. `bash -n` passes.
The function runs. Exit code 0. The JSON it produces even parses.

2026-08-28, writing a `json_escape` helper for a hook.

**Reality.** Backslashes collapsed on the way in. All five lines of the function were
corrupted. The worst one:

```
written : s=${s//\\/\\\\}      # double the backslash (JSON escape)
on disk : s=${s//\/\\}         # convert SLASH to backslash  ← entirely different job
```

The function no longer escaped anything. It rewrote path separators. Injected file paths
silently turned from `/c/Users/...` into `\c\Users\...`, and newlines vanished.

**Why it wasn't caught.** This is the textbook case. A quoted heredoc is supposed to be
literal, so the corruption is invisible at the source level. Syntax stays **valid**, so
`bash -n` is clean. The function still *works*, in the sense of running and returning 0.
Only the content is wrong — and content errors in an escaping function surface as
mangled text in some downstream consumer, weeks later, if ever.

**Guardrail.**

1. **Don't write escape-heavy files through a heredoc.** Use a file-writing tool that
   doesn't add a shell layer. This is the actual fix.
2. If you already did, verify at byte level — reading it back with your eyes is not
   enough, you have to count:

   ```bash
   sed -n '/^json_escape/,/^}/p' file.sh | cat -A
   ```

3. Better: run it against a known input.

   ```bash
   ( . file.sh; json_escape "$(printf 'path: /a/b\nline2')" )
   ```

   Are the `/` and the newline still intact in the output?

4. If a working version already exists somewhere, copy the block file-to-file
   (`sed -n '/^name/,/^}/p' source.sh`) rather than retyping it through a shell.

Same family, different layer: **writing a file with Python on Windows converts every
`\n` to `\r\n`.** `git diff` looks clean, because git normalizes to LF in the index —
only the *working copy* is corrupted. It surfaces as a test that reads source text and
searches for a literal `\n` pattern, failing for reasons unrelated to your change.
Fix: `io.open(p, 'w', encoding='utf-8', newline='')`, or write bytes.

---

### 13. `ProtectHome=yes` makes a running service look stopped

**Symptom.** A monitoring dashboard showed `api-worker` as **stopped**. It had been
running without interruption for 118 days.

2026-09-03.

**Reality.** The collector unit had `ProtectHome=yes`. `pm2` keeps its state socket
under `/root/.pm2`, which that directive makes unreachable, so `pm2 jlist` returned an
**empty list without erroring**.

**Why it wasn't caught.** Nothing failed. The collector didn't error, nothing landed in
the journal, the exit code was fine, and the systemd unit was `active`. An empty list is
a perfectly well-formed answer, and "no processes" is a plausible thing for a process
manager to say.

The general shape: **hardening directives close read paths, and most tools interpret
"can't read" as "nothing there."** Same class — `ProtectHome` plus `~/.docker`,
`ProtectSystem=strict` plus sockets under `/etc`.

**Guardrail.** After adding any `Protect*` or `ReadWritePaths` directive, verify the
output **against an independent source**. A unit being `active` says nothing about
whether its output is correct:

```bash
systemctl show <unit> -p ProtectHome -p ProtectSystem -p ReadWritePaths
sudo -u root pm2 list        # compare against what the collector reports
```

A unit that reads `pm2` needs `ProtectHome=no`. To restrict the write surface instead,
`ProtectSystem=strict` plus explicit `ReadWritePaths` is sufficient and doesn't blind
the reader.

---

### 14. A cheap-looking periodic measurement burns a core

**Symptom.** Server CPU drifted from ~7% to ~30% after a monitoring dashboard was
installed. The hot thread was spinning in `futex(FUTEX_WAIT)` — user space, not syscalls.

2026-09-03.

**Reality.** `docker stats --no-stream`, called every 20 seconds, was costing `dockerd`
a **full core**. Measured with a control experiment rather than guessed:

| Collector | `dockerd` CPU |
|---|---|
| on | **103%** (one full core) |
| off | 0.13% · 0.33% |

**Why it wasn't caught.** Periodic measurement code reads as trivial — one short command
on a timer. Its per-call cost is assumed rather than measured. But every 20 seconds is
**4320 times a day**, so an unmeasured per-call cost arrives multiplied by that factor.
The load was real and visible in production; it took the dashboard itself to find it.

**Guardrail.** Before putting anything on a timer or in cron, **measure one iteration in
isolation** and multiply by the frequency. Split expensive collectors onto a slower
timer.

For this specific case: read the numbers from cgroups instead of asking the daemon.
`docker stats` is doing that anyway, just via `dockerd` and expensively. Under cgroup v2:

```
/sys/fs/cgroup/system.slice/docker-<FULL_ID>.scope/cpu.stat      # usage_usec
/sys/fs/cgroup/system.slice/docker-<FULL_ID>.scope/memory.current
```

Two file reads: **2 ms**. CPU percentage comes from the delta in `usage_usec` between
rounds. You need the full container ID:
`docker ps --no-trunc --format "{{.ID}}"`.

`docker ps` and `docker inspect` are cheap and can stay. `stats` is the expensive one.

From the same round: `du` on a large tree took 11–20 s (moved to a separate 30-minute
timer with `Nice=19` and idle I/O), and log scanning every 120 s was as good as every
20 s. After the changes, `dockerd` returned to 0%.

Related: [#10](agents.md#10-polling-a-running-subagent-costs-more-than-the-work) is this
exact mistake one layer up — an unpriced repeated call, multiplied by an uncounted loop.

---

## The rule these three share

> Any layer that text or measurement passes through can change its meaning while
> preserving its validity.

Heredocs and file writers transform escapes. Sandboxing directives transform "denied"
into "empty". Timers transform a negligible cost into a permanent one. In each case the
output stays well-formed, which is precisely why nothing complains.
