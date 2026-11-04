unit uDockerVfs;

{ The version 2 VFS callbacks for docker:///. Every operation runs the docker or
  kubectl program (GRunTool) and maps its exit code and text to a result code
  of the plugin ABI. Files inside a container or pod are reached through
  "exec" (listing, reading, writing, deleting) and "cp" (copying). }

interface

uses
  uPluginHostAbi, uDockerFormat;

type
  /// <summary>Runs a program; False when it could not be started or did not finish in time
  /// (AOutput then explains why). Otherwise ACode is its exit code.</summary>
  TRunToolFunc = function(const AExe: string; const AArgs: TArray<string>; const AStdIn: string;
    ATimeoutMs: Cardinal; out AOutput: string; out ACode: Cardinal): Boolean;

  /// <summary>Gets the folder address and a JSON object {row name: color role}
  /// after a listing of containers or pods. Called on the thread that listed.</summary>
  TRowColorsEvent = procedure(const AFolderUri, AJson: string);

var
  /// <summary>The program runner; tests put a fake one here.</summary>
  GRunTool: TRunToolFunc;
  GOnRowColors: TRowColorsEvent;

function DefaultRunTool(const AExe: string; const AArgs: TArray<string>; const AStdIn: string;
  ATimeoutMs: Cardinal; out AOutput: string; out ACode: Cardinal): Boolean;

function DockerVfsCallbacks: TVfsCallbacksCdeclV2;

/// <summary>Runs "docker <verb> <container>" for start, stop, restart, pause or unpause.
/// Returns '' when it worked, otherwise the program's message.</summary>
function ControlContainer(const AVerb, AContainer: string): string;

implementation

uses
  System.SysUtils, System.StrUtils, System.JSON, System.DateUtils, System.TimeSpan, uVfsTypes, uPlatformProcess;

const
  cListTimeoutMs = 20000;
  cReadTimeoutMs = 30000;
  cControlTimeoutMs = 60000;
  cCopyTimeoutMs = 600000;
  cNoneImage = '<none>';

function DefaultRunTool(const AExe: string; const AArgs: TArray<string>; const AStdIn: string;
  ATimeoutMs: Cardinal; out AOutput: string; out ACode: Cardinal): Boolean;
begin
  Result := PlatformRunCaptured(AExe, AArgs, AStdIn, ATimeoutMs, nil, AOutput, ACode) = srOk;
  if not Result then
    AOutput := AExe + ' did not run (is it installed and in PATH?)';
end;

function Fail(ACtx: PVfsOpContext; ACode: TVfsCdeclResult; const AText: string): Int64;
var
  Text: UTF8String;
begin
  if (ACtx <> nil) and Assigned(ACtx^.SetErrorText) and (AText <> '') then
  begin
    Text := UTF8String(Trim(Copy(AText, 1, 400)));
    ACtx^.SetErrorText(ACtx, PAnsiChar(Text));
  end;
  Result := Ord(ACode);
end;

// "No such file", "not found" in the program's message mean the item is not there.
function CodeOfFailure(const AOutput: string): TVfsCdeclResult;
begin
  if ContainsText(AOutput, 'No such') or ContainsText(AOutput, 'not found') or
     ContainsText(AOutput, 'NotFound') then
    Result := verNotFound
  else if ContainsText(AOutput, 'denied') or ContainsText(AOutput, 'forbidden') or
          ContainsText(AOutput, 'not permitted') then
    Result := verAccessDenied
  else
    Result := verIOError;
end;

// Runs a program; verOk = done, otherwise the result code with the message set on ACtx.
function Run(ACtx: PVfsOpContext; ABackend: TDockerBackend; const AArgs: TArray<string>;
  const AStdIn: string; ATimeoutMs: Cardinal; out AOutput: string): Int64;
var
  Code: Cardinal;
begin
  if not GRunTool(BackendExe(ABackend), AArgs, AStdIn, ATimeoutMs, AOutput, Code) then
    Exit(Fail(ACtx, verIOError, AOutput));
  if Code <> 0 then
    Exit(Fail(ACtx, CodeOfFailure(AOutput), AOutput));
  Result := Ord(verOk);
end;

function ControlContainer(const AVerb, AContainer: string): string;
var
  Output: string;
  Code: Cardinal;
