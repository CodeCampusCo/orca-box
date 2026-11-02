# orca-box

Scripts and a runbook to set up, migrate, retire and maintain a headless Ubuntu box that runs the Orca server for remote agent work. `RUNBOOK.md` is the procedure; the scripts are the parts of it a machine can do. Design: `docs/specs/2026-11-03-design.md`.

The repo may go public: nothing committed names a specific machine, address, account, token or person's setup. Box-specific values are read on the box (`tailscale ip -4`) or kept outside the repo.

Purpose: moving, deleting and rebuilding the box must stay easy. A Multipass VM on the owner's Mac is both the test target for every script change and the fallback box when the real one is down, so scripts must run on arm64 VMs as well as the amd64 box.

Every change to the box goes into the scripts first and is applied by rerunning them (`sudo bash setup-box.sh` must stay safe to rerun); never hand-edit the box except for the interactive steps. Scripts only add, so rebuild in a fresh VM now and then and treat any difference from the live box as a bug.

Interactive steps stay manual: Tailscale login and Tailnet Lock signing, agent logins, Orca pairing. Pairing URLs and tokens never go into chats, logs or commits.

Check before committing: `bash -n` on every script. A script change counts as tested only after it ran on a box (a fresh Mac VM counts); say which steps were not.

Talk to the owner in Thai; write the repo in English. Dates are ISO `YYYY-MM-DD`.
