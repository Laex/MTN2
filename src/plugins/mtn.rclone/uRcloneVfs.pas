unit uRcloneVfs;

{ The version 2 VFS callbacks for rclone:///. Every operation runs the rclone
  program (GRcRunTool) and maps its exit code and text to a result code of the
  plugin ABI. Listing, reading, writing, deleting and copying go through
  lsjson, cat, rcat, deletefile, purge, mkdir, copyto and moveto. }

interface

uses
  uPluginHostAbi;

type
  /// <summary>Runs a program; False when it could not be started or did not finish in time
  /// (AOutput then explains why). Otherwise ACode is its exit code.</summary>
  TRcRunFunc = function(const AExe: string; const AArgs: TArray<string>; const AStdIn: string;
    ATimeoutMs: Cardinal; out AOutput: string; out ACode: Cardinal): Boolean;

var
  /// <summary>The program runner; tests put a fake one here.</summary>
  GRcRunTool: TRcRunFunc;

function DefaultRcRunTool(const AExe: string; const AArgs: TArray<string>; const AStdIn: string;
  ATimeoutMs: Cardinal; out AOutput: string; out ACode: Cardinal): Boolean;

function RcloneVfsCallbacks: TVfsCallbacksCdeclV2;

implementation

uses
  System.SysUtils, System.Classes, System.StrUtils, System.JSON, System.DateUtils, System.TimeSpan,
  System.IOUtils, uVfsTypes, uPlatformProcess, uRcloneFormat;

const
  cListTimeoutMs = 120000;
  cReadTimeoutMs = 120000;
  cControlTimeoutMs = 120000;
  cCopyTimeoutMs = 3600000;

function DefaultRcRunTool(const AExe: string; const AArgs: TArray<string>; const AStdIn: string;
  ATimeoutMs: Cardinal; out AOutput: string; out ACode: Cardinal): Boolean;
var
  Status: TSpawnResult;
begin
  Status := PlatformRunCaptured(AExe, AArgs, AStdIn, ATimeoutMs, nil, AOutput, ACode);
  Result := Status = srOk;
  if Status = srTimeout then
    AOutput := Format('%s did not finish in %d s', [AExe, ATimeoutMs div 1000])
  else if Status <> srOk then
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

function CodeOfFailure(const AOutput: string): TVfsCdeclResult;
begin
  if ContainsText(AOutput, 'not found') or ContainsText(AOutput, 'no such') or
     ContainsText(AOutput, 'doesn''t exist') or ContainsText(AOutput, 'does not exist') then
    Result := verNotFound
  else if ContainsText(AOutput, 'denied') or ContainsText(AOutput, 'forbidden') or
          ContainsText(AOutput, 'not permitted') or ContainsText(AOutput, 'unauthorized') then
    Result := verAccessDenied
  else
    Result := verIOError;
end;

// verOk = done, otherwise the result code with the message set on ACtx.
function Run(ACtx: PVfsOpContext; const AArgs: TArray<string>; const AStdIn: string;
  ATimeoutMs: Cardinal; out AOutput: string): Int64;
var
  Code: Cardinal;
begin
  if not GRcRunTool(cRcloneExe, AArgs, AStdIn, ATimeoutMs, AOutput, Code) then
    Exit(Fail(ACtx, verIOError, AOutput));
  if Code <> 0 then
    Exit(Fail(ACtx, CodeOfFailure(AOutput), AOutput));
  Result := Ord(verOk);
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

function EntryJson(const AName: string; AIsDir: Boolean; ASize, AModified: Int64): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AName);
  Result.AddPair('size', TJSONNumber.Create(ASize));
  Result.AddPair('isDir', TJSONBool.Create(AIsDir));
  Result.AddPair('isLink', TJSONBool.Create(False));
  Result.AddPair('isHidden', TJSONBool.Create(AName.StartsWith('.')));
  if AModified > 0 then
    Result.AddPair('modified', TJSONNumber.Create(AModified));
end;

// The listing carries local time, rclone reports UTC.
function ToLocalSeconds(AUtcSeconds: Int64): Int64;
begin
  if AUtcSeconds <= 0 then
    Exit(0);
  Result := AUtcSeconds + Round(TTimeZone.Local.GetUtcOffset(UnixToDateTime(AUtcSeconds, True)).TotalSeconds);