begin
  if not GRunTool(cDocker, [AVerb, AContainer], '', cControlTimeoutMs, Output, Code) then
    Exit(Output);
  if Code = 0 then
    Result := ''
  else
    Result := Trim(Output);
end;

function UriOf(AURI: PAnsiChar): string;
begin
  Result := string(UTF8String(AURI));
end;

procedure PutBytes(const ABytes: TBytes; ABuf: PByte; ABufSize: Int64; ATerminate: Boolean;
  out ANegotiated: Int64; out AFits: Boolean);
var
  Need: Int64;
begin
  Need := Length(ABytes);
  if ATerminate then
    Inc(Need);
  AFits := Need <= ABufSize;
  // Fitting: the length of the data alone (no terminator); otherwise the size to ask for.
  if AFits then
    ANegotiated := Length(ABytes)
  else
    ANegotiated := Need;
  if not AFits then
    Exit;
  if Length(ABytes) > 0 then
    Move(ABytes[0], ABuf^, Length(ABytes));
  if ATerminate then
    ABuf[Length(ABytes)] := 0;
end;

function EntryJson(const AName: string; AIsDir, AIsLink: Boolean; ASize, AModified: Int64): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AName);
  Result.AddPair('size', TJSONNumber.Create(ASize));
  Result.AddPair('isDir', TJSONBool.Create(AIsDir));
  Result.AddPair('isLink', TJSONBool.Create(AIsLink));
  Result.AddPair('isHidden', TJSONBool.Create(AName.StartsWith('.')));
  if AModified > 0 then
    Result.AddPair('modified', TJSONNumber.Create(AModified));
end;

// The listing carries local time, the tools report UTC.
function ToLocalSeconds(AUtcSeconds: Int64): Int64;
begin
  if AUtcSeconds <= 0 then
    Exit(0);
  Result := AUtcSeconds + Round(TTimeZone.Local.GetUtcOffset(UnixToDateTime(AUtcSeconds, True)).TotalSeconds);
end;

procedure AddFolder(const AArr: TJSONArray; const AName: string);
begin
  AArr.AddElement(EntryJson(AName, True, False, 0, 0));
end;

procedure AddFile(const AArr: TJSONArray; const AName: string);
begin
  AArr.AddElement(EntryJson(AName, False, False, 0, 0));
end;

procedure AddRows(const AArr: TJSONArray; const ARows: TContainerRows; const AFolderUri: string);
var
  R: TContainerRow;
  Colors: TJSONObject;
  Name: string;
begin
  Colors := TJSONObject.Create;
  try
    for R in ARows do
    begin
      Name := EncodeSegment(R.Name);
      AddFolder(AArr, Name);
      Colors.AddPair(Name, StateRole(R.State));
    end;
    if Assigned(GOnRowColors) then
      GOnRowColors(AFolderUri, Colors.ToJSON);
  finally
    Colors.Free;
  end;
end;

procedure AddImages(const AArr: TJSONArray; const ARows: TContainerRows);
var
  R: TContainerRow;
  Name: string;
begin
  for R in ARows do
  begin
    // An untagged image is addressed by its id.
    if R.Name.StartsWith(cNoneImage) then
      Name := R.State
    else
      Name := R.Name;
    AddFile(AArr, EncodeSegment(Name));
  end;
end;

function ListFsInto(ACtx: PVfsOpContext; const AAddr: TDockerAddr; const AArr: TJSONArray): Int64;
var
  Output, Dir: string;
  Entries: TFsEntries;
  E: TFsEntry;
begin
  Dir := AAddr.FsPath;
  if Dir[Length(Dir)] <> '/' then
    Dir := Dir + '/';
  Result := Run(nil, AAddr.Backend, ExecArgs(AAddr, False, ['find', Dir, '-mindepth', '1',
    '-maxdepth', '1', '-printf', '%y|%Y|%s|%T@|%f\n']), '', cListTimeoutMs, Output);
  if Result = Ord(verOk) then
    Entries := ParseFindListing(Output)
  else
  begin
    // Busybox find has no -printf: the fallback gives names and kinds only.
    Result := Run(ACtx, AAddr.Backend, ExecArgs(AAddr, False, ['ls', '-1AF', Dir]), '',
      cListTimeoutMs, Output);
    if Result <> Ord(verOk) then
      Exit;
    Entries := ParseLsListing(Output);
  end;
  for E in Entries do
    AArr.AddElement(EntryJson(E.Name, E.IsDir, E.IsLink, E.Size, ToLocalSeconds(E.Modified)));
