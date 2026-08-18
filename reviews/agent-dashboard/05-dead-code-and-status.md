# Code review: `agent/dashboard` (pass 5)

Full review of `bin/cohort-dashboard` (1072 lines), `install.sh`, `bin/cohort-init` against design docs (`dashboard-design.md`, `dashboard-refactor.md`, `dashboard-deploy.md`). Focus: dead code paths, artifacts of incorrect assumptions, simplification opportunities.

## P0 — real bugs (wrong behavior under live conditions)

### P0.1 `web_url_of_remote` regex leaks port into path for `ssh://` URLs
**File:** `bin/cohort-dashboard` ~L140
**Finding:** The regex `([^:/]+)[:/](.+?)` captures the port as part of the path for `ssh://git@github.com:22/user/repo.git`. The `[^:/]+` host group stops at `:` (port separator), then `[:/]` matches the first `:`, then `(.+?)` captures `22/user/repo`. Result: `https://github.com/22/user/repo` — wrong.
**Fix:** Handle optional `:port` in ssh:// form: `ssh://(?:[^@/]+@)?([^:/]+)(?::\d+)?/(.+?)(?:\.git)?$` (separate regex for ssh:// vs scp-style).
**Severity:** Low — `ssh://` with explicit port is rare; the scp-style (`git@host:path`) and https forms work correctly.

### P0.2 Orphan `fmt.esc(o.upstream_ref || '')` fallback is unreachable dead code
**File:** `bin/cohort-dashboard` JS (orphan row render)
**Finding:** The orphan row render uses `o.head_short ? ... : fmt.esc(o.upstream_ref || '')`. But `head_short` is always truthy for any real ref (derived from `%(objectname)` in for-each-ref, which is always a 40-char SHA for real branches). The only way `head_short` could be falsy is if `head` is empty, which only happens for symbolic refs / HEAD — and those are filtered out. The fallback `fmt.esc(o.upstream_ref || '')` can never fire.
**Evidence:** `o.upstream_ref` IS read by JS (confirmed via regex trace) but only in this unreachable branch. The field is still populated by Python (wasted work).
**Fix:** Delete the `: fmt.esc(o.upstream_ref || '')` fallback — simplify the ternary.

## P1 — provably-dead code / fields / branches

### P1.1 `"new"` status is a dead branch — can never be produced
**File:** `bin/cohort-dashboard` ~L358-361
**Finding:** In collect_git's worktree status logic:
```python
elif not item["has_upstream"]:
    status = "new" if item["ahead"] else "noupstream"
```
When `has_upstream` is False, `ahead` is always 0 (set to 0 at ~L343: `item["ahead"], item["behind"] = 0, 0`). So `"new" if 0 else "noupstream"` → **always `"noupstream"`**. `"new"` can never be produced.
**Fix:** Collapse to `status = "noupstream"`. Delete the dead `"new"` branch.
**Also:** `"new"` has no entry in the JS `statusBadge` map (only `dirty|unpushed|deleted|up to date|local`). If it somehow reached the browser, it would render as a gray pill with raw text "new".

### P1.2 `"idle"` / `"noupstream"` intermediate statuses have no JS map entries
**File:** `bin/cohort-dashboard` ~L364 (Python), JS `statusBadge` map
**Finding:** collect_git produces `"idle"` and `"noupstream"` as intermediate statuses. `status_after_reconcile` overwrites them … **but only when `live_branches` succeeds**. If `live_branches` returns `None` (network hiccup, no origin), `status_after_reconcile` is NOT called, and these intermediates reach the browser. The JS `statusBadge` map has no entry for `"idle"` or `"noupstream"` — they would render as `["gray", "idle"]` / `["gray", "noupstream"]` via the fallback.
**Fix:** Add a fallback status_after_reconcile call even when live is None (use collect_git's `on_remote` field — it's less accurate but at least maps to a known status label). Or add `"idle"`/`"noupstream"` to the JS map as explicit gray entries.

### P1.3 `prCmp` function defined but never called
**File:** `bin/cohort-dashboard` ~L815-821 (JS)
**Finding:** `prCmp(a, b)` is defined but has zero call-sites in the JS. The server's `sort_groups` already sorts `open_prs` by the same logic (drafts after ready, then by `updatedAt`). The refactor plan (`72b547b`) specifically says "Deleted JS `recencyBand`/`rowUrgency`/`urgencyCmp` + 'must mirror urgency_key' comments; server's `sort_groups` is the only owner." `prCmp` is a leftover from the same pattern — a client-side sort that was supposed to be deleted but wasn't.
**Evidence:** `grep -n prCmp bin/cohort-dashboard` → only the definition at line 815, no call site.
**Fix:** Delete the `prCmp` function (6 lines).

### P1.4 JS fields written by Python but never read by JS

| Field | Where emitted | JS reads? |
|---|---|---|
| `wt.path` | collect_git worktree | ❌ Dead |
| `wt.has_upstream` | collect_git worktree | ❌ Dead |
| `wt.last_commit_at` | collect_git worktree | ❌ Dead |
| `o.has_upstream` | collect_git orphan | ❌ Dead |
| `o.last_commit_at` | collect_git orphan | ❌ Dead |
| `repo.host` | never emitted* | ❌ Dead |

