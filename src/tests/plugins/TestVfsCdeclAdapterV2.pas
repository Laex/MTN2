unit TestVfsCdeclAdapterV2;

{ The version 2 VFS table of a plugin (TVfsCallbacksCdeclV2) behind
  IVirtualFileSystem: paged listings, a buffer that has to grow, progress,
  cancellation and the message a plugin attaches to a failure. The "plugin" is
  a set of cdecl functions in this unit. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVfsCdeclAdapterV2 = class
  public
    [Test] procedure TestListingArrivesInPagesAndKeepsOrder;
    [Test] procedure TestListingRetriesWithTheBufferThePluginAsksFor;
    [Test] procedure TestCopyReportsProgressAndSucceeds;
    [Test] procedure TestCancelledTokenStopsThePluginCall;
    [Test] procedure TestPluginErrorTextReachesTheError;
    [Test] procedure TestFlagsCarryOverwriteAndTimestamps;
    [Test] procedure TestNotFoundExistsIsNotAnError;
    [Test] procedure TestResultCodesMapToVfsErrors;
    [Test] procedure TestUnixModeComesThroughTheListing;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Math,
  uVfsTypes, uPluginHostAbi, uVfsCdeclAdapterV2;

const
  cPageSize = 2;
  cEntryCount = 5;

var
  GLastFlags: Int64;
  GLastListUri: string;

procedure PutUtf8(const AText: string; ABuf: PAnsiChar; ABufSize: Int64;
  out ANegotiated: Int64; out AFits: Boolean);
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AText);
  ANegotiated := Length(Bytes);
  AFits := ANegotiated <= ABufSize;
  if AFits and (ANegotiated > 0) then
    Move(Bytes[0], ABuf^, ANegotiated);
end;

function FakeList(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  AOffset: Int64; ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64;
  out AMore: Int64): Int64; cdecl;
var
  Uri, Json: string;
  I, Last: Integer;
  Fits: Boolean;
begin
  Uri := UTF8ToString(AURI);
  GLastListUri := Uri;
  AMore := 0;
  if Uri = 'fake://big/' then
  begin
    // One entry with a name that cannot fit the first buffer.
    Json := '[{"name":"' + StringOfChar('n', 5 * 1024 * 1024) + '","size":1}]';
    PutUtf8(Json, ABuf, ABufSize, ANegotiatedSize, Fits);
    if Fits then
      Result := Ord(verOk)
    else
      Result := Ord(verNeedsBiggerBuffer);
    Exit;
  end;
  if Uri = 'fake://mode/' then
  begin
    PutUtf8('[{"name":"x","unixMode":493}]', ABuf, ABufSize, ANegotiatedSize, Fits);
    Exit(Ord(verOk));
  end;
  Json := '[';
  Last := Min(AOffset + cPageSize, cEntryCount) - 1;
  for I := AOffset to Last do
  begin
    if I > AOffset then
      Json := Json + ',';
    Json := Json + '{"name":"e' + IntToStr(I) + '","size":' + IntToStr(I) + '}';
  end;
  Json := Json + ']';
  PutUtf8(Json, ABuf, ABufSize, ANegotiatedSize, Fits);
  if Last + 1 < cEntryCount then
    AMore := 1;
  Result := Ord(verOk);
end;

