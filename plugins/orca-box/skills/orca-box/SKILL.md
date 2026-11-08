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

### Remove a project

`orca project setups --json` lists projects with their ids. `orca project setup-delete --setup <id>` removes the project record and refuses while it has open terminals or saved workspace details; `--force` overrides that. It deletes no files: close the project's terminals, then run `rm -rf <path>` in an Orca terminal on the box. `orca worktree rm` removes a non-root git worktree with its directory; for a project's root it fails with "Cannot delete the project root workspace".

## 5. Steps that belong to the owner

- Logging an agent in (device codes, browser sign-in). Start the login command in a terminal, show the owner the prompt it prints, and wait. Never write a code, token or URL into a chat, log or commit.
- Pairing a device with the box.
- The first-run "Bypass Permissions" confirmation of Claude Code in an automation. A run stays `dispatched` until the owner accepts it in that run's terminal.

## 6. Not done from here

Updating Orca on the box, rebuilding the VM and changing the host belong to the session that keeps the box scripts.
