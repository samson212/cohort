# Using gh on exe.dev VMs: `cohort-gh`

How the GitHub CLI works on this VM, and why you must run it through
`cohort-gh` — never bare `gh`.

## The exe.dev GitHub integration model

This VM reaches GitHub through the exe.dev GitHub integration
(`github.int.exe.xyz`). The credential lives at the network edge:

- **There is NO token on the VM.** No `~/.config/gh/hosts.yml`, no
  `GH_TOKEN`, no credential helper, no git credential store. This is by
  design — the secret is injected by the edge when the VM calls the
  integration host, and the VM can never read it.
- **Never run `gh auth login` or `gh auth setup-git`** for
  `github.int.exe.xyz`. There is nothing to log in to; auth is the VM's
  attachment to the integration. Trying to store a token fights the design
  and the token would be useless.
- The integration is **per-repository** (e.g. `samson212/cohort`). Only
  paths for configured repos are proxied.

## The one rule: run gh via `cohort-gh`

```
cohort-gh pr list -R samson212/cohort
cohort-gh repo view samson212/cohort
```

`cohort-gh` sets `GH_HOST` from the repo's origin remote
(`git remote get-url origin`), which is the documented exe.dev mechanism
(exe.dev/docs/integrations-github: "Set `GH_HOST` to the aggregate
integration hostname"). Bare `gh` has no way to know the host and no token
on disk, so it falls back to github.com and fails — that is not a
misconfiguration, it is the expected behavior without `cohort-gh`.

## 403s on some paths are BY DESIGN — not auth failures

The mirror host only proxies repo-scoped paths. These work:

- `gh repo view OWNER/REPO`
- `gh issue list -R OWNER/REPO` / `gh pr list -R OWNER/REPO`
- `gh api repos/OWNER/REPO/...`
- git clone / ls-remote of `OWNER/REPO.git`

These 403 with a path message — do not chase them:

- `GET /` → `path does not match any configured repository`
- `GET /api/v3/user` → `/user names no repository; only /repos/OWNER/REPO/... is proxied`
- `GET /OWNER/REPO` (html page) → `path does not match any configured repository`
- any repo that is NOT in the integration's configured set → same 403

The 403 is the proxy scoping the path to configured repos. It is not an
auth failure, not a dead integration, and not a reason to invent a new
host or start probing curl. If a documented `cohort-gh` command 403s on a
repo you know is configured, that is the time to check the attachment —
otherwise keep going.

## Failure checklist (in order)

1. Am I running `cohort-gh`, not bare `gh`? If bare — use `cohort-gh`.
2. Is the remote's host `github.int.exe.xyz` (integration) or
   `github.com` (plain public)? `cohort-gh` follows origin.
3. Is the path repo-scoped? Root `/` and `/user` are not — that 403 is
   expected.
4. Only then: is the integration actually attached to this VM?
   `curl -s https://reflection.int.exe.xyz/integrations`.
