# orca-box

Scripts and a runbook for a headless Ubuntu host that runs one Multipass VM with the Orca server and coding agents. The host is reachable only over Tailscale, and the VM is isolated from the LAN.

## Before you start

- A mini PC or small server with hardware virtualization and a wired network port. Tested on amd64 only; arm64 is untested.
- The Ubuntu Server 24.04 ISO and a USB stick.
- A second computer with an SSH key, the Orca desktop app, and Tailscale installed and signed in, with Tailnet Lock already enabled and the disablement secrets saved in a password manager.
- The accounts the agents will log in with, and a GitHub fine-grained token.

## Guided setup

Copy this prompt into your coding agent (Claude Code or similar) on the second computer:

```
Clone or open the orca-box repository. Read README.md, RUNBOOK.md and the "Guided setup (for the agent)" section of RUNBOOK.md.
I am starting from a blank mini PC and want a working Orca box.

First give me the complete numbered list of steps from blank hardware to a paired Orca with the coding agents I use (the last step is agent setup: ask me which agents I use and help me find how to install and log in to any the scripts do not already cover), short, marking the ones only I can do. Then walk me through them one at a time and wait for me to confirm each before the next.

Talk to me in my own language. Never ask me to paste passwords, tokens, pairing URLs or Tailscale login URLs into the chat, and never write them to files. Ask before any reboot, any change to SSH, firewall or kernel, and before running anything on the box that is not in this repo's scripts. Follow RUNBOOK.md exactly instead of improvising. When something fails, stop and report the exact error instead of working around it.
```

## Doing it by hand

`RUNBOOK.md` is the procedure. `docs/specs/2026-11-03-design.md` has the reasoning and what is tested.
