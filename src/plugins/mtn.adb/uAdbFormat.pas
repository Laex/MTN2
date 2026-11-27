unit uAdbFormat;

{ Pure helpers of the Android plugin: addresses, the command lines handed to
  the adb program and the parsers of its text output.

    adb:///                    the connected devices
    adb:///<serial>            the root folder of a device
    adb:///<serial>/<path>     a file or folder of the device

  "adb shell" joins its arguments and gives the result to the shell of the
  device, so every command is built here as one string with each path in single
  quotes (ShellQuote). "pull" and "push" use no shell and take plain paths. }

interface

type
  TAdbNode = (anInvalid, anRoot, anFs);

  TAdbAddr = record
    Node: TAdbNode;
    Serial: string;
    /// <summary>The absolute path on the device (anFs).</summary>
    Path: string;
  end;

  TAdbDevice = record
    Serial: string;
    /// <summary>"device" when ready; otherwise "unauthorized", "offline",
    /// "no permissions" and so on.</summary>
    State: string;
    Model: string;
    Product: string;
  end;
  TAdbDevices = TArray<TAdbDevice>;

  TAdbEntry = record
    Name: string;
    IsDir: Boolean;
    IsLink: Boolean;
    Size: Int64;
    /// <summary>Seconds since 1970-01-01 UTC; 0 when unknown.</summary>
    Modified: Int64;
  end;
  TAdbEntries = TArray<TAdbEntry>;

  /// <summary>Why adb could not reach the device.</summary>
  TAdbProblem = (apNone, apUnauthorized, apOffline, apNotConnected, apNoPermissions);

const
  cAdb = 'adb';
  cAdbPrefix = 'adb:///';
  cReadyState = 'device';

/// <summary>False for another scheme or a path with "." or ".." segments.</summary>
function ParseAdbUri(const AUri: string; out AAddr: TAdbAddr): Boolean;

/// <summary>%2F for "/" and %25 for "%" so a serial stays one path segment.</summary>
function EncodeSegment(const AText: string): string;
function DecodeSegment(const AText: string): string;

/// <summary>AText as one word of the device shell, whatever it contains.</summary>
function ShellQuote(const AText: string): string;

/// <summary>The arguments that run AScript in the shell of the device.</summary>
function ShellArgs(const ASerial, AScript: string): TArray<string>;

function DevicesArgs: TArray<string>;
function StateArgs(const ASerial: string): TArray<string>;
function PullArgs(const ASerial, ARemote, ALocal: string; AKeepTimes: Boolean): TArray<string>;
function PushArgs(const ASerial, ALocal, ARemote: string): TArray<string>;

/// <summary>One "S|mode|size|time|path" line per entry of the folder and one
/// "D|path" line per link that leads to a folder (see ParseStatListing).</summary>
function ListScript(const ADir: string): string;
/// <summary>Prints "d" for a folder, "f" for anything else, "n" for nothing.</summary>
function KindScript(const APath: string): string;
function MkdirScript(const APath: string): string;
function RemoveScript(const APath: string): string;
function MoveScript(const AFrom, ATo: string): string;
/// <summary>AMergeDirs copies the content of the folder AFrom into ATo.</summary>
function CopyScript(const AFrom, ATo: string; AMergeDirs: Boolean): string;
/// <summary>Prints the file in base64, so binary data survives the text channel;
/// AMaxBytes > 0 limits it to the head of the file.</summary>
function ReadScript(const APath: string; AMaxBytes: Int64): string;

/// <summary>Output of "adb devices -l".</summary>
function ParseDeviceList(const AText: string): TAdbDevices;
function ParseStatListing(const AText: string): TAdbEntries;
/// <summary>Recognizes the messages of adb itself (lines that begin with
/// "adb:" or "error:").</summary>
function AdbProblem(const AOutput: string): TAdbProblem;
/// <summary>Removes the "* daemon ..." lines adb prints when it starts its server.</summary>
function StripDaemonNoise(const AText: string): string;

/// <summary>Child of a device path: "/" + "a" = "/a", "/x" + "a" = "/x/a".</summary>
function JoinDevicePath(const ADir, AName: string): string;

implementation

uses
  System.SysUtils;

function EncodeSegment(const AText: string): string;
begin
  Result := AText.Replace('%', '%25').Replace('/', '%2F');
end;

function DecodeSegment(const AText: string): string;
begin
  // "%2F" first: an encoded "%2F" reads "%252F" and holds no "%2F".
  Result := AText.Replace('%2F', '/').Replace('%25', '%');
end;

function ParseAdbUri(const AUri: string; out AAddr: TAdbAddr): Boolean;
var
  Part, Path: string;
