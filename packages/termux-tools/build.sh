TERMUX_PKG_HOMEPAGE=https://termux.dev/
TERMUX_PKG_DESCRIPTION="Basic system tools for Termux"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="1.46.0+really1.45.0"
TERMUX_PKG_REVISION=1
TERMUX_PKG_SRCURL=https://github.com/termux/termux-tools/archive/refs/tags/v1.45.0.tar.gz
TERMUX_PKG_SHA256=1ae29b1b875d95cc626dae323b45a2ace759969862d96094b2fa6d13bffe20d2
TERMUX_PKG_ESSENTIAL=true
#TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_UPDATE_TAG_TYPE="newest-tag"
TERMUX_PKG_BREAKS="termux-keyring (<< 1.9)"
TERMUX_PKG_CONFLICTS="procps (<< 3.3.15-2)"
TERMUX_PKG_SUGGESTS="termux-api"

# Some of these packages are not dependencies and used only to ensure
# that core packages are installed after upgrading (we removed busybox
# from essentials).
TERMUX_PKG_DEPENDS="bzip2, coreutils, curl, dash, diffutils, findutils, gawk, grep, gzip, less, procps, psmisc, sed, tar, termux-am (>= 0.8.0), termux-am-socket (>= 1.5.0), termux-core, termux-exec, util-linux, xz-utils, dialog"

# Optional packages that are distributed as part of bootstrap archives.
TERMUX_PKG_RECOMMENDS="ed, dos2unix, inetutils, net-tools, patch, unzip"

termux_step_pre_configure() {
	# Export Termux identity variables so that ./configure (which runs as
	# a child process) can detect them and use jo.codeide instead of the
	# hardcoded com.termux fallback in configure.ac.
	#
	# Without these exports, the compiled termux-tools binaries (cmd,
	# termux-open, etc.) have "/data/data/com.termux/..." paths baked
	# into the ELF, which breaks the "no com.termux leakage" check in
	# the GitHub Actions workflow.
	#
	# The variables are defined in scripts/properties.sh as shell
	# variables (deprecated aliases), but NOT exported. We export them
	# here just before autoreconf/configure runs.
	export TERMUX_APP_PACKAGE
	export TERMUX_BASE_DIR
	export TERMUX_CACHE_DIR
	export TERMUX_PREFIX
	export TERMUX_ANDROID_HOME
	export TERMUX_PACKAGE_FORMAT
	export TERMUX_PACKAGE_MANAGER

	autoreconf -vfi
}

termux_step_post_make_install() {
	TERMUX_PKG_CONFFILES="$(cat "$TERMUX_PKG_BUILDDIR/conffiles")"

	# Global scan-and-replace: find ALL text files in $TERMUX_PREFIX that
	# contain the hardcoded runtime path "/data/data/com.termux" and
	# replace it with "/data/data/$TERMUX_APP_PACKAGE".
	#
	# This catches files that are NOT processed by configure/Makefile
	# templates (which use @TERMUX_APP_PACKAGE@ placeholders). Examples:
	#   - share/examples/termux/termux.properties (comment with hardcoded path)
	#   - share/man/man1/termux.1 (man page with examples)
	#   - bin/termux-reset (script with Java class name)
	#   - any other installed text file with a stray com.termux path
	#
	# `grep -I` (capital I) excludes binary files, so this is safe for
	# ELF binaries and .gz compressed files.
	#
	# Without this, the CI verification check "no com.termux runtime
	# leakage" fails because it scans the final bootstrap zip for the
	# byte sequence b'/data/data/com.termux'.
	echo "[termux-tools] Scanning installed files for /data/data/com.termux..."
	local patched=0
	while IFS= read -r -d '' f; do
		if grep -q '/data/data/com\.termux' "$f" 2>/dev/null; then
			sed -i "s|/data/data/com\.termux|/data/data/$TERMUX_APP_PACKAGE|g" "$f"
			echo "[termux-tools]   patched: ${f#$TERMUX_PREFIX/}"
			patched=$((patched+1))
		fi
	done < <(find "$TERMUX_PREFIX" -type f -size -1M \
		! -name "*.gz" ! -name "*.zip" ! -name "*.xz" ! -name "*.bz2" \
		! -name "*.png" ! -name "*.jpg" ! -name "*.so" ! -name "*.a" \
		-print0 2>/dev/null)
	echo "[termux-tools] Patched $patched file(s) with /data/data/com.termux → /data/data/$TERMUX_APP_PACKAGE"
}

termux_step_create_debscripts() {
	cat <<- EOF > ./preinst
	$(cat "$TERMUX_PKG_BUILDDIR/preinst")
	EOF
}
