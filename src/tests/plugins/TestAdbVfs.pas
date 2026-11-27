unit TestAdbVfs;

{ The adb callbacks against a fake program runner: the arguments each operation
  sends and the way the program's text and exit code come back. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAdbVfs = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestRootListsDevicesWithStateColors;
    [Test] procedure TestMissingAdbIsExplained;
    [Test] procedure TestUnauthorizedDeviceIsExplained;
    [Test] procedure TestFolderListingGivesEntries;
    [Test] procedure TestFolderWithSomeUnreadableEntriesIsListed;
    [Test] procedure TestMissingFolderIsNotFound;
    [Test] procedure TestExistsTellsFolderFromFile;
    [Test] procedure TestReadDecodesBinaryData;
    [Test] procedure TestWritePushesATemporaryFile;
    [Test] procedure TestDeleteAndCreateRunOnTheDevice;
    [Test] procedure TestDeviceAndItsRootAreNotDeleted;
    [Test] procedure TestPullCopiesOneFile;
    [Test] procedure TestPushFileRefusesToOverwriteUnlessAsked;
    [Test] procedure TestPushFolderIntoAnExistingFolderMerges;
    [Test] procedure TestPushNewFolderKeepsEmptySubfolders;
    [Test] procedure TestRenameMovesOnTheDevice;
    [Test] procedure TestRenameOntoAnExistingNameIsRefused;
    [Test] procedure TestCopyBetweenDevicesIsNotSupported;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, uPluginHostAbi, uPlatformProcess, uVfsTypes,
  uAdbFormat, uAdbVfs;

var
  GCalls: TArray<string>;
  GReply: TFunc<string, string>;
  GExit: TFunc<string, Cardinal>;
  GSpawn: TSpawnResult;
  GColorsJson: string;
  GPushed: TBytes;
  GErrorText: string;
  GTemp: string;

function FakeRun(const AArgs: TArray<string>; ATimeoutMs: Cardinal; ACancel: IJobCancelToken;
  out AOutput: string; out ACode: Cardinal): TSpawnResult;
var
  Line: string;
begin
  Line := string.Join(' ', AArgs);
  GCalls := GCalls + [Line];
  AOutput := '';
  ACode := 0;
  if GSpawn <> srOk then
    Exit(GSpawn);
  // The pushed temporary file is gone after the call returns, so keep its bytes.
  if (Length(AArgs) = 5) and (AArgs[2] = 'push') and TFile.Exists(AArgs[3]) then
    GPushed := TFile.ReadAllBytes(AArgs[3]);
  AOutput := GReply(Line);
  ACode := GExit(Line);
  Result := srOk;
end;

procedure CaptureColors(const AFolderUri, AJson: string);
begin
  GColorsJson := AJson;
end;

procedure SetErrorText(ACtx: PVfsOpContext; AText: PAnsiChar); cdecl;
begin
  GErrorText := string(UTF8String(AText));
end;

function Context: TVfsOpContext;
begin
  Result := Default(TVfsOpContext);
  Result.SetErrorText := SetErrorText;
end;

function LastCall: string;
begin
  Result := GCalls[High(GCalls)];
end;

function Called(const APart: string): Boolean;
var
  Line: string;
begin
  for Line in GCalls do
    if Line.Contains(APart) then
      Exit(True);
  Result := False;
end;

function List(const AUri: string; out AJson: TJSONArray): Int64;
var
  Cb: TVfsCallbacksCdeclV2;
  Ctx: TVfsOpContext;
  Buf: TBytes;
  Neg, More: Int64;
  Uri: UTF8String;
begin
  Cb := AdbVfsCallbacks;
  Ctx := Context;
  SetLength(Buf, 1024 * 1024);
  Uri := UTF8String(AUri);
  AJson := nil;
  Result := Cb.ListDirectory(PAnsiChar(Uri), nil, @Ctx, 0, PAnsiChar(@Buf[0]), Length(Buf), Neg, More);
  if Result = Ord(verOk) then
    AJson := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Buf, 0, Neg)) as TJSONArray;
