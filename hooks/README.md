# Shelley hooks

These scripts live in the repo and are symlinked into
`~/.config/shelley/hooks/`. Install:

```sh
mkdir -p ~/.config/shelley/hooks
ln -sf "$PWD/hooks/new-conversation" ~/.config/shelley/hooks/new-conversation
```

## new-conversation

Fires when a new conversation starts in a Cohort worktree. Detects the
Cohort root by resolving its own symlink path (no tree-walking) and
prepends the universal docs — git-workflow, agent-roles, agent-commands
— to the first user message so Cohort never needs to be told to read
docs.

Role-specific docs (e.g. code-review-guidelines.md) are not auto-loaded.
When Cohort spins up a subagent, it tells the subagent to `cat` those
docs so they join the universal context.
