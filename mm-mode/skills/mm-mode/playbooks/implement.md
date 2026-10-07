### Implement a spec

**You own the plan and the gate. A worker gets room to finish its slice. A slice that fails returns control to the human.**

Implement builds a spec on a branch, one commit per slice. If the user wants an existing branch reviewed and fixed, this playbook does not match. Use the harden playbook.

The planner makes every product and interface decision, so a slice worker can build its slice with no oversight. Read [references/slicing.md](../references/slicing.md) for the slice rules, the brief format and the plan check. Workers follow the Workers rules in the mm-mode skill, with one change. **Slice workers** run in their own herdr tab with the model `sonnet`, per [references/herdr-workers.md](../references/herdr-workers.md). If `test "${HERDR_ENV:-}" = 1` fails, spawn a `general-purpose` subagent with the model `sonnet` instead.

Shell variables do not survive between commands or reach workers. In every brief and every command, write literal values. Below, `<run>` is the absolute run path and `<base>` is the base SHA. `<impl>`, `<harden>` and `<slicing>` are the absolute paths of `scripts/implement.sh`, `scripts/harden.sh` and `references/slicing.md` in the mm-mode skill directory. `<k>` is a round number. Name the other workers `plan-r<k>`, `plancheck-r<k>`, `features` and `qa`.

**Handoff.** When a check fails after the first slice starts, stop the run and hand control to the human. `<impl>` writes the handoff to `<run>/<name>.handoff.md` and marks the ledger row `needs-human`. The handoff has nine sections: phase, attempted, failed check, expected, observed, reproduce, evidence, checkout state and decision needed. Read it, and fill in "Decision needed" if the default does not fit. The failed attempt stays in the checkout as the worker left it. Never repair it, retry it, re-plan around it, stash it or revert it.

**Ledger.** `<run>/ledger.tsv` is the record of progress. Read it, not your memory, after a context reset. Each row has a phase: `slice`, `features`, `qa` or `final`. Only a `needs-human` row blocks the run. A handoff file stays on disk as evidence after the human resolves it, and never blocks. `<impl> phase <run>` reads the ledger and prints the phase to run next. While any row is `needs-human`, it prints `NEEDS_HUMAN` with the row and its phase, and every `<impl>` command that starts work refuses.

1. **Pin the run.**
   - If `git status --porcelain` shows any change, stop. List the changed files and ask the user to commit or stash them.
   - If HEAD is on the trunk, make a branch named for the spec and switch to it.
   - Record `git rev-parse HEAD` as `<base>`.
   - Make the run directory with `git rev-parse --path-format=absolute --git-path mm-mode/implement`, plus a timestamp folder. Record the absolute path as `<run>`.
   - Copy the spec to `<run>/spec.md`. The spec can be a file, an issue or text in the chat. If you have no spec, ask the user for one.
   - Write `<run>/checks.sh`, `<run>/checks.expected` and `<run>/baseline.txt` as step 1 of the harden playbook says. Run the full unit-test command in every check run, because a slice can break a test far from the files it touches. If no file has changed yet, a check scoped to changed files prints `DONE <check> 0`.
   - Start `<run>/ledger.tsv` with the header `name	phase	status	commits	note`.
   - Done when the branch, `<base>`, the spec copy, the baseline and the ledger exist.

2. **Plan the slices.** Start a new **planner** worker. Brief it: "Read `<run>/spec.md` and `<slicing>`. Read the code that the spec touches. Find the test commands and the seams the repo already uses. Invoke the `mm-mode:principle-test-first` and `mm-mode:principle-narrowest-seam` skills. Split the spec into slices per the slice rules. For each slice, write the brief, the `.files` file and the `.cmd` file to `<run>/slices/`. Write `<run>/slices/questions.md` with every product question that the spec and the code cannot answer, or 'no questions'. Do not edit repository source."
   - Apply the status gate from the harden playbook's stage loop.
   - If `questions.md` holds a question, ask the user. Give the answers to the next planner.
   - Done when every slice has its three files and `questions.md` says "no questions".

3. **Check the plan.** Start a new **plan checker** worker. Brief it: "Read `<run>/spec.md`, `<slicing>`, the ledger `<run>/ledger.tsv` and every file in `<run>/slices/`. The scope is `<full or replan>`. The proposed slices are `<ids>`. Read the code the briefs name. Test the proposed slices against every line of the plan check. Try to find a slice that could split, a decision a slice worker would have to make, and a requirement no slice covers. Write each failure to `<run>/plan.check.md`. Each finding names the slice, the plan-check line it fails and the fix. A split finding names both new slices, each with its own red test. Drop a finding that names no rule and no fix. If you find none, write 'no findings'."
   - If the check has findings, start a new planner with the spec, the ledger, the proposed slices and `plan.check.md`. Tell it to rewrite the proposed slices per the id rules. Then check again with a new plan checker and the same scope.
   - If the third check still has findings, stop. Show the user the findings.
   - Update the ledger by slice id. Add a row for each new id, with the phase `slice` and the status `planned`. Mark each id the planner dropped as `dropped`. Never change a `done` row.
   - Done when a plan check returns `PASS` with 0 findings and the ledger matches the slice files.