end;

function Field(const AArr: TJSONArray; AIndex: Integer; const AName: string): string;
begin
  Result := (AArr.Items[AIndex] as TJSONObject).GetValue<string>(AName);
end;

function Copy_(const AFrom, ATo: string; AFlags: Int64): Int64;
var
  Cb: TVfsCallbacksCdeclV2;
  Ctx: TVfsOpContext;
  F, T: UTF8String;
begin
  Cb := AdbVfsCallbacks;
  Ctx := Context;
  F := UTF8String(AFrom);
  T := UTF8String(ATo);
  Result := Cb.CopyItem(PAnsiChar(F), PAnsiChar(T), AFlags, nil, @Ctx);
end;

function Move_(const AFrom, ATo: string; AFlags: Int64): Int64;
var
  Cb: TVfsCallbacksCdeclV2;
  Ctx: TVfsOpContext;
  F, T: UTF8String;
begin
  Cb := AdbVfsCallbacks;
  Ctx := Context;
  F := UTF8String(AFrom);
  T := UTF8String(ATo);
  Result := Cb.MoveItem(PAnsiChar(F), PAnsiChar(T), AFlags, nil, @Ctx);
end;

procedure TTestAdbVfs.Setup;
begin
  GRunAdb := FakeRun;
  GCalls := nil;
  GSpawn := srOk;
  GColorsJson := '';
  GPushed := nil;
  GErrorText := '';
  GReply := function(ALine: string): string begin Result := ''; end;
  GExit := function(ALine: string): Cardinal begin Result := 0; end;
  GTemp := TPath.Combine(TPath.GetTempPath, 'mtn2-adb-test-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(GTemp);
end;

procedure TTestAdbVfs.TearDown;
begin
  GRunAdb := DefaultRunAdb;
  GOnRowColors := nil;
  TDirectory.Delete(GTemp, True);
end;

procedure TTestAdbVfs.TestRootListsDevicesWithStateColors;
var
  Arr: TJSONArray;
begin
  GOnRowColors := CaptureColors;
  GReply := function(ALine: string): string
    begin
      Result := 'List of devices attached'#10 +
        'emulator-5554 device model:Pixel_7'#10 +
        'ABC123 unauthorized'#10;
    end;
  Assert.AreEqual(Int64(Ord(verOk)), List('adb:///', Arr));
  try
    Assert.AreEqual(2, Arr.Count);
    Assert.AreEqual('emulator-5554', Field(Arr, 0, 'name'));
    Assert.AreEqual('true', Field(Arr, 0, 'isDir'));
    Assert.AreEqual('Pixel 7', Field(Arr, 0, 'extra.model'));
    Assert.AreEqual('unauthorized', Field(Arr, 1, 'extra.state'));
  finally
    Arr.Free;
  end;
  Assert.AreEqual('devices -l', LastCall);
  Assert.IsTrue(Pos('"emulator-5554":"ok"', GColorsJson) > 0, GColorsJson);
  Assert.IsTrue(Pos('"ABC123":"warn"', GColorsJson) > 0, GColorsJson);
end;

procedure TTestAdbVfs.TestMissingAdbIsExplained;
var
  Arr: TJSONArray;
begin
  GSpawn := srSpawnFailed;
  Assert.AreEqual(Int64(Ord(verIOError)), List('adb:///', Arr));
  Assert.AreEqual(GAdbText.NoProgram, GErrorText);
  Assert.IsTrue(GErrorText.Contains('PATH'), GErrorText);
end;

procedure TTestAdbVfs.TestUnauthorizedDeviceIsExplained;
var
  Arr: TJSONArray;
begin
  GReply := function(ALine: string): string begin Result := 'error: device unauthorized.'#10; end;
  GExit := function(ALine: string): Cardinal begin Result := 1; end;
  Assert.AreEqual(Int64(Ord(verAccessDenied)), List('adb:///ABC123/sdcard', Arr));
  Assert.AreEqual(GAdbText.Unauthorized, GErrorText);
end;

procedure TTestAdbVfs.TestFolderListingGivesEntries;
var
  Arr: TJSONArray;
begin
  GReply := function(ALine: string): string
    begin
      Result := 'S|41f9|4096|1700000000|/sdcard/DCIM'#10'S|81b0|7|1700000000|/sdcard/.hidden'#10;
    end;
  Assert.AreEqual(Int64(Ord(verOk)), List('adb:///dev1/sdcard', Arr));
  try
    Assert.AreEqual(2, Arr.Count);
    Assert.AreEqual('DCIM', Field(Arr, 0, 'name'));
    Assert.AreEqual('true', Field(Arr, 1, 'isHidden'));
    Assert.AreEqual('7', Field(Arr, 1, 'size'));
  finally
    Arr.Free;
  end;
  Assert.AreEqual('-s dev1 shell ' + ListScript('/sdcard'), LastCall);
end;

procedure TTestAdbVfs.TestFolderWithSomeUnreadableEntriesIsListed;
var
  Arr: TJSONArray;
begin
  GReply := function(ALine: string): string
    begin
      Result := 'stat: ''//init'': Permission denied'#10'S|41f9|4096|0|//sdcard'#10;
    end;
  GExit := function(ALine: string): Cardinal begin Result := 1; end;
  Assert.AreEqual(Int64(Ord(verOk)), List('adb:///dev1', Arr));
  try
    Assert.AreEqual(1, Arr.Count);
    Assert.AreEqual('sdcard', Field(Arr, 0, 'name'));
  finally
    Arr.Free;
  end;
end;

procedure TTestAdbVfs.TestMissingFolderIsNotFound;
var
  Arr: TJSONArray;
begin
  GReply := function(ALine: string): string begin Result := 'find: /nope/: No such file or directory'#10; end;
  GExit := function(ALine: string): Cardinal begin Result := 1; end;
  Assert.AreEqual(Int64(Ord(verNotFound)), List('adb:///dev1/nope', Arr));
end;

procedure TTestAdbVfs.TestExistsTellsFolderFromFile;
var
  Cb: TVfsCallbacksCdeclV2;
  Uri: UTF8String;
  IsDir: Int64;
begin
  Cb := AdbVfsCallbacks;
  Uri := 'adb:///dev1/sdcard/x';
  GReply := function(ALine: string): string begin Result := 'd'#10; end;
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Exists(PAnsiChar(Uri), nil, nil, IsDir));
  Assert.AreEqual(Int64(1), IsDir);
  GReply := function(ALine: string): string begin Result := 'f'#10; end;
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Exists(PAnsiChar(Uri), nil, nil, IsDir));
  Assert.AreEqual(Int64(0), IsDir);
  GReply := function(ALine: string): string begin Result := 'n'#10; end;
  Assert.AreEqual(Int64(Ord(verNotFound)), Cb.Exists(PAnsiChar(Uri), nil, nil, IsDir));
