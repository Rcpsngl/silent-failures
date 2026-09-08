# Configuration and data

Three failures where the code was correct. The environment it ran in, or the data it ran
on, was not — and neither one raises an error.

---

### 16. A missing environment variable selects the permissive default

**Symptom.** A hardening change is written, reviewed, merged, deployed. The code is
correct. The protection is not active in production.

2026-09-08.

**Reality.** The environment split was keyed on `APP_ENV`, whose **default value is
`development`**. Production never set it. Every guard behind that flag stayed in its
permissive branch — no error, no warning, nothing but one line in the startup log.

**Why it wasn't caught.** The gap is between *"the change is in the code"* and *"the
change is running"*, and nothing in the pipeline measures that gap. The diff is right.
The review is right. The deploy succeeds. The test suite runs in an environment where
the variable **is** set, so it passes there too.

And this is never one bug. Once a flag's default is the permissive branch, every guard
behind it inherits the same failure — a single unset variable relaxes a whole family at
once.

**Guardrail.** **Make the strict value the default and fail loudly on the loose one.** An
unset variable should refuse to boot rather than quietly pick a branch:

```python
APP_ENV = os.environ["APP_ENV"]          # KeyError beats a silent default
```

If you cannot change the default, verify after every deploy. Log the resolved state at
startup as an explicit assertion — not the variable, but its *consequence*:

```
relaxed-origin rule OFF (APP_ENV=production)
```

Then grep for that line after deploying. A configuration value in a log is data; a
statement about what it changed is a check.

---

### 17. Diagnosing DNS from a single resolver

**Symptom.** A domain's nameservers were pointed back at the real host and the zone was
rebuilt correctly. Two major public resolvers both returned the right answers. Verified,
apparently fine.

Meanwhile an email provider's domain verification kept failing, the site loaded in some
browsers and not others, and a third component reported
`Supplied countryName is invalid`. Three unrelated outages, seemingly.

2026-09-04.

**Reality.** One cause. **The old nameservers were never removed, and they kept
answering.** Queried directly, the previous parking provider returned a wildcard TXT
record for *every* subdomain — including the `_domainkey` lookup the email provider
needed. Resolvers that had not yet propagated were still asking there, and getting that.

The verification was not reporting "your record is wrong". It was **asking the wrong
server**, and reporting the result as a record failure.

**Why it wasn't caught.** Because the check ran against one resolver, and that resolver
agreed. A resolver that has already propagated tells you nothing about the ones that have
not. And the three symptoms looked distinct enough to be filed as three problems, which
is exactly what propagation failures do — they reach different consumers at different
times, so the shared cause is invisible from any one of them.

The same round produced the mirror image: a `curl` from a Windows box aborted the TLS
handshake, so the site was assumed down; from inside the server it returned `200`.
**Both directions, one instrument, a confident verdict.**

**Guardrail.** Never diagnose DNS from one vantage point. Ask at least three and compare:

```bash
dig @8.8.8.8 <record> <type>                                # a public resolver
dig @$(dig +short NS <domain> | head -1) <record> <type>    # the authoritative server
dig @<old-nameserver> <record> <type>                       # the one you migrated off
```

If the three disagree, the diagnosis is **propagation**, not a bad record — and the
remedy is to wait, not to edit. `whois` gives the `Updated Date`; `.com` NS TTLs can run
to 48 hours. Pressing a service's "verify" button repeatedly inside that window
accomplishes nothing.

The general form: **one instrument cannot distinguish "the thing is broken" from "this
instrument cannot see it."**

---

### 18. Two schemas, one reader — content renders empty

**Symptom.** A user reported: *"some questions show only the hint."* The question text was
missing from the screen. No error, no warning, clean console. The backend serialized the
content correctly and it passed validation.

Reported from production 2026-08-27.

**Reality.** The content model carried **two schemas** for the same item type — an active
one and a legacy one kept for backward compatibility. **No client ever implemented the
legacy branch.** Normalization read the active field, got an empty string, produced zero
segments, and rendered an empty container. The hint came from a different field and was
printed unconditionally, so it survived on screen alone.

Only items authored under the legacy schema went blank. That is why it was "some".

**Why it wasn't caught.** Nothing in the pipeline objected. The legacy shape is valid, it
serializes, it validates — the model still declares it. The failure lives entirely in the
gap between *"the schema exists"* and *"some client reads it"*, and nothing checks that.

**And it could not be reproduced on development data.** Dev content had all been authored
under the active schema. Every local test passed, correctly. The bug existed only where
the old rows did.

**Guardrail.** When the symptom is *empty output rather than wrong output*, ask which
schema the data was written in **before** reading any code. That answer changes the whole
fix:

- legacy rows exist → a **data** problem → migration, no deploy
- no legacy rows → a **code** problem → implement the branch, deploy

```bash
# how many rows are on the old shape?
db.<collection>.countDocuments({ <legacy_field>: { $exists: true } })
```

Two structural rules follow:

1. **A schema nothing reads is not backward compatibility, it is a trap.** Either
   implement the branch, or migrate the data off it and delete the field. Leaving it
   declared "just in case" guarantees that something eventually writes to it.
2. **Development data is not a sample of production data.** It is a sample of what your
   own team authored, recently, with current tooling. Bugs that live in old rows are
   invisible there by construction — which makes "I can't reproduce it locally" evidence
   about the data, not about the bug.
