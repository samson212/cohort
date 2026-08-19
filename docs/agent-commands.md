# Agent skills

Cohort's slash commands are **skills**. Each is a self-contained prompt in
`skills/cohort-<name>/SKILL.md` using the agent-skills standard (`name` +
`description` frontmatter, `$ARGUMENTS` substitution) — the same format
Claude Code, Pi, and Codex read natively, so the file *is* the skill and
porting needs no copy or translation.

When a user sends a message starting with `/cohort-*`, the matching skill is
rendered in place of the message. The skill registry below names them and
gives a one-liner — nothing more, so it never drifts from the source
(`name`/`description` frontmatter in each `SKILL.md`).

| Skill (invocation) | File | What it does |
|--------------------|------|--------------|
| `/cohort-save` | `skills/cohort-save/SKILL.md` | Review, stage, commit, display message |
| `/cohort-sync` | `skills/cohort-sync/SKILL.md` | Fetch, show commits, push, display result |
| `/cohort-pr` | `skills/cohort-pr/SKILL.md` | Create draft PR or update description for the current branch |
| `/cohort-cleanup` | `skills/cohort-cleanup/SKILL.md` | Check unresolved comments, hand off merge, clean up worktree/branch, update main |
| `/cohort-update` | `skills/cohort-update/SKILL.md` | Update the Cohort engine to the latest main |

Invocation equivalents on other harnesses: Claude Code auto-registers a skill
at `skills/cohort-save/SKILL.md` as `/cohort-save`; Pi exposes it as
`/skill:cohort-save`. Shelley renders the same files through a single thin
hook — see `docs/portability.md` for the cross-harness contract.

`cohort-gh` (in `bin/`) is the sanctioned way to run the GitHub CLI on
this VM. `docs/cohort-gh.md` explains the exe.dev integration model —
no token on the VM, edge-injected auth, 403s on unproxied paths are
expected — and why bare `gh` does not work without it.
