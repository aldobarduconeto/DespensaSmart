[Setup]
AppId=DespensaSmart
AppName=DespensaSmart
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\DespensaSmart
DefaultGroupName=DespensaSmart
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\installer
OutputBaseFilename=DespensaSmart-Setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\despensa_smart.exe
WizardStyle=modern

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\DespensaSmart"; Filename: "{app}\despensa_smart.exe"
