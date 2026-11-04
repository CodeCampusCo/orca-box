#!/usr/bin/env bash
# Run as root from the admin account on a fresh Ubuntu Server 24.04 host: sudo bash setup-host.sh [--lock-lan]
# Hardens the host, installs Tailscale and Multipass, loads the firewall that isolates the VM,
# creates the VM "orca" and runs setup-box.sh inside it (keep setup-box.sh next to this file).
# Tailscale login and Tailnet Lock signing stay manual. Without --lock-lan the LAN stays open to the host.
# Sizing overrides (Multipass syntax, e.g. 8G): CPUS, MEM, DISK. They apply only when the VM is created.
set -euo pipefail

VM=orca
ORCA_PORT=6768
SSH_PROXY_PORT=2222
fw=/usr/local/lib/orca-fw

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }
pkg_ok() { [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null)" == ii* ]]; }

# put PATH MODE < content: writes the file only when it differs and sets changed=1.
changed=0
put() {
  local tmp; tmp="$(mktemp)"; cat >"$tmp"
  if ! cmp -s "$tmp" "$1"; then install -D -m "$2" "$tmp" "$1"; changed=1; fi
  rm -f "$tmp"
}

lock=0
case "${1:-}" in "") ;; --lock-lan) lock=1 ;; *) die "usage: sudo bash setup-host.sh [--lock-lan]" ;; esac

# Preflight: nothing is changed before all of these pass.
[ "$(id -u)" -eq 0 ] || die "run as root: sudo bash setup-host.sh"
admin="${SUDO_USER:-}"
{ [ -n "$admin" ] && [ "$admin" != root ]; } || die "run with sudo from the admin account, not as root directly"
keys="$(getent passwd "$admin" | cut -d: -f6)/.ssh/authorized_keys"
grep -qvE '^[[:space:]]*(#|$)' "$keys" 2>/dev/null || die "$admin has no authorized SSH key; key-only login would lock everyone out"
. /etc/os-release
[ "${VERSION_ID:-}" = 24.04 ] || die "Ubuntu 24.04 required (found ${VERSION_ID:-unknown}); the hardening here is written for it"
[ -c /dev/kvm ] || die "/dev/kvm is missing; Multipass needs hardware virtualization (enable it in the firmware)"
[ -f "$(dirname "$(readlink -f "$0")")/setup-box.sh" ] || die "setup-box.sh must be next to this script"
if [ "$lock" = 1 ]; then
  command -v tailscale >/dev/null && tailscale ip -4 >/dev/null 2>&1 \
    || die "Tailscale is not up on this host; run 'tailscale up' and confirm SSH over the tailnet first"
fi
here="$(dirname "$(readlink -f "$0")")"

pkg_ok linux-generic-hwe-24.04 || warn "HWE kernel (linux-generic-hwe-24.04) is not installed; newer NICs may need it"

need=""
for p in ca-certificates curl nftables; do pkg_ok "$p" || need="$need $p"; done
if [ -n "$need" ]; then apt-get update; apt-get install -y --no-install-recommends $need; fi

# Grow the root LV into free space in its volume group.
src="$(findmnt -n -o SOURCE /)"
if vg="$(lvs --noheadings -o vg_name "$src" 2>/dev/null | tr -d ' ')" && [ -n "$vg" ]; then
  free="$(vgs --noheadings --units b --nosuffix -o vg_free "$vg" | tr -d ' ')"
  if [ "${free:-0}" -gt 0 ]; then lvextend -r -l +100%FREE "$src"; fi
fi

systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Drop-ins sort before 50-cloud-init.conf, which turns password login on; the first value read wins.
changed=0
put /etc/ssh/sshd_config.d/10-orca-keyonly.conf 644 <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
if [ "$changed" = 1 ]; then
  sshd -t || { rm -f /etc/ssh/sshd_config.d/10-orca-keyonly.conf; die "sshd config check failed; drop-in removed"; }
  systemctl reload ssh
fi

eval "$(apt-config shell ua APT::Periodic::Unattended-Upgrade/b ar Unattended-Upgrade::Automatic-Reboot/b)"
pkg_ok unattended-upgrades && [ "${ua:-false}" = true ] || warn "unattended-upgrades is not enabled"
[ "${ar:-false}" = false ] || warn "unattended-upgrades is set to reboot by itself; a reboot ends running agents"

# Tailscale from its apt repo, so unattended-upgrades and apt keep it current.
if ! command -v tailscale >/dev/null; then
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list
  apt-get update
  apt-get install -y tailscale
fi

