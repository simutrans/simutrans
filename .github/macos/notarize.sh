#!/bin/bash
#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#
# Submit a signed archive to the Apple notary service, wait for the verdict,
# and staple the resulting ticket to the application bundle.
#
# Usage: notarize.sh <submission.zip> <path-to-.app>
#
# Environment:
#   MACOS_NOTARY_API_KEY_P8      base64 of the App Store Connect API key (.p8)
#   MACOS_NOTARY_API_KEY_ID      the key ID
#   MACOS_NOTARY_API_ISSUER_ID   the issuer UUID
#   SIMU_NOTARY_BUDGET           total seconds to wait for a verdict (default 2700)
#
# The key must be an App Store Connect *Team* key.  Apple states plainly that
# individual keys "aren't able to use Provisioning endpoints, access Sales and
# Finance, or notaryTool", so an individual key fails here no matter how its
# role is set.  The Developer role is enough; Admin is not required.
#
# altool is not used and must not be reintroduced: Apple stopped accepting
# notarization through it on 2023-11-01.
#
#
# Submitting and waiting are two operations, not one
# --------------------------------------------------
# An earlier version used `submit --wait` and treated the wait expiring as a
# transport failure, which meant it submitted the same archive again.  On
# 2026-09-08 that produced three submissions for one artifact, none of which
# was ever asked about:
#
#   54975800-79ad-44c9-b81d-f56022379415
#   44199d3a-016b-4886-91c8-0791c5190665
#   1e012e38-8a35-4db4-9906-fc715aaad6ff
#
# A wait that expires says nothing about the submission; the submission is
# still being processed, under an id the tool had already returned.  So this
# submits once, records the id immediately, and then polls that same id.  Once
# an id exists there is no path in this script that submits again.
#
# Exit codes:
#   0  Accepted, ticket stapled
#   2  Apple examined the artifact and rejected it.  Do not resubmit as-is.
#   3  Could not submit, or submitted with no usable id: state UNCERTAIN.
#   5  Submitted and still In Progress when the waiting budget ran out.
#      The id is known and can be queried later with notary-status.sh.

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
. "$HERE/notary-lib.sh"

ZIP=${1:?usage: notarize.sh <submission.zip> <path-to-.app>}
APP=${2:?usage: notarize.sh <submission.zip> <path-to-.app>}

# Total time to wait for a verdict.  Deliberately smaller than the job's own
# timeout so that running out leaves room to report the id, print diagnostics
# and clean up rather than being killed mid-sentence.
BUDGET=${SIMU_NOTARY_BUDGET:-2700}
POLL_MIN=${SIMU_NOTARY_POLL_MIN:-30}
POLL_MAX=${SIMU_NOTARY_POLL_MAX:-120}

EXIT_REJECTED=2
EXIT_UNCERTAIN=3
EXIT_PENDING=5

if [ ! -f "$ZIP" ]; then
	echo "::error::archive to notarize not found: $ZIP"
	exit 1
fi
if [ ! -d "$APP" ]; then
	echo "::error::bundle to staple not found: $APP"
	exit 1
fi

workdir=$(mktemp -d "${RUNNER_TEMP:-/tmp}/simu-notary.XXXXXX")
trap 'rm -rf "$workdir"' EXIT INT TERM

KEY_FILE="$workdir/AuthKey.p8"
if ! notary_write_key "$KEY_FILE"; then
	echo "::error::No package will be presented as notarized.  See .github/macos/README.md."
	exit "$EXIT_UNCERTAIN"
fi

# ---------------------------------------------------------------------------
# Identify exactly what is being sent, before sending it.
#
# The previous run did not record this, so afterwards there was no way to say
# which bytes had gone to Apple.  The archive is rebuilt after stapling, so
# the submitted zip is not the same file as the one that ships.
# ---------------------------------------------------------------------------
zip_sha=$(shasum -a 256 "$ZIP" | awk '{ print $1 }')
zip_size=$(wc -c < "$ZIP" | tr -d ' ')
echo "== submitting =============================================="
echo "archive        : $(basename "$ZIP")"
echo "size           : $zip_size bytes"
echo "sha256         : $zip_sha"
echo "submitted at   : $(utc_now)"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		echo "submitted_zip_sha256=$zip_sha"
		echo "submitted_zip_bytes=$zip_size"
	} >> "$GITHUB_OUTPUT"
fi
echo

# ---------------------------------------------------------------------------
# A. Submit once, and get an id.
#
# No --wait: the id is the thing that matters, and it should be in hand and
# recorded before any long wait begins.
# ---------------------------------------------------------------------------
sub_out="$workdir/submit.json"
sub_err="$workdir/submit.err"
sub_rc=0
xcrun notarytool submit "$ZIP" \
	--key "$KEY_FILE" \
	--key-id "$MACOS_NOTARY_API_KEY_ID" \
	--issuer "$MACOS_NOTARY_API_ISSUER_ID" \
	--output-format json > "$sub_out" 2> "$sub_err" || sub_rc=$?

submission_id=$(extract_submission_id "$sub_out" "$sub_err" || true)

echo "notarytool exit code : $sub_rc"
if [ -s "$sub_err" ]; then
	echo "----- notarytool stderr (redacted) -----"
	redact_notary < "$sub_err"
	echo "----- end stderr -----"
fi

