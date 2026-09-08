#!/bin/bash
#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#
# Check that a submission-binding record really belongs to the archive that
# was just restored, and to the submission the operator asked about.
#
# Usage: verify-binding.sh <binding-dir> <restored.zip>
#
# Required environment:
#   MACOS_ARTIFACT_KEY        passphrase the record was made with
#   EXPECT_RUN_ID             run the archive came from
#   EXPECT_SUBMISSION_ID      submission the operator is finishing
#
# Three things have to agree, and none of them is taken from the record alone:
#
#   * the record is authentic - it decrypts under the key, so whoever wrote it
#     had the key and it has not been altered;
#   * it names the archive that was actually restored, by hash;
#   * the submission it names is the one the operator asked about, which the
#     operator knows independently.
#
# A missing record is not a small problem: without it the archive cannot be
# tied to any verdict, and the correct response is to stop, not to guess.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
. "$HERE/artifact-lib.sh"
# shellcheck source=/dev/null
. "$HERE/notary-lib.sh"

DIR=${1:?usage: verify-binding.sh <binding-dir> <restored.zip>}
ZIP=${2:?usage: verify-binding.sh <binding-dir> <restored.zip>}

fail() { echo "::error::$1"; exit 1; }

record="$DIR/submission.gpg"
[ -f "$record" ] || fail "no submission binding in $DIR. The archive cannot be tied to a notarization result, so there is nothing to finish."
[ -f "$ZIP" ] || fail "restored archive not found: $ZIP"
artifact_key_present || fail "MACOS_ARTIFACT_KEY is not set."
for v in EXPECT_RUN_ID EXPECT_SUBMISSION_ID; do
	[ -n "${!v:-}" ] || fail "$v must be provided; a record cannot be trusted to describe itself."
done

work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/simu-binding.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

echo "== verifying the submission binding ========================"

artifact_decrypt "$record" "$work/binding.json" \
	|| fail "the binding record could not be authenticated. Wrong key, or it has been altered or substituted."
echo "authenticated: AES-256 OCB tag verified"

schema=$(json_field "$work/binding.json" schema || true)
kind=$(json_field "$work/binding.json" record || true)
[ "$schema" = "$ARTIFACT_CONTAINER_SCHEMA" ] || fail "unrecognised binding schema '${schema:-<none>}'."
[ "$kind" = "submission-binding" ] || fail "this is not a submission binding record."

bound_sha=$(json_field "$work/binding.json" zip_sha256 || true)
bound_run=$(json_field "$work/binding.json" source_run_id || true)
bound_uuid=$(json_field "$work/binding.json" submission_id || true)

printf '  %-18s %s\n' "payload sha256" "${bound_sha:-<none>}"
printf '  %-18s %s\n' "source run" "${bound_run:-<none>}"
printf '  %-18s %s\n' "submission" "${bound_uuid:-<none>}"

is_uuid "$bound_uuid" || fail "the record names no valid submission id."

actual_sha=$(shasum -a 256 "$ZIP" | awk '{ print $1 }')
[ "$bound_sha" = "$actual_sha" ] \
	|| fail "this record belongs to a different archive: it names $bound_sha, the restored archive is $actual_sha."
[ "$bound_run" = "$EXPECT_RUN_ID" ] \
	|| fail "this record came from run $bound_run, not from run $EXPECT_RUN_ID."
[ "$bound_uuid" = "$EXPECT_SUBMISSION_ID" ] \
	|| fail "this archive is bound to submission $bound_uuid, not to $EXPECT_SUBMISSION_ID. Stapling a ticket from another submission would produce a package nobody can account for."

echo "binding accepted: archive, run and submission all agree"
