#!/usr/bin/bash

# termux_download <URL> <DESTINATION> [<CHECKSUM>] [<FALLBACK_URL>...]
#
# Downloads a file from <URL> to <DESTINATION>. If <CHECKSUM> is provided,
# the downloaded file is verified against it (SHA-256).
#
# Any additional arguments after <CHECKSUM> are treated as fallback URLs that
# will be tried in order if the primary URL (and its built-in retries) fails.
# This is useful for upstreams that are intermittently unavailable (e.g.
# dist.schmorp.de occasionally returns 404 for files that are normally
# present in both `Attic/` and the top-level directory).
termux_download() {
	if [[ $# -lt 2 ]]; then
		echo "termux_download(): Invalid arguments - expected <URL> <DESTINATION> [<CHECKSUM>] [<FALLBACK_URL>...]" 1>&2
		return 1
	fi
	local URL="$1"
	local DESTINATION="$2"
	local CHECKSUM="${3:-SKIP_CHECKSUM}"
	shift 3 2>/dev/null || shift $#
	local -a FALLBACK_URLS=("$@")

	if [[ "$URL" =~ ^file://(/[^/]+)+$ ]]; then
		local source="${URL:7}" # Remove `file://` prefix

		if [ -d "$source" ]; then
			# Create tar file from local directory
			echo "Downloading local source directory at '$source'"
			rm -f "$DESTINATION"
			(cd "$(dirname "$source")" && tar -cf "$DESTINATION" --exclude=".git" "$(basename "$source")")
			return 0
		elif [ ! -f "$source" ]; then
			echo "No local source file found at path of URL '$URL'"
			return 1
		else
			ln -sf "$source" "$DESTINATION"
			return 0
		fi
	fi

	if [ -f "$DESTINATION" ] && [ "$CHECKSUM" != "SKIP_CHECKSUM" ]; then
		# Keep existing file if checksum matches.
		local EXISTING_CHECKSUM
		EXISTING_CHECKSUM=$(sha256sum "$DESTINATION" | cut -d' ' -f1)
		[[ "$EXISTING_CHECKSUM" == "$CHECKSUM" ]] && return
	fi

	local TMPFILE
	local -a CURL_OPTIONS=(
		--fail               # Consider 4xx and 5xx responses as failures
		--retry 5            # Retry up to 5 times on transient failures
		--retry-connrefused  # Also retry on refused connections
		--retry-delay 5      # Wait 5 seconds between retries
		--connect-timeout 30 # Wait at most 30 seconds for a connection to be established
		--retry-max-time 120 # Stop retrying if it's still failing after 120 seconds
		--speed-limit 1000   # Expect at least 1000 Bytes per second
		--speed-time 60      # Fail if the minimum speed isn't met for at least 60 seconds
		--location           # Follow redirects
		--user-agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
	)
	TMPFILE=$(mktemp "$TERMUX_PKG_TMPDIR/download.${TERMUX_PKG_NAME-unnamed}.XXXXXXXXX")
	if [[ "${TERMUX_QUIET_BUILD-}" == "true" ]]; then
		CURL_OPTIONS+=(--no-progress-meter) # Don't print out transfer statistics
	fi

	# Internal helper: try to download a single URL with the existing retry policy.
	# Sets $_termux_download_ok to 1 on success, 0 on failure.
	_termux_download_one() {
		local url="$1"
		echo "Downloading ${url}"
		if curl "${CURL_OPTIONS[@]}" --output "$TMPFILE" "$url"; then
			_termux_download_ok=1
			return 0
		fi
		local error=1
		local retry=2
		local delay=60
		local try
		for (( try=1; try <= retry; try++ )); do
			echo "Retrying #${try} download ${url} in ${delay}"
			sleep "${delay}"
			if curl "${CURL_OPTIONS[@]}" --output "$TMPFILE" "$url"; then
				error=0
				break
			fi
		done
		if [[ "${error}" != 0 ]]; then
			echo "Failed to download ${url}" 1>&2
			_termux_download_ok=0
			return 1
		fi
		_termux_download_ok=1
		return 0
	}

	local -a ALL_URLS=("$URL" "${FALLBACK_URLS[@]}")
	local current_url
	local downloaded=0
	local last_url="${ALL_URLS[${#ALL_URLS[@]}-1]}"
	for current_url in "${ALL_URLS[@]}"; do
		if _termux_download_one "$current_url"; then
			downloaded=1
			break
		elif [[ "$current_url" != "$last_url" ]]; then
			echo "Trying fallback URL for ${URL}..." 1>&2
		fi
	done

	if [[ "$downloaded" != 1 ]]; then
		echo "Failed to download ${URL}" 1>&2
		if [[ ${#FALLBACK_URLS[@]} -gt 0 ]]; then
			echo "Also tried ${#FALLBACK_URLS[@]} fallback URL(s):" 1>&2
			local fb
			for fb in "${FALLBACK_URLS[@]}"; do
				echo "  - ${fb}" 1>&2
			done
		fi
		return 1
	fi

	local ACTUAL_CHECKSUM
	ACTUAL_CHECKSUM=$(sha256sum "$TMPFILE" | cut -d' ' -f1)
	if [[ -z "$CHECKSUM" ]]; then
		printf "WARNING: No checksum check for %s:\nActual: %s\n" \
			"$URL" "$ACTUAL_CHECKSUM"
	elif [[ "$CHECKSUM" == "SKIP_CHECKSUM" ]]; then
		:
	elif [[ "$CHECKSUM" != "$ACTUAL_CHECKSUM" ]]; then
		printf "Wrong checksum for %s\nExpected: %s\nActual:   %s\n" \
			"$URL" "$CHECKSUM" "$ACTUAL_CHECKSUM" 1>&2
		return 1
	fi
	mv "$TMPFILE" "$DESTINATION"
	return 0
}

# Make script standalone executable as well as sourceable
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	termux_download "$@"
fi
