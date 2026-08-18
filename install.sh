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
# resolve to root). install.sh only symlinks the unit (not copies — the
# engine's committed unit stays the one copy of truth, so an engine
# update is picked up at the next restart), enables linger (user
# services need it to start at boot), and starts it — no root, no
# generated paths, no SUDO_USER ladder.
#
# Why linger: the user manager only starts at boot if linger is enabled
# — otherwise it comes up only after that user's first login session.
# On a headless VM (no console/SSH session present at boot) the
# dashboard would never come up after a reboot without it. A dedicated
# "cohort" user would not help: the dashboard reads THIS user's
# worktrees/config, so it must run under the user whose data it shows.
#
# The port is deliberately not pinned here: cohort-dashboard reads
# ~/.config/cohort-dashboard/config (written by cohort-init
# --dashboard-port) and falls back to 6283 when nothing is supplied — an
# explicit --port in this unit would silently override that config.
DASH_UNIT_SRC="$ENGINE_DIR/bin/cohort-dashboard.service"
DASH_USER_UNIT_DIR="$HOME/.config/systemd/user"
if command -v systemctl >/dev/null 2>&1; then
    mkdir -p "$DASH_USER_UNIT_DIR"
    ln -sf "$DASH_UNIT_SRC" "$DASH_USER_UNIT_DIR/cohort-dashboard.service"

    # User services don't start at boot unless linger is enabled.
    if ! loginctl show-user "$(id -un)" --property Linger 2>/dev/null | grep -q "Linger=yes"; then
        loginctl enable-linger "$(id -un)" 2>/dev/null || true
    fi

    # Migrate away from the legacy *system* unit the pre-merger installer
    # wrote (with baked-in user/home and a pinned --port that overrode the
    # config file). If it is still present, stop it and remove it so the
    # user unit is the only owner of port + config.
    if systemctl is-enabled cohort-dashboard >/dev/null 2>&1 && \
       [[ -f /etc/systemd/system/cohort-dashboard.service ]]; then
        echo "Removing legacy system unit /etc/systemd/system/cohort-dashboard.service"
        if ! sudo systemctl stop cohort-dashboard 2>/dev/null || ! sudo systemctl disable cohort-dashboard 2>/dev/null; then
            echo "⚠  Could not stop/disable the legacy system unit (need sudo)." >&2
            echo "    It serves on the same port as the new user unit; remove it as root:" >&2
            echo "      sudo systemctl stop cohort-dashboard" >&2
            echo "      sudo systemctl disable cohort-dashboard" >&2
            echo "      sudo rm /etc/systemd/system/cohort-dashboard.service" >&2
        fi
        sudo rm -f /etc/systemd/system/cohort-dashboard.service
        sudo rm -rf /etc/systemd/system/cohort-dashboard.service.d
        sudo systemctl daemon-reload 2>/dev/null || true
    fi

    systemctl --user daemon-reload
    systemctl --user enable --now cohort-dashboard

    # Verify after mutation, not by exit code: a started-but-broken unit
    # exits 0 from enable --now. Probe /healthz to confirm it serves.
    # Read the configured port (cohort-init --dashboard-port) rather than
    # assuming 6283 — probing the wrong port would report a healthy
    # install as broken.
    DASH_PORT=6283
    if [[ -f "$HOME/.config/cohort-dashboard/config" ]]; then
        cfg_port=$(sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$HOME/.config/cohort-dashboard/config" 2>/dev/null | head -1)
        if [[ "$cfg_port" =~ ^[0-9]+$ ]]; then
            DASH_PORT="$cfg_port"
        fi
    fi
    BIND_URL="http://localhost:$DASH_PORT/healthz"
    if curl -fsS --max-time 5 "$BIND_URL" >/dev/null 2>&1; then
        echo ""
        echo "Dashboard service installed and started (user unit):"
        echo "  $DASH_USER_UNIT_DIR/cohort-dashboard.service"
        echo "  Dashboard: http://localhost:$DASH_PORT/  (exe.dev: https://$(hostname).exe.xyz:$DASH_PORT/)"
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
    echo "      ln -s $DASH_UNIT_SRC ~/.config/systemd/user/"
    echo "      systemctl --user enable --now cohort-dashboard"
fi

