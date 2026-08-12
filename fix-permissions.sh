#!/bin/bash
# ===========================================================================
# fix-permissions.sh — fix exec bits already pushed to GitHub
# ===========================================================================
#
# PROBLEM
#
#   You pushed the codeide-packages repo to GitHub, but GitHub Actions
#   fails with:
#
#       ./scripts/run-docker.sh: Permission denied
#       Process completed with exit code 126.
#
#   This happens because ALL files in your commit ended up as mode
#   100644 (regular) instead of 100755 (executable) for the .sh / .py
#   scripts. You can verify this on GitHub:
#
#       https://github.com/jjoblab/codeide-packages
#       → click any .sh file → "Raw" button URL contains /blob/main/
#       → or use the API:
#         curl -s https://api.github.com/repos/jjoblab/codeide-packages/git/trees/main?recursive=1 | grep run-docker
#
#   The cause: Android's Termux `git init` may default to
#   `core.filemode=false` on certain filesystems (e.g. /sdcard which is
#   FAT-based). When `core.filemode=false`, `git add -A` IGNORES the
#   filesystem +x bit and tracks everything as 100644.
#
# SOLUTION
#
#   This script uses `git update-index --chmod=+x` which works
#   REGARDLESS of core.filemode — it tells git directly "track this
#   file as executable in the next commit".
#
# USAGE (run from inside the codeide-packages repo, after cloning)
#
#   cd codeide-packages
#   bash fix-permissions.sh            # → updates index + commits
#   git push
#
#   Or in CI mode (no commit, just update the working tree + index):
#
#   bash fix-permissions.sh --no-commit
#
#   The push will update the existing branch with corrected modes.
#
# WHAT IT DOES
#
#   1. Marks every .sh, .py, config.sub, config.guess file as
#      executable in the git index (using update-index --chmod=+x).
#      Also runs `chmod +x` on the filesystem so the scripts can be
#      executed immediately.
#   2. Commits the change (unless --no-commit is passed).
#   3. Prints a one-line summary.
#
# ===========================================================================

set -e
cd "$(dirname "$0")"

NO_COMMIT=0
if [ "${1:-}" = "--no-commit" ]; then
    NO_COMMIT=1
fi

# Make sure we're in a git repo (or at least a directory we can chmod)
if [ ! -d .git ]; then
    echo "ℹ️  Not a git repository — will only chmod +x files on the filesystem."
    echo "    Run this from inside the codeide-packages repo to also fix git index."
    IN_GIT=0
else
    IN_GIT=1
    # Ensure git can detect file modes (just in case)
    git config core.filemode true 2>/dev/null || true
fi

echo "=== Restoring exec bits ==="
if [ "$NO_COMMIT" = "1" ]; then
    echo "Mode: --no-commit (CI mode, will not commit)"
fi
if [ "$IN_GIT" = "1" ]; then
    echo "Using 'git update-index --chmod=+x' which works regardless of core.filemode."
fi
echo ""

# --- Top-level executable scripts (explicit list) -------------------------
TOP_LEVEL_SCRIPTS=(
    build-package.sh
    build-all.sh
    clean.sh
    setup.sh
    android-push.sh
    test-bootstrap.sh
    fix-permissions.sh
)

# --- Scripts in scripts/ (explicit list of well-known ones) --------------
SCRIPTS_DIR_FILES=(
    scripts/run-docker.sh
    scripts/run-docker.ps1
    scripts/setup-termux.sh
    scripts/setup-termux-glibc.sh
    scripts/setup-cgct.sh
    scripts/setup-android-sdk.sh
    scripts/setup-archlinux.sh
    scripts/setup-ubuntu.sh
    scripts/setup-offline-bundle.sh
    scripts/build-bootstraps.sh
    scripts/generate-bootstraps.sh
    scripts/check-versions.sh
    scripts/list-versions.sh
    scripts/list-packages.sh
    scripts/lint-packages.sh
    scripts/free-space.sh
    scripts/update-docker.sh
    scripts/update-docker.ps1
    scripts/aptly_api.sh
    scripts/check-built-packages.py
    scripts/check-repository-health.js
    scripts/buildorder.py
    scripts/get_hash_from_file.py
    scripts/config.sub
    scripts/config.guess
)

CHANGED=0
SKIPPED=0

# Helper function: chmod +x on filesystem AND git update-index --chmod=+x
mark_exec() {
    local f="$1"
    [ -f "$f" ] || return 0
    # Always chmod on filesystem (works even outside git)
    chmod +x "$f" 2>/dev/null || true
    if [ "$IN_GIT" = "1" ]; then
        if git ls-files --error-unmatch "$f" > /dev/null 2>&1; then
            git update-index --chmod=+x "$f" 2>/dev/null && CHANGED=$((CHANGED+1)) && echo "  +x $f" || SKIPPED=$((SKIPPED+1))
        fi
    fi
}

echo "--- Top-level scripts ---"
for f in "${TOP_LEVEL_SCRIPTS[@]}"; do
    mark_exec "$f"
done

echo ""
echo "--- scripts/ files ---"
for f in "${SCRIPTS_DIR_FILES[@]}"; do
    mark_exec "$f"
done

echo ""
echo "--- All .sh files under scripts/build/ ---"
COUNT_BUILD=0
if [ -d scripts/build ]; then
    while IFS= read -r -d '' f; do
        mark_exec "$f" && COUNT_BUILD=$((COUNT_BUILD+1))
    done < <(find scripts/build -name "*.sh" -print0 2>/dev/null)
