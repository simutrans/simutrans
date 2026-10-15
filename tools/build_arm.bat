rem ############# ARM only supports GDI or SDL3 #######################

call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
vcpkg integrate install

msbuild /m .\Simutrans-GDI.vcxproj /t:Rebuild -p:Configuration=Release /p:platform=ARM64 /p:Configuration=Release
move "build\GDI\Simutrans GDI Nightly.exe" simutrans\simutrans.exe
powershell Compress-Archive -Path "simutrans" -DestinationPath "simuwin-arm.zip" -Force

msbuild /m .\Simutrans-SDL3.vcxproj /t:Rebuild -p:Configuration=Release /p:platform=ARM64 /p:Configuration=Release
move "build\SDL3\Simutrans SDL3 Nightly.exe" simutrans\simutrans.exe
powershell Compress-Archive -Path "simutrans" -DestinationPath "simuwin-arm-sdl3.zip" -Force

echo "Please update installer and version number manually!"
