---
description: Open a pull request for the current branch — review commits, draft description, create
argument-hint: [--draft]
---

Open a pull request for the current branch. The branch must already be pushed
(use `/git-push` first).

### 1. Prerequisites

- `git branch --show-current` → confirm this is an `agent/*` branch.
- Check upstream: `git rev-parse --abbrev-ref @{u}` → if no upstream, the
  branch hasn't been pushed. Stop and tell the user to `/git-push` first.
- Check for an existing PR:
  - `gh pr list --head $(git branch --show-current) --json number,title,url,state`
  - If one exists, report its number/title/URL and stop — use `/git-push` to
    update an existing PR.

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

### 3. Draft PR title + description

- **Title** (<80 chars): a one-liner summarizing the branch's work — prefix
  with the area if it helps (e.g. "commands: add /git-pr workflow").
- **Body**: a one-paragraph summary of what the branch does, listing key
  changes. Not a commit log — describe the effect, not each commit. Use
  bullet points for distinct changes when they're independent.

Show the draft and **wait for confirmation** — never create a PR without it.

`$ARGUMENTS` may contain `--draft` to open as a draft PR.

### 4. Create

Confirmed →

```
gh pr create \
  --title "<title>" \
  --body "<body>" \
  --base <default-branch> \
  --head $(git branch --show-current) \
  [$ARGUMENTS]
```

Report the PR URL and number. Push is separate — the branch is already up.