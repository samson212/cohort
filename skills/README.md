# Cohort skills (slash commands)

Each subdirectory is one skill per the agent-skills standard
(`skills/cohort-<name>/SKILL.md` with `name` + `description` frontmatter).
The same files are what Claude Code (auto-registers as `/cohort-<name>`),
Pi (`/skill:cohort-<name>`), and Codex read natively — this directory is
the single source of truth across harnesses.

On Shelley, `cohort-init` symlinks `hooks/slash/cohort` into
`~/.config/shelley/hooks/slash/` once **per skill name** (each under its
cohort-<name>), and the dispatcher renders the matching SKILL.md in place
of `/cohort-<name> [args...]`. `$ARGUMENTS` in a SKILL.md body is replaced
with the args passed after the command name. See `bin/cohort-skill`.

| Skill | Description |
|-------|-------------|
| `cohort-save` | Review everything changed, stage what belongs, commit, display message |
| `cohort-sync` | Sync with the remote, show unpushed commits, push |
| `cohort-pr` | Create/update a pull request (always a draft) |
| `cohort-cleanup` | Close out a merged PR — clean up worktree/branch, update main |
