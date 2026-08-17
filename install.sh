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

# ── Install the dashboard systemd user service ─────────────────────────
# A static user unit shipped in the repo (bin/cohort-dashboard.service)
# uses %h, which in a USER manager resolves to that user's home — the
# dashboard aggregates the invoking user's worktrees and must run as that
# user, so a user unit is the right home (a system unit's %u/%h would
# resolve to root). install.sh only copies the unit, enables linger (user
# services need it to start at boot), and starts it — no root, no
# generated paths, no SUDO_USER ladder.
#
# The port is deliberately not pinned here: cohort-dashboard reads
# ~/.config/cohort-dashboard/config (written by cohort-init
# --dashboard-port) and falls back to 6283 when nothing is supplied — an
# explicit --port in this unit would silently override that config.
DASH_UNIT_SRC="$ENGINE_DIR/bin/cohort-dashboard.service"
DASH_USER_UNIT_DIR="$HOME/.config/systemd/user"
if command -v systemctl >/dev/null 2>&1; then
    mkdir -p "$DASH_USER_UNIT_DIR"
    cp "$DASH_UNIT_SRC" "$DASH_USER_UNIT_DIR/cohort-dashboard.service"

    # User services don't start at boot unless linger is enabled.
    if ! loginctl show-user "$(id -un)" --property Linger 2>/dev/null | grep -q "Linger=yes"; then
        loginctl enable-linger "$(id -un)" 2>/dev/null || true
    fi

    systemctl --user daemon-reload
    systemctl --user enable --now cohort-dashboard

    # Verify after mutation, not by exit code: a started-but-broken unit
    # exits 0 from enable --now. Probe /healthz to confirm it serves.
    BIND_URL="http://localhost:6283/healthz"
    if curl -fsS --max-time 5 "$BIND_URL" >/dev/null 2>&1; then
        echo ""
        echo "Dashboard service installed and started (user unit):"
        echo "  $DASH_USER_UNIT_DIR/cohort-dashboard.service"
        echo "  Dashboard: http://localhost:6283/  (exe.dev: https://$(hostname).exe.xyz:6283/)"
    else
        echo ""
        echo "⚠  Dashboard unit installed but /healthz not answering yet."
        echo "    Check: systemctl --user status cohort-dashboard"
        echo "          journalctl --user -u cohort-dashboard"
    fi
else
    echo "⚠  systemctl not found; skipping dashboard service install."
    echo "    The unit is at $DASH_UNIT_SRC — install it manually:"
    echo "      mkdir -p ~/.config/systemd/user"
    echo "      cp $DASH_UNIT_SRC ~/.config/systemd/user/"
    echo "      systemctl --user enable --now cohort-dashboard"
fi

