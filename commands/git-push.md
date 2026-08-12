---
description: Sync with the remote, show unpushed commits, then push after confirmation
---

Sync, show what's about to go up, push **only after confirmation**.

- Branch/upstream:
  - `git branch --show-current`
  - has a remote upstream? If not (first push), say so and skip the sync below.
- Sync (only with an upstream):
  - `git fetch` the upstream remote first (read-only).
  - Divergence: `git rev-list --left-right --count @{u}...HEAD` → behind/ahead.
  - **Not behind**: note up-to-date, continue.
  - **Behind** (remote-only commits): show them
    (`git log --oneline HEAD..@{u}`), then `git pull` (a **merge** — may create
    a merge commit) and continue if clean; if **conflicts**, STOP — do NOT
    auto-resolve, do NOT push. Hand back to the user; they re-run afterward.
- Commit list: `git log --oneline @{u}..HEAD` (or, for a first push, commits
  not on the remote default branch) — one-line subjects only — plus the
  upstream it targets (`<remote>/<branch>`). If nothing to push, say so, stop.
- Present branch/target + commit list, **wait for confirmation**.

Only after confirmation: a plain `git push` (add `-u origin <branch>` only if
no upstream yet). Never `--force` / `--force-with-lease` — that's a separate,
usually-unnecessary decision. No confirmation → no push.
