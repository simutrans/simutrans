#!/bin/bash
#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#
# Shared helpers for talking to the Apple notary service.
#
# Meant to be sourced, not executed.
#
# The reason this exists as its own file is a defect that reached a real run.
# When `notarytool submit --wait` hits its timeout it exits 124 and writes its
# JSON -- including the submission id -- to *stderr*, leaving stdout empty.
# The caller parsed stdout, `plutil` failed, and `plutil` printed its complaint
# on *stdout*, so the error text was picked up as if it were the value:
#
#   submission id : /Users/runner/.../submit-1.json: Property List error: ...
#
# The submission id was in stderr the whole time.  The consequences were a
# useless diagnostic exactly when it was needed, and a resubmission instead of
# a query.
#
# So: every field is validated against the shape it is supposed to have before
# it is allowed to be a value, stdout and stderr are read separately and never
# concatenated to make JSON, and a parser error can never become a UUID or a
# status.

# Statuses the notary service is documented to return.  Anything else is
# "unknown", never silently accepted.
NOTARY_TERMINAL_STATUSES='Accepted Invalid Rejected'

# ---------------------------------------------------------------------------
# json_field <file> <key>
#
# Prints the value on stdout and returns 0 only when the file parses and the
# key exists.  Returns 1 otherwise, printing nothing: a failure must never
# produce output that a caller could mistake for a value.
# ---------------------------------------------------------------------------
json_field() {
	local file=$1 key=$2 out rc
	[ -s "$file" ] || return 1
	# plutil writes some of its own errors to stdout, so its exit status is
	# the only thing worth believing here.
	out=$(plutil -extract "$key" raw -o - -- "$file" 2>/dev/null)
	rc=$?
	[ "$rc" -eq 0 ] || return 1
	[ -n "$out" ] || return 1
	printf '%s' "$out"
	return 0
}

# ---------------------------------------------------------------------------
# is_uuid <string>
#
# The notary service returns lower-case hyphenated UUIDs.  Nothing that is not
# one is allowed to be treated as a submission id -- which is what stops a
# parser error, a file path or an error sentence from being carried forward as
# though it identified a submission.
# ---------------------------------------------------------------------------
is_uuid() {
	printf '%s' "${1:-}" | grep -qE '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
}

# ---------------------------------------------------------------------------
# is_known_status <string>
# ---------------------------------------------------------------------------
is_known_status() {
	local s=${1:-} k
	for k in $NOTARY_TERMINAL_STATUSES; do
		[ "$s" = "$k" ] && return 0
	done
	[ "$s" = "In Progress" ] && return 0
	return 1
}

is_terminal_status() {
	local s=${1:-} k
	for k in $NOTARY_TERMINAL_STATUSES; do
		[ "$s" = "$k" ] && return 0
	done
	return 1
}

# ---------------------------------------------------------------------------
# extract_submission_id <stdout-file> <stderr-file>
#
# Looks for a submission id in stdout first and then in stderr, validating
# each candidate as a UUID before accepting it.  The two files are read
# separately on purpose: concatenating them to "make the JSON parse" is how
# an error message ends up being treated as data.
#
# stderr is not necessarily JSON, so it is also scanned textually -- but only
# for something that is literally shaped like a UUID.
# ---------------------------------------------------------------------------
extract_submission_id() {
	local out_file=$1 err_file=$2 candidate

	candidate=$(json_field "$out_file" id || true)
	if is_uuid "$candidate"; then
		printf '%s' "$candidate"
		return 0
	fi

	# `notarytool submit --wait` prints {"message":"Timeout ...","id":"..."}
	# on stderr when the wait expires.  That id is a real submission that is
	# still being processed, and losing it is what caused the resubmissions.
	candidate=$(json_field "$err_file" id || true)
	if is_uuid "$candidate"; then
		printf '%s' "$candidate"
		return 0
	fi

	candidate=$(grep -oE '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' "$err_file" 2>/dev/null | head -1)
	if is_uuid "$candidate"; then
		printf '%s' "$candidate"
		return 0
	fi

	return 1
}

# ---------------------------------------------------------------------------
# redact_notary <<< text
#
# Removes machine paths and the credential identifiers from anything that is
# going to be printed.  The notary log holds no secret, but it is full of
# absolute build paths and there is no reason to publish the key or issuer id.
# ---------------------------------------------------------------------------
redact_notary() {
	sed \
		-e "s#${RUNNER_TEMP:-/nonexistent-runner-temp}#\$RUNNER_TEMP#g" \
		-e "s#${HOME:-/nonexistent-home}#\$HOME#g" \
		-e "s#/Users/runner#\$HOME#g" \
		-e "s#${MACOS_NOTARY_API_KEY_ID:-__no_key_id__}#<key-id>#g" \
		-e "s#${MACOS_NOTARY_API_ISSUER_ID:-__no_issuer__}#<issuer-id>#g"
}

# ---------------------------------------------------------------------------
# notary_write_key <destination>
#
# Materialises the App Store Connect key from its base64 secret with a
# restrictive umask.  The caller owns the trap that removes it.
# ---------------------------------------------------------------------------
notary_write_key() {
	local dest=$1
	local missing=0 name
	for name in MACOS_NOTARY_API_KEY_P8 MACOS_NOTARY_API_KEY_ID MACOS_NOTARY_API_ISSUER_ID; do
		if [ -z "${!name:-}" ]; then
			echo "::error::required secret '$name' is empty or not set."
			missing=1
		fi
	done
	if [ "$missing" -ne 0 ]; then
		echo "::error::cannot contact the notary service without credentials."
		return 1
	fi

	umask 077
	if ! printf '%s' "$MACOS_NOTARY_API_KEY_P8" | openssl base64 -d -A > "$dest"; then
		echo "::error::MACOS_NOTARY_API_KEY_P8 is not valid base64."
		return 1
	fi
	if [ ! -s "$dest" ]; then
		echo "::error::MACOS_NOTARY_API_KEY_P8 decoded to an empty file."
		return 1
	fi
	chmod 600 "$dest"
	return 0
}

# ---------------------------------------------------------------------------
# utc_now
# ---------------------------------------------------------------------------
utc_now() {
	date -u '+%Y-%m-%dT%H:%M:%SZ'
}