begin
  AAddr := Default(TAdbAddr);
  if not SameText(Copy(AUri, 1, Length(cAdbPrefix)), cAdbPrefix) then
    Exit(False);
  Path := '';
  for Part in Copy(AUri, Length(cAdbPrefix) + 1, MaxInt).Split(['/']) do
  begin
    if Part = '' then
      Continue;
    // The shell of the device would follow these out of the folder shown.
    if (Part = '.') or (Part = '..') then
    begin
      AAddr := Default(TAdbAddr);
      Exit(False);
    end;
    if AAddr.Serial = '' then
      AAddr.Serial := DecodeSegment(Part)
    else
      Path := Path + '/' + Part;
  end;
  if AAddr.Serial = '' then
    AAddr.Node := anRoot
  else
  begin
    AAddr.Node := anFs;
    if Path = '' then
      Path := '/';
    AAddr.Path := Path;
  end;
  Result := True;
end;

function ShellQuote(const AText: string): string;
begin
  // Inside single quotes the shell reads everything literally except the quote,
  // which is written as: close, an escaped quote, open again.
  Result := '''' + AText.Replace('''', '''\''''') + '''';
end;

function ShellArgs(const ASerial, AScript: string): TArray<string>;
begin
  Result := ['-s', ASerial, 'shell', AScript];
end;

function DevicesArgs: TArray<string>;
begin
  Result := ['devices', '-l'];
end;

function StateArgs(const ASerial: string): TArray<string>;
begin
  Result := ['-s', ASerial, 'get-state'];
end;

function PullArgs(const ASerial, ARemote, ALocal: string; AKeepTimes: Boolean): TArray<string>;
begin
  Result := ['-s', ASerial, 'pull'];
  if AKeepTimes then
    Result := Result + ['-a'];
  Result := Result + [ARemote, ALocal];
end;

function PushArgs(const ASerial, ALocal, ARemote: string): TArray<string>;
begin
  Result := ['-s', ASerial, 'push', ALocal, ARemote];
end;

function ListScript(const ADir: string): string;
var
  Dir: string;
