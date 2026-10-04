### Harden a change

**You own the gate. Every finding faces an adversary before it touches the code.**

The orchestrator (you) keeps only pointers and verdict summaries. Every producer, reviewer and fixer runs in a new worker per the Workers rules in the mm-mode skill.

A **stage** is one producer pass plus its gate: produce findings, review them adversarially, apply what survives, run the checks. The run has three stage kinds: `simplify`, `code-review` and `qa`.

Shell variables do not survive between commands or reach workers. In every brief and every command, write the literal absolute run path and the literal base SHA. The `<run>` and `<base>` below stand for those literal values.

1. **Pin the run.**
   - Find the base with `git merge-base HEAD origin/main`, or the repo's trunk. Record the SHA as `<base>`.
   - If `git status --porcelain` shows changes, stage all of them with `git add -A`. Then commit them as `chore: checkpoint before harden`.
   - Make the run directory with `git rev-parse --path-format=absolute --git-path mm-mode/harden`, plus a timestamp folder. Record the absolute path as `<run>`. The directory lives inside `.git`, so nothing in it gets committed.
   - Write one test file to `<run>` with the Write tool. If the write fails, use an ignored folder outside `.git` as `<run>`.
   - Find the spec: an issue number in the branch name or commit messages, or a spec file. If you find none, record "no spec".
   - Find the check commands in the target repo: CLAUDE.md, AGENTS.md, package scripts, Makefile, pre-commit config, CI workflow. Pick the unit-test commands and every static check (lint, typecheck, format check).
   - Write `<run>/checks.sh`. It computes the changed files when it runs, with `git diff --name-only <base>...HEAD`. It scopes each check to those files where the tool supports it. It prints one `PASS <check>` or `FAIL <check>` line per check, and exits non-zero if any check fails.
   - Run `<run>/checks.sh` once now. Save its `FAIL` lines to `<run>/baseline.txt`. These checks were red before the run started.
   - Start `<run>/ledger.tsv` with the header `stage	finding	verdict	confidence	action	evidence`.
   - Done when `<base>`, the spec source, `checks.sh`, the baseline and the ledger exist, and the tree is clean.

2. **Pass loop.** A **pass** runs the three stages below in order: simplify, then code review, then QA. Repeat the pass until the exit predicate holds, for at most 3 passes. Number the passes `p1`, `p2`, `p3`. Name each stage `<pass>-<kind>`, such as `p2-code-review`. Every pass reviews the whole branch with `git diff <base>...HEAD`, so later passes also review the fixes that earlier passes applied.
   - **Simplify stage.** Run the **stage loop** with stage kind `simplify`. Producer brief: "Invoke the `simplify` skill on the diff `git diff <base>...HEAD`. Report findings only. Leave every file unchanged. Write each finding to `<run>/<stage>.findings.md` with its file, line, the problem and the proposed change."
   - **Code review stage.** Run the **stage loop** with stage kind `code-review`. Producer brief: "Invoke the `code-review` skill. The fixed point is `<base>`. The spec source is `<spec source or 'no spec, skip the Spec axis'>`. If the skill asks for a file you cannot find, such as `docs/agents/issue-tracker.md`, use the spec source given here and continue. Write both reports to `<run>/<stage>.findings.md`. Leave every file unchanged."
   - **QA stage.** Run the **stage loop** with stage kind `qa`. Producer brief: "Invoke the `mm-mode:manual-qa` skill on the change `git diff <base>...HEAD`. The spec source is `<spec source>`. Write the report and evidence under `<run>/<stage>/`. Write the findings to `<run>/<stage>.findings.md`."
   - If QA reports `BLOCKED` because of the environment, fix the cause, then run the QA stage again in the same pass. Examples are a stale volume, a port in use or a missing dependency. If it is still `BLOCKED`, end the pass. `BLOCKED` is never a pass.
   - **Exit predicate:** one whole pass applies no commit. In that pass, QA reports `PASS` and the last checks run shows no new failure. A pass that applied any fix needs another pass to review that fix.
   - If pass 3 ends and the predicate is false, stop. Report the open findings and the last QA report.

3. **Final checks.** Run `<run>/checks.sh` once more on the final HEAD. Done when it shows no new failure.

**Reply:** one row per stage with findings in, applied, considered and dismissed, grouped by pass. Then the QA verdict per pass, the check status, any baseline failures, and the open `consider` findings in plain words. Name the bucket thresholds from the `mm-mode:adversarial-review` skill and the pass cap. Give the run directory path so the user can read the dismissed list.

#### Stage loop

Run these four steps for each stage. Start a new worker for each of steps A, B and C.

**A. Produce.** Start a worker with the producer brief.
- When it returns, run `git status --porcelain`.
- If the tree is dirty, the producer edited files. Save its edits with `git diff > <run>/<stage>.producer.patch`, then restore the tree with `git checkout -- . && git clean -fd`. Tell the reviewer in step B to judge the hunks in that patch as findings.
- If the findings file is empty or says "no findings", log one ledger row and skip to the next stage.
- Done when the findings file exists and the tree is clean.

**B. Adversarial review.** Start a new worker. Brief it: "Invoke the `mm-mode:adversarial-review` skill. The stage kind is `<kind>`. The findings are in `<findings file>` (and `<patch file>` if one exists). The diff command is `git diff <base>...HEAD`. The spec source is `<spec source>`. Write the verdict to `<run>/<stage>.verdict.md`."
- Read only the verdict table from `<run>/<stage>.verdict.md`.
- Add one ledger row per finding.
- Done when every finding in the findings file has a row in the verdict table.

**C. Apply.** Pick the findings to apply from the verdict table:
- `act-on`: apply.
- `consider`: apply only if its `auto-apply` column says `yes`. Keep the rest for the reply.
- `noted` and `dismissed`: do not apply. They stay in the ledger.

If nothing is left to apply, skip to the next stage. Otherwise start a new worker. Brief it with the verdict file path and the IDs of the findings to apply. Tell it: "Invoke the `mm-mode:principle-test-first` and `mm-mode:principle-narrowest-seam` skills, and follow them. Apply each listed finding. If a finding changes behavior or fixes a bug, start with a red test at the narrowest seam. Run `<run>/checks.sh`. Commit with the message `<kind>: apply harden findings <IDs>`. Report the commit SHA and the IDs you could not apply, with the reason."
- Done when the commit exists and every listed ID is applied or has a reason.

**D. Checks.** You run the checks yourself. Do not trust the fixer's report.
- Run `bash <run>/checks.sh > <run>/<stage>.checks.log 2>&1`. Read the exit code, the `FAIL` lines and the last 40 lines.
- A **new failure** is a `FAIL` line that is not in `<run>/baseline.txt`.
- If a new failure shows, start a new fixer worker with the log path and the stage commit SHA. If a new failure still shows after that fixer, revert the stage commit with `git revert --no-edit <sha>` and log it.
- Done when no new failure shows, or the stage commit is reverted and logged.
