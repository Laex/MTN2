unit uShellAssoc;

{ Platform shell file associations (open handler probe + open), Posix build:
  the freedesktop tools xdg-open and xdg-mime. Host/UI code uses only this
  unit. The Windows build lives in Platform\Windows; each project puts
  exactly one of the two directories on its unit search path. }

interface

uses
  uOpenWith;

type
  /// <summary>Result of asking the OS for an "open" handler for an extension.</summary>
  TShellOpenQuery = record
    Available: Boolean;
    AppName: string;
    Command: string;
    class function None: TShellOpenQuery; static;
  end;

/// <summary>Normalize to lowercase ".ext" (accepts "pdf", ".PDF", or a file name).</summary>
function NormalizeFileExtension(const AExtOrName: string): string;

/// <summary>Ask the OS whether an open action is registered for the extension.</summary>
function QueryShellOpen(const AExtension: string): TShellOpenQuery;

function HasShellOpen(const AExtension: string): Boolean;

/// <summary>Open a local file via the platform shell. Returns False on failure.</summary>
function ShellOpenFile(const AFilePath: string): Boolean;

/// <summary>Open a local file for editing: $VISUAL or $EDITOR in the desktop's
/// default handler, otherwise the plain open. Returns False on failure.</summary>
function ShellEditFile(const AFilePath: string): Boolean;

/// <summary>Open a URL (https://..., mailto:...) with the OS default handler,
/// e.g. the default browser. Returns False on failure.</summary>
function ShellOpenUrl(const AUrl: string): Boolean;

/// <summary>The applications that can open the files, default first, each with
/// the command line that opens them. Empty where the platform has no such list.</summary>
function ShellOpenWithApps(const APaths: TArray<string>): TArray<TOpenWithApp>;

/// <summary>The OS file context menu is not available: always False.</summary>
function ShellShowContextMenu(const AFilePath: string; AScreenX, AScreenY: Integer;
  AOwnerHwnd: NativeUInt): Boolean;
function ShellShowContextMenuFor(const APaths: TArray<string>; AScreenX, AScreenY: Integer;
  AOwnerHwnd: NativeUInt): Boolean;

/// <summary>The file manager's properties window, asked through the
/// freedesktop FileManager1 service; False without a desktop session, dbus-send
/// or a file manager that offers it.</summary>
function ShellShowProperties(const APaths: TArray<string>; AOwnerHwnd: NativeUInt): Boolean;

