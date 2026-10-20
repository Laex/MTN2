unit TestPluginTransfers;

{ Copy and move between local folders and plugin-served schemes through the
  default VFS stack: a plugin to or from a local folder (move is copy plus
  delete of the source), and two different plugins (through a local temporary
  copy). The plugins are in-memory stubs. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginTransfers = class
  private
    FRoot: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestCopyLocalFileToPlugin;
    [Test] procedure TestMoveLocalFileToPluginDeletesTheSource;
    [Test] procedure TestMovePluginFileToLocalDeletesTheSource;
    [Test] procedure TestCopyBetweenTwoPluginsGoesThroughATempFolder;
    [Test] procedure TestMoveBetweenTwoPluginsDeletesTheSource;
    [Test] procedure TestFailedFirstHopLeavesSourceAndReportsTheError;
    [Test] procedure TestFailedCopyDoesNotDeleteTheMovedSource;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  uVfsTypes, uVfsRegistry, uTextEncoding;

type
  // A flat in-memory "plugin": items are byte arrays by URI.
  TMemVfs = class(TInterfacedObject, IVirtualFileSystem)
  public
    Items: TDictionary<string, TBytes>;
    FailCopy: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure ListDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsListCallback);
    procedure DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
      ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
      AOnDone: TVfsBoolCallback);
    procedure CreateDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsBoolCallback);
    procedure CopyAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure MoveAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure ReadTextAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
    procedure ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
    procedure WriteTextAsync(const AURI, AText: string; AEncoding: TTextFileEncoding;
      ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
    procedure ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsExistsCallback);
    procedure GetFreeSpaceAsync(const ARootURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsFreeSpaceCallback);
  end;

constructor TMemVfs.Create;
begin
  inherited Create;
  Items := TDictionary<string, TBytes>.Create;
end;

destructor TMemVfs.Destroy;
begin
  Items.Free;
  inherited Destroy;
end;

procedure TMemVfs.ListDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsListCallback);
begin
  TThread.Queue(nil,
    procedure
    begin
      AOnDone(nil, TVfsError.Ok);
    end);
end;

procedure TMemVfs.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback);
var
  Ok: Boolean;
begin
  TMonitor.Enter(Items);
  try
    Ok := Items.ContainsKey(AURI);
    Items.Remove(AURI);
  finally
    TMonitor.Exit(Items);
  end;
  TThread.Queue(nil,
    procedure
    begin
      if Ok then
        AOnDone(True, TVfsError.Ok)
      else
        AOnDone(False, TVfsError.Make(vecNotFound, 'Not found', AURI));
    end);
end;

procedure TMemVfs.CreateDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsBoolCallback);
begin
  TThread.Queue(nil,
    procedure
    begin
      AOnDone(True, TVfsError.Ok);
    end);
end;

procedure TMemVfs.CopyAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback; AOverwrite: Boolean;
  APreserveTimestamps: Boolean);
var
  Data: TBytes;
  Err: TVfsError;
  FromMem, ToMem: Boolean;
  FromPath, ToPath: string;
begin
  Err := TVfsError.Ok;
  FromMem := UriSchemeOf(AFromURI) <> 'file';
  ToMem := UriSchemeOf(AToURI) <> 'file';
  if FailCopy then
    Err := TVfsError.Make(vecIOError, 'stub copy failure', AFromURI)
  else if FromMem and not ToMem then
  begin
    TMonitor.Enter(Items);
    try
      if not Items.TryGetValue(AFromURI, Data) then
        Err := TVfsError.Make(vecNotFound, 'Not found', AFromURI);
    finally
      TMonitor.Exit(Items);
    end;
    if Err.Code = vecOk then
    begin
      ToPath := FileUriToPath(AToURI);
      TDirectory.CreateDirectory(TPath.GetDirectoryName(ToPath));
      TFile.WriteAllBytes(ToPath, Data);
    end;
  end
  else if ToMem and not FromMem then
  begin
    FromPath := FileUriToPath(AFromURI);
    if not TFile.Exists(FromPath) then
      Err := TVfsError.Make(vecNotFound, 'Not found', AFromURI)
    else
    begin
      Data := TFile.ReadAllBytes(FromPath);
      TMonitor.Enter(Items);
      try
        Items.AddOrSetValue(AToURI, Data);
      finally
        TMonitor.Exit(Items);
      end;
    end;
  end
  else
    Err := TVfsError.Make(vecNotSupported, 'stub does not copy between plugins', AFromURI);
  TThread.Queue(nil,
    procedure
    begin
      AOnDone(Err.Code = vecOk, Err);
    end);
