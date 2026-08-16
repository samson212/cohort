---
description: Create or update a pull request — draft title/description for the current branch's commits. New PRs are always opened as drafts.
---

Create a pull request for the current branch, or update the description of an
existing one. The branch must already be pushed (use `/cohort-sync` first).

### 1. Check local state

- `git status` → if there are staged, unstaged, or untracked changes, stop.
  Tell the user to run `/cohort-save` and `/cohort-sync` first.
- Check for unpushed commits. The branch may have no upstream yet, so guard
  for that: `git rev-parse --abbrev-ref --symbolic-full-name @{u}`.
  - No upstream → the branch was never pushed. Stop, tell the user to run
    `/cohort-sync` first.
  - Upstream exists → `git log --oneline @{u}..HEAD`. If any commits are
    listed, stop and tell the user to `/cohort-sync` first.

All local work must be committed and pushed before running this command.

### 2. Identify the PR

- `git branch --show-current` → confirm this is an `agent/*` branch.
- Determine the default branch:
  - `cohort-gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'`
- Check for an existing PR:
  - `cohort-gh pr list --head $(git branch --show-current) --json number,title,url,state`

### 3. Decide: create or update?

- **No existing PR** → draft a title + description for a new PR (step 4).
- **Existing PR** → check whether new commits have been pushed since the last
  description update:
  - `cohort-gh pr view <number> --json commits,body -q '{commits: [.commits[].oid], body: .body}'`
  - `git log --oneline origin/<default>..HEAD` → the current commit set.
  - If the PR's commit list already matches HEAD and the description is current
    (the body reflects the commit set), say so and stop — nothing to do.
  - Otherwise, draft an updated description (step 4).

### 4. Draft title + description

- **Title** (<80 chars): a one-liner summarizing the branch's work — prefix
  with the area if it helps (e.g. "commands: add /cohort-pr workflow").
- **Body**: a one-paragraph summary of what the branch does, listing key
  changes. Not a commit log — describe the effect, not each commit. Use
  bullet points for distinct changes when they're independent.

Show the draft and **wait for confirmation** — never create or update a PR
without it.

**New PRs are always opened as drafts** — there is no prompt, and the `--draft`
argument is not needed (and should not be passed; the creation command below
hardcodes it). Drafting signals the branch isn't merge-ready; a human marks it
ready when they want it reviewed.

### 5. Create or update

Confirmed →

- **New PR**:
  ```
  cohort-gh pr create \
    --draft \
    --title "<title>" \
    --body "<body>" \
    --base <default-branch> \
    --head $(git branch --show-current)
  ```
- **Existing PR**:
  ```
  cohort-gh pr edit <number> --title "<title>" --body "<body>"
  ```

(Updating an existing PR never changes its draft state — if a PR is already a
draft, it stays a draft; if it's open, it stays open.)

Report the PR URL and number.

### 6. Verify it landed

Don't trust the exit status — read the PR back and confirm the title and body
are the ones you just sent:

```
cohort-gh pr view <number> --json title,body
```

If they don't match, say so plainly rather than reporting success. (`gh pr
edit` has been seen to exit 0 while changing nothing when its GraphQL query
hits a deprecated field; `cohort-gh api -X PATCH repos/<owner>/<repo>/pulls/<number>`
is the fallback.)