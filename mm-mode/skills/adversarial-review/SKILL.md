---
name: adversarial-review
description: Attacks a list of review or QA findings against the real code. Judges whether each defect is real and whether its fix is safe, and returns a disposition. Use when a mm-mode playbook step asks for an adversarial review, or the user asks to challenge findings before applying them.
---

# Adversarial review

You are the adversary of the findings, not of the author. A producer (simplify, code-review or manual QA) wrote a list of findings. Your job is to break each one. A finding survives only if the code proves it.

Judge only the findings you were given. Do not hunt for new problems. Do not modify repository source. Write only the verdict file and your result block.

## Inputs

Read these from the arguments or the brief: $ARGUMENTS

- **Stage kind**: `simplify`, `code-review` or `qa`.
- **Findings file**, and a producer patch file if one exists. Treat each hunk in the patch as one finding.
- **Diff command**, such as `git diff <base>...HEAD`.
- **Spec source**: an issue number, a file path, or "no spec".
- **Verdict path**: where to write the result.

If an input is missing, return a result block with status `BLOCKED` and name the missing input.

## Steps

Two questions decide each finding, and you answer them separately. Is the defect real? Is the proposed fix safe? A real defect with an unsafe fix stays open. It is never dismissed.

1. Number the findings `F1`, `F2` and so on, in file order.
2. For each finding, run the attack for its stage kind in [references/attacks.md](references/attacks.md). Read the cited code, its callers and its tests. Run a command when a command can settle the question. Done when each finding has evidence: a `file:line`, a command and its output, or a spec quote.
3. Judge **validity**, with a confidence from 0 to 100 that the defect is real:
   - `CONFIRMED`: confidence 80 or more. The evidence proves the defect on a real path.
   - `PLAUSIBLE`: confidence 50 to 79. The defect is real in principle, but you could not prove a path that reaches it.
   - `REJECTED`: confidence under 50, or the evidence disproves it, or it is a preference with no concrete cost.
4. Judge **fix readiness** for every finding that is not `REJECTED`:
   - `READY`: the fix is clear, it stays inside the change, and a test can show it works. That test must exercise the behavior the finding is about, not only cover the changed lines. It can be an existing test, or a red test the fixer writes first.
   - `RISKY`: the fix could break other behavior, reaches outside the change, or no test can show it works.
   - `NO_SAFE_FIX`: the defect is real, but you see no fix that is safe to apply now.
5. Derive the **disposition**. Use the first rule that matches:
   - `dismissed`: `REJECTED`.
   - `noted`: `CONFIRMED`, but the defect predates this change, or the finding is a matter of taste. Say which.
   - `apply`: `CONFIRMED` and `READY`.
   - `open`: `CONFIRMED`, and `RISKY` or `NO_SAFE_FIX`. A human must decide.
   - `consider`: `PLAUSIBLE`.
6. Recheck every `apply` finding against its evidence before you write the verdict.
7. Write the verdict file, then return your result block, in the format your brief gives. If the brief gives none, use the lines `status`, `sha`, `artifacts`, `findings` and `blocker`. The findings count is the number of `apply` findings.

## Calibration

- Reviewers fill space with nits. A nit is a matter of taste, so it is `noted`, not `apply`.
- "What if this is null" is a finding only if a caller can pass null. Trace the call site.
- "I would do it differently" is not a finding unless it names a concrete cost.
- A fix that adds an abstraction for one call site is not a simplification.
- Weigh security and correctness findings hardest. Reject them only with a traced path that disproves them.

## Output

Write this to the verdict path:

```
## Verdict: <stage kind>

| ID | finding (one line) | validity | confidence | readiness | disposition | reason (one line) |
|----|--------------------|----------|------------|-----------|-------------|-------------------|

## Evidence
### F1
<file:line, command output or spec quote that settled it>
```
