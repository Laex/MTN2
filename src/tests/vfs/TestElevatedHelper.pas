unit TestElevatedHelper;

{ The administrator helper over its pipes (uElevatedVfs <-> uElevatedHelper).
  The helper here is this test program started again with --elevated-helper as
  an ordinary process (no UAC prompt), which exercises everything except the
  elevation itself: the pipe handshake, the file operations with progress and
  errors, the refusal of foreign URIs, and the checks that end a helper that is
  talked to by the wrong client. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestElevatedHelper = class
  public
    [Test] procedure TestFileOperations;
    [Test] procedure TestWriteText;
    [Test] procedure TestErrorComesBack;
    [Test] procedure TestForeignUriRefused;
    [Test] procedure TestActiveStateAndShutdown;
    [Test] procedure TestWrongSecretEndsHelper;
    [Test] procedure TestWrongClientProcessEndsHelper;
  end;

  /// <summary>The real thing: a UAC prompt appears and must be accepted, then a
  /// folder is made in and removed from Program Files by the elevated helper.
  /// Run with run-tests.ps1 -All.</summary>
  [TestFixture, Category('Manual')]
  TTestElevatedHelperUac = class
  public
    [Test] procedure TestProgramFilesFolder;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.SyncObjs,
  Winapi.Windows, uVfsTypes, uTextEncoding, uFileVfs, uElevatedVfs,
  uElevatedProtocol, uElevatedWin, uElevatedHelper;

type
  /// <summary>What one asynchronous call reported.</summary>
  TOutcome = record
    Done: Boolean;
    Ok: Boolean;
    Error: TVfsError;
    Progress: Integer;
  end;
  POutcome = ^TOutcome;

function StartPlainProcess(const AParams: string; out AProcess: THandle;
  out AError: TVfsError): Boolean;
var
  Cmd: string;
  Si: TStartupInfo;
  Pi: TProcessInformation;
begin
  AProcess := 0;
  Cmd := '"' + ParamStr(0) + '" ' + AParams;
  UniqueString(Cmd);
  ZeroMemory(@Si, SizeOf(Si));
  Si.cb := SizeOf(Si);
  Result := CreateProcess(nil, PChar(Cmd), nil, nil, False, CREATE_NO_WINDOW, nil,
    nil, Si, Pi);
  if Result then
  begin
    CloseHandle(Pi.hThread);
    AProcess := Pi.hProcess;
  end
  else
    AError := TVfsError.Make(vecIOError, SysErrorMessage(GetLastError), '');
end;

function NewVfs: TElevatedFileVfs;
begin
  Result := TElevatedFileVfs.Create(TFileVirtualFileSystem.Create);
  Result.Launcher := StartPlainProcess;
end;

// The results arrive through TThread.Queue; the test thread is the main thread.
procedure Pump(const ADone: TFunc<Boolean>; ATimeoutMs: Integer = 30000);
var
  Started: UInt64;
begin
  Started := GetTickCount64;
  while not ADone() and (GetTickCount64 - Started < UInt64(ATimeoutMs)) do
  begin
    CheckSynchronize(10);
    Sleep(5);
  end;
end;

function OnDone(AOut: POutcome): TVfsBoolCallback;
begin
  Result :=
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      AOut.Ok := ASuccess;
      AOut.Error := AError;
      AOut.Done := True;
    end;
end;

function OnProgress(AOut: POutcome): TVfsProgressCallback;
begin
  Result :=
    procedure(const ADone, ATotal: Int64; const ACurrentName: string;
      const AItemDone, AItemTotal: Int64; const AItemSrcPath, AItemDstPath: string)
    begin
      Inc(AOut.Progress);
    end;
end;

procedure WaitOutcome(var AOut: TOutcome);
var
  P: POutcome;
begin
  P := @AOut;
  Pump(function: Boolean begin Result := P.Done; end);
  Assert.IsTrue(AOut.Done, 'the helper answered in time');
end;

function TempDir(const AName: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-elev-test-' + AName);
  if TDirectory.Exists(Result) then
    TDirectory.Delete(Result, True);
  TDirectory.CreateDirectory(Result);
end;

procedure TTestElevatedHelper.TestFileOperations;
var
  Vfs: TElevatedFileVfs;
  Dir, Src, SubDir, Copied, Moved: string;
  Out_: TOutcome;
begin
  Dir := TempDir('ops');
  Vfs := NewVfs;
  try
    Src := TPath.Combine(Dir, 'a.txt');
    TFile.WriteAllText(Src, 'content of a');
    SubDir := TPath.Combine(Dir, 'sub');

    Out_ := Default(TOutcome);
    Vfs.CreateDirectoryAsync(PathToFileUri(SubDir), nil, OnDone(@Out_));
    WaitOutcome(Out_);
    Assert.IsTrue(Out_.Ok, 'create folder: ' + Out_.Error.Message);
    Assert.IsTrue(TDirectory.Exists(SubDir));

    Copied := TPath.Combine(SubDir, 'copy.txt');
    Out_ := Default(TOutcome);
    Vfs.CopyAsync(PathToFileUri(Src), PathToFileUri(Copied), nil, OnProgress(@Out_),
      OnDone(@Out_), False, False);
    WaitOutcome(Out_);
    Assert.IsTrue(Out_.Ok, 'copy: ' + Out_.Error.Message);
    Assert.AreEqual('content of a', TFile.ReadAllText(Copied));
    Assert.IsTrue(TFile.Exists(Src), 'a copy keeps the source');

    Moved := TPath.Combine(SubDir, 'moved.txt');
    Out_ := Default(TOutcome);
    Vfs.MoveAsync(PathToFileUri(Copied), PathToFileUri(Moved), nil, nil,
      OnDone(@Out_), False, False);
    WaitOutcome(Out_);
    Assert.IsTrue(Out_.Ok, 'move: ' + Out_.Error.Message);
    Assert.IsTrue(TFile.Exists(Moved));
    Assert.IsFalse(TFile.Exists(Copied));

    Out_ := Default(TOutcome);
    Vfs.DeleteAsync(PathToFileUri(SubDir), vdmPermanent, nil, OnProgress(@Out_),
      OnDone(@Out_));
    WaitOutcome(Out_);
    Assert.IsTrue(Out_.Ok, 'delete: ' + Out_.Error.Message);
    Assert.IsFalse(TDirectory.Exists(SubDir));
  finally
    Vfs.Shutdown;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestElevatedHelper.TestWriteText;
var
  Vfs: TElevatedFileVfs;
  Dir, Path: string;
  Out_: TOutcome;
begin
  Dir := TempDir('text');
  Vfs := NewVfs;
  try
    Path := TPath.Combine(Dir, 'note.txt');
    Out_ := Default(TOutcome);
    Vfs.WriteTextAsync(PathToFileUri(Path), 'строка один'#13#10'line two', tfeUtf8,
      nil, OnDone(@Out_));
    WaitOutcome(Out_);
    Assert.IsTrue(Out_.Ok, 'write: ' + Out_.Error.Message);
    Assert.AreEqual('строка один'#13#10'line two', TFile.ReadAllText(Path, TEncoding.UTF8));
  finally
    Vfs.Shutdown;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestElevatedHelper.TestErrorComesBack;
var
  Vfs: TElevatedFileVfs;
  Dir: string;
  Out_: TOutcome;
begin
  Dir := TempDir('err');
  Vfs := NewVfs;
  try
    Out_ := Default(TOutcome);
    Vfs.CopyAsync(PathToFileUri(TPath.Combine(Dir, 'missing.txt')),
      PathToFileUri(TPath.Combine(Dir, 'x.txt')), nil, nil, OnDone(@Out_), False, False);
    WaitOutcome(Out_);
    Assert.IsFalse(Out_.Ok, 'copying a missing file fails');
    Assert.IsTrue(Out_.Error.Code <> vecOk);
    Assert.AreNotEqual('', Out_.Error.Message, 'the error text comes with it');
    Assert.IsFalse(TFile.Exists(TPath.Combine(Dir, 'x.txt')));
  finally
    Vfs.Shutdown;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestElevatedHelper.TestForeignUriRefused;
var
  Vfs: TElevatedFileVfs;
  Out_: TOutcome;
begin
  Vfs := NewVfs;
  try
    Out_ := Default(TOutcome);
    Vfs.DeleteAsync('file:///C:/archive.zip!/inner.txt', vdmPermanent, nil, nil,
      OnDone(@Out_));
    WaitOutcome(Out_);
    Assert.IsFalse(Out_.Ok);
    Assert.IsTrue(Out_.Error.Code = vecInvalidURI, 'the helper runs plain local paths only');
  finally
    Vfs.Shutdown;
  end;
end;

procedure TTestElevatedHelper.TestActiveStateAndShutdown;
var
  Vfs: TElevatedFileVfs;
  Dir: string;
  Out_: TOutcome;
  Events: TStringList;
begin
  Dir := TempDir('state');
  Events := TStringList.Create;
  Vfs := NewVfs;
  try
    Vfs.OnActiveChanged :=
      procedure(AActive: Boolean)
      begin
        Events.Add(BoolToStr(AActive, True));
      end;
    Assert.IsFalse(Vfs.IsActive, 'no helper before the first request');
    Out_ := Default(TOutcome);
    Vfs.CreateDirectoryAsync(PathToFileUri(TPath.Combine(Dir, 'd')), nil, OnDone(@Out_));
    WaitOutcome(Out_);
    Assert.IsTrue(Vfs.IsActive, 'the helper runs after a request');
    Vfs.Shutdown;
    Pump(function: Boolean begin Result := Events.Count >= 2; end, 5000);
    Assert.IsFalse(Vfs.IsActive);
    Assert.AreEqual('True,False', Events.CommaText, 'started, then ended');
  finally
    Vfs.OnActiveChanged := nil;
    Vfs.Shutdown;
    Events.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

type
  TRawClient = record
    Process: THandle;
    Req, Rep: THandle;
  end;

// A client written by hand, to talk to the helper the way a wrong client would.
function StartRawHelper(AParentPid: Cardinal; const ANonce: string;
  out AClient: TRawClient; out APipeName: string): Boolean;
var
  Err: TVfsError;
  Started: UInt64;

  function OpenEnd(AReplies: Boolean): THandle;
  var
    Access: DWORD;
  begin
    if AReplies then
      Access := GENERIC_READ
    else
      Access := GENERIC_WRITE;
    while True do
    begin
      Result := CreateFile(PChar(ElevatedPipePath(APipeName, AReplies)), Access, 0,
        nil, OPEN_EXISTING, 0, 0);
      if (Result <> INVALID_HANDLE_VALUE) or (GetTickCount64 - Started > 15000) then
        Exit;
      Sleep(50);
    end;
  end;

begin
  AClient := Default(TRawClient);
  APipeName := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '');
  Started := GetTickCount64;
  Result := StartPlainProcess(BuildHelperParams(APipeName, AParentPid,
    CurrentUserSidText, ANonce), AClient.Process, Err);
  if not Result then
    Exit;
  AClient.Req := OpenEnd(False);
  AClient.Rep := OpenEnd(True);
  Result := (AClient.Req <> INVALID_HANDLE_VALUE) and (AClient.Rep <> INVALID_HANDLE_VALUE);
end;

procedure CloseRawClient(var AClient: TRawClient);
begin
  if (AClient.Req <> 0) and (AClient.Req <> INVALID_HANDLE_VALUE) then
    CloseHandle(AClient.Req);
  if (AClient.Rep <> 0) and (AClient.Rep <> INVALID_HANDLE_VALUE) then
    CloseHandle(AClient.Rep);
  if AClient.Process <> 0 then
  begin
    TerminateProcess(AClient.Process, 99);
    CloseHandle(AClient.Process);
  end;
end;

procedure TTestElevatedHelper.TestWrongSecretEndsHelper;
var
  C: TRawClient;
  PipeName: string;
  Hello: TElevatedRequest;
  Buf, Payload: TBytes;
  Code: DWORD;
begin
  Assert.IsTrue(StartRawHelper(GetCurrentProcessId, 'right-secret', C, PipeName));
  try
    Hello := Default(TElevatedRequest);
    Hello.Op := eoHello;
    Hello.Nonce := 'wrong-secret';
    Assert.IsTrue(WriteFramedMessage(C.Req, EncodeRequest(Hello)));
    Assert.IsFalse(ReadFramedMessage(C.Rep, Buf, Payload),
      'no hello answer for a wrong secret');
    Assert.AreEqual(DWORD(WAIT_OBJECT_0), WaitForSingleObject(C.Process, 10000),
      'the helper ends');
    GetExitCodeProcess(C.Process, Code);
    Assert.AreNotEqual(DWORD(STILL_ACTIVE), Code);
  finally
    CloseRawClient(C);
  end;
end;

procedure TTestElevatedHelper.TestWrongClientProcessEndsHelper;
var
  C: TRawClient;
  PipeName: string;
  Other: TRawClient;
  Code: DWORD;
  Cmd: string;
  Si: TStartupInfo;
  Pi: TProcessInformation;
begin
  // A process that is not the one named as the program on the helper's
  // command line: the helper must refuse a connection from this test process.
  Cmd := 'cmd.exe /c ping -n 30 127.0.0.1 >nul';
  UniqueString(Cmd);
  ZeroMemory(@Si, SizeOf(Si));
  Si.cb := SizeOf(Si);
  Assert.IsTrue(CreateProcess(nil, PChar(Cmd), nil, nil, False, CREATE_NO_WINDOW, nil,
    nil, Si, Pi));
  CloseHandle(Pi.hThread);
  Other := Default(TRawClient);
  Other.Process := Pi.hProcess;
  try
    Assert.IsTrue(StartRawHelper(Pi.dwProcessId, 'secret', C, PipeName));
    try
      Assert.AreEqual(DWORD(WAIT_OBJECT_0), WaitForSingleObject(C.Process, 10000),
        'the helper ends');
      GetExitCodeProcess(C.Process, Code);
      Assert.AreEqual(DWORD(3), Code, 'rejected');
    finally
      CloseRawClient(C);
    end;
  finally
    CloseRawClient(Other);
  end;
end;

procedure TTestElevatedHelperUac.TestProgramFilesFolder;
var
  Vfs: TElevatedFileVfs;
  Dir: string;
  Out_: TOutcome;
begin
  Dir := TPath.Combine(GetEnvironmentVariable('ProgramFiles'), 'mtn2-elevation-test');
  Vfs := TElevatedFileVfs.Create(TFileVirtualFileSystem.Create);
  try
    Out_ := Default(TOutcome);
    Vfs.CreateDirectoryAsync(PathToFileUri(Dir), nil, OnDone(@Out_));
    Pump(function: Boolean begin Result := Out_.Done; end, 120000);
    Assert.IsTrue(Out_.Done, 'the prompt was answered');
    Assert.IsTrue(Out_.Ok, 'create folder: ' + Out_.Error.Message);
    Assert.IsTrue(TDirectory.Exists(Dir));

    Out_ := Default(TOutcome);
    Vfs.DeleteAsync(PathToFileUri(Dir), vdmPermanent, nil, nil, OnDone(@Out_));
    Pump(function: Boolean begin Result := Out_.Done; end);
    Assert.IsTrue(Out_.Ok, 'delete: ' + Out_.Error.Message);
    Assert.IsFalse(TDirectory.Exists(Dir));
  finally
    Vfs.Shutdown;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestElevatedHelper);
  TDUnitX.RegisterTestFixture(TTestElevatedHelperUac);

end.
