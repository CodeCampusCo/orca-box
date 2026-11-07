#!/usr/bin/env bash
# Run as the runtime user; writes a tar.gz of what git does not hold to stdout:
#   ssh -p <vm-ssh-port> orca@<host-tailnet-address> bash -s < backup.sh > orca-box-$(date +%F).tgz
# Warns on stderr about repos with uncommitted or unpushed work, which this backup does not cover.
set -euo pipefail
cd "$HOME"

for g in $(find "$HOME" -maxdepth 5 -name .git -not -path '*/node_modules/*' 2>/dev/null); do
  r="$(dirname "$g")"
  [ -n "$(git -C "$r" status --porcelain 2>/dev/null)" ] && echo "WARN uncommitted: $r" >&2
  [ -n "$(git -C "$r" log --branches --not --remotes --oneline 2>/dev/null | head -1)" ] && echo "WARN unpushed: $r" >&2
done

# Agent memory and history; logins are redone, not copied.
paths=()
for p in .claude/projects .codex/memories_1.sqlite; do
  [ -e "$p" ] && paths+=("$p")
done

# Orca automations: the CLI has no import, so restore.sh recreates them from this list.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if orca-ide automations list --json 2>/dev/null | jq -e '.result.automations' > "$tmp/orca-automations.json"; then
  paths+=(-C "$tmp" orca-automations.json)
else
  echo "WARN automations not backed up: Orca is not answering" >&2
fi

tar -czf - "${paths[@]}"