begin
  // The trailing slash makes find enter a folder reached through a link.
  Dir := ADir;
  if not Dir.EndsWith('/') then
    Dir := Dir + '/';
  Dir := ShellQuote(Dir);
  Result :=
    'find ' + Dir + ' -mindepth 1 -maxdepth 1 -exec stat -c ''S|%f|%s|%Y|%n'' {} +; r=$?; ' +
    'find ' + Dir + ' -mindepth 1 -maxdepth 1 -type l -exec sh -c ' +
    '''for p; do [ -d "$p" ] && echo "D|$p"; done'' sh {} +; exit $r';
end;

function KindScript(const APath: string): string;
var
  P: string;
begin
  P := ShellQuote(APath);
  Result := 'if [ -d ' + P + ' ]; then echo d; elif [ -e ' + P + ' ] || [ -L ' + P +
    ' ]; then echo f; else echo n; fi';
end;

function MkdirScript(const APath: string): string;
begin
  Result := 'mkdir -p ' + ShellQuote(APath);
end;

function RemoveScript(const APath: string): string;
begin
  Result := 'rm -rf ' + ShellQuote(APath);
end;

function MoveScript(const AFrom, ATo: string): string;
begin
  Result := 'mv -f ' + ShellQuote(AFrom) + ' ' + ShellQuote(ATo);
end;

function CopyScript(const AFrom, ATo: string; AMergeDirs: Boolean): string;
var
  From: string;
begin
  From := AFrom;
  if AMergeDirs then
    From := JoinDevicePath(From, '.');
  Result := 'cp -R ' + ShellQuote(From) + ' ' + ShellQuote(ATo);
end;

function ReadScript(const APath: string; AMaxBytes: Int64): string;
var
  P, Count: string;
begin
  P := ShellQuote(APath);
  if AMaxBytes <= 0 then
    Exit('base64 ' + P);
  Count := IntToStr(AMaxBytes);
  // A pipeline reports the status of its last command only: reading nothing
  // first makes a missing or unreadable file fail with its message.
  Result := 'head -c 0 ' + P + ' && head -c ' + Count + ' ' + P + ' | base64';
end;

function Lines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13, '').Split([#10]);
end;

function StripDaemonNoise(const AText: string): string;
var
  P: Integer;
  Line: string;
begin
  Result := AText.Replace(#13#10, #10);
  while Result.StartsWith('* daemon ') do
  begin
    P := Pos(#10, Result);
    if P = 0 then
      Exit('');
    Line := Copy(Result, 1, P);
    Delete(Result, 1, Length(Line));
  end;
end;

// Where the state begins: the first known state word after a blank. A serial
// of a wireless device may itself hold a blank ("name (2)._adb-tls-connect").
function StateStart(const ALine: string): Integer;
const
  cStates: array[0..10] of string = ('device', 'unauthorized', 'offline', 'no permissions',
    'authorizing', 'connecting', 'recovery', 'sideload', 'bootloader', 'host', 'rescue');
var
  I: Integer;
  State, Rest: string;
begin
  for I := 2 to Length(ALine) do
    if CharInSet(ALine[I - 1], [' ', #9]) then
    begin
      Rest := Copy(ALine, I, MaxInt);
      for State in cStates do
        if (Rest = State) or Rest.StartsWith(State + ' ') or Rest.StartsWith(State + ';') then
          Exit(I);
    end;
  Result := 0;
end;

function ParseDeviceList(const AText: string): TAdbDevices;
var
  Line, Rest, Token: string;
  Device: TAdbDevice;
  Started: Boolean;
  P: Integer;
begin
  Result := nil;
  Started := False;
  for Line in Lines(AText) do
  begin
    if not Started then
    begin
      Started := Line.StartsWith('List of devices');
      Continue;
    end;
    P := StateStart(Line);
    if P = 0 then
      Continue;
    Device := Default(TAdbDevice);
    Device.Serial := Trim(Copy(Line, 1, P - 1));
    Rest := Trim(Copy(Line, P, MaxInt));
    if Rest.StartsWith('no permissions') then
      Device.State := 'no permissions'
    else
      for Token in Rest.Split([' '], TStringSplitOptions.ExcludeEmpty) do
        if Device.State = '' then
          Device.State := Token
        else if Token.StartsWith('model:') then
          Device.Model := Copy(Token, 7, MaxInt).Replace('_', ' ')
        else if Token.StartsWith('product:') then
          Device.Product := Copy(Token, 9, MaxInt);
    if Device.Serial <> '' then
      Result := Result + [Device];
  end;
end;

function ParseStatListing(const AText: string): TAdbEntries;
const
  cTypeMask = $F000;
  cTypeDir = $4000;
  cTypeLink = $A000;
var
  Line, Path: string;
  Parts: TArray<string>;
  DirLinks: TArray<string>;
  Paths: TArray<string>;
  Entry: TAdbEntry;
  Mode, I, J: Integer;
begin
  Result := nil;
  DirLinks := nil;
  Paths := nil;
  for Line in Lines(AText) do
  begin
    if Line.StartsWith('D|') then
    begin
      DirLinks := DirLinks + [Copy(Line, 3, MaxInt)];
      Continue;
    end;
    // mode in hex | size | seconds since 1970 | path
    Parts := Line.Split(['|']);
    if (Length(Parts) < 5) or (Parts[0] <> 'S') then
      Continue;
    Mode := StrToIntDef('$' + Parts[1], -1);
    if Mode < 0 then
      Continue;
    // A bar inside the name belongs to the name.
    Path := string.Join('|', Copy(Parts, 4, Length(Parts)));
    Entry := Default(TAdbEntry);
    Entry.Name := Copy(Path, Path.LastIndexOf('/') + 2, MaxInt);
    if Entry.Name = '' then
      Continue;
    Entry.IsDir := (Mode and cTypeMask) = cTypeDir;
    Entry.IsLink := (Mode and cTypeMask) = cTypeLink;
    Entry.Size := StrToInt64Def(Parts[2], 0);
    Entry.Modified := StrToInt64Def(Parts[3], 0);
    Result := Result + [Entry];
    Paths := Paths + [Path];
  end;
  for I := 0 to High(Result) do
    if Result[I].IsLink then
      for J := 0 to High(DirLinks) do
        if DirLinks[J] = Paths[I] then
          Result[I].IsDir := True;
end;

function AdbProblem(const AOutput: string): TAdbProblem;
var
  Line: string;
begin
  for Line in Lines(AOutput) do
  begin
    if not (Line.StartsWith('error:') or Line.StartsWith('adb:')) then
      Continue;
    if Line.Contains('unauthorized') then
      Exit(apUnauthorized);
    if Line.Contains('device offline') or Line.Contains('still authorizing') then
      Exit(apOffline);
    if Line.Contains('insufficient permissions') or Line.Contains('no permissions') then
      Exit(apNoPermissions);
    if Line.Contains('no devices') or (Line.Contains('device ''') and Line.Contains(''' not found')) then
      Exit(apNotConnected);
  end;
  Result := apNone;
end;

function JoinDevicePath(const ADir, AName: string): string;
begin
  if ADir.EndsWith('/') then
    Result := ADir + AName
  else
    Result := ADir + '/' + AName;
end;

end.
