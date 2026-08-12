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

## Complexity budget: delete before debating tools

When code looks over-engineered (N copies of nearly-identical logic,
a chain of scripts that could be one), the first question isn't "can I
rewrite this in bash" — it's "does the thing need to exist at all?"
Often the right fix is deletion, not refactoring. A single Python
script that does one job clearly beats three Python scripts with
duplicated boilerplate, regardless of whether any of them could have
been sed or jq.

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
