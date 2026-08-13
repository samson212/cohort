# Engine installation model

Cohort is an engine you install once per VM and deploy into individual
projects via a thin `.cohort/` directory.

## Layout

```
~/cohort/                   # clone the engine here (visible, editable)
~/.cohort -> ~/cohort       # symlink — canonical path for tooling
~/cohort/
  bin/                      # scripts (add ~/.cohort/bin to PATH)
  agents/cohort/            # universal prompt.md + symlinked docs
  docs/                     # canonical docs
  commands/                 # slash commands
  hooks/                    # system-prompt hook
  install.sh                # curl-pipeable installer

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
curl -sSL https://raw.githubusercontent.com/samson212/cohort/main/install.sh | bash
```

This clones the engine to `~/cohort`, creates `~/.cohort -> ~/cohort`,
and checks that `~/.cohort/bin` is on your PATH.

Add the export to the file your **login** shell reads:

```bash
export PATH="$HOME/.cohort/bin:$PATH"
```

| Shell | File |
|-------|------|
| bash | the first of `~/.bash_profile`, `~/.bash_login`, `~/.profile` that exists — the rest are skipped |
| zsh | `~/.zprofile` (zsh never reads `~/.profile`) |

Avoid `~/.bashrc` and `~/.zshrc`. Agents run these scripts from
non-interactive shells, and both files are conventionally guarded to exit
early when not interactive — so an export there works in your terminal but
leaves every script `command not found` for an agent.

Then, from any project root:

```bash
cohort-init
```

This scaffolds `.cohort/` and installs the system-prompt hook. The hook
loads universal docs from the engine, then layers on `.cohort/` deltas
(project prompt at highest recency).

## Keeping the engine updated

```bash
cohort-update
```

Checks out main and fast-forwards to `origin/main`.

All projects pick up the update immediately — no per-project migration.

## Design decisions

- **The engine derives from the hook symlink, not `~/.cohort/` detection.**
  Open Shelley in `~/cohort/` to hack on Cohort itself; open Shelley in
  `~/my-project/` to work on that project. Both load the same universal docs.
- **`.cohort/` is committed to the target project.** Other developers on
  the project get the same Cohort prompts. The engine itself is a personal
  tooling choice (like your editor or shell config) — each dev installs it
  on their VM.
- **Scripts live in `bin/`.** With `~/.cohort/bin` on PATH, any project
  can call `cohort-new-worktree` etc. directly — no dependency on a
  particular task runner.
- **Project prompt.md is the tail position** — it loads last, so it can
  override or augment anything in the universal set.
