---
description: Review everything changed, stage what belongs, confirm a message, commit, and push
argument-hint: [commit message]
---

Wrap up the current unit of work. By now, coherent completed changes should already be
staged from working liberally as you went (see `docs/git-workflow.md`'s "stage as you
go" rule) — but this command still looks at the full picture, not just what's already
staged, and can stage more of it right here if that's the right call.

1. Run `git status` and `git diff` (both unstaged and `--staged`) to see everything —
   staged, unstaged, and untracked.
2. If nothing has changed at all, say so clearly and stop.
3. Summarize what changed, organized by file — a brief (1-2 sentence) description of
   what changed in each, and whether it's currently staged, unstaged, or untracked.
   Not a line-by-line diff dump.
4. Decide what belongs in this commit:
   - If everything relevant is already staged, proceed as-is.
   - If there's unstaged or untracked work that's clearly part of the same logical
     change, stage it now with `git add`.
   - If there's a mix that doesn't belong together (e.g. an unrelated fix that crept
     in along the way), call it out explicitly and suggest splitting it into a
     separate commit, rather than silently bundling it in or silently leaving it out.
5. Determine the commit message:
   - If `$ARGUMENTS` is non-empty, use it verbatim as the commit message.
   - If `$ARGUMENTS` is empty, draft one yourself from the staged diff, in this shape:
     - A single-line subject, under 80 characters.
     - A blank line.
     - A bulleted body giving a high-level summary of what the change accomplishes and
       why — not a restating of the diff line-by-line, and not an enumeration of every
       file touched.
     Show the drafted message and wait for confirmation (or a requested edit) before
     using it — never commit with a self-drafted message that hasn't been confirmed.
6. Once confirmed, write the message to a temp file, with a trailing:

    Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>

   Then run `just save <message-file>` to commit. Never use `--no-verify`,
   `--no-gpg-sign`, `-c commit.gpgsign=false`, or force-amend an existing commit
   unless explicitly asked — if a pre-commit hook fails, fix the issue, re-stage
   (`git add -p`), and create a new commit instead (a fresh `just save` call).
7. Now follow `/git-push`'s own sync procedure, unchanged, against the commit that
   just landed: fetch the upstream remote, check for divergence, integrate cleanly
   with `git pull` if behind (stop and hand back on conflicts, don't push), then list
   the commits not yet on the upstream — including the one from step 6 — and show
   them. Wait for confirmation before pushing; the message confirmation in step 5 is
   not itself authorization to push silently, that's a separate nod.
8. Once confirmed, run `just ship` to push.

After it runs, confirm the working tree is clean (or show what's left).
