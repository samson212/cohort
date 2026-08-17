# Architecture review #2 — the alternative-approaches pass

Scope: the dashboard feature on `agent/dashboard` (`bin/cohort-dashboard{,-pr,-prep}`,
`install.sh`, `bin/cohort-init`, `docs/dashboard-{design,incident}.md`).

This builds on `REVIEW.md` rather than repeating it. REVIEW.md's findings are
all real and all confirmed; this pass pressure-tests its **bottom line** —
*"the three-stage shape is defensible, reduce duplicated ownership"* — and
concludes that the duplicated ownership is a **symptom**, not the disease.
The disease is that the pipeline models the same object (a branch) four
separate times, and each model needs its own collector, its own status
vocabulary, its own sorter, and its own renderer.

**Current size:** 1,262 lines of code (prep 500, pr 264, server 498) + 71
lines of install plumbing + 504 lines of docs, with **zero tests** and
**zero consumers of the inter-stage JSON contract** outside this repo.

---

## Measurements taken (not estimates)

| Measurement | Result |
|---|---|
| git subprocesses per repo scan | **60** (21 `rev-list`, 15 `log`, 8 `merge-base`, 7 `status`, 5 `for-each-ref`, 4 misc) |
| Same data via one `for-each-ref` + one `status` per worktree | **10** — prototyped, output verified equivalent |
| Prototype LOC for that collection core | **63** vs **~256** today |
| Server-side `PAGE` constant | 326 of 498 lines (82 HTML/CSS, **243 JS**) |
| `pr_*` fields written by `enrich()` | 13 |
| `pr_*` fields read by the page | **5** |
| `/api/data?no_gh=1` status values served | `idle`, `noupstream`, `dirty` |
| `statusBadge` map keys in the page | `dirty`, `unpushed`, `deleted`, `up to date`, `local` |
| Full pipeline wall time | 1.5 s (prep alone: 0.17 s; the 1.3 s is `gh`) |

---

## Findings

