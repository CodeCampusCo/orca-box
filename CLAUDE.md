# orca-box

Scripts and a runbook to set up, migrate, retire and maintain a headless Ubuntu box that runs the Orca server for remote agent work. `RUNBOOK.md` is the procedure; the scripts are the parts of it a machine can do. Design: `docs/specs/2026-11-03-design.md`.

The repo may go public: nothing committed names a specific machine, address, account, token or person's setup. Box-specific values are read on the box (`tailscale ip -4`) or kept outside the repo.

Interactive steps stay manual: Tailscale login and Tailnet Lock signing, agent logins, Orca pairing. Pairing URLs and tokens never go into chats, logs or commits.

Check before committing: `bash -n` on every script. A script change counts as tested only after it ran on a real box; say which steps were not.

Talk to the owner in Thai; write the repo in English. Dates are ISO `YYYY-MM-DD`.
