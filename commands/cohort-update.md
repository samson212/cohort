---
description: Update the Cohort engine to the latest main
---

Update the Cohort engine itself to the latest `main`, then show the result.

- Run `cohort-update` (from any directory). This:
  - ensures the primary checkout (`~/cohort`) is on `main`, checking it out if needed
  - fetches `origin`
  - fast-forwards to `origin/main` (`merge --ff-only`) — local main must be an ancestor
  - prints `Updated: <short-sha> <subject>` on success
- If it fails (diverged main): report the error and do NOT try to force or reset
  — surface the divergence (`git log origin/main..HEAD`) and hand back.
- Note the new head: `git log -1 --oneline` is printed by the script; restate it
  in one line so the result is visible in the transcript.
