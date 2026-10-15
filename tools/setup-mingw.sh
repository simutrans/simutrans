#!/bin/bash

echo "First we update the system"
pacman -Syu
pacman -Syu

echo "Now installing dependencies"

# neccessary packets
pacman -S --noconfirm make autoconf pkg-config subversion zip unzip zstd
pacman -S --noconfirm $MINGW_PACKAGE_PREFIX-gcc $MINGW_PACKAGE_PREFIX-bzip2 $MINGW_PACKAGE_PREFIX-freetype $MINGW_PACKAGE_PREFIX-libpng $MINGW_PACKAGE_PREFIX-brotli $MINGW_PACKAGE_PREFIX-cmake

# optional for SLD2 builds:
pacman -S --noconfirm $MINGW_PACKAGE_PREFIX-SDL2

# optional for SLD3 builds (only 64 bit):
pacman -S --noconfirm $MINGW_PACKAGE_PREFIX-sdl3
if [ $? -eq 0 ];then
  # i686 need manual build
  rm -rf main.zip
  wget https://github.com/libsdl-org/SDL/archive/refs/heads/main.zip
  unzip -o main.zip
  cd SDL-main
  cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release -DSDL_STATIC=ON -DSDL_RENDER_D3D11=ON -DSDL_RENDER_D3D12=OFF -DSDL_OPENGLES=OFF
  cmake --build build -j$(($(nproc)+1))
  cmake --install build --prefix $MINGW_PREFIX

  cd ..
  rm -rf main.zip
  rm -rf SDL-main
fi

# optional for installer:
pacman -S --noconfirm $MINGW_PACKAGE_PREFIX-nsis

# optional: minupnpc
pacman -S --noconfirm $MINGW_PACKAGE_PREFIX-miniupnpc
if [ $? -eq 0 ];then
  # i686 need manual build
  rm -rf master.zip
  wget https://github.com/miniupnp/miniupnp/archive/master.zip
  unzip -o master.zip
  cd miniupnp-master/miniupnpc
  cat Makefile.mingw | sed 's|[ \t]wingenminiupnpcstrings.exe |'"$(printf '\t')"'./wingenminiupnpcstrings.exe |' >Makefile.mingw2
  make -f Makefile.mingw2
  cp libminiupnpc.a $MINGW_PREFIX/lib
  cp *.h $MINGW_PREFIX/lib
  mkdir -p $MINGW_PREFIX/include/miniupnpc
  cp *.h $MINGW_PREFIX/include/miniupnpc
  cp include/*.h $MINGW_PREFIX/include/miniupnpc

  cd ../..
  rm -rf master.zip
  rm -rf miniupnpc-master
fi

# there libbrotli has been fixed
exit 0

# libbrotli static is broken but needed for freetype
for f in libbrotlidec libbrotlienc libbrotlicommon; do
	mv "$MINGW_PREFIX/lib/$f-static.a" "$MINGW_PREFIX/lib/$f.a"
done

