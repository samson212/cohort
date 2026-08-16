---
description: Review everything changed, stage what belongs, draft a message, commit, then display the message
---

Wrap up this unit of work — see `git status` + `git diff`, stage what belongs,
commit, then show what landed. The diff itself is one `git diff` away; the summary
below is for orientation, not to restate it.

**Before anything else:** verify you're in a worktree, not the primary
checkout:

    git rev-parse --git-dir | grep -q worktrees && echo WORKTREE || echo PRIMARY

- **WORKTREE**: continue to the diff below.
- **PRIMARY**: do NOT proceed. Ask the user for a short topic name, then run
  `cohort-move-to-worktree <topic>`. It copies all dirty files into a new
  worktree on `agent/<topic>`, verifies diffs match, and cleans the primary
  checkout. Then `cd ~/worktrees/<topic>` and re-invoke `/cohort-save`.

```
git status
# keep an eye on staged, unstaged, untracked

git diff                    # unstaged
git diff --staged           # staged
```

Then work through these — each step is a single sentence, no more:

1. Nothing changed → say so and stop.
2. In one short paragraph, name the **kinds** of files changed and **why**
   (e.g. "docs + bin: rename claude→agent, save→commit"), with a
   scan-track (staged / unstaged / untracked). Don't enumerate files one by
   one — `git status` already does that.
3. Stage anything relevant that isn't already (no blind `git add -A`). If
   something doesn't belong in this commit, call it out and suggest a
   separate commit rather than bundling silently. After staging, check for
   remaining unstaged modifications to tracked files
   (`git diff --name-only`). If any exist, flag them — they will not be
   included in this commit. Confirm this is intentional.
4. Commit message — follow the format in git-workflow.md (subject <80,
   bulleted body, `Co-Authored-By` trailer):
   - Draft and show the message.
   - Write to a temp file, run `git commit -F <message-file>` (NEVER
     `git commit` directly in a verbose tab — the output is too large).
     Never `--no-verify`, `--no-gpg-sign`, `-c commit.gpgsign=false`,
     or force-amend — if a pre-commit hook fails, fix the issue,
     `git add -p`, and re-run.
   - Confirm the commit landed: `git log -1 --oneline`.
5. Display the commit message as confirmation of what was saved — the user
   can `--amend` if something looks wrong.

Push is separate. Use `/cohort-sync` when ready to publish — typically after
several commits, when the branch's work is complete.
