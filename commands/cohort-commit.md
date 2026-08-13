---
description: Review everything changed, stage what belongs, confirm a message, commit
---

Wrap up this unit of work — see `git status` + `git diff`, stage what belongs,
confirm a message, commit. The diff itself is one `git diff` away; the summary
below is for orientation, not to restate it.

**Before anything else:** verify you're in a worktree, not the primary
checkout:

    git rev-parse --git-dir | grep -q worktrees && echo WORKTREE || echo PRIMARY

- **WORKTREE**: continue to the diff below.
- **PRIMARY**: do NOT proceed. Ask the user for a short topic name, then run
  `cohort-move-to-worktree <topic>`. It copies all dirty files into a new
  worktree on `agent/<topic>`, verifies diffs match, and cleans the primary
  checkout. Then `cd ~/worktrees/<topic>` and re-invoke `/cohort-commit`.

```
git status
# keep an eye on staged, unstaged, untracked

git diff                    # unstaged
git diff --staged           # staged
```

Then work through these — each step is a single sentence, no more:

1. Nothing changed → say so and stop.
2. In one short paragraph, name the **kinds** of files changed and **why**
   (e.g. "docs + bin: rename claude→agent, 'save'→'commit'"), with a
   scan-track (staged / unstaged / untracked). Don't enumerate files one by
   one — `git status` already does that.
3. Stage anything relevant that isn't already (no blind `git add -A`). If
   something doesn't belong in this commit, call it out and suggest a
   separate commit rather than bundling silently. After staging, check for
   remaining unstaged modifications to tracked files
   (`git diff --name-only`). If any exist, flag them — they will not be
   included in this commit. Confirm this is intentional before proceeding.
4. Commit message:
   - Draft a one-line subject (<80 chars), blank line, then a bulleted
     body. Count is free, but each bullet must describe one clearly scoped
     change — its kind and why, not file-by-file. *Show it and wait for
     confirmation* — never commit a self-drafted message that wasn't confirmed.
   - Trailer: append `Co-Authored-By: $(cohort-model-name)`. The model-name
     invocation must be run at commit time so it reflects the active model.
   Confirmed → write the message to a temp file, then run
   `git commit -F <message-file>`. Never `--no-verify`,
   `--no-gpg-sign`, `-c commit.gpgsign=false`, or force-amend — if a
   pre-commit hook fails, fix the issue, `git add -p`, and re-run.
5. Verify the commit exists: `git log -1 --oneline` — confirm the hash is
   real and the subject matches. Then report working tree state.

Push is separate. Use `/cohort-push` when ready to publish — typically after
several commits, when the branch's work is complete.
