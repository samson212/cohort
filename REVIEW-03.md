# Branch review: `agent/dashboard` vs `main`

Scope: the dashboard feature as it stands on this branch — 19 commits,
12 files, +1960/−4 — reviewed as a final-state diff against `main`.
This is a review-type pass (correctness, robustness, edge cases),
complementing the architecture passes in REVIEW.md and REVIEW-02.md.

**Verification performed:** the full pipeline (`prep → pr → server`) was
run end-to-end on the VM against the live engine; the systemd dashboard
renders all tables with internally consistent header/cell counts; the
rename crash below was reproduced against the real `status_counts`.

---

## Findings, most important first

### 1. `status_counts` crashes (or mislabels) on staged renames — real, latent

`git status --porcelain=v1 -z` emits a rename as **two** NUL records:
`R  new\0old\0` — the second is the bare rename source, no XY prefix.
`status_counts` does `xy = entry[:2]` on every record:

- source path of 1 char → `IndexError` (reproduced against the real
  `cohort-dashboard-prep`; `xy[1]` on a 1-char string).
- source path ≥ 2 chars → e.g. `xy = 'bi'` from `bin/...` → both counts
  as staged **and** unstaged → `dirty_files` inflated, so a *clean* staged
  rename displays as **dirty** and jumps up the urgency sort.

Worse, the `IndexError` is not caught per-repo: it propagates out of
`_collect` in the server, so `/api/data` returns a 500 for the **whole**
request — directly contradicting the design doc's “the dashboard never
500s” promise. This is the one fragile NUL parse in the pipeline.

**Fix:** skip records shorter than 2 chars (rename sources carry no XY),
move on. Also consider making prep per-repo fault-isolated so one bad
repo cannot kill the whole scrape, matching the doc's isolation claim.

### 2. `web_url_of_remote` requires a dot in the host

`git@host:owner/repo` with a single-label host (LAN hostname, ssh config
alias like `github`) yields `""` → `repo.web` fallback degrades to no
links at all. The sibling `host_of_remote` allows such hosts; the web
URL builder silently doesn't. Minor: intranet/mirror setups lose all
GitHub links even though the dashboard could still build
`https://github/owner/repo`.

### 3. install.sh privilege ladder has a gap

The three paths are root → install, passwordless sudo → install, else
write unit + manual steps. A user with `sudo` rights but no passwordless
access (common: `sudo` prompts) silently drops to the manual fallback
instead of being prompted. The docs' “root or passwordless sudo” claim is
accurate but under-sells the in-between case.

### 4. `remote_only` rows lost their `merged` text

`remoteRows` renders a remote-only branch *without* a PR as
`badge purple: remote` — `o.merged` is unused in that branch (`merged`
text exists in orphan rows and prep logic). Since nearly every
orphan/remote-only has a merged PR it's mostly invisible, but a merged
remote branch with no PR shows “remote” instead of “merged”.

### 5. Dashboard repo-level errors render as JSON to the browser

Per-repo `error` fields (e.g. “not a git repository”) are handled well,
but a whole-repo scrape failure returns `{"error": ...}` to `/api/data`
and the page shows `error: {…}` — an ugly but arguably correct live
error over stale green.

### 6. Minor: single-label hosts / rename-vs-copy

Covered by #1 (the record guard) and #2.

---

## What's right

- **Two-half split** (git-only `prep`, gh-only `pr`) — network failure
  cannot kill local reads; `prep` is testable standalone.
- **Unit generated from known values** in install.sh — removes an entire
  placeholder/template category; the guidelines doc captures the lesson.
- **Live-branch reconciliation** via `ls-remote` — the right call for
  stale `refs/remotes/origin/*`.
- **Dedup by `--git-common-dir`** — correct, handles linked-worktree
  `.git` files.
- **Escaping discipline** — everything user-visible is `fmt.esc()`-ed;
  `encodeURIComponent` on URL paths is right.
- **Config holds only the port, no domain** — the incident fix removes a
  whole class of proxy-origin breakage.

---

## Recommended actions before merge

1. Fix #1 (rename parsing) — the only path that can actually 500 the
   dashboard; a 2-line guard.
2. Decide #4 — use `o.merged` in `remoteRows` or drop the dead field.
3. Re-verify install.sh under all privilege paths; document the
   sudo-but-not-passwordless case.
4. Optional: allow single-label hosts in `web_url_of_remote`.
