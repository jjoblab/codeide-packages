TERMUX_PKG_HOMEPAGE=http://www.libpng.org/pub/png/libpng.html
TERMUX_PKG_DESCRIPTION="Official PNG reference library"
TERMUX_PKG_LICENSE="Libpng"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="1.6.58"
# As of Aug 14 2026, GitHub Actions runners are getting a genuine HTTP 403
# from BOTH master.dl.sourceforge.net and downloads.sourceforge.net for this
# exact file (confirmed in the bootstrap-aarch64 workflow run that failed
# while building the `apt` bootstrap dependency chain) — this is SourceForge
# itself blocking/rate-limiting the runner, not a broken URL or a cache miss.
#
# When the termux-build cache (~/.termux-build, /data) is present, the
# tarball is already on disk and the SourceForge URL is never hit, which
# is why previous builds succeeded. Once the cache is evicted (the repo
# is currently over its 10 GB Actions cache quota — see GitHub Actions
# Caches page), every source must be re-downloaded from scratch, and
# SourceForge returns 403 for libpng.
#
# Primary URL is now MacPorts' distfiles mirror (mirrors.mit.edu), which
# caches the exact same upstream tarball independently of SourceForge and
# is not subject to the same block. Verified against TERMUX_PKG_SHA256.
# SourceForge URLs are kept as fallbacks in case the block is transient
# and a future runner can reach them again.
TERMUX_PKG_SRCURL=https://mirrors.mit.edu/macports/distfiles/libpng/libpng-$TERMUX_PKG_VERSION.tar.xz
TERMUX_PKG_SRCURL_FALLBACKS=(
	"https://downloads.sourceforge.net/project/libpng/libpng16/$TERMUX_PKG_VERSION/libpng-$TERMUX_PKG_VERSION.tar.xz"
	"https://downloads.sourceforge.net/libpng/libpng-$TERMUX_PKG_VERSION.tar.xz"
	"https://master.dl.sourceforge.net/project/libpng/libpng16/$TERMUX_PKG_VERSION/libpng-$TERMUX_PKG_VERSION.tar.xz"
)
TERMUX_PKG_SHA256=28eb403f51f0f7405249132cecfe82ea5c0ef97f1b32c5a65828814ae0d34775
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="zlib"
TERMUX_PKG_BREAKS="libpng-dev"
TERMUX_PKG_REPLACES="libpng-dev"
TERMUX_PKG_RM_AFTER_INSTALL="bin/png-fix-itxt bin/pngfix"
