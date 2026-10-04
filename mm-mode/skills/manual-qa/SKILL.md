---
name: manual-qa
description: Starts a clean QA stack and drives the changed features the way a user does, with screenshots and logs as proof. Use when a mm-mode playbook step asks for manual QA, or the user asks to QA, smoke test or click through a change.
---

# Manual QA

You are the user. Use the real app on the real surface and prove what the change does. "It compiles" and "the tests pass" are not QA.

Do not edit source files. Report what you find. Another agent fixes it.

## Inputs

Read these from the arguments or the brief: $ARGUMENTS

- **Diff command**, such as `git diff <base>...HEAD`.
- **Spec source**: an issue number, a file path, or "no spec".
- **Output directory** for the report and evidence. If none is given, use `$(git rev-parse --git-path mm-mode/qa)/<timestamp>`.
- **Findings path**: where to write the findings list.

## 1. Plan from the change

Read the diff and the spec. List every user-facing behavior the change adds or alters. For each behavior, name the surface (web route, iOS screen, Android screen, API endpoint, CLI command) and the end state that proves it works. Add the error and empty cases the spec names.

Done when every changed user-facing file maps to at least one planned check. If the change has no user-facing surface, write `PASS: no user-facing surface` with the reason and stop.

## 2. Find how to run the app

Read the repo, not the user. Look in this order:

1. A project skill named `verify-*`, `qa-*` or `run-*`. If one exists, follow it and skip to step 4.
2. CLAUDE.md and AGENTS.md sections about QA stacks, e2e or local dev.
3. `docker-compose*.yml`, `Makefile`, package scripts, `Procfile`, README quickstart.
4. Existing e2e harnesses: Playwright or Cypress config, XCUITest, Detox, Maestro flows.

Record the start command, the ready signal (a log line or a port that answers), the URL or device, the seed data and the login. Done when you have each of these, or you know which one is missing.

## 3. Start a clean stack

- Give the QA stack its own name. For Docker Compose, pass `-p mmqa-<short sha>` to every command, or set `COMPOSE_PROJECT_NAME`. Use ports that do not clash with a stack the user already runs.
- Start from a clean state. Run the down command with `-v` against your own project name only, before you start. Stale volumes and stale branches cause errors that look like real bugs.
- Never stop a process, container or volume that you did not start. The user's dev database lives in their own stack.
- Start long processes with `nohup ... > <output dir>/stack.log 2>&1 &` and poll for the ready signal. macOS has no `setsid`.
- Run a **doctor** check before you drive anything. The process is up, the port answers and login works. The build matches `git rev-parse HEAD`.

Done when the doctor check passes. If the stack will not start after one environment fix, write `BLOCKED` with the exact error and the log path, then clean up and stop.

## 4. Drive each planned check

Use the surface's own tools:

- **Web:** the Claude in Chrome tools or Playwright. Prefer ARIA roles, labels and `data-testid` over coordinates.
- **iOS:** `xcrun simctl` to boot, install and launch, and `xcrun simctl io booted screenshot` for evidence.
- **Android:** `adb` and `adb exec-out screencap -p`.
- **API:** `curl -sS -i` against the running stack.
- **CLI:** run the built binary and save the full transcript.

For each check, capture the action and the end state. Check side effects too: rows written, emails queued, webhooks sent. Look for wrong copy, broken links, truncated text, missing controls and console errors. Save each piece of evidence in the output directory with the check name in the file name.

Done when every planned check has a result and evidence.

## 5. Clean up

Stop only what you started. Run the down command with your own project name, and kill only the PIDs you recorded. Keep the evidence. Confirm the evidence files still exist after cleanup.

## 6. Report

Write `<output dir>/report.md`:

```
## QA: PASS | ISSUES | BLOCKED
Build: <sha>    Stack: <start command>

| check | surface | result | evidence |
|-------|---------|--------|----------|
```

Write each problem to the findings path as one finding:

```
### <short title>
Surface: <route, screen, endpoint or command>
Repro: <numbered steps from a clean stack>
Expected: <what the spec or common sense says>
Actual: <what happened>
Evidence: <file path in the output directory>
```

Report every problem you can prove, not only the first. Return only the verdict, the report path and the number of findings.
