# vim: set ft=make :

set positional-arguments

# list available recipes
default:
	@just --list --unsorted --justfile {{justfile()}}

# create a new git worktree + branch off up-to-date main, without
# accidentally tracking origin/main (git's default tracking behavior when
# branching directly off a remote ref)
new-worktree name:
    git fetch origin main
    git worktree add -b agent/{{name}} $HOME/worktrees/{{name}} origin/main --no-track

# commit staged changes using the message in the given file. Called from
# /git-commit's flow, after that command's own review/staging/message-draft
# steps, and before the push steps -- deliberately commit-only, so the
# git-push sync check can run against a commit that already exists.
commit message-file:
    git commit -F {{message-file}}

# push the current branch, creating/refreshing upstream tracking either way
# (safe to always pass -u: it's a no-op if tracking is already correct).
# Called from /git-commit's flow, after that command's own /git-push-derived
# sync-and-confirm steps.
push:
    git push -u origin $(git branch --show-current)
# symlink repo hooks into ~/.config/shelley/hooks/ so they fire
install-hooks:
    mkdir -p ~/.config/shelley/hooks
    ln -sf "{{justfile_directory()}}/hooks/system-prompt" ~/.config/shelley/hooks/system-prompt
