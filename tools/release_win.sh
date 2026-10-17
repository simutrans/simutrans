#!/bin/bash

#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#

#
# This builds the release
# "-svn" updates languages and the isntaller sizes
# "-cross_arm" forces msbuild ARM64 crosscompile
#
# should be called from the main directory "tools/build_win.sh"
#


GDI="BACKEND:=gdi\n"
SDL2="BACKEND:=sdl2\n"
SDL3="BACKEND:=sdl3\n"

CONFIG="OSTYPE:=mingw\nMSG_LEVEL:=2\nOPTIMISE:=1\nSTATIC:=1\nWITH_REVISION:=1\nMULTI_THREAD:=1\nUSE_FREETYPE:=1\nUSE_UPNP:=1\nUSE_ZSTD:=1\n#LTO:=1\n"

# updating languages and installer?
svn_flag=false
for arg in "$@"; do
    if [ "$arg" = "-svn" ]; then
        svn_flag=true
        break # Schleife abbrechen, da die Option gefunden wurde
    fi
done

# First update languages
$svn_flag && tools/get_lang_files.sh -svn

# cross compile for ARM64
not_cross_ming=true
for arg in "$@"; do
    if [ "$arg" = "-cross" ]; then
        not_cross_ming=false
        break # Schleife abbrechen, da die Option gefunden wurde
    fi
done

echo "Find revision"

# then get the version number from simversion
while read -r _ name val _; do
	case "$name" in
		SIM_VERSION_MAJOR) maj=$val ;;
		SIM_VERSION_MINOR) min=$val ;;
		SIM_VERSION_PATCH) patch=$val ;;
	esac
done < <(grep "^#define SIM_VERSION_" src/simutrans/simversion.h)

# if patch is zero, no patch number
if [ "$patch" -eq 0 ]; then
    VERSION="${maj}-${min}"
else
    VERSION="${maj}-${min}-${patch}"
fi
WINVERSION="${maj}.${min}.${patch}"
echo "Version $VERSION"

# update installer version information
$svn_flag && sed -i "s|!define VERSION.*|!define VERSION \"0.$WINVERSION\"|" src/Windows/nsis/simutrans.nsi
$svn_flag && sed -i "s|!define SF_VERSION.*|!define SF_VERSION \"$VERSION\"|" src/Windows/nsis/simutrans.nsi
$svn_flag && sed -i "s|!define VERSION.*|!define VERSION \"0.$WINVERSION\"|" src/Windows/nsis/simutrans-noadmin.nsi
$svn_flag && sed -i "s|!define SF_VERSION.*|!define SF_VERSION \"$VERSION\"|" src/Windows/nsis/simutrans-noadmin.nsi

# save old config
make clean
mv config.default config.default_tmp


if [[ "$MINGW_PACKAGE_PREFIX" == *"x86_64"* ]]; then
  simarchivbase=simuwin-x64
  nsis_id=x64
  msbuild_id=x64
elif [[ "$MINGW_PACKAGE_PREFIX" == *"aarch64"* ]]; then
  simarchivbase=simuwin-arm
  nsis_id=arm
  msbuild_id=ARM64
else
  simarchivbase=simuwin
  nsis_id=win32
  msbuild_id=Win32
fi

# size of base files without executable
base_size=$(du -s -Bk simutrans | sed "s|K.*$||")

if $svn_flag; then
  echo "updating svn and nsis installer"
fi

# now build gdi
echo "$cross_arm"

echo -e "$GDI$CONFIG" > config.default
rm -rf build
$not_cross_ming  &&  make -j$(( $(nproc) + 1 ))
if [ ! -f "build/default/sim.exe" ]; then
  echo "Try GDI built by msbuild!"
  cmd.exe //c "tools\\use_msbuild.bat" GDI $msbuild_id
fi
if [ -f "build/default/sim.exe" ]; then
  strip build/default/sim.exe
  exe_size=$(du -s -Bk build/default/sim.exe | sed "s|K.*$||")
  tools/distribute.sh -no-lang
  mv "$simarchivbase-.zip" "$simarchivbase-$VERSION.zip"
  # Now output to nsh
  if [ $svn_flag ]; then
    total_size=$(($base_size + $exe_size))
	sed -i "s/  AddSize [0-9]* # $simarchivbase-size/  AddSize $total_size # $simarchivbase-size/" src/Windows/nsis/simutrans.nsh
  fi
else
  echo "GDI built failed!"
fi
make clean

# now build SDL2
echo -e "$SDL2$CONFIG" > config.default
rm -rf build
$not_cross_ming  &&  make -j$(( $(nproc) + 1 ))
if [ ! -f "build/default/sim.exe" ]; then
  echo "Try SDL2 built by msbuild!"
  cmd.exe //c "tools\\use_msbuild.bat" SDL2 $msbuild_id
fi
if [ -f "build/default/sim.exe" ]; then
  strip build/default/sim.exe
  exe_size=$(du -s -Bk build/default/sim.exe | sed "s|K.*$||")
  tools/distribute.sh -no-lang
  mv "$simarchivbase-sdl-.zip" "$simarchivbase-sdl-$VERSION.zip"
  if [ $svn_flag ]; then
    total_size=$(($base_size + $exe_size))
	sed -i "s/  AddSize [0-9]* # $simarchivbase-sdl-size/  AddSize $total_size # $simarchivbase-sdl-size/" src/Windows/nsis/simutrans.nsh
  fi
else
  echo "SDL2 built failed!"
fi
make clean

# now build SDL3
echo -e "$SDL3$CONFIG" > config.default
rm -rf build
$not_cross_ming  &&  make -j$(( $(nproc) + 1 ))
if [ ! -f "build/default/sim.exe" ]; then
  echo "Try SDL3 built by msbuild!"
  cmd.exe //c "tools\\use_msbuild.bat" SDL3 $msbuild_id
fi
if [ -f "build/default/sim.exe" ]; then
  strip build/default/sim.exe
  exe_size=$(du -s -Bk build/default/sim.exe | sed "s|K.*$||")
  tools/distribute.sh -no-lang
  mv "$simarchivbase-sdl3-.zip" "$simarchivbase-sdl3-$VERSION.zip"
  if [ $svn_flag ]; then
    total_size=$(($base_size + $exe_size))
	sed -i "s/  AddSize [0-9]* # $simarchivbase-sdl3-size/  AddSize $total_size # $simarchivbase-sdl3-size/" src/Windows/nsis/simutrans.nsh
  fi
else
  echo "SDL3 built failed!"
fi
make clean

# restore old config
mv config.default_tmp config.default
