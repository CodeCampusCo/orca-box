#!/usr/bin/env bash
# Run as root (sudo) inside the Orca VM, normally by setup-host.sh: sudo bash setup-box.sh
# Installs Orca and the agent CLIs for a non-root runtime user and the firewall,
# then installs Orca as a systemd user service. Interactive steps are in RUNBOOK.md.
# Tailscale lives on the host. On a standalone box, SSH and Orca are then reachable from its own subnet only.
set -euo pipefail

ORCA_VERSION="${ORCA_VERSION:-1.4.247}"
CODEX_VERSION="${CODEX_VERSION:-0.166.0}"
OPENCODE_VERSION="${OPENCODE_VERSION:-2.3.0}"
RUN_USER="${RUN_USER:-orca}"
ORCA_PORT=6768

arch="$(dpkg --print-architecture)"   # amd64 or arm64; both have release assets
deb="orca-ide_${ORCA_VERSION}_${arch}.deb"

apt-get update
# libatomic1: Node binaries from nvm link libatomic.so.1, which the VM image lacks.
apt-get install -y --no-install-recommends ca-certificates curl git jq ufw gh libatomic1

curl -fL -o "/tmp/${deb}" "https://github.com/stablyai/orca/releases/download/v${ORCA_VERSION}/${deb}"
apt-get install -y "/tmp/${deb}"

id "$RUN_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$RUN_USER"
install -d -m 700 -o "$RUN_USER" -g "$RUN_USER" "/home/$RUN_USER/.ssh"
# The invoking user first: on cloud images root's file holds a forced "log in as ubuntu" command.
for k in "/home/${SUDO_USER:-ubuntu}/.ssh/authorized_keys" /root/.ssh/authorized_keys; do
  if [ -s "$k" ]; then install -m 600 -o "$RUN_USER" -g "$RUN_USER" "$k" "/home/$RUN_USER/.ssh/authorized_keys"; break; fi
done
loginctl enable-linger "$RUN_USER"
# /dev/kvm for agents' hardware-accelerated emulators (needs nested virtualization from the host).
if getent group kvm >/dev/null; then usermod -aG kvm "$RUN_USER"; fi

su - "$RUN_USER" -c 'curl -fsSL https://claude.ai/install.sh | bash'

# Codex needs all three binaries from the same release; the CLI fails without code-mode-host.
case "$arch" in amd64) triple=x86_64-unknown-linux-musl ;; arm64) triple=aarch64-unknown-linux-musl ;; esac
install -d -o "$RUN_USER" -g "$RUN_USER" "/home/$RUN_USER/.local/bin"
for n in codex codex-code-mode-host codex-exec-server; do
  curl -fsSL "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/${n}-${triple}.tar.gz" | tar -xzC /tmp
  install -m 755 -o "$RUN_USER" -g "$RUN_USER" "/tmp/${n}-${triple}" "/home/$RUN_USER/.local/bin/$n"
done

# OpenCode V2 only: https://opencode.ai/install is V1, which takes the same `opencode` name and cannot open V2's database.
# The V2 installer adds an `opencode2` alias each run; the box keeps the one name.
# The installer's PATH line goes into .bashrc, which non-interactive shells skip; Ubuntu's ~/.profile already puts ~/.local/bin on PATH.
su - "$RUN_USER" -c "set -o pipefail; curl -fsSL https://opencode.ai/v2/install | bash -s -- --version ${OPENCODE_VERSION} --no-modify-path && rm -f ~/.opencode/bin/opencode2 && ln -sf ~/.opencode/bin/opencode ~/.local/bin/opencode"

su - "$RUN_USER" -c "set -o pipefail; curl -fsSL https://x.ai/cli/install.sh | bash"

# Interactive non-login shells read only .bashrc, so ~/.local/bin must be added there too.
path_line='export PATH="$HOME/.local/bin:$PATH"'
grep -qxF "$path_line" "/home/$RUN_USER/.bashrc" || echo "$path_line" >> "/home/$RUN_USER/.bashrc"

# Athena, the agents' shared knowledge base, as the MCP server `athena` for Claude, Codex, OpenCode and Grok.
# Skipped until the owner places ~/.config/athena/url and ~/.config/athena/token.
# Every agent reads the token from that file when it connects; Orca does not pass env vars to agents reliably.
su - "$RUN_USER" -c 'bash -s' <<'EOF'
set -euo pipefail
a="$HOME/.config/athena"
if ! [ -s "$a/url" ] || ! [ -s "$a/token" ]; then echo "athena: $a/url or token missing, skipped"; exit 0; fi
for f in url token; do v="$(tr -d '[:space:]' < "$a/$f")"; printf %s "$v" > "$a/$f"; done
chmod 600 "$a/url" "$a/token"
url="$(cat "$a/url")"

