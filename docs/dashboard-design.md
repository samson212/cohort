# Cohort dashboard — design

The dashboard is a zero-dependency view of the Cohort engine's working set:
every worktree, its dirty state, its PR, and the branches that linger
without a worktree. It runs as a single Python stdlib HTTP server and is
meant to be read from a browser, refreshed periodically, and trusted to
never fall over — including when GitHub's API is slow or down.

It is environment-agnostic by design: the server binds a port and serves
relative paths. It binds **127.0.0.1 by default** (`--bind 0.0.0.0` to
expose), so without a proxy/reverse it is reachable only locally.
Whatever domain, reverse proxy, or auth layer wraps it is
an external concern; the exe.dev proxy reaches it by forwarding to the
bound interface even when loopback. On an exe.dev VM users typically expose it through
the built-in HTTPS proxy; on a local machine they access it via
`http://localhost:6283`. The port is set at install time with
`cohort-init --dashboard-port` and stored in a config file.

There is deliberately **no domain in the config**: the page serves only
root-relative URLs (`/api/data`), which resolve against whatever origin
the browser loaded the page from, so the same server works unchanged
behind any proxy — same host, different port, localhost, or a custom
domain. A hardcoded `<base href>` would point the fetch at a fixed
origin and break every other entry point (e.g. a proxy that maps a
non-default port). **A `<base href>` injection at a fixed origin caused
a real outage** (the page loaded but `/api/data` fetched the wrong
origin and the browser blocked it) — root-relative URLs only, never a
`<base href>`. The config file therefore holds only the port.

This document captures the current design. It is the source of truth for
how the pieces fit; the code in `bin/` is the implementation.

## Why it exists

Cohort's workflow is worktree-centric: one worktree per task, branches
under `agent/`, PRs opened from them, cleanup after merge. The state of
that working set is spread across `git worktree list`, `git status`,
`git log`, and the GitHub PR list. The dashboard collects all of it into
one page so an operator can see, at a glance:

- which branches have worktrees and what state they're in
- which worktrees have uncommitted changes (and how many files)
- which branches are ahead of / behind their upstream or the default branch
- which PRs are open, draft, or merged for each branch
- what needs the operator's attention, in one place (an "Action required"
  section: draft PRs, reviews pending, changes requested, ready to merge,
  merged-but-lingering worktrees/branches)
- which branches exist locally but were never pushed (unlinked, no decoration)
- which branches were deleted from the remote after their PR merged (rendered grey)
- which branches exist only on the remote (no local ref, no worktree)
- which local branches no longer have a worktree (cleanup candidates)

## Components

One script, one process. The old three-file split (git-only `prep`, gh-only
`pr`, HTTP server) is merged: local git reads and GitHub calls both run
in-process, and the collection half is exposed standalone with
`--json-only` (the independently testable boundary the split used to
buy).

```
bin/cohort-dashboard        # collect (git+gh) and serve — one process
```

Pipeline:

```
       git worktree list ─┐
       git status         │
       git for-each-ref   ├─► collect_git ─► collect_gh ─► payload
       git rev-list       │        │
       git remote get-url ┘    gh (repo view, pr list)
```

- **collect_git** runs entirely against local git. It can never crash on
  the network because it never touches it. It produces the self-contained
  JSON document (below).
- **collect_gh** makes up to two `gh` calls per repo (`repo view` for the
  canonical web URL, `pr list --state all` for PRs) and enriches the
  document. If `gh` fails or the `COHORT_NO_GH` env guard is set, the
  collection returns the data unchanged — the dashboard degrades to
  git-only rather than erroring.
- **server** runs the pipeline on a TTL, caches the result, and serves
  the HTML page and the JSON. It is the only long-lived process.

`--json-only` prints the payload without starting the server — the
collection pipeline is independently testable (pipe it to
`python3 -m json.tool` or feed it to scripts) without the server, the
boundary the old three-script split used to enforce by process isolation.

The systemd unit is a static user unit shipped in the repo
(`bin/cohort-dashboard.service`); install.sh symlinks it into place.

## Data model

One JSON document per scrape:

