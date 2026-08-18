# Cohort dashboard deployment — design doc

Status: **design** (approved for a fresh implementation session).

Supersedes the ad-hoc dashboard install in `install.sh` and the earlier
`active`-link idea (a shared symlink that agents flip). It failed on
parallelism: one shared mutable target means whichever agent runs a
lifecycle script last wins, and every other agent's service silently
re-targets. We don't flip a single target; we run one instance per
worktree and never mutate a shared thing during branch work.

## Non-goals (settled)

- **No browser default.** The dashboard runs on its own dedicated port.
  Once this lands, we will be developing two repos side by side on one
  VM — cohort and a target repo — so the default browser port stays with
  the target repo's dev server; the dashboard is a separate, explicit
  thing. Default dedicated dashboard port: **6283 = round(τ × 1000)**.
- **No `active` link in the agent path.** Dropped. It cannot be a
  per-worktree mechanism, so it buys nothing and adds a shared global
  that agents would have to coordinate on.

## Core principle

Two service shapes, separated by where the code lives and who owns the
lifecycle:

- **Production** — one static instance, code from the engine clone
  (main), managed by `install.sh` + `cohort-update`. Survives
  `cohort-cleanup` (never runs from a worktree). Always matches main.
- **Preview** — per-worktree instances, code from the branch's worktree,
  managed by lifecycle scripts. Ephemeral: comes up with the worktree,
  torn down by `cohort-cleanup`. This is the bootstrapping answer:
  deployment work gets a real named install, real systemd, and a real
  wire probe — all scoped to the branch.

**A service must never run from a worktree in production.** `cohort-
cleanup` deletes worktrees, so anything whose code lives at
`~/worktrees/<topic>/...` dies with it. Production code always comes from
the engine clone; only preview instances run branch code.

## Worktree layout: repo-namespaced

Two repos may share a VM. Topic names are not globally unique, so the
**worktree path itself** must namespace by repo, or two repos developing
the same topic collider on `~/worktrees/<topic>`:

    ~/worktrees/<repo>--<topic>

`<repo>` is the last path component of the origin URL with `.git`
stripped (e.g. `cohort`, `myproject`). This is the single canonical fact
worktrees, preview instances, and paths derive from.

Consequences:

- `cohort-new-worktree <topic>` creates `~/worktrees/<repo>--<topic>`,
  branch `agent/<topic>`.
- `cohort-move-to-worktree <topic>` and `cohort-cleanup` follow the same
  layout.
- The old flat layout `~/worktrees/<topic>` is legacy; existing
  worktrees are migrated lazily (rename or leave, but new work is namespaced).

## Unit files (shipped in engine main)

Production (static):

```ini
[Unit]
Description=Cohort worktree & PR dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=PATH=%h/.cohort/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=%h/.cohort/bin/cohort-dashboard --refresh 30
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
```

Port: the script reads `~/.config/cohort-dashboard/config`; default 6283
when absent. Production uses the config file — no `--port`, no env var,
no drop-in. `install.sh` ships/enables this unit, and `cohort-update`
keeps it in sync with main; it never runs from a worktree.

Preview (template, per-worktree) — instance name carries everything:

```ini
[Unit]
Description=Cohort dashboard preview (worktree %i)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=PATH=%h/.cohort/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=%h/.cohort/bin/cohort-dashboard-instance %i
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
```

`%i` is the **instance name** = `<repo>--<topic>--p<port>`. A tiny
helper, `cohort-dashboard-instance` (engine bin), parses the name and
execs with the right env:

```bash
#!/bin/bash
# cohort-dashboard-instance <repo>--<topic>--p<port>
# Parse & exec the dashboard with the right worktree and port.
name="$1"
repo="${name%%--*}"; rest="${name#*--}"
topic="${rest%%--p*}"
port="${rest##*--p}"
exec env COHORT_DASHBOARD_PORT="$port" "$HOME/worktrees/$repo--$topic/bin/cohort-dashboard" --refresh 30
```

Started by `cohort-dashboard-serve`:

```bash
cohort-dashboard-serve <topic>          # in a worktree; picks a free port, starts preview
cohort-dashboard-serve --port P <topic> # explicit port
```