# The header as a JSON object: the output both Claude's headersHelper and Codex's http_headers_helper expect.
cat > "$a/headers" <<'H'
#!/bin/sh
printf '{"Authorization":"Bearer %s"}' "$(cat "$HOME/.config/athena/token")"
H
chmod 700 "$a/headers"

claude mcp remove -s user athena >/dev/null 2>&1 || true
claude mcp add-json -s user athena "$(jq -nc --arg u "$url" --arg h "$a/headers" '{type: "http", url: $u, headersHelper: $h}')"

mkdir -p ~/.codex ~/.grok ~/.config/opencode
# Rewrites the [mcp_servers.athena] table (and its sub-tables) at the end of a TOML file, keeping the rest.
athena_toml() {
  touch "$1"
  awk '/^\[/ { skip = ($0 == "[mcp_servers.athena]" || index($0, "[mcp_servers.athena.") == 1) }
    skip { next } /^$/ { blank = blank "\n"; next } { printf "%s", blank; blank = ""; print }' "$1" > "$1.new"
  printf '\n[mcp_servers.athena]\n%s\n' "$2" >> "$1.new"
  mv "$1.new" "$1"
}
# omit_tools_from: without it Codex defers MCP tools behind code mode, so the model never sees Athena's tools or
# instructions. Undocumented (present in the 0.166.0 binary): check it still exists after a Codex upgrade.
athena_toml ~/.codex/config.toml "url = \"$url\"
http_headers_helper = \"$a/headers\"
omit_tools_from = [\"code_mode\"]"
athena_toml ~/.grok/config.toml "url = \"$url\"
bearer_token_file = \"$a/token\""

o=~/.config/opencode/opencode.json
[ -s "$o" ] || echo '{}' > "$o"
jq --arg u "$url" --arg t "Bearer {file:$a/token}" \
  '.mcp.servers.athena = {type: "remote", url: $u, headers: {Authorization: $t}, oauth: false}' "$o" > "$o.new"
mv "$o.new" "$o"

echo "athena: configured"
EOF

# SSH and Orca only from the gateway's subnet: the host's proxies connect from the VM's bridge.
gw="$(ip route | awk '/^default/ {print $3; exit}')"
ufw default deny incoming
ufw allow from "${gw%.*}.0/24" to any port 22,"$ORCA_PORT" proto tcp
ufw --force enable

# Pairing is off in the service; pair.sh opens it briefly.
uid="$(id -u "$RUN_USER")"
until [ -d "/run/user/$uid" ]; do sleep 1; done
su - "$RUN_USER" -c "XDG_RUNTIME_DIR=/run/user/$uid orca-ide serve service install --port $ORCA_PORT"

# The Node runtime (default) does not advertise browser.screencast.v1, so the app cannot open browser tabs on this server.
dropin="/home/$RUN_USER/.config/systemd/user/orca-serve.service.d"
install -d -o "$RUN_USER" -g "$RUN_USER" "$dropin"
printf '[Service]\nEnvironment=ORCA_SERVE_RUNTIME=electron\n' > "$dropin/runtime.conf"
chown "$RUN_USER:$RUN_USER" "$dropin/runtime.conf"
su - "$RUN_USER" -c "XDG_RUNTIME_DIR=/run/user/$uid systemctl --user daemon-reload"

# agent-browser (bundled with Orca) with its own Chrome, so agents can screenshot pages themselves
# (screenshots through Orca's browser come back as one flat colour on this server).
case "$(uname -m)" in x86_64) ab_arch=x64 ;; aarch64) ab_arch=arm64 ;; *) echo "unsupported arch" >&2; exit 1 ;; esac
ab="/opt/Orca/resources/agent-browser-linux-${ab_arch}"
su - "$RUN_USER" -c "mkdir -p ~/.local/bin && ln -sf '$ab' ~/.local/bin/agent-browser && '$ab' install"

echo "done: orca-ide $(dpkg-query -W -f='${Version}' orca-ide), user=$RUN_USER"
echo "next: RUNBOOK.md, 'Set up a new box', agent logins"
