---
name: orca-box
description: Use when work involves the Orca server on the remote box: giving agents work, watching runs and terminals, installing a new agent, or logging one in. Every step goes through the `orca` CLI.
---

# Orca on the box

The box runs an Orca server inside a VM. This session reaches it with the `orca` CLI only, and the CLI already points at the box.

## 1. Confirm the target

```text
orca status --json
```

The output is long (hundreds of capability strings): read only `target.kind`, `runtime.reachable`, `runtime.connectionState` and `runtime.appVersion`, for example with `orca status --json | grep -E '"(kind|reachable|connectionState|appVersion)"'`. Expect `environment`, `true`, `connected` and the box's version. The server is headless, so `app.running` is `false` and `desktopWindowStatus` is `blocked`; that is normal. The target comes from `ORCA_ENVIRONMENT` (a name from `orca environment list`). If it is unset or the server is unreachable, tell the owner and wait.

`runtime.appVersion` is the server's version. The CLI on the owner's computer can be newer, and a command the server does not know fails with a clear error.

## 2. Learn the commands

```text
orca skills get orca-cli
```

That guide matches the installed CLI, so it is not copied here. For this box the useful parts are: `worktree create --agent` and `agent launch` to start work, `worktree ps` and `search` to see what runs, `terminal read`, `terminal send` and `terminal wait` to follow or steer an agent, `automations runs` for scheduled work. Paths and ids always refer to the box.

## 3. Install an agent

Run the agent's own install command in a terminal on the box, then read the output back. Find the install command in the agent's own documentation. It runs as the box's runtime user, not root, so it installs into that user's home.

A terminal needs a workspace. List them first with `orca repo list --json` and reuse a folder workspace if one fits. If none does, add one for a path that exists on any Linux box (`/tmp`, or the runtime user's home):

```text
orca repo add --path /tmp --kind folder --json
orca terminal create --worktree path:/tmp --title install --command "<install command>" --json
orca terminal read --terminal <handle> --json
```

`--title` is optional. The create reply may warn that the terminal is running but not discoverable; the terminal still runs and `terminal read` works. Close it when done with `orca terminal close --terminal <handle> --tab`. Reuse that workspace for the next install and tell the owner what was added; when it is no longer needed, see "Remove a project" below.

Check the result with a one-line prompt, for example `Reply with exactly: ok`.

A VM rebuild removes anything installed this way. Agents added after setup are reinstalled by the session that needs them.

## 4. Working with agents and projects

- Start a coordinator or worker with `orca agent launch`. Where Claude Code has not yet been accepted into Bypass Permissions mode, the Enter that `--prompt` sends lands on the confirmation, whose default is "No, exit", and Claude exits. Launch without `--prompt`, have the owner accept once, then send the brief with `orca terminal send --text "<brief>" --enter`.
- `orca terminal read` prints stacked fragments for full-screen agents and wrapped commands. Use `--screen` for what is rendered.
- A new terminal can take a few seconds to show output, and `terminal wait --for exit` timing out does not mean the command failed.
- `orca orchestration ...` works only inside an Orca terminal (outside it fails with `no_active_sender_terminal`). From outside, launch a coordinator agent with `agent launch`; the coordinator then uses `worker-start`. It needs the orchestration skill installed on the box (Settings > Orchestration in the Orca app); `orca skills install` installs only Orca's bundled skills.
- Environment variables an agent needs (for example Claude's `CLAUDE_CODE_OAUTH_TOKEN`) are set by the owner in the runtime user's `~/.profile`, which Orca's terminals read.
- Browser tabs: `orca tab create --url <url> --worktree path:<abs>` opens a page on the box, and `orca snapshot` reads its DOM. Screenshots taken through Orca's browser from a terminal on the box come back as a flat single colour. To check how a page looks, use `agent-browser` (on the runtime user's PATH, with its own Chrome): start the app on a free port, then `agent-browser --args "--no-sandbox" open http://localhost:<port>`, `agent-browser set viewport <w> <h>`, `agent-browser screenshot <path>`, `agent-browser close`, and read the PNG. Chrome cannot start with its sandbox on this box (Ubuntu 24.04 blocks it), so pass `--no-sandbox` only on that first `open`, and only for pages the project itself serves on localhost. Run `agent-browser skills get core --full` for the other commands.

### Giving work

Pick by what you expect back. From outside an Orca terminal, `--repo id:<repoId>` is needed (the id is in `orca repo list --json`).

- Handoff, nothing comes back: `orca worktree create --repo id:<repoId> --name <n> --no-parent --agent claude --prompt "<brief>" --json`. It is handed off once the reply gives the worktree id, the agent handle and `prompt.outcome` of `handed-to-terminal` or `journaled`. Never resend on silence; retry a lost reply with `--retry-launch <operationId>`. For an existing worktree use `orca agent launch --agent claude --worktree id:<repo>::<path> --prompt "<brief>"`. Terminal handles go stale after an Orca restart, so list them again.
- Team: hand off a claude coordinator whose brief tells it to use the orchestration skill: create a Run and Tasks, start workers with `worker-start`, end its turn and let Orca wake it. Keep the coordinator on the box: the Run stays on the coordinator's runtime.
- Scheduled: `orca automations create --name <n> --trigger "<cron>" --timezone UTC --prompt "<brief>" --provider claude --repo id:<repoId> [--precheck "<cmd>"] --json`; test with `automations run <id>`, read history with `automations runs --id <id>`, stop with `automations edit <id> --disabled`. A failing precheck gives status `skipped_precheck` with no worktree and no agent.

A worker brief names the tools (`agent-browser` and its commands, not "the browser tool"), lists the widths to check (for example 360, 390, 768, 900, 1024, 1280, 1440), says not to ask questions but to write `blocked.md` and stop, says not to push (use local git), and ends with the completion signal: `orca worktree set --worktree active --comment "done: <one line>" --workspace-status in-review`. Wait by polling `orca worktree show --worktree id:<id>` for that status; `terminal wait --for tui-idle` can return at once and is not proof of completion.

Do not accept "done". Read the git log and the files, and look at the PNGs the agent says it took. Fonts differ between the box and the owner's computer, so offer the owner the page to look at: serve it with `systemd-run --user --unit=<name> --working-directory=<worktree> python3 -m http.server <port> --bind 127.0.0.1`, open it with `orca tab create --url http://localhost:<port> --worktree id:<repo>::<path> --json`, and `systemctl --user stop <name>` afterwards.

To bring text or an image back, `orca terminal read` can return only the echoed command for long or slow output. Print it between markers (`echo BEGIN; base64 -w 200 <file>; echo END`), read with `--cursor 0 --limit 900` and decode locally; this worked up to about 100 KB per read.

### Remove a project

`orca project setups --json` lists projects with their ids. `orca project setup-delete --setup <id>` removes the project record and refuses while it has open terminals or saved workspace details; `--force` overrides that. It deletes no files: close the project's terminals, then run `rm -rf <path>` in an Orca terminal on the box. `orca worktree rm` removes a non-root git worktree with its directory; for a project's root it fails with "Cannot delete the project root workspace".

## 5. Steps that belong to the owner

- Logging an agent in (device codes, browser sign-in). Start the login command in a terminal, show the owner the prompt it prints, and wait. Never write a code, token or URL into a chat, log or commit.
- Pairing a device with the box.
- The first-run "Bypass Permissions" confirmation of Claude Code in an automation. A run stays `dispatched` until the owner accepts it in that run's terminal.

## 6. Not done from here

Updating Orca on the box, rebuilding the VM and changing the host belong to the session that keeps the box scripts.
