#!/bin/bash
#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#
# Recover a preserved signed archive and prove it is the one that was meant.
#
# Usage: restore-artifact.sh <preserved-dir> <output.zip>
#
# Required environment:
#   MACOS_ARTIFACT_KEY        passphrase the container was made with
#   EXPECT_PRODUCT_SHA        commit the product must have been built from
#   EXPECT_RUN_ID             run that must have produced it
#   EXPECT_ARCH               architecture it must be
# Optional:
#   EXPECT_SIGNING_IDENTITY   identity it must have been signed with
#
# The expectations are REQUIRED, and that is the point of this script.
#
# Authenticity and identity are two different questions.  The AEAD tag answers
# the first: this container was made by someone with the key and has not been
# altered.  It does not answer the second, because a DIFFERENT container, also
# perfectly valid, also made with the same key, could be put in its place -
# an older run, another architecture, another commit.  Nothing the package
# says about itself can settle that; only comparing it against values the
# caller already holds from somewhere else can.
#
# So: the container is authenticated first, opened second, and only then
# checked against what the caller expected.  Content is never extracted before
# its authenticity is established.

set -euo pipefail

DIR=${1:?usage: restore-artifact.sh <preserved-dir> <output.zip>}
OUTZIP=${2:?usage: restore-artifact.sh <preserved-dir> <output.zip>}

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
. "$HERE/artifact-lib.sh"
# shellcheck source=/dev/null
. "$HERE/notary-lib.sh"

fail() { echo "::error::$1"; exit 1; }

container="$DIR/bundle.gpg"
[ -f "$container" ] || fail "no encrypted container in $DIR; refusing to continue."
artifact_key_present || fail "MACOS_ARTIFACT_KEY is not set; the container cannot be opened."

# Independently known values.  Without them there is nothing to compare the
# package against, and a valid-but-wrong package would sail through.
for v in EXPECT_PRODUCT_SHA EXPECT_RUN_ID EXPECT_ARCH; do
	[ -n "${!v:-}" ] || fail "$v must be provided. A container cannot be trusted to describe itself."
done

work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/simu-restore.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

echo "== restoring the preserved archive ========================="
echo "from      : $DIR"
echo "container : sha256 $(shasum -a 256 "$container" | awk '{print $1}')"

# ---------------------------------------------------------------------------
# 1. Authenticity, before anything is unpacked.
# ---------------------------------------------------------------------------
artifact_decrypt "$container" "$work/container.tar" \
	|| fail "the container could not be authenticated and decrypted."
echo "authenticated: AES-256 OCB tag verified"

# Extract only the two members expected, into an empty directory.  A container
# is not a place to accept arbitrary paths from.
mkdir -p "$work/in"
tar -C "$work/in" -xf "$work/container.tar" manifest.json payload.zip \
	|| fail "the container does not hold the expected members."

manifest="$work/in/manifest.json"
payload="$work/in/payload.zip"
[ -s "$manifest" ] || fail "the container has no manifest."
[ -s "$payload" ]  || fail "the container has no payload."

# ---------------------------------------------------------------------------
# 2. The manifest is now trustworthy - it was inside the authenticated
#    container - so its fields can be read.
# ---------------------------------------------------------------------------
schema=$(json_field "$manifest" schema || true)
[ "$schema" = "$ARTIFACT_CONTAINER_SCHEMA" ] \
	|| fail "unrecognised container schema '${schema:-<none>}'; refusing to guess its meaning."

zip_sha=$(json_field "$manifest" zip_sha256 || true)
product_sha=$(json_field "$manifest" product_sha || true)
run_id=$(json_field "$manifest" run_id || true)
arch=$(json_field "$manifest" arch || true)
identity=$(json_field "$manifest" signing_identity || true)
revision_id=$(json_field "$manifest" revision_id || true)

printf '  %-18s %s\n' "product" "${product_sha:-<none>}"
printf '  %-18s %s\n' "revision" "${revision_id:-<none>}"
printf '  %-18s %s\n' "arch" "${arch:-<none>}"
printf '  %-18s %s\n' "identity" "${identity:-<none>}"
printf '  %-18s %s\n' "source run" "${run_id:-<none>}"

printf '%s' "$zip_sha" | grep -qE '^[0-9a-f]{64}$' || fail "the manifest has no usable zip_sha256."

actual_sha=$(shasum -a 256 "$payload" | awk '{ print $1 }')
[ "$actual_sha" = "$zip_sha" ] \
	|| fail "the payload does not match its own manifest: $actual_sha != $zip_sha."

# ---------------------------------------------------------------------------
# 3. Substitution defence: is this the package the caller meant, and not
#    merely a valid one?
# ---------------------------------------------------------------------------
[ "$product_sha" = "$EXPECT_PRODUCT_SHA" ] \
	|| fail "this container was built from '${product_sha}', but '$EXPECT_PRODUCT_SHA' was expected."
[ "$run_id" = "$EXPECT_RUN_ID" ] \
	|| fail "this container came from run '${run_id}', but run '$EXPECT_RUN_ID' was expected."
[ "$arch" = "$EXPECT_ARCH" ] \
	|| fail "this container is '${arch}', but '$EXPECT_ARCH' was expected."
if [ -n "${EXPECT_SIGNING_IDENTITY:-}" ] && [ "$identity" != "$EXPECT_SIGNING_IDENTITY" ]; then
	fail "this container was signed as '$identity', not as '$EXPECT_SIGNING_IDENTITY'."
fi

mkdir -p "$(dirname "$OUTZIP")"
cp "$payload" "$OUTZIP"

echo "provenance accepted"
echo "restored to $OUTZIP (sha256 $actual_sha)"
