# Contributing

The bar for a catalog entry is narrow on purpose.

## What belongs here

An entry qualifies if all three hold:

1. **It exits successfully.** If the tool errors, it's a bug report, not a silent failure.
2. **You confirmed it.** You reproduced it, or traced it to source, or ran a control
   experiment (broke the thing deliberately and watched the check go red).
3. **There is a guardrail.** A command, a check, a number to look at. "Be careful" is
   not a guardrail.

## What does not belong here

- **Anything you inferred but did not observe.** A plausible failure mode is a
  hypothesis. This catalog is worth reading only because every entry actually happened.
- **State.** Version numbers that will move, branch names, "as of today". An entry
  must still be true in a year or it must say what it depends on.
- **Prompts.** There are enough prompt collections.

## Format

Every entry follows the same four beats. Keep them.

```markdown
### <Short name of the failure>

**Symptom.** What you saw. Quote the exact reassuring output.

**Reality.** What was actually happening.

**Why it wasn't caught.** The specific reason the failure was invisible —
this is the part readers learn from.

**Guardrail.** The check, as a command or a rule.
```

Add a date and, where you have it, a root cause traced to source. A root cause turns
an anecdote into a fact other people can act on.

## Tone

Plain. No hedging, no drama. The incidents are interesting on their own; they do not
need adjectives. If an entry needs a superlative to feel important, it probably isn't.
