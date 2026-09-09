#!/bin/bash
#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#
# Sign simutrans.app with the Developer ID identity held in the temporary
# keychain created by keychain.sh, from the inside out, and prove the result
# is fit to be sent to the Apple notary service.
#
# Usage: sign.sh <path-to-.app>
#
# Environment:
#   MACOS_SIGNING_IDENTITY  identity string to sign with (required)
#   MACOS_TEAM_ID           expected Team ID, asserted if set (optional)
#   SIMU_KEYCHAIN_PATH      keychain to sign from (defaults as in keychain.sh)
#
# Two things this script deliberately does not do:
#
#   * it does not use `codesign --deep` to sign.  --deep applies one set of
#     flags to whatever it happens to find and silently skips things it does
#     not recognise; Apple documents it as unsuitable for distribution
#     signing.  Every Mach-O file is signed by name instead.
#   * it does not pass --entitlements.  Simutrans requests no restricted
#     capability: the sources contain no dlopen/dlsym, no JIT or writable
#     executable mapping, and no audio-input, camera or location use.  Every
#     library it loads ships inside the bundle and is signed here with the
#     same Team ID, so the Hardened Runtime's library validation is satisfied
#     without disabling it.  An empty entitlement set is the minimum that
#     works, and adding entitlements "just in case" would weaken the runtime.

set -euo pipefail

# Overridable only so the scripts can be exercised off a Mac; on macOS this is
# always the real tool.
PLISTBUDDY=${PLISTBUDDY:-/usr/libexec/PlistBuddy}

APP=${1:?usage: sign.sh <path-to-.app>}
IDENTITY=${MACOS_SIGNING_IDENTITY:?MACOS_SIGNING_IDENTITY is required}
KEYCHAIN_PATH=${SIMU_KEYCHAIN_PATH:-${RUNNER_TEMP:-/tmp}/simutrans-signing.keychain-db}

if [ ! -d "$APP" ]; then
	echo "::error::bundle not found: $APP"
	exit 1
fi
if [ ! -f "$KEYCHAIN_PATH" ]; then
	echo "::error::temporary keychain not found at $KEYCHAIN_PATH; run keychain.sh setup first."
	exit 1
fi

