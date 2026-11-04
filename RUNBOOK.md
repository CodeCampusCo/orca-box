# Orca box runbook

A headless Ubuntu host runs one Multipass VM, `orca`. In the VM, Orca runs as a systemd user service for a non-root user (`orca`), with Claude Code and Codex as agents. Tailscale runs on the host (Tailnet Lock on); two proxies on the host forward tailnet ports to the VM. The Mac reaches the box over Tailscale only, and the Orca desktop app pairs with it.

Box-specific values (tailnet address, LAN IP) are not kept here; read them with `tailscale ip -4` on the host or from the Tailscale admin console. Below, `<ts>` is the host's tailnet address.

Ports on `<ts>`: 22 is the host (admin user), 2222 is the VM's SSH (`ssh -p 2222 orca@<ts>`, `scp -P 2222`), 6768 is Orca. The constants live at the top of `setup-host.sh`.

Change the box by editing the scripts and rerunning `sudo bash setup-host.sh` on the host, not by hand.

## Set up a new box

1. Install Ubuntu Server 24.04 with the HWE kernel (some NICs need kernel 6.13 or newer; `setup-host.sh` warns if it is missing), OpenSSH and the Mac's public key for the admin user. Find the host's LAN IP.
2. From the Mac: `scp setup-host.sh setup-box.sh <admin>@<lan-ip>:` then `ssh -t <admin>@<lan-ip> sudo bash setup-host.sh`. It hardens the host, installs Tailscale and Multipass, builds the VM and runs `setup-box.sh` in it. The LAN stays open to the host until step 6.
3. On the host, as admin: `sudo tailscale up --hostname <name>`, open the printed URL and log in.
4. Tailnet Lock: the new node starts locked out. In the admin console, Machines, choose Sign node for it (or run the `tailscale lock sign ...` command the host's `tailscale lock status` prints, from the Mac CLI at `/Applications/Tailscale.app/Contents/MacOS/Tailscale`).
5. Admin console, the new machine, `...`: Disable key expiry.
6. Check from the Mac that `ssh <admin>@<ts>` and `ssh -p 2222 orca@<ts>` both work. Then close the LAN, over the tailnet: `ssh -t <admin>@<ts> sudo bash setup-host.sh --lock-lan`. Afterwards the LAN reaches nothing on the host; check that `ssh <admin>@<lan-ip>` times out.
7. Agent logins, as `orca` (`ssh -p 2222 orca@<ts>`): `claude` (then `/exit`), `codex login --device-auth`. Check: `claude -p "Reply with exactly: ok"` and `codex exec --skip-git-repo-check "Reply with exactly: ok" </dev/null`.
8. `gh auth login --with-token` with a fine-grained token scoped to the repos the box works on, then `gh auth setup-git`.
9. Pair Orca, in your own terminal (the URL is a credential, keep it out of chats): `scp -P 2222 pair.sh orca@<ts>:` then `ssh -t -p 2222 orca@<ts> bash pair.sh <ts>`. Paste the URL into Orca: Settings, Remote Orca Servers, Add server. Press Enter on the box when paired.

## Migrate to a new box

1. Old box: commit and push every repo and worktree. Run the backup and read its warnings:
   `ssh -p 2222 orca@<old-ts> bash -s < backup.sh > orca-box-$(date +%F).tgz`
2. New box: steps 1 to 8 above.
3. Clone each repo to the same path it had on the old box, then restore agent memory:
   `scp -P 2222 restore.sh orca@<new-ts>:` then `ssh -p 2222 orca@<new-ts> bash restore.sh < orca-box-YYYY-MM-DD.tgz`.
4. Step 9 to pair the new box. Recreate any Orca automations (they are not in the backup).
5. Retire the old box (below).

## Rebuild the VM on the same host

The VM is never resized or repaired; it is rebuilt, and the node keeps its Tailscale signature. Back up (migrate step 1), then on the host: `sudo multipass delete --purge orca` and `sudo bash setup-host.sh`. On the Mac: `ssh-keygen -R "[<ts>]:2222"`. Then steps 7 to 9 and migrate step 3.

## Retire a box

1. In the VM as `orca`: `claude auth logout`, `codex logout`. Revoke the box's GitHub token.
2. In Orca on the Mac: remove the server entry.
3. Tailscale admin console: remove the host's machine. If it was a Tailnet Lock signing node, run `tailscale lock remove tlpub:<its key>` from the Mac first.
4. Wipe the host's disk (this destroys the VM with it).

Rebuild or retire one signing node at a time, so the other can sign the replacement. Disablement secrets are only for losing every signing node at once.

## Maintain

- Ubuntu security updates and Tailscale (apt repo) arrive through unattended-upgrades on the host; the VM updates itself the same way. Reboot when `/var/run/reboot-required` exists. After a host reboot the firewall, proxies, VM and Orca service come back by themselves; running agents do not.
- Claude Code updates itself. Codex and Orca are pinned: rerun the host script with the new version, which reruns `setup-box.sh` in the VM, then `systemctl --user restart orca-serve` as `orca` (restart ends running agents): `sudo env CODEX_VERSION=x.y.z ORCA_VERSION=x.y.z bash setup-host.sh`.
- Multipass is held, because a refresh restarts the VM. To update on purpose: `sudo snap refresh --unhold multipass`, `sudo snap refresh multipass`, check isolation (`sudo nft list table inet orca_isolation` shows the table; from the VM, `ping -c1 -W2 <lan-gateway>` must fail), then `sudo snap refresh --hold multipass`.
- Health: on the host `systemctl status orca-fw`, `tailscale status`, `df -h /`; in the VM as `orca` `systemctl --user status orca-serve`; in the VM `sudo ufw status`.
- Backup: run the migrate step 1 command periodically; it holds agent memory only, code lives in git.
- Recovery has no network path besides Tailscale: use a monitor and keyboard on the host. If the tailnet is broken, log in as admin and either fix Tailscale or reopen the LAN with `sudo rm /etc/orca-fw/lock-lan; sudo nft delete table inet orca_input`. Then rerun `sudo bash setup-host.sh --lock-lan` once SSH over the tailnet works again.
