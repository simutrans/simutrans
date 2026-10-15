Section /o "Executable (GDI)" GDIexe
  AddSize 111 # simuwin-size
  StrCpy $downloadlink "http://downloads.sourceforge.net/project/simutrans/simutrans/${SF_VERSION}/simuwin-${SF_VERSION}.zip"
  StrCpy $archievename "simuwin-${SF_VERSION}.zip"
  StrCpy $downloadname "nodelete"
  SetOutPath $INSTDIR
  Call DownloadInstallZip
  Call PostExeInstall
SectionEnd

Section "Executable (SDL2)" SDLexe
  AddSize 23728 # simuwin-sdl-size
  StrCpy $downloadlink "http://downloads.sourceforge.net/project/simutrans/simutrans/${SF_VERSION}/simuwin-sdl-${SF_VERSION}.zip"
  StrCpy $archievename "simuwin-sdl-${SF_VERSION}.zip"
  StrCpy $downloadname "nodelete"
  SetOutPath $INSTDIR
  Call DownloadInstallZip
  Call PostExeInstall
SectionEnd

Section /o "Executable (GDI 64bit)" GDI64exe
  AddSize 20728 # simuwin-x64-size
  StrCpy $downloadlink "http://downloads.sourceforge.net/project/simutrans/simutrans/${SF_VERSION}/simuwin-x64-${SF_VERSION}.zip"
  StrCpy $archievename "simuwin-x64-${SF_VERSION}.zip"
  StrCpy $downloadname "nodelete"
  SetOutPath $INSTDIR
  Call DownloadInstallZip
  Call PostExeInstall
SectionEnd

Section /o "Executable (SDL2 64bit)" SDL64exe
  AddSize 22936 # simuwin-x64-sdl-size
  StrCpy $downloadlink "http://downloads.sourceforge.net/project/simutrans/simutrans/${SF_VERSION}/simuwin-x64-sdl-${SF_VERSION}.zip"
  StrCpy $archievename "simuwin-x64-sdl-${SF_VERSION}.zip"
  StrCpy $downloadname "nodelete"
  SetOutPath $INSTDIR
  Call DownloadInstallZip
  Call PostExeInstall
SectionEnd

Section /o "Executable (SDL3 64bit beta)" SDL364exe
  AddSize 24573
  StrCpy $downloadlink "http://downloads.sourceforge.net/project/simutrans/simutrans/${SF_VERSION}/simuwin-x64-${SF_VERSION}.zip"
  StrCpy $archievename "simuwin-x64-${SF_VERSION}.zip"
  StrCpy $downloadname "nodelete"
  SetOutPath $INSTDIR
  Call DownloadInstallZip
  Call PostExeInstall
SectionEnd