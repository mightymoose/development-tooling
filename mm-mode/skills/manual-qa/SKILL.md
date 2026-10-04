---
name: manual-qa
description: Black-box QA. Starts a clean QA stack, proves each listed feature works on the real app, then hunts for edge cases that break it. Use when a mm-mode playbook step asks for manual QA, or the user asks to QA, smoke test or click through a change.
---

# Manual QA

Your job is not to confirm that the change works. Your job is to try to break it.

**Trust nothing.** The feature list, the spec, a passing test suite, a success toast and your own earlier observation are all claims. A claim becomes a fact only when you observe it on the running app in this session.

**Test from the outside.** You are a user, not a reviewer. Do not read the source code, the diff or the tests. Work only from the feature list, the spec and what the running app shows you. To start the app, read only its run docs and config: README, CLAUDE.md, compose files, package scripts. Knowing the code makes you test what the code does, not what the user needs.

Do not modify repository source. Write only the report, the evidence, the findings file and your result block. Another agent fixes what you find.

Every exit, early or not, goes through step 8. That way the orchestrator always gets the same report, findings file and result block.

## Inputs

Read these from the arguments or the brief: $ARGUMENTS

- **Feature list**: a file path or text. Each feature says what a user can now do, and where in the app to find it.
- **Spec source**: an issue number, a file path, or "no spec".
- **Output directory** for the report and evidence. If none is given, use `$(git rev-parse --git-path mm-mode/qa)/<timestamp>`.
- **Findings path**: where to write the findings list.

## 1. Write the charter

Read the feature list and the spec. If you have neither, ask the user for a feature list. If you run as a worker and cannot ask, go to step 8 with status `BLOCKED` and the blocker "no feature list".

Write `<output dir>/charter.md` with three parts:

- **Mission:** one sentence about the main thing this change lets a user do.
- **Main checks:** at least one for each feature in the list. For each one, name the surface (web route, screen, API endpoint, CLI command), the action, and the **oracle**: the expected result and where that expectation comes from (the spec, existing behavior, or common sense).
- **Risk areas:** where a user is most likely to break each feature. Think about the input it takes, the data it saves and shows, who may use it, and the features next to it in the app.

Done when every feature in the list has at least one main check. If the feature list says the change has no user-facing feature, go to step 8 with status `NOT_APPLICABLE` and the reason.

## 2. Find how to run the app

Read the repo, not the user. Look in this order:

1. A project skill named `verify-*`, `qa-*` or `run-*`. If one exists, follow it to start the app.
2. CLAUDE.md and AGENTS.md sections about QA stacks, e2e or local dev.
3. `docker-compose*.yml`, `Makefile`, package scripts, `Procfile`, README quickstart.
4. Existing e2e harnesses: Playwright or Cypress config, XCUITest, Detox, Maestro flows.

If you run in a new git worktree, it has no installed dependencies and no ignored files such as `.env`. Install the dependencies, and copy ignored config from the main checkout, before you start the stack. The main checkout is the first path in `git worktree list`.

Record the start command, the ready signal (a log line or a port that answers), the URL or device, the seed data and the login. Done when you have each of these, or you know which one is missing.

## 3. Start a clean stack

- Give the QA stack its own name. For Docker Compose, pass `-p mmqa-<short sha>` to every command, or set `COMPOSE_PROJECT_NAME`. Use ports that do not clash with a stack the user already runs.
- Start from a clean state. Run the down command with `-v` against your own project name only, before you start. Stale volumes and stale branches cause errors that look like real bugs.
- Never stop a process, container or volume that you did not start. The user's dev database lives in their own stack.
- Start long processes with `nohup ... > <output dir>/stack.log 2>&1 &` and poll for the ready signal. macOS has no `setsid`.
- Run a **doctor** check before you drive anything. The process is up, the port answers and login works. The build matches `git rev-parse HEAD`.

Done when the doctor check passes. If the stack will not start after one environment fix, clean up, then go to step 8 with status `BLOCKED`. Put the exact error and the log path in the blocker.

