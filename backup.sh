#!/usr/bin/env bash
# Run as the runtime user; writes a tar.gz of what git does not hold to stdout:
#   ssh orca@<box> bash -s < backup.sh > orca-box-$(date +%F).tgz
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
for p in .claude/projects .codex/memories_1.sqlite .gemini/antigravity-cli/brain; do
  [ -e "$p" ] && paths+=("$p")
done
tar -czf - "${paths[@]}"
