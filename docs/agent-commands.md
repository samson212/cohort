# Agent commands

Custom slash commands. Each is a self-contained prompt in `commands/`,
loaded on invocation by a small shell hook that replaces the bare `/cohort-*`
message with the full prompt text — the authoritative behavior lives in the
file itself. This catalog names them and gives a one-liner — nothing more,
so it never drifts from the source.

| Command | File | What it does |
|----------|------|--------------|
| `/cohort-commit` | `commands/cohort-commit.md` | Review, stage, confirm, commit |
| `/cohort-push` | `commands/cohort-push.md` | Sync, show commits, push after confirmation |
| `/cohort-pr` | `commands/cohort-pr.md` | Create draft PR or update description for the current branch |
| `/cohort-cleanup` | `commands/cohort-cleanup.md` | Check unresolved comments, hand off merge, clean up worktree/branch, update main |
