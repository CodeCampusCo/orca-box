#!/usr/bin/env bash
# Run as the runtime user on the new box, before the agents are first used, with a backup.sh archive on stdin:
#   ssh orca@<new-box> bash restore.sh < orca-box-YYYY-MM-DD.tgz
# Claude keys memory by repo path, so clone repos to the same paths as on the old box.
set -euo pipefail
cd "$HOME"
tar -xzvf - | sed 's/^/restored: /'
