### Implement a spec

**You own the plan. Slice it thin, check the plan, then let each slice go red, then green.**

Implement builds a spec on a branch, one commit per slice, plus a repair commit when a slice needs one. If the user wants an existing branch reviewed and fixed, this playbook does not match. Use the harden playbook.

The planner makes every product and interface decision, so a slice worker can build its slice with no oversight. Read [references/slicing.md](../references/slicing.md) for the slice rules, the brief format and the plan check. Workers follow the Workers rules in the mm-mode skill, with one change. **Slice workers** run in their own herdr tab with the model `sonnet`, per [references/herdr-workers.md](../references/herdr-workers.md). If `test "${HERDR_ENV:-}" = 1` fails, spawn a `general-purpose` subagent with the model `sonnet` instead.

Shell variables do not survive between commands or reach workers. In every brief and every command, write literal values. Below, `<run>` is the absolute run path and `<base>` is the base SHA. `<harden>` and `<slicing>` are the absolute paths of `scripts/harden.sh` and `references/slicing.md` in the mm-mode skill directory. `<NN>` is the slice number, and `<k>` is the round number.

Herdr names must start with a letter, so name the workers `plan-r<k>`, `plancheck-r<k>`, `s<NN>-build`, `s<NN>-repair`, `features-r<k>`, `qa-r1` and `qa-r2`. The ledger keeps the full slice id.

1. **Pin the run.**
   - If `git status --porcelain` shows any change, stop. List the changed files and ask the user to commit or stash them.
   - If HEAD is on the trunk, make a branch named for the spec and switch to it.
   - Record `git rev-parse HEAD` as `<base>`.
   - Make the run directory with `git rev-parse --path-format=absolute --git-path mm-mode/implement`, plus a timestamp folder. Record the absolute path as `<run>`.
   - Copy the spec to `<run>/spec.md`. The spec can be a file, an issue or text in the chat. If you have no spec, ask the user for one.
   - Write `<run>/checks.sh`, `<run>/checks.expected` and `<run>/baseline.txt` as step 1 of the harden playbook says. Run the full unit-test command in every check run, because a slice can break a test far from the files it touches. If no file has changed yet, a check scoped to changed files prints `DONE <check> 0`.
   - Start `<run>/slices.tsv` with the header `slice	status	commits	note`. The status is `planned`, `done` or `dropped`. This ledger is the record of progress. Read it, not your memory, after a context reset.
   - Done when the branch, `<base>`, the spec copy, the baseline and the ledger exist.

2. **Plan the slices.** Start a new **planner** worker. Brief it: "Read `<run>/spec.md` and `<slicing>`. Read the code that the spec touches. Find the test commands and the seams the repo already uses. Invoke the `mm-mode:principle-test-first` and `mm-mode:principle-narrowest-seam` skills. Split the spec into slices per the slice rules. Write one brief per slice to `<run>/slices/` in the brief format. Write `<run>/slices/questions.md` with every product question that the spec and the code cannot answer, or 'no questions'. Do not edit repository source."
   - Apply the status gate from the harden playbook's stage loop.
   - If `questions.md` holds a question, ask the user. Give the answers to the next planner.
   - Done when every brief exists and `questions.md` says "no questions".

3. **Check the plan.** Start a new **plan checker** worker. Name the scope from the plan check in `<slicing>`: `full` for the first plan, `replan` after a re-plan, `qa-fix` for QA fix slices. Brief it: "Read `<run>/spec.md`, `<slicing>`, the ledger `<run>/slices.tsv` and every brief in `<run>/slices/`. The scope is `<scope>`. The proposed slices are `<ids>`. Read the code the briefs name. Test the proposed slices against every line of the plan check. Try to find a slice that could split, a decision a slice worker would have to make, and a requirement no slice covers. Write each failure to `<run>/plan.check.md`. Each finding names the slice, the plan-check line it fails and the fix. A split finding names both new slices, each with its own red test. Drop a finding that names no rule and no fix. If you find none, write 'no findings'."
   - If the check has findings, start a new planner with the spec, the ledger, the proposed briefs and `plan.check.md`. Tell it to rewrite the proposed briefs per the id rules. Then check again with a new plan checker and the same scope.
   - If the third check still has findings, stop. Show the user the findings.
   - Update the ledger by slice id. Add a `planned` row for each new id. Mark each id the planner dropped as `dropped`. Never change a `done` row.
   - Done when a plan check returns `PASS` with 0 findings and the ledger matches the briefs.