end;

function ListInto(ACtx: PVfsOpContext; const AAddr: TRcAddr; const AArr: TJSONArray): Int64;
var
  Output, Name: string;
  E: TRcEntry;
begin
  if AAddr.Node = rnRoot then
  begin
    Result := Run(ACtx, ['listremotes', '--ask-password=false'], '', cListTimeoutMs, Output);
    if Result = Ord(verOk) then
      for Name in ParseRemotes(Output) do
        AArr.AddElement(EntryJson(RcEncode(Name), True, 0, 0));
    Exit;
  end;
  Result := Run(ACtx, ListArgs(AAddr), '', cListTimeoutMs, Output);
  if Result <> Ord(verOk) then
    Exit;
  for E in ParseLsJson(Output) do
    AArr.AddElement(EntryJson(RcEncode(E.Name), E.IsDir, E.Size, ToLocalSeconds(E.Modified)));
end;

function VfsListDirectory(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  AOffset: Int64; ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64;
  out AMore: Int64): Int64; cdecl;
var
  Addr: TRcAddr;
  Arr: TJSONArray;
  Bytes: TBytes;
  Fits: Boolean;
begin
  ANegotiatedSize := 0;
  AMore := 0;
  try
    if not ParseRcloneUri(UriOf(AURI), Addr) then
      Exit(Ord(verInvalidURI));
    // The whole listing goes in one page; a bigger one is asked again with a bigger buffer.
    if AOffset > 0 then
      Exit(Ord(verOk));
    Arr := TJSONArray.Create;
    try
      Result := ListInto(ACtx, Addr, Arr);
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

// What the remote holds at the address: a folder, a file, or an error code.
function Stat(ACtx: PVfsOpContext; const AAddr: TRcAddr; out AEntry: TRcEntry): Int64;
var
  Output: string;
begin
  AEntry := Default(TRcEntry);
  if AAddr.Path = '' then
  begin
    AEntry.IsDir := True;
    Exit(Ord(verOk));
  end;
  Result := Run(ACtx, StatArgs(AAddr), '', cListTimeoutMs, Output);
  if Result <> Ord(verOk) then
    Exit;
  if not ParseStatJson(Output, AEntry) then
    Result := Fail(ACtx, verNotFound, 'Not found');
end;

function VfsExists(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  out AIsDirectory: Int64): Int64; cdecl;
var
  Addr: TRcAddr;
  Entry: TRcEntry;
begin
  AIsDirectory := 0;
  try
    if not ParseRcloneUri(UriOf(AURI), Addr) then
      Exit(Ord(verInvalidURI));
    if Addr.Node = rnRoot then
    begin
      AIsDirectory := 1;
      Exit(Ord(verOk));
    end;
    Result := Stat(ACtx, Addr, Entry);
    if (Result = Ord(verOk)) and Entry.IsDir then
      AIsDirectory := 1;
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

// The last AMaxBytes of a file another program may still be writing; '' when
// it cannot be read.
function ReadFileTail(const APath: string; AMaxBytes: Integer): string;
var
  FS: TFileStream;
  Buf: TBytes;
begin
  Result := '';
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if FS.Size > AMaxBytes then
        FS.Position := FS.Size - AMaxBytes;
      SetLength(Buf, FS.Size - FS.Position);
      if Length(Buf) > 0 then
        SetLength(Buf, FS.Read(Buf[0], Length(Buf)));
      Result := TEncoding.UTF8.GetString(Buf);
    finally
      FS.Free;
    end;
  except
    Result := '';
  end;
end;

type
  /// <summary>Follows the totals log of a running transfer and passes them to
  /// the host. The context must outlive the thread: stop it before the call
  /// that owns the context returns.</summary>
  TStatsFollower = class(TThread)
  private
    FCtx: PVfsOpContext;
    FLog: string;
  protected
    procedure Execute; override;
  public
    constructor Create(ACtx: PVfsOpContext; const ALog: string);
  end;

