unit TestDockerVfs;

{ The Docker callbacks against a fake program runner: the arguments each
  operation sends and the way the program's text and exit code come back. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDockerVfs = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestRootListsTheThreeFolders;
    [Test] procedure TestContainerListHasColorsAndFolders;
    [Test] procedure TestUntaggedImageIsListedById;
    [Test] procedure TestContainerFolderHoldsFsInfoLogs;
    [Test] procedure TestFsListingUsesFindAndFallsBackToLs;
    [Test] procedure TestMissingProgramIsAnIoError;
    [Test] procedure TestMissingPathIsNotFound;
    [Test] procedure TestReadReturnsTheProgramText;
    [Test] procedure TestWriteSendsTheTextOnStdin;
    [Test] procedure TestDeleteAndCreateRunInsideTheContainer;
    [Test] procedure TestRootOfAContainerIsNotDeleted;
    [Test] procedure TestCopyUsesCpWithTheLocalPath;
    [Test] procedure TestExistsTellsFolderFromFile;
    [Test] procedure TestControlContainerReportsFailure;
  end;

implementation

uses
  System.SysUtils, System.JSON, uPluginHostAbi, uDockerFormat, uDockerVfs;

var
  GCalls: TArray<string>;
  GStdIn: string;
  GReply: TFunc<string, string>;
  GExit: TFunc<string, Cardinal>;
  GMissing: Boolean;
  GColorsJson: string;

function FakeRun(const AExe: string; const AArgs: TArray<string>; const AStdIn: string;
  ATimeoutMs: Cardinal; out AOutput: string; out ACode: Cardinal): Boolean;
var
  Line: string;
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
  Result := True;
end;

procedure CaptureColors(const AFolderUri, AJson: string);
begin
  GColorsJson := AJson;
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
  Value: TJSONValue;
begin
  Cb := DockerVfsCallbacks;
  SetLength(Buf, 1024 * 1024);
  Uri := UTF8String(AUri);
  AJson := nil;
  Result := Cb.ListDirectory(PAnsiChar(Uri), nil, nil, 0, PAnsiChar(@Buf[0]), Length(Buf), Neg, More);
  if Result = Ord(verOk) then
  begin
    // The host decodes exactly Neg bytes; a terminator counted in Neg would end up in the JSON text.
    Assert.IsTrue(Neg > 0);
    Assert.AreNotEqual(0, Integer(Buf[Neg - 1]), 'negotiated size must not count the terminator');
    Value := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Buf, 0, Neg));
    AJson := Value as TJSONArray;
  end;
end;

function NameAt(const AArr: TJSONArray; AIndex: Integer): string;
begin
  Result := (AArr.Items[AIndex] as TJSONObject).GetValue<string>('name');
end;

function IsDirAt(const AArr: TJSONArray; AIndex: Integer): Boolean;
begin
  Result := (AArr.Items[AIndex] as TJSONObject).GetValue<Boolean>('isDir');
end;

procedure TTestDockerVfs.Setup;
begin
  GRunTool := FakeRun;
  GCalls := nil;
  GStdIn := '';
  GMissing := False;
  GColorsJson := '';
  GReply := function(ALine: string): string begin Result := ''; end;
  GExit := function(ALine: string): Cardinal begin Result := 0; end;
end;

procedure TTestDockerVfs.TearDown;
begin
  GRunTool := DefaultRunTool;
  GOnRowColors := nil;
end;

procedure TTestDockerVfs.TestRootListsTheThreeFolders;
var
  Arr: TJSONArray;
begin
  Assert.AreEqual(Int64(Ord(verOk)), List('docker:///', Arr));
  try
    Assert.AreEqual(3, Arr.Count);
    Assert.AreEqual('containers', NameAt(Arr, 0));
    Assert.AreEqual('kubernetes', NameAt(Arr, 2));
    Assert.AreEqual(0, Integer(Length(GCalls)), 'the root needs no program');
  finally
    Arr.Free;
  end;
end;

procedure TTestDockerVfs.TestContainerListHasColorsAndFolders;
var
  Arr: TJSONArray;
begin
  GOnRowColors := CaptureColors;
  GReply := function(ALine: string): string
    begin
      Result := 'web|running|nginx' + #10 + 'db|exited|postgres' + #10;
    end;
  Assert.AreEqual(Int64(Ord(verOk)), List('docker:///containers', Arr));
  try
    Assert.AreEqual(2, Arr.Count);
    Assert.IsTrue(IsDirAt(Arr, 0));
    Assert.AreEqual('web', NameAt(Arr, 0));
  finally
    Arr.Free;
  end;
  Assert.IsTrue(Pos('"web":"ok"', GColorsJson) > 0);
  Assert.IsTrue(Pos('"db":"neutral"', GColorsJson) > 0);
  Assert.IsTrue(Pos('docker ps -a', LastCall) = 1);
