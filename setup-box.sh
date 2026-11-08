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

# Node and Playwright with Chromium for the runtime user, so agents can screenshot pages themselves
# (screenshots through Orca's browser come back as one flat colour on this server).
su - "$RUN_USER" -c "NODE_VERSION=${NODE_VERSION:-22.23.4} PLAYWRIGHT_VERSION=${PLAYWRIGHT_VERSION:-1.65.0} bash -s" <<'PW'
set -euo pipefail
NODE_VERSION="${NODE_VERSION:-22.23.4}"
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-1.65.0}"

case "$(uname -m)" in x86_64) arch=x64 ;; aarch64) arch=arm64 ;; *) echo "unsupported arch" >&2; exit 1 ;; esac
tarball="node-v${NODE_VERSION}-linux-${arch}.tar.xz"
base="https://nodejs.org/dist/v${NODE_VERSION}"
node_dir="$HOME/.local/node-v${NODE_VERSION}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

if [ ! -x "$node_dir/bin/node" ]; then
  curl -fL -o "$tmp/$tarball" "$base/$tarball"
  curl -fL -o "$tmp/SHASUMS256.txt" "$base/SHASUMS256.txt"
  (cd "$tmp" && grep " $tarball\$" SHASUMS256.txt | sha256sum -c -)
  mkdir -p "$node_dir"
  tar -xJf "$tmp/$tarball" -C "$node_dir" --strip-components=1
fi
mkdir -p "$HOME/.local/bin"
for b in node npm npx; do ln -sf "$node_dir/bin/$b" "$HOME/.local/bin/$b"; done
export PATH="$HOME/.local/bin:$PATH"

npm install -g --prefix "$HOME/.local" "playwright@${PLAYWRIGHT_VERSION}"
playwright install chromium

PW

echo "done: orca-ide $(dpkg-query -W -f='${Version}' orca-ide), user=$RUN_USER"
echo "next: RUNBOOK.md, 'Set up a new box', agent logins"
