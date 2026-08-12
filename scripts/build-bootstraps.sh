#!/usr/bin/env bash
# shellcheck disable=SC2039,SC2059

# Title:         build-bootstrap.sh
# Description:   A script to build bootstrap archives for the CodeIDE app
#                (jo.codeide) from local package sources instead of debs
#                published in apt repo like done by generate-bootstrap.sh.
#                It allows bootstrap archives to be easily built for
#                (forked) termux apps without having to publish an apt
#                repo first.
# Usage:         run "build-bootstrap.sh --help"
version=0.2.0-codeide

set -e

export TERMUX_SCRIPTDIR=$(realpath "$(dirname "$(realpath "$0")")/../")
: "${TERMUX_TOPDIR:="$HOME/.termux-build"}"
. "${TERMUX_SCRIPTDIR}"/scripts/properties.sh
. "${TERMUX_SCRIPTDIR}"/scripts/build/termux_step_handle_buildarch.sh

BOOTSTRAP_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-tmp.XXXXXXXX")

# By default, bootstrap archives are compatible with Android >=7.0
# and <10.
BOOTSTRAP_ANDROID10_COMPATIBLE=false

# By default, CodeIDE bootstrap archives are built for aarch64 only.
# This is the only architecture supported by CodeIDE v1 to keep CI fast.
# Override with option '--architectures' (e.g. for experimental arm builds).
TERMUX_DEFAULT_ARCHITECTURES=("aarch64")
TERMUX_ARCHITECTURES=("${TERMUX_DEFAULT_ARCHITECTURES[@]}")

TERMUX_PACKAGES_DIRECTORY="/home/builder/termux-packages"
TERMUX_BUILT_DEBS_DIRECTORY="$TERMUX_PACKAGES_DIRECTORY/output"
TERMUX_BUILT_PACKAGES_DIRECTORY="/data/data/.built-packages"

IGNORE_BUILD_SCRIPT_NOT_FOUND_ERROR=1
FORCE_BUILD_PACKAGES=0

# A list of packages to build
# Populated from `bootstrap-packages.txt` if present (minimal CodeIDE
# bootstrap list), otherwise falls back to a hardcoded minimal list.
declare -a PACKAGES=()

# Path to the bootstrap packages list file. Defaults to
# `$TERMUX_PACKAGES_DIRECTORY/bootstrap-packages.txt`.
BOOTSTRAP_PACKAGES_LIST_FILE="bootstrap-packages.txt"

# A list of non-essential packages to build.
# By default it is empty, but can be filled with option '--add'.
declare -a ADDITIONAL_PACKAGES=()

# A list of already extracted packages
declare -a EXTRACTED_PACKAGES=()

# A list of options to pass to build-package.sh
declare -a BUILD_PACKAGE_OPTIONS=()

# Check for some important utilities that may not be available for
# some reason.
for cmd in ar awk curl grep gzip find sed tar xargs xz zip; do
        if [ -z "$(command -v $cmd)" ]; then
                echo "[!] Utility '$cmd' is not available in PATH."
                exit 1
        fi
done

# Build deb files for package and its dependencies deb from source for arch
build_package() {

        local return_value

        local TERMUX_ARCH="$1"
        local package_name="$2"

        local build_output

        # Build package from source
        # stderr will be redirected to stdout and both will be captured into variable and printed on screen
        cd "$TERMUX_PACKAGES_DIRECTORY"
        echo $'\n\n\n'"[*] Building '$package_name'..."
        exec 99>&1
        build_output="$("$TERMUX_PACKAGES_DIRECTORY"/build-package.sh "${BUILD_PACKAGE_OPTIONS[@]}" -a "$TERMUX_ARCH" "$package_name" 2>&1 | tee >(cat - >&99); exit ${PIPESTATUS[0]})";
        return_value=$?
        echo "[*] Building '$package_name' exited with exit code $return_value"
        exec 99>&-
        if [ $return_value -ne 0 ]; then
                echo "Failed to build package '$package_name' for arch '$TERMUX_ARCH'" 1>&2

                # Dependency packages may not have a build.sh, so we ignore the error.
                # A better way should be implemented to validate if its actually a dependency
                # and not a required package itself, by removing dependencies from PACKAGES array.
                if [[ $IGNORE_BUILD_SCRIPT_NOT_FOUND_ERROR == "1" ]] && [[ "$build_output" == *"No build.sh script at package dir"* ]]; then
                        echo "Ignoring error 'No build.sh script at package dir'" 1>&2
                        return 0
                fi
        fi

        return $return_value

}

