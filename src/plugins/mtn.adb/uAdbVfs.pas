unit uAdbVfs;

{ The version 2 VFS callbacks for adb:///. Every operation runs the adb program
  (GRunAdb) and maps its exit code and text to a result code of the plugin ABI.
  Exit codes of commands run on the device come through "adb shell" from
  Android 7 on. File data moves with "pull" and "push"; F3 and F4 read a file
  as base64 and write it by pushing a temporary file. }

interface

uses
  uPluginHostAbi, uPlatformProcess, uVfsTypes, uAdbFormat;

type
  TRunAdbFunc = function(const AArgs: TArray<string>; ATimeoutMs: Cardinal;
    ACancel: IJobCancelToken; out AOutput: string; out ACode: Cardinal): TSpawnResult;

  /// <summary>Gets the folder address and a JSON object {row name: color role}
  /// after the devices are listed. Called on the thread that listed.</summary>
  TRowColorsEvent = procedure(const AFolderUri, AJson: string);

  /// <summary>The messages the panel shows; the plugin translates them when it
  /// starts, because the calls come from worker threads.</summary>
  TAdbTexts = record
    NoProgram: string;
    Timeout: string;
    Unauthorized: string;
    Offline: string;
    NotConnected: string;
    NoPermissions: string;
  end;

var
  /// <summary>The program runner; tests put a fake one here.</summary>
  GRunAdb: TRunAdbFunc;
  GOnRowColors: TRowColorsEvent;
  GAdbText: TAdbTexts;

function DefaultRunAdb(const AArgs: TArray<string>; ATimeoutMs: Cardinal;
  ACancel: IJobCancelToken; out AOutput: string; out ACode: Cardinal): TSpawnResult;

function AdbVfsCallbacks: TVfsCallbacksCdeclV2;

implementation

uses
  System.SysUtils, System.Classes, System.StrUtils, System.JSON, System.IOUtils,
  System.DateUtils, System.TimeSpan, System.NetEncoding;

const
  cListTimeoutMs = 30000;
  cReadTimeoutMs = 120000;
  cCommandTimeoutMs = 600000;
  cNoTimeout = 0;
  cFlagOverwrite = 1;
  cFlagKeepTimes = 2;

type
  // Lets a running transfer be stopped when the host cancels the operation.
  TCtxCancel = class(TInterfacedObject, IJobCancelToken)
  private
    FCtx: PVfsOpContext;
  public
    constructor Create(ACtx: PVfsOpContext);
    function IsCancellationRequested: Boolean;
    procedure Cancel;
  end;

  TRemoteKind = (rkNone, rkFile, rkDir);

constructor TCtxCancel.Create(ACtx: PVfsOpContext);
begin
  inherited Create;
  FCtx := ACtx;
end;

function TCtxCancel.IsCancellationRequested: Boolean;
begin
  Result := (FCtx <> nil) and Assigned(FCtx^.IsCancelled) and (FCtx^.IsCancelled(FCtx) <> 0);
end;

procedure TCtxCancel.Cancel;
begin
  // Only the host cancels.
end;

function DefaultRunAdb(const AArgs: TArray<string>; ATimeoutMs: Cardinal;
  ACancel: IJobCancelToken; out AOutput: string; out ACode: Cardinal): TSpawnResult;
var
  Path: string;
begin
  Result := PlatformRunCaptured(cAdb, AArgs, '', ATimeoutMs, ACancel, AOutput, ACode);
  if Result <> srSpawnFailed then
    Exit;
  // Installing the SDK does not add platform-tools to PATH.
  for Path in AdbSdkPrograms(
    function(AName: string): string
    begin
      Result := GetEnvironmentVariable(AName);
    end) do
    if FileExists(Path) then
      Exit(PlatformRunCaptured(Path, AArgs, '', ATimeoutMs, ACancel, AOutput, ACode));
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

