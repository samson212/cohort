# Engine installation model

Cohort is an engine you install once per VM and deploy into individual
projects via a thin `.cohort/` directory.

## Layout

```
~/cohort/                   # clone the engine here (visible, editable)
~/.cohort -> ~/cohort       # symlink — canonical path for tooling
~/cohort/
  bin/
  agents/cohort/            # universal prompt.md + symlinked docs
  docs/                     # canonical docs
  commands/                 # slash commands
  hooks/                    # system-prompt hook
  justfile

~/my-project/               # Shelley opens HERE
  .cohort/
    prompt.md               # project-specific persona delta
    docs/                   # project-specific conventions (optional)
  src/...
```

The hook derives the engine root from its own symlink chain, so it works
identically whether Shelley opens in an engine clone or a project using it.

## Bootstrap

```bash
# Clone the engine and create the canonical symlink:
git clone <cohort-repo-url> ~/cohort
ln -s ~/cohort ~/.cohort

# From any project root:
~/.cohort/bin/cohort-init
```

This scaffolds `.cohort/` and installs the system-prompt hook. The hook
loads universal docs from the engine, then layers on `.cohort/` deltas
(project prompt at highest recency).

## Keeping the engine updated

```bash
cd ~/cohort && git pull
```

All projects pick up the update immediately — no per-project migration.

## Design decisions

- **The engine derives from the hook symlink, not `~/.cohort/` detection.**
  Open Shelley in `~/cohort/` to hack on Cohort itself; open Shelley in
  `~/my-project/` to work on that project. Both load the same universal docs.
- **`.cohort/` is committed to the target project.** Other developers on
  the project get the same Cohort prompts. The engine itself is a personal
  tooling choice (like your editor or shell config) — each dev installs it
  on their VM.
- **Scripts live in `bin/`, not just in `justfile`.** Any project can call
  `cohort-new-worktree` regardless of whether it uses `just`. The `justfile`
  is a thin convenience layer.
- **Project prompt.md is the tail position** — it loads last, so it can
  override or augment anything in the universal set.