constructor TStatsFollower.Create(ACtx: PVfsOpContext; const ALog: string);
begin
  FCtx := ACtx;
  FLog := ALog;
  inherited Create(False);
end;

procedure TStatsFollower.Execute;
const
  cPollMs = 100;
  // A totals line names every file in flight; one file fits well within this.
  cTailBytes = 16384;
var
  Done, Total, LastDone: Int64;
begin
  LastDone := -1;
  while not Terminated do
  begin
    Sleep(cPollMs);
    if ParseStatsLog(ReadFileTail(FLog, cTailBytes), Done, Total) and (Done <> LastDone) then
    begin
      LastDone := Done;
      FCtx^.ReportProgress(FCtx, Done, Total, Done, Total, nil);
    end;
  end;
end;

// Copies the remote file to ATmp. With a context that takes progress the
// transfer logs its totals to a file next to ATmp, which a follower reads;
// the log then also holds the error text that otherwise comes on the output.
function CopyToTemp(ACtx: PVfsOpContext; const AAddr: TRcAddr; const ATmp: string): Int64;
var
  Output, Log, Text: string;
  Args: TArray<string>;
  Follower: TStatsFollower;
begin
  Args := CopyToArgs(RemoteSpec(AAddr), ATmp, False);
  if (ACtx = nil) or not Assigned(ACtx^.ReportProgress) then
    Exit(Run(ACtx, Args, '', cCopyTimeoutMs, Output));
  Log := ATmp + '.log';
  Follower := TStatsFollower.Create(ACtx, Log);
  try
    try
      Result := Run(ACtx, Args + StatsLogArgs(Log), '', cCopyTimeoutMs, Output);
    finally
      Follower.Terminate;
      Follower.WaitFor;
    end;
    if Result <> Ord(verOk) then
    begin
      Text := LogMessages(ReadFileTail(Log, 65536));
      if Text <> '' then
        Result := Fail(ACtx, CodeOfFailure(Text), Text);
    end;
  finally
    Follower.Free;
    if TFile.Exists(Log) then
      TFile.Delete(Log);
  end;
end;

// Reads the file: text through "cat", bytes through a temporary local copy so that
// binary content survives.
function ReadContent(ACtx: PVfsOpContext; const AAddr: TRcAddr; AMaxBytes: Int64;
  AAsBytes: Boolean; out ABytes: TBytes): Int64;
var
  Output, Tmp: string;
begin
  ABytes := nil;
  if not AAsBytes then
  begin
    Result := Run(ACtx, CatArgs(AAddr, AMaxBytes), '', cReadTimeoutMs, Output);
    if Result = Ord(verOk) then
      ABytes := TEncoding.UTF8.GetBytes(Output);
    Exit;
  end;
  Tmp := TPath.GetTempFileName;
  try
    Result := CopyToTemp(ACtx, AAddr, Tmp);
    if Result = Ord(verOk) then
      ABytes := TFile.ReadAllBytes(Tmp);
  finally
    if TFile.Exists(Tmp) then
      TFile.Delete(Tmp);
  end;
end;

function ReadItem(AURI: PAnsiChar; AMaxBytes: Int64; ACtx: PVfsOpContext; ABuf: PByte;
  ABufSize: Int64; ATerminate: Boolean; out ANegotiated: Int64): Int64;
var
  Addr: TRcAddr;
  Bytes: TBytes;
  Fits: Boolean;
begin
  ANegotiated := 0;
  try
    if not ParseRcloneUri(UriOf(AURI), Addr) or (Addr.Node <> rnPath) or (Addr.Path = '') then
      Exit(Ord(verInvalidURI));
    Result := ReadContent(ACtx, Addr, AMaxBytes, not ATerminate, Bytes);
    if Result <> Ord(verOk) then
      Exit;
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
  Addr: TRcAddr;
  Output: string;
