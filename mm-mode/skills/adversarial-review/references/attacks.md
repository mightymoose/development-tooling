# Attacks per stage kind

Run the attack that matches the stage kind. Each attack is a set of questions. A finding survives only if the evidence answers them in its favor.

## simplify

The producer claims the code can be simpler, can reuse something, or can run faster.

- **Behavior.** Does the proposed change keep every behavior the current code has? Check error paths, ordering, side effects and the empty case.
- **Reuse.** If it says "reuse X", does X exist, and does X handle every case the current code handles? Open X and compare.
- **Reach.** Does the change touch code outside the diff? If it does, it needs a stronger reason.
- **Net gain.** Count the lines, layers and names before and after. A change that moves complexity without removing it is `REJECTED`.
- **Tests.** Does a test exercise the behavior that the change touches? Coverage of the lines alone is not enough. If no test does, the fix is at most `RISKY`.

## code-review

The producer claims the code breaks a repo standard, misses the spec, or has a bug.

- **Standard.** For a standards finding, quote the rule from the repo file. If no repo file states the rule, the finding is a judgment call. If a linter already enforces it, dismiss it.
- **Spec.** For a spec finding, quote the spec line. Check that the diff truly lacks it. Search the whole branch, not only the hunk the producer cited.
- **Bug.** For a bug finding, trace a real path from an entry point to the failure. If you can, write the input that triggers it. If no caller can reach it, the finding is `REJECTED`.
- **Tests.** For a finding about a test, invoke `mm-mode:principle-narrowest-seam`. Judge the test by its key question: what does this test prove that no other test proves?
- **Scope creep.** For "not asked for" findings, check whether the extra code is needed to make a spec item work.

## qa

The producer claims the running app misbehaves.

- **Reproduce.** Read the repro steps and the evidence (screenshot, response body, log). Does the evidence show the claimed failure? A finding with no evidence is at most `PLAUSIBLE`.
- **Cause.** Is the failure caused by this change? Check whether the same path fails on the base commit from the diff command. Use a worktree at the base only if the check is cheap. A failure that also exists on the base goes to `noted`, with a note that it predates the change.
- **Environment.** Could a stale environment cause it: an old volume, cached data, a wrong branch, a port held by another process? If the evidence points there, the finding is `REJECTED` and the reason names the environment fix.
- **Spec.** Does the spec say what the right behavior is? If the spec is silent and the behavior is a product choice, set readiness to `RISKY` and say it needs a human decision. The finding then stays open.