end;

function ListInto(ACtx: PVfsOpContext; const AUri: string; const AAddr: TDockerAddr;
  const AArr: TJSONArray): Int64;
var
  Output, Name: string;
begin
  Result := Ord(verOk);
  case AAddr.Node of
    dnRoot:
      begin
        AddFolder(AArr, 'containers');
        AddFolder(AArr, 'images');
        AddFolder(AArr, cKubeDir);
      end;
    dnContainers:
      begin
        Result := Run(ACtx, dbDocker, ['ps', '-a', '--format', '{{.Names}}|{{.State}}|{{.Image}}'],
          '', cListTimeoutMs, Output);
        if Result = Ord(verOk) then
          AddRows(AArr, ParseContainerList(Output), AUri);
      end;
    dnImages:
      begin
        Result := Run(ACtx, dbDocker, ['images', '--format', '{{.Repository}}:{{.Tag}}|{{.ID}}'],
          '', cListTimeoutMs, Output);
        if Result = Ord(verOk) then
          AddImages(AArr, ParseContainerList(Output));
      end;
    dnNamespaces:
      begin
        Result := Run(ACtx, dbKube, ['get', 'namespaces', '-o', 'name'], '', cListTimeoutMs, Output);
        if Result = Ord(verOk) then
          for Name in ParseKubeNames(Output) do
            AddFolder(AArr, EncodeSegment(Name));
      end;
    dnPods:
      begin
        Result := Run(ACtx, dbKube, ['get', 'pods', '-n', AAddr.Ns, '--no-headers', '-o',
          'custom-columns=NAME:.metadata.name,STATUS:.status.phase'], '', cListTimeoutMs, Output);
        if Result = Ord(verOk) then
          AddRows(AArr, ParsePodList(Output), AUri);
      end;
    dnItem:
      begin
        AddFolder(AArr, cFsDir);
        AddFile(AArr, cInfoFile);
        AddFile(AArr, cLogsFile);
      end;
    dnFs:
      Result := ListFsInto(ACtx, AAddr, AArr);
  else
    Result := Ord(verNotFound);
  end;
end;

function VfsListDirectory(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  AOffset: Int64; ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64;
  out AMore: Int64): Int64; cdecl;
var
  Uri: string;
  Addr: TDockerAddr;
  Arr: TJSONArray;
  Bytes: TBytes;
  Fits: Boolean;
begin
  ANegotiatedSize := 0;
  AMore := 0;
  try
    Uri := UriOf(AURI);
    if not ParseDockerUri(Uri, Addr) then
      Exit(Ord(verInvalidURI));
    // The whole listing goes in one page; a bigger one is asked again with a bigger buffer.
    if AOffset > 0 then
      Exit(Ord(verOk));
    Arr := TJSONArray.Create;
    try
      Result := ListInto(ACtx, Uri, Addr, Arr);
      if Result <> Ord(verOk) then
        Exit;
      Bytes := TEncoding.UTF8.GetBytes(Arr.ToJSON);
    finally
      Arr.Free;
    end;
    PutBytes(Bytes, PByte(ABuf), ABufSize, True, ANegotiatedSize, Fits);
    if Fits then
      Result := Ord(verOk)
    else
      Result := Ord(verNeedsBiggerBuffer);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

// 0 on a path that is a folder, 1 on a file; an error code when it is not there.
function FsKind(ACtx: PVfsOpContext; const AAddr: TDockerAddr; out AIsDir: Boolean): Int64;
var
  Output: string;
begin
  AIsDir := True;
  if AAddr.FsPath = '/' then
    Exit(Ord(verOk));
  if Run(nil, AAddr.Backend, ExecArgs(AAddr, False, ['test', '-d', AAddr.FsPath]), '',
       cListTimeoutMs, Output) = Ord(verOk) then
    Exit(Ord(verOk));
  AIsDir := False;
  Result := Run(ACtx, AAddr.Backend, ExecArgs(AAddr, False, ['test', '-e', AAddr.FsPath]), '',
    cListTimeoutMs, Output);
  if Result <> Ord(verOk) then
    Result := Ord(verNotFound);
end;

function VfsExists(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  out AIsDirectory: Int64): Int64; cdecl;
var
  Addr: TDockerAddr;
  Output: string;
  IsDir: Boolean;