function FakeCopy(AFromURI, AToURI: PAnsiChar; AFlags: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  I: Integer;
begin
  GLastFlags := AFlags;
  if Pos('fail', UTF8ToString(AFromURI)) > 0 then
  begin
    ACtx^.SetErrorText(ACtx, 'Login incorrect: 530');
    Exit(Ord(verAuthFailed));
  end;
  for I := 1 to 10 do
    if ACtx^.ReportProgress(ACtx, I * 10, 100, I * 10, 100, 'file.bin') <> 0 then
      Exit(Ord(verCancelled));
  Result := Ord(verOk);
end;

function FakeExists(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  out AIsDirectory: Int64): Int64; cdecl;
begin
  AIsDirectory := 0;
  if Pos('missing', UTF8ToString(AURI)) > 0 then
    Exit(Ord(verNotFound));
  AIsDirectory := 1;
  Result := Ord(verOk);
end;

function MakeBackend: IVirtualFileSystem;
var
  Table: TVfsCallbacksCdeclV2;
begin
  Table := Default(TVfsCallbacksCdeclV2);
  Table.ListDirectory := FakeList;
  Table.CopyItem := FakeCopy;
  Table.Exists := FakeExists;
  Result := TCdeclVfsBackendV2.Create(Table, nil);
end;

// Runs the main-thread queue until AFlag is set (or ~10 s pass).
procedure Pump(const AFlag: PBoolean);
var
  I: Integer;
begin
  for I := 1 to 1000 do
  begin
    CheckSynchronize(10);
    if AFlag^ then
      Exit;
  end;
end;

procedure TTestVfsCdeclAdapterV2.TestListingArrivesInPagesAndKeepsOrder;
var
  Done: Boolean;
  Items: TArray<TVfsEntry>;
  Err: TVfsError;
  I: Integer;
begin
  Done := False;
  MakeBackend.ListDirectoryAsync('fake://x/', nil,
    procedure(const AItems: TArray<TVfsEntry>; const AError: TVfsError)
    begin
      Items := AItems;
      Err := AError;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done, 'the listing finished');
  Assert.IsTrue(Err.Code = vecOk, 'no error');
  Assert.IsTrue(Length(Items) = cEntryCount, 'every page was fetched');
  for I := 0 to High(Items) do
    Assert.AreEqual('e' + IntToStr(I), Items[I].Name);
end;

procedure TTestVfsCdeclAdapterV2.TestListingRetriesWithTheBufferThePluginAsksFor;
var
  Done: Boolean;
  Items: TArray<TVfsEntry>;
  Err: TVfsError;
begin
  Done := False;
  MakeBackend.ListDirectoryAsync('fake://big/', nil,
    procedure(const AItems: TArray<TVfsEntry>; const AError: TVfsError)
    begin
      Items := AItems;
      Err := AError;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done, 'the listing finished');
  Assert.IsTrue(Err.Code = vecOk, 'no error: ' + Err.Message);
  Assert.IsTrue(Length(Items) = 1, 'the entry arrived');
  Assert.IsTrue(Length(Items[0].Name) = 5 * 1024 * 1024, 'whole name');
end;

procedure TTestVfsCdeclAdapterV2.TestCopyReportsProgressAndSucceeds;
var
  Done: Boolean;
  Ok: Boolean;
  LastDone, LastTotal: Int64;
  LastName: string;
  Calls: Integer;
begin
  Done := False;
  Calls := 0;
  LastDone := 0;
  LastTotal := 0;
  MakeBackend.CopyAsync('fake://x/a', 'file:///C:/b', nil,
    procedure(const ADone, ATotal: Int64; const ACurrentName: string;
      const AItemDone, AItemTotal: Int64; const AItemSrcPath, AItemDstPath: string)
    begin
      Inc(Calls);
      LastDone := ADone;
      LastTotal := ATotal;
      LastName := ACurrentName;
    end,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Ok := ASuccess;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done and Ok, 'the copy succeeded');
  Assert.IsTrue(Calls > 0, 'progress reached the host');
  Assert.IsTrue((LastDone = 100) and (LastTotal = 100), 'the last report is the full size');
  Assert.AreEqual('file.bin', LastName);
end;

procedure TTestVfsCdeclAdapterV2.TestCancelledTokenStopsThePluginCall;
var
  Done: Boolean;
  Err: TVfsError;
  Token: TJobCancelToken;
  Ref: IJobCancelToken;
begin
  Done := False;
  Token := TJobCancelToken.Create;
  Ref := Token;
  Token.Cancel;
  MakeBackend.CopyAsync('fake://x/a', 'file:///C:/b', Ref,
    procedure(const ADone, ATotal: Int64; const ACurrentName: string;
      const AItemDone, AItemTotal: Int64; const AItemSrcPath, AItemDstPath: string)
    begin
    end,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Err := AError;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done, 'the call returned');
  Assert.IsTrue(Err.Code = vecCancelled, 'the plugin saw the cancellation');
end;

procedure TTestVfsCdeclAdapterV2.TestPluginErrorTextReachesTheError;
var
  Done: Boolean;
  Err: TVfsError;
begin
  Done := False;
  MakeBackend.CopyAsync('fake://fail/a', 'file:///C:/b', nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Err := AError;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done, 'the call returned');
  Assert.IsTrue(Err.Code = vecAccessDenied, 'a login failure is access denied');
  Assert.AreEqual('Login incorrect: 530', Err.Message);
end;

procedure TTestVfsCdeclAdapterV2.TestFlagsCarryOverwriteAndTimestamps;
var
  Done: Boolean;
begin
  Done := False;
  MakeBackend.CopyAsync('fake://x/a', 'file:///C:/b', nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Done := True;
    end, True, True);
  Pump(@Done);
  Assert.IsTrue(GLastFlags = 3, 'bit 0 overwrite, bit 1 timestamps');
  Done := False;
  MakeBackend.CopyAsync('fake://x/a', 'file:///C:/b', nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Done := True;
    end, False, False);
  Pump(@Done);
  Assert.IsTrue(GLastFlags = 0, 'no flags');
end;

procedure TTestVfsCdeclAdapterV2.TestNotFoundExistsIsNotAnError;
var
  Done, Found, IsDir: Boolean;
  Err: TVfsError;
begin
  Done := False;
  MakeBackend.ExistsAsync('fake://x/missing', nil,
    procedure(const AExists: Boolean; const AIsDirectory: Boolean; const AError: TVfsError)
    begin
      Found := AExists;
      IsDir := AIsDirectory;
      Err := AError;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done and (not Found) and (Err.Code = vecOk), 'missing is a plain "no"');
  Done := False;
  MakeBackend.ExistsAsync('fake://x/dir', nil,
    procedure(const AExists: Boolean; const AIsDirectory: Boolean; const AError: TVfsError)
    begin
      Found := AExists;
      IsDir := AIsDirectory;
      Err := AError;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done and Found and IsDir, 'a folder exists');
end;

procedure TTestVfsCdeclAdapterV2.TestResultCodesMapToVfsErrors;
begin
  Assert.IsTrue(V2ErrorFromCode(Ord(verOk), 'u', '').Code = vecOk);
  Assert.IsTrue(V2ErrorFromCode(Ord(verNotFound), 'u', '').Code = vecNotFound);
  Assert.IsTrue(V2ErrorFromCode(Ord(verAccessDenied), 'u', '').Code = vecAccessDenied);
  Assert.IsTrue(V2ErrorFromCode(Ord(verAlreadyExists), 'u', '').Code = vecAlreadyExists);
  Assert.IsTrue(V2ErrorFromCode(Ord(verNotSupported), 'u', '').Code = vecNotSupported);
  Assert.IsTrue(V2ErrorFromCode(Ord(verInvalidURI), 'u', '').Code = vecInvalidURI);
  Assert.IsTrue(V2ErrorFromCode(Ord(verCancelled), 'u', '').Code = vecCancelled);
  Assert.IsTrue(V2ErrorFromCode(Ord(verAuthFailed), 'u', '').Code = vecAccessDenied);
  Assert.IsTrue(V2ErrorFromCode(Ord(verTimeout), 'u', '').Code = vecIOError);
  Assert.IsTrue(V2ErrorFromCode(99, 'u', '').Code = vecIOError, 'an unknown code is an I/O error');
  Assert.AreEqual('why', V2ErrorFromCode(Ord(verTimeout), 'u', 'why').Message,
    'the text of the plugin replaces the stock message');
  Assert.AreEqual('u', V2ErrorFromCode(Ord(verTimeout), 'u', '').URI);
end;

procedure TTestVfsCdeclAdapterV2.TestUnixModeComesThroughTheListing;
var
  Done: Boolean;
  Items: TArray<TVfsEntry>;
begin
  Done := False;
  MakeBackend.ListDirectoryAsync('fake://mode/', nil,
    procedure(const AItems: TArray<TVfsEntry>; const AError: TVfsError)
    begin
      Items := AItems;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done and (Length(Items) = 1), 'one entry');
  Assert.IsTrue(Items[0].UnixMode = 493, 'octal 755');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestVfsCdeclAdapterV2);

end.
