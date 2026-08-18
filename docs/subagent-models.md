# Subagent models

Shelley pins subagents to a default model via the `-subagent-default-model`
server flag. Cohort's installed Shelley is configured with
`deepseek-v4-flash-0731`, so subagents spawned without an explicit `model`
parameter run on that model — regardless of what model the parent
conversation is using.

Consequences for how Cohort delegates:

- **Do not pass a `model` parameter when spawning a subagent unless the
  task genuinely requires a stronger model.** The pinned default is cheap
  and fast, and it is the intended workhorse for reviews, QA passes, and
  doc maintenance.
- **If a task truly needs a heavier model** (deep architectural analysis,
  resolving a hard merge conflict, writing subtle concurrency code), pass
  `model="gpt-5.6-sol"` (or another listed model) explicitly. The subagent
  tool accepts only the models listed in its description; anything else is
  rejected.
- **Never call `cohort-model-name` to "pick a subagent model"** — that
  script exists only to stamp the `Co-Authored-By` commit trailer and
  prints the *parent's* model. Subagent model choice is the server
  flag + explicit `model` parameter, not the commit-trailer helper.

If you want to change the pinned subagent model, set
`-subagent-default-model` in the Shelley systemd unit
(`/etc/systemd/system/shelley.service`) and restart; no Cohort change
needed.
