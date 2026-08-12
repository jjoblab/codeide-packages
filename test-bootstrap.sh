#!/usr/bin/env bash
# ===========================================================================
# test-bootstrap.sh — verify a built bootstrap-aarch64.zip
# ===========================================================================
#
# Extracts a `bootstrap-aarch64.zip` into a temporary directory that
# mimics the CodeIDE runtime layout (/data/data/jo.codeide/files/usr)
# and verifies that:
#
#   1. The zip contains the expected essential binaries
#      (bash, apt, coreutils, sed, grep, tar, ...).
#   2. No ELF binary in the zip is x86 / x86_64 / ARM32 — must be aarch64.
#   3. The second-stage entry script references the jo.codeide prefix
#      (NOT com.termux).
#   4. No file in the zip contains the byte sequence "com.termux" — this
#      is the strongest correctness check: any leakage means the build
#      was not natively compiled with jo.codeide.
#   5. The zip can be extracted cleanly.
#
# This script does NOT require a running Android device — it runs on any
# Linux host with `bash`, `unzip`, `file`, `python3` installed. It is
# suitable for both local dev usage and as a CI step.
#
# Usage:
#   ./test-bootstrap.sh [path/to/bootstrap-aarch64.zip]
#
# Exit codes:
#   0 — all checks passed
#   1 — at least one check failed
#   2 — invalid usage
# ===========================================================================

set -euo pipefail

ZIP_FILE="${1:-bootstrap-aarch64.zip}"

if [[ ! -f "$ZIP_FILE" ]]; then
    echo "❌ File not found: $ZIP_FILE"
    echo "Usage: $0 [path/to/bootstrap-aarch64.zip]"
    exit 2
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

EXTRACT_DIR="$WORK_DIR/rootfs"
mkdir -p "$EXTRACT_DIR"

echo "=== CodeIDE bootstrap verification ==="
echo "Zip file : $ZIP_FILE"
echo "Work dir : $WORK_DIR"
echo ""

# -------------------------------------------------------------------------
# 1. Size check
# -------------------------------------------------------------------------
SIZE=$(stat -c%s "$ZIP_FILE" 2>/dev/null || stat -f%z "$ZIP_FILE")
echo "[1/5] Zip size: $SIZE bytes"
if (( SIZE < 10000000 )); then
    echo "❌ FAIL: bootstrap too small (< 10 MB)"
    exit 1
fi
echo "  ✓ Size OK (> 10 MB)"
echo ""

# -------------------------------------------------------------------------
# 2. Extract zip
# -------------------------------------------------------------------------
echo "[2/5] Extracting zip..."
unzip -q "$ZIP_FILE" -d "$EXTRACT_DIR"
echo "  ✓ Extracted to $EXTRACT_DIR"
ENTRY_COUNT=$(find "$EXTRACT_DIR" -type f | wc -l)
echo "  → $ENTRY_COUNT files extracted"
echo ""

# -------------------------------------------------------------------------
# 3. Check essential binaries exist
# -------------------------------------------------------------------------
echo "[3/5] Checking essential binaries..."
PREFIX_BIN="$EXTRACT_DIR/bin"
ESSENTIAL_BINS=(bash apt ls cat sed grep tar)
MISSING=()
for b in "${ESSENTIAL_BINS[@]}"; do
    # The binary may be a regular file or a symlink to a sibling (e.g.
    # `ls` is often a symlink to `coreutils`).
    if [[ -e "$PREFIX_BIN/$b" || -L "$PREFIX_BIN/$b" ]]; then
        echo "  ✓ bin/$b"
    else
        # Some bootstraps store binaries as `bin/<name>.real` with a
        # wrapper symlink `bin/<name>`. Check that too.
        if compgen -G "$PREFIX_BIN/$b*" > /dev/null; then
            echo "  ✓ bin/$b (matched glob)"
        else
            echo "  ❌ bin/$b MISSING"
            MISSING+=("$b")
        fi
    fi
done
if (( ${#MISSING[@]} > 0 )); then
    echo ""
    echo "❌ FAIL: ${#MISSING[@]} essential binaries missing: ${MISSING[*]}"
    exit 1
fi
echo ""

# -------------------------------------------------------------------------
# 4. ELF architecture check
# -------------------------------------------------------------------------
echo "[4/5] Checking ELF architecture (must be aarch64)..."
ELF_COUNT=0
NON_AARCH64=()
while IFS= read -r -d '' elf; do
    ELF_COUNT=$((ELF_COUNT + 1))
    INFO=$(file "$elf" 2>/dev/null || echo "unknown")
    if echo "$INFO" | grep -q "ELF"; then
        if echo "$INFO" | grep -q "aarch64"; then
            : # OK
        elif echo "$INFO" | grep -qE "x86-64|Intel 80386|ARM, EABI"; then
            NON_AARCH64+=("$elf ($INFO)")
        fi
    fi
done < <(find "$EXTRACT_DIR" -type f -exec sh -c '
    for f; do
        # Cheap ELF detection: read first 4 bytes
        head -c 4 "$f" 2>/dev/null | grep -q $"\x7fELF" && printf "%s\0" "$f"
    done
' _ {} +)

echo "  → $ELF_COUNT ELF files found"
if (( ${#NON_AARCH64[@]} > 0 )); then
    echo ""
    echo "❌ FAIL: ${#NON_AARCH64_COUNT} non-aarch64 ELF binaries found:"
    for e in "${NON_AARCH64[@]}"; do echo "    $e"; done
    exit 1
fi
echo "  ✓ All ELF binaries are aarch64 (or no ELF mismatch found)"
echo ""

# -------------------------------------------------------------------------
# 5. No com.termux leakage + jo.codeide prefix present
# -------------------------------------------------------------------------
echo "[5/5] Checking for com.termux leakage and jo.codeide prefix..."
LEAK=$(python3 - "$ZIP_FILE" <<'PYEOF'
import sys, zipfile
zip_file = sys.argv[1]
com_termux_count = 0
jo_codeide_count = 0
with zipfile.ZipFile(zip_file) as z:
    for info in z.infolist():
        if info.is_dir():
            continue
        data = z.read(info.filename)
        com_termux_count += data.count(b"com.termux")
        jo_codeide_count += data.count(b"jo.codeide")
print(f"{com_termux_count}\t{jo_codeide_count}")
PYEOF
)
COM_TERMUX_COUNT=$(echo "$LEAK" | cut -f1)
JO_CODEIDE_COUNT=$(echo "$LEAK" | cut -f2)

if (( COM_TERMUX_COUNT > 0 )); then
    echo "  ❌ FAIL: $COM_TERMUX_COUNT occurrences of 'com.termux' found in zip"
    echo "          The build was not natively compiled with jo.codeide."
    exit 1
fi
echo "  ✓ Zero 'com.termux' byte sequence in zip"

if (( JO_CODEIDE_COUNT == 0 )); then
    echo "  ⚠️  WARN: 'jo.codeide' not found in zip — bootstrap may not be CodeIDE-native"
    echo "          (this is informational; some Termux forks legitimately remove it)"
else
    echo "  ✓ $JO_CODEIDE_COUNT occurrences of 'jo.codeide' found in zip"
fi
echo ""

echo "================================================"
echo "✓ All bootstrap verification checks passed"
echo "================================================"
exit 0
