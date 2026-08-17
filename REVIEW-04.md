# Review pass 4 — `agent/dashboard` (8 commits vs `origin/agent/dashboard`)

Scope: `bin/cohort-dashboard` (three-script merge, 1043 lines), `bin/cohort-dashboard.service`,
`install.sh` (user-unit migration), `docs/dashboard-design.md`, `docs/dashboard-refactor.md`,
`docs/engine-install.md`, `docs/dashboard-incident.md` deletion.

Verification performed: script smoke-run (`--json-only`, `COHORT_NO_GH=1`, failing `cohort-gh`
on PATH, port-config load), live server /healthz + /api/data, `py_compile`, `bash -n`,
rename edge reproduced against `status_counts`, payload-shape diff vs design-doc data model,
commit-by-commit diff of the merged script.

## Findings

| severity | finding | recommendation |
|---|---|---|
| **major** | gh-failure contract is a lie in both directions: `collect_gh` sets `payload["pr_enriched"]=True` unconditionally and `pr_error` is only written by `full_payload`'s exception handler, which `collect_gh` can't reach (it swallows every failure internally) — a total gh failure (verified with failing `cohort-gh` on PATH) emits `pr_enriched: true` with NO `pr_error`, contradicting design-doc ll.100-101 & 303; the same is true for `COHORT_NO_GH`. | `collect_gh` must return/set `pr_enriched=False` when the guard or the pr-list/repo-view calls failed, and set `pr_error` on the payload itself (or raise); have `--json-only` and the server share one code path so the degraded state is observable. |
| **major** | `install.sh`'s "/healthz" verification probes `http://localhost:6283/healthz` but a configured port comes from `~/.config/cohort-dashboard/config` (`_load_port_config`) — if `cohort-init --dashboard-port 9999` was used, install reports the unit "broken" (healthz check fails on 6283) while it's actually serving on 9999, and the echoed URL is also hardcoded 6283. | Read the config in install.sh (jq/python or grep) and probe/echo the configured port. |
| **major** | Upgrade path is broken on this very VM: the old install.sh left a *system* unit `/etc/systemd/system/cohort-dashboard.service` (enabled, `multi-user.target`, generated paths); the new install.sh only manages the *user* unit, never removes the stale system one, so a re-run leaves the old root unit enabled and running (observed: system `cohort-dashboard.service` active; user unit `disabled`/`inactive`). | install.sh should remove/disable the legacy system unit (or at minimum detect and loudly warn) when migrating; document the one-time manual removal. |
| **major** | Stale unit carries `--port 6283` in ExecStart, silently overriding the config file — the exact port-ownership bug REVIEW.md #1 flagged; on this VM the *old* unit still passes it. | The committed static unit correctly omits `--port` (good); apply the same to any lingering generated unit (fix above). |
| minor | `days_since_last_commit` is absent from worktree entries (design-doc `worktree entry` model lists it, ll.133), and present on orphans/remote_only — the page reads it for all three groups so worktree age renders as "—". Verified against live payload. | Either add `days_since_last_commit` to the worktree item in `scan_repo` or drop it from the doc's model (doc is source of truth). |
| minor | Design-doc data model (ll.107) still lists `"host"` field on repo entries — the refactor doc claims it's deleted ("no `repo.host` emitted"); live payload confirms it's gone. | Remove `host` from the design-doc data model. |
| minor | Design-doc failure-handling ll.308 says "subprocess timeouts (120s)" — prep/old server had 120s; merged `run()` defaults to 20s, gh 25s, ls-remote 30s. | Update the doc's number. |
| minor | Design-doc pipeline diagram (ll.65) lists `git worktree list` and `git rev-list` among collectors — collect_git uses one `for-each-ref` + per-worktree `status` + `rev-list --left-right` for upstream, never `worktree list` or `rev-list` for default-vs-branch (ahead-behind comes from the for-each-ref atom). | Update diagram to the actual collectors or drop the two commands. |
| minor | `status_counts` miscounts staged renames: `git status --porcelain=v1 -z` emits rename as TWO NUL records (`R  new\0old\0`); the bare source record `old` has xy="xx" → counted as staged+unstaged. Reproduced: `rename staged counts: (2,0,0)` for one file. Not a crash here (the record-guard in earlier review never landed — AND the 1-record guard REVIEW-03#1 recommended is still absent) but the count is wrong and the phantom `x` in `xy[0]`/`xy[1]` over-counts. | Skip records whose first two chars are both non-space non-`?` letters without a lone `?`-only, or match `xy[0]`/`xy[1]` against the exact porcelain alphabet (`MARC.D?`), or better: detect the rename source record (bare 2-char XY with no filename in `xy`) and skip it. |
| minor | `urgency_key` docstring says "Must mirror the page's rowUrgency" but the JS mirror was deleted in `72b547b` — stale reference to a removed function. | Drop the sentence. |
| minor | `pr_error`/`pr_enriched`/`collected_at` when gh is skipped are never set on the payload in degraded mode; the page never reads them but the JSON contract (and `--json-only` consumers) can't tell git-only from gh-enriched. Same root cause as the major — fold into that fix. | Surface `pr_enriched:false` in degraded mode per fix above. |
| minor | Design doc "Port selection" (ll.264-265): "τ × 1000, rounded) just e^3" — 6283 is neither τ×1000 (6283.19 → 6283, arguably "rounded" down) nor e^3 (20.09); the parenthetical is self-contradictory. | Reword: "6283 = round(τ × 1000)" or similar. |
| nit | `install.sh` healthz probe of the just-started unit races: systemd `RestartSec`/startup may take >0s; probe failure only prints a warning (fine) but the message says "installed but /healthz not answering" — could add a short retry loop. | Optional: retry the probe a few times over ~2s before warning. |
| nit | install.sh's `loginctl enable-linger ... || true` suppresses a real authorization failure (policy may deny non-root on some distros) — the dashboard then won't start at boot and nothing says so. | Surfaced: check `systemctl --user is-enabled` after enable step, or echo a warning. |
| nit | `bin/cohort-init`'s new `--dashboard-port` writes `~/.config/cohort-dashboard/config` — the dashboard's `_load_port_config` reads it, but `REPOS_FILE` and the config's `port` live in two different files with no cross-check; a stale repo list is silent. | Not a blocker; note as future work if repo pinning matters. |
| nit | Live server was started by the old system unit with `--port 6283 --refresh 30` — verify the CI/draft-PR interaction won't start a second instance on the same port after merging. | Out of scope for code review; noted. |

## What's right

- One merged script: the three-process boundary becomes `--json-only`; in-process caching of the combined payload is a genuine complexity cut (1,262 → 1,043 LOC live).
- `--refresh` served as `refresh_interval_ms` and consumed by page + footer — one owner.
- Loopback bind by default (`--bind` opt-in) — closes the unauthenticated-exposed-port hole.
- Live-branch reconciliation via `ls-remote` is the right answer to stale `refs/remotes/origin/*`; `deleted` vs `local` distinction is correct and well-documented.
- The static user unit with `%h` is a real simplification over the generated system unit and fixes the port-ownership *in the committed unit*.
- Dedup by `--git-common-dir`, `for-each-ref` atom-dropping for missing default refs, and the NUL `%00` handling are all careful and correct.
- Failure isolation per repo via `error` fields works; the server stays up when scrobbling breaks (module verified: no 500 on gh failure even though the *signal* is wrong).

## Bottom line

The merge and refactor are a genuine improvement and the code quality is high — but **the branch is not ready to push as-is**. The gh-failure degradation contract is factually inverted in both the code and the docs (the dashboard *silently* claims PR enrichment succeeded when it deterministically can't), and the install path continues to verify against a hardcoded 6283 and leaves a stale root system unit enabled on upgrade — the first confirmed on this VM, the second directly contradicts the design doc's "no root/sudo needed, no generated unit" claim. Fix the `pr_enriched`/`pr_error` plumbing (set them in `collect_gh` on every path), add the legacy-unit removal to install.sh, and make the healthz probe read the configured port; the rename and docs-drift items are quick follow-ups in the same pass. Everything else is minor-to-nit.

REVIEW-04.md written to the worktree (uncommitted) — matches the precedent set by 2055a8c, which committed REVIEW.md/REVIEW-02.md/REVIEW-03.md by an explicit follow-up commit; left uncommitted here since the task said "your call" and the branch is otherwise clean.
