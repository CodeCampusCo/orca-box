# Orca box runbook

A headless Ubuntu box runs the Orca server as a systemd user service for a non-root user (`orca`), with Claude Code, Codex and Antigravity (`agy`) as agents. The Mac reaches it over Tailscale (Tailnet Lock on), and the Orca desktop app pairs with it.

Box-specific values (tailnet address, LAN IP) are not kept here; read them with `tailscale ip -4` on the box or from the Tailscale admin console.

## Set up a new box

1. Install Ubuntu Server 24.04 with OpenSSH and the Mac's public key for the admin user. Find its LAN IP.
2. From the Mac: `scp setup-box.sh pair.sh <admin>@<lan-ip>:` then `ssh <admin>@<lan-ip> sudo bash setup-box.sh`.
3. On the box, as admin: `sudo tailscale up --hostname <name>`, open the printed URL and log in.
4. Tailnet Lock: the new node starts locked out. In the admin console, Machines, choose Sign node for it (or run the `tailscale lock sign ...` command the box's `tailscale lock status` prints, from the Mac CLI at `/Applications/Tailscale.app/Contents/MacOS/Tailscale`).
5. Admin console, the new machine, `...`: Disable key expiry.
6. Agent logins, as `orca` over SSH (`ssh orca@<tailnet-ip>`): `claude` (then `/exit`), `codex login --device-auth`, `agy`. Check: `claude -p "Reply with exactly: ok"` and `codex exec --skip-git-repo-check "Reply with exactly: ok" </dev/null`.
7. `gh auth login --with-token` with a fine-grained token scoped to the repos the box works on, then `gh auth setup-git`.
8. Pair Orca, in your own terminal (the URL is a credential, keep it out of chats): `ssh -t orca@<tailnet-ip> bash pair.sh`. Paste the URL into Orca: Settings, Remote Orca Servers, Add server. Press Enter on the box when paired.

## Migrate to a new box

1. Old box: commit and push every repo and worktree. Run the backup and read its warnings:
   `ssh orca@<old> bash -s < backup.sh > orca-box-$(date +%F).tgz`
2. New box: steps 1 to 7 above.
3. Clone each repo to the same path it had on the old box, then restore agent memory:
   `scp restore.sh orca@<new>:` then `ssh orca@<new> bash restore.sh < orca-box-YYYY-MM-DD.tgz`.
4. Step 8 to pair the new box. Recreate any Orca automations (they are not in the backup).
5. Retire the old box (below).

## Retire a box

1. On the box as `orca`: `claude auth logout`, `codex logout`, `/logout` inside `agy` (or remove the Antigravity grant at https://myaccount.google.com/permissions). Revoke the box's GitHub token.
2. In Orca on the Mac: remove the server entry.
3. Tailscale admin console: remove the machine. If it was a Tailnet Lock signing node, run `tailscale lock remove tlpub:<its key>` from the Mac first.
4. Wipe the disk.

Rebuild or retire one signing node at a time, so the other can sign the replacement. Disablement secrets are only for losing every signing node at once.

## Maintain

- Ubuntu security updates and Tailscale (apt repo) arrive through unattended-upgrades. Reboot when `/var/run/reboot-required` exists; the service comes back by itself, running agents do not.
- Claude Code updates itself. Codex and agy do not: rerun the Codex block of setup-box.sh with a new `CODEX_VERSION`, and `agy` updates via its own installer.
- Orca: install the newer `.deb` (`ORCA_VERSION=x.y.z` and the first block of setup-box.sh), then `systemctl --user restart orca-serve` as `orca`. Restart ends running agents.
- Health: `systemctl --user status orca-serve` as `orca`, `tailscale status`, `df -h /`, `sudo ufw status`.
- Backup: run the migrate step 1 command periodically; it holds agent memory only, code lives in git.