## 4. Drive the app

Use the surface's own tools:

- **Web:** the Claude in Chrome tools or Playwright. Prefer ARIA roles, labels and `data-testid` over coordinates.
- **iOS:** `xcrun simctl` to boot, install and launch, and `xcrun simctl io booted screenshot` for evidence.
- **Android:** `adb` and `adb exec-out screencap -p`.
- **API:** `curl -sS -i` against the running stack.
- **CLI:** run the built binary and save the full transcript.

These rules hold for every check in steps 5 and 6:

- **One probe at a time.** Do one action, then observe, then decide the next one.
- **Watch for silent failures after every action.** Read the browser console, the failed network requests (4xx and 5xx), and the server log. A silent error is a finding even when the screen looks right.
- **Prove the lasting effect, not the screen.** After a save, reload the page or fetch the record again through the API. Check side effects too: rows written, emails queued, webhooks sent. A success message alone proves nothing.
- **Record each check** in `<output dir>/checks.md` as: action, observed result, expected result, `PASS` or `FAIL`, evidence path. Save evidence with the check name in the file name.
- **A check you could not run is not a pass.** A missing prerequisite, a timeout or a tool error makes it `NOT VERIFIED`, with the reason.

## 5. Prove the main functionality

Run every main check from the charter, start to finish, as a real user would. Use realistic data, not `test` and `123`.

Done when every main check is `PASS`, `FAIL` or `NOT VERIFIED` with evidence. If a feature in the list does not exist in the app, that is a `FAIL`.

## 6. Hunt for edge cases

Now attack the risk areas. Use the probe list in [references/probes.md](references/probes.md). Pick the probes that fit this change, and start with the risk areas from the charter.

Keep exploration notes in `<output dir>/notes.md`. For each surprise, write what you observed, your hypothesis, and the next probe that tests it. Follow every surprise until you can explain it or reproduce it as a bug.

Done when every probe group in the list was tried or marked `n/a` with a reason, and every surprise is explained or filed.

## 7. Confirm, then clean up

- **Replay each failure** from a clean state with the exact steps, before you report it. If it does not happen again, keep it, and mark it `flaky` with the number of tries.
- If the brief names a base commit and replay is cheap, run the base build and check whether the same failure happens there. If it does, mark it `predates the change`.
- Stop only what you started. Run the down command with your own project name, and kill only the PIDs you recorded. Keep the evidence, and confirm the evidence files still exist after cleanup.

## 8. Report

Write `<output dir>/report.md`:

```
## QA: PASS | NOT_APPLICABLE | BLOCKED | FAILED
Build: <sha>    Stack: <start command>
Mission: <from the charter>

| check | kind (main or edge) | surface | result | evidence |
|-------|---------------------|---------|--------|----------|

Not verified: <each check you could not run, and why>
Not tried: <each probe group marked n/a, and why>
```

Merge duplicate problems into one finding. Write each finding to the findings path:

```
### <short title>
Severity: critical | high | medium | low
Category: functional | data | security | error handling | visual | accessibility | console | content
Surface: <route, screen, endpoint or command>
Repro: <numbered steps from a clean stack>
Expected: <the oracle, and its source>
Actual: <what happened>
Reproduced: <yes, or flaky with tries>    Predates the change: <yes, no or unknown>
Evidence: <file paths in the output directory>
```

Severity:
- **critical:** a core feature is unusable, data is lost or wrong, or a security hole exists.
- **high:** a feature is broken but has a workaround, or an uncaught error shows on a main path.
- **medium:** the feature works, but the experience is poor or an error is unclear.
- **low:** polish, such as copy, spacing or a console warning.

Report every problem you can prove, not only the first. If you found none, write "no findings" to the findings path.

End with your result block, in the format your brief gives. If the brief gives none, use the lines `status`, `sha`, `artifacts`, `findings` and `blocker`. The status is `PASS` only when every main check ran, whether or not it found problems. The findings count says how many it found. Use `FAILED` if any main check is `NOT VERIFIED`.
