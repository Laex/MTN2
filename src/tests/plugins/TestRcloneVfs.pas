unit TestRcloneVfs;

{ The rclone callbacks against a fake program runner: the arguments each
  operation sends and the way the program's text and exit code come back. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRcloneVfs = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestRootListsTheRemotes;
    [Test] procedure TestRemoteFolderListsEntries;
    [Test] procedure TestMissingProgramIsAnIoError;
    [Test] procedure TestMissingPathIsNotFound;
    [Test] procedure TestExistsTellsFolderFromFile;
    [Test] procedure TestReadTextUsesCat;
    [Test] procedure TestReadBytesReportsTheTransferTotals;
    [Test] procedure TestFailedReadTakesItsErrorFromTheLog;
    [Test] procedure TestReadOfTooLargeFileIsStoppedAndRefused;
    [Test] procedure TestCancelStopsTheProgram;
    [Test] procedure TestCopyReportsTheTransferTotals;
    [Test] procedure TestWriteSendsTheTextOnStdin;
    [Test] procedure TestDeleteChoosesPurgeForFolders;
    [Test] procedure TestRemoteRootIsNotDeleted;
    [Test] procedure TestCopyBetweenRemoteAndLocal;
    [Test] procedure TestMoveUsesMoveto;
    [Test] procedure TestTwoLocalPathsAreRefused;
    [Test] procedure TestFreeSpaceComesFromAbout;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, uPluginHostAbi, uVfsTypes, uRcloneFormat, uRcloneVfs;

var
  GCalls: TArray<string>;
  GStdIn: string;
  GReply: TFunc<string, string>;
  GExit: TFunc<string, Cardinal>;
  GMissing: Boolean;
  /// How long the fake program runs, and whether it was stopped before that.
  GRunMs: Cardinal;
  GStopped: Boolean;

function FakeRun(const AExe: string; const AArgs: TArray<string>; const AStdIn: string;
  ATimeoutMs: Cardinal; const ACancel: IJobCancelToken; out AOutput: string;
  out ACode: Cardinal): Boolean;
var
  Line: string;
  Tick: UInt64;
begin
  Line := AExe + ' ' + string.Join(' ', AArgs);
  GCalls := GCalls + [Line];
  GStdIn := AStdIn;
  if GMissing then
  begin
    AOutput := AExe + ' did not run';
    ACode := 0;
    Exit(False);
  end;
  AOutput := GReply(Line);
  ACode := GExit(Line);
  // A program that takes time is killed when the call is cancelled.
  GStopped := False;
  Tick := TThread.GetTickCount64;
  while (TThread.GetTickCount64 - Tick < GRunMs) and not GStopped do
  begin
    GStopped := (ACancel <> nil) and ACancel.IsCancellationRequested;
    Sleep(10);
  end;
  if GStopped then
  begin
    AOutput := 'Cancelled';
    Exit(False);
  end;
  Result := True;
end;

function LastCall: string;
begin
  Result := GCalls[High(GCalls)];
end;

function List(const AUri: string; out AJson: TJSONArray): Int64;
var
  Cb: TVfsCallbacksCdeclV2;
  Buf: TBytes;
  Neg, More: Int64;
  Uri: UTF8String;
begin
  Cb := RcloneVfsCallbacks;
  SetLength(Buf, 1024 * 1024);
  Uri := UTF8String(AUri);
  AJson := nil;
  Result := Cb.ListDirectory(PAnsiChar(Uri), nil, nil, 0, PAnsiChar(@Buf[0]), Length(Buf), Neg, More);
  if Result = Ord(verOk) then
  begin
    Assert.IsTrue(Neg > 0);
    Assert.AreNotEqual(0, Integer(Buf[Neg - 1]), 'negotiated size must not count the terminator');
    AJson := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Buf, 0, Neg)) as TJSONArray;
  end;
end;