```
{
  "generated_at": "…Z",            # when collect_git ran
  "collected_at": "…Z",            # when the server cached it
  "refresh_interval_ms": 30000,    # the server's --refresh, in ms
  "pr_enriched": true,             # false when gh was skipped/failed
  "pr_error": null,                # set when gh failed (non-fatal)
  "repos": [
    {
      "root": "/home/exedev/major",   # primary checkout (dedup canonical)
      "name": "major",
      "remote": "…",
      "web": "https://github.com/…",   # canonical browser URL (gh-derived)
      "default_branch": "main",
      "worktrees": [ … ],              # every checkout, incl. primary
      "orphans": [ … ],                # local branches w/o worktree
      "remote_only": [ … ],            # remote branches w/o local ref
      "actions": [ … ]                # everything needing attention (merged across groups)
    },
    … # further repos; the Cohort engine repo always sorts LAST
  ]
}
```

### repo ordering

The engine repo is identified by the canonical root of the directory this
script ships in (`git_common_root_of(__file__)`, the same common-git-dir
dedup the scanner uses), and its entry is moved to the tail of `repos`.
All other repos keep discovery order. This is computed in `collect_git`
so `--json-only` and the server agree.

### worktree entry

```
{
  "path": "/home/exedev/worktrees/foo",   "branch": "agent/foo",
  "is_primary": false,                    "on_remote": true,
  "head": "<40-hex>", "head_short": "…",
  "staged": 1, "unstaged": 2, "untracked": 0, "dirty_files": 3,
  "upstream_ref": "origin/agent/foo",
  "ahead": 2, "behind": 0, "commits_since_default": 2,
  "subject": "…", "days_since_last_commit": 1.2,
  "status": "dirty",           # dirty | unpushed | deleted | up to date | local
  "pr_number": 12, "pr_state": "MERGED", "pr_url": "https://github.com/…/pull/12",
  "pr_draft": false
}
```

The per-worktree `pr_*` enrichment is limited to the four fields the page
reads (`pr_number`, `pr_state`, `pr_draft`, `pr_url`); the Open-PRs table
gets its richer fields directly from `gh` in `collect_gh`.


### orphan entry

A local branch with **no worktree** (its worktree was cleaned up but the
ref lingers). Fields: `branch`, `upstream_ref`, `on_remote`, `merged`,
`commits_since_default`, `subject`, `head`/`head_short`,
`days_since_last_commit`, plus `pr_*` enrichment when a PR matches.

### remote_only entry

A **remote-tracking** branch with no local branch and no worktree (a
cleaned-up merged PR head). Fields: `branch`, `head`, `head_short`,
`merged`, `commits_since_default`, `subject`, dates, plus `pr_*`.

## Status classification

For each worktree, a single status string drives the pill. It is computed
in the gh stage, after live-branch reconciliation, so the label reflects
reality (collect_git's local-git-only status is **always** reclassified
for worktrees — even when the live check is skipped via `COHORT_NO_GH`
or fails, the labels never leak collect_git's intermediate
`idle`/`noupstream`):

| status | meaning | link behavior |
|---|---|---|
| `dirty` | uncommitted changes present | PR page, else compare |
| `unpushed` | ahead of upstream (commits not pushed) | PR, else compare |
| `deleted` | was on the remote, branch removed after merge | PR page, else none |

A worktree with `deleted` status **and a `MERGED` PR** is a cleanup
candidate, but cleanup isn't the only thing the operator needs to know.
Instead of a single cleanup section, the page lifts **everything that
needs attention** across all three groups (worktrees, orphans,
remote_only) into one **"Action required"** section at the top. Each
entry carries an `action_required` label from `enrich()`:

| action | meaning |
|---|---|
| `mark-ready` | PR open but still in draft — mark it ready for review |
| `changes-requested` | PR open, review asked for changes — address the review |
| `awaiting-review` | PR open & ready, no decision yet — get it reviewed |
| `ready-to-merge` | PR open, review approved — merge it |
| `merged-cleanup` | PR merged; worktree/branch still exists — run `cohort-cleanup` |