Which bind-tests for a free port, then
`systemctl --user start cohort-dashboard-preview@<repo>--<topic>--p<port>`
and probes `/healthz` on the assigned port (verify after mutation), then
prints the URL (default `https://<vm>.exe.xyz:<port>/`).

## Port allocation

- Production: 6283 = round(τ × 1000). Owned by the config file only.
- Preview: nearest free port ≥ 6300, bind-tested at `serve` time,
  encoded in the instance name. Freed on `cohort-cleanup` (stop + remove
  instance). No central registry — the port is derived from the instance
  name, which is derived from the worktree name. Nothing else needs to
  know it.

## Lifecycle integration

- `cohort-new-worktree <topic>` → namespaced path; nothing else.
- `cohort-move-to-worktree <topic>` → namespaced path; nothing else.
- `cohort-dashboard-serve <topic>` → free port, start preview, verify.
- `cohort-dashboard-stop <repo>--<topic>--p<port>` (or topic) → stop,
  remove instance.
- `cohort-cleanup` → stop/remove the preview instance for the worktree
  it's deleting, then proceed (remove worktree, delete branch, ff main).

`cohort-cleanup` must tear down the preview *before* `git worktree
remove`, so no orphan instance points at a deleted directory.

## Env-in-script vs drop-ins (design decision)

Port and other per-instance parameters are **passed in the environment**
(`COHORT_DASHBOARD_PORT`) or **encoded in the instance name** — never
via systemd **drop-ins** (`*.d/*.conf`) or by mutating a shared
`~/.config/cohort-dashboard/config` from an agent.

Why: drop-ins and a shared config file are **unbounded mutable shared
state** — exactly what parallel agents must not race on. A drop-in is a
file that the same worktree edit can never produce a conflict-free
change to (two agents writing config for two previews both mutate the
same directory/file). The instance name is a *parameter*, not state:
creating `cohort-dashboard-preview@a--b--p6301` cannot collide with
`...p6302`, and removing one cannot affect the other. Environment is
process-scoped, so it can't leak across instances.

This should be codified as an explicit guideline (code-review-
guidelines.md): **prefer instance-name parameterization over drop-ins
for per-instance unit tuning; prefer env vars over generated config
files.** Drop-ins are for *static, machine-wide* overrides, not for
dynamic per-instance state.

## The gh-env contract (from the dashboard branch review)

Not part of this design's scope, but the preview/production split makes
it testable in isolation: a preview instance with `COHORT_NO_GH=1`
(exercising the degraded path) must report `pr_enriched: false` with a
`pr_error`, per the design doc. When the dashboard branch lands, this
becomes a preview smoke test.

## Migration

1. Remove the stale **system** unit / drop-in
   (`/etc/systemd/system/cohort-dashboard.service*`) that this VM still
   runs — the old install left it enabled with a hardcoded worktree
   path; it must not survive.
2. Remove the ad-hoc **user** unit copy
   (`~/.config/systemd/user/cohort-dashboard.service`) — replaced by the
   engine-shipped static unit + templates.
3. `cohort-update`; re-run `install.sh` (idempotent; ships unit, enables
   linger, starts prod on 6283).
4. Rename existing worktrees to `~/worktrees/<repo>--<topic>` lazily.

## Implementation checklist (fresh session)

- [ ] `bin/cohort-dashboard-instance` (parse/exec helper) + unit
      templates in engine main.
- [ ] `bin/cohort-dashboard-serve` / `-stop` (free-port, start, probe;
      stop/remove).
- [ ] `bin/cohort-new-worktree` / `-move-to-worktree`: namespaced paths.
- [ ] `bin/cohort-cleanup`: stop preview before remove worktree.
- [ ] `bin/cohort-dashboard`: honor `COHORT_DASHBOARD_PORT` before the
      config file; keep 6283 default.
- [ ] `install.sh`: ship static unit + templates; remove (or hard-warn
      on) stale system/user units; idempotent.
- [ ] Docs: `docs/engine-install.md`, `docs/git-workflow.md`;
      `code-review-guidelines.md` drop-in preference.
- [ ] Smoke: prod on 6283; two previews side by side on distinct free
      ports; cleanup stops them.
