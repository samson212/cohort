---
description: Check unresolved comments, hand off the merge, then clean up worktree and branch
---

Close out a pull request. Work through these steps in order:

### 1. Identify the PR

Find the PR for the current branch. Try open PRs first, then merged/closed:

```
cohort-gh pr list --head $(git branch --show-current) --state open --json number,title,state,url
```

If nothing is found, try:

```
cohort-gh pr list --head $(git branch --show-current) --state merged --json number,title,state,url
```

(`--state` only accepts a single value; `merged,closed` is not valid. Try
`merged` first — it covers the common case. If the PR was closed without
merging, it’ll be under `closed`, but in practice a branch that needs
cleanup was merged.)

If a PR is found (open or closed), get its details: title, body, state,
mergeability, review decision, and all comments (review + issue comments).

If **no PR is found at all**, say:
"No PR found for this branch — it may have already been merged and the remote
branch deleted. Has this PR been merged?"
- If yes: skip to step 4 (Clean up). The script's own ancestor check will
  confirm the merge before doing anything destructive.
- If no: stop — a PR should exist before cleanup.

If a PR **is** found, continue to step 2.

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
cohort-cleanup
```

`cohort-cleanup` verifies the branch tip is an ancestor of the
remote default branch (i.e. the PR really was merged), and only then removes
the current worktree, deletes the local branch, checks out the default
branch, and fast-forwards to origin/<default>. It does NOT merge, and does
NOT delete the remote branch — a human does both.

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
