#!/bin/bash
#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#
# Ask the Apple notary service what happened to submissions that were already
# made.  Query only: it submits nothing, signs nothing, and never touches the
# Developer ID.
#
# Usage: notary-status.sh <uuid> [<uuid> ...]
#
# Environment:
#   MACOS_NOTARY_API_KEY_P8      base64 of the App Store Connect API key
#   MACOS_NOTARY_API_KEY_ID      the key ID
#   MACOS_NOTARY_API_ISSUER_ID   the issuer UUID
#
# This exists because a `submit --wait` that times out has NOT told you the
# submission failed -- it has told you nothing, and the submission is still
# being processed under an id that was handed back on stderr.  Asking about
# that id is the correct next step.  Submitting the same archive again is not,
# and this script cannot do it even by accident: it has no submit path.
#
# Exit codes:
#   0  every submission was queried and returned a status the service defines
#   4  at least one query could not be answered (auth, transport, or a reply
#      that could not be understood).  A query that fails says nothing about
#      the submission.

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
. "$HERE/notary-lib.sh"

# --require-accepted turns the last verdict into the exit status, so a caller
# that must not continue on anything but Accepted does not have to grep for it.
REQUIRE_ACCEPTED=0
if [ "${1:-}" = "--require-accepted" ]; then
	REQUIRE_ACCEPTED=1
	shift
fi
EXIT_NOT_ACCEPTED=6

if [ "$#" -eq 0 ]; then
	echo "usage: notary-status.sh [--require-accepted] <uuid> [<uuid> ...]" >&2
	exit 64
fi

# ---------------------------------------------------------------------------
# Validate every argument before anything else happens.  These values reach a
# command line, so nothing that is not literally a UUID is allowed through.
# ---------------------------------------------------------------------------
for arg in "$@"; do
	if ! is_uuid "$arg"; then
		echo "::error::'$arg' is not a submission UUID."
		echo "::error::This script only accepts submission identifiers, and only in the"
		echo "::error::canonical 8-4-4-4-12 hexadecimal form."
		exit 64
	fi
done
if [ "$#" -gt 8 ]; then
	echo "::error::refusing to query more than 8 submissions in one run."
	exit 64
fi

workdir=$(mktemp -d "${RUNNER_TEMP:-/tmp}/simu-notary-query.XXXXXX")
# Removes the decrypted key on success, on failure, and when the job is
# cancelled -- INT and TERM are what a cancellation delivers.
# shellcheck disable=SC2329  # invoked by the trap below
cleanup() {
	rm -rf "$workdir"
}
trap cleanup EXIT INT TERM

KEY_FILE="$workdir/AuthKey.p8"
if ! notary_write_key "$KEY_FILE"; then
	exit 4
fi

echo "== notary submission status ================================"
echo "queried at : $(utc_now)"
echo "submissions: $#"
echo

query_failures=0
accepted=0
invalid=0
in_progress=0

for uuid in "$@"; do
	echo "------------------------------------------------------------"
	echo "submission : $uuid"
	when=$(utc_now)
	echo "queried at : $when"

	out="$workdir/info-$uuid.json"
	err="$workdir/info-$uuid.err"
	rc=0
	# stdout and stderr to separate files, deliberately.  Merging them is how
	# an error sentence ends up inside something that is then parsed as JSON.
	xcrun notarytool info "$uuid" \
		--key "$KEY_FILE" \
		--key-id "$MACOS_NOTARY_API_KEY_ID" \
		--issuer "$MACOS_NOTARY_API_ISSUER_ID" \
		--output-format json > "$out" 2> "$err" || rc=$?

	status=$(json_field "$out" status || true)

	if [ "$rc" -ne 0 ] || ! is_known_status "$status"; then
		# Work out what kind of "we do not know" this is.  None of them mean
		# the submission was rejected.
		kind="query error"
		if grep -qiE 'unauthor|authentication|invalid.*(key|issuer)|forbidden|401|403' "$err" 2>/dev/null; then
			kind="AUTHENTICATION error"
		elif grep -qiE 'timeout|timed out|network|connection|could not connect|temporarily' "$err" 2>/dev/null; then
			kind="TRANSPORT error"
		elif [ -s "$out" ] || [ -s "$err" ]; then
			kind="UNEXPECTED reply"
		fi
		echo "result     : $kind (notarytool exit $rc)"
		if [ -s "$err" ]; then
			echo "--- notarytool stderr (redacted) ---"
			redact_notary < "$err"
			echo "--- end stderr ---"
		fi
		if [ -s "$out" ]; then
			echo "--- notarytool stdout (redacted) ---"
			redact_notary < "$out"
			echo "--- end stdout ---"
		fi
		echo "::warning::could not determine the status of $uuid. This says nothing"
		echo "::warning::about the submission itself - it is not a rejection."
		query_failures=$((query_failures + 1))
		echo
		continue
	fi

	echo "status     : $status"
	case "$status" in
		Accepted)  accepted=$((accepted + 1)) ;;
		Invalid|Rejected) invalid=$((invalid + 1)) ;;
		"In Progress") in_progress=$((in_progress + 1)) ;;
	esac

	# Everything else the service chose to tell us.
	for field in name createdDate status statusSummary; do
		v=$(json_field "$out" "$field" || true)
		[ -n "$v" ] && printf '  %-14s %s\n' "$field" "$v"
	done

	# The log only exists once processing has finished.  Its absence while a
	# submission is still In Progress is expected and proves nothing.
	if is_terminal_status "$status"; then
		logfile="$workdir/log-$uuid.json"
		logerr="$workdir/log-$uuid.err"
		lrc=0
		xcrun notarytool log "$uuid" \
			--key "$KEY_FILE" \
			--key-id "$MACOS_NOTARY_API_KEY_ID" \
			--issuer "$MACOS_NOTARY_API_ISSUER_ID" \
			"$logfile" > /dev/null 2> "$logerr" || lrc=$?
		if [ "$lrc" -eq 0 ] && [ -s "$logfile" ]; then
			echo "--- notary log (redacted) ---"
			redact_notary < "$logfile"
			echo "--- end notary log ---"
		else
			echo "  log            not retrievable (notarytool exit $lrc)"
			[ -s "$logerr" ] && redact_notary < "$logerr"
		fi
	else
		echo "  log            not available yet; the submission has not finished."
		echo "                 That is not evidence of rejection."
	fi
	echo
done

echo "============================================================"
echo "Accepted      : $accepted"
echo "Invalid       : $invalid"
echo "In Progress   : $in_progress"
echo "Not determined: $query_failures"
echo "============================================================"

if [ "$query_failures" -gt 0 ]; then
	echo "::error::$query_failures submission(s) could not be queried."
	exit 4
fi

if [ "$REQUIRE_ACCEPTED" -eq 1 ] && [ "$accepted" -ne "$#" ]; then
	echo "::error::--require-accepted: $accepted of $# submission(s) are Accepted."
	echo "::error::Refusing to report success.  A submission that is still In Progress"
	echo "::error::has not been rejected, but it has not been accepted either, and"
	echo "::error::nothing may be stapled or described as notarized on that basis."
	exit "$EXIT_NOT_ACCEPTED"
fi
exit 0
