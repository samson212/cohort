# Dashboard incident — findings & actions

A record of the dashboard outage (`NetworkError when attempting to fetch
resource`), the root cause, the fix, and the follow-up work it spawned.
Written after the fact; the authoritative design doc is
docs/dashboard-design.md, and this branch's code is the implementation.

## Symptom

Loading the cohort dashboard at the proxy URL failed: the page HTML
rendered, but no data appeared and the status line showed

```
error: NetworkError when attempting to fetch resource.
```

The user found that **omitting the port** (`https://chouquette-party.exe.xyz/`
instead of `https://chouquette-party.exe.xyz:8000/`) made it work — the
first real clue.

## Root cause

A `<base href>` tag injected into the dashboard page broke the data fetch.

- The service ran on port 8000; the page was read at
  `https://chouquette-party.exe.xyz:8000/`.
- Uncommitted dashboard work added a `domain` config field
  (`~/.config/cohort-dashboard/config`) and a server-side injection:
  `<base href="https://chouquette-party.exe.xyz/">`.
- The page's only relative request is `fetch('/api/data')`. Browsers
  resolve a root-relative URL against the page's **document base**, which
  the `<base>` tag overrides — so the fetch went to
  `https://chouquette-party.exe.xyz/api/data` (port 443), a different
  **origin** than the page (port 8000).
- The dashboard server sends no CORS headers (it was never designed for
  cross-origin), so the browser blocked the response and threw
  `NetworkError` / `Failed to fetch`. The page itself loaded fine;
  only the data fetch died.
- At the portless URL, page origin and base coincided → same-origin
  fetch → worked. Hence “omitting the port fixes it.”

### Evidence

- **Server access logs told the story.** Before the restart that deployed
  the new build (00:47 UTC), every `GET /` was paired with a `GET
  /api/data`. After it, `/` was served dozens of times but the browser's
  `/api/data` fetches **never arrived** — only manual curl probes showed
  up. A client-side fetch failure, not a server failure.
- The server answered `/api/data` with 200 and valid JSON locally;
  `/healthz` was fine. The server was healthy the whole time.
- Browser console on the local page showed `fetch('/api/data')` resolving
  to `https://chouquette-party.exe.xyz/api/data` because of the injected
  `<base>`, and `TypeError: Failed to fetch` in the network layer.

## Fix — delete the `<base>`/domain machinery

The page has exactly **one** relative URL (`/api/data`), and it is
root-absolute — it already resolves against whatever origin served the
page. A `<base href>` at a fixed origin can only *move* that fetch to a
different origin and break it. The feature was both unnecessary and
damaging. Commit `4f86140`:

- **`bin/cohort-dashboard`** — removed the `<base href>` injection and
  the `domain` config field. Still reads **only the port** from
  `~/.config/cohort-dashboard/config`.
- **`bin/cohort-init`** — dropped `--dashboard-domain` / reflection
  discovery; writes `{"port": N}` only.
- **`docs/dashboard-design.md`** — replaced the “Domain configuration”
  section with a “why there is no domain” note.

Result: the dashboard now works identically at any origin — host,
host:8000, host:6283, localhost, or a custom domain — because `/api/data`
is always resolved against the page the browser actually loaded.

## Move to port 6283 (the original requirement)

The underlying goal was: run Cohort on a machine that already hosts an app
on the default port, without colliding with the app's routes. A `cohort.`
subdomain isn't simply supported on exe.dev, so the chosen port is **6283**
(already the committed default).

- Updated `~/.config/cohort-dashboard/config` → `{"port": 6283}` and the
  systemd drop-in's `--port` flag.
- Port 8000 stays free for the app at the bare domain; the dashboard now
  lives at `https://chouquette-party.exe.xyz:6283/`.
- This works because of the fix above: moving ports is a routing concern,
  not a page concern, once `<base>` is gone.

## Machine-local config audit (what a fresh clone does NOT get)

The dashboard scripts and unit are committed, but a fresh machine needs
machine-local pieces to actually run the service:

| Piece | Where | Recreated by |
|---|---|---|
| `~/.cohort -> ~/cohort` symlink | home | `install.sh` ✓ |
| PATH entry for `~/.cohort/bin` | shell profile | install.sh hints (manual) |
| `~/.config/cohort-dashboard/config` | home | `cohort-init --dashboard-port 6283` |
| systemd unit installed | `/etc/systemd/system/` | **previously nothing** — now install.sh |

Before this work, install.sh never installed the service; a fresh machine
would get the scripts but no running dashboard.

## install.sh now installs the service

Commit `c03fb90`. After cloning/updating, install.sh:

- Renders `bin/cohort-dashboard.service` with the **real** target
  user/home. The unit uses `%u`/`%h` as a portable template, but systemd
  resolves those to **root** for a system unit (verified: a scratch unit
  loaded as `User=root`, `ExecStart=/root/.cohort/...`). Materializing at
  install time avoids the dashboard scraping `/root` instead of the user
  HOME.
- Honours `SUDO_USER` when run via sudo; falls back to the invoking user.
- Three paths: root → install + start; passwordless sudo → install + start;
  no privileges → write rendered unit to `~/.cohort-dashboard.service`
  and print manual steps.
- Guards against rendering an empty `User=`/`HOME=` and escapes sed
  delimiters in substituted values.

Docs updated to match (`dashboard-design.md` deployment section,
`engine-install.md` bootstrap).

## Current status & outstanding caveats

- Service is up on port 6283, page has no `<base>` tag, `/api/data`
  returns 200 with full worktree data, and the browser renders it at the
  6283 URL. Port 8000 is free.
- The live install still runs the **dev drop-in**
  (`/etc/systemd/system/cohort-dashboard.service.d/devpath.conf`),
  pointing at this worktree's `bin/`. That is the intended dev override.
- install.sh's new service step reads
  `$ENGINE_DIR/bin/cohort-dashboard.service` — which only exists after
  this branch merges to `main` (the primary checkout is on `main` and
  doesn't have the dashboard files yet). So the fresh-machine promise
  activates on merge.
- **Recommended post-merge cleanup:** remove the `devpath.conf` drop-in,
  re-run `install.sh` (renders the modern unit: `exedev`, port 6283,
  stable `~/.cohort/bin` path), and `systemctl enable --now
  cohort-dashboard`. That reproduces exactly what a fresh machine gets.

## Files touched on this branch

`bin/cohort-dashboard`, `bin/cohort-dashboard-pr`, `bin/cohort-dashboard-prep`,
`bin/cohort-dashboard.service`, `bin/cohort-init`, `docs/dashboard-design.md`,
`docs/engine-install.md`, `install.sh` (plus earlier dashboard work already
on the branch).