begin
  AIsDirectory := 0;
  try
    if not ParseDockerUri(UriOf(AURI), Addr) then
      Exit(Ord(verInvalidURI));
    case Addr.Node of
      dnRoot, dnContainers, dnImages, dnNamespaces, dnPods:
        begin
          AIsDirectory := 1;
          Result := Ord(verOk);
        end;
      dnItem:
        begin
          AIsDirectory := 1;
          if Addr.Backend = dbKube then
            Result := Run(nil, dbKube, ['get', 'pod', '-n', Addr.Ns, Addr.Name, '-o', 'name'], '',
              cListTimeoutMs, Output)
          else
            Result := Run(nil, dbDocker, ['container', 'inspect', '-f', '{{.Id}}', Addr.Name], '',
              cListTimeoutMs, Output);
          if Result <> Ord(verOk) then
            Result := Ord(verNotFound);
        end;
      dnInfo, dnLogs:
        Result := Ord(verOk);
      dnImage:
        begin
          Result := Run(nil, dbDocker, ['image', 'inspect', '-f', '{{.Id}}', Addr.Name], '',
            cListTimeoutMs, Output);
          if Result <> Ord(verOk) then
            Result := Ord(verNotFound);
        end;
      dnFs:
        begin
          Result := FsKind(ACtx, Addr, IsDir);
          if (Result = Ord(verOk)) and IsDir then
            AIsDirectory := 1;
        end;
    else
      Result := Ord(verInvalidURI);
    end;
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

// The text F3 shows, or the content of a file inside the container.
function ItemText(ACtx: PVfsOpContext; const AAddr: TDockerAddr; out AText: string): Int64;
begin
  case AAddr.Node of
    dnInfo, dnImage:
      Result := Run(ACtx, AAddr.Backend, InfoArgs(AAddr), '', cReadTimeoutMs, AText);
    dnLogs:
      Result := Run(ACtx, AAddr.Backend, LogsArgs(AAddr), '', cReadTimeoutMs, AText);
    dnFs:
      Result := Run(ACtx, AAddr.Backend, ExecArgs(AAddr, False, ['cat', AAddr.FsPath]), '',
        cReadTimeoutMs, AText);
  else
    Result := Fail(ACtx, verNotSupported, 'Not a file');
  end;
end;

function ReadItem(AURI: PAnsiChar; AMaxBytes: Int64; ACtx: PVfsOpContext; ABuf: PByte;
  ABufSize: Int64; ATerminate: Boolean; out ANegotiated: Int64): Int64;
var
  Addr: TDockerAddr;
  Text: string;
  Bytes: TBytes;
  Fits: Boolean;
begin
  ANegotiated := 0;
  try
    if not ParseDockerUri(UriOf(AURI), Addr) then
      Exit(Ord(verInvalidURI));
    Result := ItemText(ACtx, Addr, Text);
    if Result <> Ord(verOk) then
      Exit;
    Bytes := TEncoding.UTF8.GetBytes(Text);
    if (AMaxBytes > 0) and (Length(Bytes) > AMaxBytes) then
      SetLength(Bytes, AMaxBytes);
    PutBytes(Bytes, ABuf, ABufSize, ATerminate, ANegotiated, Fits);
    if Fits then
      Result := Ord(verOk)
    else
      Result := Ord(verNeedsBiggerBuffer);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsReadText(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext; ABuf: PAnsiChar; ABufSize: Int64;
  out ANegotiatedSize: Int64): Int64; cdecl;
begin
  Result := ReadItem(AURI, AMaxBytes, ACtx, PByte(ABuf), ABufSize, True, ANegotiatedSize);
end;

function VfsReadBytes(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext; ABuf: PByte; ABufSize: Int64;
  out ANegotiatedSize: Int64): Int64; cdecl;
begin
  Result := ReadItem(AURI, AMaxBytes, ACtx, ABuf, ABufSize, False, ANegotiatedSize);
end;

