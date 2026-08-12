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

After the push succeeds: check for an open PR on this branch (GitHub API:
`GET /repos/:owner/:repo/pulls?head=:owner::branch`). If one exists, update
its description with a summary of the branch's work:
- Read the PR's current body and diff (`GET /repos/:owner/:repo/pulls/:number`).
- Draft an updated body that reflects the current commit set — a one-paragraph
  summary of what the branch does, listing the key changes. Not a commit log.
- If the current body already matches, leave it alone.
- Show the draft, wait for confirmation, then PATCH.
