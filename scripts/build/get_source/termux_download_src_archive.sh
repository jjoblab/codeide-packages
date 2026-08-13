termux_download_src_archive() {
	local PKG_SRCURL=(${TERMUX_PKG_SRCURL[@]})
	local PKG_SHA256=(${TERMUX_PKG_SHA256[@]})
	if  [ ! ${#PKG_SRCURL[@]} == ${#PKG_SHA256[@]} ] && [ ! ${#PKG_SHA256[@]} == 0 ]; then
		termux_error_exit "length of TERMUX_PKG_SRCURL isn't equal to length of TERMUX_PKG_SHA256."
	fi

	# Optional parallel array `TERMUX_PKG_SRCURL_FALLBACKS` may be defined by
	# packages whose upstream is intermittently unavailable. Each non-empty
	# element is used as a fallback URL for the corresponding entry in
	# TERMUX_PKG_SRCURL (same index). Empty elements mean "no fallback".
	# Use ${var+x} so this is safe under `set -u` when the array is unset.
	local -a PKG_SRCURL_FALLBACKS=()
	if [[ -n "${TERMUX_PKG_SRCURL_FALLBACKS+x}" ]] && [[ ${#TERMUX_PKG_SRCURL_FALLBACKS[@]} -gt 0 ]]; then
		PKG_SRCURL_FALLBACKS=("${TERMUX_PKG_SRCURL_FALLBACKS[@]}")
	fi

	for i in $(seq 0 $(( ${#PKG_SRCURL[@]}-1 ))); do
		local file="$TERMUX_PKG_CACHEDIR/$(basename "${PKG_SRCURL[$i]}")"
		local checksum="${PKG_SHA256[$i]:-}"
		local fallback="${PKG_SRCURL_FALLBACKS[$i]:-}"

		# Build argument list for termux_download. Fallback URLs are appended
		# after the checksum so termux_download can try them in order if the
		# primary URL fails.
		local -a dl_args=("${PKG_SRCURL[$i]}" "$file")
		if [ -n "$checksum" ]; then
			dl_args+=("$checksum")
		elif [ -n "$fallback" ]; then
			# Need a placeholder checksum slot so the fallback is parsed as
			# a URL, not as the checksum.
			dl_args+=("SKIP_CHECKSUM")
		fi
		if [ -n "$fallback" ]; then
			dl_args+=("$fallback")
		fi

		termux_download "${dl_args[@]}"
	done
}
