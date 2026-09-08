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
# Usage: inspect-bundle.sh <path-to-.app> <expected-arch> [inventory-out] [summary-out]
#
#   expected-arch    arm64 or x86_64
#   inventory-out    optional file to write the Mach-O list to, one path per
#                    line, deepest first.  A record of what was there; sign.sh
#                    deliberately recomputes its own list rather than trusting
#                    this one.
#   summary-out      optional key=value file for the build manifest

set -euo pipefail

# Overridable only so the scripts can be exercised off a Mac; on macOS this is
# always the real tool.
PLISTBUDDY=${PLISTBUDDY:-/usr/libexec/PlistBuddy}

APP=${1:?usage: inspect-bundle.sh <path-to-.app> <expected-arch> [inventory-out] [summary-out]}
EXPECTED_ARCH=${2:?expected architecture (arm64 or x86_64) is required}
INVENTORY=${3:-}
# key=value facts about the bundle, for the build manifest.
SUMMARY_OUT=${4:-}

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
matching=0
other_arch_only=0
while IFS= read -r f; do
	archs=$(lipo -archs "$f" 2>/dev/null || echo "unknown")
	printf '%-12s %s\n' "$archs" "${f#"$APP"/}"
	if [ "$archs" = "$EXPECTED_ARCH" ]; then
		matching=$((matching + 1))
	else
		note_failure "architecture mismatch: ${f#"$APP"/} is '$archs', expected exactly '$EXPECTED_ARCH'"
		case " $archs " in
			*" $EXPECTED_ARCH "*) ;;
			*) other_arch_only=$((other_arch_only + 1)) ;;
		esac
	fi
done < "$macho_list.sorted"

# Spelled out separately because this is the exact shape the published
# "simumac-intel" archive has: an asset named for one architecture whose every
# binary is the other one.  The name of a package is not evidence about it.
if [ "$matching" -eq 0 ] && [ "$other_arch_only" -gt 0 ]; then
	note_failure "this package is labelled '$EXPECTED_ARCH' but not one of its $macho_count Mach-O files is $EXPECTED_ARCH; it would not run on the machines it is named for"
fi
echo

# ---------------------------------------------------------------------------
# 3. Minimum macOS version, measured across the whole bundle.
#
# The main executable's own deployment target is not the answer.  The bundle
# ships Homebrew libraries built for the runner's macOS, and the application
# cannot start on a system older than the highest minimum among everything it
# loads.  The effective floor is therefore the maximum over all of them, and
# that is what gets reported; the executable's own value is printed beside it
# so the two cannot be confused.
# ---------------------------------------------------------------------------
echo "== minimum macOS (measured across every Mach-O) ============"

minos_of() {
	otool -l "$1" | awk '
		/LC_BUILD_VERSION/      { inblock = 1 }
		inblock && /minos/      { print $2; exit }
		/LC_VERSION_MIN_MACOSX/ { vmin = 1 }
		vmin && /version/       { print $2; exit }'
}

# Orders 15.0 < 15.4 < 26.0, which a string compare does not.
version_gt() {
	[ "$1" = "$2" ] && return 1
	[ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$1" ]
}

effective_min=""
effective_min_file=""
while IFS= read -r f; do
	m=$(minos_of "$f")
	[ -n "$m" ] || continue
	printf '   %-10s %s\n' "$m" "${f#"$APP"/}"
	if [ -z "$effective_min" ] || version_gt "$m" "$effective_min"; then
		effective_min=$m
		effective_min_file=$f
	fi
done < "$macho_list.sorted"

main_binary="$APP/Contents/MacOS/$("$PLISTBUDDY" -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
if [ -f "$main_binary" ]; then
	main_min=$(minos_of "$main_binary")
	echo
	echo "   main executable deployment target : ${main_min:-unknown}"
	echo "   EFFECTIVE minimum macOS           : ${effective_min:-unknown} (set by ${effective_min_file#"$APP"/})"
	if [ -n "$main_min" ] && [ -n "$effective_min" ] && version_gt "$effective_min" "$main_min"; then
		echo "::warning::a bundled library requires macOS $effective_min while the executable targets $main_min."
		echo "::warning::The package runs on macOS $effective_min and later.  Do not advertise $main_min."
	fi
	if [ -n "$SUMMARY_OUT" ]; then
		{
			echo "expected_arch=$EXPECTED_ARCH"
			echo "macho_count=$macho_count"
			echo "symlinks=$symlink_count"
			echo "main_deployment_target=${main_min:-unknown}"
			echo "effective_min_macos=${effective_min:-unknown}"
			echo "effective_min_set_by=${effective_min_file#"$APP"/}"
		} > "$SUMMARY_OUT"
	fi
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