end;

procedure TTestDockerVfs.TestUntaggedImageIsListedById;
var
  Arr: TJSONArray;
begin
  GReply := function(ALine: string): string
    begin
      Result := 'library/nginx:1|aaa111' + #10 + '<none>:<none>|bbb222' + #10;
    end;
  Assert.AreEqual(Int64(Ord(verOk)), List('docker:///images', Arr));
  try
    Assert.AreEqual('library%2Fnginx:1', NameAt(Arr, 0));
    Assert.AreEqual('bbb222', NameAt(Arr, 1));
    Assert.IsFalse(IsDirAt(Arr, 0));
  finally
    Arr.Free;
  end;
end;

procedure TTestDockerVfs.TestContainerFolderHoldsFsInfoLogs;
var
  Arr: TJSONArray;
begin
  Assert.AreEqual(Int64(Ord(verOk)), List('docker:///containers/web', Arr));
  try
    Assert.AreEqual(3, Arr.Count);
    Assert.AreEqual('fs', NameAt(Arr, 0));
    Assert.IsTrue(IsDirAt(Arr, 0));
    Assert.AreEqual('info.txt', NameAt(Arr, 1));
    Assert.AreEqual('logs.txt', NameAt(Arr, 2));
  finally
    Arr.Free;
  end;
end;

procedure TTestDockerVfs.TestFsListingUsesFindAndFallsBackToLs;
var
  Arr: TJSONArray;
begin
  GReply := function(ALine: string): string
    begin
      if ALine.Contains(' find ') then
        Result := 'd|d|4096|1700000000.0|etc' + #10
      else
        Result := 'etc/' + #10 + 'hosts' + #10;
    end;
  Assert.AreEqual(Int64(Ord(verOk)), List('docker:///containers/web/fs', Arr));
  try
    Assert.AreEqual(1, Arr.Count);
    Assert.AreEqual('etc', NameAt(Arr, 0));
  finally
    Arr.Free;
  end;
  Assert.IsTrue(GCalls[0].StartsWith('docker exec web find / -mindepth 1'), GCalls[0]);

  GCalls := nil;
  GExit := function(ALine: string): Cardinal
    begin
      if ALine.Contains(' find ') then Result := 1 else Result := 0;
    end;
  Assert.AreEqual(Int64(Ord(verOk)), List('docker:///containers/web/fs', Arr));
  try
    Assert.AreEqual(2, Arr.Count);
    Assert.AreEqual('hosts', NameAt(Arr, 1));
  finally
    Arr.Free;
  end;
  Assert.AreEqual('docker exec web ls -1AF /', LastCall);
end;

procedure TTestDockerVfs.TestMissingProgramIsAnIoError;
var
  Arr: TJSONArray;
begin
  GMissing := True;
  Assert.AreEqual(Int64(Ord(verIOError)), List('docker:///containers', Arr));
end;

procedure TTestDockerVfs.TestMissingPathIsNotFound;
var
  Arr: TJSONArray;
begin
  GReply := function(ALine: string): string
    begin
      Result := 'ls: cannot access ''/nope'': No such file or directory';
    end;
  GExit := function(ALine: string): Cardinal begin Result := 2; end;
  Assert.AreEqual(Int64(Ord(verNotFound)), List('docker:///containers/web/fs/nope', Arr));
end;

procedure TTestDockerVfs.TestReadReturnsTheProgramText;
var
  Cb: TVfsCallbacksCdeclV2;
  Buf: TBytes;
  Neg: Int64;
  Uri: UTF8String;
begin
  Cb := DockerVfsCallbacks;
  SetLength(Buf, 4096);
  GReply := function(ALine: string): string begin Result := 'hello from the container'; end;
  Uri := 'docker:///containers/web/fs/etc/motd';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.ReadText(PAnsiChar(Uri), 0, nil, nil, PAnsiChar(@Buf[0]),
    Length(Buf), Neg));
  Assert.AreEqual('hello from the container', UTF8ToString(PAnsiChar(@Buf[0])));
  Assert.AreEqual('docker exec web cat /etc/motd', LastCall);

  Uri := 'docker:///kubernetes/prod/api/logs.txt';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.ReadText(PAnsiChar(Uri), 0, nil, nil, PAnsiChar(@Buf[0]),
    Length(Buf), Neg));
  Assert.AreEqual('kubectl logs --tail=2000 -n prod api', LastCall);

  SetLength(Buf, 4);
  Assert.AreEqual(Int64(Ord(verNeedsBiggerBuffer)), Cb.ReadText(PAnsiChar(Uri), 0, nil, nil,
    PAnsiChar(@Buf[0]), Length(Buf), Neg));
  Assert.AreEqual(Int64(Length('hello from the container') + 1), Neg);
end;

