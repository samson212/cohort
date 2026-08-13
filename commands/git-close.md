---
description: Close a PR — check for unresolved comments, merge, clean up, and update main
argument-hint: [PR number or URL]
---

Close a pull request. Work through these steps in order:

### 1. Identify the PR

- `$ARGUMENTS` non-empty:
  - If it's a `#NN` number, resolve it in the current repo.
  - If it's a full URL (github.com / github.int.exe.xyz), parse owner/repo/number.
- `$ARGUMENTS` empty → find the PR for the current branch:
  - `git branch --show-current` → look up its PR:
    - `gh pr list --head $(git branch --show-current) --json number,title,state`
  - If no PR exists for this branch, say so and stop.

Get PR details: title, body, state, mergeability, review decision, and all
comments (review + issue comments).

### 2. Check for unresolved comments

Scan all comments for actionable, unresolved feedback. This means:
- Review comments that are part of a review thread and haven't been marked
  resolved or addressed.
- Constructive suggestions or requested changes that haven't been acted on.

If unresolved comments exist:
- List them succinctly (file, snippet, what was asked).
- **Ask the user**: does this need a re-review, or is the PR ready to merge?
- If they want a re-review, stop here so it can happen.
- If they say it's ready, continue.

### 3. Merge

**This step is deliberately left to a human.** The agent presents the PR and
steps back; the human merges it on GitHub (e.g. with merge/rebase/squash as
they choose) and, separately, deletes the remote branch there. Remote-branch
cleanup is intentionally not scripted: it needs GitHub authentication, and
leaving the branch in place after a merge is harmless — the merged tip stays
reachable until a human removes it.

- If the merge fails (conflicts, checks failing, etc.), report the error and
  stop — do not force.
- Report the merge commit SHA.

### 4. Clean up

**Ask for confirmation** before the cleanup step. Report what will happen:
- Worktree path that will be removed
- Local branch that will be deleted
- The default branch will be checked out in the primary checkout and
  fast-forwarded to the newly-merged tip

If the merge succeeds, confirm the new HEAD on the default branch, then run
the script from the branch's worktree (no arguments — it derives everything
from context):

```
cohort-close
```

`cohort-close` verifies the branch tip is an ancestor of the remote default
branch (i.e. the PR really was merged), and only then removes the current
worktree, deletes the local branch, checks out the default branch, and fast-
forwards to origin/<default>. It does NOT delete the remote branch — a human
cleans that up in the GitHub UI.
