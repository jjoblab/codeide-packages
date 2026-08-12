#!/bin/bash
# ===========================================================================
# android-push.sh — one-shot helper for Android (Termux) users
# ===========================================================================
#
# WHAT THIS DOES
#
#   1. Restores the executable bit on every .sh / .py file in the repo
#      (lost when Android unzip extracted the .zip archive).
#   2. Initialises a git repo if none exists.
#   3. Configures the local branch name to `main` (GitHub default).
#   4. Stages and commits all files (with proper 0755 mode on scripts).
#   5. Adds the `origin` remote if not already set.
#   6. Pushes to https://github.com/jjoblab/codeide-packages
#
# WHY
#
#   When you extract `codeide-packages-minimal-aarch64.zip` on Android,
#   the Unix executable bit on every .sh file is lost. Running
#   `git add .` then commits the files with mode 0644, which means
#   GitHub Actions (and anyone who clones the repo) gets non-executable
#   scripts — `./scripts/build-bootstraps.sh` fails with
#   `Permission denied`. This helper fixes that.
#
#   The `git push -u origin main` error "src refspec main does not match any"
#   is caused by the local branch being named `master` instead of `main`
#   on older git versions. This script renames the branch automatically.
#
# USAGE (from Termux)
#
#   cd ~/storage/downloads/codeide-packages    # or wherever you extracted
#   bash android-push.sh
#
#   # If you've already done `git init` and committed with bad perms:
#   bash android-push.sh --amend
#
# ===========================================================================

set -e
cd "$(dirname "$0")"

# --- Step 1: restore exec bits ---------------------------------------------
echo ""
echo "=== Step 1/4: Restore executable bits ==="
bash setup.sh 2>&1 | tail -3

# --- Step 2: git init (if needed) ------------------------------------------
echo ""
echo "=== Step 2/4: Git init ==="
if [ ! -d .git ]; then
    git init -q
    echo "  ✓ git repository initialised"
else
    echo "  ✓ git repository already exists"
fi

# Set a sensible identity if none exists ( Termux often has no global config)
if ! git config user.email > /dev/null; then
    git config user.email "you@example.com"
    git config user.name "CodeIDE Builder"
    echo "  ⚠️  No git identity found — set a placeholder."
    echo "      Run: git config user.name 'Your Name' && git config user.email 'you@example.com'"
fi

# --- Step 3: stage everything, ensure correct mode bits in index ------------
echo ""
echo "=== Step 3/4: Stage files (with exec bits preserved) ==="
git add -A 2>&1 | tail -5 || true
# Force git to re-check the mode bits for already-tracked files
git ls-files -s | awk '$1 == "100644" && $4 ~ /\.sh$/ {print $4}' | while read -r f; do
    if [ -x "$f" ]; then
        git update-index --chmod=+x "$f" 2>/dev/null && echo "  +x (forced) $f"
    fi
done

# Count what's staged
STAGED_COUNT=$(git diff --cached --name-only | wc -l)
echo "  ✓ $STAGED_COUNT files staged"

# --- Step 4: commit if needed ----------------------------------------------
echo ""
echo "=== Step 4/4: Commit & rename branch ==="
AMEND_FLAG="${1:-}"
if git diff --cached --quiet; then
    echo "  ℹ️  Nothing to commit — working tree clean"
else
    if [ "$AMEND_FLAG" = "--amend" ]; then
        git commit --amend --no-edit -q
        echo "  ✓ Previous commit amended with exec-bit fix"
    else
        git commit -q -m "Initial commit: CodeIDE Packages minimal aarch64 bootstrap"
        echo "  ✓ Committed"
    fi
fi

# Rename branch to main (GitHub's default) if needed
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "main" ]; then
    git branch -M main
    echo "  ✓ Renamed branch '$CURRENT_BRANCH' → 'main'"
elif [ -z "$CURRENT_BRANCH" ]; then
    echo "  ⚠️  No branch yet — creating 'main'"
    git branch -M main 2>/dev/null || git checkout -b main
fi

# --- Add remote & push -----------------------------------------------------
echo ""
echo "=== Push to GitHub ==="
REMOTE_URL="https://github.com/jjoblab/codeide-packages.git"
if ! git remote get-url origin > /dev/null 2>&1; then
    git remote add origin "$REMOTE_URL"
    echo "  ✓ Added remote: $REMOTE_URL"
else
    EXISTING=$(git remote get-url origin)
    if [ "$EXISTING" != "$REMOTE_URL" ]; then
        git remote set-url origin "$REMOTE_URL"
        echo "  ✓ Updated remote: $EXISTING → $REMOTE_URL"
    else
        echo "  ✓ Remote already configured"
    fi
fi

echo ""
echo "Run this command to push:"
echo "    git push -u origin main"
echo ""
echo "If you get a 'Permission denied (publickey)' error, either:"
echo "  1. Use HTTPS with a Personal Access Token (PAT) instead of password"
echo "  2. Or set up SSH: https://docs.github.com/authentication/connecting-to-github-with-ssh"
