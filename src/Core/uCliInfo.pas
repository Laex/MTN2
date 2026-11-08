unit uCliInfo;

{ Command-line switches that print information and exit, without a window and
  before the single-instance handshake:

    --version                 program version
    --paths                   program, settings, plugin, resource and theme folders
    --list-commands           every built-in command with its context and keys
    --list-plugins            installed plugins and whether each is switched off
    --check-keymap [FILE]     validates keymap.json (or FILE); exit 1 on errors
    --export-theme [ID]       writes a theme as JSON; without an id lists them
    --shell-init SHELL        prints a function for bash, zsh, fish or powershell
                              that runs the program and then changes the shell
                              to the folder of the active panel

  The function passes `--cd-file FILE`; on exit the program writes the folder
  of the active panel to FILE (WriteCdFile), which the function reads back.

  Output is plain ASCII lines (the keymap and theme JSON aside), one fact per
  line, so it can be piped and diffed. The functions return their lines through
  a writer so the tests read them without a console. }

interface

type
  TCliInfoCommand = (cicNone, cicVersion, cicPaths, cicListCommands,
    cicListPlugins, cicCheckKeymap, cicExportTheme, cicShellInit);

  TCliLineWriter = reference to procedure(const ALine: string);

const
  cVersionSwitch = '--version';
  cPathsSwitch = '--paths';
  cListCommandsSwitch = '--list-commands';
  cListPluginsSwitch = '--list-plugins';
  cCheckKeymapSwitch = '--check-keymap';
  cExportThemeSwitch = '--export-theme';
  cShellInitSwitch = '--shell-init';
  cCdFileSwitch = '--cd-file';

/// <summary>True when AArgs hold one of the information switches; AArgument
/// is the word after it (a file or theme id) when that word is not another
/// switch, '' otherwise.</summary>
function CliInfoRequested(const AArgs: TArray<string>; out ACommand: TCliInfoCommand;
  out AArgument: string): Boolean;

/// <summary>The same on the process command line.</summary>
function CliInfoRequestedOnCommandLine(out ACommand: TCliInfoCommand;
  out AArgument: string): Boolean;

/// <summary>Runs the command and writes its lines to AWrite; the result is the
/// process exit code (0 ok, 1 a check failed or the argument names nothing).</summary>
function RunCliInfo(ACommand: TCliInfoCommand; const AArgument: string;
  const AWrite: TCliLineWriter): Integer;

/// <summary>Checks the text of a keymap file: unknown actions, unrecognized
/// keys, and chords that two actions of one context share. Lines start with
/// 'OK   ', 'WARN ' or 'FAIL '. True when no line is a FAIL.</summary>
function CheckKeymapText(const AJsonText: string; out AReport: TArray<string>): Boolean;

/// <summary>The "plugins" folder next to the program.</summary>
function CliPluginsDirectory: string;

/// <summary>The function definition for AShell (bash, zsh, fish, powershell)
/// that starts AExe and changes the shell to the folder the program leaves in
/// the --cd-file it is given. False for another shell name.</summary>
function ShellInitLines(const AShell, AExe: string; out ALines: TArray<string>): Boolean;

/// <summary>The FILE after --cd-file (or in --cd-file=FILE) among AArgs, '' when absent.</summary>
function CdFileOfArgs(const AArgs: TArray<string>): string;
function CdFileOnCommandLine: string;

/// <summary>Writes ADir to AFile as plain UTF-8 without a line break, for a
/// shell function to read; nothing when either is empty or the file cannot be
/// written.</summary>
procedure WriteCdFile(const AFile, ADir: string);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.TypInfo,
  System.Generics.Collections, uKeymap, uConfigLocation, uStrings, uPlatformInfo, uUpdater,
  uPluginManifest, uThemeRegistry, uThemeSpec;

const
  cDisabledPluginsFile = 'disabled-plugins.json';
  cPathNameWidth = 12;

function SwitchOf(const AArg: string; out ACommand: TCliInfoCommand): Boolean;
begin
  Result := True;
  if SameText(AArg, cVersionSwitch) then
    ACommand := cicVersion
  else if SameText(AArg, cPathsSwitch) then
    ACommand := cicPaths
  else if SameText(AArg, cListCommandsSwitch) then
    ACommand := cicListCommands
  else if SameText(AArg, cListPluginsSwitch) then
    ACommand := cicListPlugins
  else if SameText(AArg, cCheckKeymapSwitch) then
    ACommand := cicCheckKeymap
  else if SameText(AArg, cExportThemeSwitch) then
    ACommand := cicExportTheme
  else if SameText(AArg, cShellInitSwitch) then
    ACommand := cicShellInit
  else
    Result := False;
end;