The section replaces the old Open-PRs table (redundant: every open PR's
head branch maps to a worktree, orphan, or remote_only entry, all of
which are enriched) and the old cleanup-only section. A `deleted`
worktree without a `MERGED` PR (branch removed without merging, or gh
unavailable) stays in the main worktree table: `cohort-cleanup` would
refuse it (its tip isn't an ancestor of the default branch), so it isn't
"cleanup-ready."
| `up to date` | clean, exists on the remote | tree page (or PR) |
| `local` | clean, never pushed / no upstream | none (unlinked) |

`deleted` carries the final say on tree/compare linkability: a branch
deleted from the remote loses its tree/compare links and its name renders
grey — its PR page (if any) and head-SHA link (the merged commit
lives in the default branch) still link. `local` branches are unlinked and
plain: no decoration, they just don't link. Action-required rows render
their branch, PR badge, action pill, and age — the rest of the row's
cells are not applicable (clean, not ahead, no tree page).

`dirty` wins. If there is a PR for the branch, its PR page is linked
regardless of status.

## Link semantics

The dashboard links to GitHub pages in the operator's **browser**: branch
names → `/tree/<branch>`, head SHAs → `/commit/<sha>`, status pills →
PR page if a PR exists, else `compare/default...branch` for
dirty/unpushed/new, else the tree; the "ahead" count links to the compare
page; PR rows link their branch and title to the PR.

The web base (`repo.web`) comes from **`gh repo view --json url`**, not
from the git remote. On this VM the origin remote points at an internal
mirror (`github.int.exe.xyz`) used only for push/pull; the dashboard is
read from a client machine that reaches GitHub's public domain. gh reports
the canonical public URL, so all links use it. When gh is unavailable
(`COHORT_NO_GH` or a failed call), collect_git's origin-derived URL is the
fallback — degraded but functional.

Branches not on the remote have no `/tree/`, `/commit/`, or `/compare/`
page. How they render depends on why they're not on the remote:

- **Deleted upstream** (was on the remote, branch removed after the PR
  merged): the branch name renders grey and has no tree/compare link.
  The head SHA still links to `/commit/<sha>` — the merged commit is
  reachable from the default branch, so that page is alive.
- **Local-only** (never pushed / no upstream): unlinked and plain — no
  grey, no decoration. The head SHA is also unlinked (those
  commits don't exist on GitHub).

Both keep their PR badge if a PR exists — the PR page is still valid after
its branch head is deleted.

PR URLs from gh are re-homed to `repo.web`'s host if they differ (gh can
return the canonical `github.com` host even when the API went through a
mirror). This is a defensive normalization; with gh's `repo view` URL as
the base it is usually a no-op.

## Deployment

The dashboard runs as a systemd **user** unit shipped in the repo
(`bin/cohort-dashboard.service`). A user unit's `%h` resolves to the
user manager's home (the owner of the unit), so a single static file
serves every user — `install.sh` just symlinks it into
`~/.config/systemd/user/` and starts it:

```
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

- **User units, not a generated system unit.** The old install.sh wrote
  a system unit with the real user/home baked in (a `%u`/`%h` template
  in a system unit resolves to **root**, not the invoking user). A user
  unit resolves `%h` to the right home automatically, so no
  generation, no SUDO_USER ladder, no root/sudo needed at all.
- **Linger.** User services only start at boot when linger is enabled for
  the user (`loginctl enable-linger <user>`). install.sh enables it.
- `PATH` includes `<home>/.cohort/bin` so `cohort-gh` (a sibling in the
  same bin) is found.
- Port 6283 is the default (an unused high-number port; see "Port
  selection" below). The unit deliberately passes no `--port` so the
  config file keeps authority. On an exe.dev VM, expose it through the
  proxy: `ssh exe.dev share port <vm> 6283`.
- `--refresh` is the server-side cache TTL (default 30s). The server
  serves it as `refresh_interval_ms` in the payload, and the page uses
  that value for its own auto-refresh timer (footer shows it too) — one
  owner, no client-side hardcode.
- The deployed script lives in `~/.cohort/bin/` (a symlink to the primary
  checkout's `bin/`), so the unit's ExecStart is the stable path.
  `install.sh` installs and starts this unit. During development it may
  be overridden with a drop-in pointing `ExecStart` at a worktree's copy
  — that override is temporary and should be removed once the branch
  merges.

### Port selection

The default port is **6283** — a high, unassigned port (τ × 1000, rounded)
just `e^3`, a nod to Euler's number). It is unlikely to collide with any
common service. Override with `--port` at any level:

- In the server: `cohort-dashboard --port 9999` (highest priority)
- For the systemd unit: run `cohort-init --dashboard-port 9999`, which
  writes the config the server reads

If the unit itself needs a one-off different port without touching the
config, add a drop-in:

```
systemctl --user edit cohort-dashboard
#   [Service]
#   ExecStart=
#   ExecStart=%h/.cohort/bin/cohort-dashboard --refresh 30 --port 9999
```

### Config file

The config lives at `~/.config/cohort-dashboard/config` and holds only
the port:

```
{
  "port": 6283
}
```

The server reads the port in this order: the `--port` CLI flag, then the
config file, then the 6283 default. The unit does not pass `--port`, so
`cohort-init --dashboard-port` controls the installed service. There is
no domain field — see "Why no domain" above.

## Failure handling

The design goal: **the dashboard never 500s on a slow or broken
dependency.**

- `gh` failures (timeout, auth, rate limit) surface as `pr_error` and the
  page falls back to git-only data; the server stays up.
- collect_git failures (e.g. a repo that isn't actually a git root) are
  isolated per repo via `error` fields, and the remaining repos still
  render.
- subprocess timeouts (git 20s, gh 25s, ls-remote 30s) bound how long any
  scrape can block; the TTL cache means a slow scrape only delays the next
  refresh, never blocks a concurrent read.

## Discovery & dedup

`collect_git` walks `$HOME` (bounded depth) looking for git roots — this
catches
`~/cohort`, projects, and every `~/worktrees/` entry. Repos are
de-duplicated by their **shared common git dir**: `git rev-parse
--git-common-dir` on a worktree yields the same path as its primary
checkout, whose parent is the repo root. That is what makes all worktrees
of one repo collapse under one canonical header. A pinned list
(`--repos FILE` or `$HOME/.config/cohort-dashboard/repos`) overrides
auto-discovery.

Remote-only detection uses `git for-each-ref refs/remotes/origin/`,
filtering symbolic refs (`origin/HEAD`), the default branch, and `pr/*`
refs (GitHub's pull-request refs aren't branches).

### Live-branch reconciliation

`refs/remotes/origin/*` goes stale: after a PR merges and its branch is
deleted on GitHub, the remote-tracking ref lingers until a prune, so
collect_git's `on_remote` (derived from those refs) can claim a branch
exists
upstream when it doesn't — handing the browser a `/tree/` or `/compare/`
URL that 404s. The gh stage reconciles this: it runs one cheap
git ls-remote --heads origin and rewrites `on_remote` for every
worktree/orphan/remote-only entry to reflect which branches actually exist
right now, and tags each entry `deleted` when it was on the remote but no
longer is (rendered grey). Local-only branches — never pushed, no
upstream — are `deleted: false` and render unlinked with no decoration.
Deleted branches keep their PR badge (the PR page is still valid) and
their head-SHA link (the merged commit exists in the default branch), but
lose their tree/compare links. When the ls-remote fails (no origin,
network hiccup), collect_git's values are kept rather than guessed at.

## Row ordering — urgency first, action-required on top

Every table is sorted most-immediate first. The ordering is computed
**in the gh stage** (`sort_groups`, keyed by a per-entry
`urgency_key`) — `/api/data` is authoritative, and the page renders
rows exactly in payload order:

1. **Action required** — anything with an `action_required` label
   surfaces at the top, ordered by blocking severity (`mark-ready` →
   `changes-requested` → `awaiting-review` → `ready-to-merge` →
   `merged-cleanup`), recency second. The page renders the cross-group
   `repo["actions"]` list exactly as the server ordered it.
2. **In-flight branches without a live PR** — dirty or ahead; next.
3. **Clean branches with no PR** — ordered by recency bands (<1d, <3d,
   <7d, older): recent commits are important, so hot branches float.
4. **Merged / deleted-upstream / abandoned** — history, sinking to the
   bottom (the bulk of the `orphans` and `remote_only` lists).

Action-required entries (any group) sort to the head; the `actions` list
is the global severity+recency ordering of those entries across groups.
Remaining rows keep the group-local tail ordering, so the most recently
merged is first among history.

Within a band, most-recent-commit-first; ties preserve collect_git order
(the sort is stable).

## Not implemented / future work

- Auth: the dashboard has no built-in auth. Place it behind a reverse
  proxy (exe.dev's built-in proxy handles auth automatically; nginx, Caddy,
  or similar for other environments).
- Multi-instance: one machine, one dashboard. Multiple VMs/machines would
  each run their own.
- Historical trends: the dashboard is a point-in-time snapshot; no metrics
  store.
- Webhook-driven refreshes: currently cache-TTL only.

## Where it lives

- `bin/` scripts: the engine's executable tooling (installed via
  `~/.cohort/bin`); committed to the repo, merged to `main`, picked up by
  every clone via the engine symlink.
- This doc: `docs/dashboard-design.md`, the durable reference. Keep it in
  sync when the pipeline, JSON shape, or link semantics change.
