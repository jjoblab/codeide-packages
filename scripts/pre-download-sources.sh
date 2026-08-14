#!/usr/bin/bash
# ============================================================
# Pre-download SourceForge-dependent sources from reliable mirrors
# ============================================================
#
# As of Aug 2026, SourceForge returns HTTP 403 to GitHub Actions
# runner IPs. This script pre-downloads ALL source tarballs that
# are normally hosted on SourceForge from alternative mirrors
# (GitHub releases, MacPorts distfiles, Ubuntu archive, NetBSD
# distfiles, Fossies) and places them in the termux build cache.
#
# When the actual build runs, termux_download() finds the files
# already on disk with matching SHA256 and skips downloading.
# This completely eliminates SourceForge 403 failures.
#
# DUAL USER-AGENT STRATEGY:
#   Different mirrors require different User-Agents:
#   - GitHub releases: requires a browser-like UA (Chrome). Returns
#     404 for Wget/curl UAs.
#   - Fossies: blocks browser UAs that don't execute JavaScript
#     (anti-robot check, returns 401). ALLOWS Wget UA.
#   - MacPorts, Ubuntu, NetBSD: work with any UA.
#
#   This script tries EACH URL with BOTH User-Agents (Chrome first,
#   then Wget) so all mirrors are reachable.
#
# This script is safe to run multiple times — it skips files
# that already exist with the correct checksum.
#
# Usage: ./scripts/pre-download-sources.sh
# ============================================================

set -uo pipefail   # NOT -e: we want to continue even if some downloads fail

TERMUX_BUILD_DIR="${HOME}/.termux-build"

# Two User-Agents for the dual-UA strategy
UA_BROWSER="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
UA_WGET="Wget/1.21"

# Download a file from one or more URLs, trying each URL with both UAs.
# Arguments: <sha256> <cache_dir> <filename> <url1> [url2] [url3]...
pre_download() {
    local expected_sha="$1"
    local cache_dir="$2"
    local filename="$3"
    shift 3
    local -a urls=("$@")
    local dest="${cache_dir}/${filename}"

    mkdir -p "$cache_dir"

    # Check if file already exists with correct checksum
    if [ -f "$dest" ]; then
        local existing_sha
        existing_sha=$(sha256sum "$dest" | cut -d' ' -f1)
        if [[ "$existing_sha" == "$expected_sha" ]]; then
            echo "  ✓ Already cached: ${filename}"
            return 0
        fi
        echo "  ⚠ Checksum mismatch for cached ${filename}, re-downloading..."
        rm -f "$dest"
    fi

    # Try each URL with each User-Agent
    for url in "${urls[@]}"; do
        for ua in "$UA_BROWSER" "$UA_WGET"; do
            echo "  → Trying: ${url}"
            echo "    UA: $(echo "$ua" | head -c 40)..."
            if curl -sL --fail \
                    --max-time 120 \
                    --connect-timeout 30 \
                    --retry 2 \
                    --retry-delay 5 \
                    -A "$ua" \
                    -o "$dest" "$url" 2>/dev/null; then
                local actual_sha
                actual_sha=$(sha256sum "$dest" | cut -d' ' -f1)
                if [[ "$actual_sha" == "$expected_sha" ]]; then
                    echo "  ✓ Downloaded: ${filename} (${actual_sha:0:12}...)"
                    return 0
                else
                    echo "  ✗ SHA256 mismatch (got ${actual_sha:0:12}...)"
                    rm -f "$dest"
                fi
            else
                echo "  ✗ Download failed (HTTP error or timeout)"
                rm -f "$dest"
            fi
        done
    done

    echo "  ❌ FAILED to download ${filename} from any mirror"
    return 1
}

echo "============================================================"
echo "Pre-downloading SourceForge-dependent sources from reliable"
echo "mirrors (MacPorts, GitHub releases, Ubuntu, NetBSD, Fossies)"
echo ""
echo "Dual User-Agent strategy: tries Chrome UA first, then Wget UA"
echo "for each URL (different mirrors require different UAs)."
echo "============================================================"
echo ""

FAILED=0

# --- tcl (dependency of libsqlite, python, etc.) ---
# Verified mirrors: MacPorts ✓ (Chrome UA)
echo "=== tcl 8.6.16 ==="
pre_download \
    "91cb8fa61771c63c262efb553059b7c7ad6757afa5857af6265e4b0bdc2a14a5" \
    "${TERMUX_BUILD_DIR}/tcl/cache" \
    "tcl8.6.16-src.tar.gz" \
    "https://mirrors.mit.edu/macports/distfiles/tcl/tcl8.6.16-src.tar.gz" \
    "https://downloads.sourceforge.net/project/tcl/Tcl/8.6.16/tcl8.6.16-src.tar.gz" \
    || FAILED=1
echo ""

# --- libpng (dependency of freetype, fontconfig, etc.) ---
# Verified mirrors: MacPorts ✓ (Chrome UA)
echo "=== libpng 1.6.58 ==="
pre_download \
    "28eb403f51f0f7405249132cecfe82ea5c0ef97f1b32c5a65828814ae0d34775" \
    "${TERMUX_BUILD_DIR}/libpng/cache" \
    "libpng-1.6.58.tar.xz" \
    "https://mirrors.mit.edu/macports/distfiles/libpng/libpng-1.6.58.tar.xz" \
    "https://downloads.sourceforge.net/project/libpng/libpng16/1.6.58/libpng-1.6.58.tar.xz" \
    || FAILED=1
