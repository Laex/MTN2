unit TestFindRouter;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFindRouter = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestProviderHitsReachTheCaller;
    [Test] procedure TestBoundsAreAppliedToProviderHits;
    [Test] procedure TestMaxResultsTruncates;
    [Test] procedure TestProviderFailureBeforeHitsFallsBackToTheWalk;
    [Test] procedure TestProviderFailureAfterHitsEndsWithTheHitsFound;
    [Test] procedure TestUnservableOptionsSkipTheProvider;
    [Test] procedure TestCapabilityMissingSkipsTheProvider;
    [Test] procedure TestCancelEndsTheSearch;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.DateUtils,
  uVfsTypes, uFileFind, uFindRouter, uPluginHostAbi, uPluginServiceHost, uServiceRegistry;

const
  cPlugin = 'test.finder';
  cHitsMessage =
    '{"jsonrpc":"2.0","method":"search.hits","params":{"hits":[' +
    '{"path":"C:\\Work\\small.txt","size":10,"modified":"2026-01-02T03:04:05"},' +
    '{"path":"C:\\Work\\big.txt","size":5000,"modified":"2026-01-02T03:04:05"},' +
    '{"path":"C:\\Work\\old.txt","size":500,"modified":"2020-01-02T03:04:05"}]}}';
  cOkResponse = '{"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"count":3,"truncated":false}}}';
  cErrorResponse = '{"jsonrpc":"2.0","id":1,"error":{"code":-32002,"message":"not running"}}';

type
  TProviderMode = (pmHitsThenOk, pmErrorOnly, pmHitsThenError, pmSilent);

var
  GMode: TProviderMode;
  GCaps: string;
  GCalls: Integer;
  GDone: Boolean;
  GHits: TArray<TFindHit>;
  GError: TVfsError;
  GTruncated: Boolean;
  GStreamed: Integer;

function Provider(AUserData: Pointer; ACall: Int64; AMessageJson: PAnsiChar): Int64; cdecl;
begin
  Inc(GCalls);
  case GMode of
    pmHitsThenOk:
      begin
        HostServiceNotify(ACall, cHitsMessage);
        HostServiceReply(ACall, cOkResponse);
      end;
    pmErrorOnly:
      HostServiceReply(ACall, cErrorResponse);
    pmHitsThenError:
      begin
        HostServiceNotify(ACall, cHitsMessage);
        HostServiceReply(ACall, cErrorResponse);
      end;
  end;
  Result := 0;
end;

procedure TTestFindRouter.Setup;
begin
  PluginServicesUnregister(cPlugin);
  GMode := pmHitsThenOk;
  GCaps := 'name,mask,subdirs,folders,case,words';
  GCalls := 0;
  GDone := False;
  SetLength(GHits, 0);
  GError := TVfsError.Ok;
  GTruncated := False;
  GStreamed := 0;
end;

procedure TTestFindRouter.TearDown;
begin
  PluginServicesUnregister(cPlugin);
  ServiceRegistry.Pump;
  CheckSynchronize(0);
end;

function Register: Int64;
var
  Describe: string;
begin
  Describe := '{"capabilities":["' + StringReplace(GCaps, ',', '","', [rfReplaceAll]) + '"]}';
  Result := HostRegisterService(cPlugin, 'search.files', 1, PAnsiChar(UTF8String(Describe)),
    Provider, nil, 100);
end;

procedure Run(const AOptions: TFindOptions; ACancel: IJobCancelToken = nil);
begin
  FindFilesRouted(AOptions, ACancel,
    procedure(AFound: Integer; const ADir: string)
    begin
    end,
    procedure(const AHits: TArray<TFindHit>; const AError: TVfsError; ATruncated: Boolean)
    begin
      GHits := AHits;
      GError := AError;
      GTruncated := ATruncated;
      GDone := True;
    end,
    procedure(const ANew: TArray<TFindHit>)
    begin
      Inc(GStreamed, Length(ANew));
    end);
end;

procedure WaitDone;
var
  Tick: UInt64;
begin
  Tick := TThread.GetTickCount64;
  while not GDone and (TThread.GetTickCount64 - Tick < 5000) do
  begin
    ServiceRegistry.Pump;
    CheckSynchronize(5);
  end;
  Assert.IsTrue(GDone, 'the search finished');
end;

function Opts: TFindOptions;
begin
  Result := DefaultFindOptions('C:\Work', '*.txt', True);
end;

