---
description: Check unresolved comments, hand off the merge, then clean up worktree and branch
---

Close out a pull request. Work through these steps in order:

### 1. Identify the PR

Find the PR for the current branch:

```
cohort-gh pr list --head $(git branch --show-current) --json number,title,state,url
```

If no PR exists for this branch, say so and stop.

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

### 3. Hand the merge to the human

**The agent does not merge.** Present the PR URL and stop; the human merges it
on GitHub (merge/rebase/squash — their choice) and deletes the remote branch
there. Remote-branch cleanup is intentionally not scripted: it needs GitHub
authentication, and leaving the branch in place after a merge is harmless —
the merged tip stays reachable until a human removes it.

Wait for the user to confirm the PR is merged before continuing.

### 4. Clean up

**Ask for confirmation** before cleanup. Report what will happen:
- Worktree path that will be removed
- Local branch that will be deleted
- The default branch will be checked out in the primary checkout and
  fast-forwarded to the newly-merged tip

Confirmed → run the script from the branch's worktree (no arguments — it
derives everything from context):

```
cohort-close
```

`cohort-close` verifies the branch tip is an ancestor of the remote default
branch (i.e. the PR really was merged), and only then removes the current
worktree, deletes the local branch, checks out the default branch, and fast-
forwards to origin/<default>. It does NOT merge, and does NOT delete the
remote branch — a human does both.

**The worktree you are standing in is deleted by this script.** As soon as it
succeeds, change your working directory to the primary checkout (the script
prints the path) — every later command will fail otherwise.

### 5. Verify the cleanup

From the primary checkout, confirm all three effects actually happened:

```
git worktree list          # the closed worktree is gone
git branch                 # the closed branch is gone
git log -1 --oneline       # default branch is at the merged tip
```

Report what's left. If any of the three didn't happen, say so — a partial
cleanup is not a successful one.
