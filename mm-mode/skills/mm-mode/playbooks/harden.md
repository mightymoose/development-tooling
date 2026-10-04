### Harden a change

**You own the gate. Every finding faces an adversary before it touches the code.**

Harden always applies fixes. It commits on the current branch. If the user only wants a review or QA without changes, this playbook does not match. Run the `code-review` skill or the `mm-mode:manual-qa` skill instead.

The orchestrator (you) keeps only pointers and verdict summaries. Every producer, reviewer and fixer runs in a new worker per the Workers rules in the mm-mode skill. Producers and reviewers work in their own git worktree, so their edits never reach the user's checkout. A new worktree has no installed dependencies and no ignored files such as `.env`. Tell those workers to install dependencies, and to copy ignored config from the user's checkout, when a command needs them.

A **stage** is one producer pass plus its gate: produce findings, review them adversarially, apply what survives, run the checks. The run has three stage kinds: `simplify`, `code-review` and `qa`.

Shell variables do not survive between commands or reach workers. In every brief and every command, write literal values. Below, `<run>` is the absolute run path, `<base>` is the base SHA, and `<harden>` is the absolute path of `scripts/harden.sh` in the mm-mode skill directory.

1. **Pin the run.**
   - If `git status --porcelain` shows any change, stop. List the changed files and ask the user to commit or stash them. Never commit, stash or discard the user's work yourself.
   - Find the base with `git merge-base HEAD origin/main`, or the repo's trunk. Record the SHA as `<base>`.
   - Make the run directory with `git rev-parse --path-format=absolute --git-path mm-mode/harden`, plus a timestamp folder. Record the absolute path as `<run>`. The directory lives inside `.git`, so nothing in it gets committed.
   - Find the spec: an issue number in the branch name or commit messages, or a spec file. If you find none, record "no spec".
   - Find the check commands in the target repo: CLAUDE.md, AGENTS.md, package scripts, Makefile, pre-commit config, CI workflow. Pick the unit-test commands and every static check (lint, typecheck, format check).
   - Write `<run>/checks.sh`. It computes the changed files when it runs, with `git diff --name-only <base>...HEAD`, and scopes each check to them where the tool allows.
   - Make `checks.sh` print one line per failure: `FAIL <check>::<test or diagnostic id>`. Get the IDs from the runner's machine-readable output, such as JUnit XML, a JSON reporter or `pytest -rf`. If a check cannot name its failures, it prints `FAIL <check>::*`. It exits non-zero if anything fails.
   - Run `bash <run>/checks.sh > <run>/baseline.txt`. These failures existed before the run started. They did not necessarily exist before the branch.
   - Start `<run>/ledger.tsv` with the header `stage	finding	validity	readiness	disposition	evidence`.
   - Done when `<base>`, the spec source, `checks.sh`, the baseline and the ledger exist.

2. **Pass loop.** A **pass** runs the three stages below in order: simplify, then code review, then QA. Repeat the pass until the exit predicate holds, for at most 3 passes. Number the passes `p1`, `p2`, `p3`. Name each stage `<pass>-<kind>`, such as `p2-code-review`. Every pass reviews the whole branch with `git diff <base>...HEAD`, so later passes also review the fixes that earlier passes applied.
   - **Simplify stage.** Run the **stage loop** with stage kind `simplify`. Producer brief: "Invoke the `simplify` skill on the diff `git diff <base>...HEAD`. Report findings only. Write each finding to `<run>/<stage>.findings.md` with its file, line, the problem and the proposed change."
   - **Code review stage.** Run the **stage loop** with stage kind `code-review`. Producer brief: "Invoke the `code-review` skill. The fixed point is `<base>`. The spec source is `<spec source or 'no spec, skip the Spec axis'>`. If the skill asks for a file you cannot find, such as `docs/agents/issue-tracker.md`, use the spec source given here and continue. Write both reports to `<run>/<stage>.findings.md`."
   - **QA stage.** Run the **stage loop** with stage kind `qa`. Producer brief: "Invoke the `mm-mode:manual-qa` skill on the change `git diff <base>...HEAD`. The spec source is `<spec source>`. Write the report and evidence under `<run>/<stage>/`. Write the findings to `<run>/<stage>.findings.md`."
   - If the QA result is `BLOCKED` because of the environment, fix the cause, then run the QA stage again in the same pass. Examples are a stale volume, a port in use or a missing dependency. If it is still `BLOCKED`, end the pass. `BLOCKED` is never clean.
   - **Exit predicate:** one whole pass applies no commit. In that pass, QA returns `PASS` with 0 findings, or `NOT_APPLICABLE`, and the last checks run shows no `NEW` failure.
   - If pass 3 ends and the predicate is false, stop. Report the open findings and the last QA report.

