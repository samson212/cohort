#!/bin/bash
# install.sh: one-shot Cohort engine installer. Pipe-friendly.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/samson212/cohort/main/install.sh | bash
#
# Clones the engine to ~/cohort, links ~/.cohort -> ~/cohort, and checks
# that ~/.cohort/bin is on PATH. Safe to re-run.
set -e

REPO_URL="${COHORT_REPO_URL:-https://github.com/samson212/cohort.git}"
ENGINE_DIR="$HOME/cohort"
SYMLINK="$HOME/.cohort"

echo "=== Cohort engine installer ==="
echo ""

# ── Clone / update the engine ─────────────────────────────────────────────

if [[ -d "$ENGINE_DIR/.git" ]]; then
    echo "Engine already cloned at $ENGINE_DIR; fetching latest..."
    git -C "$ENGINE_DIR" fetch origin
    git -C "$ENGINE_DIR" checkout main
    git -C "$ENGINE_DIR" merge --ff-only origin/main 2>/dev/null || \
        git -C "$ENGINE_DIR" reset --hard origin/main
else
    echo "Cloning Cohort engine to $ENGINE_DIR..."
    if [[ -d "$ENGINE_DIR" ]]; then
        echo "$ENGINE_DIR exists but is not a git repo. Remove it and re-run." >&2
        exit 1
    fi
    git clone "$REPO_URL" "$ENGINE_DIR"
fi

# ── Canonical symlink ─────────────────────────────────────────────────────

if [[ -L "$SYMLINK" ]]; then
    current=$(readlink -f "$SYMLINK")
    wanted=$(readlink -f "$ENGINE_DIR")
    if [[ "$current" != "$wanted" ]]; then
        ln -sf "$ENGINE_DIR" "$SYMLINK"
        echo "Relinked $SYMLINK -> $ENGINE_DIR (was -> $current)"
    else
        echo "Symlink $SYMLINK already correct"
    fi
elif [[ -e "$SYMLINK" ]]; then
    echo "$SYMLINK exists but is not a symlink. Remove it and re-run." >&2
    exit 1
else
    ln -s "$ENGINE_DIR" "$SYMLINK"
    echo "Created symlink: $SYMLINK -> $ENGINE_DIR"
fi

# ── Add bin to PATH ──────────────────────────────────────────────────────

if [[ ":$PATH:" != *":$HOME/.cohort/bin:"* && ":$PATH:" != *":~/.cohort/bin:"* ]]; then
    echo ""
    echo "⚠  ~/.cohort/bin is not on your PATH. Add this:"
    echo "       export PATH=\"\$HOME/.cohort/bin:\$PATH\""
    echo ""
    echo "   Put it in the file your login shell reads:"
    echo "     bash — the first of ~/.bash_profile, ~/.bash_login, ~/.profile"
    echo "            that exists (later ones are skipped entirely)"
    echo "     zsh  — ~/.zprofile (zsh does not read ~/.profile)"
    echo ""
    echo "   Avoid ~/.bashrc and ~/.zshrc: agents run these scripts from"
    echo "   non-interactive shells, and both files are commonly guarded to"
    echo "   do nothing when not interactive."
    echo ""
fi

echo ""
echo "Done. From any project root, run:  cohort-init"

# ── Install the dashboard systemd service ────────────────────────────────
# The unit is generated here, at install time, from values this script
# already knows: the invoking user (or SUDO_USER) and their home. No
# committed template, no placeholders, no substitution pass — a unit for
# a different user would need a different ExecStart, and install.sh is
# the only place that knows who that is. (A %u/%h template shipped in
# the repo cost sed escaping, empty-value guards, and still resolved to
# root if systemd ever touched it.) The dashboard aggregates the user's
# worktrees and must run as that user.
#
# The port is deliberately not pinned here: cohort-dashboard reads
# ~/.config/cohort-dashboard/config (written by cohort-init
# --dashboard-port) and falls back to 6283 when nothing is supplied — an
# explicit --port in this unit would silently override that config.
if command -v systemctl >/dev/null 2>&1; then
    if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
        DASH_USER="$SUDO_USER"
        DASH_HOME="$(getent passwd "$DASH_USER" | cut -d: -f6)"
    fi
    DASH_USER="${DASH_USER:-$(id -un)}"
    DASH_HOME="${DASH_HOME:-$HOME}"

    # Never write a unit with a blank User/Home.
    if [[ -z "$DASH_USER" || -z "$DASH_HOME" ]]; then
        echo "⚠  Could not determine target user/home; skipping dashboard install." >&2
        exit 0
    fi

    DASH_BIN="$DASH_HOME/.cohort/bin"
    DASH_UNIT_DST="/etc/systemd/system/cohort-dashboard.service"
    RENDERED="$(cat <<UNIT
[Unit]
Description=Cohort worktree & PR dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$DASH_USER
Environment=HOME=$DASH_HOME
Environment=PATH=$DASH_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$DASH_BIN/cohort-dashboard --refresh 30
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
)"

    if [[ "$(id -u)" -eq 0 ]]; then
        printf '%s\n' "$RENDERED" > "$DASH_UNIT_DST"
        systemctl daemon-reload
        systemctl enable --now cohort-dashboard
        echo ""
        echo "Dashboard service installed and started:"
        echo "  $DASH_UNIT_DST (runs as $DASH_USER)"
        echo "  Dashboard: http://localhost:6283/  (exe.dev: https://$(hostname).exe.xyz:6283/)"
    elif sudo -n true 2>/dev/null; then
        printf '%s\n' "$RENDERED" | sudo tee "$DASH_UNIT_DST" >/dev/null
        sudo systemctl daemon-reload
        sudo systemctl enable --now cohort-dashboard
        echo ""
        echo "Dashboard service installed and started:"
        echo "  $DASH_UNIT_DST (runs as $DASH_USER)"
        echo "  Dashboard: http://localhost:6283/  (exe.dev: https://$(hostname).exe.xyz:6283/)"
    else
        printf '%s\n' "$RENDERED" > "$HOME/.cohort-dashboard.service"
        echo ""
        echo "⚠  No root/sudo access — skipped the dashboard systemd install."
        echo "   The rendered unit is at $HOME/.cohort-dashboard.service"
        echo "   Finish manually:"
        echo "     sudo install -m 644 $HOME/.cohort-dashboard.service $DASH_UNIT_DST"
        echo "     sudo systemctl daemon-reload && sudo systemctl enable --now cohort-dashboard"
    fi
fi