echo ""

# --- freetype (dependency of fontconfig, etc.) ---
# Verified mirrors: MacPorts ✓, savannah ✓ (Chrome UA)
echo "=== freetype 2.14.3 ==="
pre_download \
    "36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f" \
    "${TERMUX_BUILD_DIR}/freetype/cache" \
    "freetype-2.14.3.tar.xz" \
    "https://mirrors.mit.edu/macports/distfiles/freetype/freetype-2.14.3.tar.xz" \
    "https://download.savannah.nongnu.org/releases/freetype/freetype-2.14.3.tar.xz" \
    "https://downloads.sourceforge.net/freetype/freetype-2.14.3.tar.xz" \
    || FAILED=1
echo ""

# --- ttf-dejavu (dependency of fontconfig) ---
# Verified mirrors:
#   GitHub releases ✓ (Chrome UA, SHA256 fa9ca4d13871dd122f61258a80d01751d603b4d3...)
#   NetBSD distfiles ✓ (Chrome UA, same SHA256)
echo "=== ttf-dejavu 2.37 ==="
pre_download \
    "fa9ca4d13871dd122f61258a80d01751d603b4d3ee14095d65453b4e846e17d7" \
    "${TERMUX_BUILD_DIR}/ttf-dejavu/cache" \
    "dejavu-fonts-ttf-2.37.tar.bz2" \
    "https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2.37/dejavu-fonts-ttf-2.37.tar.bz2" \
    "https://cdn.netbsd.org/pub/pkgsrc/distfiles/dejavu-fonts-ttf-2.37.tar.bz2" \
    "https://downloads.sourceforge.net/project/dejavu/dejavu/2.37/dejavu-fonts-ttf-2.37.tar.bz2" \
    || FAILED=1
echo ""

# --- tk (dependency of python, etc.) ---
# Verified mirrors: Ubuntu archive ✓ (Chrome UA, SHA256 8ffdb720f47a6ca6107eac2d...)
# NOTE: Ubuntu archive has different filename (tk8.6_8.6.14.orig.tar.gz) but
#       same content/SHA256 as SourceForge's tk8.6.14-src.tar.gz.
echo "=== tk 8.6.14 ==="
pre_download \
    "8ffdb720f47a6ca6107eac2dd877e30b0ef7fac14f3a84ebbd0b3612cee41a94" \
    "${TERMUX_BUILD_DIR}/tk/cache" \
    "tk8.6_8.6.14.orig.tar.gz" \
    "https://archive.ubuntu.com/ubuntu/pool/main/t/tk8.6/tk8.6_8.6.14.orig.tar.gz" \
    "https://downloads.sourceforge.net/project/tcl/Tcl/8.6.14/tk8.6.14-src.tar.gz" \
    || FAILED=1
echo ""

# --- swig (dependency of python, etc.) ---
# Verified mirrors: Fossies ✓ (Wget UA, SHA256 22ae0e887f8cca8031a325c67d005207653200b4...)
# Fossies blocks Chrome UA (401 anti-robot) but ALLOWS Wget UA.
# The dual-UA strategy in pre_download() handles this automatically.
echo "=== swig 4.5.0 ==="
pre_download \
    "22ae0e887f8cca8031a325c67d005207653200b40e71edb3f88780e28e47d0ff" \
    "${TERMUX_BUILD_DIR}/swig/cache" \
    "swig-4.5.0.tar.gz" \
    "https://fossies.org/linux/misc/swig-4.5.0.tar.gz" \
    "https://downloads.sourceforge.net/swig/swig-4.5.0.tar.gz" \
    "https://downloads.sourceforge.net/project/swig/swig/swig-4.5.0/swig-4.5.0.tar.gz" \
    || FAILED=1
echo ""

# --- fontconfig (dependency of many graphical packages) ---
# gitlab.freedesktop.org deploys Anubis anti-bot protection that returns
# HTML instead of the tarball to automated downloads. GitHub mirror
# (fontconfig/fontconfig) serves the EXACT same tarball (SHA256 verified).
# NOTE: GitHub archive URL produces filename "2.18.3.tar.gz" but the
# pre-download cache uses the basename of the URL. The build.sh uses
# the same GitHub URL so the filenames match.
echo "=== fontconfig 2.18.3 ==="
pre_download \
    "9ae01e1d53acdef56010c5451cd34aa41d325b2faccd8606448d8fa01b2496b3" \
    "${TERMUX_BUILD_DIR}/fontconfig/cache" \
    "2.18.3.tar.gz" \
    "https://github.com/fontconfig/fontconfig/archive/refs/tags/2.18.3.tar.gz" \
    "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/2.18.3/fontconfig-2.18.3.tar.gz" \
    || FAILED=1
echo ""

echo "============================================================"
if [ "$FAILED" -eq 0 ]; then
    echo "✅ All sources pre-downloaded successfully!"
    echo "   The build will find all files in cache and skip downloading."
else
    echo "⚠️  Some sources failed to pre-download."
    echo "   The build will try to download them itself."
    echo "   If the build also fails, the mirror may be temporarily down."
fi
echo "============================================================"