procedure TTestFindRouter.TestProviderHitsReachTheCaller;
begin
  Assert.AreEqual<Int64>(0, Register);
  Run(Opts);
  WaitDone;
  Assert.AreEqual<Integer>(1, GCalls);
  Assert.AreEqual<Integer>(3, Length(GHits));
  Assert.AreEqual<Integer>(3, GStreamed, 'streamed as they arrived');
  Assert.IsTrue(GError.Code = vecOk);
  Assert.IsFalse(GTruncated);
  Assert.AreEqual('C:\Work\small.txt', GHits[0].Path);
end;

procedure TTestFindRouter.TestBoundsAreAppliedToProviderHits;
var
  O: TFindOptions;
begin
  Assert.AreEqual<Int64>(0, Register);
  O := Opts;
  O.MinSize := 100;
  O.MaxSize := 1000;
  O.ModifiedFrom := EncodeDate(2025, 1, 1);
  Run(O);
  WaitDone;
  Assert.AreEqual<Integer>(0, Length(GHits), 'small, big and old are each outside one bound');
  Assert.IsTrue(GError.Code = vecOk);
end;

procedure TTestFindRouter.TestMaxResultsTruncates;
var
  O: TFindOptions;
begin
  Assert.AreEqual<Int64>(0, Register);
  O := Opts;
  O.MaxResults := 2;
  Run(O);
  WaitDone;
  Assert.AreEqual<Integer>(2, Length(GHits));
  Assert.IsTrue(GTruncated);
end;

procedure TTestFindRouter.TestProviderFailureBeforeHitsFallsBackToTheWalk;
var
  Dir: string;
  O: TFindOptions;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn_router_' + IntToStr(TThread.GetTickCount64));
  TDirectory.CreateDirectory(Dir);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'walked.txt'), 'x');
    GMode := pmErrorOnly;
    Assert.AreEqual<Int64>(0, Register);
    O := DefaultFindOptions(Dir, '*.txt', True);
    Run(O);
    WaitDone;
    Assert.AreEqual<Integer>(1, GCalls, 'the provider was asked first');
    Assert.AreEqual<Integer>(1, Length(GHits), 'the walk found the file');
    Assert.IsTrue(Pos('walked.txt', GHits[0].Path) > 0);
    Assert.IsTrue(GError.Code = vecOk);
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestFindRouter.TestProviderFailureAfterHitsEndsWithTheHitsFound;
begin
  GMode := pmHitsThenError;
  Assert.AreEqual<Int64>(0, Register);
  Run(Opts);
  WaitDone;
  Assert.AreEqual<Integer>(3, Length(GHits));
  Assert.IsFalse(GError.Code = vecOk, 'the failure is reported');
end;

procedure TTestFindRouter.TestUnservableOptionsSkipTheProvider;
var
  Dir: string;
  O: TFindOptions;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn_router_' + IntToStr(TThread.GetTickCount64));
  TDirectory.CreateDirectory(Dir);
  try
    Assert.AreEqual<Int64>(0, Register);
    O := DefaultFindOptions(Dir, '*.txt', True);
    O.RequireAttr := 1;
    Run(O);
    WaitDone;
    Assert.AreEqual<Integer>(0, GCalls, 'attribute filters stay with the walk');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestFindRouter.TestCapabilityMissingSkipsTheProvider;
var
  Dir: string;
  O: TFindOptions;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn_router_' + IntToStr(TThread.GetTickCount64));
  TDirectory.CreateDirectory(Dir);
  try
    Assert.AreEqual<Int64>(0, Register);
    O := DefaultFindOptions(Dir, '*.txt', True);
    O.ContainingText := 'needle';
    Run(O);
    WaitDone;
    Assert.AreEqual<Integer>(0, GCalls, 'the provider lists no content capability');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

type
  TTestToken = class(TInterfacedObject, IJobCancelToken)
  private
    FCancelled: Boolean;
  public
    function IsCancellationRequested: Boolean;
    procedure Cancel;
  end;

function TTestToken.IsCancellationRequested: Boolean;
begin
  Result := FCancelled;
end;

procedure TTestToken.Cancel;
begin
  FCancelled := True;
end;

procedure TTestFindRouter.TestCancelEndsTheSearch;
var
  Token: IJobCancelToken;
begin
  GMode := pmSilent;
  Assert.AreEqual<Int64>(0, Register);
  Token := TTestToken.Create;
  Run(Opts, Token);
  Token.Cancel;
  WaitDone;
  Assert.IsTrue(GError.Code = vecCancelled, 'cancelled');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFindRouter);

end.