function Succeeded(AResult: Int64): Boolean;
begin
  Result := AResult = Ord(verOk);
end;

// Runs adb; verOk means the program ran, whatever its exit code.
function Start(ACtx: PVfsOpContext; const AArgs: TArray<string>; ATimeoutMs: Cardinal;
  out AOutput: string; out ACode: Cardinal): Int64;
var
  Cancel: IJobCancelToken;
begin
  Cancel := nil;
  if ACtx <> nil then
    Cancel := TCtxCancel.Create(ACtx);
  case GRunAdb(AArgs, ATimeoutMs, Cancel, AOutput, ACode) of
    srSpawnFailed:
      Exit(Fail(ACtx, verIOError, GAdbText.NoProgram));
    srTimeout:
      Exit(Fail(ACtx, verTimeout, GAdbText.Timeout));
    srCancelled:
      Exit(Ord(verCancelled));
  end;
  AOutput := StripDaemonNoise(AOutput);
  Result := Ord(verOk);
end;

// The result code and message for a nonzero exit code.
function Failure(ACtx: PVfsOpContext; const AOutput: string): Int64;
begin
  case AdbProblem(AOutput) of
    apUnauthorized:
      Result := Fail(ACtx, verAccessDenied, GAdbText.Unauthorized);
    apOffline:
      Result := Fail(ACtx, verIOError, GAdbText.Offline);
    apNotConnected:
      Result := Fail(ACtx, verNotFound, GAdbText.NotConnected);
    apNoPermissions:
      Result := Fail(ACtx, verAccessDenied, GAdbText.NoPermissions);
  else
    if ContainsText(AOutput, 'No such file') then
      Result := Fail(ACtx, verNotFound, AOutput)
    else if ContainsText(AOutput, 'Permission denied') or ContainsText(AOutput, 'Read-only file') or
            ContainsText(AOutput, 'not permitted') then
      Result := Fail(ACtx, verAccessDenied, AOutput)
    else if ContainsText(AOutput, 'File exists') then
      Result := Fail(ACtx, verAlreadyExists, AOutput)
    else
      Result := Fail(ACtx, verIOError, AOutput);
  end;
end;

function Run(ACtx: PVfsOpContext; const AArgs: TArray<string>; ATimeoutMs: Cardinal;
  out AOutput: string): Int64;
var
  Code: Cardinal;
begin
  Result := Start(ACtx, AArgs, ATimeoutMs, AOutput, Code);
  if Succeeded(Result) and (Code <> 0) then
    Result := Failure(ACtx, AOutput);
end;

function Shell(ACtx: PVfsOpContext; const ASerial, AScript: string; ATimeoutMs: Cardinal): Int64;
var
  Output: string;
begin
  Result := Run(ACtx, ShellArgs(ASerial, AScript), ATimeoutMs, Output);
end;

function KindOf(ACtx: PVfsOpContext; const ASerial, APath: string; out AKind: TRemoteKind): Int64;
var
  Output, Answer: string;
begin
  AKind := rkNone;
  Result := Run(ACtx, ShellArgs(ASerial, KindScript(APath)), cListTimeoutMs, Output);
  if not Succeeded(Result) then
    Exit;
  Answer := Trim(Output);
  if Answer = 'd' then
    AKind := rkDir
  else if Answer = 'f' then
    AKind := rkFile
  else if Answer <> 'n' then
    Result := Failure(ACtx, Output);
end;

function UriOf(AURI: PAnsiChar): string;
begin
  Result := string(UTF8String(AURI));
end;

// A file or folder below the root of a device: what can be changed.
function ParseItemUri(const AUri: string; out AAddr: TAdbAddr): Boolean;
begin
  Result := ParseAdbUri(AUri, AAddr) and (AAddr.Node = anFs) and (AAddr.Path <> '/');
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