4. **Slice loop.** Run `<impl> phase <run>`. While it prints `slice <id>`, build that slice. When it prints `features`, go to step 5. If it prints `NEEDS_HUMAN`, stop and go to the reply. For each slice:
   - Run `<impl> begin <run> <slice>`. It moves any earlier attempt's files to `<run>/<slice>.attempt-<n>/` and records the start SHA.
   - Start a new slice worker in the user's checkout, named `<slice>`, with the **slice worker brief** below.
   - When it returns, if `<run>/<slice>.result` says `status: PASS`, read `<run>/<slice>.red.txt`. Confirm that each test failed with the expected failure in the brief. A refactor slice has no red file. If a test failed for another reason, run `<impl> handoff <run> <slice> red "<expected failure>" "<observed failure>" "<test command>" <run>/<slice>.red.txt`. Then stop.
   - Run `<impl> gate <run> <slice>`. It saves the output of each run under `<run>`. It checks, in order:
     - The worker's status is `PASS`, and a red run exists.
     - The working tree is clean, with one commit since the start.
     - Every changed file is in the `.files` list.
     - The `.cmd` test passes, and `checks.sh` shows no new failure.
   - If the gate prints `PASS`, it marks the row `done` with the commit. If it prints `NEEDS_HUMAN`, stop and go to the reply.
   - Done when the row says `done`, or a handoff exists.

5. **QA.** QA starts when `<impl> phase <run>` prints `features` or `qa`. That happens when every slice row is `done` or `dropped`. QA reports. It never starts a fix.
   - **Feature list.** Run `<impl> begin <run> features`. Start a feature-list worker named `features`. Use the brief from the feature-list section of the harden playbook, with this run's `<base>`, `<run>` and spec. Tell it to write its result block to `<run>/features.result`. Then run `<impl> accept <run> features`. If it prints `NEEDS_HUMAN`, stop and go to the reply.
   - Run `<harden> coverage-gaps <base> <run>/features.coverage.md`. If it prints a `MISSING` line, run the feature list once more with those files named. If the gaps remain, list them in the reply as incomplete coverage.
   - If `features.md` says the branch changes no observable behavior, run `<impl> mark <run> qa done`, log QA as not applicable, and go to step 6.
   - **QA run.** Run `<impl> begin <run> qa`. Make a worktree with `<harden> worktree-add <run> qa`. Start a new worker in it. Brief it: "Invoke the `mm-mode:manual-qa` skill. The feature list is `<run>/features.md`. The spec source is `<run>/spec.md`. Test from the outside: do not read the source code, the diff or the tests. Write the report and evidence under `<run>/qa/`. Write the findings to `<run>/qa.findings.md`. Write your result block to `<run>/qa.result`."
   - When it returns, run `<harden> capture <run> qa`. A QA worker must not edit source. If a patch appears, list it in the reply.
   - Run `<impl> accept <run> qa`. If it prints `NEEDS_HUMAN`, QA did not finish. Stop and go to the reply.
   - Done when `<impl> phase <run>` prints `final`, or a handoff exists.

6. **Final checks.** Run `<impl> final <run>` when `<impl> phase <run>` prints `final`. It runs `checks.sh`, compares the result with the baseline, and writes a handoff on a new failure. Done when it prints `PASS final`, or a handoff exists.

**Resume.** Resume only when the human tells you to.
- Run `<impl> state <run> <name>` for the `needs-human` row, and read the ledger. The human may have changed the checkout.
- Follow the human's direction. Ask only if the changed state makes that direction ambiguous. An example is a direction to retry a slice when the human has already committed a fix for it.
- Run `<impl> mark <run> <name> <status>` with the status the direction implies. `planned` reruns the row in its own phase. `done` accepts it as it stands. `dropped` removes a slice from the plan.
- If the human directs a re-plan, run step 2 for the slices that are not `done`, then step 3 with the scope `replan`.
- Then run `<impl> phase <run>`, and continue at the step for the phase it prints. A `qa` or `final` row never goes to a slice worker.

**Reply:** the branch name, and one row per slice with its behavior, kind, status and commits. Then the plan check rounds. If the run stopped, give the handoff path, the failed check, the decision needed and the checkout state, before anything else. Then the QA result, every QA finding in plain words, the incomplete coverage, and the open investigations under their own heading. Then the check status with any `UNRESOLVED` checks. Give the run directory path.

#### Slice worker brief

"Invoke the `mm-mode:principle-test-first` and `mm-mode:principle-narrowest-seam` skills, and follow them. Your slice brief is `<run>/slices/<slice>.md`. It is your whole task. You have room to finish it: iterate on your own code and tests until the slice is green.

1. Read the brief and the files it names.
2. Make ordinary coding choices yourself, such as a local name, a helper or a call to existing code in a listed file. Stop and report `BLOCKED` with the blocker 'needs decision: <the question>' for a change to product behavior, a change to the brief's interfaces, a file outside the brief's list, or work outside its scope.
3. Write the red tests from the brief. Run the command and save the output to `<run>/<slice>.red.txt`. If a test does not fail with its expected failure, stop and report `BLOCKED` with the blocker 'red mismatch'. A refactor slice skips this step.
4. Write the code that makes the tests pass. Change only the files the brief lists.
5. Run the brief's command, then `bash <run>/checks.sh`. Fix each failure that your change caused.
6. Commit once, with a message that names the slice. Leave no uncommitted change.

On every exit, write your result block to `<run>/<slice>.result`. Put the commit SHA in `sha`."