procedure TTestDockerVfs.TestWriteSendsTheTextOnStdin;
var
  Cb: TVfsCallbacksCdeclV2;
  Uri, Text: UTF8String;
begin
  Cb := DockerVfsCallbacks;
  Uri := 'docker:///containers/web/fs/etc/motd';
  Text := 'new text';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.WriteText(PAnsiChar(Uri), PAnsiChar(Text), nil, nil));
  Assert.AreEqual('new text', GStdIn);
  Assert.AreEqual('docker exec -i web sh -c cat > "$1" sh /etc/motd', LastCall);
  Uri := 'docker:///containers/web/info.txt';
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.WriteText(PAnsiChar(Uri), PAnsiChar(Text), nil, nil));
end;

procedure TTestDockerVfs.TestDeleteAndCreateRunInsideTheContainer;
var
  Cb: TVfsCallbacksCdeclV2;
  Uri: UTF8String;
begin
  Cb := DockerVfsCallbacks;
  Uri := 'docker:///containers/web/fs/tmp/x';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Delete(PAnsiChar(Uri), 0, nil, nil));
  Assert.AreEqual('docker exec web rm -rf /tmp/x', LastCall);
  Assert.AreEqual(Int64(Ord(verOk)), Cb.CreateDirectory(PAnsiChar(Uri), nil, nil));
  Assert.AreEqual('docker exec web mkdir -p /tmp/x', LastCall);
  Uri := 'docker:///containers/web';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Delete(PAnsiChar(Uri), 0, nil, nil));
  Assert.AreEqual('docker rm -f web', LastCall);
  Uri := 'docker:///kubernetes/prod/api';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Delete(PAnsiChar(Uri), 0, nil, nil));
  Assert.AreEqual('kubectl delete pod -n prod api', LastCall);
end;

procedure TTestDockerVfs.TestRootOfAContainerIsNotDeleted;
var
  Cb: TVfsCallbacksCdeclV2;
  Uri: UTF8String;
begin
  Cb := DockerVfsCallbacks;
  Uri := 'docker:///containers/web/fs';
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.Delete(PAnsiChar(Uri), 0, nil, nil));
  Assert.AreEqual(0, Integer(Length(GCalls)));
  Uri := 'docker:///containers/web/logs.txt';
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.Delete(PAnsiChar(Uri), 0, nil, nil));
end;

procedure TTestDockerVfs.TestCopyUsesCpWithTheLocalPath;
var
  Cb: TVfsCallbacksCdeclV2;
  Remote, Local, Other: UTF8String;
begin
  Cb := DockerVfsCallbacks;
  Remote := 'docker:///containers/web/fs/etc/hosts';
  Local := 'file:///C:/Temp/hosts';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.CopyItem(PAnsiChar(Remote), PAnsiChar(Local), 1, nil, nil));
  Assert.IsTrue(LastCall.StartsWith('docker cp web:/etc/hosts '), LastCall);
  Assert.AreEqual(Int64(Ord(verOk)), Cb.CopyItem(PAnsiChar(Local), PAnsiChar(Remote), 1, nil, nil));
  Assert.IsTrue(LastCall.EndsWith(' web:/etc/hosts'), LastCall);
  Other := 'docker:///containers/db/fs/x';
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.CopyItem(PAnsiChar(Remote), PAnsiChar(Other), 1, nil, nil));
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.MoveItem(PAnsiChar(Remote), PAnsiChar(Local), 1, nil, nil));
end;

procedure TTestDockerVfs.TestExistsTellsFolderFromFile;
var
  Cb: TVfsCallbacksCdeclV2;
  Uri: UTF8String;
  IsDir: Int64;
begin
  Cb := DockerVfsCallbacks;
  Uri := 'docker:///containers/web/fs/etc';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Exists(PAnsiChar(Uri), nil, nil, IsDir));
  Assert.AreEqual(Int64(1), IsDir);

  GExit := function(ALine: string): Cardinal
    begin
      if ALine.Contains(' -d ') then Result := 1 else Result := 0;
    end;
  Uri := 'docker:///containers/web/fs/etc/hosts';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Exists(PAnsiChar(Uri), nil, nil, IsDir));
  Assert.AreEqual(Int64(0), IsDir);

  GExit := function(ALine: string): Cardinal begin Result := 1; end;
  Assert.AreEqual(Int64(Ord(verNotFound)), Cb.Exists(PAnsiChar(Uri), nil, nil, IsDir));
end;

procedure TTestDockerVfs.TestControlContainerReportsFailure;
begin
  Assert.AreEqual('', ControlContainer('stop', 'web'));
  Assert.AreEqual('docker stop web', LastCall);
  GReply := function(ALine: string): string begin Result := 'Error: No such container: web' + #10; end;
  GExit := function(ALine: string): Cardinal begin Result := 1; end;
  Assert.AreEqual('Error: No such container: web', ControlContainer('start', 'web'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDockerVfs);

end.
