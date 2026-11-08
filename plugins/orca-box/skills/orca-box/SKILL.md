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

The output is long (hundreds of capability strings): read only `target.kind`, `runtime.reachable`, `runtime.connectionState` and `runtime.appVersion`. Expect `environment`, `true`, `connected` and the box's version. The server is headless, so `app.running` is `false` and `desktopWindowStatus` is `blocked`; that is normal. The target comes from `ORCA_ENVIRONMENT` (a name from `orca environment list`). If it is unset or the server is unreachable, tell the owner and wait.

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

The create reply may warn that the terminal is running but not discoverable; the terminal still runs and `terminal read` works. Close it when done with `orca terminal close --terminal <handle> --tab`. The CLI has no command to remove a folder workspace, so one added here stays until the owner removes it in the Orca app: reuse it for the next install and tell the owner what was added.

Check the result with a one-line prompt, for example `Reply with exactly: ok`.

A VM rebuild removes anything installed this way. Agents added after setup are reinstalled by the session that needs them.

## 4. Steps that belong to the owner

- Logging an agent in (device codes, browser sign-in). Start the login command in a terminal, show the owner the prompt it prints, and wait. Never write a code, token or URL into a chat, log or commit.
- Pairing a device with the box.
- The first-run "Bypass Permissions" confirmation of Claude Code in an automation. A run stays `dispatched` until the owner accepts it in that run's terminal.

## 5. Not done from here

Updating Orca on the box, rebuilding the VM and changing the host belong to the session that keeps the box scripts.
