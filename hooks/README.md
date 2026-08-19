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

## slash/cohort

Pluggable slash commands. When a user sends a message starting with
`/cohort-*` (save, sync, pr, cleanup), Shelley runs the matching hook in
`~/.config/shelley/hooks/slash/` — one shared dispatcher file, symlinked
under each skill name by `cohort-init`; its stdout replaces the user
message. The dispatcher resolves the invocation name to `cohort-skill`,
which cats the corresponding `skills/cohort-<name>/SKILL.md` — frontmatter
and all — so `/cohort-save` becomes the full skill text for the model.

The skill file in `skills/` is the single source of truth (agent-skills
standard: `name` + `description` frontmatter, `$ARGUMENTS` substitution).
The hook and loader are dumb renderers, and the same skill files are read
directly by Claude Code, Pi, and Codex — see `docs/portability.md`.
`cohort-init` installs the `cohort` hook symlink and removes stale ones.