3. **Final checks.** Run `bash <run>/checks.sh > <run>/final.txt`, then `<harden> new-failures <run>/baseline.txt <run>/final.txt`. Done when it prints no `NEW` line. An `UNRESOLVED` line means a check failed before and after the run, and the run cannot tell whether it got worse. Report it as unresolved, never as "no regression".

**Reply:** one row per stage with findings in, applied, open, considered and dismissed, grouped by pass. Then the QA result per pass, the check status with any `UNRESOLVED` checks, and every `open` and `consider` finding in plain words. Give the run directory path so the user can read the ledger.

#### Stage loop

Run these four steps for each stage. Start a new worker for each of steps A, B and C.

**A. Produce.**
- Make a worktree with `<harden> worktree-add <run> <stage>-produce`. Start a worker in that worktree with the producer brief. Tell it to run every command in the worktree.
- When the worker returns, read its result block. Then run `<harden> capture <run> <stage>-produce`. If the producer edited files, this saves every edit as a patch and prints its path. It always removes the worktree.
- If the result is `NOT_APPLICABLE`, or it reports 0 findings and no patch exists, log one ledger row and skip to the next stage.
- Done when the result block is read and the worktree is gone.

**B. Adversarial review.**
- Make a worktree with `<harden> worktree-add <run> <stage>-review`. Start a new worker in it. Brief it: "Invoke the `mm-mode:adversarial-review` skill. The stage kind is `<kind>`. The findings are in `<findings file>` (and `<patch file>` if one exists). The diff command is `git diff <base>...HEAD`. The spec source is `<spec source>`. Write the verdict to `<run>/<stage>.verdict.md`."
- When it returns, run `<harden> capture <run> <stage>-review`. A reviewer must not edit source. If a patch appears, log it and ignore it.
- Read only the verdict table. Add one ledger row per finding.
- Done when every finding has a row in the verdict table.

**C. Apply.** Apply only the findings with disposition `apply`. All others stay in the ledger. `open` and `consider` findings go in the reply.
- If nothing has disposition `apply`, skip to the next stage.
- Run `<harden> begin <run> <stage>` to record where the stage starts.
- Start a new worker in the user's checkout. Brief it with the verdict file path and the IDs to apply. Tell it: "Invoke the `mm-mode:principle-test-first` and `mm-mode:principle-narrowest-seam` skills, and follow them. Apply each listed finding. If a finding changes behavior or fixes a bug, start with a red test at the narrowest seam. Run `<run>/checks.sh`. Commit with the message `<kind>: apply harden findings <IDs>`. In your result block, list the commit SHA and each ID you could not apply, with the reason."
- Done when the commit exists and every listed ID is applied or has a reason.

**D. Checks.** You run the checks yourself. Do not trust the fixer's report.
- Run `bash <run>/checks.sh > <run>/<stage>.checks.txt 2>&1`, then `<harden> new-failures <run>/baseline.txt <run>/<stage>.checks.txt`. Read only its output and the exit code.
- If it prints a `NEW` line, start a new fixer worker with the checks output path. That fixer adds repair commits.
- If a `NEW` line still shows after that fixer, run `<harden> rollback <run> <stage>`. It reverts the stage commit and every repair commit. Log the reverted SHAs.
- Done when no `NEW` line shows, or the rollback is logged.