function NameAt(const AArr: TJSONArray; AIndex: Integer): string;
begin
  Result := (AArr.Items[AIndex] as TJSONObject).GetValue<string>('name');
end;

procedure TTestRcloneVfs.Setup;
begin
  GRcRunTool := FakeRun;
  GCalls := nil;
  GStdIn := '';
  GMissing := False;
  GRunMs := 0;
  GStopped := False;
  GReply := function(ALine: string): string begin Result := ''; end;
  GExit := function(ALine: string): Cardinal begin Result := 0; end;
end;

procedure TTestRcloneVfs.TearDown;
begin
  GRcRunTool := DefaultRcRunTool;
end;

procedure TTestRcloneVfs.TestRootListsTheRemotes;
var
  Arr: TJSONArray;
begin
  GReply := function(ALine: string): string begin Result := 'gdrive:' + #10 + 'my/box:' + #10; end;
  Assert.AreEqual(Int64(Ord(verOk)), List('rclone:///', Arr));
  try
    Assert.AreEqual(2, Arr.Count);
    Assert.AreEqual('gdrive', NameAt(Arr, 0));
    Assert.AreEqual('my%2Fbox', NameAt(Arr, 1));
    Assert.IsTrue(Pos('rclone listremotes', LastCall) = 1);
  finally
    Arr.Free;
  end;
end;

procedure TTestRcloneVfs.TestRemoteFolderListsEntries;
var
  Arr: TJSONArray;
begin
  GReply := function(ALine: string): string
    begin
      Result := '[{"Name":"a.txt","Size":5,"ModTime":"2024-05-01T10:20:30Z","IsDir":false},' +
        '{"Name":"sub","Size":-1,"ModTime":"2024-05-01T10:20:30Z","IsDir":true}]';
    end;
  Assert.AreEqual(Int64(Ord(verOk)), List('rclone:///gdrive/Docs', Arr));
  try
    Assert.AreEqual(2, Arr.Count);
    Assert.AreEqual('a.txt', NameAt(Arr, 0));
    Assert.IsTrue((Arr.Items[1] as TJSONObject).GetValue<Boolean>('isDir'));
    Assert.IsTrue(Pos('rclone lsjson', LastCall) = 1);
    Assert.IsTrue(LastCall.EndsWith('gdrive:Docs'));
  finally
    Arr.Free;
  end;
end;

procedure TTestRcloneVfs.TestMissingProgramIsAnIoError;
var
  Arr: TJSONArray;
begin
  GMissing := True;
  Assert.AreEqual(Int64(Ord(verIOError)), List('rclone:///gdrive', Arr));
end;

procedure TTestRcloneVfs.TestMissingPathIsNotFound;
var
  Arr: TJSONArray;
begin
  GReply := function(ALine: string): string begin Result := 'ERROR : directory not found'; end;
  GExit := function(ALine: string): Cardinal begin Result := 3; end;
  Assert.AreEqual(Int64(Ord(verNotFound)), List('rclone:///gdrive/none', Arr));
end;

procedure TTestRcloneVfs.TestExistsTellsFolderFromFile;
var
  Cb: TVfsCallbacksCdeclV2;
  IsDir: Int64;
  Uri: UTF8String;
begin
  Cb := RcloneVfsCallbacks;
  GReply := function(ALine: string): string begin Result := '{"Name":"d","IsDir":true,"Size":-1}'; end;
  Uri := 'rclone:///gdrive/d';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Exists(PAnsiChar(Uri), nil, nil, IsDir));
  Assert.AreEqual(Int64(1), IsDir);
  GReply := function(ALine: string): string begin Result := '{"Name":"f","IsDir":false,"Size":3}'; end;
  Uri := 'rclone:///gdrive/f';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Exists(PAnsiChar(Uri), nil, nil, IsDir));
  Assert.AreEqual(Int64(0), IsDir);
  Uri := 'rclone:///gdrive';
  GCalls := nil;
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Exists(PAnsiChar(Uri), nil, nil, IsDir));
  Assert.AreEqual(Int64(1), IsDir);
  Assert.AreEqual(0, Integer(Length(GCalls)), 'a remote root needs no program');