end;

procedure TTestAdbVfs.TestReadDecodesBinaryData;
var
  Cb: TVfsCallbacksCdeclV2;
  Buf: TBytes;
  Neg: Int64;
  Uri: UTF8String;
begin
  Cb := AdbVfsCallbacks;
  SetLength(Buf, 64);
  // 00 FF 80 0D 0A: bytes that do not survive a trip through text.
  GReply := function(ALine: string): string begin Result := 'AP+A'#13#10'DQo='#13#10; end;
  Uri := 'adb:///dev1/sdcard/a.bin';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.ReadBytes(PAnsiChar(Uri), 100, nil, nil, @Buf[0], Length(Buf), Neg));
  Assert.AreEqual(Int64(5), Neg);
  Assert.AreEqual(0, Integer(Buf[0]));
  Assert.AreEqual(255, Integer(Buf[1]));
  Assert.AreEqual(128, Integer(Buf[2]));
  Assert.AreEqual(10, Integer(Buf[4]));
  Assert.AreEqual('-s dev1 shell ' + ReadScript('/sdcard/a.bin', 100), LastCall);
end;

procedure TTestAdbVfs.TestWritePushesATemporaryFile;
var
  Cb: TVfsCallbacksCdeclV2;
  Uri, Text: UTF8String;
