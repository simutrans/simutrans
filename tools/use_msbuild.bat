rem ############# ARM only supports GDI or SDL3 #######################

call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
vcpkg integrate install

msbuild /m .\Simutrans-%1.vcxproj /t:Rebuild -p:Configuration=Release /p:platform=%2 /p:Configuration=Release
mkdir build\default
move "build\%1\Simutrans %1 Nightly.exe" build\default\sim.exe