if ! is_uuid "$submission_id"; then
	# No id.  Apple may or may not have received the archive, and there is no
	# way to tell from here, so this is uncertain rather than failed - and
	# resubmitting blind is exactly what created three submissions last time.
	echo "::error::no submission id was returned."
	echo "::error::Whether the notary service received this archive is UNKNOWN."
	echo "::error::It is NOT notarized, and this script will not submit it again"
	echo "::error::automatically: a blind resubmission is how one artifact ends up"
	echo "::error::queued several times."
	echo "::error::Check for a recent submission with 'xcrun notarytool history'"
	echo "::error::before deciding to submit again."
	exit "$EXIT_UNCERTAIN"
fi

echo
echo "::notice::submission id: $submission_id"
echo "submission id  : $submission_id"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		echo "submission_id=$submission_id"
		echo "submitted_at=$(utc_now)"
	} >> "$GITHUB_OUTPUT"
fi
echo

# ---------------------------------------------------------------------------
# B. Wait for THAT id.  Nothing below this line submits anything.
# ---------------------------------------------------------------------------
echo "== waiting for a verdict (budget ${BUDGET}s) ==============="
started=$(date -u +%s)
interval=$POLL_MIN
consecutive_query_errors=0
status=""

while :; do
	now=$(date -u +%s)
	elapsed=$((now - started))
	if [ "$elapsed" -ge "$BUDGET" ]; then
		echo
		echo "::error::still not finished after ${elapsed}s of waiting."
		echo "::error::Submission $submission_id is IN PROGRESS as far as we know."
		echo "::error::Nothing was rejected; the artifact is simply NOT notarized yet,"
		echo "::error::and it must not be described as notarized."
		echo "::error::Ask again later without resubmitting:"
		echo "::error::  Actions -> macOS notary submission status -> $submission_id"
		exit "$EXIT_PENDING"
	fi

	info_out="$workdir/info.json"
	info_err="$workdir/info.err"
	info_rc=0
	xcrun notarytool info "$submission_id" \
		--key "$KEY_FILE" \
		--key-id "$MACOS_NOTARY_API_KEY_ID" \
		--issuer "$MACOS_NOTARY_API_ISSUER_ID" \
		--output-format json > "$info_out" 2> "$info_err" || info_rc=$?

	status=$(json_field "$info_out" status || true)

	if [ "$info_rc" -ne 0 ] || ! is_known_status "$status"; then
		consecutive_query_errors=$((consecutive_query_errors + 1))
		echo "[$(utc_now)] query did not return a usable status (exit $info_rc), attempt $consecutive_query_errors"
		if [ -s "$info_err" ]; then
			redact_notary < "$info_err" | sed 's/^/    /'
		fi
		if [ "$consecutive_query_errors" -ge 10 ]; then
			echo "::error::10 consecutive queries failed for $submission_id."
			echo "::error::The submission itself is UNKNOWN, not rejected, and it was NOT"
			echo "::error::resubmitted.  Query it later with the notary status workflow."
			exit "$EXIT_PENDING"
		fi
		sleep "$interval"
		continue
	fi
	consecutive_query_errors=0

	echo "[$(utc_now)] status: $status (${elapsed}s elapsed)"

	case "$status" in
		Accepted)
			break
			;;
		Invalid|Rejected)
			echo
			echo "::error::the notary service rejected this artifact (status: $status)."
			echo "::error::This is a verdict about the artifact, not a transport problem."
			logfile="$workdir/notary-log.json"
			if xcrun notarytool log "$submission_id" \
					--key "$KEY_FILE" \
					--key-id "$MACOS_NOTARY_API_KEY_ID" \
					--issuer "$MACOS_NOTARY_API_ISSUER_ID" \
					"$logfile" >/dev/null 2>&1 && [ -s "$logfile" ]; then
				echo "----- notary log (redacted) -----"
				redact_notary < "$logfile"
				echo "----- end notary log -----"
			else
				echo "::warning::could not fetch the notary log for $submission_id"
			fi
			echo "::error::Fix the cause, rebuild, and start a new run."
			exit "$EXIT_REJECTED"
			;;
		*)
			# In Progress.  Back off gently so a long queue does not turn into
			# a tight polling loop.
			sleep "$interval"
			if [ "$interval" -lt "$POLL_MAX" ]; then
				interval=$((interval * 2))
				[ "$interval" -gt "$POLL_MAX" ] && interval=$POLL_MAX
			fi
			;;
	esac
done

echo
echo "the notary service accepted submission $submission_id"

# Apple asks that the log be read even on success: it can carry warnings worth
# fixing before the next submission.
logfile="$workdir/notary-log.json"
if xcrun notarytool log "$submission_id" \
		--key "$KEY_FILE" \
		--key-id "$MACOS_NOTARY_API_KEY_ID" \
		--issuer "$MACOS_NOTARY_API_ISSUER_ID" \
		"$logfile" >/dev/null 2>&1 && [ -s "$logfile" ]; then
	echo "----- notary log (redacted) -----"
	redact_notary < "$logfile"
	echo "----- end notary log -----"
else
	echo "::warning::could not fetch the notary log for $submission_id"
fi

# ---------------------------------------------------------------------------
# Staple.
#
# The ticket is attached to the .app, not to the zip: Apple's documentation is
# explicit that zip archives cannot be stapled.  The distribution archive is
# built again afterwards, from the stapled bundle.
# ---------------------------------------------------------------------------
echo
echo "== stapling ================================================"
if ! xcrun stapler staple "$APP"; then
	echo "::error::the notarization ticket could not be stapled to $APP."
	echo "::error::The artifact would then need an online Gatekeeper check on"
	echo "::error::first launch, so it is not shipped in this state."
	exit 1
fi

echo "--- stapler validate"
xcrun stapler validate "$APP"

echo
echo "notarized and stapled: $APP"
