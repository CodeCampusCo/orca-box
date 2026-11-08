# Orca box runbook

A headless Ubuntu host runs one Multipass VM, `orca`. In the VM, Orca runs as a systemd user service for a non-root user (`orca`), with Claude Code and Codex installed as agents (others can be added in the last step). Tailscale runs on the host (Tailnet Lock on); two proxies on the host forward tailnet ports to the VM. Your computer reaches the box over Tailscale only, and the Orca desktop app pairs with it.

Box-specific values (tailnet address, LAN IP) are not kept here; read them with `tailscale ip -4` on the host or from the Tailscale admin console. Below, `<ts>` is the host's tailnet address.

Ports on `<ts>`: 22 is the host (admin user), 2222 is the VM's SSH (`ssh -p 2222 orca@<ts>`, `scp -P 2222`), 6768 is Orca. The constants live at the top of `setup-host.sh`.

Change the box by editing the scripts and rerunning `sudo bash setup-host.sh` on the host, not by hand.

## Guided setup (for the agent)

You walk the user from blank hardware to a paired Orca with the agents they use. Open by presenting the whole list below, numbered, with the user-only steps marked, then do one step at a time and wait for the user's confirmation. Speak the user's language. Never ask for or store passwords, tokens, pairing URLs or login URLs. Ask before any reboot, any SSH, firewall or kernel change, and before running anything on the box that is not in this repo's scripts. Follow the numbered steps in "Set up a new box" for the commands; do not improvise.

Steps (U = only the user can do it):

1. U: write the Ubuntu Server 24.04 ISO to a USB stick.
2. U: firmware settings: hardware virtualization on, power on after power failure, no sleep or idle power-off.
3. U: install from the USB: the HWE kernel option, OpenSSH server with the user's public key (installer key import or paste), the default LVM layout, an admin user name of their choice, wired network. Note the LAN IP shown at the end.
4. Check key-based SSH to the host works. Then the one-time update and reboot check from "Set up a new box" step 1 (U: types the `sudo` password in their own terminal, which is why the command uses `ssh -t`).
5. Copy the scripts and run `setup-host.sh` ("Set up a new box" step 2). U: `sudo` password.
6. U: `sudo tailscale up --hostname <name>` and the login (step 3), Tailnet Lock signing (step 4), disable key expiry (step 5).
7. Check SSH over the tailnet to the host and to the VM, then run `--lock-lan` and confirm the LAN times out (step 6).
8. U: GitHub token (step 7).
9. U: pairing in their own terminal (step 8).
10. U: agent logins (step 9). Last, because the user may not use the two agents the scripts install: ask which agents they use before logging in anything.

Agent does: prepare files, run read-only checks over key-based SSH, explain each step before it runs, verify the result. User does: everything marked U, because each needs their password, account or produces a credential.

Checks, after each phase:

- Step 4: `ls /var/run/reboot-required` over SSH; after a reboot the host answers SSH again.
- Step 5: the script ends with a `done: VM orca at ...` line and the `LAN: still open` hint. It must not print `WARNING` about the HWE kernel. `sudo multipass list` shows `orca` Running.
- Step 6: `tailscale status` lists the host without a lock warning; `tailscale ip -4` prints the address `<ts>`.
- Step 7: `ssh <admin>@<ts>` and `ssh -p 2222 orca@<ts>` both log in; afterwards `ssh <admin>@<lan-ip>` times out. On the host `systemctl status orca-fw` is active.
- Step 8: in the VM as `orca`, `gh auth status` shows a login.
- Step 9: in the VM as `orca`, `systemctl --user status orca-serve` is active after pairing.
- Step 10: the one-line check for each agent prints `ok`.

On any failure: stop, show the user the exact error, and do not work around it. Do not rerun with changed flags, edit scripts on the box or skip a check. Known risk points:

- The first `multipass` call as root may not be trusted automatically on a fresh install (tested once on a fresh install, see the design doc); report any failure and ask before retrying `setup-host.sh`, which is safe to rerun.
- The LAN stays open until `--lock-lan`. Run it only after SSH over the tailnet works, from the tailnet and not the LAN address.
- Never remove the HWE kernel and never edit netplan on the host.
- The recovery path is a monitor and keyboard on the host (see "Maintain").

## Set up a new box

