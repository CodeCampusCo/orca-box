#!/usr/bin/env bash
# Run as the runtime user, in your own terminal (the pairing URL is a credential):
#   ssh -t -p <vm-ssh-port> orca@<host-tailnet-address> bash pair.sh <host-tailnet-address> [--mobile-pairing]
# Pairing is off in the service (setup-box.sh), so this swaps it for a pairing server until you press Enter.
# It prints a pairing link for the desktop app; with --mobile-pairing it prints a QR code and link for the mobile app instead.
# The address is the host's tailnet address; the VM has no Tailscale.
set -euo pipefail
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
addr="${1:?usage: bash pair.sh <host-tailnet-address> [--mobile-pairing]}"

systemctl --user stop orca-serve
log="$(mktemp)"
orca-ide serve --port 6768 --pairing-address "$addr" "${@:2}" >"$log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; rm -f "$log"; systemctl --user start orca-serve' EXIT

for _ in $(seq 60); do grep -qi 'pairing' "$log" && break; sleep 1; done
sleep 2
cat "$log"
read -r -p "Pair now (desktop: Settings > Remote Orca Servers > Add server; mobile: Pair, scan the QR code). Press Enter when paired. "