# Extract *.deb files to the bootstrap root.
extract_debs() {

        local package_arch="$1"
        local current_package_name
        local data_archive
        local control_archive
        local package_tmpdir
        local deb
        local file

        cd "$TERMUX_BUILT_DEBS_DIRECTORY"

        if [ -z "$(ls -A)" ]; then
                echo $'\n\n\n'"No debs found"
                return 1
        else
                echo $'\n\n\n'"Deb Files:"
                echo "\""
                ls
                echo "\""
        fi

        for deb in *.deb; do

                current_package_name="$(echo "$deb" | sed -E 's/^([^_]+).*/\1/' )"
                current_package_arch="$(echo "$deb" | sed -E 's/.*_(aarch64|all|arm|i686|x86_64).deb$/\1/' )"
                echo "current_package_name: '$current_package_name'"
                echo "current_package_arch: '$current_package_arch'"

                if [[ "$current_package_arch" != "$package_arch" ]] && [[ "$current_package_arch" != "all" ]]; then
                        echo "[*] Skipping incompatible package '$deb' for target '$package_arch'..."
                        continue
                fi

                if [[ "$current_package_name" == *"-static" ]]; then
                        echo "[*] Skipping static package '$deb'..."
                        continue
                fi

                if [[ " ${EXTRACTED_PACKAGES[*]} " == *" $current_package_name "* ]]; then
                        echo "[*] Skipping already extracted package '$current_package_name'..."
                        continue
                fi

                EXTRACTED_PACKAGES+=("$current_package_name")

                package_tmpdir="${BOOTSTRAP_PKGDIR}/${current_package_name}"
                mkdir -p "$package_tmpdir"
                rm -rf "$package_tmpdir"/*

                echo "[*] Extracting '$deb'..."
                (cd "$package_tmpdir"
                        ar x "$TERMUX_BUILT_DEBS_DIRECTORY/$deb"

                        # data.tar may have extension different from .xz
                        if [ -f "./data.tar.xz" ]; then
                                data_archive="data.tar.xz"
                        elif [ -f "./data.tar.gz" ]; then
                                data_archive="data.tar.gz"
                        else
                                echo "No data.tar.* found in '$deb'."
                                return 1
                        fi

                        # Do same for control.tar.
                        if [ -f "./control.tar.xz" ]; then
                                control_archive="control.tar.xz"
                        elif [ -f "./control.tar.gz" ]; then
                                control_archive="control.tar.gz"
                        else
                                echo "No control.tar.* found in '$deb'."
                                return 1
                        fi

                        # Extract files.
                        tar xf "$data_archive" -C "$BOOTSTRAP_ROOTFS"

                        if ! ${BOOTSTRAP_ANDROID10_COMPATIBLE}; then
                                # Register extracted files.
                                tar tf "$data_archive" | sed -E -e 's@^\./@/@' -e 's@^/$@/.@' -e 's@^([^./])@/\1@' > "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/info/${current_package_name}.list"

                                # Generate checksums (md5).
                                tar xf "$data_archive"
                                find data -type f -print0 | xargs -0 -r md5sum | sed 's@^\.$@@g' > "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/info/${current_package_name}.md5sums"

                                # Extract metadata.
                                tar xf "$control_archive"
                                {
                                        cat control
                                        echo "Status: install ok installed"
                                        echo
                                } >> "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/status"

                                # Additional data: conffiles & scripts
                                for file in conffiles postinst postrm preinst prerm; do
                                        if [ -f "${PWD}/${file}" ]; then
                                                cp "$file" "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/info/${current_package_name}.${file}"
                                        fi
                                done
                        fi
                )
        done

}

# Add termux bootstrap second stage files
add_termux_bootstrap_second_stage_files() {

        local package_arch="$1"

        echo $'\n\n\n'"[*] Adding termux bootstrap second stage files..."

        mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_BOOTSTRAP__BOOTSTRAP_SECOND_STAGE_DIR}"
        sed -e "s|@TERMUX_PREFIX@|${TERMUX_PREFIX}|g" \
                -e "s|@TERMUX_BOOTSTRAP__BOOTSTRAP_SECOND_STAGE_DIR@|${TERMUX_BOOTSTRAP__BOOTSTRAP_SECOND_STAGE_DIR}|g" \
                -e "s|@TERMUX_BOOTSTRAP__BOOTSTRAP_SECOND_STAGE_ENTRY_POINT_SUBFILE@|${TERMUX_BOOTSTRAP__BOOTSTRAP_SECOND_STAGE_ENTRY_POINT_SUBFILE}|g" \
                -e "s|@TERMUX_PACKAGE_MANAGER@|${TERMUX_PACKAGE_MANAGER}|g" \
                -e "s|@TERMUX_PACKAGE_ARCH@|${package_arch}|g" \
                -e "s|@TERMUX_APP__NAME@|${TERMUX_APP__NAME}|g" \
                -e "s|@TERMUX_ENV__S_TERMUX@|${TERMUX_ENV__S_TERMUX}|g" \
                "$TERMUX_SCRIPTDIR/scripts/bootstrap/$TERMUX_BOOTSTRAP__BOOTSTRAP_SECOND_STAGE_ENTRY_POINT_SUBFILE" \
                > "${BOOTSTRAP_ROOTFS}/${TERMUX_BOOTSTRAP__BOOTSTRAP_SECOND_STAGE_DIR}/$TERMUX_BOOTSTRAP__BOOTSTRAP_SECOND_STAGE_ENTRY_POINT_SUBFILE"
        chmod 700 "${BOOTSTRAP_ROOTFS}/${TERMUX_BOOTSTRAP__BOOTSTRAP_SECOND_STAGE_DIR}/$TERMUX_BOOTSTRAP__BOOTSTRAP_SECOND_STAGE_ENTRY_POINT_SUBFILE"

        # TODO: Remove it when Termux app supports `pacman` bootstraps installation.
        sed -e "s|@TERMUX_PREFIX@|${TERMUX_PREFIX}|g" \
                -e "s|@TERMUX__PREFIX__PROFILE_D_DIR@|${TERMUX__PREFIX__PROFILE_D_DIR}|g" \
                -e "s|@TERMUX_BOOTSTRAP__BOOTSTRAP_SECOND_STAGE_DIR@|${TERMUX_BOOTSTRAP__BOOTSTRAP_SECOND_STAGE_DIR}|g" \
                -e "s|@TERMUX_BOOTSTRAP__BOOTSTRAP_SECOND_STAGE_ENTRY_POINT_SUBFILE@|${TERMUX_BOOTSTRAP__BOOTSTRAP_SECOND_STAGE_ENTRY_POINT_SUBFILE}|g" \
                "$TERMUX_SCRIPTDIR/scripts/bootstrap/01-termux-bootstrap-second-stage-fallback.sh" \
                > "${BOOTSTRAP_ROOTFS}/${TERMUX__PREFIX__PROFILE_D_DIR}/01-termux-bootstrap-second-stage-fallback.sh"
        chmod 600 "${BOOTSTRAP_ROOTFS}/${TERMUX__PREFIX__PROFILE_D_DIR}/01-termux-bootstrap-second-stage-fallback.sh"

}

# Final stage: generate bootstrap archive and place it to current
# working directory.
# Information about symlinks is stored in file SYMLINKS.txt.
create_bootstrap_archive() {

        echo $'\n\n\n'"[*] Creating 'bootstrap-${1}.zip'..."
        (cd "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}"
                # Do not store symlinks in bootstrap archive.
                # Instead, put all information to SYMLINKS.txt
                while read -r -d '' link; do
                        echo "$(readlink "$link")←${link}" >> SYMLINKS.txt
                        rm -f "$link"
                done < <(find . -type l -print0)

                zip -r9 "${BOOTSTRAP_TMPDIR}/bootstrap-${1}.zip" ./*
        )

        # Try the primary output directory first ($TERMUX_PACKAGES_DIRECTORY,
        # which is the repo root and is volume-mounted from the host). If
        # that fails (Permission denied — happens on GitHub Actions where
        # the container's `builder` user cannot write to the host-mounted
        # repo), fall back to ~/.termux-build/ which is mounted writable
        # via `run-docker.sh -m`. The workflow can then pick up the zip
        # from there.
        if ! mv -f "${BOOTSTRAP_TMPDIR}/bootstrap-${1}.zip" "$TERMUX_PACKAGES_DIRECTORY/" 2>/dev/null; then
                local fallback_dir="${TERMUX_TOPDIR:-$HOME/.termux-build}"
                mkdir -p "$fallback_dir"
                mv -f "${BOOTSTRAP_TMPDIR}/bootstrap-${1}.zip" "$fallback_dir/"
                echo "[!] Could not write to '$TERMUX_PACKAGES_DIRECTORY/' (Permission denied)."
                echo "    Bootstrap zip placed at: $fallback_dir/bootstrap-${1}.zip"
                echo "    On GitHub Actions, the workflow will pick it up from there."
        fi

        echo "[*] Finished successfully (${1})."

}

set_build_bootstrap_traps() {

        #set traps for the build_bootstrap_trap itself
        trap 'build_bootstrap_trap' EXIT
        trap 'build_bootstrap_trap TERM' TERM
        trap 'build_bootstrap_trap INT' INT
        trap 'build_bootstrap_trap HUP' HUP
        trap 'build_bootstrap_trap QUIT' QUIT

        return 0

}

build_bootstrap_trap() {

        local build_bootstrap_trap_exit_code=$?
        trap - EXIT

        [ -h "$TERMUX_BUILT_PACKAGES_DIRECTORY" ] && rm -f "$TERMUX_BUILT_PACKAGES_DIRECTORY"
        [ -d "$BOOTSTRAP_TMPDIR" ] && rm -rf "$BOOTSTRAP_TMPDIR"

        [ -n "$1" ] && trap - "$1"; exit $build_bootstrap_trap_exit_code

}

show_usage() {

    cat <<'HELP_EOF'

build-bootstraps.sh is a script to build bootstrap archives for the
CodeIDE app (jo.codeide) from local package sources instead of debs
published in apt repo like done by generate-bootstrap.sh. It allows
bootstrap archives to be easily built for (forked) termux apps without
having to publish an apt repo first.


Usage:
  build-bootstraps.sh [command_options]


Available command_options:
  [ -h  | --help ]             Display this help screen
  [ -f ]                       Force build even if packages have already been built.
  [ --android10 ]              Generate bootstrap archives for Android 10+ for
                               apk packaging system.
  [ -a | --add <packages> ]    Additional packages to include into bootstrap archive.
                               Multiple packages should be passed as comma-separated list.
  [ --architectures <architectures> ]
                               Override default list of architectures for which bootstrap
                               archives will be created. Multiple architectures should be
                               passed as comma-separated list.
                               Default: 'aarch64' (CodeIDE v1 only supports aarch64).


Bootstrap package list:
  The list of packages included in the bootstrap is read from
  'bootstrap-packages.txt' at the repository root if it exists.
  If the file is missing, a hardcoded minimal list is used instead.
  Only direct top-level packages need to be listed — transitive
  dependencies are discovered and built automatically by
  build-package.sh via scripts/buildorder.py.


The package name/prefix that the bootstrap is built for is defined by
TERMUX_APP__PACKAGE_NAME in 'scripts/properties.sh'. It currently
defaults to 'jo.codeide' for CodeIDE.
If package name is changed, make sure to run
`./scripts/run-docker.sh ./clean.sh` or pass '-f' to force rebuild of packages.

### Examples

Build default bootstrap archive (aarch64 only):
./scripts/run-docker.sh ./scripts/build-bootstraps.sh &> build.log

Build bootstrap archive for an additional architecture (experimental):
./scripts/run-docker.sh ./scripts/build-bootstraps.sh --architectures arm &> build.log

Build bootstrap archive with additional openssh package for aarch64:
./scripts/run-docker.sh ./scripts/build-bootstraps.sh --add openssh &> build.log
HELP_EOF

echo $'\n'"TERMUX_APP__PACKAGE_NAME: \"$TERMUX_APP__PACKAGE_NAME\""
echo "TERMUX_APP_PACKAGE: \"$TERMUX_APP_PACKAGE\""
echo "TERMUX_PREFIX: \"${TERMUX_PREFIX[*]}\""
echo "TERMUX_ARCHITECTURES: \"${TERMUX_ARCHITECTURES[*]}\""
echo "BOOTSTRAP_PACKAGES_LIST_FILE: \"$BOOTSTRAP_PACKAGES_LIST_FILE\""

}

main() {

        local return_value

        while (($# > 0)); do
                case "$1" in
                        -h|--help)
                                show_usage
                                return 0
                                ;;
                        --android10)
                                BOOTSTRAP_ANDROID10_COMPATIBLE=true
                                ;;
                        -a|--add)
                                if [ $# -gt 1 ] && [ -n "$2" ] && [[ $2 != -* ]]; then
                                        for pkg in $(echo "$2" | tr ',' ' '); do
                                                ADDITIONAL_PACKAGES+=("$pkg")
                                        done
                                        unset pkg
                                        shift 1
                                else
                                        echo "[!] Option '--add' requires an argument." 1>&2
                                        show_usage
                                        return 1
                                fi
                                ;;
                        --architectures)
                                if [ $# -gt 1 ] && [ -n "$2" ] && [[ $2 != -* ]]; then
                                        TERMUX_ARCHITECTURES=()
                                        for arch in $(echo "$2" | tr ',' ' '); do
                                                TERMUX_ARCHITECTURES+=("$arch")
                                        done
                                        unset arch
                                        shift 1
                                else
                                        echo "[!] Option '--architectures' requires an argument." 1>&2
                                        show_usage
                                        return 1
                                fi
                                ;;
                        -f)
                                BUILD_PACKAGE_OPTIONS+=("-f")
                                FORCE_BUILD_PACKAGES=1
                                ;;
                        *)
                                echo "[!] Got unknown option '$1'" 1>&2
                                show_usage
                                return 1
                                ;;
                esac
                shift 1
        done

        set_build_bootstrap_traps

        for TERMUX_ARCH in "${TERMUX_ARCHITECTURES[@]}"; do
                if [[ " ${TERMUX_DEFAULT_ARCHITECTURES[*]} " != *" $TERMUX_ARCH "* ]]; then
                        echo "Unsupported architecture '$TERMUX_ARCH' for in architectures list: '${TERMUX_ARCHITECTURES[*]}'" 1>&2
                        echo "Supported architectures: '${TERMUX_DEFAULT_ARCHITECTURES[*]}'" 1>&2
                        return 1
                fi
        done

        for TERMUX_ARCH in "${TERMUX_ARCHITECTURES[@]}"; do
                termux_step_handle_buildarch

                if [[ $FORCE_BUILD_PACKAGES == "1" ]]; then
                        rm -f "$TERMUX_BUILT_PACKAGES_DIRECTORY_FOR_ARCH"/*
                        rm -f "$TERMUX_BUILT_DEBS_DIRECTORY"/*
                fi

                BOOTSTRAP_ROOTFS="$BOOTSTRAP_TMPDIR/rootfs-${TERMUX_ARCH}"
                BOOTSTRAP_PKGDIR="$BOOTSTRAP_TMPDIR/packages-${TERMUX_ARCH}"

                # Create initial directories for $TERMUX_PREFIX
                if ! ${BOOTSTRAP_ANDROID10_COMPATIBLE}; then
                        mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/etc/apt/apt.conf.d"
                        mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/etc/apt/preferences.d"
                        mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/info"
                        mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/triggers"
                        mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/updates"
                        mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/log/apt"
                        touch "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/available"
                        touch "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/status"
                fi
                mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/tmp"



                PACKAGES=()
                EXTRACTED_PACKAGES=()

                # ------------------------------------------------------------------
                # Build the package list for the minimal CodeIDE bootstrap.
                #
                # Strategy:
                #   1. If `bootstrap-packages.txt` exists at the repo root,
                #      parse it (one package per line, `#` comments allowed).
                #   2. Otherwise, fall back to a hardcoded minimal list.
                #
                # The list contains ONLY the direct top-level packages.
                # Transitive dependencies (dpkg, gpgv, libc++, libiconv,
                # libgnutls, libgcrypt, liblzma, liblz4, zstd, xxhash, zlib,
                # openssl, libandroid-support, libandroid-glob, pcre2,
                # readline, ncurses, libacl, libgmp, libmpfr, bzip2, xz-utils,
                # curl, dialog, termux-am, termux-am-socket, termux-licenses,
                # gawk, less, procps, psmisc, util-linux, etc.) are discovered
                # and built automatically by `build-package.sh` via
                # `scripts/buildorder.py`.
                # ------------------------------------------------------------------
                local bootstrap_list_file="$TERMUX_PACKAGES_DIRECTORY/$BOOTSTRAP_PACKAGES_LIST_FILE"
                if [[ -f "$bootstrap_list_file" ]]; then
                        echo "[*] Reading bootstrap package list from '$bootstrap_list_file'..."
                        while IFS= read -r line || [[ -n "$line" ]]; do
                                # Strip inline comments and surrounding whitespace.
                                line="${line%%#*}"
                                line="$(echo "$line" | xargs)"
                                [[ -z "$line" ]] && continue
                                PACKAGES+=("$line")
                        done < "$bootstrap_list_file"
                else
                        echo "[*] '$bootstrap_list_file' not found — using hardcoded minimal list."
                        # Package manager (essential).
                        if ! ${BOOTSTRAP_ANDROID10_COMPATIBLE}; then
                                PACKAGES+=("apt")
                        fi
                        # Shell.
                        PACKAGES+=("bash")
                        # POSIX core utilities.
                        PACKAGES+=("coreutils")
                        PACKAGES+=("dash")
                        PACKAGES+=("diffutils")
                        PACKAGES+=("findutils")
                        PACKAGES+=("grep")
                        PACKAGES+=("sed")
                        PACKAGES+=("tar")
                        PACKAGES+=("gzip")
                        PACKAGES+=("unzip")
                        # Compression library required by tar / apt / unzip.
                        PACKAGES+=("libbz2")
                        # CodeIDE/Termux runtime core.
                        PACKAGES+=("termux-core")
                        PACKAGES+=("termux-exec")
                        PACKAGES+=("termux-keyring")
                        PACKAGES+=("termux-tools")
                        # Android 10+ (apk packaging) requires proot to emulate
                        # the rootfs layout.
                        if ${BOOTSTRAP_ANDROID10_COMPATIBLE}; then
                                PACKAGES+=("proot")
                        fi
                fi

                # Echo the final list for traceability in CI logs.
                echo "[*] Bootstrap packages (${#PACKAGES[@]}):"
                for p in "${PACKAGES[@]}"; do echo "    - $p"; done

                # Handle additional packages.
                for add_pkg in "${ADDITIONAL_PACKAGES[@]}"; do
                        if [[ " ${PACKAGES[*]} " != *" $add_pkg "* ]]; then
                                PACKAGES+=("$add_pkg")
                        fi
                done
                unset add_pkg

                # Build packages.
                for package_name in "${PACKAGES[@]}"; do
                        set +e
                        build_package "$TERMUX_ARCH" "$package_name" || return $?
                        set -e
                done

                # Extract all debs.
                extract_debs "$TERMUX_ARCH" || return $?

                # ------------------------------------------------------------------
                # Global cleanup: replace any remaining /data/data/com.termux
                # runtime paths in the extracted rootfs.
                #
                # Despite the TERMUX_APP_PACKAGE=jo.codeide setting in
                # properties.sh, some files may still contain hardcoded
                # /data/data/com.termux paths. This happens when:
                #   - A package ships a config example or doc with a hardcoded
                #     path (e.g. termux.properties has a comment with
                #     /data/data/com.termux/files/home)
                #   - A generated script wasn't properly templated
                #
                # This step scans ALL text files in the bootstrap rootfs and
                # replaces /data/data/com.termux with /data/data/jo.codeide.
                # Binary files (.gz, .so, .a, .png, ELF) are excluded.
                # ------------------------------------------------------------------
                echo "[*] Scanning bootstrap rootfs for /data/data/com.termux leaks..."
                local _patched=0
                while IFS= read -r -d '' _f; do
                        if grep -q '/data/data/com\.termux' "$_f" 2>/dev/null; then
                                sed -i "s|/data/data/com\.termux|/data/data/$TERMUX_APP__PACKAGE_NAME|g" "$_f"
                                echo "[*]   patched: ${_f#$BOOTSTRAP_ROOTFS}"
                                _patched=$((_patched+1))
                        fi
                done < <(find "$BOOTSTRAP_ROOTFS" -type f -size -2M \
                        ! -name "*.gz" ! -name "*.zip" ! -name "*.xz" ! -name "*.bz2" \
                        ! -name "*.png" ! -name "*.jpg" ! -name "*.so" ! -name "*.a" \
                        ! -name "*.deb" ! -name "*.dex" ! -name "*.odex" \
                        -print0 2>/dev/null)
                echo "[*] Patched $_patched file(s) in bootstrap rootfs"
                unset _f _patched

                # Add termux bootstrap second stage files.
                # NOTE: $TERMUX_ARCH is the architecture we are currently
                # iterating on (set at the top of the for loop). The previous
                # code referenced `$package_arch` which is a local variable
                # inside extract_debs() and was always empty here, leaving
                # @TERMUX_PACKAGE_ARCH@ unsubstituted in the second stage
                # entry script.
                add_termux_bootstrap_second_stage_files "$TERMUX_ARCH"

                # Create bootstrap archive.
                create_bootstrap_archive "$TERMUX_ARCH" || return $?

        done

}

main "$@"