4. **Slice loop.** Build the `planned` slices in ascending number, one at a time. For each slice:
   - Run `<harden> begin <run> <slice>`. Let `<pre>` be the SHA it writes to `<run>/<slice>.pre`. Every start of a slice, a retry included, begins here.
   - Start a new slice worker in the user's checkout with the **slice worker brief** below. Name it `s<NN>-build`.
   - Run the **slice gate** below. If the gate passes, set the ledger row to `done` and record every commit since `<pre>`.
   - If gate check 4 or 5 fails after the build, start one new slice worker named `s<NN>-repair`. Give it the slice worker brief, the brief path and the failing output. Tell it to skip step 3 and add one repair commit. Then run the slice gate again. If check 4 or 5 fails again, run `<harden> recover <run> <slice>`, log what it prints, and stop.
   - Done when the ledger row says `done`. Never start the next slice on a failing base.

   **Slice gate.** Run every check below after every slice worker, build and repair alike. Take the first check that fails and its route.
   1. The result status is `PASS`. If it is not, run `<harden> recover <run> <slice>` and log what it prints. If the blocker starts with "needs decision" or "red mismatch", use the re-plan rule. If the cause is the environment, such as a port in use or a missing dependency, fix it and start the slice again once. For any other cause, stop and report.
   2. `git status --porcelain` is empty, and `git rev-list --count <pre>..HEAD` equals the number of workers that ran for this slice. If not, run `recover` and start the slice again once with a new build worker.
   3. Every file in `git diff --name-only <pre> HEAD` is in the brief's file list. After the build, `<run>/<slice>.red.txt` shows each test fail with its expected failure. A refactor slice has no red file. If either check fails, the brief was wrong or the worker left it. Run `recover`, then use the re-plan rule.
   4. Run the brief's test command yourself, and save the output to `<run>/<slice>.green.txt`. It exits 0.
   5. Run `bash <run>/checks.sh > <run>/<slice>.checks.txt 2>&1`, then `<harden> new-failures <run>/checks.expected <run>/baseline.txt <run>/<slice>.checks.txt`. It exits 0 or 2.

   **Re-plan rule.** If a slice worker reports "needs decision" or "red mismatch", or a slice shows that a brief is wrong, stop the loop. Recover the unfinished slice first. If the decision is a product call, ask the user. Then start a new planner with the spec, the ledger, the blocker and the briefs that are not `done`. Tell it to rewrite, drop or add slices per the id rules, and never to touch a `done` slice. Run step 3 with the scope `replan`, then continue the loop.

5. **QA.** Start a feature-list worker as the harden playbook says, with this run's `<base>`, `<run>` and spec. Run `<harden> coverage-gaps <base> <run>/features.coverage.md`. If it prints a `MISSING` line, start a new feature-list worker with those files named.
   - If `features.md` says the branch changes no observable behavior, log QA as not applicable and go to step 6.
   - Make a worktree with `<harden> worktree-add <run> qa-r1`. Start a new worker in it. Brief it: "Invoke the `mm-mode:manual-qa` skill. The feature list is `<run>/features.md`. The spec source is `<run>/spec.md`. Test from the outside: do not read the source code, the diff or the tests. Write the report and evidence under `<run>/qa-r1/`. Write the findings to `<run>/qa-r1.findings.md`."
   - When it returns, run `<harden> capture <run> qa-r1`. A QA worker must not edit source. If a patch appears, ignore it.
   - Apply the status gate. If the status is `BLOCKED` because of the environment, fix the cause and retry once.
   - If QA has findings, start a new planner. Tell it to write one `fix` slice per finding, per the id rules, with a red test that reproduces the finding. Run step 3 with the scope `qa-fix`, then step 4. Then run QA once more as `qa-r2`.
   - Done when QA returns `PASS` with 0 findings or `NOT_APPLICABLE`, or `qa-r2` has run.

6. **Final checks.** Run `bash <run>/checks.sh > <run>/final.txt 2>&1`, then `<harden> new-failures <run>/checks.expected <run>/baseline.txt <run>/final.txt`. Done when it exits 0 or 2.

**Reply:** the branch name, and one row per slice with its behavior, kind, status and commits. Then the plan check rounds, every re-plan and its cause, the QA result per round, and the check status with any `UNRESOLVED` checks. List the QA findings that are still open, and suggest the harden playbook for them. List the QA open investigations under their own heading. Give the run directory path.

#### Slice worker brief

"Invoke the `mm-mode:principle-test-first` and `mm-mode:principle-narrowest-seam` skills, and follow them. Your slice brief is `<brief path>`. It is your whole task.

1. Read the brief and the files it names.
2. Make local choices yourself, such as a local name or a call to an existing helper in a listed file. Stop and report `BLOCKED` with the blocker 'needs decision: <the question>' for a product choice, a change to the brief's interfaces, a file outside the brief's list, or work outside its scope.
3. Write the red tests from the brief. Run the command and save the output to `<run>/<slice>.red.txt`. If a test does not fail with its expected failure, stop and report `BLOCKED` with the blocker 'red mismatch'. A refactor slice skips this step.
4. Write the least code that makes the tests pass. Change only the files the brief lists.
5. Run the brief's command, then `bash <run>/checks.sh`. Fix each failure that your change caused.
6. Commit once, with a message that names the slice. Leave no uncommitted change.

End with your result block. Put the commit SHA in `sha`."
