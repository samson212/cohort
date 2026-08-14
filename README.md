# Cohort

AI coding agents that live in your repo: reviewer, QA, bug-fixer, doc-maintainer.
Cohort enforces conventions and delegates work so every task follows the same
playbook.

## Install

```bash
curl -sSL https://raw.githubusercontent.com/samson212/cohort/main/install.sh | bash
```

Clones the engine to `~/cohort`, creates `~/.cohort -> ~/cohort`, and warns if
`~/.cohort/bin` isn't on your PATH. Add it to your shell profile:

```bash
export PATH="$HOME/.cohort/bin:$PATH"
```

Once that's done, from any project root, `cohort-init` scaffolds a `.cohort/`
directory and installs the Shelley system-prompt hook plus the `/cohort-*`
slash hooks.

```bash
cd ~/my-project
cohort-init
```

## Docs

- [Engine installation](docs/engine-install.md) — layout, bootstrap, updates
- [Git workflow](docs/git-workflow.md) — worktrees, branches, commits
- [Agent roles](docs/agent-roles.md) — the agent catalog and how prompts compose
- [Agent commands](docs/agent-commands.md) — slash command reference
- [Dashboard design](docs/dashboard-design.md) — worktree/PR dashboard architecture
- [Code review guidelines](docs/code-review-guidelines.md)

## Update

```bash
cohort-update
```

## Layout

```
~/.cohort -> ~/cohort       # symlink for tooling
~/.cohort/
  bin/                      # scripts (cohort-new-worktree, …)
  agents/                   # persona + docs per role
  commands/                 # slash command prompts
  hooks/                    # system-prompt + slash hooks
  docs/                     # conventions (git-workflow, code-review, …)
```

## License

MIT
