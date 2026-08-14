TERMUX_PKG_HOMEPAGE=https://www.tcl.tk/
TERMUX_PKG_DESCRIPTION="Powerful but easy to learn dynamic programming language"
TERMUX_PKG_LICENSE="custom"
TERMUX_PKG_LICENSE_FILE="license.terms"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="8.6.16"
# Both master.dl.sourceforge.net AND downloads.sourceforge.net return 403
# for this file from GitHub Actions runners (confirmed Aug 13 2026, see
# failed 'apt' bootstrap build — 6 attempts, both hosts, all 403). This is
# SourceForge's edge/anti-bot layer blocking the runner's datacenter IP
# range, not a broken URL, so swapping between those two auto-selector
# hosts alone doesn't help: they sit behind the same frontend.
#
# Fix: bypass the auto-selector entirely and hit named mirror nodes
# directly (each is a distinct backend, not guaranteed to share the same
# block) — same file, same checksum, just served from a specific mirror
# instead of being geo/IP-routed by SourceForge's front door. Also keep
# the legacy no-/project/-prefix alias, which is occasionally routed
# differently than the versioned path. If SourceForge blocks the runner's
# IP range at the network level (not just the front-end), none of these
# will help either — in that case just re-run the workflow (the block
# tends to be tied to the runner's transient IP, not permanent) and once
# the download succeeds once, the "Cache termux build directories" step
# keeps it cached for subsequent runs.
TERMUX_PKG_SRCURL=https://master.dl.sourceforge.net/project/tcl/Tcl/${TERMUX_PKG_VERSION}/tcl${TERMUX_PKG_VERSION}-src.tar.gz
TERMUX_PKG_SRCURL_FALLBACKS=(
	"https://downloads.sourceforge.net/project/tcl/Tcl/${TERMUX_PKG_VERSION}/tcl${TERMUX_PKG_VERSION}-src.tar.gz"
	"https://downloads.sourceforge.net/tcl/tcl${TERMUX_PKG_VERSION}-src.tar.gz"
	"https://kumisystems.dl.sourceforge.net/project/tcl/Tcl/${TERMUX_PKG_VERSION}/tcl${TERMUX_PKG_VERSION}-src.tar.gz"
	"https://excellmedia.dl.sourceforge.net/project/tcl/Tcl/${TERMUX_PKG_VERSION}/tcl${TERMUX_PKG_VERSION}-src.tar.gz"
	"https://netcologne.dl.sourceforge.net/project/tcl/Tcl/${TERMUX_PKG_VERSION}/tcl${TERMUX_PKG_VERSION}-src.tar.gz"
	"https://phoenixnap.dl.sourceforge.net/project/tcl/Tcl/${TERMUX_PKG_VERSION}/tcl${TERMUX_PKG_VERSION}-src.tar.gz"
	"https://versaweb.dl.sourceforge.net/project/tcl/Tcl/${TERMUX_PKG_VERSION}/tcl${TERMUX_PKG_VERSION}-src.tar.gz"
)
TERMUX_PKG_SHA256=91cb8fa61771c63c262efb553059b7c7ad6757afa5857af6265e4b0bdc2a14a5
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_DEPENDS="zlib"
TERMUX_PKG_BREAKS="tcl-dev, tcl-static"
TERMUX_PKG_REPLACES="tcl-dev, tcl-static"
TERMUX_PKG_NO_STATICSPLIT=true

TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
ac_cv_func_memcmp_working=yes
ac_cv_func_memcmp=yes
ac_cv_func_strtod=yes
ac_cv_func_strtoul=yes
tcl_cv_strstr_unbroken=ok
tcl_cv_strtod_buggy=ok
tcl_cv_strtod_unbroken=ok
tcl_cv_strtoul_unbroken=ok
--disable-rpath
--enable-man-symlinks
--mandir=$TERMUX_PREFIX/share/man
"

termux_step_pre_configure() {
	rm -rf $TERMUX_PKG_SRCDIR/pkgs/sqlite3* # libsqlite-tcl is a separate package
	TERMUX_PKG_SRCDIR=$TERMUX_PKG_SRCDIR/unix
	CFLAGS+=" -DBIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD"
}

termux_step_post_make_install() {
	# expect needs private headers
	make install-private-headers
	local _MAJOR_VERSION=${TERMUX_PKG_VERSION:0:3}
	cd $TERMUX_PREFIX/bin
	ln -f -s tclsh$_MAJOR_VERSION tclsh

	# Needed to install $TERMUX_PKG_LICENSE_FILE.
	TERMUX_PKG_SRCDIR=$(dirname "$TERMUX_PKG_SRCDIR")

	#avoid conflict with perl
	mv $TERMUX_PREFIX/share/man/man3/Thread.3 $TERMUX_PREFIX/share/man/man3/Tcl_Thread.3
}
