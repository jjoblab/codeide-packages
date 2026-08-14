TERMUX_PKG_HOMEPAGE=https://swig.org
TERMUX_PKG_DESCRIPTION="Generate scripting interfaces to C/C++ code"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_LICENSE_FILE="LICENSE, LICENSE-GPL, LICENSE-UNIVERSITIES, COPYRIGHT"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="4.5.0"
# As of Aug 14 2026, GitHub Actions runners get HTTP 403 from
# downloads.sourceforge.net. Fossies.org hosts the exact same swig release
# tarball (SHA256 verified:
# 22ae0e887f8cca8031a325c67d005207653200b40e71edb3f88780e28e47d0ff).
# SourceForge URL kept as fallback.
TERMUX_PKG_SRCURL=https://fossies.org/linux/misc/swig-$TERMUX_PKG_VERSION.tar.gz
TERMUX_PKG_SRCURL_FALLBACKS=(
        "https://downloads.sourceforge.net/swig/swig-$TERMUX_PKG_VERSION.tar.gz"
        "https://downloads.sourceforge.net/project/swig/swig/swig-$TERMUX_PKG_VERSION/swig-$TERMUX_PKG_VERSION.tar.gz"
)
TERMUX_PKG_SHA256=22ae0e887f8cca8031a325c67d005207653200b40e71edb3f88780e28e47d0ff
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="libc++, pcre2, zlib"
TERMUX_PKG_BUILD_IN_SRC=true