function CliInfoRequested(const AArgs: TArray<string>; out ACommand: TCliInfoCommand;
  out AArgument: string): Boolean;
var
  I: Integer;
begin
  ACommand := cicNone;
  AArgument := '';
  for I := 0 to High(AArgs) do
    if SwitchOf(AArgs[I], ACommand) then
    begin
      if (I < High(AArgs)) and not AArgs[I + 1].StartsWith('-') then
        AArgument := AArgs[I + 1];
      Exit(True);
    end;
  Result := False;
end;

function CliInfoRequestedOnCommandLine(out ACommand: TCliInfoCommand;
  out AArgument: string): Boolean;
var
  Args: TArray<string>;
  I: Integer;
begin
  SetLength(Args, ParamCount);
  for I := 1 to ParamCount do
    Args[I - 1] := ParamStr(I);
  Result := CliInfoRequested(Args, ACommand, AArgument);
end;

function CliPluginsDirectory: string;
begin
  Result := TPath.Combine(ProgramDirectory, 'plugins');
end;

function PathLine(const AName, AValue: string): string;
begin
  Result := AName.PadRight(cPathNameWidth) + AValue;
end;

procedure WritePaths(const AWrite: TCliLineWriter);
var
  Mode: string;
begin
  if ConfigDirectoryIsOverridden then
    Mode := 'MTN2_CONFIG_DIR'
  else if IsPortableMode then
    Mode := 'portable'
  else
    Mode := 'standard';
  AWrite(PathLine('program', PlatformExePath));
  AWrite(PathLine('config', GetConfigDirectory));
  AWrite(PathLine('config-mode', Mode));
  AWrite(PathLine('keymap', GetDefaultKeymapPath));
  AWrite(PathLine('plugins', CliPluginsDirectory));
  AWrite(PathLine('resources', ResourceRoot));
  AWrite(PathLine('themes', ShippedThemesDirectory));
  AWrite(PathLine('user-themes', UserThemesDirectory));
end;

function ContextName(AAction: TKeymapAction): string;
begin
  Result := GetEnumName(TypeInfo(TKeymapContext), Ord(KeymapActionContext(AAction)));
  if Result.StartsWith('kc') then
    Delete(Result, 1, 2);
end;

procedure WriteCommands(const AWrite: TCliLineWriter);
var
  Profile: TKeymapProfile;
  Act: TKeymapAction;
  Name: string;
begin
  Profile := ActiveKeymap;
  for Act := Low(TKeymapAction) to High(TKeymapAction) do
  begin
    Name := KeymapActionDisplayName(Act);
    if (Act = kaNone) or (Name = '') then
      Continue;
    AWrite(Name.PadRight(28) + ContextName(Act).PadRight(10) +
      BindingsToStr(Profile.Bindings[Act]));
  end;
end;

procedure WritePlugins(const AWrite: TCliLineWriter);
var
  Dirs: TArray<string>;
  Disabled: TArray<string>;
  Dir, Id, Line: string;
  Manifest: TPluginManifest;
  Off: Boolean;
  I: Integer;
begin
  if not TDirectory.Exists(CliPluginsDirectory) then
    Exit;
  if not TryReadDisabledPlugins(GetConfigFilePath(cDisabledPluginsFile), Disabled) then
    Disabled := nil;
  Dirs := TDirectory.GetDirectories(CliPluginsDirectory);
  TArray.Sort<string>(Dirs);
  for Dir in Dirs do
  begin
    Id := ExtractFileName(Dir);
    Off := False;
    for I := 0 to High(Disabled) do
      if SameText(Disabled[I], Id) then
        Off := True;
    Line := Id.PadRight(24);
    if TryReadPluginManifest(Dir, Manifest) then
      Line := Line + Manifest.Version.PadRight(10) + Manifest.Name
    else
      Line := Line + '(no plugin.json)';
    if Off then
      Line := Line + '  [disabled]';
    AWrite(TrimRight(Line));
  end;
end;

function FormatBinding(const ABinding: TKeyBinding): string;
begin
  Result := KeyBindingToStr(ABinding);
end;

function CheckKeymapText(const AJsonText: string; out AReport: TArray<string>): Boolean;
var
  Report: TArray<string>;
  Failed: Boolean;
  Root: TJSONValue;
  Bindings: TJSONObject;
  Pair: TJSONPair;
  Items: TArray<TJSONValue>;
  Item: TJSONValue;
  Act, Other: TKeymapAction;
  Profile: TKeymapProfile;
  Named: set of TKeymapAction;
  Key: string;
  I, J, K: Integer;

  procedure Add(const AStatus, AText: string);
  begin
    Report := Report + [AStatus + ' ' + AText];
    if AStatus = 'FAIL' then
      Failed := True;
  end;

