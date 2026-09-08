#!/bin/bash
#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#
# Check the extracted build payload before the signing identity is loaded.
#
# Usage: check-payload.sh <extracted-root> <expected-app-relative-path>
#
# The signing job receives an archive from the build job.  "It is only data"
# is not on its own a safety argument: an archive can carry symlinks that
# point outside the tree it was extracted into, paths that escape it, and
# files with setuid bits, and the tools that run next walk that tree.  This
# runs first, and it runs BEFORE keychain.sh, so a payload that fails here is
# rejected while the Developer ID is still nowhere near the machine.
#
# It checks that:
#   * nothing in the tree resolves outside the extraction root,
#   * no symlink is absolute or escapes the root,
#   * no file carries setuid or setgid,
#   * the bundle is exactly where the workflow expects it and there is only
#     one of them,
#   * nothing outside the bundle came along for the ride.

set -euo pipefail

ROOT=${1:?usage: check-payload.sh <extracted-root> <expected-app-relative-path>}
EXPECTED_APP=${2:?expected .app path, relative to the extraction root}

if [ ! -d "$ROOT" ]; then
	echo "::error::extraction root not found: $ROOT"
	exit 1
fi

# Compare against the physical path, so a symlinked temporary directory does
# not make every entry look like an escape.
root_real=$(cd "$ROOT" && pwd -P)

failures=0
note_failure() {
	echo "::error::$1"
	failures=$((failures + 1))
}

echo "== payload check ==========================================="
echo "root          : $root_real"
echo "expected app  : $EXPECTED_APP"
echo

entries=$(find "$ROOT" | wc -l | tr -d ' ')
echo "entries: $entries"

# ---------------------------------------------------------------------------
# 1. Symlinks.
#
# An absolute symlink, or one with enough ".." to climb out, would make the
# later `find`/`codesign` walk touch files that were never part of the build.
# ---------------------------------------------------------------------------
echo
echo "-- symlinks"
symlinks=0
while IFS= read -r -d '' link; do
	symlinks=$((symlinks + 1))
	target=$(readlink "$link")
	printf '   %s -> %s\n' "${link#"$ROOT"/}" "$target"

	case "$target" in
		/*)
			note_failure "absolute symlink in the payload: ${link#"$ROOT"/} -> $target"
			continue
			;;
	esac

	# Resolve relative to the link's own directory and check it stays inside.
	resolved=$(cd "$(dirname "$link")" 2>/dev/null && cd "$(dirname "$target")" 2>/dev/null && pwd -P || true)
	if [ -z "$resolved" ]; then
		note_failure "symlink target cannot be resolved: ${link#"$ROOT"/} -> $target"
		continue
	fi
	case "$resolved/" in
		"$root_real"/*) ;;
		*)
			note_failure "symlink escapes the payload: ${link#"$ROOT"/} -> $target (resolves to $resolved)"
			;;
	esac
done < <(find "$ROOT" -type l -print0)
[ "$symlinks" -eq 0 ] && echo "   (none)"

# ---------------------------------------------------------------------------
# 2. Every regular file and directory must physically live under the root.
# ---------------------------------------------------------------------------
echo
echo "-- containment"
outside=0
while IFS= read -r -d '' d; do
	real=$(cd "$d" && pwd -P)
	case "$real/" in
		"$root_real"/*) ;;
		*)
			note_failure "directory resolves outside the payload: ${d#"$ROOT"/} -> $real"
			outside=$((outside + 1))
			;;
	esac
done < <(find "$ROOT" -type d -print0)
echo "   directories outside the root: $outside"

# ---------------------------------------------------------------------------
# 3. setuid / setgid.
#
# Nothing the build produces should carry these, and a package that does has
# no business being signed with a Developer ID and handed to users.
# ---------------------------------------------------------------------------
echo
echo "-- setuid/setgid"
suid=$(find "$ROOT" -type f \( -perm -4000 -o -perm -2000 \) -print)
if [ -n "$suid" ]; then
	printf '%s\n' "$suid"
	note_failure "the payload contains setuid or setgid files"
else
	echo "   (none)"
fi

# ---------------------------------------------------------------------------
# 4. Exactly one bundle, exactly where it is expected.
# ---------------------------------------------------------------------------
echo
echo "-- bundle layout"
apps=$(find "$ROOT" -name '*.app' -maxdepth 4 -type d)
app_count=$(printf '%s\n' "$apps" | grep -c . || true)
printf '%s\n' "$apps" | sed 's/^/   /'
if [ "$app_count" -ne 1 ]; then
	note_failure "expected exactly one .app in the payload, found $app_count"
fi
if [ ! -d "$ROOT/$EXPECTED_APP" ]; then
	note_failure "the bundle is not at the expected path: $EXPECTED_APP"
fi

# Nothing should sit beside the bundle: the build archives one directory that
# contains one application, and anything else is a surprise worth stopping on.
strays=$(find "$ROOT" -mindepth 1 -maxdepth 2 \
	-not -path "$ROOT/$(dirname "$EXPECTED_APP")" \
	-not -path "$ROOT/$EXPECTED_APP" \
	-not -path "$ROOT/$EXPECTED_APP/*" || true)
if [ -n "$strays" ]; then
	echo "   unexpected entries beside the bundle:"
	printf '%s\n' "$strays" | sed 's/^/     /'
	note_failure "the payload contains entries outside the expected bundle"
fi

echo
if [ "$failures" -gt 0 ]; then
	echo "::error::payload check failed with $failures problem(s); refusing to load the signing identity."
	exit 1
fi
echo "payload check passed: $entries entries, $symlinks symlink(s), one bundle at $EXPECTED_APP"
