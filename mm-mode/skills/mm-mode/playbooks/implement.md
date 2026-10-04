### Implement a spec

**You own the plan. Slice it thin, check the plan, then let each slice go red, then green.**

Implement builds a spec on a branch, one slice per commit. If the user wants an existing branch reviewed and fixed, this playbook does not match. Use the harden playbook.

The planner makes every design decision, so a slice worker can build its slice with no oversight. Read [references/slicing.md](../references/slicing.md) for the slice rules, the brief format and the plan check. Workers follow the Workers rules in the mm-mode skill, with one change. **Slice workers** run in their own herdr tab with the model `sonnet`, per [references/herdr-workers.md](../references/herdr-workers.md). If `test "${HERDR_ENV:-}" = 1` fails, spawn a `general-purpose` subagent with the model `sonnet` instead.

Shell variables do not survive between commands or reach workers. In every brief and every command, write literal values. Below, `<run>` is the absolute run path and `<base>` is the base SHA. `<harden>` and `<slicing>` are the absolute paths of `scripts/harden.sh` and `references/slicing.md` in the mm-mode skill directory. `<NN>` is the slice number, and `<k>` is the round number.

Herdr names must start with a letter, so name the workers `plan-r<k>`, `plancheck-r<k>`, `s<NN>-build`, `s<NN>-repair`, `features-r<k>`, `qa-r1` and `qa-r2`. The ledger keeps the full slice id.

1. **Pin the run.**
   - If `git status --porcelain` shows any change, stop. List the changed files and ask the user to commit or stash them.
   - If HEAD is on the trunk, make a branch named for the spec and switch to it.
   - Record `git rev-parse HEAD` as `<base>`.
   - Make the run directory with `git rev-parse --path-format=absolute --git-path mm-mode/implement`, plus a timestamp folder. Record the absolute path as `<run>`.
   - Copy the spec to `<run>/spec.md`. The spec can be a file, an issue or text in the chat. If you have no spec, ask the user for one.
   - Write `<run>/checks.sh`, `<run>/checks.expected` and `<run>/baseline.txt` as step 1 of the harden playbook says. Run the full unit-test command in every check run, because a slice can break a test far from the files it touches. If no file has changed yet, a check scoped to changed files prints `DONE <check> 0`.
   - Start `<run>/slices.tsv` with the header `slice	status	commit	note`. This ledger is the record of progress. Read it, not your memory, after a context reset.
   - Done when the branch, `<base>`, the spec copy, the baseline and the ledger exist.

2. **Plan the slices.** Start a new **planner** worker. Brief it: "Read `<run>/spec.md` and `<slicing>`. Read the code that the spec touches. Find the test commands and the seams the repo already uses. Invoke the `mm-mode:principle-test-first` and `mm-mode:principle-narrowest-seam` skills. Split the spec into slices per the slice rules. Write one brief per slice to `<run>/slices/` in the brief format. Write `<run>/slices/questions.md` with every product question that the spec and the code cannot answer, or 'no questions'. Do not edit repository source."
   - Apply the status gate from the harden playbook's stage loop.
   - If `questions.md` holds a question, ask the user. Give the answers to the next planner.
   - Done when every brief exists and `questions.md` says "no questions".

3. **Check the plan.** Start a new **plan checker** worker. Brief it: "Read `<run>/spec.md`, `<slicing>` and every brief in `<run>/slices/`. Read the code the briefs name. Test the plan against every line of the plan check. Try to find a slice that could split, a decision a slice worker would have to make, and a requirement no slice covers. Write each failure to `<run>/plan.check.md`. Each finding names the slice, the plan-check line it fails and the fix. A split finding names both new slices, each with its own red test. Drop a finding that names no rule and no fix. If you find none, write 'no findings'."
   - If the check has findings, start a new planner with the spec, the briefs and `plan.check.md`. Tell it to rewrite the briefs. Then check the plan again with a new plan checker.
   - If the third check still has findings, stop. Show the user the findings.
   - Done when a plan check returns `PASS` with 0 findings. Add one ledger row per slice with the status `planned`.