begin
  Report := nil;
  Failed := False;
  Named := [];
  Root := nil;
  try
    try
      Root := TJSONObject.ParseJSONValue(AJsonText);
    except
      Root := nil;
    end;
    if not (Root is TJSONObject) then
      Add('FAIL', 'the file is not a JSON object')
    else if not (TJSONObject(Root).Values['bindings'] is TJSONObject) then
      Add('WARN', 'no "bindings" object: the file changes no keys')
    else
    begin
      Bindings := TJSONObject(TJSONObject(Root).Values['bindings']);
      for I := 0 to Bindings.Count - 1 do
      begin
        Pair := Bindings.Pairs[I];
        if not TryKeymapActionByName(Pair.JsonString.Value, Act) then
        begin
          Add('FAIL', 'unknown action "' + Pair.JsonString.Value + '"');
          Continue;
        end;
        Include(Named, Act);
        if Pair.JsonValue is TJSONArray then
        begin
          SetLength(Items, TJSONArray(Pair.JsonValue).Count);
          for J := 0 to High(Items) do
            Items[J] := TJSONArray(Pair.JsonValue).Items[J];
        end
        else if Pair.JsonValue is TJSONObject then
          Items := [Pair.JsonValue]
        else
        begin
          Add('FAIL', Pair.JsonString.Value + ': expected a binding object or a list of them');
          Continue;
        end;
        for Item in Items do
        begin
          if not (Item is TJSONObject) or not (TJSONObject(Item).Values['key'] is TJSONString) then
          begin
            Add('FAIL', Pair.JsonString.Value + ': a binding needs a "key" string');
            Continue;
          end;
          Key := TJSONObject(Item).Values['key'].Value;
          if StringToVK(Key) = 0 then
            Add('FAIL', Pair.JsonString.Value + ': unrecognized key "' + Key + '"');
          for Key in ['shift', 'alt', 'ctrl'] do
            if (TJSONObject(Item).Values[Key] <> nil) and
               not (TJSONObject(Item).Values[Key] is TJSONBool) then
              Add('WARN', Pair.JsonString.Value + ': "' + Key + '" should be true or false');
        end;
      end;
    end;
  finally
    Root.Free;
  end;

  if not Failed and (Named <> []) then
  begin
    Profile := LoadDefaultKeymapProfile;
    if MergeKeymapJson(AJsonText, Profile) then
      for Act in Named do
        for Other := Low(TKeymapAction) to High(TKeymapAction) do
          if (Other <> Act) and (Other <> kaNone) and
             (KeymapActionContext(Other) = KeymapActionContext(Act)) and
             ((Other > Act) or not (Other in Named)) then
            for J := 0 to High(Profile.Bindings[Act]) do
              for K := 0 to High(Profile.Bindings[Other]) do
                if SameKeyBinding(Profile.Bindings[Act][J], Profile.Bindings[Other][K]) then
                  Add('WARN', FormatBinding(Profile.Bindings[Act][J]) + ' is bound to both ' +
                    KeymapActionDisplayName(Act) + ' and ' + KeymapActionDisplayName(Other));
  end;

  if not Failed and (Length(Report) = 0) then
    Add('OK  ', 'the keymap is valid');
  AReport := Report;
  Result := not Failed;
end;

function RunCheckKeymap(const AFile: string; const AWrite: TCliLineWriter): Integer;
var
  Path, Line: string;
  Report: TArray<string>;
begin
  Path := AFile;
  if Path = '' then
    Path := GetDefaultKeymapPath;
  if not TFile.Exists(Path) then
  begin
    if AFile = '' then
    begin
      AWrite('OK   no keymap file at ' + Path + ': the built-in keys apply');
      Exit(0);
    end;
    AWrite('FAIL ' + Path + ' does not exist');
    Exit(1);
  end;
  Result := 0;
  if not CheckKeymapText(TFile.ReadAllText(Path, TEncoding.UTF8), Report) then
    Result := 1;
  for Line in Report do
    AWrite(Line);
end;

function RunExportTheme(const AId: string; const AWrite: TCliLineWriter): Integer;
var
  Doc: TThemeDoc;
  Info: TThemeInfo;
begin
  if AId = '' then
  begin
    for Info in GetAvailableThemes do
      AWrite(Info.Id);
    Exit(0);
  end;
  if not TryLoadThemeDoc(AId, Doc) then
  begin
    AWrite('FAIL no theme "' + AId + '"; --export-theme alone lists the ids');
    Exit(1);
  end;
  AWrite(ThemeDocToJson(Doc));
  Result := 0;
end;

function ShSingleQuote(const AText: string): string;
begin
  Result := '''' + AText.Replace('''', '''\''''') + '''';
end;

function PsSingleQuote(const AText: string): string;
begin
  Result := '''' + AText.Replace('''', '''''') + '''';