end;

procedure TTestRcloneVfs.TestReadTextUsesCat;
var
  Cb: TVfsCallbacksCdeclV2;
  Buf: array[0..255] of AnsiChar;
  Neg: Int64;
  Uri: UTF8String;
begin
  Cb := RcloneVfsCallbacks;
  GReply := function(ALine: string): string begin Result := 'hello'; end;
  Uri := 'rclone:///gdrive/n.txt';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.ReadText(PAnsiChar(Uri), 100, nil, nil, @Buf[0], SizeOf(Buf), Neg));
  Assert.AreEqual(Int64(5), Neg);
  Assert.AreEqual('hello', string(PAnsiChar(@Buf[0])));
  Assert.IsTrue(Pos('rclone cat', LastCall) = 1);
  Assert.IsTrue(Pos('--count 100', LastCall) > 0);
end;

var
  GSeenDone, GSeenTotal: Int64;
  GSeenError: string;

function NoteProgress(ACtx: PVfsOpContext; ADone, ATotal, AItemDone, AItemTotal: Int64;
  AName: PAnsiChar): Int64; cdecl;
begin
  GSeenDone := ADone;
  GSeenTotal := ATotal;
  Result := 0;
end;

procedure NoteError(ACtx: PVfsOpContext; AText: PAnsiChar); cdecl;
begin
  GSeenError := UTF8ToString(AText);
end;

// The log file a transfer was told to write; the option comes last.
function LogPathOf(const ALine: string): string;
const
  cOpt = '--log-file ';
begin
  Result := Copy(ALine, Pos(cOpt, ALine) + Length(cOpt), MaxInt);
end;

procedure TTestRcloneVfs.TestReadBytesReportsTheTransferTotals;
var
  Cb: TVfsCallbacksCdeclV2;
  Ctx: TVfsOpContext;
  Buf: array[0..255] of Byte;
  Neg: Int64;
  Uri: UTF8String;
begin
  Cb := RcloneVfsCallbacks;
  Ctx := Default(TVfsOpContext);
  Ctx.ReportProgress := NoteProgress;
  GSeenDone := -1;
  GSeenTotal := -1;
  GReply := function(ALine: string): string
    begin
      Result := '';
      TFile.WriteAllText(LogPathOf(ALine),
        '{"level":"notice","msg":"t","stats":{"bytes":30,"totalBytes":90}}' + #10);
    end;
  // The transfer lasts long enough for the log to be looked at.
  GRunMs := 500;
  Uri := 'rclone:///gdrive/b.bin';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.ReadBytes(PAnsiChar(Uri), 100, nil, @Ctx, @Buf[0],
    SizeOf(Buf), Neg));
  Assert.IsTrue(Pos('rclone copyto', LastCall) = 1);
  Assert.IsTrue(Pos('--use-json-log', LastCall) > 0, 'the transfer logs its totals');
  Assert.AreEqual(Int64(30), GSeenDone);
  Assert.AreEqual(Int64(90), GSeenTotal);
  Assert.IsFalse(TFile.Exists(LogPathOf(LastCall)), 'the log is removed');
end;

procedure TTestRcloneVfs.TestFailedReadTakesItsErrorFromTheLog;
var
  Cb: TVfsCallbacksCdeclV2;
  Ctx: TVfsOpContext;
  Buf: array[0..255] of Byte;
  Neg: Int64;
  Uri: UTF8String;
