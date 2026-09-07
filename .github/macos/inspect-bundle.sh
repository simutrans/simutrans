#!/bin/bash
#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#
# Inventory and sanity-check a built simutrans.app before it is signed.
#
# Needs no credentials, so it runs in the unprivileged build job.  It answers
# the questions that decide whether the bundle is fit to be signed at all:
#
#   * which files are Mach-O, and therefore have to be signed individually,
#   * whether every one of them is the architecture we claim to be shipping,
#   * whether anything still points at a path that only exists on the build
#     machine (Homebrew prefixes, the runner home directory), which would work
#     on the runner and fail on a user's Mac.
#
# Usage: inspect-bundle.sh <path-to-.app> <expected-arch> [inventory-out]
#
#   expected-arch    arm64 or x86_64
#   inventory-out    optional file to write the Mach-O list to, one path per
#                    line, deepest first.  sign.sh consumes this ordering.

set -euo pipefail

# Overridable only so the scripts can be exercised off a Mac; on macOS this is
# always the real tool.
PLISTBUDDY=${PLISTBUDDY:-/usr/libexec/PlistBuddy}

APP=${1:?usage: inspect-bundle.sh <path-to-.app> <expected-arch> [inventory-out]}
EXPECTED_ARCH=${2:?expected architecture (arm64 or x86_64) is required}
INVENTORY=${3:-}

if [ ! -d "$APP" ]; then
	echo "::error::bundle not found: $APP"
	exit 1
fi

case "$EXPECTED_ARCH" in
	arm64|x86_64) ;;
	*)
		echo "::error::unsupported expected architecture '$EXPECTED_ARCH' (use arm64 or x86_64)"
		exit 1
		;;
esac

# Absolute paths that exist only on the build machine.  A dependency or an
# rpath resolving into one of these makes the bundle non-portable.
BUILD_ONLY_PREFIXES=(
	'/opt/homebrew'
	'/usr/local/opt'
	'/usr/local/Cellar'
	'/usr/local/lib'
	'/Users/runner'
	"$HOME"
)

failures=0
note_failure() {
	echo "::error::$1"
	failures=$((failures + 1))
}

echo "== bundle =================================================="
echo "path : $APP"
echo "expected architecture : $EXPECTED_ARCH"
echo

# ---------------------------------------------------------------------------
# 1. Real inventory of signable components.
#
# -type f on purpose: symlinks are not signed, their targets are.  Signing a
# symlink would either sign the target twice or fail outright.
# ---------------------------------------------------------------------------
macho_list=$(mktemp)
trap 'rm -f "$macho_list" "$macho_list.sorted"' EXIT

while IFS= read -r -d '' f; do
	if file -b "$f" | grep -q 'Mach-O'; then
		printf '%s\n' "$f"
	fi
done < <(find "$APP" -type f -print0) > "$macho_list"

# Deepest path first, so nested code is always signed before its container.
awk '{ print gsub(/\//, "/") "\t" $0 }' "$macho_list" \
	| sort -rn -k1,1 \
	| cut -f2- > "$macho_list.sorted"

macho_count=$(wc -l < "$macho_list.sorted" | tr -d ' ')
echo "== Mach-O inventory ($macho_count files) ===================="
cat "$macho_list.sorted"
echo

if [ "$macho_count" -eq 0 ]; then
	note_failure "no Mach-O files found inside $APP - the build produced nothing signable"
fi

symlink_count=$(find "$APP" -type l | wc -l | tr -d ' ')
echo "symlinks inside the bundle : $symlink_count"
echo

# ---------------------------------------------------------------------------
# 2. Architecture of every Mach-O file.
#
# lipo -archs lists the slices.  A single-architecture distribution must not
# contain a file of a different architecture, and a file carrying extra slices
# is reported rather than silently accepted.
# ---------------------------------------------------------------------------
echo "== architectures ==========================================="
while IFS= read -r f; do
	archs=$(lipo -archs "$f" 2>/dev/null || echo "unknown")
	printf '%-12s %s\n' "$archs" "${f#"$APP"/}"
	if [ "$archs" != "$EXPECTED_ARCH" ]; then
		note_failure "architecture mismatch: ${f#"$APP"/} is '$archs', expected exactly '$EXPECTED_ARCH'"
	fi
done < "$macho_list.sorted"
echo

# ---------------------------------------------------------------------------
# 3. Deployment target actually produced by this toolchain.
#
# The project sets no CMAKE_OSX_DEPLOYMENT_TARGET, so this value is whatever
# the runner's SDK defaulted to.  It is recorded, not asserted: claiming a
# minimum macOS version we have not measured would be a fabrication.
# ---------------------------------------------------------------------------
echo "== deployment target (measured, not configured) ============"
main_binary="$APP/Contents/MacOS/$("$PLISTBUDDY" -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
if [ -f "$main_binary" ]; then
	otool -l "$main_binary" | awk '
		/LC_BUILD_VERSION/   { inblock = 1 }
		inblock && /platform/ { platform = $2 }
		inblock && /minos/    { minos = $2 }
		inblock && /sdk/      { sdk = $2; inblock = 0 }
		END { printf "platform=%s minos=%s sdk=%s\n", platform, minos, sdk }'
else
	note_failure "main executable not found where Info.plist says it is: $main_binary"
fi
echo

# ---------------------------------------------------------------------------
# 4. Dynamic dependencies and rpaths must not escape the bundle.
# ---------------------------------------------------------------------------
echo "== dynamic dependencies ===================================="
while IFS= read -r f; do
	echo "--- ${f#"$APP"/}"
	# otool -L repeats the file name on the first line; drop it.
	deps=$(otool -L "$f" | tail -n +2 | awk '{ print $1 }')
	rpaths=$(otool -l "$f" | awk '/LC_RPATH/ { getline; getline; print $2 }')

	for d in $deps $rpaths; do
		printf '    %s\n' "$d"
		for prefix in "${BUILD_ONLY_PREFIXES[@]}"; do
			[ -n "$prefix" ] || continue
			case "$d" in
				"$prefix"*)
					note_failure "build-machine path leaked into ${f#"$APP"/}: $d"
					;;
			esac
		done
	done
done < "$macho_list.sorted"
echo

if [ -n "$INVENTORY" ]; then
	cp "$macho_list.sorted" "$INVENTORY"
	echo "inventory written to $INVENTORY"
fi

if [ "$failures" -gt 0 ]; then
	echo "::error::bundle inspection failed with $failures problem(s); refusing to treat this build as signable"
	exit 1
fi

echo "bundle inspection passed: $macho_count Mach-O file(s), all $EXPECTED_ARCH, no build-machine paths"
