#!/usr/bin/env bash
# Run as root (sudo) on a fresh Ubuntu Server 24.04 box: sudo bash setup-box.sh
# Installs Orca and the agent CLIs for a non-root runtime user, Tailscale, and the firewall,
# then installs Orca as a systemd user service. Interactive steps are in RUNBOOK.md.
set -euo pipefail

ORCA_VERSION="${ORCA_VERSION:-1.4.245}"
CODEX_VERSION="${CODEX_VERSION:-0.166.0}"
RUN_USER="${RUN_USER:-orca}"
ORCA_PORT=6768

arch="$(dpkg --print-architecture)"   # amd64 or arm64; both have release assets
deb="orca-ide_${ORCA_VERSION}_${arch}.deb"

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl git jq ufw gh

curl -fL -o "/tmp/${deb}" "https://github.com/stablyai/orca/releases/download/v${ORCA_VERSION}/${deb}"
apt-get install -y "/tmp/${deb}"

# Tailscale from its apt repo, so unattended-upgrades and apt keep it current.
. /etc/os-release
curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list
apt-get update
apt-get install -y tailscale

id "$RUN_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$RUN_USER"
install -d -m 700 -o "$RUN_USER" -g "$RUN_USER" "/home/$RUN_USER/.ssh"
for k in /root/.ssh/authorized_keys "/home/${SUDO_USER:-ubuntu}/.ssh/authorized_keys"; do
  if [ -s "$k" ]; then install -m 600 -o "$RUN_USER" -g "$RUN_USER" "$k" "/home/$RUN_USER/.ssh/authorized_keys"; break; fi
done
loginctl enable-linger "$RUN_USER"

su - "$RUN_USER" -c 'curl -fsSL https://claude.ai/install.sh | bash'

# Codex needs all three binaries from the same release; the CLI fails without code-mode-host.
case "$arch" in amd64) triple=x86_64-unknown-linux-musl ;; arm64) triple=aarch64-unknown-linux-musl ;; esac
install -d -o "$RUN_USER" -g "$RUN_USER" "/home/$RUN_USER/.local/bin"
for n in codex codex-code-mode-host codex-exec-server; do
  curl -fsSL "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/${n}-${triple}.tar.gz" | tar -xzC /tmp
  install -m 755 -o "$RUN_USER" -g "$RUN_USER" "/tmp/${n}-${triple}" "/home/$RUN_USER/.local/bin/$n"
done

su - "$RUN_USER" -c 'curl -fsSL -o /tmp/agy-install.sh https://antigravity.google/cli/install.sh && bash /tmp/agy-install.sh'

# SSH from anywhere, everything over the tailnet, Orca's port from the LAN as a fallback.
gw="$(ip route | awk '/^default/ {print $3; exit}')"
ufw default deny incoming
ufw allow OpenSSH
ufw allow in on tailscale0
ufw allow from "${gw%.*}.0/24" to any port "$ORCA_PORT" proto tcp
ufw --force enable

# Pairing is off in the service; pair.sh opens it briefly.
uid="$(id -u "$RUN_USER")"
until [ -d "/run/user/$uid" ]; do sleep 1; done
su - "$RUN_USER" -c "XDG_RUNTIME_DIR=/run/user/$uid orca-ide serve service install --port $ORCA_PORT"

echo "done: orca-ide $(dpkg-query -W -f='${Version}' orca-ide), tailscale $(tailscale version | head -1), user=$RUN_USER"
echo "next: RUNBOOK.md, 'Set up a new box' step 3 (tailscale up)"