begin
  Cb := RcloneVfsCallbacks;
  Ctx := Default(TVfsOpContext);
  Ctx.ReportProgress := NoteProgress;
  Ctx.SetErrorText := NoteError;
  GSeenError := '';
  GReply := function(ALine: string): string
    begin
      Result := '';
      TFile.WriteAllText(LogPathOf(ALine), '{"level":"error","msg":"object not found"}' + #10);
    end;
  GExit := function(ALine: string): Cardinal begin Result := 3; end;
  Uri := 'rclone:///gdrive/none.bin';
  Assert.AreEqual(Int64(Ord(verNotFound)), Cb.ReadBytes(PAnsiChar(Uri), 100, nil, @Ctx, @Buf[0],
    SizeOf(Buf), Neg));
  Assert.AreEqual('object not found', GSeenError);
end;

procedure TTestRcloneVfs.TestReadOfTooLargeFileIsStoppedAndRefused;
var
  Cb: TVfsCallbacksCdeclV2;
  Ctx: TVfsOpContext;
  Buf: array[0..255] of Byte;
  Neg: Int64;
  Uri: UTF8String;
begin
  Cb := RcloneVfsCallbacks;
  Ctx := Default(TVfsOpContext);
  Ctx.ReportProgress := NoteProgress;
  GReply := function(ALine: string): string
    begin
      Result := '';
      TFile.WriteAllText(LogPathOf(ALine),
        '{"level":"notice","msg":"t","stats":{"bytes":10,"totalBytes":5000}}' + #10);
    end;
  GRunMs := 5000;
  Uri := 'rclone:///gdrive/huge.bin';
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.ReadBytes(PAnsiChar(Uri), 100, nil, @Ctx,
    @Buf[0], SizeOf(Buf), Neg));
  Assert.IsTrue(GStopped, 'the transfer is stopped once its size is known');
end;

function AlwaysCancelled(ACtx: PVfsOpContext): Int64; cdecl;
begin
  Result := 1;
end;

procedure TTestRcloneVfs.TestCancelStopsTheProgram;
var
  Cb: TVfsCallbacksCdeclV2;
  Ctx: TVfsOpContext;
  Buf: TBytes;
  Neg, More: Int64;
  Uri: UTF8String;
begin
  Cb := RcloneVfsCallbacks;
  Ctx := Default(TVfsOpContext);
  Ctx.IsCancelled := AlwaysCancelled;
  GRunMs := 5000;
  SetLength(Buf, 4096);
  Uri := 'rclone:///gdrive/dir';
  Assert.AreEqual(Int64(Ord(verCancelled)), Cb.ListDirectory(PAnsiChar(Uri), nil, @Ctx, 0,
    PAnsiChar(@Buf[0]), Length(Buf), Neg, More));
  Assert.IsTrue(GStopped, 'the program does not run to its end');
end;

procedure TTestRcloneVfs.TestCopyReportsTheTransferTotals;
var
  Cb: TVfsCallbacksCdeclV2;
  Ctx: TVfsOpContext;
  From, To_: UTF8String;
begin
  Cb := RcloneVfsCallbacks;
  Ctx := Default(TVfsOpContext);
  Ctx.ReportProgress := NoteProgress;
  GSeenDone := -1;
  GSeenTotal := -1;
  GReply := function(ALine: string): string
    begin
      Result := '';
      TFile.WriteAllText(LogPathOf(ALine),
        '{"level":"notice","msg":"t","stats":{"bytes":700,"totalBytes":9000}}' + #10);
    end;
  GRunMs := 500;
  From := 'rclone:///gdrive/a.bin';
  To_ := 'rclone:///gdrive/b.bin';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.CopyItem(PAnsiChar(From), PAnsiChar(To_), 0, nil, @Ctx));
  Assert.AreEqual(Int64(700), GSeenDone);
  Assert.AreEqual(Int64(9000), GSeenTotal);
end;

procedure TTestRcloneVfs.TestWriteSendsTheTextOnStdin;
var
  Cb: TVfsCallbacksCdeclV2;
  Uri, Text: UTF8String;
begin
  Cb := RcloneVfsCallbacks;
  Uri := 'rclone:///gdrive/w.txt';
  Text := 'body';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.WriteText(PAnsiChar(Uri), PAnsiChar(Text), nil, nil));
  Assert.IsTrue(Pos('rclone rcat', LastCall) = 1);
  Assert.AreEqual('body', GStdIn);
