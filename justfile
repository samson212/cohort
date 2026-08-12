# vim: set ft=make :

set positional-arguments

# list available recipes
default:
	@just --list --unsorted --justfile {{justfile()}}

# create a new git worktree + branch off up-to-date main
new-worktree name:
    {{justfile_directory()}}/bin/cohort-new-worktree {{name}}

# commit staged changes using the message in the given file
commit message-file:
    {{justfile_directory()}}/bin/cohort-commit {{message-file}}

# push the current branch with upstream tracking
push:
    {{justfile_directory()}}/bin/cohort-push

# bootstrap Cohort into a project. Run from the project root.
init:
    {{justfile_directory()}}/bin/cohort-init
