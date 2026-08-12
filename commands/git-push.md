---
description: Sync with the remote, show unpushed commits, then push after confirmation
---

Before pushing anything, make sure the local branch has integrated any new remote
commits, and show me exactly what's about to go up.

1. Get the current branch name (`git branch --show-current`).
2. Check whether it has an upstream configured.
   - If it does: continue to the sync check (step 3).
   - If it doesn't (first push of this branch): say so explicitly. There's nothing to
     fetch or integrate, so skip step 3 and go straight to step 4.
3. Sync with the remote before pushing (only when an upstream exists):
   - `git fetch` the upstream remote first (read-only — safe to run without asking).
   - Compare local to upstream to see if it has diverged (e.g.
     `git rev-list --left-right --count @{u}...HEAD` → `behind`/`ahead` counts).
   - If **not behind** (the remote has nothing you don't): note the branch is up to date
     with the remote and continue.
   - If **behind** (the remote has commits you don't): show the incoming commits
     (`git log --oneline HEAD..@{u}`), then integrate them with a plain `git pull`
     (a merge — this may create a merge commit).
     - If the merge is **clean**: report it and continue.
     - If the merge hits **conflicts**: STOP. Show the conflicted files, do NOT attempt
       to auto-resolve, and do NOT push. Hand control back to me to resolve; I'll re-run
       this command afterward.
4. List the commits on this branch not yet on the upstream, one-line subject only (e.g.
   `git log --oneline @{u}..HEAD`), and name the upstream (`<remote>/<branch>`) it's
   pushing to. For a first push with no upstream, list the commits not on the remote's
   default branch instead. If there are no commits to push (e.g. an integrate just
   fast-forwarded local to match the remote), say so and stop.
5. Present the branch/target and the commit list, then wait for my confirmation before
   doing anything else.

Only after I confirm: run a plain `git push` (add `-u origin <branch>` only if there's
no upstream yet, so it starts tracking). Never use `--force` or `--force-with-lease`
here — if that's ever needed, it should be asked for explicitly and separately, not
folded into this command. Do not push if I don't confirm.