function VfsWriteText(AURI: PAnsiChar; AText: PAnsiChar; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  Addr: TDockerAddr;
  Output: string;
begin
  try
    if not ParseDockerUri(UriOf(AURI), Addr) then
      Exit(Ord(verInvalidURI));
    if (Addr.Node <> dnFs) or (Addr.FsPath = '/') then
      Exit(Fail(ACtx, verNotSupported, 'Only files inside a container can be written'));
    Result := Run(ACtx, Addr.Backend, ExecArgs(Addr, True,
      ['sh', '-c', 'cat > "$1"', 'sh', Addr.FsPath]), string(UTF8String(AText)),
      cReadTimeoutMs, Output);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsDelete(AURI: PAnsiChar; AMode: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  Addr: TDockerAddr;
  Output: string;
begin
  try
    if not ParseDockerUri(UriOf(AURI), Addr) then
      Exit(Ord(verInvalidURI));
    case Addr.Node of
      dnItem, dnImage:
        Result := Run(ACtx, Addr.Backend, RemoveArgs(Addr), '', cControlTimeoutMs, Output);
      dnFs:
        if Addr.FsPath = '/' then
          Result := Fail(ACtx, verNotSupported, 'The root of a container is not deleted')
        else
          Result := Run(ACtx, Addr.Backend, ExecArgs(Addr, False, ['rm', '-rf', Addr.FsPath]), '',
            cControlTimeoutMs, Output);
    else
      Result := Fail(ACtx, verNotSupported, 'This item cannot be deleted');
    end;
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsCreateDirectory(AURI: PAnsiChar; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  Addr: TDockerAddr;
  Output: string;
begin
  try
    if not ParseDockerUri(UriOf(AURI), Addr) then
      Exit(Ord(verInvalidURI));
    if Addr.Node <> dnFs then
      Exit(Fail(ACtx, verNotSupported, 'Folders are made inside a container only'));
    Result := Run(ACtx, Addr.Backend, ExecArgs(Addr, False, ['mkdir', '-p', Addr.FsPath]), '',
      cListTimeoutMs, Output);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

// One side is a file inside a container, the other a local file: "cp" moves it.
function VfsCopyItem(AFromURI, AToURI: PAnsiChar; AFlags: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  From, To_, Local: string;
  FromAddr, ToAddr: TDockerAddr;
  FromRemote, ToRemote: Boolean;
  Output: string;
begin
  try
    From := UriOf(AFromURI);
    To_ := UriOf(AToURI);
    FromRemote := ParseDockerUri(From, FromAddr);
    ToRemote := ParseDockerUri(To_, ToAddr);
    if FromRemote and ToRemote then
      Exit(Fail(ACtx, verNotSupported, 'Copying between containers is not supported'));
    if FromRemote and (FromAddr.Node = dnFs) then
    begin
      Local := FileUriToPath(To_);
      if Local = '' then
        Exit(Fail(ACtx, verNotSupported, 'Only a local folder can receive the files'));
      Result := Run(ACtx, FromAddr.Backend, CopyArgs(FromAddr, True, Local), '', cCopyTimeoutMs, Output);
    end
    else if ToRemote and (ToAddr.Node = dnFs) then
    begin
      Local := FileUriToPath(From);
      if Local = '' then
        Exit(Fail(ACtx, verNotSupported, 'Only local files can be sent from here'));
      Result := Run(ACtx, ToAddr.Backend, CopyArgs(ToAddr, False, Local), '', cCopyTimeoutMs, Output);
    end
    else
      Result := Fail(ACtx, verNotSupported, 'Only files inside a container can be copied');
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsMoveItem(AFromURI, AToURI: PAnsiChar; AFlags: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
begin
  Result := Fail(ACtx, verNotSupported, 'Moving is not supported here');
end;

function VfsGetFreeSpace(ARootURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  out AFree, ATotal: Int64): Int64; cdecl;
begin
  AFree := 0;
  ATotal := 0;
  Result := Ord(verNotSupported);
end;

function DockerVfsCallbacks: TVfsCallbacksCdeclV2;
begin
  Result := Default(TVfsCallbacksCdeclV2);
  Result.ListDirectory := VfsListDirectory;
  Result.Delete := VfsDelete;
  Result.CreateDirectory := VfsCreateDirectory;
  Result.CopyItem := VfsCopyItem;
  Result.MoveItem := VfsMoveItem;
  Result.ReadText := VfsReadText;
  Result.ReadBytes := VfsReadBytes;
  Result.WriteText := VfsWriteText;
  Result.Exists := VfsExists;
  Result.GetFreeSpace := VfsGetFreeSpace;
end;

initialization
  GRunTool := DefaultRunTool;

end.
