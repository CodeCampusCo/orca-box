#!/usr/bin/env bash
# Run as root (sudo) inside the Orca VM, normally by setup-host.sh: sudo bash setup-box.sh
# Installs Orca and the agent CLIs for a non-root runtime user and the firewall,
# then installs Orca as a systemd user service. Interactive steps are in RUNBOOK.md.
# Tailscale lives on the host. On a standalone box, SSH and Orca are then reachable from its own subnet only.
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

id "$RUN_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$RUN_USER"
install -d -m 700 -o "$RUN_USER" -g "$RUN_USER" "/home/$RUN_USER/.ssh"
# The invoking user first: on cloud images root's file holds a forced "log in as ubuntu" command.
for k in "/home/${SUDO_USER:-ubuntu}/.ssh/authorized_keys" /root/.ssh/authorized_keys; do
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

# Interactive non-login shells read only .bashrc, so ~/.local/bin must be added there too.
path_line='export PATH="$HOME/.local/bin:$PATH"'
grep -qxF "$path_line" "/home/$RUN_USER/.bashrc" || echo "$path_line" >> "/home/$RUN_USER/.bashrc"

# SSH and Orca only from the gateway's subnet: the host's proxies connect from the VM's bridge.
gw="$(ip route | awk '/^default/ {print $3; exit}')"
ufw default deny incoming
ufw allow from "${gw%.*}.0/24" to any port 22,"$ORCA_PORT" proto tcp
ufw --force enable

# Pairing is off in the service; pair.sh opens it briefly.
uid="$(id -u "$RUN_USER")"
until [ -d "/run/user/$uid" ]; do sleep 1; done
su - "$RUN_USER" -c "XDG_RUNTIME_DIR=/run/user/$uid orca-ide serve service install --port $ORCA_PORT"

# agent-browser (bundled with Orca) with its own Chrome, so agents can screenshot pages themselves
# (screenshots through Orca's browser come back as one flat colour on this server).
case "$(uname -m)" in x86_64) ab_arch=x64 ;; aarch64) ab_arch=arm64 ;; *) echo "unsupported arch" >&2; exit 1 ;; esac
ab="/opt/Orca/resources/agent-browser-linux-${ab_arch}"
su - "$RUN_USER" -c "mkdir -p ~/.local/bin && ln -sf '$ab' ~/.local/bin/agent-browser && '$ab' install"

echo "done: orca-ide $(dpkg-query -W -f='${Version}' orca-ide), user=$RUN_USER"
echo "next: RUNBOOK.md, 'Set up a new box', agent logins"
