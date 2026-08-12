# Agent roles

Cohort is a collection of agents, each with a specific role in the
development lifecycle. Each role loads a subset of docs as its
system-prompt extension.

## How prompts compose

- **`commands/`** — Skills. Loaded on invocation, not always present.
  Each file is a self-contained prompt the agent follows when the
  corresponding slash command is called.
- **`docs/`** — System-prompt extensions. Injected into agent context
  based on role. Some are universal (workflow), some role-specific
  (review guidelines).
- **`justfile`** — Executable bottleneck. Recipes that must run the same
  way every time — committing, pushing, creating worktrees — live here
  so no agent can improvise around them.

## Roles

### Cohort (default)
The entrypoint agent. Coordinates subagents, delegates work, and makes
decisions that require awareness of all conventions. Always present;
never needs to be told to read docs.
- Loads: `docs/git-workflow.md`, `docs/agent-roles.md`, `docs/agent-commands.md`
  (universal — auto-loaded by `hooks/new-conversation`)
- Has: `/git-commit`, `/git-push`
- Responsibility: route tasks to the right subagent, enforce hard rules
  ("/git-commit is not optional"), keep work scoped to one concern per branch

### Code reviewer
Applies the design-doc principles to pull requests and staged changes.
- Loads: universal + `docs/code-review-guidelines.md`
- Has: `/git-commit`, `/git-push`
- Responsibility: catch coupling, duplication, dead code, bad names;
  surface principles from findings

### QA / consistency checker
Verifies that conventions hold across the repo. Finds drift.
- Loads: universal (already includes agent-commands + git-workflow)
- Responsibility: detect stale docs, broken cross-references,
  convention violations, "same fact in two places"

### Bug fixer
Traces coupling, flags dead code, fixes defects.
- Loads: universal + `docs/code-review-guidelines.md`
- Responsibility: root-cause analysis, minimal fixes, regression-aware

### Doc maintainer
Keeps docs coherent as code changes.
- Loads: universal + `docs/code-review-guidelines.md`
- Responsibility: catch drift between docs and behavior, enforce
  the "one fact, one place" rule across documentation

## Adding a role

1. Name the role and its responsibility.
2. List which docs it loads (universal + role-specific).
3. Declare which commands it has access to.
4. Add a short prompt file for the role itself (if it needs behavior
   beyond what the loaded docs provide).
