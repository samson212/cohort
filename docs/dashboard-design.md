# Cohort dashboard — design

The dashboard is a zero-dependency view of the Cohort engine's working set:
every worktree, its dirty state, its PR, and the branches that linger
without a worktree. It runs as a single Python stdlib HTTP server on the
VM and is meant to be read from a browser, refreshed periodically, and
trusted to never fall over — including when GitHub's API is slow or down.

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
- which branches exist locally but were never pushed (unlinked, no decoration)
- which branches were deleted from the remote after their PR merged (struck through)
- which branches exist only on the remote (no local ref, no worktree)
- which local branches no longer have a worktree (cleanup candidates)

## Components

Three scripts, split by a simple rule: **local git reads are cheap and
reliable; GitHub calls are slow and can fail** — so the git half and the
gh half are separate processes that can run independently.

```
bin/cohort-dashboard-prep   # git only — no network
bin/cohort-dashboard-pr     # gh only — enriches prep JSON with PR metadata
bin/cohort-dashboard        # stdlib HTTP server; runs the other two
bin/cohort-dashboard.service # systemd unit (deploy)
```

Pipeline:

```
       git worktree list ─┐
       git status         │
       git for-each-ref   ├─► prep ─► JSON ─► pr ─► JSON ─► /api/data
       git rev-list       │                │
       git remote get-url ┘            gh pr list
```

- **prep** runs entirely against local git. It can never crash on the
  network because it never touches it. It outputs a self-contained JSON
  document (below).
- **pr** reads prep JSON on stdin, makes up to two `gh` calls per repo
  (`repo view` for the canonical web URL, `pr list --state all` for PRs),
  and writes enriched JSON. If `gh` fails or the `COHORT_NO_GH` env guard
  is set, it returns the input unchanged — the dashboard degrades to
  git-only rather than erroring.
- **server** runs prep (and pr unless `no_gh`) on a TTL, caches the
  result, and serves the HTML page and the JSON. It is the only long-lived
  process.

The split has a second benefit: prep is independently testable — you can
pipe it to `python3 -m json.tool` or feed it to pr by hand — and the
server stays a thin shell around two boring pipelines.

## Data model

One JSON document per scrape:

```
{
  "generated_at": "…Z",            # when prep ran
  "collected_at": "…Z",            # when the server cached it
  "pr_enriched": true,             # false when gh was skipped/failed
  "pr_error": null,                # set when gh failed (non-fatal)
  "repos": [
    {
      "root": "/home/exedev/cohort",   # primary checkout (dedup canonical)
      "name": "cohort",
      "remote": "…",
      "host": "github.int.exe.xyz",    # host part of the origin remote
      "web": "https://github.com/…",   # canonical browser URL (gh-derived)
      "default_branch": "main",
      "worktrees": [ … ],              # every checkout, incl. primary
      "orphans": [ … ],                # local branches w/o worktree
      "remote_only": [ … ],            # remote branches w/o local ref
      "open_prs": [ … ]                # OPEN PRs for the repo
    }
  ]
}
```

### worktree entry

```
{
  "path": "/home/exedev/worktrees/foo",   "branch": "agent/foo",
  "is_primary": false,                    "on_remote": true,
  "head": "<40-hex>", "head_short": "…",
  "staged": 1, "unstaged": 2, "untracked": 0, "dirty_files": 3,
  "has_upstream": true, "upstream_ref": "origin/agent/foo",
  "ahead": 2, "behind": 0, "commits_since_default": 2,
  "subject": "…", "last_commit_at": "…Z", "days_since_last_commit": 1.2,
  "status": "dirty",           # dirty | unpushed | deleted | up to date | local
  "pr_number": 12, "pr_state": "MERGED", "pr_url": "https://github.com/…/pull/12",
  "pr_draft": false, "pr_created_at": "…", "pr_updated_at": "…",
  "pr_review_decision": "APPROVED", "pr_mergeable": "MERGEABLE",
  "pr_additions": 3, "pr_deletions": 1,
  "pr_head_sha": "…", "pr_head_sha_matches": true
}
```

### orphan entry

A local branch with **no worktree** (its worktree was cleaned up but the
ref lingers). Fields: `branch`, `has_upstream`, `on_remote`, `merged`,
`commits_since_default`, `subject`, `head`/`head_short`, `last_commit_at`,
`days_since_last_commit`, plus `pr_*` enrichment when a PR matches.

### remote_only entry

A **remote-tracking** branch with no local branch and no worktree (a
cleaned-up merged PR head). Fields: `branch`, `head`, `head_short`,
`merged`, `commits_since_default`, `subject`, dates, plus `pr_*`.

## Status classification

