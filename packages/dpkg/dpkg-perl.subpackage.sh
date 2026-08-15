TERMUX_SUBPKG_DESCRIPTION="Perl modules for dpkg"
TERMUX_SUBPKG_INCLUDE="share/perl5"
TERMUX_SUBPKG_DEPENDS="perl, make"
TERMUX_SUBPKG_PLATFORM_INDEPENDENT=true

# NOTE: The original Termux dpkg-perl subpackage depends on `clang` because
# its postinst script runs `cpan -Ti Locale::gettext` which compiles a Perl
# module from source (requires a C compiler).
#
# However, CodeIDE's apt repo does NOT include `clang` (it's a ~500 MB
# package that would make the repo huge and slow to build). Without clang
# in the repo, the dependency on clang makes dpkg-perl uninstallable, which
# blocks ALL apt install operations:
#
#   E: Unable to correct problems, you have held broken packages.
#   dpkg-perl : Depends: clang but it is not installable
#
# FIX: Remove `clang` from TERMUX_SUBPKG_DEPENDS. The postinst script
# that runs `cpan -Ti Locale::gettext` will fail silently (the module
# won't be installed), but dpkg-perl itself will install correctly.
# Users who actually need Locale::gettext can install clang manually
# and run `cpan -Ti Locale::gettext` themselves.
#
# The `cpan` call in the postinst is non-fatal (uses `|| echo` instead
# of `set -e`) so the package installs cleanly even without clang.

termux_step_create_subpkg_debscripts() {
	cat > ./postinst <<POSTINST_EOF
#!$TERMUX_PREFIX/bin/bash
# CodeIDE dpkg-perl postinst
# Don't use 'set -e' - the cpan call may fail if clang is not installed,
# but that shouldn't fail the whole package installation.
export PERL_MM_USE_DEFAULT=1

echo "Sideloading Perl Locale::gettext ..."
cpan -Ti Locale::gettext 2>/dev/null || echo "Warning: cpan Locale::gettext failed (clang not installed?) - skipping"

exit 0
POSTINST_EOF
}