end;

procedure TTestRcloneVfs.TestDeleteChoosesPurgeForFolders;
var
  Cb: TVfsCallbacksCdeclV2;
  Uri: UTF8String;
begin
  Cb := RcloneVfsCallbacks;
  GReply := function(ALine: string): string begin Result := '{"Name":"d","IsDir":true}'; end;
  Uri := 'rclone:///gdrive/d';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Delete(PAnsiChar(Uri), 0, nil, nil));
  Assert.IsTrue(Pos('rclone purge', LastCall) = 1);
  GReply := function(ALine: string): string begin Result := '{"Name":"f","IsDir":false}'; end;
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Delete(PAnsiChar(Uri), 0, nil, nil));
  Assert.IsTrue(Pos('rclone deletefile', LastCall) = 1);
end;

procedure TTestRcloneVfs.TestRemoteRootIsNotDeleted;
var
  Cb: TVfsCallbacksCdeclV2;
  Uri: UTF8String;
begin
  Cb := RcloneVfsCallbacks;
  Uri := 'rclone:///gdrive';
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.Delete(PAnsiChar(Uri), 0, nil, nil));
  Assert.AreEqual(0, Integer(Length(GCalls)));
end;

procedure TTestRcloneVfs.TestCopyBetweenRemoteAndLocal;
var
  Cb: TVfsCallbacksCdeclV2;
  From, To_: UTF8String;
begin
  Cb := RcloneVfsCallbacks;
  From := 'rclone:///gdrive/a.bin';
  To_ := 'file:///C:/Temp/a.bin';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.CopyItem(PAnsiChar(From), PAnsiChar(To_), 0, nil, nil));
  Assert.IsTrue(Pos('rclone copyto', LastCall) = 1);
  Assert.IsTrue(Pos('gdrive:a.bin', LastCall) > 0);
  From := 'rclone:///gdrive/a.bin';
  To_ := 'rclone:///box/b.bin';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.CopyItem(PAnsiChar(From), PAnsiChar(To_), 0, nil, nil));
  Assert.IsTrue(LastCall.EndsWith('gdrive:a.bin box:b.bin'));
end;

procedure TTestRcloneVfs.TestMoveUsesMoveto;
var
  Cb: TVfsCallbacksCdeclV2;
  From, To_: UTF8String;
begin
  Cb := RcloneVfsCallbacks;
  From := 'rclone:///gdrive/a.bin';
  To_ := 'rclone:///gdrive/b.bin';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.MoveItem(PAnsiChar(From), PAnsiChar(To_), 0, nil, nil));
  Assert.IsTrue(Pos('rclone moveto', LastCall) = 1);
end;

procedure TTestRcloneVfs.TestTwoLocalPathsAreRefused;
var
  Cb: TVfsCallbacksCdeclV2;
  From, To_: UTF8String;
begin
  Cb := RcloneVfsCallbacks;
  From := 'file:///C:/a.txt';
  To_ := 'file:///C:/b.txt';
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.CopyItem(PAnsiChar(From), PAnsiChar(To_), 0, nil, nil));
  Assert.AreEqual(0, Integer(Length(GCalls)));
end;

procedure TTestRcloneVfs.TestFreeSpaceComesFromAbout;
var
  Cb: TVfsCallbacksCdeclV2;
  Uri: UTF8String;
  Free, Total: Int64;
begin
  Cb := RcloneVfsCallbacks;
  GReply := function(ALine: string): string begin Result := '{"total":1000,"free":250}'; end;
  Uri := 'rclone:///gdrive';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.GetFreeSpace(PAnsiChar(Uri), nil, nil, Free, Total));
  Assert.AreEqual(Int64(250), Free);
  Assert.AreEqual(Int64(1000), Total);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRcloneVfs);

end.