For each worktree, a single status string drives the pill. It is computed
in the pr stage, after live-branch reconciliation, so the label reflects
reality (prep's local-git-only status is overwritten for worktrees):

| status | meaning | link behavior |
|---|---|---|
| `dirty` | uncommitted changes present | PR page, else compare |
| `unpushed` | ahead of upstream (commits not pushed) | PR, else compare |
| `deleted` | was on the remote, branch removed after merge | PR page, else none |
| `up to date` | clean, exists on the remote | tree page (or PR) |
| `local` | clean, never pushed / no upstream | none (unlinked) |

`deleted` carries the final say on tree/compare linkability: a branch
deleted from the remote loses its tree/compare links and its name is
struck through — its PR page (if any) and head-SHA link (the merged commit
lives in the default branch) still link. `local` branches are unlinked but
not struck through: no decoration, they just don't link.

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
(`COHORT_NO_GH` or a failed call), prep's origin-derived URL is the
fallback — degraded but functional.

Branches not on the remote have no `/tree/`, `/commit/`, or `/compare/`
page. How they render depends on why they're not on the remote:

- **Deleted upstream** (was on the remote, branch removed after the PR
  merged): the branch name gets a strikethrough and no tree/compare link.
  The head SHA still links to `/commit/<sha>` — the merged commit is
  reachable from the default branch, so that page is alive.
- **Local-only** (never pushed / no upstream): unlinked and plain — no
  strikethrough, no decoration. The head SHA is also unlinked (those
  commits don't exist on GitHub).

Both keep their PR badge if a PR exists — the PR page is still valid after
its branch head is deleted.

PR URLs from gh are re-homed to `repo.web`'s host if they differ (gh can
return the canonical `github.com` host even when the API went through a
mirror). This is a defensive normalization; with gh's `repo view` URL as
the base it is usually a no-op.

## Deployment

The service ships as a systemd unit:

```
bin/cohort-dashboard.service
```

```
[Service]
Type=simple
User=exedev
Environment=HOME=/home/exedev
Environment=PATH=/home/exedev/.cohort/bin:…
ExecStart=/home/exedev/.cohort/bin/cohort-dashboard --port 8000 --refresh 30
Restart=on-failure
RestartSec=3
```

- Runs as the VM user (`exedev`), not root — the discovery walk uses the
  user's `$HOME`.
- `PATH` includes `~/.cohort/bin` so `cohort-gh` (a sibling in the same
  bin) is found.
- Port 8000 is the exe.dev proxy default, so the page is
  `https://<vm>.exe.xyz/`; the proxy handles auth.
- `--refresh` is the server-side cache TTL (default 30s); the page also
  auto-refreshes client-side on a fixed 30s timer.
- The deployed script is the engine's `~/.cohort/bin/cohort-dashboard`
  (a symlink to the primary checkout's `bin/`), so the unit's intention is
  the stable path. During development it may be overridden with a drop-in
  pointing `ExecStart` at a worktree's copy — that override is temporary
  and should be removed once the branch merges (see git-workflow's "Which
  `bin/` to edit" note).

## Failure handling

The design goal: **the dashboard never 500s on a slow or broken
dependency.**

- `gh` failures (timeout, auth, rate limit) surface as `pr_error` and the
  page falls back to git-only data; the server stays up.
- prep failures (e.g. a repo that isn't actually a git root) are isolated
  per repo via `error` fields, and the remaining repos still render.
- subprocess timeouts (120s) bound how long any scrape can block; the TTL
  cache means a slow scrape only delays the next refresh, never blocks a
  `no_gh` read.
- The `no_gh=1` query param on `/api/data` forces the cheap git-only path
  for probes and for periods when gh is down.

## Discovery & dedup

`prep` walks `$HOME` (bounded depth) looking for git roots — this catches
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
prep's `on_remote` (derived from those refs) can claim a branch exists
upstream when it doesn't — handing the browser a `/tree/` or `/compare/`
URL that 404s. The pr stage reconciles this: it runs one cheap
git ls-remote --heads origin and rewrites `on_remote` for every
worktree/orphan/remote-only entry to reflect which branches actually exist
right now, and tags each entry `deleted` when it was on the remote but no
longer is (struck through). Local-only branches — never pushed, no
upstream — are `deleted: false` and render unlinked with no decoration.
Deleted branches keep their PR badge (the PR page is still valid) and
their head-SHA link (the merged commit exists in the default branch), but
lose their tree/compare links. When the ls-remote fails (no origin,
network hiccup), prep's values are kept rather than guessed at.
The server's `no_gh=1` fast path skips this stage entirely, so it shows
the prep-derived (possibly optimistic) `on_remote` — acceptable, since
that path is for when the network is down, when GitHub pages are
unreachable anyway.

## Row ordering — urgency first

Every table is sorted most-immediate first. The ordering is computed
**server-side** in the pr stage (`sort_groups`, keyed by a per-entry
`urgency_key`) so `/api/data` is authoritative — the page sorts again
client-side only as a degraded `no_gh` fallback (pr stage skipped):

1. **Active PRs** (open, ready before draft) — work awaiting review or
   merge is the closest to done and the first thing to act on.
2. **In-flight branches without a live PR** — dirty or ahead; next.
3. **Clean branches with no PR** — ordered by recency bands (<1d, <3d,
   <7d, older): recent commits are important, so hot branches float.
4. **Merged / deleted-upstream / abandoned** — history, sinking to the
   bottom (the bulk of the `orphans` and `remote_only` lists).

Within a band, most-recent-commit-first; ties preserve prep order (the
sort is stable). Open PRs order among themselves by last activity
(`updatedAt`, else `createdAt`), drafts after ready ones. The client's
`rowUrgency`/`urgencyCmp` mirror `urgency_key` so both paths agree.

## Not implemented / future work

- Auth: the exe.dev proxy authenticates the operator; no app-level auth.
- Multi-instance: one VM, one dashboard. Multiple VMs would each run
  their own.
- Historical trends: the dashboard is a point-in-time snapshot; no metrics
  store.
- Webhook-driven refreshes: currently cache-TTL only.

## Where it lives

- `bin/` scripts: the engine's executable tooling (installed via
  `~/.cohort/bin`); committed to the repo, merged to `main`, picked up by
  every clone via the engine symlink.
- This doc: `docs/dashboard-design.md`, the durable reference. Keep it in
  sync when the pipeline, JSON shape, or link semantics change.
