---
description: Open or update a pull request — review branch, surface issues, draft description, create or edit
argument-hint: [--draft]
---

Open a pull request for the current branch, or update an existing one if it
already exists. The branch must already be pushed (use `/git-push` first).

### 1. Prerequisites

- `git branch --show-current` → confirm this is an `agent/*` branch.
- Check upstream: `git rev-parse --abbrev-ref @{u}` → if no upstream, the
  branch hasn't been pushed. Stop and tell the user to `/git-push` first.
- Check for an existing PR:
  - `gh pr list --head $(git branch --show-current) --json number,title,url,state`
  - If one exists, note it and continue — the flow below handles both new and
    existing PRs.

### 2. Review the branch's work

- Determine the default branch:
  - `gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'`
- Show commits not on the default branch:
  - `git log --oneline origin/<default>..HEAD`
- If nothing to PR, say so and stop.
- Scan the diff (`git diff origin/<default>..HEAD --stat`, then spot-check key
  files). Call out anything that looks incomplete, out of scope, or diverges
  from repo conventions. If issues found:
  - List them succinctly.
  - **Ask the user**: fix these before opening, or proceed as-is?
  - If they want fixes, stop here so they can be made.

### 3. For an existing PR: check for new commits

If a PR already exists, determine whether there are new commits since the last
update that would warrant a new description:
- `gh pr view <number> --json commits -q '.commits[].oid'` → the commits
  currently in the PR on the remote.
- Compare against `git log --oneline origin/<default>..HEAD`.
- If there are local commits not yet in the PR:
  - Note them: "N new commits since the PR was last updated."
  - They'll need to be pushed (`git push` — standard, non-force). Then the
    description should be refreshed.
- If the remote PR already has all local commits but the description is stale
  (new commits were added by a prior push without updating the PR), note that
  too.
- If nothing changed, say so and stop.

### 4. Draft PR title + description

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
- **Existing PR** (and commits were already pushed):
  ```
  gh pr edit <number> --title "<title>" --body "<body>"
  ```
- **Existing PR** (new commits not yet pushed): push them first
  (`git push` — standard, no force), then edit as above.

Report the PR URL and number.