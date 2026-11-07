#!/usr/bin/env bash
# Run as the runtime user on the new box, before the agents are first used, with a backup.sh archive on stdin:
#   ssh -p <vm-ssh-port> orca@<new-host-tailnet-address> bash restore.sh < orca-box-YYYY-MM-DD.tgz
# Claude keys memory by repo path, so clone repos to the same paths as on the old box.
# Automations are recreated for repos already cloned at their old path; others are skipped with a warning.
set -euo pipefail
cd "$HOME"
tar -xzvf - | sed 's/^/restored: /'

f="$HOME/orca-automations.json"
[ -s "$f" ] || exit 0
while IFS= read -r a; do
  name="$(jq -r .name <<<"$a")"
  path="$(jq -r '.runContext.path // empty' <<<"$a")"
  if [ "$(jq -r .workspaceMode <<<"$a")" != new_per_run ] || [ ! -d "$path" ]; then
    echo "WARN automation not restored (needs a repo at its old path, new worktree per run): $name" >&2
    continue
  fi
  if orca-ide automations list --json | jq -e --arg n "$name" '.result.automations | any(.name == $n)' >/dev/null; then
    echo "automation exists: $name"
    continue
  fi
  orca-ide repo add --path "$path" --json >/dev/null
  args=(--name "$name" --prompt "$(jq -r .prompt <<<"$a")" --provider "$(jq -r .agentId <<<"$a")"
        --trigger "$(jq -r .rrule <<<"$a")" --timezone "$(jq -r .timezone <<<"$a")" --repo "path:$path")
  [ "$(jq -r .precheck <<<"$a")" = null ] ||
    args+=(--precheck "$(jq -r .precheck.command <<<"$a")" --precheck-timeout "$(jq -r .precheck.timeoutSeconds <<<"$a")")
  [ "$(jq -r .enabled <<<"$a")" = true ] || args+=(--disabled)
  orca-ide automations create "${args[@]}" --json >/dev/null
  echo "automation restored: $name"
done < <(jq -c '.[]' "$f")
rm -f "$f"
