---
description: Review everything changed, stage what belongs, confirm a message, commit, push
argument-hint: [commit message]

---

Wrap up this unit of work — see `git status` + `git diff`, stage what belongs,
confirm a message, commit via `just commit`, sync and push via `just push`. The
diff itself is one `git diff` away; the summary below is for orientation, not
to restate it.

```
git status
# keep an eye on staged, unstaged, untracked

git diff                    # unstaged
git diff --staged           # staged
```

Then work through these — each step is a single sentence, no more:

1. Nothing changed → say so and stop.
2. In one short paragraph, name the **kinds** of files changed and **why**
   (e.g. "docs + justfile: rename claude→agent, 'save'→'commit'"), with a
   scan-track (staged / unstaged / untracked). Don't enumerate files one by
   one — `git status` already does that.
3. Stage anything relevant that isn't already (no blind `git add -A`). If
   something doesn't belong in this commit, call it out and suggest a
   separate commit rather than bundling silently.
4. Commit message:
   - `$ARGUMENTS` non-empty → use it verbatim.
   - else → draft a one-line subject (<80 chars), blank line, then a bulleted
     body. Count is free, but each bullet must describe one clearly scoped
     change — its kind and why, not file-by-file. *Show it and wait for
     confirmation* — never commit a self-drafted message that wasn't confirmed.
   - Trailer: `Co-Authored-By: <model name>` — the active model's name.
   Confirmed → write the message to a temp file, then:
   `just commit <message-file>`. Never `--no-verify`, `--no-gpg-sign`,
   `-c commit.gpgsign=false`, or force-amend — if a pre-commit hook fails,
   fix the issue, `git add -p`, and re-run `just commit`.
5. Now run `/git-push`'s sync-and-confirm procedure against this new commit
   (the message confirmation is *not* push authorization — that's a separate
   nod). On confirmation: `just push`.

After it runs: confirm the working tree is clean (or show what remains).
