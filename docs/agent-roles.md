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

## Roles (to build)

### Code reviewer
Applies the design-doc principles to pull requests and staged changes.
- Loads: `docs/code-review-guidelines.md`, `docs/git-workflow.md`
- Has: `/git-commit`, `/git-push`
- Responsibility: catch coupling, duplication, dead code, bad names;
  surface principles from findings

### QA / consistency checker
Verifies that conventions hold across the repo. Finds drift.
- Loads: `docs/agent-commands.md`, `docs/git-workflow.md`
- Responsibility: detect stale docs, broken cross-references,
  convention violations, "same fact in two places"

### Bug fixer
Traces coupling, flags dead code, fixes defects.
- Loads: `docs/code-review-guidelines.md`
- Responsibility: root-cause analysis, minimal fixes, regression-aware

### Doc maintainer
Keeps docs coherent as code changes.
- Loads: `docs/agent-commands.md`, `docs/code-review-guidelines.md`
- Responsibility: catch drift between docs and behavior, enforce
  the "one fact, one place" rule across documentation

## Adding a role

1. Name the role and its responsibility.
2. List which docs it loads (universal + role-specific).
3. Declare which commands it has access to.
4. Add a short prompt file for the role itself (if it needs behavior
   beyond what the loaded docs provide).
