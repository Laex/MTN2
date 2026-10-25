unit uDesktopEntry;

{ Menu entry and icon of the Linux programs, in the user's folders of the
  freedesktop.org data (no administrator rights):

    <data>/applications/<id>.desktop           mtn2-sdl.desktop, mtn2-tui.desktop
    <data>/icons/hicolor/256x256/apps/mtn2.png

  <data> is $XDG_DATA_HOME, or ~/.local/share. A window manager matches the
  window of the SDL build to its entry by the class name (StartupWMClass) and,
  under Wayland, by the application id; both are the entry's id, so the taskbar
  shows the name and the icon of the entry instead of the defaults of the
  window manager.

  A file this unit wrote carries the X-MTN2-Generated line and is rewritten when
  the program moves; a file without it belongs to someone else and stays as it
  is. The SDL window installs its entry on every start unless
  MTN2_NO_DESKTOP_ENTRY is set; --install-desktop and --uninstall-desktop do it
  on request. }

interface

uses
  System.SysUtils;

const
  cInstallDesktopSwitch = '--install-desktop';
  cUninstallDesktopSwitch = '--uninstall-desktop';
  cNoDesktopEntryVariable = 'MTN2_NO_DESKTOP_ENTRY';
  cDesktopIconName = 'mtn2';
  cDesktopIconResource = 'APP_ICON';
  cGeneratedMarker = 'X-MTN2-Generated=true';

type
  TDesktopEntryKind = (dekSdl, dekTui);

  TDesktopLineWriter = reference to procedure(const ALine: string);

  TDesktopEntryResult = (derInstalled, derUpToDate, derForeignKept, derFailed, derRemoved,
    derNothingToRemove);

/// <summary>"mtn2-sdl" / "mtn2-tui": the file name without ".desktop", the
/// window class and the application id.</summary>
function DesktopEntryId(AKind: TDesktopEntryKind): string;

/// <summary>$XDG_DATA_HOME or ~/.local/share.</summary>
function DesktopDataHome: string;

/// <summary>An Exec argument as the desktop entry specification wants it:
/// quoted when it has a space or a reserved character, with the backslash,
/// quote, back quote, dollar and percent characters escaped.</summary>
function DesktopExecArgument(const AValue: string): string;

/// <summary>Text of the .desktop file for AExecPath. The Exec line passes the
/// files and folders a file manager hands over (%F), which the program opens
/// in tabs.</summary>
function DesktopEntryText(AKind: TDesktopEntryKind; const AExecPath: string): string;

/// <summary>Writes the entry and the icon below ADataHome. AIconPng is the
/// 256-pixel icon; without it the entry is written and uses the icon name only.</summary>
function InstallDesktopEntry(AKind: TDesktopEntryKind; const ADataHome, AExecPath: string;
  const AIconPng: TBytes; out ADetail: string): TDesktopEntryResult;

/// <summary>Deletes the entry written by InstallDesktopEntry. The icon goes
/// with it when no other entry of ours remains.</summary>
function RemoveDesktopEntry(AKind: TDesktopEntryKind; const ADataHome: string;
  out ADetail: string): TDesktopEntryResult;

/// <summary>The icon embedded in the program (empty when the build has none).</summary>
function BundledDesktopIcon: TBytes;

/// <summary>True when the program should write its entry by itself: not
/// switched off by MTN2_NO_DESKTOP_ENTRY and not installed from a package
/// (a package brings its own entry).</summary>
function DesktopEntryAutoInstallAllowed: Boolean;

/// <summary>--install-desktop / --uninstall-desktop on the command line.</summary>
function InstallDesktopRequested: Boolean;
function UninstallDesktopRequested: Boolean;

/// <summary>The command-line forms: installs or removes the entry of AKind for
/// the running program, writes what happened to AWrite and returns the exit
/// code (0 done or nothing to do, 1 failed).</summary>
function RunDesktopCommand(AKind: TDesktopEntryKind; AInstall: Boolean;
  const AWrite: TDesktopLineWriter): Integer;

/// <summary>Installs the entry of AKind quietly when the program may do it by
/// itself; failures are ignored.</summary>
procedure EnsureDesktopEntry(AKind: TDesktopEntryKind);

implementation

uses
  System.Classes, System.IOUtils, uPlatformInfo, uResourceAccess, uUpdater;

