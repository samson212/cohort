# Git workflow: worktrees, branches, commits, and pushing

How agents should work in this repo across sessions, not just during code
review.

## One worktree per task

Never do substantive work directly in the primary checkout. Create a
dedicated `git worktree` for each task, on its own branch, via:

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
4. **Wrap up with `/git-commit`** — it looks at everything (staged,
   unstaged, and untracked), can stage more of it right there if some of it
   belongs in this commit, drafts and confirms a message, commits — then
   leaves the push for later, when `/git-push` is invoked.

### Hard rule: `/git-commit` is not optional

Never run `git commit` directly — under any circumstances, including when
the diff looks obviously correct, when a commit message was already drafted
and agreed on earlier in conversation, or when the user's phrasing is
general encouragement rather than a specific instruction (e.g. "let's fix
it," "go ahead," "sounds good"). None of those are the confirmation
`/git-commit` is built to collect. A commit being local and reversible does
not waive this — that's a general default this repo overrides on purpose.
Freely staging with `git add` as you go (see above), or inspecting state
with `git status`/`git diff`, is fine; committing outside `/git-commit` is
not. If you catch yourself about to type `git commit`, stop and invoke the
slash command instead.

## Parking work

If a task pauses (blocked, superseded, or the user redirects to something
else), leave it as a committed branch in its worktree rather than deleting
it. Resuming later means reusing that worktree, not starting over.

## Pushing

`/git-commit` commits locally only. Use `/git-push` when the branch's work
is complete — typically after several commits — to sync and publish.
`/git-push` is standalone: it syncs with the remote, shows what's about to
go up, and pushes only after confirmation. Once pushed, use `/git-pr` to
open a pull request — it drafts a title and description from the commit set
and creates the PR after confirmation. If a PR already exists for the branch,
`/git-pr` updates its description to reflect any new commits.

This doesn't mean over-verifying a simple, unambiguous, explicitly-requested
git command (e.g. a plain "push this") with unrequested pre-flight recon —
reserve that instinct for genuinely ambiguous or destructive operations;
`/git-push`'s own confirmation step already covers the ordinary case.

## Closing a PR

When a branch's work is complete and its PR is approved, use `/git-close`.
It:

1. Identifies the PR (from arguments or the current branch).
2. Scans for unresolved actionable comments — if found, lists them and asks
   whether a re-review is needed before merging.
3. Merges by `gh pr merge --merge --delete-branch` — keeps every commit and
   its attribution rather than squashing.
4. After confirmation, runs `cohort-close` (from the branch's worktree, no
   arguments) to remove the worktree and delete the local branch, then
   fast-forwards the default branch in the main checkout to the latest
   `origin/<default>`.

`/git-close` does not push. The branch should already be pushed and the PR
open before this command runs. If the merge fails (conflicts, failing
checks), stop — do not force.
