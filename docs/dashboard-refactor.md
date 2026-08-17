# Dashboard complexity-reduction refactor

State of the plan. Source: `REVIEW.md` + `REVIEW-02.md` (both in repo root).
Goal: 1,262 → ~560 LOC, 60 → ~10 git spawns/repo, 3 processes → 1, one
"branch" model instead of four.

## Status key
- ✅ done (commit)
- 🔄 in progress
- ⬜ not started

## Done so far (branch `agent/dashboard`)

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

## Remaining, ranked by (complexity removed ÷ risk)

1. ⬜ **Delete `no_gh` + client-side sort mirror** — −95 LOC, risk ≈ 0
   - `no_gh` query param, cache bucket, `_no_gh` fields; broken (unmapped
     status pills, mirror-host links) with no caller.
   - Delete JS `recencyBand`/`rowUrgency`/`urgencyCmp` + the "must mirror
     urgency_key" comments: server's `sort_groups` becomes the only owner.
   - Update `docs/dashboard-design.md` (remove no_gh section, row-ordering
     "client mirror" note).

2. ⬜ **Merge three scripts into one** — −90 LOC, −2 files, risk low
   - `cohort-dashboard-prep` + `cohort-dashboard-pr` +
     `cohort-dashboard` → one file with `collect_git()`/`collect_gh()`/
     `serve()`. Kills duplicated `run()`/`gh()`, two docstrings/imports,
     JSON re-serialize/re-parse round trip, `pr_enriched` protocol.
   - `install.sh` ExecStart + `cohort-init` --dashboard-port references
     must follow the rename.
   - "Independently testable" justification is unbacked (zero tests);
     add `--json-only` (3 lines) if the boundary is wanted back.

3. ⬜ **Ship a static systemd *user* unit** — −35 LOC, risk low-med
   - `%h` verified to resolve correctly in a user unit; removes the entire
     generated-unit machinery in `install.sh` (heredoc, SUDO_USER
     derivation, blank-value guards, three-branch root/sudo/no-privilege
     ladder ~57 lines) and fixes port-ownership (REVIEW.md #1) for free.
   - Needs `loginctl enable-linger` (already enabled on this VM).

4. ⬜ **Cut `remote_only`, Open-PRs table, 9 dead `pr_*` fields** —
   −60 to −110 LOC, risk low but product call
   - Page reads 5 of 13 `pr_*` fields (`pr_number`, `pr_state`, `pr_draft`,
     `pr_title`, `pr_url`): drop `baseRefName`, `reviewDecision`,
     `headRefOid` + enrichment of unread fields, plus `additions`/
     `deletions`/`mergeable` unless Open-PRs table stays. Confirmed unread
     repo-wide.
   - Is the "Open pull requests" table worth its ~50 lines? It duplicates
     the per-worktree PR column.

5. ⬜ **Small correctness/safety (do regardless, before merge)**
   - Bind `127.0.0.1` (explicit `--bind` opt-in); install-should prompt.
     Currently `0.0.0.0` no auth, enabled unconditionally.
   - Verify install via `curl /healthz` after `enable --now` — "verify
     after mutation" / "exit codes lie".
   - `orphan_branches` hardcodes `"main"` (prep:288 in old file): now
     excluded by `br == db` — confirm no master-default orphan regression
     (golden-verified for fallback "main"; `default_branch` still falls
     back to "main" when origin/HEAD absent — acceptable, matches old).
   - Delete dead schema `host_of_remote`/`repo.host` (no consumer) — never
     ported into the new prep; confirm absence.
   - Refresh interval has 4 owners (`DEFAULT_REFRESH`, unit `--refresh`,
     page `setInterval(30000)`, footer "30s"): serve it in payload.

6. ⬜ **Docs sweep**
   - `docs/dashboard-incident.md` (145 lines): keep only the durable lesson
     (root-relative URLs only, never `<base href>`), fold as two-line note
     into design doc, delete file.
   - Design doc status table: single vocabulary, one place; prep docstring
     contract (`new`/`noupstream`/`idle`) vs real set
     (`dirty|unpushed|deleted|up to date|local`) already disagree.
   - Keep this file current as each task lands.

## Carry-over context for the next session

- Golden payloads used for verification: prep-only and full (prep|pr)
  captured from the pre-refactor build. Rebuild after each structural
  change and diff (exclude `generated_at`, `collected_at`,
  `days_since_last_commit`, dirty counts while editing in this worktree).
- `%(ahead-behind:origin/DB)` placeholder is replaced with the real
  default branch inside `for_each_ref`; when the default ref is missing
  the atom is dropped from the format (whole call would fatal).
- Threshold for `no_gh` deletion: no production caller (only self-refs +
  design doc). Host link 404 on internal mirror confirmed.
