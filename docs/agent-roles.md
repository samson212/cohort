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
- **`justfile`** — Executable bottleneck. Recipes that must run the same
  way every time — committing, pushing, creating worktrees — live here
  so no agent can improvise around them.

## Roles

### Cohort (default)
The entrypoint agent. Coordinates subagents, delegates work, and makes
decisions that require awareness of all conventions.
- Has: `/git-commit`, `/git-push`
- Responsibility: route tasks to the right subagent, enforce hard rules
  ("/git-commit is not optional"), keep work scoped to one concern per branch
- Universal docs: `agents/cohort/` (auto-loaded by `hooks/system-prompt` on
  every turn, including subagents) — symlinked into this directory

### Code reviewer
Applies the design-doc principles to pull requests and staged changes.
- Has: `/git-commit`, `/git-push`
- Responsibility: catch coupling, duplication, dead code, bad names;
  surface principles from findings
- Output shape: a findings table — severity, finding, recommendation —
  one sentence per row. Then a bottom-line verdict. No rambling.
- Strategy: after the first findings pass, try an "alternative approaches"
  pass — is there a substantively different way to do this that would be
  cleaner? Would a different hook, tool, or pattern eliminate an entire
  class of problem? The best finding isn't a bug — it's a simpler design.
- Delta docs: `agents/reviewer/prompt.md` + `code-review-guidelines.md`

### QA / consistency checker
Verifies that conventions hold across the repo. Finds drift.
- Responsibility: detect stale docs, broken cross-references,
  convention violations, "same fact in two places"
- Delta docs: `agents/qa/prompt.md`

### Bug fixer
Traces coupling, flags dead code, fixes defects.
- Responsibility: root-cause analysis, minimal fixes, regression-aware
- Delta docs: `agents/bug-fixer/prompt.md` +
  `code-review-guidelines.md`

### Doc maintainer
Keeps docs coherent as code changes.
- Responsibility: catch drift between docs and behavior, enforce
  the "one fact, one place" rule across documentation
- Delta docs: `agents/doc-maintainer/prompt.md` +
  `code-review-guidelines.md`

## Adding a role

1. Create `agents/<role>/prompt.md` — the persona.
2. Symlink any role-specific docs it needs beyond the universal set:
   `ln -sf ../../docs/<doc>.md agents/<role>/`
3. Add it to the catalog above.
4. Cohort loads a subagent's docs by having it `cat agents/<role>/*.md`.
