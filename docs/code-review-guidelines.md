# Code review guidelines

Style and architecture preferences to apply during review, distilled from
actual review sessions. Update this file when a new preference comes up
often enough to be worth writing down.

## Don't let the same fact live in two places

If changing one thing (an order, a config value, a mapping) requires
touching N files that all have to agree with each other, that fact is
duplicated, not centralized. Look for this specifically when a small
conceptual change caused a surprisingly wide diff — that's often the
symptom, not the cost of the change itself.

Concrete example: an enum defined step order for an input wizard, but every
template *also* hardcoded its own successor step's name to build the "Next"
button. Reordering the enum required editing every template to match. The
fix was a `next_state` property that computes "what's next" from the one
canonical source (the enum, filtered by visibility) — nothing else needs to
name its successor again.

## Prefer implementation-agnostic calling code

Calling code should read declaratively and stay ignorant of *how* a value
is produced. If a caller needs to know the mechanism (skip hidden states,
walk an index, special-case a branch) to use something correctly, that
mechanism belongs behind a property or method on the owning object, not
repeated at each call site. Terse, boring call sites are a goal — `x.next`
beats `x.steps[x.i + 1] if visible else ...` inlined everywhere it's needed.

## Don't pass context the callee already owns

Before adding a parameter, identify its source of truth. If the value is
already authoritatively available from the receiver, a closure, or the
callable's defined execution context, derive it there instead of asking
callers to repeat it. Redundant inputs permit contradictory states and burden
every call site.

Keep parameters when the caller genuinely chooses the value, it varies per
invocation, or explicit injection improves isolation and testing. Don't
replace explicit dependencies with unrelated global state.

## Verify after mutation

Every tool that changes state should have its effect confirmed in the same
pass. `patch` → `git diff`. `gh pr create` → `gh pr view`. A script that
removes a worktree → check `git worktree list`. Exit codes lie — don't
trust them. Even "expected" warnings (like `gh pr create` reporting
"1 uncommitted change") deserve a second look before proceeding.

## Make failures loud

Three recurring ways code hides its own failure:

- **Suppressed errors.** `2>/dev/null || echo "already gone"` reports one
  cause for every failure. Let the real error through; branch on the exit
  status if you need to.
- **Unvalidated parsing.** String manipulation that can't fail (bash
  parameter expansion, a regex with a fallback) always produces *something*.
  Check the result is well-formed before using it — an empty-string check is
  not enough.
- **Effects assumed, not verified.** A command that exits 0 without doing its
  job is worse than one that errors. When a step has an observable effect,
  confirm the effect, not the exit code.

## Hunt for coupling disguised as a data-flow accident

Before removing a "redundant-looking" value passed between two pieces of
code, check whether some other logic silently depends on it being present
— not because it's structurally required, but because callers happened to
always supply it. Removing the duplication can silently break the
dependent logic if the dependency isn't traced first.

Concrete example: auto-generation of AI content on entering a step was
gated on `if to_state and ...` — which only ever fired because every
caller happened to pass `to_state` explicitly. Once callers stopped doing
that (to remove the duplication above), generation would have silently
stopped firing. The real invariant (`_should_generate` already checks the
correct preceding state) made the `to_state` gate redundant on inspection —
but that's only visible if you trace every reader of the value you're
about to stop populating.

## Distinguish "the default path" from "an explicit branch"

Sequential/default advancement through a process and a genuine conditional
redirect are different concerns and should be tested differently:
- Default advancement: check *position* (is this the immediately-next
  step?), not *name* (is the target literally called X?). Position-based
  checks survive reordering; name-based checks don't and don't generalize
  to alternate entry points (e.g. a side-nav jump that lands on the same
  step a different way).
- Genuine branches (skip this step under condition Y) are real logic and
  should stay explicit — don't try to fold them into the default-path
  helper just because they also change what's "next."

## Dead identical branches are a signal

When every arm of an `if`/`else` does the same thing, at least one branch
is dead. Don't just simplify the code — check whether the condition itself
was ever meaningful. If both branches were `git checkout -- "$f"`, the
file-exists check was the dead weight. The fix is deletion, not cleanup.

## Flag dead/unreachable code instead of routing around it quietly

If a code path is structurally unreachable (a step permanently excluded
from navigation, a branch whose condition can never be true), say so
explicitly as its own finding. Don't silently leave a workaround in place
that only makes sense because of the dead code, and don't silently "fix"
the dead code's own inconsistencies as a side effect of an unrelated
change — surface it and let the value of deleting it be a separate
decision.

## Blind spots to check for specifically in analyst-authored code

Domain experts writing code for the first time tend to solve the problem
in front of them correctly, but miss:
- **Implicit cross-file invariants** — e.g. two files that must be kept in
  sync by convention, with nothing enforcing it. Ask "what breaks if I
  change only one of these?"