fi
echo "  +x ($COUNT_BUILD files in scripts/build/)"

echo ""
echo "--- All .py / .sh files under scripts/bin/, scripts/utils/, scripts/updates/ ---"
COUNT_BIN=0
for d in scripts/bin scripts/utils scripts/updates; do
    [ -d "$d" ] || continue
    while IFS= read -r -d '' f; do
        mark_exec "$f" && COUNT_BIN=$((COUNT_BIN+1))
    done < <(find "$d" -type f \( -name "*.sh" -o -name "*.py" \) -print0 2>/dev/null)
done
echo "  +x ($COUNT_BIN files in scripts/bin, utils, updates)"

echo ""
echo "--- All package build.sh files ---"
COUNT_PKG=0
while IFS= read -r -d '' f; do
    mark_exec "$f" && COUNT_PKG=$((COUNT_PKG+1))
done < <(find packages root-packages x11-packages disabled-packages -name "build.sh" -print0 2>/dev/null)
echo "  +x ($COUNT_PKG build.sh files across packages/, root-packages/, x11-packages/, disabled-packages/)"

echo ""
echo "--- sample/ directory ---"
COUNT_SAMPLE=0
if [ -d sample ]; then
    while IFS= read -r -d '' f; do
        mark_exec "$f" && COUNT_SAMPLE=$((COUNT_SAMPLE+1))
    done < <(find sample -name "*.sh" -print0 2>/dev/null)
fi
echo "  +x ($COUNT_SAMPLE files in sample/)"

echo ""
echo "--- All scripts WITHOUT extension that have a shebang (#!) ---"
COUNT_SHEBANG=0
# Find files that don't have a known "data" extension and check their first 2 bytes
# This catches things like:
#   - packages/termux-core/build/scripts/termux-replace-termux-core-src-scripts
#   - packages/proot/termux-chroot
#   - x11-packages/openbox/scripts/openbox-session
#   - scripts/bin/ldd, scripts/bin/revbump, etc.
# Without this, build of termux-core fails with:
#   /bin/sh: 1: .../termux-replace-termux-core-src-scripts: Permission denied
#   make: *** Error 126
while IFS= read -r -d '' f; do
    # Quick shebang check (only read first 2 bytes — fast)
    if head -c 2 "$f" 2>/dev/null | grep -q "^#!"; then
        mark_exec "$f" && COUNT_SHEBANG=$((COUNT_SHEBANG+1))
    fi
done < <(find packages root-packages x11-packages disabled-packages scripts \
    -type f \
    ! -name "*.sh" ! -name "*.py" \
    ! -name "*.md" ! -name "*.txt" ! -name "*.json" ! -name "*.yml" ! -name "*.yaml" \
    ! -name "*.cfg" ! -name "*.conf" ! -name "*.in" ! -name "*.am" ! -name "*.ac" \
    ! -name "*.sub" ! -name "*.guess" \
    ! -name "*.patch" ! -name "*.diff" ! -name "*.patch.*" ! -name "*.patch32" ! -name "*.patch64" \
    ! -name "*.gpg" ! -name "*.key" \
    ! -name "*.tar" ! -name "*.gz" ! -name "*.zip" ! -name "*.xz" ! -name "*.bz2" \
    ! -name "*.png" ! -name "*.jpg" ! -name "*.desktop" \
    ! -name "*.ps1" \
    ! -name "*.map" ! -name "*.list" \
    -print0 2>/dev/null)
echo "  +x ($COUNT_SHEBANG extension-less scripts with shebang)"

echo ""
echo "============================================================"
echo "✓ Forced $((CHANGED + COUNT_BUILD + COUNT_BIN + COUNT_PKG + COUNT_SAMPLE + COUNT_SHEBANG)) files to mode 100755 in git index"
echo "   ($SKIPPED files were already +x in the index)"
echo "============================================================"

# --- Show what's staged ----------------------------------------------------
if [ "$IN_GIT" = "1" ]; then
    echo ""
    echo "=== Files staged for commit ==="
    git diff --cached --name-only | wc -l
    echo "files with mode changes"
fi

# --- Early exit in CI mode -------------------------------------------------
if [ "$NO_COMMIT" = "1" ]; then
    echo ""
    echo "ℹ️  --no-commit mode: skipping commit step."
    echo "    Filesystem +x bits have been restored; scripts can be executed now."
    exit 0
fi

if [ "$IN_GIT" != "1" ]; then
    echo ""
    echo "ℹ️  Not in a git repo — only filesystem +x bits were restored."
    exit 0
fi

# --- Commit if needed ------------------------------------------------------
if git diff --cached --quiet; then
    echo ""
    echo "ℹ️  Nothing to commit — exec bits were already correct in the index."
    exit 0
fi

echo ""
echo "=== Committing ==="
git commit -q -m "fix: restore executable bits on .sh / .py / config.sub / config.guess

GitHub Actions was failing with 'Permission denied' on ./scripts/run-docker.sh
because all files were tracked as mode 100644 instead of 100755.

This commit uses 'git update-index --chmod=+x' to force the exec bit
in the git index, which works regardless of the local core.filemode
setting (relevant on Android Termux where core.filemode may be false)."

echo "✓ Committed."

echo ""
echo "=== Push ==="
echo "Run this to push the fix to GitHub:"
echo ""
echo "    git push"
echo ""
echo "If you have local changes that haven't been pushed yet, you may need:"
echo "    git push --force-with-lease   # safer than --force"
