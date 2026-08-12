=== docs/engine-install.md ===
# Engine installation model

Cohort can operate in two modes:

## Installed mode (recommended for project work)

Cohort lives at `~/.cohort/` on the VM — cloned once and shared across all
projects. Each target project gets a thin `.cohort/` directory with only
project-specific deltas (`prompt.md`, optional `docs/*.md`).

```
~/.cohort/                  # the engine (clone, symlink, or submodule)
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

### Bootstrap

```bash
# From the target project root:
~/.cohort/bin/cohort-init
```

This scaffolds `.cohort/` and installs the system-prompt hook. The hook
detects `~/.cohort/`, loads universal docs from there, then layers on
`.cohort/` deltas (project prompt at highest recency).

### Keeping the engine updated

```bash
cd ~/.cohort && git pull
```

All projects pick up the update immediately — no per-project migration.

## Self-hosted mode

Cohort is its own project. The hook derives the engine root from its own
location (`hooks/system-prompt` → repo root). This is the fallback when
`~/.cohort/` doesn't exist.

## Design decisions

- **`~/.cohort/` is the single source of truth for universal docs.**
  No copies, no per-project symlink farms.
- **`.cohort/` is committed to the target project.** Other developers on
  the project get the same Cohort prompts. The engine itself is a personal
  tooling choice (like your editor or shell config) — each dev installs it
  on their VM.
- **Scripts live in `bin/`, not just in `justfile`.** Any project can call
  `cohort-new-worktree` regardless of whether it uses `just`. The `justfile`
  is a thin convenience layer.
- **Project prompt.md is the tail position** — it loads last, so it can
  override or augment anything in the universal set.
