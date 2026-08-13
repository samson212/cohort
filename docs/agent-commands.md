# Agent commands

Custom slash commands. Each is a self-contained prompt in `commands/`
loaded on invocation; the authoritative behavior is in the file itself.
This catalog names them and gives a one-liner — nothing more, so it
never drifts from the source.

| Command | File | What it does |
|----------|------|--------------|
| `/cohort-commit` | `commands/cohort-commit.md` | Review, stage, confirm, commit |
| `/cohort-push` | `commands/cohort-push.md` | Sync, show commits, push after confirmation |
| `/cohort-pr` | `commands/cohort-pr.md` | Create PR or update description for the current branch |
| `/cohort-close` | `commands/cohort-close.md` | Check unresolved comments, hand off merge, clean up worktree/branch, update main |
