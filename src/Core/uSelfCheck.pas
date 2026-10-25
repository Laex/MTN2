unit uSelfCheck;

{ `MTN2.exe --self-check`: verifies that this copy of the program has
  everything it reads at run time, prints one line per check to stdout and
  exits with 0 (all present) or 1 -- before the single-instance handshake
  and before any window, so it runs headless on the release runner against
  a freshly unzipped package (src\tools\check-release.ps1).

  Checked:
  - the embedded RCDATA the app cannot start without (menu, default keymap,
    default theme, parent-up icon), and every DIALOG_* resource parses as
    JSON;
  - the language packs under resource\: help\index.md for English, and for
    every other folder a locale.json whose version matches the program
    (an older one is a warning, a newer or unreadable one a failure), a
    strings.json and help\index.md;
  - the shipped themes under resource\themes: each *.theme.json parses (an
    unparsable one fails, a missing folder leaves only the embedded default
    theme and is a warning);
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
  System.SysUtils, System.Classes, System.IOUtils,
  System.JSON, uStrings, uPluginManifest, uResourceAccess, uPlatformInfo,
  uThemeSpec;

const
  cRequiredResources: array[0..4] of string =
    ('MENU_MAIN', 'KEYMAP_DEFAULT', 'THEME_NDN', 'ICON_PARENT_UP', 'RESOURCE_VERSION');

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
  RS: TStream;
begin
  RS := OpenRcData(AName);
  if RS = nil then
    Exit(0);
  try
    Result := RS.Size;
  finally
    RS.Free;
  end;
end;

function ResourceText(const AName: string; out AText: string): Boolean;
var
  RS: TStream;
  Bytes: TBytes;
begin
  AText := '';
  RS := OpenRcData(AName);
  if RS = nil then
    Exit(False);
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

procedure CheckResources(var AReport: TSelfCheckReport);
var
  Names: TStringList;
  Name, Text: string;
  Dialogs: Integer;
begin
  // Presence only: ICON_PARENT_UP is a PNG, the JSON ones are parsed by
  // their own loaders (and DIALOG_* just below).
  for Name in cRequiredResources do
    if ResourceSize(Name) > 0 then
      Add(AReport, 'OK  ', 'resource ' + Name)
    else
      Add(AReport, 'FAIL', 'resource ' + Name + ' is not embedded');

  Dialogs := 0;
  Names := TStringList.Create;
  try
    ListRcDataNames('', Names);
    for Name in Names do
    begin
      if not Name.StartsWith('DIALOG_') then
        Continue;
      Inc(Dialogs);
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
    Add(AReport, 'OK  ', Format('%d dialog resources', [Dialogs]));
end;

procedure CheckHelpIndex(const AAppDir, ALocale: string; var AReport: TSelfCheckReport);
var
  Rel: string;
begin
  Rel := 'resource' + PathDelim + ALocale + PathDelim + 'help' + PathDelim + 'index.md';
  if TFile.Exists(TPath.Combine(AAppDir, Rel)) then
    Add(AReport, 'OK  ', Rel)
  else
    Add(AReport, 'FAIL', Rel + ' is missing');
end;

procedure CheckLocalePacks(const AAppDir: string; var AReport: TSelfCheckReport);
var
  Root, Locale, Rel: string;
  Info: TLocalePackInfo;
  Expected: Integer;
begin
  Root := TPath.Combine(AAppDir, 'resource');
  Expected := ResourceVersion;
  CheckHelpIndex(AAppDir, 'en', AReport);
  if not TDirectory.Exists(Root) then
  begin
    Add(AReport, 'FAIL', 'resource' + PathDelim + ' is missing');
    Exit;
  end;
  for Locale in TDirectory.GetDirectories(Root) do
  begin
    // resource\themes holds the shipped themes, not a language.
    if SameText(ExtractFileName(Locale), 'themes') then
      Continue;
    Info := InspectLocalePack(Root, ExtractFileName(Locale), Expected);
    if Info.Locale = 'en' then
      Continue;
    Rel := 'resource' + PathDelim + Info.Locale + PathDelim;
    case Info.Status of
      lpsMissing:
        Add(AReport, 'FAIL', Rel + 'locale.json is missing');
      lpsInvalid:
        Add(AReport, 'FAIL', Rel + 'locale.json is not {"version": N}');
      lpsNewer:
        Add(AReport, 'FAIL', Format('%slocale.json version %d is newer than the program (%d): pack ignored',
          [Rel, Info.Version, Expected]));
      lpsOlder, lpsCurrent:
      begin
        if Info.Status = lpsOlder then
          Add(AReport, 'WARN', Format('%slocale.json version %d is older than the program (%d): missing keys show English',
            [Rel, Info.Version, Expected]))
        else
          Add(AReport, 'OK  ', Rel + 'locale.json version ' + IntToStr(Info.Version));
        if TFile.Exists(TPath.Combine(Info.Dir, 'strings.json')) then
          Add(AReport, 'OK  ', Rel + 'strings.json')
        else
          Add(AReport, 'FAIL', Rel + 'strings.json is missing');
        CheckHelpIndex(AAppDir, Info.Locale, AReport);
      end;
    end;
  end;
end;

procedure CheckShippedThemes(const AAppDir: string; var AReport: TSelfCheckReport);
var
  Dir, FileName, Text, Err, Rel: string;
  Doc: TThemeDoc;
  Count: Integer;
begin
  Dir := TPath.Combine(TPath.Combine(AAppDir, 'resource'), 'themes');
  Rel := 'resource' + PathDelim + 'themes' + PathDelim;
  if not TDirectory.Exists(Dir) then
  begin
    Add(AReport, 'WARN', Rel + ' is missing: only the default theme is available');
    Exit;
  end;
  Count := 0;
  for FileName in TDirectory.GetFiles(Dir, '*' + cThemeFileExt) do
  begin
    Text := '';
    try
      Text := TFile.ReadAllText(FileName, TEncoding.UTF8);
    except
      Text := '';
    end;
    if (Trim(Text) <> '') and TryParseThemeDoc(Text, Doc, Err) then
      Inc(Count)
    else
      Add(AReport, 'FAIL', Rel + ExtractFileName(FileName) + ' is not a valid theme file');
  end;
  Add(AReport, 'OK  ', Format('%d shipped themes', [Count]));
end;

procedure CheckDll(const AAppDir, AName: string; ARequired: Boolean;
  var AReport: TSelfCheckReport);
var
  Path: string;
  Loads: Boolean;
begin
  Path := TPath.Combine(AAppDir, AName);
  Loads := TFile.Exists(Path) and PlatformCanLoadLibrary(Path);
  if Loads then
    Add(AReport, 'OK  ', AName)
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
    Add(AReport, 'FAIL', 'plugins' + PathDelim + ' is missing');
    Exit;
  end;
  for Dir in TDirectory.GetDirectories(Root) do
  begin
    Id := ExtractFileName(Dir);
    if not TryReadPluginManifest(Dir, Manifest) then
    begin
      Add(AReport, 'FAIL', 'plugins' + PathDelim + Id + PathDelim + 'plugin.json is missing or invalid');
      Continue;
    end;
    if not SameText(Manifest.Id, Id) then
    begin
      Add(AReport, 'FAIL', Format('plugins%s%s%splugin.json names id "%s"', [PathDelim, Id, PathDelim, Manifest.Id]));
      Continue;
    end;
    Modules := 0;
    for FileName in TDirectory.GetFiles(Dir) do
    begin
      Ext := LowerCase(TPath.GetExtension(FileName));
      if (Ext = PlatformSharedLibExt) or (Ext = '.wasm') or (Ext = '.wat') then
        Inc(Modules);
    end;
    if Modules = 0 then
      Add(AReport, 'FAIL', 'plugins' + PathDelim + Id + PathDelim + ' has no module (*' + PlatformSharedLibExt + ', *.wasm, *.wat)')
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
  for Step := 0 to 5 do
    try
      case Step of
        0: CheckResources(AReport);
        1: CheckLocalePacks(AAppDir, AReport);
        2:
          if PlatformRenderLibrary <> '' then
            CheckDll(AAppDir, PlatformRenderLibrary, True, AReport);
        3: CheckDll(AAppDir, PlatformSharedLibName('wasmtime'), False, AReport);
        4: CheckPlugins(AAppDir, AReport);
        5: CheckShippedThemes(AAppDir, AReport);
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

function RunSelfCheckToStdOut: Integer;
var
  Report: TSelfCheckReport;
  Ok: Boolean;
begin
  Ok := RunSelfCheck(ExtractFileDir(PlatformExePath), Report);
  if Ok then
    Report := Report + ['self-check passed']
  else
    Report := Report + ['self-check FAILED'];
  PlatformWriteStdOut(string.Join(sLineBreak, Report) + sLineBreak);
  if Ok then
    Result := 0
  else
    Result := 1;
end;

end.