# Firewall. Our rules live in their own tables, loaded by orca-fw; /etc/nftables.conf is not used (it flushes the whole ruleset).
put "$fw/orca-isolation.nft" 644 <<'EOF'
# Own table; loading replaces only this table. lan4/lan6 are filled by orca-fw-load.sh
# from the host's connected networks. Multipass bridges are matched by name pattern.
table inet orca_isolation
delete table inet orca_isolation
table inet orca_isolation {
	set lan4 { type ipv4_addr; flags interval; }
	set lan6 { type ipv6_addr; flags interval; }
	set nonglobal4 {
		type ipv4_addr; flags interval
		elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16,
			172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16, 198.18.0.0/15, 224.0.0.0/3 }
	}

	chain forward {
		type filter hook forward priority -10; policy accept;
		iifname != "mpqemubr*" return
		# Replies to connections opened toward the VM pass; VM-initiated flows fall through to the drops.
		ct state established,related accept
		ip daddr @nonglobal4 counter drop
		ip daddr @lan4 counter drop
		ip6 daddr != 2000::/3 counter drop
		ip6 daddr @lan6 counter drop
	}

	chain input {
		type filter hook input priority -10; policy accept;
		iifname != "mpqemubr*" return
		ct state established,related accept
		udp dport 67 accept
		meta l4proto { tcp, udp } th dport 53 accept
		icmpv6 type { nd-router-solicit, nd-neighbor-solicit, nd-neighbor-advert } accept
		counter drop
	}
}
EOF
put "$fw/orca-input.nft" 644 <<'EOF'
# Host input policy: nothing is open to the LAN. Tailnet, loopback, replies and the VM bridge's DHCP/DNS are accepted.
table inet orca_input
delete table inet orca_input
table inet orca_input {
	chain input {
		type filter hook input priority filter; policy drop;
		iif lo accept
		ct state established,related accept
		ct state invalid drop
		iifname "tailscale0" accept
		# Multipass bridges: only what the VM needs from the host (orca_isolation drops the rest first).
		iifname "mpqemubr*" udp dport 67 accept
		iifname "mpqemubr*" meta l4proto { tcp, udp } th dport 53 accept
		# Host's own address configuration on the LAN: DHCPv4/v6 renewals and IPv6 neighbour/router discovery.
		udp sport 67 udp dport 68 accept
		udp sport 547 udp dport 546 accept
		icmpv6 type { nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept
	}
}
EOF
put "$fw/orca-fw-load.sh" 755 <<'EOF'
#!/bin/bash
# Idempotent: (re)loads orca_isolation with this host's current LAN prefixes, and orca_input only once /etc/orca-fw/lock-lan exists.
set -eu
dir=$(dirname "$(readlink -f "$0")")
# Connected (on-link) prefixes of every interface except loopback, Multipass bridges and Tailscale.
lan4=$(ip -4 -o route show scope link | awk '$1 ~ /\// && $3 !~ /^(lo|mpqemubr.*|tailscale0)$/ {print $1}' | paste -sd,)
lan6=$(ip -6 -o route show | awk '$1 ~ /^[23][0-9a-f][0-9a-f][0-9a-f]:/ && $0 !~ / via / && $3 !~ /^(lo|mpqemubr.*|tailscale0)$/ {print $1}' | paste -sd,)
{
  cat "$dir/orca-isolation.nft"
  [ -n "$lan4" ] && echo "add element inet orca_isolation lan4 { $lan4 }"
  [ -n "$lan6" ] && echo "add element inet orca_isolation lan6 { $lan6 }"
  true
} | nft -f -
if [ -e /etc/orca-fw/lock-lan ]; then nft -f "$dir/orca-input.nft"; fi
echo "loaded; lan4=[$lan4] lan6=[$lan6] input=$([ -e /etc/orca-fw/lock-lan ] && echo locked || echo open)"
EOF
# No ExecStop: stopping the unit leaves the rules in place, so it fails closed.
# ExecReload exists because restarting this unit would restart multipassd (and the VM) through its Requires=.
put /etc/systemd/system/orca-fw.service 644 <<EOF
[Unit]
Description=Orca box firewall: VM isolation and host input policy
Wants=network-online.target
After=network-online.target
Before=snap.multipass.multipassd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$fw/orca-fw-load.sh
ExecReload=$fw/orca-fw-load.sh

[Install]
WantedBy=multi-user.target
EOF
# A failed or stopped firewall unit must keep the VM from running.
put /etc/systemd/system/snap.multipass.multipassd.service.d/orca-fw.conf 644 <<'EOF'
[Unit]
Requires=orca-fw.service
After=orca-fw.service
EOF
systemctl daemon-reload
systemctl enable orca-fw.service
systemctl reload-or-restart orca-fw.service

# Multipass, installed after the firewall and its drop-in are in place; refreshes are manual (see RUNBOOK.md).
snap list multipass >/dev/null 2>&1 || snap install multipass
snap refresh --hold multipass
for _ in $(seq 30); do multipass list >/dev/null 2>&1 && break; sleep 2; done
multipass list >/dev/null || die "the Multipass daemon does not answer"

if ! multipass info "$VM" >/dev/null 2>&1; then
  mem=$(( $(awk '/^MemTotal/ {print $2}' /proc/meminfo) / 1048576 - 2 ))
  disk=$(( $(df -BG --output=size / | tail -1 | tr -dc 0-9) - 60 ))
  { [ -n "${MEM:-}" ] || [ "$mem" -ge 1 ]; } || die "too little RAM for the default VM size; set MEM"
  { [ -n "${DISK:-}" ] || [ "$disk" -ge 1 ]; } || die "too little disk for the default VM size; set DISK"
  { echo '#cloud-config'; echo 'ssh_authorized_keys:'
    grep -vE '^[[:space:]]*(#|$)' "$keys" | sed "s/'/''/g; s/^/  - '/; s/\$/'/"
  } | multipass launch 24.04 --name "$VM" --cpus "${CPUS:-$(nproc)}" --memory "${MEM:-${mem}G}" --disk "${DISK:-${disk}G}" --cloud-init -
fi
multipass list --format csv | grep -q "^$VM,Running," || multipass start "$VM"
multipass exec "$VM" -- cloud-init status --wait >/dev/null || true

# The VM's default gateway is the host's bridge address; Multipass subnets are /24.
gw="$(multipass exec "$VM" -- ip -4 -o route show default | awk '{print $3; exit}')"
[ -n "$gw" ] || die "the VM has no default route"
pin="${gw%.*}.250"
# Added next to DHCP: Multipass finds the VM by its DHCP lease, so pure static breaks multipass exec.
if ! multipass exec "$VM" -- ip -4 -o addr show | grep -q " $pin/"; then
  printf 'network:\n  version: 2\n  ethernets:\n    eth0:\n      addresses: [%s/24]\n' "$pin" \
    | multipass exec "$VM" -- sudo sh -c 'umask 077; cat > /etc/netplan/60-orca-pin.yaml'
  multipass exec "$VM" -- sudo netplan apply
fi
for _ in $(seq 15); do timeout 3 bash -c "exec 3<>/dev/tcp/$pin/22" 2>/dev/null && break; sleep 2; done
timeout 3 bash -c "exec 3<>/dev/tcp/$pin/22" 2>/dev/null || die "the VM does not answer SSH on $pin"

# Tailnet-facing proxies. Not WantedBy sockets.target: orca-fw waits for network-online, which would make an ordering cycle.
# The sockets bind all addresses so they can start before tailscaled; orca_input admits only tailscale0 to them.
changed=0
for p in "orca $ORCA_PORT $ORCA_PORT" "ssh 22 $SSH_PROXY_PORT"; do
  set -- $p; name=$1; vmport=$2; listen=$3
  put "/etc/systemd/system/orca-proxy-$name.socket" 644 <<EOF
[Unit]
Description=Tailnet-facing proxy socket for VM port $vmport
DefaultDependencies=no
After=orca-fw.service
Requires=orca-fw.service
Conflicts=shutdown.target
Before=shutdown.target

[Socket]
ListenStream=0.0.0.0:$listen
FreeBind=true

[Install]
WantedBy=multi-user.target
EOF
  put "/etc/systemd/system/orca-proxy-$name.service" 644 <<EOF
[Unit]
Description=Proxy to the VM's port $vmport
Requires=orca-proxy-$name.socket
After=orca-proxy-$name.socket orca-fw.service

[Service]
ExecStart=/usr/lib/systemd/systemd-socket-proxyd --exit-idle-time=0 $pin:$vmport
DynamicUser=yes
PrivateTmp=yes
EOF
done
systemctl daemon-reload
systemctl enable --now orca-proxy-orca.socket orca-proxy-ssh.socket
if [ "$changed" = 1 ]; then systemctl restart orca-proxy-orca.socket orca-proxy-ssh.socket; fi

# setup-box.sh runs in the VM as its login user via sudo (it reads SUDO_USER for the authorized keys).
envs=()
for v in ORCA_VERSION CODEX_VERSION RUN_USER; do [ -z "${!v:-}" ] || envs+=("$v=${!v}"); done
multipass exec "$VM" -- sh -c 'cat > setup-box.sh' < "$here/setup-box.sh"
multipass exec "$VM" -- sudo env "${envs[@]}" bash setup-box.sh </dev/null

# Last, so a failure above never leaves the LAN closed on a half-built host. Existing LAN sessions keep working.
if [ "$lock" = 1 ]; then
  install -d /etc/orca-fw
  touch /etc/orca-fw/lock-lan
  systemctl reload orca-fw.service
fi

echo "done: VM $VM at $pin, proxied on tailscale0 ports $ORCA_PORT (Orca) and $SSH_PROXY_PORT (VM SSH)"
if [ -e /etc/orca-fw/lock-lan ]; then
  echo "LAN: closed (reloaded now and at every boot)"
else
  echo "LAN: still open to this host. After 'tailscale up' and a working SSH over the tailnet, rerun: sudo bash setup-host.sh --lock-lan"
fi
echo "next: RUNBOOK.md, 'Set up a new box' (tailscale up, sign the node, disable key expiry, lock the LAN, agent logins)"
