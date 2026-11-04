#!/usr/bin/env bash
# Run as the runtime user, in your own terminal (the pairing URL is a credential):
#   ssh -t -p <vm-ssh-port> orca@<host-tailnet-address> bash pair.sh <host-tailnet-address>
# Pairing is off in the service (setup-box.sh), so this swaps it for a pairing server until you press Enter.
# The address is the host's tailnet address; the VM has no Tailscale.
set -euo pipefail
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
addr="${1:?usage: bash pair.sh <host-tailnet-address>}"

systemctl --user stop orca-serve
log="$(mktemp)"
orca-ide serve --port 6768 --pairing-address "$addr" >"$log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; rm -f "$log"; systemctl --user start orca-serve' EXIT

for _ in $(seq 60); do grep -q '^Pairing URL' "$log" && break; sleep 1; done
grep -E '^Pairing URL' "$log" || { cat "$log"; exit 1; }
read -r -p "Paste it in Orca: Settings > Remote Orca Servers > Add server. Press Enter when paired. "
