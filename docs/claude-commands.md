# Claude Code commands

Reference for the custom slash commands in `.claude/commands/` — what each
one does and how it behaves. This is reference, not instruction: see
`git-workflow.md` for when and how these commands fit into the actual
workflow.

## Custom slash commands (`.claude/commands/`)

Four custom commands live under `.claude/commands/`:

- **`/git-commit`** — the wrap-up command: looks at everything changed (staged,
  unstaged, and untracked — not staged-only), summarizes it per file, stages more of
  it itself if some of it belongs in the commit, drafts and confirms a message (or
  uses one given verbatim), commits via `just save <message-file>`, then follows
  `/git-push`'s own sync procedure and pushes via `just ship`. Absorbed what used to
  be a separate read-only `/git-review` command once staging moved from "a deliberate
  step before commit" to "continuous, as you work" (see `git-workflow.md`) — at that
  point a standalone pre-commit review step no longer matched the workflow, so its
  per-file summary became `/git-commit`'s own first move instead.
- **`/git-push`** — shows the current branch, its upstream (or the lack of one), and
  the one-line subjects of commits not yet pushed; waits for confirmation; then pushes
  via `just ship`. Never force-pushes — that's explicitly out of scope for this
  command. Still exists standalone for pushing outside the `/git-commit` flow (e.g.
  retrying a push that didn't go through).

