# Shelley hooks

These scripts live in the repo and are symlinked into
`~/.config/shelley/hooks/`. Install:

```sh
just install-hooks
```

## system-prompt

Fires on every system prompt — every turn, including subagents. Detects
the Cohort root by resolving its own symlink path and prepends universal
docs (git-workflow, agent-roles, agent-commands) to the system prompt.
Idempotent: passes through if docs are already present.

Role-specific docs (e.g. code-review-guidelines.md) are not auto-loaded.
When Cohort spins up a subagent, it tells the subagent to `cat` those
docs so they join the universal context.