main_executable_name=$("$PLISTBUDDY" -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")
main_executable="$APP/Contents/MacOS/$main_executable_name"
bundle_id=$("$PLISTBUDDY" -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")

echo "bundle           : $APP"
echo "bundle identifier: $bundle_id"
echo "main executable  : ${main_executable#"$APP"/}"
echo

# ---------------------------------------------------------------------------
# Inventory.
#
# Recomputed here rather than read from the build job's artifact: the job that
# holds the signing identity decides for itself what it is about to sign, and
# never takes that list from data produced elsewhere.
# ---------------------------------------------------------------------------
inventory=$(mktemp)
trap 'rm -f "$inventory"' EXIT

while IFS= read -r -d '' f; do
	if file -b "$f" | grep -q 'Mach-O'; then
		printf '%s\n' "$f"
	fi
done < <(find "$APP" -type f -print0) \
	| awk '{ print gsub(/\//, "/") "\t" $0 }' \
	| sort -rn -k1,1 \
	| cut -f2- > "$inventory"

total=$(wc -l < "$inventory" | tr -d ' ')
echo "== signing $total Mach-O file(s), deepest first ============"

# ---------------------------------------------------------------------------
# Nested code first, the bundle last.
#
# The main executable is skipped in this loop: signing the bundle signs it as
# part of sealing the bundle, and doing it twice would only invalidate the
# seal that the bundle signature is about to compute.
# ---------------------------------------------------------------------------
signed=0
while IFS= read -r f; do
	if [ "$f" = "$main_executable" ]; then
		continue
	fi
	echo "--- ${f#"$APP"/}"
	codesign --force \
		--sign "$IDENTITY" \
		--keychain "$KEYCHAIN_PATH" \
		--options runtime \
		--timestamp \
		--verbose=2 \
		"$f"
	signed=$((signed + 1))
done < "$inventory"

echo "--- $(basename "$APP") (bundle)"
codesign --force \
	--sign "$IDENTITY" \
	--keychain "$KEYCHAIN_PATH" \
	--options runtime \
	--timestamp \
	--verbose=2 \
	"$APP"

echo
echo "signed $signed nested Mach-O file(s) plus the bundle itself"
echo
echo "::notice::the bundle is signed; nothing may modify it from here on."
echo "Any later change to a file inside it, including touching a resource,"
echo "breaks the seal and the notary service will reject the submission."

# ---------------------------------------------------------------------------
# Verify before submitting anything to Apple.
#
# --deep IS correct here.  The prohibition is on signing with --deep; for
# verification Apple's own guidance is to use --deep --strict so that nested
# code is checked too.
# ---------------------------------------------------------------------------
echo
echo "== verification before submission =========================="

echo "--- codesign --verify --deep --strict"
codesign --verify --deep --strict --verbose=4 "$APP"

details=$(codesign --display --verbose=4 "$APP" 2>&1)
echo "--- codesign --display"
echo "$details"

failures=0
note_failure() {
	echo "::error::$1"
	failures=$((failures + 1))
}

# Every check below reads its subject with a here-string, not through
# `printf ... | grep`.  That is not a style preference.
#
# `grep -q` exits as soon as it matches.  When the text is larger than the pipe
# buffer the writer is still writing at that moment, so it dies of SIGPIPE with
# status 141 - and under `set -o pipefail` that 141 becomes the status of the
# whole pipeline.  `if ! ...` then reads a SUCCESSFUL match as a failure.
# Whether it happens depends on how much the writer got out first, so it is a
# race: on 2026-09-09 it reported "nested code without Hardened Runtime" for a
# library that was correctly signed, and that had passed every run before.
#
# A here-string has no second process to kill, so the match decides the status
# and nothing else does.
#
# Hardened Runtime shows up as the "runtime" flag on the code signature.
if ! grep -qE '^CodeDirectory .*flags=.*runtime' <<<"$details"; then
	note_failure "the signature does not have the Hardened Runtime flag set; the notary service rejects such submissions"
fi

# A secure timestamp appears as "Timestamp=".  A signature without one shows
# "Signed Time=" instead, which is not good enough for notarization.
if ! grep -q '^Timestamp=' <<<"$details"; then
	note_failure "the signature carries no secure timestamp (only 'Signed Time'); check that timestamp.apple.com was reachable"
fi

if ! grep -q 'Authority=Developer ID Application:' <<<"$details"; then
	note_failure "the signing authority is not a Developer ID Application certificate"
fi

if [ -n "${MACOS_TEAM_ID:-}" ]; then
	if ! grep -q "^TeamIdentifier=$MACOS_TEAM_ID\$" <<<"$details"; then
		note_failure "TeamIdentifier does not match the declared MACOS_TEAM_ID"
	fi
fi

# get-task-allow is the entitlement that turns a distribution build into a
# debuggable one; Apple rejects notarization when it is present.
entitlements=$(codesign --display --entitlements :- "$APP" 2>/dev/null || true)
if grep -q 'get-task-allow' <<<"$entitlements"; then
	note_failure "the signed bundle requests com.apple.security.get-task-allow, which the notary service refuses"
fi
echo "--- entitlements"
if [ -z "$entitlements" ]; then
	echo "(none, as intended)"
else
	echo "$entitlements"
fi

# Every nested Mach-O must have come out with the same treatment.
while IFS= read -r f; do
	nested=$(codesign --display --verbose=2 "$f" 2>&1)
	if ! grep -qE 'flags=.*runtime' <<<"$nested"; then
		note_failure "nested code without Hardened Runtime: ${f#"$APP"/}"
	fi
	if ! grep -q '^Timestamp=' <<<"$nested"; then
		note_failure "nested code without a secure timestamp: ${f#"$APP"/}"
	fi
done < "$inventory"

if [ "$failures" -gt 0 ]; then
	echo "::error::signature verification failed with $failures problem(s); nothing will be submitted to Apple."
	exit 1
fi

echo
echo "signature verified: Developer ID, Hardened Runtime, secure timestamp, no get-task-allow"
