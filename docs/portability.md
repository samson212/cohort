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

---

# Thread 3: porting to Pi (earendil-works/pi)

Status: **analysis, not implemented.** Pi = the open-source "Agent Harness"
(`earendil-works/pi`, ~92k stars): a self-extending coding agent CLI with a
minimal four-tool core (Read/Write/Edit/Bash) that you extend at runtime with
TypeScript extensions, skills, and prompt templates. Philosophy is
literally "minimal core, self-extends at runtime" — which matches Cohort's
shape (markdown + scripts + thin runtime shim) even better than Claude Code.

## Bottom line

**Pi is the friendliest port target of the three**, because the things
Cohort had to *build* on Shelley (hook that rewrites prompts, subagent
identity detection, worktree scripts) and the things Claude Code provides
*natively but as opaque product features* (subagent isolation, agent files,
skills) are all **first-class, documented, open-source Pi extensions** —
many of them *literally shipped as example extensions* that implement
Cohort's exact model.

Biggest single finding: Pi's own `subagent` example extension is a
working implementation of **Cohort's roles system**:
- Agents are markdown files in `~/.pi/agent/agents/*.md` (user) and
  `.pi/agents/*.md` (project) with YAML frontmatter `name`, `description`,
  `tools`, `model` — the body is the system prompt, exactly like
  `agents/<role>/prompt.md`.
