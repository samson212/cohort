---
description: Create or update a pull request — draft title/description for the current branch's commits
argument-hint: [--draft]
---

Create a pull request for the current branch, or update the description of an
existing one. The branch must already be pushed (use `/git-push` first).

### 1. Check local state

- `git status` → if there are staged, unstaged, or untracked changes, stop.
  Tell the user to run `/git-commit` and `/git-push` first.
- `git log --oneline @{u}..HEAD` → unpushed commits. If any exist, stop and
  tell the user to `/git-push` first.

All local work must be committed and pushed before running this command.

### 2. Identify the PR

- `git branch --show-current` → confirm this is an `agent/*` branch.
- Determine the default branch:
  - `gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'`
- Check for an existing PR:
  - `gh pr list --head $(git branch --show-current) --json number,title,url,state`

### 3. Decide: create or update?

- **No existing PR** → draft a title + description for a new PR (step 4).
- **Existing PR** → check whether new commits have been pushed since the last
  description update:
  - `gh pr view <number> --json commits,body -q '{commits: [.commits[].oid], body: .body}'`
  - `git log --oneline origin/<default>..HEAD` → the current commit set.
  - If the PR's commit list already matches HEAD and the description is current
    (the body reflects the commit set), say so and stop — nothing to do.
  - Otherwise, draft an updated description (step 4).

### 4. Draft title + description

- **Title** (<80 chars): a one-liner summarizing the branch's work — prefix
  with the area if it helps (e.g. "commands: add /git-pr workflow").
- **Body**: a one-paragraph summary of what the branch does, listing key
  changes. Not a commit log — describe the effect, not each commit. Use
  bullet points for distinct changes when they're independent.

Show the draft and **wait for confirmation** — never create or update a PR
without it.

`$ARGUMENTS` may contain `--draft` to open as a draft PR (new PR only;
ignored for updates).

### 5. Create or update

Confirmed →

- **New PR**:
  ```
  gh pr create \
    --title "<title>" \
    --body "<body>" \
    --base <default-branch> \
    --head $(git branch --show-current) \
    [$ARGUMENTS]
  ```
- **Existing PR**:
  ```
  gh pr edit <number> --title "<title>" --body "<body>"
  ```

Report the PR URL and number.