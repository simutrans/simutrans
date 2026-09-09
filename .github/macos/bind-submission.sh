#!/bin/bash
#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#
# Tie a submission id to the exact archive it was made from.
#
# Usage: bind-submission.sh <preserved-dir> <uuid> <output-dir>
#
# Why this is a separate record
# -----------------------------
# A workflow artifact cannot be edited once it has been uploaded, and the
# archive has to be uploaded BEFORE the submission so that a runner dying
# immediately afterwards still leaves the signed bytes behind.  The id only
# exists after that, so it is written as its own small record.
#
# That record is encrypted with the same key, which authenticates it: a
# separate file sitting next to a container proves nothing on its own.  It
# names the payload by hash and the run it came from, so it cannot be lifted
# onto a different package.
#
# If a submission was made and no id came back, nothing is bound.  The archive
# stays recoverable, but it is UNRECONCILED: it cannot be resumed, and it must
# not be resubmitted on the assumption that the first attempt failed, because
# Apple may well have received it.  Reconciling means finding the id with
# `notarytool history` and binding it deliberately.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
. "$HERE/artifact-lib.sh"
# shellcheck source=/dev/null
. "$HERE/notary-lib.sh"

DIR=${1:?usage: bind-submission.sh <preserved-dir> <uuid> <output-dir>}
UUID=${2:?usage: bind-submission.sh <preserved-dir> <uuid> <output-dir>}
OUT=${3:?usage: bind-submission.sh <preserved-dir> <uuid> <output-dir>}

if ! is_uuid "$UUID"; then
	echo "::error::'$UUID' is not a submission UUID; refusing to bind it."
	echo "::error::A record bound to something that is not a submission id could never"
	echo "::error::be resumed, and would hide the fact that the id was lost."
	exit 1
fi
artifact_key_present || { echo "::error::MACOS_ARTIFACT_KEY is not set."; exit 1; }

container="$DIR/bundle.gpg"
[ -f "$container" ] || { echo "::error::no container in $DIR."; exit 1; }

umask 077
work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/simu-bind.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

# Read the payload hash out of the authenticated container rather than from
# anything lying beside it.
artifact_decrypt "$container" "$work/container.tar" \
	|| { echo "::error::the container could not be authenticated; refusing to bind."; exit 1; }
mkdir -p "$work/in"
tar -C "$work/in" -xf "$work/container.tar" manifest.json
zip_sha=$(json_field "$work/in/manifest.json" zip_sha256 || true)
run_id=$(json_field "$work/in/manifest.json" run_id || true)
grep -qE '^[0-9a-f]{64}$' <<<"$zip_sha" \
	|| { echo "::error::the container manifest has no usable zip_sha256."; exit 1; }

mkdir -p "$OUT"
cat > "$work/binding.json" <<BINDING
{
  "schema": "$ARTIFACT_CONTAINER_SCHEMA",
  "record": "submission-binding",
  "bound_utc": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "zip_sha256": "$zip_sha",
  "source_run_id": "$run_id",
  "repository": "${GITHUB_REPOSITORY:-}",
  "binding_run_id": "${GITHUB_RUN_ID:-}",
  "submission_id": "$UUID",
  "notarization_status": "submitted, awaiting verdict"
}
BINDING

artifact_encrypt "$work/binding.json" "$OUT/submission.gpg"

echo "== submission bound to the preserved archive ==============="
cat "$work/binding.json"
echo
echo "submission $UUID tied to the archive with sha256 $zip_sha"
echo "written to $OUT/submission.gpg (authenticated)"
