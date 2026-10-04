---
name: mm-mode
description: mightymoose's agent style. Matches each task to a playbook and runs helper skills as the playbook steps need them. Use for /mm-mode or requests to work in this style.
disable-model-invocation: true
---

# mm mode

## Sticky mode

After the user starts mm mode, it stays on for the rest of the session. On each new user turn:

- If the turn matches a playbook, apply mm mode.
- If the turn is casual or matches no playbook, answer normally.
- If the user says to stop mm mode, stop applying it until they start it again.

## How to run a playbook

1. Match the task to one playbook in the table below.
2. Open a todo list. Copy the playbook steps into it word for word.
3. Do each step in order. If a step names a skill, invoke that skill with the Skill tool.
4. End with the reply that the playbook names.

If no playbook matches, say so and answer normally.

## Principles

Apply these in every playbook. When a principle shapes a decision, name it in the reply. Each worker brief that writes or reviews code tells the worker to invoke the matching principle skills.

- **Test first** (**mm-mode:principle-test-first**). Before you change what code does. Every behavior change starts red, one vertical slice at a time.
- **Narrowest seam** (**mm-mode:principle-narrowest-seam**). When you choose where a test goes, or review a test. Start from the behavior, then test at the narrowest seam that holds all of it.

## Workers

A **worker** is a fresh agent that runs one playbook step with its own context. When a playbook step says to start a worker, pick how to run it:

- If `test "${HERDR_ENV:-}" = 1` passes, run the worker in a new herdr tab. Follow [references/herdr-workers.md](references/herdr-workers.md).
- Otherwise, spawn a `general-purpose` subagent with the Agent tool. Add this line to its brief: "If you cannot spawn subagents, do that work yourself, one part after the other."

These rules hold for both kinds:

- Start a new worker for each step. Give a fix round or a retry to a new worker with the full brief, not to the worker that ran before.
- Pass file paths, not file contents. Tell the worker where to write its output.
- Ask for a short return: a verdict, a path and counts. The detail stays in the files.
- You own the worker's output. Check the real output (the file, the commit, the exit code) before you act on its summary.

## Playbooks

| playbook | for |
|---|---|
| [harden a change](playbooks/harden.md) | the user asks to harden, polish, review or QA a branch before a PR. |
| [tell a joke](playbooks/tell-a-joke.md) | the user asks for a joke. |