begin
  try
    if not ParseRcloneUri(UriOf(AURI), Addr) or (Addr.Node <> rnPath) or (Addr.Path = '') then
      Exit(Ord(verInvalidURI));
    Result := Run(ACtx, ['rcat', '--ask-password=false', RemoteSpec(Addr)],
      string(UTF8String(AText)), cReadTimeoutMs, Output);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsDelete(AURI: PAnsiChar; AMode: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  Addr: TRcAddr;
  Entry: TRcEntry;
  Output, Verb: string;
begin
  try
    if not ParseRcloneUri(UriOf(AURI), Addr) or (Addr.Node <> rnPath) then
      Exit(Ord(verInvalidURI));
    if Addr.Path = '' then
      Exit(Fail(ACtx, verNotSupported, 'A remote is deleted in the rclone configuration'));
    Result := Stat(ACtx, Addr, Entry);
    if Result <> Ord(verOk) then
      Exit;
    // purge removes a folder with everything in it, deletefile one file.
    if Entry.IsDir then
      Verb := 'purge'
    else
      Verb := 'deletefile';
    Result := Run(ACtx, [Verb, '--ask-password=false', RemoteSpec(Addr)], '',
      cControlTimeoutMs, Output);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsCreateDirectory(AURI: PAnsiChar; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  Addr: TRcAddr;
  Output: string;
begin
  try
    if not ParseRcloneUri(UriOf(AURI), Addr) or (Addr.Node <> rnPath) or (Addr.Path = '') then
      Exit(Ord(verInvalidURI));
    Result := Run(ACtx, ['mkdir', '--ask-password=false', RemoteSpec(Addr)], '',
      cControlTimeoutMs, Output);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

// The rclone spec of a local folder or file, or of a remote path; '' when the address is neither.
function SpecOf(const AUri: string): string;
var
  Addr: TRcAddr;
begin
  if ParseRcloneUri(AUri, Addr) then
  begin
    if (Addr.Node = rnPath) and (Addr.Path <> '') then
      Exit(RemoteSpec(Addr));
    Exit('');
  end;
  Result := FileUriToPath(AUri);
end;

function TransferItem(AFromURI, AToURI: PAnsiChar; ACtx: PVfsOpContext; AMove: Boolean): Int64;
var
  From, To_, FromSpec, ToSpec, Output: string;
  Addr: TRcAddr;
begin
  try
    From := UriOf(AFromURI);
    To_ := UriOf(AToURI);
    // One side at least lives on a remote; two local paths are the host's own business.
    if not (ParseRcloneUri(From, Addr) or ParseRcloneUri(To_, Addr)) then
      Exit(Fail(ACtx, verNotSupported, 'Not a remote path'));
    FromSpec := SpecOf(From);
    ToSpec := SpecOf(To_);
    if (FromSpec = '') or (ToSpec = '') then
      Exit(Fail(ACtx, verNotSupported, 'Only files of a remote and local files can be transferred'));
    Result := Run(ACtx, CopyToArgs(FromSpec, ToSpec, AMove), '', cCopyTimeoutMs, Output);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsCopyItem(AFromURI, AToURI: PAnsiChar; AFlags: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
begin
  Result := TransferItem(AFromURI, AToURI, ACtx, False);
end;

function VfsMoveItem(AFromURI, AToURI: PAnsiChar; AFlags: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
begin
  Result := TransferItem(AFromURI, AToURI, ACtx, True);
end;

function VfsGetFreeSpace(ARootURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  out AFree, ATotal: Int64): Int64; cdecl;
var
  Addr: TRcAddr;
  Output: string;
begin
  AFree := 0;
  ATotal := 0;
  try
    if not ParseRcloneUri(UriOf(ARootURI), Addr) or (Addr.Node <> rnPath) then
      Exit(Ord(verNotSupported));
    Result := Run(nil, ['about', '--json', '--ask-password=false', RemoteSpec(Addr)], '',
      cListTimeoutMs, Output);
    if Result <> Ord(verOk) then
      Exit(Ord(verNotSupported));
    if not ParseAboutJson(Output, AFree, ATotal) then
      Exit(Ord(verNotSupported));
    if AFree < 0 then
      AFree := 0;
    if ATotal < 0 then
      ATotal := 0;
  except
    Result := Ord(verNotSupported);
  end;
end;

function RcloneVfsCallbacks: TVfsCallbacksCdeclV2;
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
  GRcRunTool := DefaultRcRunTool;

end.
