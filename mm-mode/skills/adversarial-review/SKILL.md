---
name: adversarial-review
description: Attacks a list of review or QA findings against the real code and returns a verdict, confidence and bucket for each. Use when a mm-mode playbook step asks for an adversarial review, or the user asks to challenge findings before applying them.
---

# Adversarial review

You are the adversary of the findings, not of the author. A producer (simplify, code-review or manual QA) wrote a list of findings. Your job is to break each one. A finding survives only if the code proves it.

Do not hunt for new problems. Judge only the findings you were given. Do not edit any file.

## Inputs

Read these from the arguments or the brief: $ARGUMENTS

- **Stage kind**: `simplify`, `code-review` or `qa`.
- **Findings file**, and a producer patch file if one exists. Treat each hunk in the patch as one finding.
- **Diff command**, such as `git diff <base>...HEAD`.
- **Spec source**: an issue number, a file path, or "no spec".
- **Verdict path**: where to write the result.

If an input is missing, write `BLOCKED: <missing input>` to the verdict path and stop.

## Steps

1. Number the findings `F1`, `F2` and so on, in file order. Done when every finding has an ID.
2. For each finding, run the attack for its stage kind in [references/attacks.md](references/attacks.md). Read the cited code, its callers and its tests. Run a command when a command can settle the question. Done when each finding has evidence: a `file:line`, a command and its output, or a spec quote.
3. Give each finding a **verdict**:
   - `CONFIRMED`: the evidence proves the problem on a real path.
   - `PLAUSIBLE`: the problem is real in principle, but you could not prove a path that reaches it.
   - `REJECTED`: the evidence disproves it, or it is a preference with no concrete cost.
4. Give each finding a **confidence** from 0 to 100. This is how sure you are that applying the fix makes the code better and breaks nothing.
5. Put each finding in a **bucket**. Use the first rule that matches:
   - `dismissed`: `REJECTED`, or confidence under 50.
   - `act-on`: `CONFIRMED` and confidence 80 or more.
   - `consider`: `CONFIRMED`, or `PLAUSIBLE` with confidence 70 or more.
   - `noted`: every other finding.
6. For each `consider` finding, set **auto-apply** to `yes` or `no`. Use `-` for the other buckets. Set `yes` only if all three hold:
   - The fix stays inside the changed files.
   - A test covers the lines it changes.
   - It needs no human decision.
7. Write the verdict file and stop.

## Calibration

- Reviewers fill space. If every finding in a list is a nit, say so and dismiss them.
- "What if this is null" is a finding only if a caller can pass null. Trace the call site.
- "I would do it differently" is not a finding unless it names a concrete cost.
- A fix that adds an abstraction for one call site is not a simplification.
- Weigh security and correctness findings hardest. Dismiss them only with a traced path that disproves them.
- More than 5 `act-on` findings means you are not filtering hard enough. Check each one again.

## Output

Write this to the verdict path:

```
## Verdict: <stage kind>

| ID | finding (one line) | verdict | confidence | bucket | auto-apply | reason (one line) |
|----|--------------------|---------|------------|--------|------------|-------------------|

## Evidence
### F1
<file:line, command output or spec quote that settled it>
```

Return only the verdict path and the count per bucket.