- **Guard clauses whose necessity isn't obvious** — a condition that looks
  removable; check whether removing it changes behavior on some path
  before assuming it's dead weight.
- **Behavior that "just works" due to caller conventions** rather than
  being enforced by the type system or a clear contract. This is exactly
  the kind of thing that breaks quietly during a later refactor.

## Import style

Prefer `from module import specific_name` over `from package import
module` plus qualified call sites, for this codebase's own internal
modules. Not retroactively applied to the pre-existing `shared.services`
convention, which already does the latter — new modules only.

## Naming reduces cognitive load

A name (function, variable, recipe, command, option) should make the
reader's mental work as small as possible. If a name obscures what it
does — e.g. `save` for "commit", `ship` for "push" — rename it to match
the concept. A name is a promise; make the promise obvious.

## Defer to convention when there is doubt

When a choice is ambiguous, prefer the established convention over
invention. Conventions are the repo's accumulated decisions — the
default path is the one that already works. Don't add a new pattern
where an existing one covers the case, and don't silently deviate from
the documented one. (Example: the commit trailer is always
`Co-Authored-By: <model name>`, never a hardcoded or invented value.)

## Keep scope tight — "while I'm in here" is the enemy

Before building something adjacent to the ask, stop and ask: was this
requested? An agent's task scope is set by the user, not stretched by
proximity. "While I'm in here" additions (extra hooks, helper scripts,
quality-of-life features that "felt related") are the #1 source of
revertible code. The fix is usually deletion — the simpler the
solution, the smaller the diff to review.

The reviewer's job: flag every change that wasn't in the ask. "Related" is
not "requested." Even small, obviously-correct improvements on adjacent
files are revert risks — surface them so the author can decide whether they
stay or land separately.

## Complexity budget: delete before debating tools

When code looks over-engineered (N copies of nearly-identical logic,
a chain of scripts that could be one), the first question isn't "can I
rewrite this in bash" — it's "does the thing need to exist at all?"
Often the right fix is deletion, not refactoring. A single Python
script that does one job clearly beats three Python scripts with
duplicated boilerplate, regardless of whether any of them could have
been sed or jq.

## Ask whether an earlier point in the pipeline already knows the answer

When you see a piece of config, a template, or a parameterized value
that needs a "render" or "substitution" step to be usable, stop and ask:
where does the final value actually first become known, and is that
point an *earlier step in this same execution*? If so, generate the
concrete thing there instead of shipping a placeholder that some later
program must rewrite.

Symptoms that this applies:

- A template whose placeholders (`%u`, `%h`, `${USER}`, a config key)
  can never be resolved by the tool that reads them, so a *separate*
  script must string-substitute them before use — with escaping, empty
  guards, and "which user" logic for every possible invocation.
- The values being substituted are already known to the very installer
  that would do the substitution — e.g. an install script that knows
  `$HOME`/`$USER` but renders a unit with `User=%u`, then later resolves
  `%u` back to the same user it already had.
- A committed template file whose only consumer is a post-processor
  that makes it correct. The file doesn't run standalone; it's a broken
target waiting to be patched.

The fix is usually **deletion of the indirection**: write the literal
value at the point where it's known, and delete the placeholder + the
renderer. Concrete example: a systemd unit shipped as `bin/*.service`
with `User=%u`/`%h`, which systemd resolves to *root* for a system
unit — so install.sh had to sed-substitute the real user/home, escape
`&/\` in sed delimiters, guard against empty renders, and re-derive the
user from `SUDO_USER`/`id`. But install.sh had `$HOME`/`$USER` at the
top of the script. The whole template+escape+guard machinery existed
only to express "the user I already am." Generating the unit inline
from `$DASH_USER`/`$DASH_HOME` and deleting the committed template
removed the entire category.

Caveat: this is not an argument against all templating. The check is
whether the *consumer* can resolve the placeholder itself. If the
tool reading the config naturally expands it (shell `${VAR:-}`,
openssl envsubst, systemd's own specifiers where they resolve
correctly), the placeholder is fine. The target is a placeholder that
is *guaranteed wrong* until an unrelated program rewrites it.

## Try an alternative-approaches pass

After the first findings pass, step back and ask: is there a
substantively different way? The best finding isn't a bug — it's a
simpler design. Concrete example: a `new-conversation` hook with
Python+JSON parsing worked, but asking "would a different hook be
cleaner?" surfaced `system-prompt` — plain text I/O, bash instead of
Python, fires for subagents automatically, eliminates three problems
in one move. The alternative-approaches pass is not about nitpicking
the implementation; it's about finding the approach that makes the
implementation trivial.
