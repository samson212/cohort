# Agent commands

Custom slash commands. Each is a self-contained prompt in `commands/`,
loaded on invocation by a small shell hook that replaces the bare `/cohort-*`
message with the full prompt text — the authoritative behavior lives in the
file itself. This catalog names them and gives a one-liner — nothing more,
so it never drifts from the source.

| Command | File | What it does |
|----------|------|--------------|
| `/cohort-save` | `commands/cohort-save.md` | Review, stage, commit, display message |
| `/cohort-sync` | `commands/cohort-sync.md` | Fetch, show commits, push, display result |
| `/cohort-pr` | `commands/cohort-pr.md` | Create draft PR or update description for the current branch |
| `/cohort-cleanup` | `commands/cohort-cleanup.md` | Check unresolved comments, hand off merge, clean up worktree/branch, update main |