/// <summary>Run a command or file as a separate OS process that outlives this one.</summary>
function ShellRunDetached(const ACommand, AWorkingDir: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, Posix.Base, uPlatformProcess;

function system(ACommand: MarshaledAString): Integer; cdecl;
  external libc name 'system';

class function TShellOpenQuery.None: TShellOpenQuery;
begin
  Result.Available := False;
  Result.AppName := '';
  Result.Command := '';
end;

function NormalizeFileExtension(const AExtOrName: string): string;
var
  S: string;
begin
  S := Trim(AExtOrName);
  if S = '' then
    Exit('');
  // File name -> extension; bare "pdf" -> ".pdf".
  if (Pos(PathDelim, S) > 0) or (Pos('/', S) > 0) or (Pos('.', S) > 1) then
    S := ExtractFileExt(S)
  else if (Length(S) > 0) and (S[1] <> '.') then
    S := '.' + S;
  Result := LowerCase(S);
end;

function ShellQuote(const AText: string): string;
begin
  Result := '''' + StringReplace(AText, '''', '''\''''', [rfReplaceAll]) + '''';
end;

// A graphical desktop is available to take the file.
function HasDisplay: Boolean;
begin
  Result := GetEnvironmentVariable('DISPLAY') + GetEnvironmentVariable('WAYLAND_DISPLAY') <> '';
end;

function ToolInPath(const ATool: string): Boolean;
begin
  Result := FileSearch(ATool, GetEnvironmentVariable('PATH')) <> '';
end;

function RunShell(const ACommandLine: string): Boolean;
var
  Cmd: UTF8String;
begin
  Cmd := UTF8String(ACommandLine);
  Result := system(MarshaledAString(Cmd)) = 0;
end;

function QueryShellOpen(const AExtension: string): TShellOpenQuery;
var
  Ext: string;
begin
  Result := TShellOpenQuery.None;
  Ext := NormalizeFileExtension(AExtension);
  if Ext = '' then
    Exit;
  // xdg-open picks the handler itself; the probe only says it can be asked.
  Result.Available := HasDisplay and ToolInPath('xdg-open');
  if Result.Available then
    Result.Command := 'xdg-open';
end;

function HasShellOpen(const AExtension: string): Boolean;
begin
  Result := QueryShellOpen(AExtension).Available;
end;

function ShellOpenFile(const AFilePath: string): Boolean;
begin
  Result := False;
  if (AFilePath = '') or not HasDisplay or not ToolInPath('xdg-open') then
    Exit;
  Result := RunShell('xdg-open ' + ShellQuote(AFilePath) + ' >/dev/null 2>&1 &');
end;

function ShellEditFile(const AFilePath: string): Boolean;
var
  Editor: string;
begin
  Result := False;
  if AFilePath = '' then
    Exit;
  Editor := GetEnvironmentVariable('VISUAL');
  if Editor = '' then
    Editor := GetEnvironmentVariable('EDITOR');
  if (Editor <> '') and ToolInPath(Editor) and
     HasDisplay then
    Exit(RunShell(Editor + ' ' + ShellQuote(AFilePath) + ' >/dev/null 2>&1 &'));
  Result := ShellOpenFile(AFilePath);
end;

function ShellOpenUrl(const AUrl: string): Boolean;
begin
  Result := False;
  if (AUrl = '') or not ToolInPath('xdg-open') then
    Exit;
  Result := RunShell('xdg-open ' + ShellQuote(AUrl) + ' >/dev/null 2>&1 &');
end;

function ReadTextFile(const APath: string; out AText: string): Boolean;
begin
  Result := False;
  AText := '';
  try
    if TFile.Exists(APath) then
    begin
      AText := TFile.ReadAllText(APath, TEncoding.UTF8);
      Result := True;
    end;
  except
    AText := '';
  end;
end;

// MIME type of the first file as the desktop's shared database sees it.
function MimeTypeOf(const APath: string): string;
var
  Output: string;
  Code: Cardinal;
begin
  Result := '';
  if not ToolInPath('xdg-mime') then
    Exit;
  if (PlatformRunCaptured('xdg-mime', ['query', 'filetype', APath], '', 5000, nil,
       Output, Code) = srOk) and (Code = 0) then
    Result := Trim(Output);
end;

function DefaultAppId(const AMime: string): string;
var
  Output: string;
  Code: Cardinal;
begin
  Result := '';
  if (PlatformRunCaptured('xdg-mime', ['query', 'default', AMime], '', 5000, nil,
       Output, Code) = srOk) and (Code = 0) then
    Result := Trim(Output);
end;

function ApplicationDirs: TArray<string>;
var
  Home, Dirs, D: string;
  N: Integer;
begin
  SetLength(Result, 0);
  Home := GetEnvironmentVariable('XDG_DATA_HOME');
  if Home = '' then
    Home := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + '.local/share';
  Dirs := GetEnvironmentVariable('XDG_DATA_DIRS');
  if Dirs = '' then
    Dirs := '/usr/local/share:/usr/share';
  Dirs := Home + ':' + Dirs;
  for D in Dirs.Split([':'], TStringSplitOptions.ExcludeEmpty) do
  begin
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N] := IncludeTrailingPathDelimiter(D) + 'applications/';
  end;
end;

function ShellOpenWithApps(const APaths: TArray<string>): TArray<TOpenWithApp>;
const
  cMaxApps = 30;
