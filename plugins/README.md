# Skills for working with a box

A Claude Code plugin, `orca-box`, that lets a coding agent work with the Orca server on a box set up from this repository. This file is for the agent that installs it for its user: read it and do the steps. Ask the owner whenever a step says to.

| Skill | Teaches the agent to |
|---|---|
| `orca-box` | reach the box's Orca server with the `orca` CLI, give agents work, watch runs, install and log in agents |

## What the owner needs first

- The Orca desktop app on this computer, paired with the box (RUNBOOK.md, Orca pairing).
- Orca's command line on the PATH: in the app, Settings, General, Orca CLI, turn on Shell command. Check with `command -v orca`. Only the owner can turn it on.

## Install for Claude Code

1. Find the box among the saved Orca servers: `orca environment list --json`, field `name`. If there is more than one, ask the owner which is the box. The name can be a plain IP address: do not repeat it in chat summaries, and keep it out of this repository and anything committed.
2. Point every `orca` command at the box by default, so they do not run against the Orca on this computer. Read `env.ORCA_ENVIRONMENT` in `~/.claude/settings.json`. If it already equals the name from step 1, go to step 3. If it is missing, merge this into the `env` object, keeping everything already there, after showing the owner the exact change. If it holds a different value, ask the owner before changing it.
   ```json
   { "env": { "ORCA_ENVIRONMENT": "<name from step 1>" } }
   ```
3. Install the plugin from this repository's marketplace, from the root of this checkout. Show the owner the two commands first; they change the agent's own plugin settings.
   ```sh
   claude plugin marketplace add ./
   claude plugin install orca-box@orca-box
   ```
4. Start a new session so the setting and the plugin are loaded.

Orca itself may have installed a separate skill, `orca-cli`, in `~/.claude/skills`. Leave it as it is; the `orca-box` skill adds to it and does not replace it.

## It worked when

In a new session, `orca status --json` shows `target.kind` as `environment`, `runtime.reachable` as `true` and `runtime.connectionState` as `connected` (the output is long: read only those fields), `claude plugin list` shows `orca-box` enabled, and the skill is listed as `orca-box:orca-box`.

## Updating

When this repository changes, pull it, then from its root run `claude plugin marketplace update orca-box` and `claude plugin update orca-box@orca-box`, and start a new session. Steps 1 and 2 are done once.
