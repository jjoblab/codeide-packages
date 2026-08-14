TERMUX_PKG_HOMEPAGE=https://www.freetype.org
TERMUX_PKG_DESCRIPTION="Software font engine capable of producing high-quality output"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="2.14.3"
# As of Aug 14 2026, GitHub Actions runners are getting HTTP 403 from
# downloads.sourceforge.net for this exact file (same issue as libpng and
# tcl). MacPorts distfiles mirror (mirrors.mit.edu) hosts the identical
# upstream tarball, verified against TERMUX_PKG_SHA256 below.
# NOTE: even without this explicit override, scripts/build/termux_download.sh
# now rewrites any SourceForge URL to MacPorts automatically. This build.sh
# override is kept as belt-and-suspenders (and so the primary URL in the
# build log clearly shows where the file is coming from, instead of the
# silent rewrite). SourceForge URL kept as a fallback in case the block
# is transient.
TERMUX_PKG_SRCURL=https://mirrors.mit.edu/macports/distfiles/freetype/freetype-${TERMUX_PKG_VERSION}.tar.xz
TERMUX_PKG_SRCURL_FALLBACKS=(
        "https://downloads.sourceforge.net/freetype/freetype-${TERMUX_PKG_VERSION}.tar.xz"
        "https://download.savannah.nongnu.org/releases/freetype/freetype-${TERMUX_PKG_VERSION}.tar.xz"
        "https://master.dl.sourceforge.net/project/freetype/freetype2/${TERMUX_PKG_VERSION}/freetype-${TERMUX_PKG_VERSION}.tar.xz"
)
#TERMUX_PKG_SRCURL=https://download.savannah.nongnu.org/releases/freetype/freetype-${TERMUX_PKG_VERSION}.tar.xz
TERMUX_PKG_SHA256=36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f
TERMUX_PKG_DEPENDS="brotli, libbz2, libpng, zlib"
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_BREAKS="freetype-dev"
TERMUX_PKG_REPLACES="freetype-dev"
# Use with-harfbuzz=no to avoid circular dependency between freetype and harfbuzz:
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="--with-harfbuzz=no"
# not install these files anymore so install them manually.
termux_step_post_make_install() {
        install -Dm700 freetype-config $TERMUX_PREFIX/bin/freetype-config
        install -Dm600 ../src/docs/freetype-config.1 $TERMUX_PREFIX/share/man/man1/freetype-config.1
}