var
  Mime, Text, Id, DefaultId: string;
  Dirs: TArray<string>;
  Dir: string;
  Ids: TArray<string>;
  Seen: TStringList;
  Entry: TOpenWithEntry;
  Cmd: string;
  N: Integer;
  Full: TArray<string>;
  I: Integer;

  procedure AddId(const AId: string);
  var
    Dir2, Body: string;
  begin
    if (AId = '') or (Seen.IndexOf(AId) >= 0) or (Length(Result) >= cMaxApps) then
      Exit;
    Seen.Add(AId);
    for Dir2 in Dirs do
      if ReadTextFile(Dir2 + AId, Body) then
      begin
        if ParseOpenWithEntry(Body, Entry) and not Entry.Hidden and not Entry.Terminal then
        begin
          Cmd := OpenWithExecToCommand(Entry.Exec, Entry.Name, Full);
          if Cmd <> '' then
          begin
            N := Length(Result);
            SetLength(Result, N + 1);
            Result[N].Name := Entry.Name;
            Result[N].Command := Cmd;
          end;
        end;
        Exit;
      end;
  end;

begin
  SetLength(Result, 0);
  if (Length(APaths) = 0) or not HasDisplay then
    Exit;
  SetLength(Full, Length(APaths));
  for I := 0 to High(APaths) do
    Full[I] := ExpandFileName(APaths[I]);
  Mime := MimeTypeOf(Full[0]);
  if Mime = '' then
    Exit;
  Dirs := ApplicationDirs;
  Seen := TStringList.Create;
  try
    DefaultId := DefaultAppId(Mime);
    AddId(DefaultId);
    for Dir in Dirs do
      if ReadTextFile(Dir + 'mimeinfo.cache', Text) then
      begin
        Ids := MimeCacheApps(Text, Mime);
        for Id in Ids do
          AddId(Id);
      end;
  finally
    Seen.Free;
  end;
end;

function ShellShowContextMenu(const AFilePath: string; AScreenX, AScreenY: Integer;
  AOwnerHwnd: NativeUInt): Boolean;
begin
  Result := False;
end;

function ShellShowContextMenuFor(const APaths: TArray<string>; AScreenX, AScreenY: Integer;
  AOwnerHwnd: NativeUInt): Boolean;
begin
  Result := False;
end;

// file:// URI of a local path; every byte outside the unreserved set is
// percent-encoded, so no character can end the dbus-send array argument.
function PathToUriText(const APath: string): string;
var
  Bytes: TBytes;
  B: Byte;
begin
  Result := 'file://';
  Bytes := TEncoding.UTF8.GetBytes(APath);
  for B in Bytes do
    if (B = Ord('/')) or ((B >= Ord('a')) and (B <= Ord('z'))) or
       ((B >= Ord('A')) and (B <= Ord('Z'))) or ((B >= Ord('0')) and (B <= Ord('9'))) or
       (B = Ord('-')) or (B = Ord('_')) or (B = Ord('.')) or (B = Ord('~')) then
      Result := Result + Char(B)
    else
      Result := Result + '%' + IntToHex(B, 2);
end;

function ShellShowProperties(const APaths: TArray<string>; AOwnerHwnd: NativeUInt): Boolean;
var
  Uris: string;
  Path: string;
begin
  Result := False;
  if (Length(APaths) = 0) or not HasDisplay or not ToolInPath('dbus-send') then
    Exit;
  Uris := '';
  for Path in APaths do
  begin
    if Path = '' then
      Continue;
    if Uris <> '' then
      Uris := Uris + ',';
    Uris := Uris + PathToUriText(ExpandFileName(Path));
  end;
  if Uris = '' then
    Exit;
  // --print-reply waits for the answer, so a missing service is a failure.
  Result := RunShell('dbus-send --session --print-reply --reply-timeout=3000 ' +
    '--dest=org.freedesktop.FileManager1 --type=method_call ' +
    '/org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItemProperties ' +
    ShellQuote('array:string:' + Uris) + ' string:"" >/dev/null 2>&1');
end;

function ShellRunDetached(const ACommand, AWorkingDir: string): Boolean;
var
  Line: string;
begin
  Result := False;
  if ACommand = '' then
    Exit;
  Line := ACommand + ' >/dev/null 2>&1 &';
  if AWorkingDir <> '' then
    Line := 'cd ' + ShellQuote(AWorkingDir) + ' && ' + Line;
  Result := RunShell(Line);
end;

end.
