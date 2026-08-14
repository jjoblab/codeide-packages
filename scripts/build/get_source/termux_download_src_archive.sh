termux_download_src_archive() {
	local PKG_SRCURL=(${TERMUX_PKG_SRCURL[@]})
	local PKG_SHA256=(${TERMUX_PKG_SHA256[@]})
	if  [ ! ${#PKG_SRCURL[@]} == ${#PKG_SHA256[@]} ] && [ ! ${#PKG_SHA256[@]} == 0 ]; then
		termux_error_exit "length of TERMUX_PKG_SRCURL isn't equal to length of TERMUX_PKG_SHA256."
	fi

	# Optional array `TERMUX_PKG_SRCURL_FALLBACKS` may be defined by packages
	# whose upstream is intermittently unavailable.
	#
	# - Single-URL packages (${#PKG_SRCURL[@]} == 1, the common case): EVERY
	#   element of TERMUX_PKG_SRCURL_FALLBACKS is tried, in order, as a
	#   fallback for that one URL. This matches termux_download()'s own
	#   variadic `[<FALLBACK_URL>...]` support (see termux_download.sh) —
	#   list as many mirrors as you want.
	# - Multi-URL packages (a single build.sh downloading several distinct
	#   source files, e.g. ncurses pulling in terminal-emulator patches):
	#   TERMUX_PKG_SRCURL_FALLBACKS stays parallel to TERMUX_PKG_SRCURL by
	#   index — element [i] is the (single) fallback for TERMUX_PKG_SRCURL[i].
	#   Empty elements mean "no fallback for this entry".
	# Use ${var+x} so this is safe under `set -u` when the array is unset.
	local -a PKG_SRCURL_FALLBACKS=()
	if [[ -n "${TERMUX_PKG_SRCURL_FALLBACKS+x}" ]] && [[ ${#TERMUX_PKG_SRCURL_FALLBACKS[@]} -gt 0 ]]; then
		PKG_SRCURL_FALLBACKS=("${TERMUX_PKG_SRCURL_FALLBACKS[@]}")
	fi

	for i in $(seq 0 $(( ${#PKG_SRCURL[@]}-1 ))); do
		local file="$TERMUX_PKG_CACHEDIR/$(basename "${PKG_SRCURL[$i]}")"
		local checksum="${PKG_SHA256[$i]:-}"

		local -a fallbacks=()
		if [ ${#PKG_SRCURL[@]} -eq 1 ]; then
			# Single source file: every configured fallback applies to it.
			fallbacks=("${PKG_SRCURL_FALLBACKS[@]}")
		elif [ -n "${PKG_SRCURL_FALLBACKS[$i]:-}" ]; then
			# Multiple source files: index-parallel, one fallback each.
			fallbacks=("${PKG_SRCURL_FALLBACKS[$i]}")
		fi

		# Build argument list for termux_download. Fallback URLs are appended
		# after the checksum so termux_download can try them in order if the
		# primary URL fails.
		local -a dl_args=("${PKG_SRCURL[$i]}" "$file")
		if [ -n "$checksum" ]; then
			dl_args+=("$checksum")
		elif [ ${#fallbacks[@]} -gt 0 ]; then
			# Need a placeholder checksum slot so the fallbacks are parsed
			# as URLs, not as the checksum.
			dl_args+=("SKIP_CHECKSUM")
		fi
		if [ ${#fallbacks[@]} -gt 0 ]; then
			dl_args+=("${fallbacks[@]}")
		fi

		termux_download "${dl_args[@]}"
	done
}
