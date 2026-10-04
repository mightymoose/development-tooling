# Herdr workers

A herdr worker is a fresh Claude Code session in its own herdr tab. It is a top-level session, so it can start its own subagents and run any skill. Run one worker at a time, because all workers share one checkout.

Run `herdr tab`, `herdr agent` and `herdr pane` without a subcommand to read the current syntax. Never run bare `herdr`, because it opens the TUI. Parse every ID from the JSON that a command returns.

## Start a worker

1. **Name it.** Use `<stage>-<role>`, such as `p1-simplify-produce` or `p2-qa-review`. The name must match `[a-z][a-z0-9_-]{0,31}` and be unique among live agents.
2. **Write the brief to a file.** Put the full brief in `<run>/<name>.brief.md`. End it with this line: "When you are done, write the word DONE to `<run>/<name>.done`. If you cannot finish, write BLOCKED and the reason to that file."
3. **Make the tab.** Run `herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd <repo root> --label <name> --no-focus`. Record `.result.tab.tab_id` and `.result.root_pane.pane_id`.
4. **Start Claude.** Run `herdr agent start <name> --kind claude --pane <pane id> -- --permission-mode <mode>`. Use the permission mode the user named. If the user named none, use `auto`. If the start returns `agent_not_ready`, run `herdr agent wait <name> --timeout 60000` before you prompt it.
5. **Prompt it.** Run `herdr agent prompt <name> "Read <run>/<name>.brief.md and do what it says." --wait --timeout 3600000`.

## Wait for the result

The `.done` file is the completion signal. The agent state alone does not prove that the work is done.

- If `--wait` returns and `<run>/<name>.done` says `DONE`, check the outputs that the brief names. Then close the tab with `herdr tab close <tab id>`.
- If the `.done` file says `BLOCKED`, read the reason. Keep the tab open, and treat the step as failed.
- If the state is `blocked`, the worker shows an approval or a question. Read it with `herdr agent read <name> --source recent-unwrapped --lines 80`. Do not answer an approval yourself. Tell the user the worker name and what it asks, and wait for them.
- If the state is `idle` or `done` and no `.done` file exists, read the last 120 lines. Send one prompt that asks the worker to finish and write the `.done` file. If that fails, keep the tab open and treat the step as failed.
- If `--wait` times out, the worker can still be working. Run `herdr agent wait <name> --timeout 3600000` again. Never send the brief a second time.

Close only the tabs you created. Keep a failed worker's tab open so the user can read it, and name it in the reply.