1. Install Ubuntu Server 24.04 with the HWE kernel (some NICs need kernel 6.13 or newer; `setup-host.sh` warns if it is missing), OpenSSH and your computer's public key for the admin user. Find the host's LAN IP. Then update once, because the script does not (a snapd update during the Multipass install would restart the daemon): `ssh -t <admin>@<lan-ip> 'sudo apt update && sudo apt full-upgrade -y'`, and reboot if `/var/run/reboot-required` exists.
2. From your computer: `scp setup-host.sh setup-box.sh <admin>@<lan-ip>:` then `ssh -t <admin>@<lan-ip> sudo bash setup-host.sh`. It hardens the host, installs Tailscale and Multipass, builds the VM and runs `setup-box.sh` in it. The LAN stays open to the host until step 6.
3. On the host, as admin: `sudo tailscale up --hostname <name>`, open the printed URL and log in.
4. Tailnet Lock: the new node starts locked out. In the admin console, Machines, choose Sign node for it (or run the `tailscale lock sign ...` command the host's `tailscale lock status` prints, from a signing node's Tailscale CLI).
5. Admin console, the new machine, `...`: Disable key expiry.
6. Check from your computer that `ssh <admin>@<ts>` and `ssh -p 2222 orca@<ts>` both work. Then close the LAN, over the tailnet: `ssh -t <admin>@<ts> sudo bash setup-host.sh --lock-lan`. Afterwards the LAN reaches nothing on the host; check that `ssh <admin>@<lan-ip>` times out.
7. `gh auth login --with-token` with a fine-grained token scoped to the repos the box works on, then `gh auth setup-git`.
8. Pair Orca, in your own terminal (the URL is a credential, keep it out of chats): `scp -P 2222 pair.sh orca@<ts>:` then `ssh -t -p 2222 orca@<ts> bash pair.sh <ts>`. Paste the URL into Orca: Settings, Remote Orca Servers, Add server. For the mobile app (iPhone on the same tailnet) add `--mobile-pairing` after `<ts>`, then in the app choose Pair and scan the QR code. Press Enter on the box when paired.
9. Agents, last, as `orca` (`ssh -t -p 2222 orca@<ts>`). The scripts install Claude Code and Codex: log in with `claude` (then `/exit`) and `codex login --device-auth`; check with `claude -p "Reply with exactly: ok"` and `codex exec --skip-git-repo-check "Reply with exactly: ok" </dev/null`. Orca starts Claude Code in automations with permission prompts off, and the first such run stops at a one-time "Bypass Permissions" confirmation; until someone accepts it in that run's terminal in Orca ("Yes, I accept"), the run stays `dispatched`. Accept it once after the first Claude automation is created. If the user wants a different or additional agent, ask which one, then find its current install and login instructions (its own documentation) and help install and log in as `orca` in the VM, with a one-line prompt as the check. Anything installed by hand is lost when the VM is rebuilt: offer to add its install to `setup-box.sh`, and make that script change first.

## Migrate to a new box

1. Old box: commit and push every repo and worktree. Run the backup and read its warnings:
   `ssh -p 2222 orca@<old-ts> bash -s < backup.sh > orca-box-$(date +%F).tgz`
2. New box: steps 1 to 7 above, then 9.
3. Clone each repo to the same path it had on the old box, then restore agent memory:
   `scp -P 2222 restore.sh orca@<new-ts>:` then `ssh -p 2222 orca@<new-ts> bash restore.sh < orca-box-YYYY-MM-DD.tgz`.
4. Step 8 to pair the new box. The restore recreates Orca automations that create a new worktree per run, for repos already cloned at their old path; it warns about the rest, which you recreate by hand with `orca-ide automations create`.
5. Retire the old box (below).

## Rebuild the VM on the same host

The VM is never resized or repaired; it is rebuilt, and the node keeps its Tailscale signature. Back up (migrate step 1), then on the host: `sudo multipass delete --purge orca` and `sudo bash setup-host.sh`. On your computer: `ssh-keygen -R "[<ts>]:2222"`. Then steps 7 to 9 and migrate step 3.

## Retire a box

1. In the VM as `orca`: `claude auth logout`, `codex logout`, and log out of any other agent. Revoke the box's GitHub token.
2. In Orca on your computer: remove the server entry.
3. Tailscale admin console: remove the host's machine. The host is not a signing node, so no `tailscale lock remove` is needed; the console refuses to remove a signing node, in which case something is wrong.
4. Wipe the host's disk (this destroys the VM with it).

## Tailnet Lock signing nodes

Signing nodes hold the lock's private key and sign new nodes. They are the owner's personal devices and never a box that runs agents: the box is assumed compromisable, and a signing key on it would let an attacker sign their own node into the tailnet.

Keep more than one signing node when possible, and change them one at a time, so one lost device does not stop new nodes from being signed. To retire a signing node: `tailscale lock remove tlpub:<its key>` from another signing node (the last key cannot be removed), then remove the machine in the console. Keep the disablement secrets in a password manager: they are the only way back if every signing node is lost.

## Maintain

- Ubuntu security updates and Tailscale (apt repo) arrive through unattended-upgrades on the host; the VM updates itself the same way. Reboot when `/var/run/reboot-required` exists. After a host reboot the firewall, proxies, VM and Orca service come back by themselves; running agents do not.
- Claude Code updates itself. Codex and Orca are pinned: rerun the host script with the new version, which reruns `setup-box.sh` in the VM, then `systemctl --user restart orca-serve` as `orca` (restart ends running agents): `sudo env CODEX_VERSION=x.y.z ORCA_VERSION=x.y.z bash setup-host.sh`.
- `setup-box.sh` runs `orca-serve` on Orca's Electron runtime (`ORCA_SERVE_RUNTIME=electron`, a systemd drop-in). The default Node runtime does not advertise `browser.screencast.v1`: the app then refuses to open browser tabs on the box ("paired runtime does not support browser streaming") and `orca screenshot` returns a flat colour. Check with `orca status --json`: the capability list must contain `browser.screencast.v1`.
- Multipass is held, because a refresh restarts the VM. To update on purpose: `sudo snap refresh --unhold multipass`, `sudo snap refresh multipass`, check isolation (`sudo nft list table inet orca_isolation` shows the table; from the VM, `ping -c1 -W2 <lan-gateway>` must fail), then `sudo snap refresh --hold multipass`.
- Health: on the host `systemctl status orca-fw`, `tailscale status`, `df -h /`; in the VM as `orca` `systemctl --user status orca-serve`; in the VM `sudo ufw status`.
- Backup: run the migrate step 1 command periodically; it holds agent memory only, code lives in git.
- Recovery has no network path besides Tailscale: use a monitor and keyboard on the host. If the tailnet is broken, log in as admin and either fix Tailscale or reopen the LAN with `sudo rm /etc/orca-fw/lock-lan; sudo nft delete table inet orca_input`. Then rerun `sudo bash setup-host.sh --lock-lan` once SSH over the tailnet works again.
