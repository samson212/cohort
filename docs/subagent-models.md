# Subagent models

Shelley pins subagents to a default model via the `-subagent-default-model`
server flag. Cohort's installed Shelley is configured with
`deepseek-v4-flash-0731`, so subagents spawned without an explicit `model`
parameter run on that model — regardless of what model the parent
conversation is using.

Consequences for how Cohort delegates:

- **Do NOT pass a `model` parameter when spawning a subagent for routine
  work.** The pinned default is cheap and fast, and it is the intended
  workhorse for code reviews, QA passes, doc maintenance, and every other
  delegation that doesn't genuinely need a heavier model. Passing an
  explicit `model` for such work is a convention violation.
- **An explicit `model` is reserved for tasks that truly need it**: deep
  architectural analysis, resolving a hard merge conflict, writing subtle
  concurrency code. Even then, the subagent tool accepts only the models
  listed in its description; anything else is rejected.
- **Explicit overrides are loud, not silent.** When an agent passes a
  `model` that differs from the pinned default, Shelley logs a warning
  (`subagent: explicit model override of pinned default`) containing the
  pinned default, the chosen model, and the slug. That warning is a
  deliberate signal: if it fires on routine work, the delegation was
  wrong. Don't habitually trigger it.
- **Never call `cohort-model-name` to "pick a subagent model"** — that
  script exists only to stamp the `Co-Authored-By` commit trailer and
  prints the *parent's* model. Subagent model choice is the server
  flag + explicit `model` parameter, not the commit-trailer helper.

If you want to change the pinned subagent model, set
`-subagent-default-model` in the Shelley systemd unit
(`/etc/systemd/system/shelley.service`) and restart; no Cohort change
needed.
