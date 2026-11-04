unit TestWinSysSystem;

{ The registry, process and service units against the real system: a key is
  made under HKEY_CURRENT_USER and removed again; the process list holds this
  process; the service list is read from the service manager. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWinSysSystem = class
  public
    [Test] procedure TestRegistryKeyAndValueLifeCycle;
    [Test] procedure TestRegistryRootListsTheFiveHives;
    [Test] procedure TestRegistryDeleteRefusesAHive;
    [Test] procedure TestRegistryNamesWithSlashSurviveTheRoundTrip;
    [Test] procedure TestProcessListHoldsThisProcess;
    [Test] procedure TestProcessInfoNamesThePid;
    [Test] procedure TestProcessCannotTerminateItself;
    [Test] procedure TestServiceListIsNotEmptyAndColored;
    [Test] procedure TestServiceInfoOfAMissingServiceFails;
    [Test] procedure TestVfsListsAndReadsThroughTheCallbackTable;
  end;

implementation

uses
  System.SysUtils, System.JSON, Winapi.Windows, Winapi.WinSvc, uPluginHostAbi,
  uWinSysFormat, uWinSysRegistry, uWinSysProcess, uWinSysServices, uWinSysVfs;

function TestSegs(const AParts: array of string): TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Length(AParts) + 2);
  Result[0] := 'HKEY_CURRENT_USER';
  Result[1] := 'Software';
  for I := 0 to High(AParts) do
    Result[I + 2] := AParts[I];
end;

procedure CleanTestKey;
begin
  RegDeletePath(TestSegs(['MTN2WinSysTest']));
end;

function HasRow(const ARows: TRegRows; const AName: string; AIsKey: Boolean): Boolean;
var
  R: TRegRow;
begin
  for R in ARows do
    if (R.Name = AName) and (R.IsKey = AIsKey) then
      Exit(True);
  Result := False;
end;

function OwnProcessName: string;
begin
  Result := MakeProcessName(ExtractFileName(ParamStr(0)), GetCurrentProcessId);
end;

procedure TTestWinSysSystem.TestRegistryKeyAndValueLifeCycle;
var
  Key, Value: TArray<string>;
  Rows: TRegRows;
  Kind: TRegPathKind;
  T: Cardinal;
  Data, Read: TBytes;
