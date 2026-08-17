# Dashboard complexity-reduction refactor

State of the plan. Source: `REVIEW.md` + `REVIEW-02.md` (both in repo root).
Goal: 1,262 → ~560 LOC, 60 → ~10 git spawns/repo, 3 processes → 1, one
"branch" model instead of four.

## Status key
- ✅ done (commit)
- 🔄 in progress
- ⬜ not started

## Done (branch `agent/dashboard`)

- ✅ **One branch record, one `for-each-ref`** (`c14ef82`)
  - Collapsed 8 collectors into two passes: heads (name/upstream/oid/
    date/subject/worktree path/ahead-behind vs default) + remote-tracking.
  - Git spawns per repo: 60 → 19 (per-worktree `status` + upstream
    left-right remain; can't come from for-each-ref).
  - prep: 500 → 428 LOC. Behavior verified byte-identical (minus time +
    in-worktree edits) against captured golden payload; edge cases
    (no-origin, no-default-branch) match old behavior.
  - Also removed dead `upstream:track` parse.
  - Caveats found: `%(ahead-behind:)` needs git ≥ 2.41 and fatals the whole
    call if the compared ref is missing (guarded via `show-ref` + atom
    drop). NUL separator must be written as `%00` (literal NUL breaks argv).
- ✅ Committed reviews: `2055a8c` (`REVIEW.md` + `REVIEW-02.md`).

- ✅ **Delete `no_gh` + client-side sort mirror** (`72b547b`)
  - `no_gh` query param, cache bucket, `_no_gh` fields — all gone (no caller).
  - Deleted JS `recencyBand`/`rowUrgency`/`urgencyCmp` + "must mirror
    urgency_key" comments; server's `sort_groups` is the only owner.
  - Design doc: removed no_gh section + client-mirror paragraph; page
    renders payload order.
  - −90 net lines (file 498 → ~490 before merge; net with other files).

- ✅ **Merge three scripts into one** (`a545dff`)
  - `cohort-dashboard-prep` + `cohort-dashboard-pr` + `cohort-dashboard`
    → one `bin/cohort-dashboard` with `collect_git()`/`collect_gh()`/
    `serve()`. Killed duplicated `run()`/`gh()`, two docstrings/imports,
    JSON re-serialize/re-parse round trip, `pr_enriched` protocol.
  - `--json-only [--repos FILE]` keeps the collection half standalone
    (the independently-testable boundary, 3 lines instead of 3 processes).
  - install.sh ExecStart now runs the single binary (was already the
    case for the server half).
  - Behavior verified: payload byte-identical to golden (minus timestamps,
    in-worktree dirty counts, and the new commit SHA).

- ✅ **Ship a static systemd *user* unit** (`a545dff`)
  - `bin/cohort-dashboard.service` with `%h` — resolves to the owner's
    home in a user manager (verified live on this VM on port 6411).
  - install.sh: removed the entire generated-unit machinery (heredoc,
    SUDO_USER derivation, blank-value guards, three-branch ladder);
    now copies the static unit, `loginctl enable-linger`, `--user enable
    --now`, then verifies `curl /healthz`.
  - Fixes port-ownership (REVIEW.md #1) for free; no root needed.

- ✅ **Dead `pr_*` enrichment fields** (`a072c67`) — partial Task 4
  - `enrich()` writes only the 4 fields the page reads (`pr_number`,
    `pr_state`, `pr_draft`, `pr_url`).
  - gh `pr list` stops requesting `baseRefName`/`reviewDecision`/
    `headRefOid`; keeps the Open-PRs-table fields (`createdAt`,
    `updatedAt`, `mergeable`, `additions`, `deletions`).
  - ⏳ Still open from Task 4 (product call, not done): cut
    `remote_only` and/or the Open-PRs table (visible feature removal).

- ✅ **Bind 127.0.0.1 default (`--bind` opt-in)** (`a545dff`)
  - Was `0.0.0.0` no auth, enabled unconditionally. Now loopback by
    default; the exe.dev proxy still reaches it.

- ✅ **Verify install via `/healthz`** (`a545dff`) — "verify after
  mutation": after `enable --now`, curl `/healthz`; report failure loudly.

- ✅ **Orphan master-default** — confirmed excluded by `br == db` in
  `collect_git` (no master-default orphan regression).

- ✅ **Delete dead schema `host_of_remote`/`repo.host`** — confirmed
  absent (never ported into the merged prep; no `repo.host` emitted).

- ✅ **Refresh interval one owner** (`07ea365`)
  - Payload serves `refresh_interval_ms`; page `setInterval` and footer
    both read it (fallback 30s). Four owners → one.

- ✅ **Docs sweep** (`a545dff`, `07ea365`, current commit)
  - Deleted `docs/dashboard-incident.md`; durable lesson (root-relative
    URLs only, never `<base href>`) folded into design doc as a
    two-line note.
  - Design doc: single status vocabulary (the `dirty|unpushed|deleted|
    up to date|local` set; `collect_git`'s `new`/`noupstream`/`idle`
    are intermediate, reclassified by `status_after_reconcile`);
    `status_after_reconcile` docstring updated to `collect_git`.
  - Deployment section: user-unit model; component section: one script
    one process; pipeline diagrams updated.

## Remaining

- 🔄 **Task 4 (product call): cut `remote_only` + Open-PRs table**
  - The "Open pull requests" table (~50 lines + 5 gh fields) duplicates
    the per-worktree PR column; `remote_only` section (~40 lines) is the
    same data as merged/closed PR history.
  - **Decision needed from the user** — both are visible UI features.
  - If removed: delete JS `prRow`/`prCmp`, the `pr_*` Open-PRs fields
    additions/deletions/mergeable/createdAt/updatedAt/title/headRefName
    from the gh request, and the `remote_only` collection + renderer.

## Carry-over context

- Golden payloads: prep-only and full (prep|pr) captured from the
  pre-refactor build; now superseded by the single binary's
  `--json-only`. For future structural changes, diff `--json-only`
  output against a freshly captured baseline (exclude `generated_at`,
  `collected_at`, `refresh_interval_ms`, `days_since_last_commit`, and
  dirty counts while editing in this worktree).
- `%(ahead-behind:origin/DB)` placeholder is replaced with the real
  default branch inside `for_each_ref`; when the default ref is missing
  the atom is dropped from the format (whole call would fatal).
- Threshold for `no_gh` deletion: no production caller (only self-refs +
  design doc). Host link 404 on internal mirror confirmed.