function EntryJson(const AName: string; AIsDir, AIsLink, AIsHidden: Boolean;
  ASize, AModified: Int64): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AName);
  Result.AddPair('size', TJSONNumber.Create(ASize));
  Result.AddPair('isDir', TJSONBool.Create(AIsDir));
  Result.AddPair('isLink', TJSONBool.Create(AIsLink));
  Result.AddPair('isHidden', TJSONBool.Create(AIsHidden));
  if AModified > 0 then
    Result.AddPair('modified', TJSONNumber.Create(AModified));
end;

// The listing carries local time, the device reports UTC.
function ToLocalSeconds(AUtcSeconds: Int64): Int64;
begin
  if AUtcSeconds <= 0 then
    Exit(0);
  Result := AUtcSeconds + Round(TTimeZone.Local.GetUtcOffset(UnixToDateTime(AUtcSeconds, True)).TotalSeconds);
end;

function ListDevices(ACtx: PVfsOpContext; const AUri: string; const AArr: TJSONArray): Int64;
var
  Output, Name: string;
  Device: TAdbDevice;
  Entry, Extra, Colors: TJSONObject;
begin
  Result := Run(ACtx, DevicesArgs, cListTimeoutMs, Output);
  if not Succeeded(Result) then
    Exit;
  Colors := TJSONObject.Create;
  try
    for Device in ParseDeviceList(Output) do
    begin
      Name := EncodeSegment(Device.Serial);
      Entry := EntryJson(Name, True, False, False, 0, 0);
      Extra := TJSONObject.Create;
      Extra.AddPair('state', Device.State);
      if Device.Model <> '' then
        Extra.AddPair('model', Device.Model);
      if Device.Product <> '' then
        Extra.AddPair('product', Device.Product);
      Entry.AddPair('extra', Extra);
      AArr.AddElement(Entry);
      Colors.AddPair(Name, IfThen(Device.State = cReadyState, 'ok', 'warn'));
    end;
    if Assigned(GOnRowColors) then
      GOnRowColors(AUri, Colors.ToJSON);
  finally
    Colors.Free;
  end;
end;

function ListFolder(ACtx: PVfsOpContext; const AAddr: TAdbAddr; const AArr: TJSONArray): Int64;
var
  Output: string;
  Code: Cardinal;
  Entries: TAdbEntries;
  E: TAdbEntry;
begin
  Result := Start(ACtx, ShellArgs(AAddr.Serial, ListScript(AAddr.Path)), cListTimeoutMs, Output, Code);
  if not Succeeded(Result) then
    Exit;
  Entries := ParseStatListing(Output);
  // Some entries of a system folder may be closed to the shell user; the rest
  // are still worth showing.
  if (Code <> 0) and (Length(Entries) = 0) then
    Exit(Failure(ACtx, Output));
  for E in Entries do
    AArr.AddElement(EntryJson(E.Name, E.IsDir, E.IsLink, E.Name.StartsWith('.'), E.Size,
      ToLocalSeconds(E.Modified)));
end;

function VfsListDirectory(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  AOffset: Int64; ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64;
  out AMore: Int64): Int64; cdecl;
var
  Uri: string;
  Addr: TAdbAddr;
  Arr: TJSONArray;
  Bytes: TBytes;
  Fits: Boolean;
begin
  ANegotiatedSize := 0;
  AMore := 0;
  try
    Uri := UriOf(AURI);
    if not ParseAdbUri(Uri, Addr) then
      Exit(Ord(verInvalidURI));
    // The whole listing goes in one page; a bigger one is asked again with a bigger buffer.
    if AOffset > 0 then
      Exit(Ord(verOk));
    Arr := TJSONArray.Create;
    try
      if Addr.Node = anRoot then
        Result := ListDevices(ACtx, Uri, Arr)
      else
        Result := ListFolder(ACtx, Addr, Arr);
      if not Succeeded(Result) then
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

function VfsExists(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  out AIsDirectory: Int64): Int64; cdecl;
var
  Addr: TAdbAddr;
  Output: string;
  Kind: TRemoteKind;