end;

function ShellInitLines(const AShell, AExe: string; out ALines: TArray<string>): Boolean;
var
  Exe: string;
begin
  Result := True;
  if SameText(AShell, 'bash') or SameText(AShell, 'zsh') then
  begin
    Exe := ShSingleQuote(AExe);
    // Under Git Bash / MSYS the program is a Windows one: it gets and writes
    // Windows paths, which cygpath converts.
    ALines := [
      'mtn() {',
      '  local f d',
      '  f="$(mktemp)" || return',
      '  if command -v cygpath >/dev/null 2>&1; then',
      '    ' + Exe + ' --cd-file "$(cygpath -w "$f")" "$@"',
      '    d="$(cygpath -u "$(cat -- "$f")" 2>/dev/null)"',
      '  else',
      '    ' + Exe + ' --cd-file "$f" "$@"',
      '    d="$(cat -- "$f")"',
      '  fi',
      '  rm -f -- "$f"',
      '  if [ -n "$d" ] && [ -d "$d" ]; then',
      '    cd -- "$d"',
      '  fi',
      '}'];
  end
  else if SameText(AShell, 'fish') then
  begin
    Exe := ShSingleQuote(AExe);
    ALines := [
      'function mtn',
      '    set -l f (mktemp)',
      '    ' + Exe + ' --cd-file $f $argv',
      '    set -l d (cat $f)',
      '    rm -f $f',
      '    if test -n "$d" -a -d "$d"',
      '        cd $d',
      '    end',
      'end'];
  end
  else if SameText(AShell, 'powershell') or SameText(AShell, 'pwsh') then
  begin
    Exe := PsSingleQuote(AExe);
    // The Windows program is a window application, which PowerShell does not
    // wait for when it is called directly.
    ALines := [
      'function mtn {',
      '    $f = [System.IO.Path]::GetTempFileName()',
      '    try {',
      '        $p = @(''--cd-file'', ''"'' + $f + ''"'') + @($args | ForEach-Object { ''"'' + $_ + ''"'' })',
      '        Start-Process -FilePath ' + Exe + ' -ArgumentList $p -Wait',
      '        $d = (Get-Content -LiteralPath $f -Raw)',
      '        if ($d -and (Test-Path -LiteralPath $d -PathType Container)) { Set-Location -LiteralPath $d }',
      '    } finally {',
      '        Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue',
      '    }',
      '}'];
  end
  else
  begin
    ALines := nil;
    Result := False;
  end;
end;

function CdFileOfArgs(const AArgs: TArray<string>): string;
var
  I: Integer;
  Prefix: string;
begin
  Prefix := cCdFileSwitch + '=';
  for I := 0 to High(AArgs) do
    if SameText(AArgs[I], cCdFileSwitch) then
    begin
      if I < High(AArgs) then
        Exit(AArgs[I + 1]);
      Exit('');
    end
    else if AArgs[I].StartsWith(Prefix, True) then
      Exit(Copy(AArgs[I], Length(Prefix) + 1, MaxInt));
  Result := '';
end;

function CdFileOnCommandLine: string;
var
  Args: TArray<string>;
  I: Integer;
begin
  SetLength(Args, ParamCount);
  for I := 1 to ParamCount do
    Args[I - 1] := ParamStr(I);
  Result := CdFileOfArgs(Args);
end;

procedure WriteCdFile(const AFile, ADir: string);
begin
  if (AFile = '') or (ADir = '') then
    Exit;
  try
    TFile.WriteAllText(AFile, ADir, TUTF8Encoding.Create(False));
  except
    // The shell function simply finds the file empty and stays where it is.
  end;
end;

function RunShellInit(const AShell: string; const AWrite: TCliLineWriter): Integer;
var
  Lines: TArray<string>;
  Line: string;
begin
  if not ShellInitLines(AShell, PlatformExePath, Lines) then
  begin
    AWrite('FAIL --shell-init needs bash, zsh, fish or powershell');
    Exit(1);
  end;
  for Line in Lines do
    AWrite(Line);
  Result := 0;
end;

function RunCliInfo(ACommand: TCliInfoCommand; const AArgument: string;
  const AWrite: TCliLineWriter): Integer;
begin
  Result := 0;
  case ACommand of
    cicVersion:
      AWrite('MTN2 ' + AppVersionString);
    cicPaths:
      WritePaths(AWrite);
    cicListCommands:
      WriteCommands(AWrite);
    cicListPlugins:
      WritePlugins(AWrite);
    cicCheckKeymap:
      Result := RunCheckKeymap(AArgument, AWrite);
    cicExportTheme:
      Result := RunExportTheme(AArgument, AWrite);
    cicShellInit:
      Result := RunShellInit(AArgument, AWrite);
  end;
end;

end.