- `registerTool` exposes a `subagent` tool with **single / parallel /
  chain** modes; each subagent runs in a **separate `pi` process** with an
  isolated context window ("Isolated context: Each subagent runs in a
  separate `pi` process").
- Discovery is **fresh per invocation** — you can edit an agent file
  mid-session and the next call picks it up.
- It already has scout/planner/reviewer/worker sample agents — the same
  *shape* as Cohort's reviewer/qa/bug-fixer/doc-maintainer, plus per-agent
  `model` selection (Cohort doesn't have this yet — worth stealing).
- Security model matches Cohort's trust stance: project-local agents are
  repo-controlled prompts; default only loads user-level, prompts before
  running project agents.

So the *identity problem that spawned the subagent-detection branch* is not
even a Pi thing: subagents aren't spawned by modifying the main prompt, they
run as **separate processes** with their own `--append-system-prompt`. There
is no "main agent vs subagent" sharing a prompt to sniff.

## Feature mapping (Shelley → Pi)

| Cohort building block | Shelley mechanism | Pi equivalent |
|---|---|---|
| Universal docs | system-prompt hook | `AGENTS.override.md` / `AGENTS.md` / `CLAUDE.md` loaded natively from parent dirs AND `~/.pi/agent/AGENTS.md` (global) — there's even `--no-context-files` |
| Project deltas | tail-position project prompt | AGENTS.md/CLAUDE.md in the project, or `.pi/` settings |
| Role personas | agents/<role>/prompt.md + "cat your docs" | `.pi/agent/agents/*.md` / `.pi/agents/*.md` — native, via the subagent extension |
| Slash commands | hooks/slash/*  that `cat commands/*.md` | Two native ways: skills register `/skill:name`; extensions `pi.registerCommand()` → `/mycommand` |
| Subagent detection | SHELLEY_IS_SUBAGENT | Not needed — subagents are separate processes |
| Worktree/branch isolation | bin/ worktree scripts | `git worktree` still the primitive; Pi's `/tree` / `/fork` / `/clone` are session-level (not git) so worktree discipline stays in bin/ |
| Commands/prompts | commands/*.md | `prompt-templates.md` — prompt files as `pi ... --append-system-prompt`, plus skills carry their own instructions |
| Event-driven behavior | hooks | `extensions.md`: `pi.on("session_start")`, `pi.on("tool_call")`, `pi.on("turn_start")`, `pi.on("before_agent_start")` — can inject messages, modify system prompt, block tool calls, add `additionalContext` |
| Settings | .cohort/ prompts | `.pi/settings.json` + `.pi/extensions/` (project) and `~/.pi/agent/extensions/` (global) — real config, not prompt text |

## What actually gets written (the port)

For Claude Code the port was *deletions*. For Pi it's **deletions plus two
tiny adapters**:

1. **Skills**: copy `commands/cohort-*.md` to `.pi/skills/cohort-<name>/SKILL.md`
   (or point Pi at `~/.claude/skills` — it reads other harnesses' skill
   dirs directly). Progressively disclosed; load on `/skill:cohort-save`.
2. **Agents**: copy `agents/<role>/prompt.md` to `~/.pi/agent/agents/<role>.md`
   with YAML frontmatter, symlink the role's docs as sibling `.md` files.
3. **The `subagent` extension**: one TypeScript file (or use the shipped
   example) that registers the tool — this is the "one small harness-specific
   shim" the port needs.
4. **`bin/cohort-*` scripts**: unchanged — they're already harness-agnostic.
5. **Extend-or-not decision**: `system-prompt`'s *per-turn context injection*
   is already native (AGENTS.md loads at startup, `/reload` refreshes). The
   hook's *dynamic* role (identity swap) has no Pi analog — and needs none.

## Pi-specific advantages over Claude Code, for Cohort

- **Open source, self-hostable, BYOK** — 20+ providers, `DeepSeek V4 Flash`
  is a verified option. Satisfies the corporate constraint harder than
  Claude Code does: no Anthropic account needed, no vendor lock.
- **The four-tool core is exactly Cohort's surface** (Read/Write/Edit/Bash —
  no call-home, no OAuth choreography).
- **Skills are portable across harnesses** (Agent Skills standard — shares
  with Claude Code and Codex). The same SKILL.md works on Pi, Claude Code,
  and Codex.
- **Per-agent model choice** (frontmatter `model:`) — Cohort's
  reviewer/qa/bug-fixer could use cheap models, Cohort could use a big one.
- **Extensions are plain TypeScript with real APIs**, not prompt-rewriting —
  a `before_agent_start` handler building `systemPromptOptions` is closer to
  Cohort's intent than Claude Code's opaque `additionalContext` hexing.

## Pi-specific caveats / unknowns

- **Subagents as separate processes** = some overhead per delegation (each
  spawns a fresh `pi` exec + session). Fine for Cohort's role count, but not
  a "zero-cost" story like Claude Code's in-process agents.
- **No built-in permission system** (README: "Pi does not include a built-in
  permission system... runs with the permissions of the user") — containerize
  for hostile inputs; Cohort's own trust stance is unaffected.
- **Skills need a `description` frontmatter** and are *progressive
  disclosure* — the model must decide to load them. Cohort's
  `/cohort-save` hooks fire deterministically; Pi's skill model requires
  prompting or `/skill:name` to force-load. (Same caveat as Claude Code
  skills.)
- **`extension` code is TypeScript + Bun/npm**, not bash — a small
  toolchain dependency for project-local extensions (though the shipped
  example is symlink-installable with no build).
- **Does not cache file contents** as aggressively; the real per-turn cost
  question is identical to any harness (context budget).

## The three-harness verdict, updated

| | Shelley (custom) | Claude Code (stock) | Pi (stock, OSS) |
|---|---|---|---|
| Role personas | system-prompt rewrite | .claude/agents/*.md | .pi/agents/*.md + subagent ext |
| Slash commands | hooks/slash/* shell | skills (/skill name) | skills + registerCommand |
| Subagent detection | SHELLEY_IS_SUBAGENT (needed) | agent_id/agent_type (native) | separate process (none needed) |
| Worktree isolation | bin/ scripts | --worktree (native) | git worktree + bin/ scripts |
| Universal context | hook injects | CLAUDE.md/AGENTS.md | AGENTS.md/CLAUDE.md native |
| Corporate-friendly | ✗ (custom build) | ✓ stock, closed | ✓✓ stock, open, BYOK, self-host |

Recommended posture: **design Cohort's engine as harness-agnostic markdown +
bin/ scripts (as this doc argues), and treat Pi as the reference adapter** —
it's the one that demonstrates the architecture *without* any custom harness,
and its extension model is the smallest shim of the three.