function DesktopEntryId(AKind: TDesktopEntryKind): string;
begin
  if AKind = dekSdl then
    Result := 'mtn2-sdl'
  else
    Result := 'mtn2-tui';
end;

function DesktopDataHome: string;
begin
  Result := GetEnvironmentVariable('XDG_DATA_HOME');
  if (Result = '') or not TPath.IsPathRooted(Result) then
    Result := TPath.Combine(TPath.GetHomePath, '.local/share');
end;

function DesktopExecArgument(const AValue: string): string;
var
  C: Char;
  Quote: Boolean;
begin
  Quote := False;
  Result := '';
  for C in AValue do
    case C of
      ' ', #9, #10, '"', '''', '\', '>', '<', '~', '|', '&', ';', '$', '*', '?', '#',
      '(', ')', '`':
        begin
          Quote := True;
          Break;
        end;
    end;
  if not Quote then
    Exit(StringReplace(AValue, '%', '%%', [rfReplaceAll]));
  for C in AValue do
    case C of
      '"', '`', '$':
        Result := Result + '\' + C;
      '\':
        Result := Result + '\\';
      '%':
        Result := Result + '%%';
    else
      Result := Result + C;
    end;
  Result := '"' + Result + '"';
end;

// The Exec line is a string value of the key file: its backslashes are doubled
// once more.
function KeyFileString(const AValue: string): string;
begin
  Result := StringReplace(AValue, '\', '\\', [rfReplaceAll]);
end;

function DesktopEntryText(AKind: TDesktopEntryKind; const AExecPath: string): string;
var
  Id: string;
begin
  Id := DesktopEntryId(AKind);
  Result :=
    '[Desktop Entry]'#10 +
    'Type=Application'#10 +
    'Name=MTN2'#10 +
    'GenericName=File manager'#10 +
    'Comment=Dual-panel file manager with a built-in terminal'#10 +
    'Exec=' + KeyFileString(DesktopExecArgument(AExecPath)) + ' %F'#10 +
    'Icon=' + cDesktopIconName + #10;
  if AKind = dekTui then
    Result := Result + 'Terminal=true'#10 +
      'Categories=System;FileTools;FileManager;ConsoleOnly;'#10
  else
    Result := Result + 'Terminal=false'#10 +
      'Categories=System;FileTools;FileManager;'#10 +
      'StartupWMClass=' + Id + #10;
  Result := Result + cGeneratedMarker + #10;
end;

function EntryFile(const ADataHome: string; AKind: TDesktopEntryKind): string;
begin
  Result := TPath.Combine(TPath.Combine(ADataHome, 'applications'),
    DesktopEntryId(AKind) + '.desktop');
end;

function IconFile(const ADataHome: string): string;
begin
  Result := TPath.Combine(TPath.Combine(ADataHome, 'icons/hicolor/256x256/apps'),
    cDesktopIconName + '.png');
end;

function ReadTextOrEmpty(const AFile: string): string;
begin
  try
    if TFile.Exists(AFile) then
      Result := TFile.ReadAllText(AFile, TEncoding.UTF8)
    else
      Result := '';
  except
    Result := '';
  end;
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and
    ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function InstallDesktopEntry(AKind: TDesktopEntryKind; const ADataHome, AExecPath: string;
  const AIconPng: TBytes; out ADetail: string): TDesktopEntryResult;
var
  EntryPath, IconPath, Wanted, Existing: string;
  Changed: Boolean;
  Utf8: TEncoding;
begin
  EntryPath := EntryFile(ADataHome, AKind);
  IconPath := IconFile(ADataHome);
  ADetail := EntryPath;
  Wanted := DesktopEntryText(AKind, AExecPath);
  Existing := ReadTextOrEmpty(EntryPath);
  if (Existing <> '') and (Pos(cGeneratedMarker, Existing) = 0) then
    Exit(derForeignKept);
  Utf8 := TUTF8Encoding.Create(False);
  try
    try
      Changed := Existing <> Wanted;
      if Changed then
      begin
        TDirectory.CreateDirectory(ExtractFileDir(EntryPath));
        TFile.WriteAllText(EntryPath, Wanted, Utf8);
      end;
      if Length(AIconPng) > 0 then
        if not TFile.Exists(IconPath) or not SameBytes(TFile.ReadAllBytes(IconPath), AIconPng) then
        begin
          TDirectory.CreateDirectory(ExtractFileDir(IconPath));
          TFile.WriteAllBytes(IconPath, AIconPng);
          Changed := True;
        end;
    except
      on E: Exception do
      begin
        ADetail := E.Message;
        Exit(derFailed);
      end;
    end;
  finally
    Utf8.Free;
  end;
  if Changed then
    Result := derInstalled
  else
    Result := derUpToDate;
end;

function RemoveDesktopEntry(AKind: TDesktopEntryKind; const ADataHome: string;
  out ADetail: string): TDesktopEntryResult;
var
  EntryPath, Other: string;
  OtherKind: TDesktopEntryKind;
begin
  EntryPath := EntryFile(ADataHome, AKind);
  ADetail := EntryPath;
  Result := derNothingToRemove;
  if Pos(cGeneratedMarker, ReadTextOrEmpty(EntryPath)) = 0 then
  begin
    if TFile.Exists(EntryPath) then
      Result := derForeignKept;
    Exit;
  end;
  try
    TFile.Delete(EntryPath);
    Result := derRemoved;
    // The icon is shared by both entries.
    for OtherKind := Low(TDesktopEntryKind) to High(TDesktopEntryKind) do
    begin
      Other := EntryFile(ADataHome, OtherKind);
      if (OtherKind <> AKind) and TFile.Exists(Other) then
        Exit;
    end;
    if TFile.Exists(IconFile(ADataHome)) then
      TFile.Delete(IconFile(ADataHome));
  except
    on E: Exception do
    begin
      ADetail := E.Message;
      Result := derFailed;
    end;
  end;
end;

function BundledDesktopIcon: TBytes;
var
  Stream: TStream;
begin
  Result := nil;
  Stream := OpenRcData(cDesktopIconResource);
  if Stream = nil then
    Exit;
  try
    SetLength(Result, Stream.Size);
    if Length(Result) > 0 then
      Stream.ReadBuffer(Result[0], Length(Result));
  finally
    Stream.Free;
  end;
end;

function DesktopEntryAutoInstallAllowed: Boolean;
begin
  Result := (GetEnvironmentVariable(cNoDesktopEntryVariable) = '') and
    not UpdatesManagedByPackage(AppDir);
end;

function SwitchGiven(const ASwitch: string): Boolean;
var
  I: Integer;
begin
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), ASwitch) then
      Exit(True);
  Result := False;
