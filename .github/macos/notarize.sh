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
#
# The key must be an App Store Connect *Team* key.  Apple states plainly that
# individual keys "aren't able to use Provisioning endpoints, access Sales and
# Finance, or notaryTool", so an individual key fails here no matter how its
# role is set.  The Developer role is enough; Admin is not required and should
# not be used.
#
# altool is not used and must not be reintroduced: Apple stopped accepting
# notarization through it on 2023-11-01.

set -euo pipefail

ZIP=${1:?usage: notarize.sh <submission.zip> <path-to-.app>}
APP=${2:?usage: notarize.sh <submission.zip> <path-to-.app>}

MAX_ATTEMPTS=3
WAIT_TIMEOUT=${SIMU_NOTARY_TIMEOUT:-30m}
# Overridable only so the retry path can be exercised in a test without three
# minutes of sleeping; the workflow leaves it at the default.
SIMU_NOTARY_BACKOFF=${SIMU_NOTARY_BACKOFF:-60}

# Exit codes, so the workflow can tell the two failure kinds apart.
EXIT_REJECTED=2   # Apple examined the artifact and said no.  Do not retry.
EXIT_TRANSIENT=3  # We never got a verdict.  Retrying is meaningful.

if [ ! -f "$ZIP" ]; then
	echo "::error::archive to notarize not found: $ZIP"
	exit 1
fi
if [ ! -d "$APP" ]; then
	echo "::error::bundle to staple not found: $APP"
	exit 1
fi

missing=0
for name in MACOS_NOTARY_API_KEY_P8 MACOS_NOTARY_API_KEY_ID MACOS_NOTARY_API_ISSUER_ID; do
	if [ -z "${!name:-}" ]; then
		echo "::error::required secret '$name' is empty or not set."
		missing=1
	fi
done
if [ "$missing" -ne 0 ]; then
	echo "::error::cannot contact the notary service without credentials."
	echo "::error::No package will be presented as notarized.  See .github/macos/README.md."
	exit 1
fi

umask 077
workdir=$(mktemp -d "${RUNNER_TEMP:-/tmp}/simu-notary.XXXXXX")
trap 'rm -rf "$workdir"' EXIT

KEY_FILE="$workdir/AuthKey.p8"
printf '%s' "$MACOS_NOTARY_API_KEY_P8" | openssl base64 -d -A > "$KEY_FILE" || {
	echo "::error::MACOS_NOTARY_API_KEY_P8 is not valid base64."
	echo "::error::Re-export it with:  base64 -i AuthKey_XXXXXXXX.p8 | pbcopy"
	exit 1
}
if [ ! -s "$KEY_FILE" ]; then
	echo "::error::MACOS_NOTARY_API_KEY_P8 decoded to an empty file."
	exit 1
fi
chmod 600 "$KEY_FILE"

# ---------------------------------------------------------------------------
# Remove anything from notary output that identifies this machine or the
# credentials.  The notary log itself carries no secret, but it is full of
# absolute build paths, and the key/issuer identifiers have no business in a
# public log.
# ---------------------------------------------------------------------------
redact() {
	sed \
		-e "s#${RUNNER_TEMP:-/nonexistent-runner-temp}#\$RUNNER_TEMP#g" \
		-e "s#${HOME:-/nonexistent-home}#\$HOME#g" \
		-e "s#/Users/runner#\$HOME#g" \
		-e "s#${MACOS_NOTARY_API_KEY_ID}#<key-id>#g" \
		-e "s#${MACOS_NOTARY_API_ISSUER_ID}#<issuer-id>#g"
}

# plutil reads JSON as well as plists and is always present on macOS, which
# avoids depending on a particular python or jq being installed.
json_get() {
	local key=$1 file=$2
	plutil -extract "$key" raw -o - "$file" 2>/dev/null || true
}

fetch_log() {
	local submission_id=$1
	local out="$workdir/notary-log.json"
	if xcrun notarytool log "$submission_id" \
			--key "$KEY_FILE" \
			--key-id "$MACOS_NOTARY_API_KEY_ID" \
			--issuer "$MACOS_NOTARY_API_ISSUER_ID" \
			"$out" >/dev/null 2>&1; then
		echo "----- notary log (redacted) -----"
		redact < "$out"
		echo "----- end notary log -----"
	else
		echo "::warning::could not fetch the notary log for submission $submission_id"
	fi
}

# ---------------------------------------------------------------------------
# Submit.
# ---------------------------------------------------------------------------
attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
	echo "== notarization attempt $attempt of $MAX_ATTEMPTS ==========="
	out="$workdir/submit-$attempt.json"
	rc=0
	xcrun notarytool submit "$ZIP" \
		--key "$KEY_FILE" \
		--key-id "$MACOS_NOTARY_API_KEY_ID" \
		--issuer "$MACOS_NOTARY_API_ISSUER_ID" \
		--wait \
		--timeout "$WAIT_TIMEOUT" \
		--output-format json > "$out" 2>"$workdir/submit-$attempt.err" || rc=$?

	status=$(json_get status "$out")
	submission_id=$(json_get id "$out")

	echo "notarytool exit code : $rc"
	echo "submission id        : ${submission_id:-<none>}"
	echo "status               : ${status:-<none>}"
	if [ -s "$workdir/submit-$attempt.err" ]; then
		echo "----- notarytool stderr (redacted) -----"
		redact < "$workdir/submit-$attempt.err"
		echo "----- end stderr -----"
	fi

	case "$status" in
		Accepted)
			echo "the notary service accepted submission $submission_id"
			# Apple asks that the log be read even on success, because it can
			# contain warnings worth fixing before the next submission.
			fetch_log "$submission_id"
			break
			;;

		Invalid|Rejected)
			echo "::error::the notary service rejected this artifact (status: $status)."
			echo "::error::This is a verdict about the artifact, not a transport problem,"
			echo "::error::so it will not be retried.  The log below says why."
			if [ -n "$submission_id" ]; then
				fetch_log "$submission_id"
			fi
			echo "::error::Fix the cause, rebuild, and start a new run."
			exit "$EXIT_REJECTED"
			;;

		*)
			# No verdict: a network failure, an expired wait, a service
			# outage, or a malformed response.  Nothing is known about the
			# artifact, so trying again is legitimate.
			echo "::warning::no verdict from the notary service on attempt $attempt (status: '${status:-none}', exit $rc)."
			if [ "$attempt" -eq "$MAX_ATTEMPTS" ]; then
				echo "::error::the notary service did not return a verdict after $MAX_ATTEMPTS attempts."
				echo "::error::Nothing is known about this artifact; it is NOT notarized."
				if [ -n "$submission_id" ]; then
					echo "::error::A submission may still be in progress under id $submission_id;"
					echo "::error::check it with 'xcrun notarytool info' before resubmitting."
				fi
				exit "$EXIT_TRANSIENT"
			fi
			backoff=$((attempt * SIMU_NOTARY_BACKOFF))
			echo "waiting ${backoff}s before retrying"
			sleep "$backoff"
			attempt=$((attempt + 1))
			continue
			;;
	esac
done

# ---------------------------------------------------------------------------
# Staple.
#
# The ticket is attached to the .app, not to the zip: Apple's documentation is
# explicit that zip archives cannot be stapled.  The distribution zip is built
# again afterwards, from the stapled bundle.
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
