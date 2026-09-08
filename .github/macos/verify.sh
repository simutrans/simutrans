#!/bin/bash
#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#
# Final gate.  Everything before this point operated on a bundle sitting in
# the build tree; this checks the file that would actually be handed to a
# user, after a full archive/extract round trip.
#
# Usage: verify.sh <distribution.zip> <expected-arch> <expected-symlink-count>
#
# It fails if any of these is not true of the extracted application:
#   * the code signature is valid, including all nested code,
#   * a notarization ticket is stapled to it,
#   * Gatekeeper assesses it as a notarized Developer ID application,
#   * the archive round trip preserved symlinks and executable bits,
#   * the architecture is still the one being shipped and no build-machine
#     path survived into the dependencies.

set -euo pipefail

# Overridable only so the scripts can be exercised off a Mac; on macOS this is
# always the real tool.
PLISTBUDDY=${PLISTBUDDY:-/usr/libexec/PlistBuddy}

ZIP=${1:?usage: verify.sh <distribution.zip> <expected-arch> <expected-symlink-count>}
EXPECTED_ARCH=${2:?expected architecture is required}
EXPECTED_SYMLINKS=${3:?expected symlink count is required}

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ ! -f "$ZIP" ]; then
	echo "::error::distribution archive not found: $ZIP"
	exit 1
fi

workdir=$(mktemp -d "${RUNNER_TEMP:-/tmp}/simu-verify.XXXXXX")
trap 'rm -rf "$workdir"' EXIT

echo "== extracting the archive that would be shipped ============"
echo "archive : $ZIP"
echo "size    : $(stat -f %z "$ZIP") bytes"
echo "sha256  : $(shasum -a 256 "$ZIP" | awk '{ print $1 }')"
# ditto, not unzip: unzip does not restore the metadata that ditto stored, and
# verifying an incorrectly extracted copy would prove nothing about the file
# users receive.
ditto -x -k "$ZIP" "$workdir/extracted"

app=$(find "$workdir/extracted" -maxdepth 3 -name '*.app' -type d | head -1)
if [ -z "$app" ]; then
	echo "::error::no .app found inside $ZIP"
	find "$workdir/extracted" -maxdepth 3
	exit 1
fi
echo "application : ${app#"$workdir/extracted"/}"
echo

failures=0
note_failure() {
	echo "::error::$1"
	failures=$((failures + 1))
}

# ---------------------------------------------------------------------------
# 1. The round trip preserved the bundle.
# ---------------------------------------------------------------------------
echo "== archive fidelity ========================================"
actual_symlinks=$(find "$app" -type l | wc -l | tr -d ' ')
echo "symlinks : $actual_symlinks (expected $EXPECTED_SYMLINKS)"
if [ "$actual_symlinks" -ne "$EXPECTED_SYMLINKS" ]; then
	note_failure "the archive did not preserve symlinks: $actual_symlinks survived, $EXPECTED_SYMLINKS were present before archiving"
fi

main_executable_name=$("$PLISTBUDDY" -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")
if [ ! -x "$app/Contents/MacOS/$main_executable_name" ]; then
	note_failure "the main executable lost its executable bit in the archive round trip"
fi
echo

# ---------------------------------------------------------------------------
# 2. Signature, including nested code.
# ---------------------------------------------------------------------------
echo "== code signature =========================================="
if ! codesign --verify --deep --strict --verbose=4 "$app"; then
	note_failure "the code signature of the extracted application is not valid"
fi
codesign --display --verbose=4 "$app" 2>&1 || true
echo

# ---------------------------------------------------------------------------
# 3. Stapled ticket.
#
# Checked on the extracted copy on purpose: a ticket stapled before archiving
# is only useful if it survived being archived.
# ---------------------------------------------------------------------------
echo "== stapled notarization ticket ============================="
if ! xcrun stapler validate "$app"; then
	note_failure "no valid notarization ticket is stapled to the extracted application"
fi
echo

# ---------------------------------------------------------------------------
# 4. Gatekeeper's own verdict.
# ---------------------------------------------------------------------------
echo "== Gatekeeper assessment ==================================="
assessment=$(spctl --assess --type exec -vvv "$app" 2>&1 || true)
echo "$assessment"
if ! printf '%s' "$assessment" | grep -q 'accepted'; then
	note_failure "Gatekeeper did not accept the application"
fi
if ! printf '%s' "$assessment" | grep -q 'source=Notarized Developer ID'; then
	note_failure "Gatekeeper does not see this as a notarized Developer ID application"
fi
echo

# ---------------------------------------------------------------------------
# 5. The binary is still what we said we were shipping.
# ---------------------------------------------------------------------------
echo "== architecture and dependencies of the shipped binary ====="
if ! "$HERE/inspect-bundle.sh" "$app" "$EXPECTED_ARCH"; then
	note_failure "the extracted application failed the same inspection the build applied before signing"
fi

if [ "$failures" -gt 0 ]; then
	echo "::error::final verification failed with $failures problem(s)."
	echo "::error::This artifact must not be described as signed and notarized."
	exit 1
fi

echo
echo "VERIFIED: signed with Developer ID, notarized, ticket stapled, accepted by Gatekeeper."
