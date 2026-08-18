# Portability analysis: Cohort on Claude Code (design notes)

Status: **analysis, not implemented.** Captured from design conversations on
approaches to making Cohort run on stock Claude Code (no custom build of the
harness). Revisit before any port work starts. Facts about Claude Code's
hook/agent/skill surface below were pulled from its public docs (hooks
reference, memory, skills) and will drift — re-verify when revisiting.

## The goal

Cohort today is built on Shelley-specific machinery:

- a `system-prompt` hook that rewrites the rendered prompt (identity swap
  `You are Shelley` → `You are Cohort`, injects universal docs, avoids
  touching subagents)
- slash hooks (`hooks/slash/*`) that expand `/cohort-*` into prompt text
- worktree/branch scripts (`bin/`) that enforce one-branch-per-concern

The want: the same feature set on Claude Code, using the stock distributed
build — corporate work can't depend on a custom harness. Both conversations
converged on one principle:

> **The port is a removal of harness-specific scaffolding, not a
> re-implementation of Cohort.**

The Shelley-specific layer exists to do at runtime what Claude Code does
declaratively, so most of it is deleted rather than translated.

## Thread 1: architecture split — core vs adapter

Keep one engine; treat each harness as a thin renderer of markdown.

| Cohort building block | Shelley mechanism | Claude Code equivalent |
|---|---|---|
| Universal docs injection | system-prompt hook, every turn | `CLAUDE.md` / `AGENTS.md`, loaded at session start |
| Project deltas (`.cohort/docs/*.md`, prompt.md) | same hook, tail position | Project `CLAUDE.md` + `.claude/rules/`; AGENTS.md is a growing cross-tool standard |
| Role personas | `agents/<role>/prompt.md` + "cat your docs" | `.claude/agents/<role>.md` — persona *is* the file, no runtime cat |
| Slash commands | shell hooks that `cat commands/*.md` | Skills: `.claude/skills/cohort-save/SKILL.md` (legacy `.claude/commands/` also works), `$ARGUMENTS` substitution, auto-registered as `/cohort-save` |
| Subagent detection | `SHELLEY_IS_SUBAGENT` env contract | `agent_id`/`agent_type` on every hook event's stdin JSON — native, documented |
| `bin/` scripts | harness-agnostic already | unchanged |

Key deletion: the subagent-detection branch's whole problem (rewrite the
rendered prompt's identity without touching subagents) **doesn't exist in
Claude Code** — there is no synthesized prompt to surgically rewrite. Roles
are files; hooks get a JSON stdin that already says which agent is running.

### Corporate-restriction reality check (drives the layering)

- Hooks are the **most-restrictable** layer: enterprise managed policy
  (`allowManagedHooksOnly`) can block user/project/plugin hooks; remote/web
  sessions don't even read `~/.claude/settings.json`.
- Markdown (`CLAUDE.md`, `AGENTS.md`, agents, skills) survives basically
  everywhere; skills can be turned off per-name but not wholesale the way
  hooks can.
- Conclusion: **declarative markdown is load-bearing; hooks are opportunistic
  enhancement.** Core workflow (save/sync/pr/cleanup prompts, personas,
  git-workflow rules) must work with zero hooks. Hooks should only carry
  genuinely dynamic mechanical context (per-prompt state via
  `UserPromptSubmit`, a `PreToolUse` guard). If policy strips them, Cohort
  loses live context but doesn't break.

### Claude Code quirks noted (would need handling)

- `additionalContext` capped at ~10k chars before it spills to a file path.
- Injected context should read as factual statements, not imperative system
  commands, to avoid Claude's prompt-injection defenses — the auto-load
  block's "Do NOT ask to read these files" phrasing needs a rewrite.
- `CLAUDE.md` loads once per session, not per turn — the Shelley hook
  re-injects dynamic state every turn for free; the port needs a different
  mechanism for turn-fresh context.
- Identity swap has no analog to port; confirm nothing depends on it.

## Thread 2: how the feature set would have been built for Claude

### Subagents / roles — native

`.claude/agents/*.md` with frontmatter; `SubagentStart` can inject
`additionalContext` into the subagent. No machinery needed.

### Worktrees / parallel agents — the big one

Why Cohort built worktree machinery at all: undeclared concurrency. Multiple
agents sharing one primary checkout need isolation invented via
`agent/<topic>` branch + worktree scripts. Claude Code makes isolation a
native primitive:

- Subagents can run with `isolation: "worktree"` — their own git worktree,
  auto-created, auto-cleaned when the subagent finishes.
- `claude --worktree` starts a session in its own worktree.
- SDK `TaskCreate` background tasks get per-task isolation.
- All default to `git worktree add` under the hood; `WorktreeCreate` /
  `WorktreeRemove` hooks replace that default only for non-git VCS or custom
  setup (e.g. copy `.env` in), and `WorktreeCreate` must print the created
  path.

So the worktree scripts are **deleted**, not ported: the harness *is* the
worktree and the main checkout never gets dirty.

### Parallelism regimes (open question from the conversation)

1. **Within one conversation** → `isolation: "worktree"` subagents. Native,
   zero scripts.
2. **Across separate instances you drive** → plain git hygiene: agents run
   `git worktree add` because CLAUDE.md says so. Worktrees stay as the git
   concurrency primitive, but as a documented convention, not Cohort
   machinery.
3. **You (human) coordinating many instances** → stock Claude Code web/SDK/
   remote-control: each session/agent gets its own worktree automatically,
   no per-agent scaffolding. Satisfies the corporate constraint: stock build.

Punchline: for plain git, native isolation covers ~95% of the parallel-agent
case out of the box; the rest is convention-in-CLAUDE.md, not scripts.

## Revisit checklist

- [ ] Decide engine layout: keep single repo with `docs/` + `agents/` +
      `skills/` + `bin/`, and per-harness installer writing symlinks.
- [ ] Confirm AGENTS.md as canonical format (it's already markdown) vs
      CLAUDE.md — or both via symlinks.
- [ ] Decide how /cohort-save-style prompts map to skills, and whether any
      current hooks/slash behavior needs hook-level support.
- [ ] Decide what (if anything) is genuinely dynamic enough to need hooks
      on Claude Code (`UserPromptSubmit` context, `PreToolUse` guard for
      primary-checkout commits).
- [ ] Re-verify all Claude Code facts above against current docs.
