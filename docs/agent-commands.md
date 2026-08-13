# Agent commands

Custom slash commands. Each is a self-contained prompt in `commands/`
loaded on invocation; the authoritative behavior is in the file itself.
This catalog names them and gives a one-liner — nothing more, so it
never drifts from the source.

| Command | File | What it does |
|----------|------|--------------|
| `/git-commit` | `commands/git-commit.md` | Review, stage, confirm, commit |
| `/git-push` | `commands/git-push.md` | Sync, show commits, push after confirmation |
| `/git-pr` | `commands/git-pr.md` | Create PR or update description for the current branch |
| `/git-close` | `commands/git-close.md` | Check unresolved comments, merge PR, clean up worktree/branch, update main |