begin
  Cb := AdbVfsCallbacks;
  Uri := 'adb:///dev1/sdcard/note.txt';
  Text := UTF8String(#$043D#$043E#$0432#$043E#$0435' text'#10);
  Assert.AreEqual(Int64(Ord(verOk)), Cb.WriteText(PAnsiChar(Uri), PAnsiChar(Text), nil, nil));
  Assert.IsTrue(LastCall.StartsWith('-s dev1 push '), LastCall);
  Assert.IsTrue(LastCall.EndsWith(' /sdcard/note.txt'), LastCall);
  Assert.AreEqual(string(Text), TEncoding.UTF8.GetString(GPushed));
  Uri := 'adb:///dev1';
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.WriteText(PAnsiChar(Uri), PAnsiChar(Text), nil, nil));
end;

procedure TTestAdbVfs.TestDeleteAndCreateRunOnTheDevice;
var
  Cb: TVfsCallbacksCdeclV2;
  Uri: UTF8String;
begin
  Cb := AdbVfsCallbacks;
  Uri := 'adb:///dev1/sdcard/my dir';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Delete(PAnsiChar(Uri), 0, nil, nil));
  Assert.AreEqual('-s dev1 shell rm -rf ''/sdcard/my dir''', LastCall);
  Assert.AreEqual(Int64(Ord(verOk)), Cb.CreateDirectory(PAnsiChar(Uri), nil, nil));
  Assert.AreEqual('-s dev1 shell mkdir -p ''/sdcard/my dir''', LastCall);
end;

procedure TTestAdbVfs.TestDeviceAndItsRootAreNotDeleted;
var
  Cb: TVfsCallbacksCdeclV2;
  Uri: UTF8String;
begin
  Cb := AdbVfsCallbacks;
  Uri := 'adb:///';
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.Delete(PAnsiChar(Uri), 0, nil, nil));
  Uri := 'adb:///dev1';
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.Delete(PAnsiChar(Uri), 0, nil, nil));
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.CreateDirectory(PAnsiChar(Uri), nil, nil));
  Assert.AreEqual(0, Integer(Length(GCalls)));
end;

procedure TTestAdbVfs.TestPullCopiesOneFile;
var
  Local: string;
begin
  Local := TPath.Combine(GTemp, 'a b.txt');
  Assert.AreEqual(Int64(Ord(verOk)), Copy_('adb:///dev1/sdcard/a b.txt', PathToFileUri(Local), 3));
  Assert.AreEqual('-s dev1 pull -a /sdcard/a b.txt ' + Local, LastCall);
  TFile.WriteAllText(Local, 'x');
  GCalls := nil;
  Assert.AreEqual(Int64(Ord(verAlreadyExists)), Copy_('adb:///dev1/sdcard/a b.txt', PathToFileUri(Local), 0));
  Assert.AreEqual(0, Integer(Length(GCalls)));
end;

procedure TTestAdbVfs.TestPushFileRefusesToOverwriteUnlessAsked;
var
  Local: string;
begin
  Local := TPath.Combine(GTemp, 'a.txt');
  TFile.WriteAllText(Local, 'x');
  GReply := function(ALine: string): string
    begin
      if ALine.Contains(' shell ') then Result := 'f'#10 else Result := '';
    end;
  Assert.AreEqual(Int64(Ord(verAlreadyExists)), Copy_(PathToFileUri(Local), 'adb:///dev1/sdcard/a.txt', 0));
  Assert.IsFalse(Called(' push '));
  Assert.AreEqual(Int64(Ord(verOk)), Copy_(PathToFileUri(Local), 'adb:///dev1/sdcard/a.txt', 1));
  Assert.AreEqual('-s dev1 push ' + Local + ' /sdcard/a.txt', LastCall);
end;