*`repo.host` was removed per refactor plan but the JS doesn't read it anyway.
**Evidence:** Confirmed via regex trace of all JS `wt.xxx` / `o.xxx` accesses against all Python field assignments.
**Fix:** Stop emitting `has_upstream` and `last_commit_at` from Python (keep `path` — it's useful for debugging/deploy scripts that consume `--json-only`).

### P1.5 `REPOS_FILE` path exists but is never created by installer
**File:** `bin/cohort-dashboard` ~L64, `discover_repos` ~L103-116
**Finding:** `REPOS_FILE = ~/.config/cohort-dashboard/repos` is checked in `discover_repos` but never created by `cohort-init` or `install.sh`. It's an undocumented opt-in feature. The design doc (`dashboard-design.md` line ~321) mentions it as if standard.
**Fix:** Either document it as "create this file if you want to pin repos" or have `cohort-init` create it from discovered repos.

## P2 — simplifications (reduce LOC, no behavior change)

### P2.1 Delete dead `"new"` branch → collapse to `"noupstream"`
**Lines:** ~L358-360. **Save:** 2 lines, one less code path.

### P2.2 Delete `prCmp` function
**Lines:** ~L815-821. **Save:** 6 lines.

### P2.3 Stop emitting `has_upstream` and `last_commit_at` from Python
**Save:** ~4 field writes; reduces payload size slightly.
**Caveat:** `last_commit_at` appears in the JSON schema in the design doc. Either delete the field or update the doc.

### P2.4 Double fetch of `/api/data` on page load
**File:** `bin/cohort-dashboard` JS ~L972-988
**Finding:** On page load, `refresh()` fetches `/api/data` and renders, then a separate IIFE also fetches `/api/data` to read `refresh_interval_ms` for `setInterval`. Two identical requests before first meaningful paint.
**Fix:** Have `refresh()` return/store the data, reuse the same response for both `render` and `setInterval`.
**Save:** One HTTP request on page load.

### P2.5 `_load_port_config` silently swallows all errors
**File:** `bin/cohort-dashboard` ~L49-57
**Finding:** Any `json.JSONDecodeError`, `ValueError`, or `OSError` silently returns `DEFAULT_PORT` with no stderr. If a user writes `{"port": "abc"}` the dashboard starts on 6283 with zero indication. **Violates "make failures loud."**
**Fix:** Print a warning to stderr: `print(f"Warning: could not parse {CONFIG_FILE}, using port {DEFAULT_PORT}", file=sys.stderr)`.

### P2.6 `cohort-init` writes dashboard config but never verifies it
**File:** `bin/cohort-init` ~L48-56
**Finding:** Writes `~/.config/cohort-dashboard/config` via heredoc but never checks the file was written correctly. `set -e` catches `mkdir`/`cat` failures but not partial writes.
**Fix:** Add `python3 -c "import json; json.load(open('$CONFIG_DIR/config'))"` after writing.

### P2.7 `sort_groups` per-group loop: `urgency_key` always computed identically across groups
**File:** `bin/cohort-dashboard` ~L628-636
**Finding:** The three groups are sorted independently (correct — they render in separate tables). But `urgency_key` is computed identically for all groups even though orphan/remote_only entries mostly sink to 9 (merged/deleted). The per-group sort means the groups don't interleave — an orphan with an open PR (urgency 0) sorts below a worktree with urgency 2. This is correct for separate tables but means `urgency_key`'s precise values for non-worktree groups are unused.
**Verdict:** Not a bug, but the identical computation across groups is wasted. If orphans/remote_only always sort to the bottom within their tables, a simpler sort key would suffice.

## P3 — doc drift

### P3.1 Design doc: `collect_git` status overwrite is incomplete
**File:** `docs/dashboard-design.md`
**Finding:** Says collect_git's status "is overwritten for worktrees" but doesn't mention this only happens when `live_branches` succeeds. When it fails, intermediates survive.
**Fix:** Add a note about the degraded fallback.

### P3.2 Design doc: `repo.host` in schema but not in payload
**File:** `docs/dashboard-design.md` ~L102
**Finding:** Schema shows `"host": "github.int.exe.xyz"` but refactor plan says it was deleted. JS doesn't read it.
**Fix:** Remove `host` from the schema.

### P3.3 Design doc: `has_upstream` in worktree schema
**File:** `docs/dashboard-design.md` ~L113
**Finding:** `has_upstream` is in the schema but JS never reads it on worktrees.
**Fix:** Decide: keep as API surface or remove from both doc and code.

### P3.4 `dashboard-deploy.md` is a forward-looking design, not current state
**File:** `docs/dashboard-deploy.md`
**Finding:** Describes preview instances, namespaced worktrees, `cohort-dashboard-serve` — none implemented on this branch. Marked as "design" but committed alongside implementation.
**Verdict:** Not drift — clearly marked "design." Could use a "NOT YET IMPLEMENTED" banner.

## If I change nothing else, delete these N things first

1. **`prCmp` function** (L815-821) — 6 lines, zero callers, confirmed dead.
2. **`"new"` status branch** (L358-360) — collapse to `"noupstream"`; `ahead` is provably always 0 there.
3. **Stop emitting `has_upstream`** on worktrees and orphans — JS never reads it.
4. **`fmt.esc(o.upstream_ref || '')` fallback** in orphan row — dead code since `head_short` is always truthy. Simplify the ternary.

## Bottom-line verdict

The code is production-quality: the core data pipeline is correct, status classification is solid, failure handling degrades gracefully, and the single-file design eliminated the original three-process complexity. The remaining issues are mostly dead-code artifacts from iterative refactoring — `prCmp` (forgotten during the "delete client sort mirror" pass), the `"new"` branch (can't fire), and a few unused fields. No P0 correctness bug that would cause wrong data to display under normal operation. The `ssh://` port regex issue is real but affects an edge case unlikely to occur on any real VM.

**Recommendation:** Merge after cleaning up the P1 dead code (items 1-4 above). The P3 doc drifts can be fixed in a follow-up docs sweep.