begin
  AIsDirectory := 0;
  try
    if not ParseAdbUri(UriOf(AURI), Addr) then
      Exit(Ord(verInvalidURI));
    if Addr.Node = anRoot then
    begin
      AIsDirectory := 1;
      Exit(Ord(verOk));
    end;
    if Addr.Path = '/' then
    begin
      Result := Run(ACtx, StateArgs(Addr.Serial), cListTimeoutMs, Output);
      if Succeeded(Result) then
        AIsDirectory := 1;
      Exit;
    end;
    Result := KindOf(ACtx, Addr.Serial, Addr.Path, Kind);
    if not Succeeded(Result) then
      Exit;
    if Kind = rkNone then
      Exit(Ord(verNotFound));
    if Kind = rkDir then
      AIsDirectory := 1;
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function ReadItem(AURI: PAnsiChar; AMaxBytes: Int64; ACtx: PVfsOpContext; ABuf: PByte;
  ABufSize: Int64; ATerminate: Boolean; out ANegotiated: Int64): Int64;
var
  Addr: TAdbAddr;
  Output: string;
  Bytes: TBytes;
  Fits: Boolean;
begin
  ANegotiated := 0;
  try
    if not ParseItemUri(UriOf(AURI), Addr) then
      Exit(Fail(ACtx, verNotSupported, 'Not a file'));
    Result := Run(ACtx, ShellArgs(Addr.Serial, ReadScript(Addr.Path, AMaxBytes)), cReadTimeoutMs, Output);
    if not Succeeded(Result) then
      Exit;
    Bytes := TNetEncoding.Base64.DecodeStringToBytes(Output.Replace(#13, '').Replace(#10, ''));
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
  Addr: TAdbAddr;
  Output, Temp: string;
  Bytes: TBytes;
begin
  try
    if not ParseItemUri(UriOf(AURI), Addr) then
      Exit(Fail(ACtx, verNotSupported, 'Only files of a device can be written'));
    SetLength(Bytes, Length(AnsiString(AText)));
    if Length(Bytes) > 0 then
      Move(AText^, Bytes[0], Length(Bytes));
    Temp := TPath.Combine(TPath.GetTempPath, 'mtn2-adb-' + TGUID.NewGuid.ToString);
    TFile.WriteAllBytes(Temp, Bytes);
    try
      Result := Run(ACtx, PushArgs(Addr.Serial, Temp, Addr.Path), cCommandTimeoutMs, Output);
    finally
      TFile.Delete(Temp);
    end;
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsDelete(AURI: PAnsiChar; AMode: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  Addr: TAdbAddr;
begin
  try
    if not ParseItemUri(UriOf(AURI), Addr) then
      Exit(Fail(ACtx, verNotSupported, 'Only files and folders of a device are deleted'));
    Result := Shell(ACtx, Addr.Serial, RemoveScript(Addr.Path), cCommandTimeoutMs);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsCreateDirectory(AURI: PAnsiChar; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  Addr: TAdbAddr;
begin
  try
    if not ParseItemUri(UriOf(AURI), Addr) then
      Exit(Fail(ACtx, verNotSupported, 'Folders are made on a device only'));
    Result := Shell(ACtx, Addr.Serial, MkdirScript(Addr.Path), cListTimeoutMs);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function AlreadyExists(ACtx: PVfsOpContext; const APath: string): Int64;
begin
  Result := Fail(ACtx, verAlreadyExists, 'Already exists: ' + APath);
end;

// The panel copies a folder of a device file by file, so one item arrives here.
function PullItem(ACtx: PVfsOpContext; const AFrom: TAdbAddr; const ALocal: string;
  AFlags: Int64): Int64;
var
  Output: string;
begin
  // pull would put the source inside an existing folder.
  if TDirectory.Exists(ALocal) or
     (((AFlags and cFlagOverwrite) = 0) and TFile.Exists(ALocal)) then
    Exit(AlreadyExists(ACtx, ALocal));
  Result := Run(ACtx, PullArgs(AFrom.Serial, AFrom.Path, ALocal, (AFlags and cFlagKeepTimes) <> 0),
    cNoTimeout, Output);
end;

// push leaves out folders without files.
function MakeEmptyFolders(ACtx: PVfsOpContext; const ASerial, ALocal, ARemote: string): Int64;
var
  Dir: string;
begin
  if Length(TDirectory.GetFileSystemEntries(ALocal)) = 0 then
    Exit(Shell(ACtx, ASerial, MkdirScript(ARemote), cListTimeoutMs));
  Result := Ord(verOk);
  for Dir in TDirectory.GetDirectories(ALocal) do
  begin
    Result := MakeEmptyFolders(ACtx, ASerial, Dir, JoinDevicePath(ARemote, ExtractFileName(Dir)));
    if not Succeeded(Result) then
      Exit;
  end;
end;

// A folder that is not on the device yet is pushed in one run. Onto an existing
// one, push would nest it (name/name), so the children are sent one by one.
function PushItem(ACtx: PVfsOpContext; const ASerial, ALocal, ARemote: string;
  AOverwrite: Boolean): Int64;
var
  Kind: TRemoteKind;
  Child, Output: string;
  Cancel: IJobCancelToken;
begin
  Cancel := TCtxCancel.Create(ACtx);
  if Cancel.IsCancellationRequested then
    Exit(Ord(verCancelled));
  Result := KindOf(ACtx, ASerial, ARemote, Kind);
  if not Succeeded(Result) then
    Exit;
  if TDirectory.Exists(ALocal) then
  begin
    if Kind = rkFile then
      Exit(AlreadyExists(ACtx, ARemote));
    if Kind = rkDir then
    begin
      for Child in TDirectory.GetFileSystemEntries(ALocal) do
      begin
        Result := PushItem(ACtx, ASerial, Child, JoinDevicePath(ARemote, ExtractFileName(Child)),
          AOverwrite);
        if not Succeeded(Result) then
          Exit;
      end;
      Exit;
    end;
    if Length(TDirectory.GetFiles(ALocal, '*', TSearchOption.soAllDirectories)) > 0 then
    begin
      Result := Run(ACtx, PushArgs(ASerial, ALocal, ARemote), cNoTimeout, Output);
      if not Succeeded(Result) then
        Exit;
    end;
    Exit(MakeEmptyFolders(ACtx, ASerial, ALocal, ARemote));
  end;
  if not TFile.Exists(ALocal) then
    Exit(Fail(ACtx, verNotFound, 'Not found: ' + ALocal));
  if (Kind = rkDir) or ((Kind = rkFile) and not AOverwrite) then
    Exit(AlreadyExists(ACtx, ARemote));
  Result := Run(ACtx, PushArgs(ASerial, ALocal, ARemote), cNoTimeout, Output);
end;

function CopyOnDevice(ACtx: PVfsOpContext; const AFrom, ATo: TAdbAddr; AOverwrite: Boolean): Int64;
var
  FromKind, ToKind: TRemoteKind;
begin
  Result := KindOf(ACtx, AFrom.Serial, AFrom.Path, FromKind);
  if not Succeeded(Result) then
    Exit;
  if FromKind = rkNone then
    Exit(Fail(ACtx, verNotFound, 'Not found: ' + AFrom.Path));
  Result := KindOf(ACtx, ATo.Serial, ATo.Path, ToKind);
  if not Succeeded(Result) then
    Exit;
  if (ToKind <> rkNone) and (not AOverwrite or (ToKind <> FromKind)) then
    Exit(AlreadyExists(ACtx, ATo.Path));
  Result := Shell(ACtx, AFrom.Serial, CopyScript(AFrom.Path, ATo.Path, ToKind = rkDir),
    cCommandTimeoutMs);
end;

function VfsCopyItem(AFromURI, AToURI: PAnsiChar; AFlags: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  From, To_, Local: string;
  FromAddr, ToAddr: TAdbAddr;
  FromRemote, ToRemote: Boolean;
begin
  try
    From := UriOf(AFromURI);
    To_ := UriOf(AToURI);
    FromRemote := ParseAdbUri(From, FromAddr);
    ToRemote := ParseAdbUri(To_, ToAddr);
    if (FromRemote and ((FromAddr.Node <> anFs) or (FromAddr.Path = '/'))) or
       (ToRemote and ((ToAddr.Node <> anFs) or (ToAddr.Path = '/'))) then
      Exit(Fail(ACtx, verNotSupported, 'Only files and folders of a device can be copied'));
    if FromRemote and ToRemote then
    begin
      if FromAddr.Serial <> ToAddr.Serial then
        Exit(Fail(ACtx, verNotSupported, 'Copying between two devices is not supported'));
      Exit(CopyOnDevice(ACtx, FromAddr, ToAddr, (AFlags and cFlagOverwrite) <> 0));
    end;
    if FromRemote then
    begin
      Local := FileUriToPath(To_);
      if Local = '' then
        Exit(Fail(ACtx, verNotSupported, 'Only a local folder can receive the files'));
      Result := PullItem(ACtx, FromAddr, Local, AFlags);
    end
    else if ToRemote then
    begin
      Local := FileUriToPath(From);
      if Local = '' then
        Exit(Fail(ACtx, verNotSupported, 'Only local files can be sent from here'));
      Result := PushItem(ACtx, ToAddr.Serial, Local, ToAddr.Path, (AFlags and cFlagOverwrite) <> 0);
    end
    else
      Result := Ord(verInvalidURI);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

// Rename and move inside one device. The panel moves to and from a local folder
// as a copy followed by a delete.
function VfsMoveItem(AFromURI, AToURI: PAnsiChar; AFlags: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  FromAddr, ToAddr: TAdbAddr;
  Kind: TRemoteKind;
begin
  try
    if not ParseItemUri(UriOf(AFromURI), FromAddr) or not ParseItemUri(UriOf(AToURI), ToAddr) or
       (FromAddr.Serial <> ToAddr.Serial) then
      Exit(Fail(ACtx, verNotSupported, 'Items are moved inside one device only'));
    // A change of letter case: a card that ignores case reports the new name as taken.
    if not SameText(FromAddr.Path, ToAddr.Path) or (FromAddr.Path = ToAddr.Path) then
    begin
      Result := KindOf(ACtx, ToAddr.Serial, ToAddr.Path, Kind);
      if not Succeeded(Result) then
        Exit;
      // mv would put the source inside an existing folder.
      if (Kind = rkDir) or ((Kind = rkFile) and ((AFlags and cFlagOverwrite) = 0)) then
        Exit(AlreadyExists(ACtx, ToAddr.Path));
    end;
    Result := Shell(ACtx, FromAddr.Serial, MoveScript(FromAddr.Path, ToAddr.Path), cCommandTimeoutMs);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsGetFreeSpace(ARootURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  out AFree, ATotal: Int64): Int64; cdecl;
begin
  AFree := 0;
  ATotal := 0;
  Result := Ord(verNotSupported);
end;

function AdbVfsCallbacks: TVfsCallbacksCdeclV2;
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
  GRunAdb := DefaultRunAdb;
  GAdbText.NoProgram := 'adb was not found: install Android platform-tools, or add its folder to PATH.';
  GAdbText.Timeout := 'adb did not answer in time.';
  GAdbText.Unauthorized := 'The device is not authorized: allow USB debugging on its screen.';
  GAdbText.Offline := 'The device is offline: reconnect it.';
  GAdbText.NotConnected := 'The device is not connected.';
  GAdbText.NoPermissions := 'No permission to open the USB device (check the udev rules).';

end.
