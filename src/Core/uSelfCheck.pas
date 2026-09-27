unit uSelfCheck;

{ `MTN2.exe --self-check`: verifies that this copy of the program has
  everything it reads at run time, prints one line per check to stdout and
  exits with 0 (all present) or 1 -- before the single-instance handshake
  and before any window, so it runs headless on the release runner against
  a freshly unzipped package (src\tools\check-release.ps1).

  Checked:
  - the embedded RCDATA the app cannot start without (menu, default keymap,
    default theme, parent-up icon), and every DIALOG_* / STRINGS_* resource
    parses as JSON;
  - help\<locale>\index.md next to the exe for every locale the language
    picker offers (uStrings.AvailableLocales);
  - sk4d.dll loads (FMX renders through Skia);
  - every plugins\<id>\ has a parsable plugin.json naming that id and at
    least one module (*.dll / *.wasm / *.wat).
  wasmtime.dll is a warning, not a failure: without it only WASM plugins
  are skipped, exactly as package-release.ps1 treats it. }

interface

const
  cSelfCheckSwitch = '--self-check';

type
  TSelfCheckReport = TArray<string>;

function SelfCheckRequested: Boolean;
/// <summary>Runs every check against AAppDir (the folder holding MTN2.exe)
/// and this module's resources. Lines start with 'OK   ', 'WARN ' or
/// 'FAIL '. True when no line is a FAIL.</summary>
function RunSelfCheck(const AAppDir: string; out AReport: TSelfCheckReport): Boolean;
/// <summary>RunSelfCheck on the exe's own folder, report to stdout; returns
/// the process exit code.</summary>
function RunSelfCheckToStdOut: Integer;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils,
  System.JSON, uStrings, uPluginManifest;

const
  cRequiredResources: array[0..3] of string =
    ('MENU_MAIN', 'KEYMAP_DEFAULT', 'THEME_DEFAULT', 'ICON_PARENT_UP');

function SelfCheckRequested: Boolean;
var
  I: Integer;
begin
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), cSelfCheckSwitch) then
      Exit(True);
  Result := False;
end;

procedure Add(var AReport: TSelfCheckReport; const AStatus, AText: string);
begin
  AReport := AReport + [AStatus + ' ' + AText];
end;

function ResourceSize(const AName: string): Cardinal;
var
  Res: HRSRC;
begin
  Res := FindResource(HInstance, PChar(AName), RT_RCDATA);
  if Res = 0 then
    Exit(0);
  Result := SizeofResource(HInstance, Res);
end;

function ResourceText(const AName: string; out AText: string): Boolean;
var
  RS: TResourceStream;
  Bytes: TBytes;
begin
  AText := '';
  if FindResource(HInstance, PChar(AName), RT_RCDATA) = 0 then
    Exit(False);
  RS := TResourceStream.Create(HInstance, AName, RT_RCDATA);
  try
    SetLength(Bytes, RS.Size);
    if RS.Size > 0 then
      RS.ReadBuffer(Bytes[0], RS.Size);
  finally
    RS.Free;
  end;
  AText := TEncoding.UTF8.GetString(Bytes);
  if (AText <> '') and (Ord(AText[1]) = $FEFF) then
    Delete(AText, 1, 1);
  Result := True;
end;

function IsJsonObject(const AText: string): Boolean;
var
  Val: TJSONValue;
begin
  Val := TJSONObject.ParseJSONValue(AText);
  try
    Result := Val is TJSONObject;
  finally
    Val.Free;
  end;
end;

function EnumResNameProc(AModule: HMODULE; AType, AName: PChar;
  AParam: NativeInt): BOOL; stdcall;
begin
  // Named resources only; an integer id arrives as a pointer below 64K.
  if (NativeUInt(AName) shr 16) <> 0 then
    TStringList(AParam).Add(UpperCase(AName));
  Result := True;
end;

procedure CheckResources(var AReport: TSelfCheckReport);
var
  Names: TStringList;
  Name, Text: string;
  Dialogs, Locales: Integer;
begin
  // Presence only: ICON_PARENT_UP is a PNG, the JSON ones are parsed by
  // their own loaders (and DIALOG_* / STRINGS_* just below).
  for Name in cRequiredResources do
    if ResourceSize(Name) > 0 then
      Add(AReport, 'OK  ', 'resource ' + Name)
    else
      Add(AReport, 'FAIL', 'resource ' + Name + ' is not embedded');

  Dialogs := 0;
  Locales := 0;
  Names := TStringList.Create;
  try
    EnumResourceNames(HInstance, RT_RCDATA, @EnumResNameProc, NativeInt(Names));
    for Name in Names do
    begin
      if Name.StartsWith('DIALOG_') then
        Inc(Dialogs)
      else if Name.StartsWith('STRINGS_') then
        Inc(Locales)
      else
        Continue;
      try
        if not (ResourceText(Name, Text) and IsJsonObject(Text)) then
          Add(AReport, 'FAIL', 'resource ' + Name + ' is not a JSON object');
      except
        on E: Exception do
          Add(AReport, 'FAIL', 'resource ' + Name + ': ' + E.Message);
      end;
    end;
  finally
    Names.Free;
  end;
  if Dialogs = 0 then
    Add(AReport, 'FAIL', 'no DIALOG_* resources embedded')
  else
    Add(AReport, 'OK  ', Format('%d dialog resources, %d embedded locales', [Dialogs, Locales]));
