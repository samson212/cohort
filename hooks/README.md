# Shelley hooks

These scripts live in the engine and are symlinked into
`~/.config/shelley/hooks/`. Install via:

```sh
~/.cohort/bin/cohort-init
```

## system-prompt

Fires on every system prompt — every turn, including subagents. Walks
`agents/cohort/`: resolves each `*.md` symlink and prepends its contents.
The file tree is the source of truth — add a symlink to `agents/cohort/`
and it loads; remove one and it drops out. Non-symlink files and dangling
symlinks are warned about and skipped. Idempotent: passes through if docs
are already present.

The hook also loads project deltas from `.cohort/docs/*.md` and
`.cohort/prompt.md` when the current project has a `.cohort/` directory.
The project prompt loads last for maximum recency.

Role-specific docs (e.g. `code-review-guidelines.md`) are not auto-loaded.
When Cohort spins up a subagent, it tells the subagent to
`cat agents/<role>/*.md` so those docs join the already-loaded universal
context.

## slash/cohort-*

Pluggable slash commands. When a user sends a message starting with
`/cohort-*` (commit, push, pr, cleanup), Shelley runs the matching
`hooks/slash/cohort-<name>` hook; its stdout replaces the user message.
Each hook cats the corresponding prompt in `commands/cohort-<name>.md` —
frontmatter and all — so `/cohort-save` becomes the full procedure text
for the LLM to follow.

The prompt file in `commands/` is the single source of truth; the hooks
are dumb readers. `cohort-init` installs these symlinks and removes stale
ones for commands that no longer exist.