procedure TTestAdbVfs.TestPushFolderIntoAnExistingFolderMerges;
var
  Dir: string;
begin
  Dir := TPath.Combine(GTemp, 'Old');
  TDirectory.CreateDirectory(Dir);
  TFile.WriteAllText(TPath.Combine(Dir, 'one.txt'), 'x');
  GReply := function(ALine: string): string
    begin
      if ALine.Contains(' shell if ') and ALine.Contains('''/sdcard/Old''') then
        Result := 'd'#10
      else if ALine.Contains(' shell if ') then
        Result := 'n'#10
      else
        Result := '';
    end;
  Assert.AreEqual(Int64(Ord(verOk)), Copy_(PathToFileUri(Dir), 'adb:///dev1/sdcard/Old', 1));
  // Pushing the folder itself onto an existing one would nest it (Old/Old).
  Assert.AreEqual('-s dev1 push ' + TPath.Combine(Dir, 'one.txt') + ' /sdcard/Old/one.txt', LastCall);
end;

procedure TTestAdbVfs.TestPushNewFolderKeepsEmptySubfolders;
var
  Dir: string;
begin
  Dir := TPath.Combine(GTemp, 'Old');
  TDirectory.CreateDirectory(TPath.Combine(Dir, 'empty'));
  TFile.WriteAllText(TPath.Combine(Dir, 'one.txt'), 'x');
  GReply := function(ALine: string): string
    begin
      if ALine.Contains(' shell if ') then Result := 'n'#10 else Result := '';
    end;
  Assert.AreEqual(Int64(Ord(verOk)), Copy_(PathToFileUri(Dir), 'adb:///dev1/sdcard/Old', 0));
  Assert.IsTrue(Called('-s dev1 push ' + Dir + ' /sdcard/Old'));
  Assert.IsTrue(Called('mkdir -p ''/sdcard/Old/empty'''));
end;

procedure TTestAdbVfs.TestRenameMovesOnTheDevice;
begin
  GReply := function(ALine: string): string
    begin
      if ALine.Contains(' shell if ') then Result := 'n'#10 else Result := '';
    end;
  Assert.AreEqual(Int64(Ord(verOk)), Move_('adb:///dev1/sdcard/a', 'adb:///dev1/sdcard/b c', 0));
  Assert.AreEqual('-s dev1 shell mv -f ''/sdcard/a'' ''/sdcard/b c''', LastCall);
  // A change of letter case only: the new name "exists" on a card that ignores case.
  GReply := function(ALine: string): string begin Result := 'd'#10; end;
  Assert.AreEqual(Int64(Ord(verOk)), Move_('adb:///dev1/sdcard/a', 'adb:///dev1/sdcard/A', 0));
  Assert.AreEqual('-s dev1 shell mv -f ''/sdcard/a'' ''/sdcard/A''', LastCall);
end;

procedure TTestAdbVfs.TestRenameOntoAnExistingNameIsRefused;
begin
  GReply := function(ALine: string): string begin Result := 'f'#10; end;
  Assert.AreEqual(Int64(Ord(verAlreadyExists)), Move_('adb:///dev1/sdcard/a', 'adb:///dev1/sdcard/b', 0));
  GReply := function(ALine: string): string begin Result := 'd'#10; end;
  Assert.AreEqual(Int64(Ord(verAlreadyExists)), Move_('adb:///dev1/sdcard/a', 'adb:///dev1/sdcard/b', 1));
  Assert.IsFalse(Called(' mv '));
end;

procedure TTestAdbVfs.TestCopyBetweenDevicesIsNotSupported;
begin
  Assert.AreEqual(Int64(Ord(verNotSupported)), Copy_('adb:///dev1/sdcard/a', 'adb:///dev2/sdcard/a', 1));
  Assert.AreEqual(Int64(Ord(verNotSupported)), Move_('adb:///dev1/sdcard/a', 'adb:///dev2/sdcard/a', 1));
  Assert.AreEqual(0, Integer(Length(GCalls)));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAdbVfs);

end.