end;

procedure CheckHelp(const AAppDir: string; var AReport: TSelfCheckReport);
var
  Locale, Index: string;
begin
  for Locale in AvailableLocales do
  begin
    Index := TPath.Combine(TPath.Combine(TPath.Combine(AAppDir, 'help'),
      LowerCase(Locale)), 'index.md');
    if TFile.Exists(Index) then
      Add(AReport, 'OK  ', 'help\' + LowerCase(Locale) + '\index.md')
    else
      Add(AReport, 'FAIL', 'help\' + LowerCase(Locale) + '\index.md is missing');
  end;
end;

procedure CheckDll(const AAppDir, AName: string; ARequired: Boolean;
  var AReport: TSelfCheckReport);
var
  Path: string;
  Handle: HMODULE;
begin
  Path := TPath.Combine(AAppDir, AName);
  Handle := 0;
  if TFile.Exists(Path) then
    Handle := LoadLibrary(PChar(Path));
  if Handle <> 0 then
  begin
    FreeLibrary(Handle);
    Add(AReport, 'OK  ', AName);
  end
  else if ARequired then
    Add(AReport, 'FAIL', AName + ' is missing or does not load')
  else
    Add(AReport, 'WARN', AName + ' is missing or does not load');
end;

procedure CheckPlugins(const AAppDir: string; var AReport: TSelfCheckReport);
var
  Root, Dir, Id, Ext, FileName: string;
  Manifest: TPluginManifest;
  Modules: Integer;
begin
  Root := TPath.Combine(AAppDir, 'plugins');
  if not TDirectory.Exists(Root) then
  begin
    Add(AReport, 'FAIL', 'plugins\ is missing');
    Exit;
  end;
  for Dir in TDirectory.GetDirectories(Root) do
  begin
    Id := ExtractFileName(Dir);
    if not TryReadPluginManifest(Dir, Manifest) then
    begin
      Add(AReport, 'FAIL', 'plugins\' + Id + '\plugin.json is missing or invalid');
      Continue;
    end;
    if not SameText(Manifest.Id, Id) then
    begin
      Add(AReport, 'FAIL', Format('plugins\%s\plugin.json names id "%s"', [Id, Manifest.Id]));
      Continue;
    end;
    Modules := 0;
    for FileName in TDirectory.GetFiles(Dir) do
    begin
      Ext := LowerCase(TPath.GetExtension(FileName));
      if (Ext = '.dll') or (Ext = '.wasm') or (Ext = '.wat') then
        Inc(Modules);
    end;
    if Modules = 0 then
      Add(AReport, 'FAIL', 'plugins\' + Id + '\ has no module (*.dll, *.wasm, *.wat)')
    else
      Add(AReport, 'OK  ', 'plugin ' + Id);
  end;
end;

function RunSelfCheck(const AAppDir: string; out AReport: TSelfCheckReport): Boolean;
var
  Line: string;
  Step: Integer;
begin
  AReport := nil;
  // Each group on its own, so one raising doesn't hide the others' results.
  for Step := 0 to 4 do
    try
      case Step of
        0: CheckResources(AReport);
        1: CheckHelp(AAppDir, AReport);
        2: CheckDll(AAppDir, 'sk4d.dll', True, AReport);
        3: CheckDll(AAppDir, 'wasmtime.dll', False, AReport);
        4: CheckPlugins(AAppDir, AReport);
      end;
    except
      on E: Exception do
        Add(AReport, 'FAIL', E.ClassName + ': ' + E.Message);
    end;
  Result := True;
  for Line in AReport do
    if Line.StartsWith('FAIL') then
      Result := False;
end;

procedure WriteStdOut(const AText: string);
var
  Handle: THandle;
  Bytes: TBytes;
  Written: DWORD;
begin
  // A GUI-subsystem exe has no console of its own: stdout is whatever the
  // caller redirected, else the parent's console if there is one.
  Handle := GetStdHandle(STD_OUTPUT_HANDLE);
  if (Handle = 0) or (Handle = INVALID_HANDLE_VALUE) then
  begin
    if not AttachConsole(ATTACH_PARENT_PROCESS) then
      Exit;
    Handle := GetStdHandle(STD_OUTPUT_HANDLE);
    if (Handle = 0) or (Handle = INVALID_HANDLE_VALUE) then
      Exit;
  end;
  Bytes := TEncoding.UTF8.GetBytes(AText);
  if Length(Bytes) > 0 then
    WriteFile(Handle, Bytes[0], Length(Bytes), Written, nil);
end;

function RunSelfCheckToStdOut: Integer;
var
  Report: TSelfCheckReport;
  Ok: Boolean;
begin
  Ok := RunSelfCheck(ExtractFileDir(ParamStr(0)), Report);
  if Ok then
    Report := Report + ['self-check passed']
  else
    Report := Report + ['self-check FAILED'];
  WriteStdOut(string.Join(sLineBreak, Report) + sLineBreak);
  if Ok then
    Result := 0
  else
    Result := 1;
end;

end.
