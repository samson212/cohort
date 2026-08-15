# Review — `agent/git-guard`

Reviewed: commits `a2ff19d`, `6ac00ff`, `c8fd7ae`, `64ea0bd` (`806b1ea..HEAD`)
plus the staged, uncommitted diff on top. Every claim below was verified by
running it. Test harness lived in `/tmp` and has been deleted; the live VM was
never put into an enforcing state.

## Bottom line up front

**Do not merge.** Two of the four blockers mean the feature has never
successfully run: `cohort-init --enforce-git` aborts before it does anything,
and the sanctioned commit path it documents points at a binary that doesn't
exist. Beneath the bugs, the threat model does not hold — the mechanism is
bypassed by a full second copy of git that ships with the OS at
`/usr/lib/git-core/git`, and by a one-word environment change. The approach
should be abandoned rather than repaired.

---

## Findings

| # | Severity | Finding | Recommendation |
|---|----------|---------|----------------|
| 1 | **Blocker** | `cohort-init` step 4a runs `cp "$ENGINE_ROOT/bin/git" "$HOME/.cohort/bin/git"`, but `~/.cohort` is a symlink to `~/cohort` — source and destination are the same file, `cp` exits 1, and `set -e` aborts the script before 4b/4c/4d ever run. | Delete the copy; the engine file is already on PATH via the symlink (see #10). |
| 2 | **Blocker** | `commands/cohort-commit.md` and `cohort-push.md` hardcode `/usr/bin/git.do.not.call`, which does not exist unless `--enforce-git` was run with root — on this VM it exits 127. The sanctioned commit path is broken on every machine that hasn't opted in, which is all of them. | Never hardcode the obscured path; the commands should call plain `git` and let the wrapper's own allow-path handle it. |
| 3 | **Blocker** | The threat model fails: `/usr/lib/git-core/git` is a **separate 4 MB copy** (different inode, not a hardlink) that is fully functional, plus 166 sibling binaries including `git-push`, `git-commit`, `git-rebase`. Renaming `/usr/bin/git` obscures nothing. | Abandon the PATH-shim approach (see Alternatives). |
| 4 | **Blocker** | The staged arg-walking loop produces rampant false positives — verified blocked: `git stash push -m wip`, `git checkout push`, `git log push`, `git add commit`, `git branch -d push`, `git rev-parse push`, `git diff -- push`, `git svn rebase`, `git subtree push`, `git cherry-pick rebase`. Any ref or pathspec named `push` bricks ordinary work. | If kept at all, parse only the first non-flag token as the subcommand and stop (reference implementation in Appendix A). |
| 5 | **High** | The `-*` "skip other flags" arm is wrong for value-taking flags in separated form: `--git-dir push status` treats the *path* `push` as the subcommand and blocks it. Only `-C`/`-c` consume their value; `--git-dir`, `--work-tree`, `--namespace`, `--exec-path` do not. | Enumerate all value-taking global flags, or use `git rev-parse --parseopt`-style handling. |
| 6 | **High** | `[[ -t 0 ]]` is unsound in **both** directions — verified: a human running `git commit -m x < /dev/null` or piping a message is **blocked**, while an agent under `script -qec "git push"` (a PTY) sails **through**. | Drop the TTY proxy entirely; it cannot distinguish agent from human (see Alternatives). |
| 7 | **High** | The marker is looked up at `$HOME/.cohort/enforce-git`, and `$HOME` is caller-controlled — verified: `HOME=/tmp git push` and `env -i git commit` both pass straight through. | Unfixable in-process; an in-band control cannot gate a caller that owns the environment. |
| 8 | **High** | `cohort-init --enforce-git` mutates `/usr/bin` system-wide, irreversibly, with **passwordless sudo available on this VM** — it would rename the system git with no prompt, and there is no `--disable`/uninstall path. | Do not ship system mutation; if it must exist, pair it with a tested reversal command. |
| 9 | **High** | The untracked `bin/git` and `bin/git-real` that an earlier iteration copied into `~/cohort` now **block merging this very branch** — verified: `error: The following untracked working tree files would be overwritten by merge: bin/git`. | Delete both from `~/cohort` before any merge; this is live breakage, not hypothetical. |
| 10 | **High** | `cohort-update` re-copies the wrapper "because `~/.cohort/bin/git` is a copy, not a symlink" — but it is the *only* file treated that way, and since `~/.cohort` → `~/cohort` the copy is a self-copy that fails (#1). Every sibling script is simply the engine's own file on PATH. | Remove the special case; git is not special, and a stale copy silently diverging from the engine is a bug the other scripts don't have. |
| 11 | **Medium** | Step 4b's failure model is incoherent with 4c: 4b *downgrades* an un-obscured git to a warning ("the wrapper will still block agents"), then 4c *hard-exits*. Worse, 4c only compares `type -p git` against the wrapper it just deployed — it verifies PATH ordering, not that enforcement works, so it passes in exactly the degraded state 4b tolerated. | Make one decision: either obscuring is required (fail hard in 4b) or it isn't (don't fail in 4c). Verify the *effect* — try a blocked command — not the PATH. |
| 12 | **Medium** | 4b's interactive fallback runs `sudo mv ... 2>/dev/null`, which suppresses sudo's password **prompt** along with its errors — the user sees a silent hang or an unexplained warning. Violates "make failures loud". | Never redirect sudo's stderr; branch on its exit status instead. |
| 13 | **Medium** | The `/bin/git` cleanup branch is dead code on any merged-`/usr` system: `/bin` is a symlink to `usr/bin`, so `/bin/git` is not a symlink and the `[[ -L /bin/git ]]` guard never fires — and after the `mv`, `/bin/git` is gone automatically anyway. | Delete the branch; per the guidelines, dead branches are a signal, and the fix is deletion. |
| 14 | **Medium** | `~/.cohort/bin/git-real` is an orphan: it exists nowhere in the repo, in no commit, and nothing references it — a sanctioned bypass shipped by hand to one VM. (Its missing self-shadow guard is *not* the issue: it probes absolute paths and isn't named `git`, so it can't self-shadow. The issue is that an undocumented escape hatch exists at all.) | Delete it; an escape hatch nobody can audit is worse than no enforcement. |
| 15 | **Medium** | Commit `c8fd7ae` (default project name from the origin remote) is unrelated to git enforcement — textbook "while I'm in here" scope creep on a branch that should cover one concern. | Move to its own branch; it's a reasonable change that shouldn't be held hostage to this one. |
| 16 | **Low** | `cohort-init`'s arg loop lets any unrecognised flag fall through `*)` and become the project name — `cohort-init --enfroce-git` silently names the project `--enfroce-git`. | Reject unknown `-*` arguments explicitly. |
| 17 | **Low** | `REPO_NAME` is derived by `basename` + `%.git` with no validation of the result — unvalidated parsing that always produces *something*. | Check the result is a plausible repo name before stamping it into `prompt.md`. |
| 18 | **Low** | `docs/engine-install.md` states the wrapper is "the only `git` an agent can reach" and that the real binary "can't be invoked behind its back" — both are factually false (#3, #7). | If any of this survives, the docs must state the bypasses plainly. |
| 19 | **Praise** | The staged diff genuinely improves three things: ordering 4a→4d so a failure leaves no marker, verifying `git.do.not.call` exists *after* the `mv` rather than trusting the exit code, and fixing the missing newline at EOF. | Keep this instinct — it's the "verify after mutation" principle applied correctly. |

---

## Why this doesn't work, plainly

The branch is trying to solve a **compliance** problem with a **security**
mechanism, and it loses on both counts.

The wrapper only stops an agent that isn't trying to get around it. An agent
willing to ignore the prose in `git-workflow.md` is equally willing to run
`/usr/lib/git-core/git push`, or `HOME=/tmp git push`, or `script -qec "git
push"` — all verified working. So the population it actually blocks is the
population prose already blocked. Meanwhile the cost is paid by everyone:
`git stash push` stops working, `git checkout push` stops working, a human
piping a commit message gets refused, and the system git is irreversibly
renamed on a machine that other tooling shares.

The `[[ -t 0 ]]` check is the tell. There is no reliable in-band signal that
distinguishes "agent" from "human" — that information exists one layer up, in
whatever is *invoking* the shell. Any mechanism that has to guess is going to
be wrong in both directions, and this one is.

The notes ranked branch protection and a Shelley command-denial hook above
this, and that ranking was right. Branch protection is the only control not on
the agent's machine, and the Shelley hook is the only one that sits where the
agent/human distinction is actually known. Building the PATH shim instead
skipped both the strongest option and the correct-layer option in favour of
the one that mutates `/usr/bin`.

There is also a governance smell worth naming: this branch's own
`/cohort-commit` path was rewritten to call `/usr/bin/git.do.not.call`, i.e.
the enforcement mechanism carved out a privileged hole for itself, and that
hole is a plain filesystem path any agent can read out of the command file and
call directly. A control whose bypass is documented in the prompt is not a
control.

---

## Alternative-approaches pass

**What I'd build instead, in priority order:**

1. **GitHub branch protection / rulesets on `main`** — require a PR, block
   force-pushes, block deletions. Cost: a few minutes in the GitHub UI, zero
   code, zero maintenance. This is the only control that is not on the
   machine the agent controls, and it defends the thing that actually matters
   (the shared history). It makes the entire local-enforcement question a
   convenience issue rather than a safety issue.

2. **A Shelley command-denial hook** — inspect the command the agent is about
   to run and refuse `git commit`, `git push`, `git rebase`, `--no-verify`,
   `reset --hard`, `branch -D`. This is strictly better than the PATH shim on
   every axis: it needs no root, mutates nothing outside the config dir, is
   undoable by deleting one file, sees the literal command string so it never
   has to re-implement git's option parser, and — decisively — it runs *only*
   in the agent's execution path, so the agent/human distinction is structural
   rather than guessed. It also can't be dodged by `/usr/lib/git-core/git`,
   because it matches on the command the agent typed rather than on which
   binary PATH resolves to. Cost: roughly the size of `bin/git` as it stands
   today, minus the TTY logic, the marker, the `/usr/bin` mutation, and
   `cohort-update`'s copy step — call it a net deletion.

3. **A local `pre-push` hook** for accident prevention, with the honest caveat
   already recorded in the notes: `--no-verify` walks through it. Worth having
   because it converts a silent mistake into a deliberate one, not because it
   enforces anything.

**What I'd delete:** `bin/git` in its entirety, the whole `--enforce-git`
branch of `cohort-init` (4a–4d), `cohort-update`'s wrapper re-deploy, the
`/usr/bin/git.do.not.call` references in both command files and the docs, and
the orphaned `~/.cohort/bin/git-real`. Retain commit `c8fd7ae` on a separate
branch. Per the complexity-budget guideline, the first question was never "can
this parser be fixed" — it was "does this need to exist," and the answer is no.

---

## Appendix A — reference parser

Only if a wrapper survives this review. Verified to block `commit`/`push`/
`rebase` (including behind `-c`, `-C`, and `--git-dir=X`) while passing
`git stash push`, `git checkout push`, `git log push`, `git add commit`,
`git diff -- push`, `git --git-dir push status`, and `git commit-tree` with
arguments arriving intact:

```bash
args=("$@"); subcmd=""; i=0
while (( i < ${#args[@]} )); do
  case "${args[i]}" in
    -C|-c|--git-dir|--work-tree|--namespace|--exec-path|--config-env|--super-prefix)
      (( i += 2 )) ;;
    --) break ;;
    -*) (( i += 1 )) ;;
    *)  subcmd="${args[i]}"; break ;;
  esac
done
```

Note this still does not address findings #3, #6, or #7 — it fixes the parser,
not the approach.