end;

function InstallDesktopRequested: Boolean;
begin
  Result := SwitchGiven(cInstallDesktopSwitch);
end;

function UninstallDesktopRequested: Boolean;
begin
  Result := SwitchGiven(cUninstallDesktopSwitch);
end;

function RunDesktopCommand(AKind: TDesktopEntryKind; AInstall: Boolean;
  const AWrite: TDesktopLineWriter): Integer;
var
  Detail: string;
begin
  Result := 0;
  if AInstall then
    case InstallDesktopEntry(AKind, DesktopDataHome, PlatformExePath, BundledDesktopIcon, Detail) of
      derInstalled: AWrite('Menu entry written: ' + Detail);
      derUpToDate: AWrite('Menu entry is up to date: ' + Detail);
      derForeignKept: AWrite('Left as it is, the file was not written by MTN2: ' + Detail);
    else
      begin
        AWrite('Could not write the menu entry: ' + Detail);
        Result := 1;
      end;
    end
  else
    case RemoveDesktopEntry(AKind, DesktopDataHome, Detail) of
      derRemoved: AWrite('Menu entry removed: ' + Detail);
      derNothingToRemove: AWrite('No menu entry to remove.');
      derForeignKept: AWrite('Left as it is, the file was not written by MTN2: ' + Detail);
    else
      begin
        AWrite('Could not remove the menu entry: ' + Detail);
        Result := 1;
      end;
    end;
end;

procedure EnsureDesktopEntry(AKind: TDesktopEntryKind);
var
  Detail: string;
begin
  if not DesktopEntryAutoInstallAllowed then
    Exit;
  try
    InstallDesktopEntry(AKind, DesktopDataHome, PlatformExePath, BundledDesktopIcon, Detail);
  except
  end;
end;

end.
