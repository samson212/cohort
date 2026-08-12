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
    git -C "$ENGINE_DIR" checkout main 2>/dev/null || true
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

if [[ ":$PATH:" != *":$HOME/.cohort/bin:"* ]]; then
    echo ""
    echo "⚠  ~/.cohort/bin is not on your PATH."
    echo "   Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    echo "       export PATH=\"\$HOME/.cohort/bin:\$PATH\""
    echo ""
fi

echo ""
echo "Done. From any project root, run:  cohort-init"
