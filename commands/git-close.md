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

- `gh pr merge <pr> --squash --delete-branch` (preferred) or `--merge`.
- If the merge fails (conflicts, checks failing, etc.), report the error and
  stop — do not force.
- Report the merge commit SHA.

### 4. Clean up

**Ask for confirmation** before the cleanup step. Report what will happen:
- Remote branch deleted (already done by `--delete-branch` if using squash)
- Worktree path that will be removed
- Local branch that will be deleted
- main will be checked out and fast-forwarded

If the user confirms:

```
cohort-close $(git rev-parse --show-toplevel) <branch-name> <worktree-path>
```

This deletes the remote branch (if it survives), removes the worktree,
force-deletes the local branch, checks out main, and fast-forwards to
origin/main.

Confirm the new HEAD on main.
