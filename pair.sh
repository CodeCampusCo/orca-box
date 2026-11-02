#!/usr/bin/env bash
# Run as the runtime user, in your own terminal (the pairing URL is a credential):
#   ssh orca@<box> bash pair.sh
# Stops the service, serves with pairing on at the box's tailnet address, waits for Enter,
# then restarts the service, which has pairing off.
set -euo pipefail
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
addr="${1:-$(tailscale ip -4)}"

systemctl --user stop orca-serve
log="$(mktemp)"
orca-ide serve --port 6768 --pairing-address "$addr" >"$log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; rm -f "$log"; systemctl --user start orca-serve' EXIT

for _ in $(seq 60); do grep -q '^Pairing URL' "$log" && break; sleep 1; done
grep -E '^Pairing URL' "$log" || { cat "$log"; exit 1; }
read -r -p "Paste it in Orca: Settings > Remote Orca Servers > Add server. Press Enter when paired. "
