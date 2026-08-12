# Shelley hooks

These scripts live in the repo and are symlinked into
`~/.config/shelley/hooks/`. Install:

```sh
just install-hooks
```

## system-prompt

Fires on every system prompt — every turn, including subagents. Walks
`agents/cohort/`: resolves each `*.md` symlink and prepends its contents.
The file tree is the source of truth — add a symlink to `agents/cohort/`
and it loads; remove one and it drops out. Non-symlink files and dangling
symlinks are warned about and skipped. Idempotent: passes through if docs
are already present.

Role-specific docs (e.g. `code-review-guidelines.md`) are not auto-loaded.
When Cohort spins up a subagent, it tells the subagent to
`cat agents/<role>/*.md` so those docs join the already-loaded universal
context.
