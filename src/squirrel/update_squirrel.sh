#!/bin/bash
#
# Script to update squirrel source code from SQUIRREL3
#
# Call with ``update_squirrel PATH_TO_SQUIRREL'', where
# PATH_TO_SQUIRREL is path of local clone of https://github.com/albertodemichelis/squirrel
#
# Call it within a git repo of simutrans. It may be called from any directory,
# it locates the simutrans tree relative to itself.
#
# It imports the upstream sources, but ignores whitespace-only upstream changes,
# so that our formatting is kept.
#
# Still needs manual review, to make sure none of our modifications are reverted.
# squirrel_modifications.diff lists the modifications that have to survive.
set -e
set -u

# locate the tree relative to this script, so the working directory does not matter
SQUIRRELDIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPODIR=$(cd -- "$SQUIRRELDIR/../.." && pwd)

SQPATH=${1-}
if [ -z "$SQPATH" ]; then
	echo "usage: update_squirrel.sh PATH_TO_SQUIRREL" >&2
	exit 1
fi
# check the upstream tree before anything is overwritten
for i in COPYRIGHT include squirrel sqstdlib; do
	if [ ! -e "$SQPATH/$i" ]; then
		echo "$SQPATH is no squirrel source tree: $i is missing" >&2
		exit 1
	fi
done

# we need gawk, gensub() in update_squirrel.awk is no posix awk function
is_gnu_awk()
{
	command -v "$1" > /dev/null 2>&1 || return 1
	case $("$1" --version 2>/dev/null | head -n 1) in
		"GNU Awk"*) return 0;;
	esac
	return 1
}

GAWK=${GAWK-}
if [ -z "$GAWK" ]; then
	for i in gawk awk; do
		if is_gnu_awk "$i"; then
			GAWK=$i
			break
		fi
	done
fi
if [ -z "$GAWK" ] || ! is_gnu_awk "$GAWK"; then
	echo "GNU awk not found, set GAWK to the path of GNU awk" >&2
	exit 1
fi

# transform a file in place, but only if the transformation succeeded
TEMPDIR=$(mktemp -d)
trap 'rm -rf "$TEMPDIR"' EXIT
transform()
{
	"$GAWK" -f "$SQUIRRELDIR/update_squirrel.awk" "$1" > "$TEMPDIR/temp"
	mv "$TEMPDIR/temp" "$1"
}

cd "$SQUIRRELDIR"
# copy and rename files
echo "$SQPATH/COPYRIGHT" "$REPODIR/simutrans/license_squirrel.txt"
cp "$SQPATH/COPYRIGHT" "$REPODIR/simutrans/license_squirrel.txt"
cp "$SQPATH"/include/* .

cp "$SQPATH"/squirrel/*.h   squirrel/
cp "$SQPATH"/squirrel/*.cpp squirrel/


for i in *.h; do transform "$i"; done

cd squirrel
# rename
for i in *.cpp; do mv "$i" "${i/.cpp}".cc; done
# replace include <sq*.h> by include "../sq*.h"
for i in *.cc; do transform "$i"; done
for i in *.h; do transform "$i"; done
cd ..

cp "$SQPATH"/sqstdlib/*.h   sqstdlib/
cp "$SQPATH"/sqstdlib/*.cpp sqstdlib/

cd sqstdlib
# rename
for i in *.cpp; do mv "$i" "${i/.cpp}".cc; done
# replace include <sq*.h> by include "../sq*.h"
for i in *.cc; do transform "$i"; done
for i in *.h; do transform "$i"; done
cd ..

cd ..
# The imported files, and only those: update_squirrel.* and squirrel_modifications.diff
# are ours, and unrelated local changes must not be imported either.
imported=(squirrel/squirrel squirrel/sqstdlib squirrel/sq*.h ../simutrans/license_squirrel.txt)

# Ignore whitespace, so that our formatting is kept. Not -w though: -w also hides
# changes between no whitespace and some whitespace, and the resulting diff can
# then no longer be applied, neither by patch nor by git apply.
git diff --ignore-blank-lines --ignore-space-at-eol -b -- "${imported[@]}" > update_squirrel.diff

git checkout -- "${imported[@]}"

# git diff writes paths relative to the top of the repo, so patch from there.
# Read the patch with -i, otherwise a question of patch would eat it from stdin.
cd "$REPODIR"
patch --ignore-whitespace -p1 -i src/update_squirrel.diff < /dev/null
