unit TestPluginSdk;

{ The helpers shared by the native plugins, driven through a fake host table. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginSdk = class
  public
    [TearDown] procedure TearDown;
    [Test] procedure TestSelectedRowsAreVisitedInListOrder;
    [Test] procedure TestCursorRowIsUsedWithoutSelection;
    [Test] procedure TestUnreadablePanelFails;
    [Test] procedure TestDetachWaitsForWorkers;
    [Test] procedure TestWorkerExceptionStaysInTheThread;
    [Test] procedure TestPostToMainStopsAfterDetach;
    [Test] procedure TestTextCallsFallBackWithoutHost;
    [Test] procedure TestDialogDeclarationHasTheControls;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.SyncObjs, uPluginHostAbi, uPluginSdk;

var
  GInfoJson, GListJson: UTF8String;
  GPosted: Integer;

function CopyOut(const AText: UTF8String; ABuf: PAnsiChar; ABufSize: Int64): Int64;
begin
  Result := Length(AText);
  if (ABuf <> nil) and (ABufSize > Result) then
    Move(PAnsiChar(AText)^, ABuf^, Result + 1);
end;

function FakePanelInfo(ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
begin
  Result := CopyOut(GInfoJson, ABuf, ABufSize);
end;

function FakePanelList(ASide: Int64; ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
begin
  Result := CopyOut(GListJson, ABuf, ABufSize);
end;

function FakePostToMain(APluginId: PAnsiChar; ACallback: THostMainCallback;
  AUserData: Pointer): Int64; cdecl;
begin
  Inc(GPosted);
  Result := 0;
end;

procedure Attach;
var
  Api: THostApiTable;
begin
  FillChar(Api, SizeOf(Api), 0);
  Api.PanelInfo := FakePanelInfo;
  Api.PanelList := FakePanelList;
  Api.PostToMain := FakePostToMain;
  SdkAttach(@Api, 't.sdk');
end;

procedure MainCallback(AUserData: Pointer); cdecl;
begin
end;

procedure TTestPluginSdk.TearDown;
begin
  SdkDetach;
  GPosted := 0;
end;

procedure TTestPluginSdk.TestSelectedRowsAreVisitedInListOrder;
var
  Dir, Names: string;
begin
  GListJson := '{"uri":"file:///C:/d","cursor":0,"rows":[{"uri":"file:///C:/d/a","name":"a"},' +
    '{"uri":"file:///C:/d/b","name":"b"},{"uri":"file:///C:/d/c","name":"c"}]}';
  GInfoJson := '{"active":"left","left":{"selected":["file:///C:/d/c","file:///C:/d/a"]}}';
  Attach;
  Names := '';
  Assert.IsTrue(ForEachSelectedRow(Dir,
    procedure(ARow: TJSONObject) begin Names := Names + ARow.GetValue<string>('name'); end));
  Assert.AreEqual('file:///C:/d', Dir);
  Assert.AreEqual('ac', Names, 'list order, not selection order');
end;

procedure TTestPluginSdk.TestCursorRowIsUsedWithoutSelection;
var
  Dir, Names: string;
begin
  GListJson := '{"uri":"file:///C:/d","cursor":1,"rows":[{"uri":"u1","name":"a"},{"uri":"u2","name":"b"}]}';
  GInfoJson := '{"active":"left","left":{"selected":[]}}';
  Attach;
  Names := '';
  Assert.IsTrue(ForEachSelectedRow(Dir,
    procedure(ARow: TJSONObject) begin Names := Names + ARow.GetValue<string>('name'); end));
  Assert.AreEqual('b', Names);
end;

procedure TTestPluginSdk.TestUnreadablePanelFails;
var
  Dir: string;
begin
  GListJson := '';
  GInfoJson := '';
  Attach;
  Assert.IsFalse(ForEachSelectedRow(Dir, procedure(ARow: TJSONObject) begin end));
end;

procedure TTestPluginSdk.TestDetachWaitsForWorkers;
var
  Done: Boolean;
begin
  Attach;
  Done := False;
  SdkRunWorker(procedure begin Sleep(150); Done := True; end);
  SdkDetach;
  Assert.IsTrue(Done, 'detach returns after the worker ended');
end;

procedure TTestPluginSdk.TestWorkerExceptionStaysInTheThread;
var
  Ran: Boolean;
begin
  Attach;
  Ran := False;
  SdkRunWorker(procedure begin Ran := True; raise Exception.Create('boom'); end);
  SdkDetach;
  Assert.IsTrue(Ran);
end;

procedure TTestPluginSdk.TestPostToMainStopsAfterDetach;
begin
  Attach;
  Assert.IsTrue(SdkPostToMain(MainCallback), 'posted while attached');
  Assert.AreEqual(1, GPosted);
  SdkDetach;
  Assert.IsFalse(SdkPostToMain(MainCallback), 'dropped after detach');
  Assert.AreEqual(1, GPosted);
end;

procedure TTestPluginSdk.TestTextCallsFallBackWithoutHost;
begin
  Attach;
  Assert.AreEqual('dflt', Tr('k', 'dflt'), 'no Translate in the host');
  Assert.AreEqual('', GetSettingText('k'));
  Notice('x', 0);
end;

procedure TTestPluginSdk.TestDialogDeclarationHasTheControls;
var
  Decl: TJSONObject;
  Children: TJSONArray;
begin
  Decl := NewDialog('T', 40, 5, Children);
  try
    AddItem(Children, 'label', '', 'hello', 1, 1, 10);
    AddField(Children, 'f', 'v', 1, 2, 20);
    AddCheck(Children, 'c', 'chk', True, 1, 3, 20);
    Assert.AreEqual('T', Decl.GetValue<string>('title'));
    Assert.AreEqual(3, Children.Count);
    Assert.AreEqual('input', (Children.Items[1] as TJSONObject).GetValue<string>('type'));
    Assert.IsTrue((Children.Items[2] as TJSONObject).GetValue<Boolean>('checked'));
  finally
    Decl.Free;
  end;
end;

end.