4. **Slice loop.** Build the slices in order, one at a time. For each slice:
   - Run `<harden> begin <run> <slice>`.
   - Start a new slice worker in the user's checkout with the **slice worker brief** below. Name it `s<NN>-build`.
   - If the status is not `PASS`, run `<harden> recover <run> <slice>` and log what it prints. Then route by the blocker:
     - "needs decision" or "red mismatch": use the re-plan rule.
     - The environment, such as a port in use or a missing dependency: fix the cause, then start the slice again once.
     - Anything else: stop and report.
   - Read `<run>/<slice>.red.txt`. Confirm that the test failed with the expected failure in the brief. A refactor slice has no red file.
   - Let `<pre>` be the SHA in `<run>/<slice>.pre`. Confirm that `git rev-list --count <pre>..HEAD` prints 1. Confirm that every file in `git diff --name-only <pre> HEAD` is in the brief's file list.
   - If the red output or the file list is wrong, the brief was wrong or the worker left it. Run `<harden> recover <run> <slice>`, then use the re-plan rule.
   - Run `bash <run>/checks.sh > <run>/<slice>.checks.txt 2>&1`, then `<harden> new-failures <run>/checks.expected <run>/baseline.txt <run>/<slice>.checks.txt`. Exit 0 or 2 passes.
   - On exit 1 or 3, start one new slice worker named `s<NN>-repair` with the brief and the checks output. Tell it to add one repair commit. Then run the checks again. If they still fail, run `<harden> recover <run> <slice>`, log what it prints, and stop.
   - Done when the checks pass and the ledger row says `done` with the commit SHA. Never start the next slice on a failing base.

   **Re-plan rule.** If a slice worker reports "needs decision" or "red mismatch", or a slice shows that a brief is wrong, stop the loop. Recover the unfinished slice first. If the decision is a product call, ask the user. Then start a new planner with the spec, the ledger, the blocker and the remaining briefs. Tell it to rewrite only the slices not yet done. Run step 3 on the new briefs, then continue the loop.

5. **QA.** Start a feature-list worker as the harden playbook says, with this run's `<base>`, `<run>` and spec. Run `<harden> coverage-gaps <base> <run>/features.coverage.md`. If it prints a `MISSING` line, start a new feature-list worker with those files named.
   - If `features.md` says the branch changes no observable behavior, log QA as not applicable and go to step 6.
   - Make a worktree with `<harden> worktree-add <run> qa-r1`. Start a new worker in it. Brief it: "Invoke the `mm-mode:manual-qa` skill. The feature list is `<run>/features.md`. The spec source is `<run>/spec.md`. Test from the outside: do not read the source code, the diff or the tests. Write the report and evidence under `<run>/qa-r1/`. Write the findings to `<run>/qa-r1.findings.md`."
   - When it returns, run `<harden> capture <run> qa-r1`. A QA worker must not edit source. If a patch appears, ignore it.
   - Apply the status gate. If the status is `BLOCKED` because of the environment, fix the cause and retry once.
   - If QA has findings, start a new planner. Tell it to write one fix slice per finding, with a red test that reproduces the finding. Run steps 3 and 4 on the fix slices. Then run QA once more as `qa-r2`.
   - Done when QA returns `PASS` with 0 findings or `NOT_APPLICABLE`, or `qa-r2` has run.

6. **Final checks.** Run `bash <run>/checks.sh > <run>/final.txt 2>&1`, then `<harden> new-failures <run>/checks.expected <run>/baseline.txt <run>/final.txt`. Done when it exits 0 or 2.

**Reply:** the branch name, and one row per slice with its behavior, kind and commit. Then the plan check rounds, every re-plan and its cause, the QA result per round, and the check status with any `UNRESOLVED` checks. List the QA findings that are still open, and suggest the harden playbook for them. List the QA open investigations under their own heading. Give the run directory path.

#### Slice worker brief

"Invoke the `mm-mode:principle-test-first` and `mm-mode:principle-narrowest-seam` skills, and follow them. Your slice brief is `<brief path>`. It is your whole task.

1. Read the brief and the files it names.
2. If the brief leaves a choice open, or the code does not match the brief, stop. Report `BLOCKED` with the blocker 'needs decision: <the question>'. Do not guess.
3. Write the red test from the brief. Run its command and save the output to `<run>/<slice>.red.txt`. If it does not fail with the expected failure, stop and report `BLOCKED` with the blocker 'red mismatch'. A refactor slice skips this step.
4. Write the least code that makes the test pass. Change only the files the brief lists. If another file must change, stop and report `BLOCKED` with the blocker 'needs decision' and the file.
5. Run `bash <run>/checks.sh`. Fix each failure that your change caused.
6. Commit once, with a message that names the slice.

End with your result block. Put the commit SHA in `sha`."