begin
  CleanTestKey;
  Key := TestSegs(['MTN2WinSysTest']);
  Value := TestSegs(['MTN2WinSysTest', 'Name']);
  try
    Assert.AreEqual(Cardinal(0), RegCreateKeyPath(Key), 'create key');
    Assert.AreEqual(Cardinal(0), RegCreateKeyPath(TestSegs(['MTN2WinSysTest', 'Child'])));
    Assert.IsTrue(ParseRegValueText('hello', cRegSz, T, Data));
    Assert.AreEqual(Cardinal(0), RegWriteValue(Value, T, Data), 'write value');

    Assert.AreEqual(Cardinal(0), RegListPath(Key, Rows));
    Assert.IsTrue(HasRow(Rows, 'Child', True), 'the child key is a folder');
    Assert.IsTrue(HasRow(Rows, 'Name', False), 'the value is a file');

    Assert.AreEqual(Cardinal(0), RegPathInfo(Key, Kind));
    Assert.AreEqual(Ord(rpKey), Ord(Kind));
    Assert.AreEqual(Cardinal(0), RegPathInfo(Value, Kind));
    Assert.AreEqual(Ord(rpValue), Ord(Kind));

    Assert.AreEqual(Cardinal(0), RegReadValue(Value, T, Read));
    Assert.AreEqual(Cardinal(cRegSz), T);
    Assert.AreEqual('Type: REG_SZ' + #10#10 + 'hello', FormatRegValue(T, Read));

    Assert.AreEqual(Cardinal(0), RegDeletePath(Value), 'delete value');
    Assert.AreNotEqual(Cardinal(0), RegPathInfo(Value, Kind), 'the value is gone');
    Assert.AreEqual(Cardinal(0), RegDeletePath(Key), 'delete key with its child');
    Assert.AreNotEqual(Cardinal(0), RegPathInfo(Key, Kind), 'the key is gone');
  finally
    CleanTestKey;
  end;
end;

procedure TTestWinSysSystem.TestRegistryRootListsTheFiveHives;
var
  Rows: TRegRows;
begin
  Assert.AreEqual(Cardinal(0), RegListPath(nil, Rows));
  Assert.AreEqual(5, Integer(Length(Rows)));
  Assert.IsTrue(HasRow(Rows, 'HKEY_LOCAL_MACHINE', True));
end;

procedure TTestWinSysSystem.TestRegistryDeleteRefusesAHive;
begin
  Assert.AreEqual(Cardinal(ERROR_ACCESS_DENIED), RegDeletePath(TArray<string>.Create('HKEY_CURRENT_USER')));
  Assert.AreEqual(Cardinal(ERROR_ACCESS_DENIED), RegDeletePath(nil));
end;

procedure TTestWinSysSystem.TestRegistryNamesWithSlashSurviveTheRoundTrip;
var
  Key, Parsed: TArray<string>;
  Rows: TRegRows;
  T: Cardinal;
  Data, Read: TBytes;
  Kind: TWinSysKind;
begin
  CleanTestKey;
  Key := TestSegs(['MTN2WinSysTest']);
  try
    Assert.AreEqual(Cardinal(0), RegCreateKeyPath(Key));
    // The value name a/b reaches the registry as one name.
    Assert.IsTrue(ParseWinSysUri('reg:///HKEY_CURRENT_USER/Software/MTN2WinSysTest/a%2Fb', Kind, Parsed));
    Assert.IsTrue(ParseRegValueText('x', cRegSz, T, Data));
    Assert.AreEqual(Cardinal(0), RegWriteValue(Parsed, T, Data));
    Assert.AreEqual(Cardinal(0), RegListPath(Key, Rows));
    Assert.IsTrue(HasRow(Rows, 'a%2Fb', False), 'listed under its encoded name');
    Assert.AreEqual(Cardinal(0), RegReadValue(Parsed, T, Read));
  finally
    CleanTestKey;
  end;
end;

procedure TTestWinSysSystem.TestProcessListHoldsThisProcess;
var
  Rows: TProcRows;
  R: TProcRow;
  Found: Boolean;
begin
  Assert.AreEqual(Cardinal(0), ListProcesses(Rows));
  Found := False;
  for R in Rows do
    if R.Pid = GetCurrentProcessId then
    begin
      Found := True;
      Assert.IsTrue(R.WorkingSet > 0, 'working set of this process');
      Assert.IsTrue(R.Started > 0, 'start time of this process');
    end;
  Assert.IsTrue(Found);
end;

procedure TTestWinSysSystem.TestProcessInfoNamesThePid;
var
  Text: string;
begin
  Assert.AreEqual(Cardinal(0), ProcessInfoText(GetCurrentProcessId, Text));
  Assert.IsTrue(Pos('PID:             ' + UIntToStr(GetCurrentProcessId), Text) > 0);
  Assert.IsTrue(Pos('Working set:', Text) > 0);
end;

procedure TTestWinSysSystem.TestProcessCannotTerminateItself;
begin
  Assert.AreEqual(Cardinal(ERROR_ACCESS_DENIED), TerminateProcessById(GetCurrentProcessId));
  Assert.AreEqual(Cardinal(ERROR_ACCESS_DENIED), TerminateProcessById(0));
end;

procedure TTestWinSysSystem.TestServiceListIsNotEmptyAndColored;
var
  Rows: TSvcRows;
  R: TSvcRow;
begin
  Assert.AreEqual(Cardinal(0), ListServices(Rows));
  Assert.IsTrue(Length(Rows) > 0);
  for R in Rows do
  begin
    Assert.IsTrue(R.Name <> '');
    Assert.IsTrue(ServiceStateRole(R.State) <> '');
  end;
  Assert.AreEqual('ok', ServiceStateRole(SERVICE_RUNNING));
  Assert.AreEqual('neutral', ServiceStateRole(SERVICE_STOPPED));
  Assert.AreEqual('warn', ServiceStateRole(SERVICE_START_PENDING));
end;

procedure TTestWinSysSystem.TestServiceInfoOfAMissingServiceFails;
var
  Text: string;
begin
  Assert.AreEqual(Cardinal(ERROR_SERVICE_DOES_NOT_EXIST), ServiceInfoText('MTN2NoSuchService', Text));
end;

var
  GColorsFolder, GColorsJson: string;

procedure CaptureColors(const AFolderUri, AJson: string);
begin
  GColorsFolder := AFolderUri;
  GColorsJson := AJson;
end;

procedure TTestWinSysSystem.TestVfsListsAndReadsThroughTheCallbackTable;
var
  Cb: TVfsCallbacksCdeclV2;
  Buf: TBytes;
  Neg, More, IsDir: Int64;
  Arr: TJSONValue;
  Uri: UTF8String;

  function BufText: string;
  begin
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
  end;

begin
  Cb := WinSysVfsCallbacks;
  SetLength(Buf, 2 * 1024 * 1024);

  Uri := 'reg:///';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.ListDirectory(PAnsiChar(Uri), nil, nil, 0, PAnsiChar(@Buf[0]),
    Length(Buf), Neg, More));
  // The host decodes exactly Neg bytes: the terminator must not be counted.
  Assert.AreNotEqual(0, Integer(Buf[Neg - 1]));
  Arr := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Buf, 0, Neg));
  try
    Assert.IsTrue(Arr is TJSONArray);
    Assert.AreEqual(5, (Arr as TJSONArray).Count);
  finally
    Arr.Free;
  end;

  Uri := 'proc:///';
  Assert.AreEqual(Int64(Ord(verOk)), Cb.ListDirectory(PAnsiChar(Uri), nil, nil, 0, PAnsiChar(@Buf[0]),
    Length(Buf), Neg, More));
  Assert.IsTrue(Pos(OwnProcessName, BufText) > 0, 'this process is listed');

  GOnServiceColors := CaptureColors;
  try
    Uri := 'svc:///';
    Assert.AreEqual(Int64(Ord(verOk)), Cb.ListDirectory(PAnsiChar(Uri), nil, nil, 0, PAnsiChar(@Buf[0]),
      Length(Buf), Neg, More));
  finally
    GOnServiceColors := nil;
  end;
  Assert.AreEqual('svc:///', GColorsFolder, 'the colors go with the folder address');
  Assert.IsTrue(GColorsJson.StartsWith('{'));

  Uri := UTF8String('proc:///' + OwnProcessName);
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Exists(PAnsiChar(Uri), nil, nil, IsDir));
  Assert.AreEqual(Int64(0), IsDir);
  Assert.AreEqual(Int64(Ord(verOk)), Cb.ReadText(PAnsiChar(Uri), 0, nil, nil, PAnsiChar(@Buf[0]),
    Length(Buf), Neg));
  Assert.IsTrue(Pos('PID:', BufText) > 0);

  Uri := 'proc:///nope.exe (4294967)';
  Assert.AreEqual(Int64(Ord(verNotFound)), Cb.Exists(PAnsiChar(Uri), nil, nil, IsDir));
  Uri := 'svc:///AnyService';
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.Delete(PAnsiChar(Uri), 0, nil, nil),
    'services are not deleted');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWinSysSystem);

end.
