#!/bin/bash

#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#

#
# This builds the release
# "-svn" updates languages and the installer sizes (not for cross-compiled ARM)
#
# should be called from the main directory "tools/build_windows_release.sh"
#

echo "=== Starting i686 (32-bit) Build ==="
MSYSTEM=MINGW32 bash --login -c '"$@"' _ tools/release_win.sh "$@"

echo "=== Starting x64 (64-bit) Build ==="
MSYSTEM=MINGW64 bash --login -c '"$@"' _ tools/release_win.sh "$@"

rm -rf build

echo "=== Starting arm64 Build by MSBuild ==="
cmd.exe //c "tools\\build_arm.bat"

rm -rf build