| severity | area | finding | recommendation |
|---|---|---|---|
| high | data model | A branch is modelled four times — `worktrees`, `orphans`, `remote_only`, `open_prs` — each with its own collector, status vocabulary, sort call and row renderer, which is the root cause of every duplication REVIEW.md lists downstream. | Collect one flat `branches` list keyed by branch name with `path`/`on_remote`/`pr` as optional attributes, and let the page group it for display. |
| high | collection cost | Per-branch `git log`, `rev-list --count` and `merge-base --is-ancestor` calls produce 60 subprocess spawns per repo where `for-each-ref` with `%(worktreepath)`, `%(ahead-behind:)`, `%(committerdate:iso-strict)` and `%(contents:subject)` returns all of it in one (verified: 60 → 10). | Replace `worktrees()`, `upstream_map()`, `branch_info()`, `count_commits()`, `branch_is_merged_into()`, `remote_branch_set()`, `orphan_branches()` and `remote_only_branches()` with a single `for-each-ref` parse. |
| high | degraded path | `?no_gh=1` is broken, not merely degraded: it serves prep's `idle`/`noupstream` statuses that `statusBadge` cannot map (raw text in a grey pill) and a `repo.web` pointing at the unreachable internal mirror, so every link 404s. | Delete the `no_gh` query param, its cache bucket and its documentation rather than fixing a path with no caller. |
| high | ordering | The urgency ladder exists in Python (`cohort-dashboard-pr:133-183`) and JavaScript (`cohort-dashboard:220-268`) purely to serve that broken `no_gh` path, and the design doc dedicates a section to keeping the two identical. | Delete the JavaScript copy with `no_gh`; ordering then has exactly one owner and the "must mirror" comments disappear. |
| high | exposure | The server binds `0.0.0.0` with no auth (verified listening) and `install.sh` enables it unconditionally for anyone who runs the engine installer, publishing repo paths, branch names and commit subjects to the whole network. | Bind `127.0.0.1` by default with an explicit `--bind` opt-in, and gate the service install behind a flag or prompt. |
| med | correctness | `orphan_branches()` hardcodes `br == "main"` as the branch to exclude (`cohort-dashboard-prep:288`) although `scan_repo` has already computed `default_branch`, so a `master`-default repo lists its own default branch as an orphan. | Pass `default_branch` into `orphan_branches()` — or delete the function outright under the unified-branch model, which never special-cases it. |
| med | process boundary | The three-process split buys nothing measurable: `prep` is 0.17 s, the JSON is re-serialised and re-parsed twice per refresh, and the split forces a duplicated `run()` helper, three docstrings, three import blocks and a `pr_enriched` protocol flag. | Merge into one file with `collect_git()` / `collect_gh()` / `serve()` functions; the "independently testable" claim in the design doc is unbacked — there are no tests. |
| med | install | `install.sh` generates a *system* unit, which forces `SUDO_USER` derivation, blank-value guards and a three-branch root/sudo/no-privilege ladder (~57 lines) — all of it to work around the fact that `%h`/`%u` resolve to root in system units. | Ship a committed **user** unit (`systemctl --user`, `%h` verified to resolve correctly, linger already enabled here); no root, no generation, no duplication of the install block. |
| med | verification | `install.sh` enables and starts the service and then prints a success message without ever checking `systemctl is-active` or `curl /healthz`, contradicting the repo's own "verify after mutation" and "exit codes lie" guidelines. | Probe `/healthz` after `enable --now` and report the real state. |
| med | payload | `enrich()` writes 13 `pr_*` fields of which the page reads 5, keeping `baseRefName`, `reviewDecision`, `headRefOid`, `additions`, `deletions` and `mergeable` in the `gh --json` request for nobody. | Confirmed unread across the whole repo — drop the nine unused fields and their source fields (extends REVIEW.md's "low" finding to "verified dead"). |
| med | feature scope | The "Open pull requests" table duplicates data already shown in the per-worktree PR column, and it alone justifies `open_prs`, `prCmp`, `prRow`, and 6 of the 9 unused `pr_*` fields. | Ask whether the section earns its ~50 lines; the branch table already links every open PR. |
| low | config ownership | Beyond REVIEW.md's port finding, the refresh interval has four owners — `DEFAULT_REFRESH`, the unit's `--refresh 30`, the page's `setInterval(30000)` and the footer's literal "every 30s". | Serve the interval in the JSON payload and have the page and footer read it from there. |
| low | docs | `docs/dashboard-incident.md` (145 lines) records machine-local transient state — a dev drop-in, a "recommended post-merge cleanup", a config audit — that will be false the moment the branch merges. | Fold the one durable lesson (root-relative URLs only, never `<base href>`) into the design doc as a two-line note and delete the file. |
| low | docs | The design doc's status table lists five values; `cohort-dashboard-prep:32` documents a different set (`new`/`noupstream`/`idle`) as the contract — one fact, two places, already disagreeing. | Single status vocabulary derived in one place, documented in one place. |
| low | discovery | `git_common_root_of()` spends 10 lines resolving a `.git` *file* to its gitdir target, a path reachable only for submodules, which this engine has none of. | Delete the branch or assert on it loudly rather than silently falling through to `git_root_of`. |

---

## Top drastic simplifications, ranked by (complexity removed ÷ risk)

### 1. Delete `no_gh` and the client-side sort mirror — **−95 LOC, −25 doc lines, risk ≈ 0**
It has no caller, it is measurably broken (unmapped status pills, mirror-host
links), and it is the *sole* reason the urgency ladder is implemented twice.
Deleting it removes a cache bucket, a query-param branch, four JS functions,
the "must mirror `urgency_key`" invariant, and a design-doc section. This is
the single best ratio in the review: pure subtraction, and it fixes a bug.

### 2. Collapse the three scripts into one — **−90 LOC, −2 files, −2 spawns/refresh, risk low**
Mechanical merge. Deletes a duplicated `run()`/`gh()` pair, two docstrings and
import blocks, the `--repos` argv parser, the JSON re-serialise/re-parse round
trip, and the `pr_enriched`/`pr_error` protocol. The stated justification
("prep is independently testable") is unbacked — no tests exist — and a
function is at least as testable as a subprocess. If the boundary is wanted
back later, `--json-only` costs three lines.

### 3. One branch record, one `for-each-ref` — **−235 LOC, 60 → 10 git spawns, risk medium**
The biggest absolute win and the one that makes REVIEW.md's four "duplicated
ownership" findings evaporate rather than get patched. Eight collector
functions collapse into one parse loop (prototyped at 63 lines against ~256
today); `worktrees`/`orphans`/`remote_only` become a single list the page
groups by `path`/`on_remote`; status normalisation, date math and row
rendering each become singular *because there is only one kind of row left*.
Risk is a rewrite of the collection core — mitigate by capturing today's
`/api/data` as a golden file and diffing the new output field-by-field.
Caveat: `%(ahead-behind:)` needs git ≥ 2.41 (2.43 here); guard or document it.

### 4. Ship a static systemd **user** unit — **−35 LOC, removes root from the install path, risk low-med**
`%h` was verified to resolve to the real home in a user unit, which removes
the entire premise of the generated-unit approach. Deletes the heredoc, the
`SUDO_USER` derivation, the blank-value guards and the triplicated
install/reload/enable block. Drop `--port` from `ExecStart` while doing it and
REVIEW.md's #1 finding (three-way port ownership) is fixed for free. Risk is
`loginctl enable-linger` for boot-time start — already enabled here, one line
in the installer otherwise.

### 5. Delete `docs/dashboard-incident.md` — **−145 doc lines, risk 0**
Transient machine state and post-merge TODOs, in a durable-docs directory.

### 6. Cut `remote_only`, the Open-PRs table, and the 9 dead `pr_*` fields — **−60 to −110 LOC, risk low but a product call**
Not a code judgement — a scope judgement for the user. Each is a whole column
of the pipeline (collector → enricher → sorter → renderer) serving a view that
partly duplicates the main table.

**Cumulative:** 1,262 → **~560 LOC** (−55%), 504 → **~250 doc lines**,
60 → 10 git spawns per scan, 3 processes → 1, and the number of places that
must agree about "what is a branch" goes from 4 to 1.

---

## Minimum viable dashboard

One table, one row per branch, columns: branch · state · changes · age · PR.
Everything else — orphan section, remote-only section, open-PR section, summary
cards (already deleted in `62dda03`), `no_gh`, the head-SHA column — is a view
of data the main table already carries. That dashboard is roughly **300 lines**
in one file, needs 2 git commands and 2 `gh` commands, and loses nothing an
operator acts on. The current 1,262 lines are not doing 4× the work of that
one; they are doing the same work four times.

---

## Bottom line

REVIEW.md's verdict — *the three-stage shape is defensible* — is the finding I
disagree with. The three stages are not expensive in themselves (prep is
170 ms), but they are what makes the four-branch-models problem invisible:
each stage gets to own its own view of a branch, so nothing forces the
vocabularies to converge, and the JSON contract between them is pure
serialisation tax with no external consumer.

Fix the data model and the process split, and the configuration, normalisation,
ordering and rendering duplications REVIEW.md correctly identified do not need
fixing — they stop existing. Roughly **55% of this feature's code is
subtractable without losing a single thing the operator sees**, and the two
highest-ratio moves (#1 and #2, ~185 lines) are near-zero-risk deletions that
should land before anything is refactored.

Two findings are not about complexity and should not wait: the server binds
`0.0.0.0` with no auth and is enabled unconditionally by the engine installer,
and `orphan_branches()` hardcodes `"main"` where `default_branch` was already
computed.
