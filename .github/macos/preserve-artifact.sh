#!/bin/bash
#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#
# Preserve the exact archive that is about to be sent to the notary service,
# so that a verdict arriving after the runner is gone can still be used.
#
# Usage: preserve-artifact.sh <submission.zip> <output-dir>
#
# Environment:
#   MACOS_ARTIFACT_KEY   passphrase for the container (required)
#   plus the descriptive values recorded in the manifest
#
# Why this exists
# ---------------
# On 2026-09-08 a bundle was signed, submitted, and the run ended before Apple
# returned a verdict.  The signed bundle only ever existed on that runner, so
# even if a submission is accepted later there is nothing left to staple.
#
# Why it is encrypted, and why authenticated
# ------------------------------------------
# The archive is kept as a workflow artifact, and a workflow artifact in a
# PUBLIC repository is not private: GitHub requires "read access to the
# repository" to download one, which on a public repository everyone has.
#
# Encryption alone would not be enough either.  A hash sitting next to a file
# does not authenticate that file, and a manifest sitting next to a container
# can be rewritten by whoever can write the artifact.  So the authoritative
# manifest goes INSIDE the container, where the AEAD tag covers it, and the
# copy left outside is explicitly untrusted.
#
# See artifact-lib.sh for the exact cipher, mode, tag length and key handling.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
. "$HERE/artifact-lib.sh"

ZIP=${1:?usage: preserve-artifact.sh <submission.zip> <output-dir>}
OUT=${2:?usage: preserve-artifact.sh <submission.zip> <output-dir>}

if [ ! -f "$ZIP" ]; then
	echo "::error::archive to preserve not found: $ZIP"
	exit 1
fi
if ! artifact_key_present; then
	echo "::error::MACOS_ARTIFACT_KEY is not set."
	echo "::error::The signed archive would then only exist on this runner, and a"
	echo "::error::verdict arriving later could not be used."
	exit 1
fi

mkdir -p "$OUT"
umask 077
stage=$(mktemp -d "${RUNNER_TEMP:-/tmp}/simu-preserve.XXXXXX")
trap 'rm -rf "$stage"' EXIT INT TERM

zip_sha=$(shasum -a 256 "$ZIP" | awk '{ print $1 }')
zip_size=$(wc -c < "$ZIP" | tr -d ' ')

echo "== preserving the submitted archive ========================"
echo "source   : $ZIP"
echo "size     : $zip_size bytes"
echo "sha256   : $zip_sha"

# ---------------------------------------------------------------------------
# The authoritative manifest.  It goes inside the container, so the AEAD tag
# covers it and it cannot be edited without the key.
#
# Descriptive only: no key, no password, no keychain, no credential.
#
# submission_id is empty here on purpose.  This runs BEFORE the archive is
# sent, so that a runner dying immediately after submit still leaves the bytes
# behind; the id is tied to this package afterwards by bind-submission.sh.
# ---------------------------------------------------------------------------
cat > "$stage/manifest.json" <<MANIFEST
{
  "schema": "$ARTIFACT_CONTAINER_SCHEMA",
  "created_utc": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "zip_sha256": "$zip_sha",
  "zip_bytes": "$zip_size",
  "product_sha": "${SIMU_PRODUCT_SHA:-}",
  "workflow_sha": "${SIMU_WORKFLOW_SHA:-}",
  "revision_id": "${SIMU_REVISION_ID:-}",
  "arch": "${SIMU_ARCH:-}",
  "signing_identity": "${MACOS_SIGNING_IDENTITY:-}",
  "team_id": "${MACOS_TEAM_ID:-}",
  "repository": "${GITHUB_REPOSITORY:-}",
  "run_id": "${GITHUB_RUN_ID:-}",
  "run_attempt": "${GITHUB_RUN_ATTEMPT:-}",
  "not_for_distribution": "${SIMU_NOT_FOR_DISTRIBUTION:-}"
}
MANIFEST

if grep -qiE 'BEGIN [A-Z ]*PRIVATE KEY|password|\.p12|\.p8|keychain' "$stage/manifest.json"; then
	echo "::error::the manifest appears to contain credential material; refusing."
	exit 1
fi

cp "$ZIP" "$stage/payload.zip"
tar -C "$stage" -cf "$stage/container.tar" manifest.json payload.zip

echo
echo "== encrypting =============================================="
artifact_encrypt "$stage/container.tar" "$OUT/bundle.gpg"
gpg --list-packets --list-only "$OUT/bundle.gpg" 2>/dev/null | sed 's/^/  /'

enc_sha=$(shasum -a 256 "$OUT/bundle.gpg" | awk '{ print $1 }')
echo "  container sha256 : $enc_sha"
echo "  container bytes  : $(wc -c < "$OUT/bundle.gpg" | tr -d ' ')"

# ---------------------------------------------------------------------------
# Prove the round trip now, while the plaintext is still here to compare
# against.  Storing something that cannot be opened is worse than storing
# nothing, because it is only discovered when it is needed.
# ---------------------------------------------------------------------------
artifact_decrypt "$OUT/bundle.gpg" "$stage/back.tar"
mkdir -p "$stage/back"
tar -C "$stage/back" -xf "$stage/back.tar"
back_sha=$(shasum -a 256 "$stage/back/payload.zip" | awk '{ print $1 }')
if [ "$back_sha" != "$zip_sha" ]; then
	echo "::error::round trip produced different bytes ($back_sha != $zip_sha)."
	exit 1
fi
echo "  round trip verified: decrypts back to the same bytes"

# ---------------------------------------------------------------------------
# A copy of the manifest left outside the container, so that someone looking
# at the artifact can see what it is without the key.
#
# It is NOT authenticated and must never be used to decide anything.  The
# marker below is there so that a reader, and a script, can tell.
# ---------------------------------------------------------------------------
{
	echo '{'
	echo '  "_warning": "UNTRUSTED DESCRIPTIVE COPY. Not authenticated. The manifest that counts is inside bundle.gpg, covered by its AEAD tag. Do not make decisions from this file.",'
	sed '1d' "$stage/manifest.json" | sed '$d'
	echo '  ,"container_sha256": "'"$enc_sha"'"'
	echo '}'
} > "$OUT/manifest.public.json"

echo
echo "preserved in $OUT"
ls -l "$OUT"
