; Instalador do PegaMídia para Windows (Inno Setup 6).
; Gerado pelo GitHub Actions:  ISCC.exe /DVersao=1.0.0 desktop\instalador.iss
; Instala só para o usuário atual (não pede senha de administrador).

#ifndef Versao
  #define Versao "1.0.0"
#endif

[Setup]
AppId={{6F2B8B9E-3D0C-4C5E-9E83-2B5C1A7D9F41}
AppName=PegaMídia
AppVersion={#Versao}
AppVerName=PegaMídia {#Versao}
AppPublisher=Projeto escolar PegaMídia (sem fins comerciais)
AppPublisherURL=https://github.com/Hiagogsantos/pegamidia
DefaultDirName={localappdata}\Programs\PegaMidia
DefaultGroupName=PegaMídia
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=PegaMidia-Instalador-{#Versao}
SetupIconFile=pegamidia.ico
UninstallDisplayIcon={app}\PegaMidia.exe
UninstallDisplayName=PegaMídia
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Languages]
Name: "pt"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "atalho"; Description: "Criar atalho na Área de Trabalho"; GroupDescription: "Atalhos:"

[Files]
Source: "..\dist\PegaMidia\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\PegaMídia"; Filename: "{app}\PegaMidia.exe"
Name: "{autodesktop}\PegaMídia"; Filename: "{app}\PegaMidia.exe"; Tasks: atalho

[Run]
Filename: "{app}\PegaMidia.exe"; Description: "Abrir o PegaMídia agora"; Flags: nowait postinstall skipifsilent
