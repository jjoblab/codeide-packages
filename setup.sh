#!/bin/bash
# ===========================================================================
# setup.sh — restore executable bits after zip extraction on Android
# ===========================================================================
#
# WHY THIS SCRIPT EXISTS
#
# When you extract a .zip archive on Android (via Termux, Material Files,
# MiXplorer, etc.), the Unix executable bit is NOT preserved. Every .sh
# script ends up with mode 0644 instead of 0755, so trying to run
# `./build-package.sh` fails with "Permission denied".
#
# This script walks the repo and restores the +x bit on every shell
# script that needs to be executable, plus the binary helper tools
# under scripts/bin/.
#
# USAGE
#
#   cd /path/to/codeide-packages
#   bash setup.sh
#
# Or, if you cloned via git on Termux:
#
#   cd codeide-packages
#   ./setup.sh           # will fail with Permission denied
#   bash setup.sh         # ← use this instead
#
# After running this script you can re-commit the permission changes:
#
#   git add -A
#   git commit --amend --no-edit   # or: git commit -m "fix: restore exec bits"
#   git push -u origin main
#
# ===========================================================================

set -e

cd "$(dirname "$0")"

echo "[*] Restoring executable bits for codeide-packages..."

# --- Top-level executable scripts ------------------------------------------
# NOTE: setup.sh chmods itself +x last, so future invocations can use
# `./setup.sh` instead of `bash setup.sh`.
for f in \
    build-package.sh \
    build-all.sh \
    clean.sh \
    test-bootstrap.sh \
    scripts/run-docker.sh \
    scripts/run-docker.ps1 \
    scripts/setup-termux.sh \
    scripts/setup-termux-glibc.sh \
    scripts/setup-cgct.sh \
    scripts/setup-android-sdk.sh \
    scripts/setup-archlinux.sh \
    scripts/setup-ubuntu.sh \
    scripts/setup-offline-bundle.sh \
    scripts/build-bootstraps.sh \
    scripts/generate-bootstraps.sh \
    scripts/check-versions.sh \
    scripts/list-versions.sh \
    scripts/list-packages.sh \
    scripts/lint-packages.sh \
    scripts/check-built-packages.py \
    scripts/check-repository-health.js \
    scripts/free-space.sh \
    scripts/update-docker.sh \
    scripts/update-docker.ps1 \
    scripts/aptly_api.sh \
    scripts/buildorder.py \
    scripts/get_hash_from_file.py \
    setup.sh \
    android-push.sh
do
    if [ -f "$f" ]; then
        chmod +x "$f" && echo "  +x $f"
    fi
done

# --- All .sh under scripts/build/ ------------------------------------------
echo "[*] Restoring +x for scripts/build/**/*.sh..."
find scripts/build -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null
find scripts/build -name "*.py" -type f -exec chmod +x {} \; 2>/dev/null
find scripts/build -name "*.sh" -type f -exec echo "  +x {}" \; 2>/dev/null | head -10
echo "  ... ($(find scripts/build -name "*.sh" 2>/dev/null | wc -l) files)"

# --- scripts/bin/ helpers ---------------------------------------------------
echo "[*] Restoring +x for scripts/bin/*..."
if [ -d scripts/bin ]; then
    find scripts/bin -type f -exec chmod +x {} \; 2>/dev/null
    find scripts/bin -type f | while read -r f; do echo "  +x $f"; done
fi

# --- scripts/utils/ shell scripts -----------------------------------------
echo "[*] Restoring +x for scripts/utils/..."
find scripts/utils -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null

# --- scripts/updates/ shell & python scripts -------------------------------
echo "[*] Restoring +x for scripts/updates/..."
find scripts/updates -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null
find scripts/updates -name "*.py" -type f -exec chmod +x {} \; 2>/dev/null

# --- package build.sh files (optional but recommended for direct invocation)
echo "[*] Restoring +x for all packages/*/build.sh (so build-package.sh can find them)..."
find packages -name "build.sh" -type f -exec chmod +x {} \; 2>/dev/null
find root-packages -name "build.sh" -type f -exec chmod +x {} \; 2>/dev/null
find x11-packages -name "build.sh" -type f -exec chmod +x {} \; 2>/dev/null
find disabled-packages -name "build.sh" -type f -exec chmod +x {} \; 2>/dev/null
TOTAL=$(find packages root-packages x11-packages disabled-packages -name "build.sh" 2>/dev/null | wc -l)
echo "  ... ($TOTAL build.sh files)"

# --- config.{sub,guess} (need +x for autotools) ----------------------------
echo "[*] Restoring +x for scripts/config.sub and scripts/config.guess..."
[ -f scripts/config.sub ] && chmod +x scripts/config.sub && echo "  +x scripts/config.sub"
[ -f scripts/config.guess ] && chmod +x scripts/config.guess && echo "  +x scripts/config.guess"

# --- sample/ directory ------------------------------------------------------
if [ -d sample ]; then
    echo "[*] Restoring +x for sample/..."
    find sample -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null
fi

echo ""
echo "=================================================="
echo "✓ Executable bits restored."
echo ""
echo "If you're in a git repo, commit the permission changes:"
echo "    git add -A"
echo "    git commit --amend --no-edit"
echo "    git push -u origin main   # or 'master' — see git branch -M main"
echo "=================================================="