end;

procedure TMemVfs.MoveAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback; AOverwrite: Boolean;
  APreserveTimestamps: Boolean);
begin
  TThread.Queue(nil,
    procedure
    begin
      AOnDone(False, TVfsError.Make(vecNotSupported, 'stub has no move', AFromURI));
    end);
end;

procedure TMemVfs.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
begin
  TThread.Queue(nil,
    procedure
    begin
      AOnDone('', tfeUtf8, TVfsError.Make(vecNotSupported, 'stub', AURI));
    end);
end;

procedure TMemVfs.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
begin
  TThread.Queue(nil,
    procedure
    begin
      AOnDone(nil, TVfsError.Make(vecNotSupported, 'stub', AURI));
    end);
end;

procedure TMemVfs.WriteTextAsync(const AURI, AText: string; AEncoding: TTextFileEncoding;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  TThread.Queue(nil,
    procedure
    begin
      AOnDone(False, TVfsError.Make(vecNotSupported, 'stub', AURI));
    end);
end;

procedure TMemVfs.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
var
  Found: Boolean;
begin
  TMonitor.Enter(Items);
  try
    Found := Items.ContainsKey(AURI);
  finally
    TMonitor.Exit(Items);
  end;
  TThread.Queue(nil,
    procedure
    begin
      AOnDone(Found, False, TVfsError.Ok);
    end);
end;

procedure TMemVfs.GetFreeSpaceAsync(const ARootURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsFreeSpaceCallback);
begin
  TThread.Queue(nil,
    procedure
    begin
      AOnDone(-1, -1, TVfsError.Make(vecNotSupported, 'stub', ARootURI));
    end);
end;

var
  GPlugA, GPlugB: TMemVfs;
  GRefA, GRefB: IVirtualFileSystem;
  GVfs: IVirtualFileSystem;

procedure Pump(const AFlag: PBoolean);
var
  I: Integer;
begin
  for I := 1 to 1500 do
  begin
    CheckSynchronize(10);
    if AFlag^ then
      Exit;
  end;
end;

function Bytes(const AText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AText);
end;

procedure TTestPluginTransfers.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'mtn2-plugtrans-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  GPlugA := TMemVfs.Create;
  GPlugB := TMemVfs.Create;
  GRefA := GPlugA;
  GRefB := GPlugB;
  GlobalVfsRegistry.RegisterPluginScheme('t.plugA', 'xmema', GRefA, 70);
  GlobalVfsRegistry.RegisterPluginScheme('t.plugB', 'xmemb', GRefB, 70);
  GVfs := CreateDefaultVfs;
end;

procedure TTestPluginTransfers.TearDown;
begin
  GlobalVfsRegistry.UnregisterPlugin('t.plugA');
  GlobalVfsRegistry.UnregisterPlugin('t.plugB');
  GVfs := nil;
  GRefA := nil;
  GRefB := nil;
  GPlugA := nil;
  GPlugB := nil;
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TTestPluginTransfers.TestCopyLocalFileToPlugin;
var
  Done, Ok: Boolean;
  Src: string;
begin
  Src := TPath.Combine(FRoot, 'a.txt');
  TFile.WriteAllBytes(Src, Bytes('hello'));
  Done := False;
  GVfs.CopyAsync(PathToFileUri(Src), 'xmema://h/a.txt', nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Ok := ASuccess;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done and Ok, 'copied');
  Assert.IsTrue(GPlugA.Items.ContainsKey('xmema://h/a.txt'), 'the plugin has the item');
  Assert.IsTrue(TFile.Exists(Src), 'a copy keeps the source');
end;

procedure TTestPluginTransfers.TestMoveLocalFileToPluginDeletesTheSource;
var
  Done, Ok: Boolean;
  Src: string;
begin
  Src := TPath.Combine(FRoot, 'a.txt');
  TFile.WriteAllBytes(Src, Bytes('hello'));
  Done := False;
  GVfs.MoveAsync(PathToFileUri(Src), 'xmema://h/a.txt', nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Ok := ASuccess;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done and Ok, 'moved');
  Assert.IsTrue(GPlugA.Items.ContainsKey('xmema://h/a.txt'), 'the plugin has the item');
  Assert.IsFalse(TFile.Exists(Src), 'the source is gone');
end;

procedure TTestPluginTransfers.TestMovePluginFileToLocalDeletesTheSource;
var
  Done, Ok: Boolean;
  Dest: string;
begin
  GPlugA.Items.Add('xmema://h/b.txt', Bytes('payload'));
  Dest := TPath.Combine(FRoot, 'b.txt');
  Done := False;
  GVfs.MoveAsync('xmema://h/b.txt', PathToFileUri(Dest), nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Ok := ASuccess;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done and Ok, 'moved');
  Assert.IsTrue(TFile.Exists(Dest), 'the file arrived');
  Assert.AreEqual('payload', TEncoding.UTF8.GetString(TFile.ReadAllBytes(Dest)));
  Assert.IsFalse(GPlugA.Items.ContainsKey('xmema://h/b.txt'), 'the item left the plugin');
end;

procedure TTestPluginTransfers.TestCopyBetweenTwoPluginsGoesThroughATempFolder;
var
  Done, Ok: Boolean;
  Got: TBytes;
begin
  GPlugA.Items.Add('xmema://h/c.txt', Bytes('between'));
  Done := False;
  GVfs.CopyAsync('xmema://h/c.txt', 'xmemb://s/c.txt', nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Ok := ASuccess;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done and Ok, 'copied');
  Assert.IsTrue(GPlugB.Items.TryGetValue('xmemb://s/c.txt', Got), 'the second plugin has it');
  Assert.AreEqual('between', TEncoding.UTF8.GetString(Got));
  Assert.IsTrue(GPlugA.Items.ContainsKey('xmema://h/c.txt'), 'a copy keeps the source');
end;

procedure TTestPluginTransfers.TestMoveBetweenTwoPluginsDeletesTheSource;
var
  Done, Ok: Boolean;
begin
  GPlugA.Items.Add('xmema://h/d.txt', Bytes('moving'));
  Done := False;
  GVfs.MoveAsync('xmema://h/d.txt', 'xmemb://s/d.txt', nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Ok := ASuccess;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done and Ok, 'moved');
  Assert.IsTrue(GPlugB.Items.ContainsKey('xmemb://s/d.txt'), 'arrived');
  Assert.IsFalse(GPlugA.Items.ContainsKey('xmema://h/d.txt'), 'source deleted');
end;

procedure TTestPluginTransfers.TestFailedFirstHopLeavesSourceAndReportsTheError;
var
  Done, Ok: Boolean;
  Err: TVfsError;
begin
  GPlugA.Items.Add('xmema://h/e.txt', Bytes('x'));
  GPlugA.FailCopy := True;
  Done := False;
  Ok := True;
  GVfs.MoveAsync('xmema://h/e.txt', 'xmemb://s/e.txt', nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Ok := ASuccess;
      Err := AError;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done and (not Ok), 'the move failed');
  Assert.AreEqual('stub copy failure', Err.Message);
  Assert.IsTrue(GPlugA.Items.ContainsKey('xmema://h/e.txt'), 'the source stays');
  Assert.IsFalse(GPlugB.Items.ContainsKey('xmemb://s/e.txt'), 'nothing arrived');
end;

procedure TTestPluginTransfers.TestFailedCopyDoesNotDeleteTheMovedSource;
var
  Done, Ok: Boolean;
  Src: string;
begin
  Src := TPath.Combine(FRoot, 'f.txt');
  TFile.WriteAllBytes(Src, Bytes('keep'));
  GPlugA.FailCopy := True;
  Done := False;
  Ok := True;
  GVfs.MoveAsync(PathToFileUri(Src), 'xmema://h/f.txt', nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Ok := ASuccess;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done and (not Ok), 'the move failed');
  Assert.IsTrue(TFile.Exists(Src), 'the local source is untouched');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPluginTransfers);

end.
