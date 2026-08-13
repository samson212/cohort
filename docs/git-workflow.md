# Git workflow: worktrees, branches, commits, and pushing

How agents should work in this repo across sessions, not just during code
review.

## One worktree per task

You may explore and edit in the primary checkout, but never commit there.
When ready to commit, move the work to a dedicated worktree:

```
cohort-move-to-worktree <short-topic>
```

This creates `agent/<short-topic>` at `$HOME/worktrees/<short-topic>`
and copies all dirty files over. For a clean-slate task (no edits yet), use:

```
cohort-new-worktree <short-topic>
```

This fetches the latest `main` and creates `agent/<short-topic>` at
`$HOME/worktrees/<short-topic>`, deliberately *without* setting up
branch tracking — branching straight off `origin/main` would otherwise
silently set `origin/main` itself as the new branch's upstream (git's
default `autoSetupMerge` behavior), making a bare `git push` push directly
onto `main`. Don't hand-run the underlying git commands; use the script.

Worktrees live under `$HOME/worktrees/`, not inside a session scratchpad
— scratchpads are ephemeral and can be cleaned up; parked work should survive
that. Branch names use the `agent/` prefix already established in this repo.

## Start in the primary checkout, move before committing

It’s fine to explore and edit in the primary checkout. When you’re
ready to commit, move the work to a dedicated worktree:

    cohort-move-to-worktree <topic>

This is the worktree equivalent of `git checkout -b <topic>`. It:

1. Creates a worktree on a new `agent/<topic>` branch from HEAD.
2. Copies all dirty files (staged, unstaged, untracked) into the worktree.
3. Verifies the diffs match identically.
4. Cleans the primary checkout back to a pristine state.

After moving, your working directory is still the primary checkout —
`cd ~/worktrees/<topic>` to resume work there, then use
`/cohort-commit` as usual.

## Keep branches small in scope

A branch should cover one concern. If the scope drifts mid-session — a
review turns up an unrelated bug, or "while I'm in here" tempts a second
change — stop and ask whether the out-of-scope part should move to its own
branch/worktree before continuing. Don't decide this unilaterally; the user
may want the unrelated fix bundled, but the default is to keep it separate.

## Commit frequently

Stage continuously as you work; commit at each logical, working increment —
not just once at the end of a session (see "The loop" below for how staging
and committing split across that increment). Small, frequent commits:
- make the diff reviewable in pieces instead of as one large blob
- give a clean rollback point if a later step turns out wrong
- let work be "parked" mid-task without losing granularity

**Never amend a pushed commit.** Amending is fine for local-only commits
(a small fix that doesn't substantively change the commit), but once a
commit is pushed, `--amend` + force-push breaks any branch other people
may have fetched. To undo a pushed commit, use `git revert` — it creates
a new commit that inverts the old one, preserving history. For fixes that
don't undo the commit entirely, make a new commit on top.

## The loop

1. **Work** — make one focused change.
2. **Stage as you go** — the moment a change is a coherent, working unit (a
   function finished and tested, a bug fixed, a small step complete), stage
   it with `git add` right away. Don't wait for a dedicated review pass to
   decide what's worth staging, and don't let unstaged changes pile up
   hoping to sort them out later — `git add` for this purpose is ordinary,
   expected behavior, not something that needs asking first.
3. Repeat until the task's scope is done, or it's a good point to wrap up.
4. **Wrap up with `/cohort-commit`** — it looks at everything (staged,
   unstaged, and untracked), can stage more of it right there if some of it
   belongs in this commit, drafts and confirms a message, commits — then
   leaves the push for later, when `/cohort-push` is invoked.

### Hard rule: `/cohort-commit` is not optional

Never run `git commit` directly — under any circumstances, including when
the diff looks obviously correct, when a commit message was already drafted
and agreed on earlier in conversation, or when the user's phrasing is
general encouragement rather than a specific instruction (e.g. "let's fix
it," "go ahead," "sounds good"). None of those are the confirmation
`/cohort-commit` is built to collect. A commit being local and reversible does
not waive this — that's a general default this repo overrides on purpose.
Freely staging with `git add` as you go (see above), or inspecting state
with `git status`/`git diff`, is fine; committing outside `/cohort-commit` is
not. If you catch yourself about to type `git commit`, stop and invoke the
slash command instead.

## Parking work

If a task pauses (blocked, superseded, or the user redirects to something
else), leave it as a committed branch in its worktree rather than deleting
it. Resuming later means reusing that worktree, not starting over.

## Pushing

`/cohort-commit` commits locally only. Use `/cohort-push` when the branch's work
is complete — typically after several commits — to sync and publish.
`/cohort-push` is standalone: it syncs with the remote, shows what's about to
go up, and pushes only after confirmation. Once pushed, use `/cohort-pr` to
open a pull request — it drafts a title and description from the commit set
and creates the PR **as a draft** after confirmation (drafts are mandatory;
`--draft` is hardcoded in the command). If a PR already exists for the branch,
`/cohort-pr` updates its description to reflect any new commits.

This doesn't mean over-verifying a simple, unambiguous, explicitly-requested
git command (e.g. a plain "push this") with unrequested pre-flight recon —
reserve that instinct for genuinely ambiguous or destructive operations;
`/cohort-push`'s own confirmation step already covers the ordinary case.

## Cleaning up after a PR has been closed

When a branch's work is complete and its PR is approved, use `/cohort-cleanup`.
It:

1. Identifies the PR for the current branch (searches open, then merged/closed).
2. If a PR is found: scans for unresolved actionable comments — if found, lists
   them and asks whether a re-review is needed before merging.
3. If no PR is found (merged and remote branch already deleted): asks the human
   to confirm the merge happened, then skips to cleanup (the script's own
   ancestor check confirms it).
4. If the PR is still open: presents it and hands the merge to the human — they
   merge on GitHub (merge/rebase/squash — their choice) and delete the remote
   branch in the GitHub UI afterwards.
5. After confirmation, runs `cohort-cleanup` (from the branch's
   worktree, no arguments): it verifies the branch tip is an ancestor of the
   remote default branch, then removes the worktree, deletes the local
   branch, and fast-forwards the default branch in the primary checkout to
   the latest `origin/<default>`. The worktree it ran from is gone
   afterwards — relocate to the primary checkout before running anything
   else.

`/cohort-cleanup` does not push and does not merge. The branch should already be
pushed and the PR open (or already merged) before this command runs.
