# Agent roles

Cohort is a collection of agents, each with a specific role in the
development lifecycle. Each role lives in `agents/<role>/`:

```
agents/
  cohort/                   # universal docs (auto-loaded by hook)
    git-workflow.md         -> ../../docs/git-workflow.md
    agent-roles.md          -> ../../docs/agent-roles.md
    agent-commands.md       -> ../../docs/agent-commands.md
  reviewer/                 # universal + delta
    prompt.md
    code-review-guidelines.md -> ../../docs/code-review-guidelines.md
  qa/                       # universal only (no delta docs)
    prompt.md
  bug-fixer/                # universal + delta
    prompt.md
    code-review-guidelines.md -> ../../docs/code-review-guidelines.md
  doc-maintainer/           # universal + delta
    prompt.md
    code-review-guidelines.md -> ../../docs/code-review-guidelines.md
```

The file tree is the source of truth for universal docs — add a symlink to
`agents/cohort/` and it loads; remove one and it drops out. No hardcoded
lists, no frontmatter. Role-specific docs are the delta: Cohort tells a
subagent to `cat agents/<role>/*.md` to get what the hook didn't already
provide.

## How prompts compose

- **`agents/<role>/`** — Persona + symlinks to docs. The `system-prompt` hook
  walks `agents/cohort/` on every turn: `prompt.md` first, then symlinked
  `*.md` in alphabetical order. Cohort loads the remaining agents' docs by
  having them `cat` their own `agents/<role>/` directory.
- **`commands/`** — Skills. Loaded on invocation, not always present.
  Each file is a self-contained prompt the agent follows when the
  corresponding slash command is called.
- **`hooks/`** — Lifecycle. `system-prompt` auto-injects Cohort's context;
  other hooks may follow.
- **`bin/`** — Executable scripts. Recipes that must run the same way every
  time — committing, pushing, creating worktrees — live here so no agent
  can improvise around them. With `~/.cohort/bin` on PATH, any project
  can call `cohort-new-worktree` etc. directly.

## Roles

### Cohort (default)
The entrypoint agent. Coordinates subagents, delegates work, and makes
decisions that require awareness of all conventions.
- Has: `/git-commit`, `/git-push`
- Universal docs: `agents/cohort/` (auto-loaded by `hooks/system-prompt` on
  every turn, including subagents) — symlinked into this directory

### Code reviewer
Reviews pull requests and staged changes against design-doc principles.
- Has: `/git-commit`, `/git-push`
- Delta docs: `agents/reviewer/prompt.md` + `code-review-guidelines.md`

### QA
Runs tests, finds coverage gaps, smoke tests recent changes.
- Delta docs: `agents/qa/prompt.md`

### Bug fixer
Root-cause analysis, minimal fixes, regression-aware.
- Delta docs: `agents/bug-fixer/prompt.md` +
  `code-review-guidelines.md`

### Doc maintainer
Keeps docs coherent as code changes. Enforces "one fact, one place."
- Delta docs: `agents/doc-maintainer/prompt.md` +
  `code-review-guidelines.md`

## Adding a role

1. Create `agents/<role>/prompt.md` — the persona.
2. Symlink any role-specific docs it needs beyond the universal set:
   `ln -sf ../../docs/<doc>.md agents/<role>/`
3. Add it to the catalog above.
4. Cohort loads a subagent's docs by having it `cat agents/<role>/*.md`.
