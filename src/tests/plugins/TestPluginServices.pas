unit TestPluginServices;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginServices = class
  public
    [TearDown] procedure TearDown;
    [Test] procedure TestWithoutAWindowEveryServiceFails;
    [Test] procedure TestServicesReachTheWindow;
    [Test] procedure TestArgumentsAreChecked;
    [Test] procedure TestEventsReachSubscribers;
    [Test] procedure TestSubscriptionIsReplacedPerTopic;
    [Test] procedure TestUnloadedPluginHearsNothing;
    [Test] procedure TestFaultyHandlerDoesNotStopTheOthers;
    [Test] procedure TestHostInfoNamesTheVersion;
    [Test] procedure TestPanelServicesReachTheWindow;
    [Test] procedure TestPanelArgumentsAreChecked;
    [Test] procedure TestDocSelectionAndLineReachTheWindow;
    [Test] procedure TestPostedWorkRunsOnTheMainThread;
    [Test] procedure TestPostedWorkOfAnUnloadedPluginIsDropped;
    [Test] procedure TestProgressStaysUntilEnded;
  end;

implementation

uses
  System.SysUtils, System.Classes, uPluginServices, uNotice;

procedure TTestPluginServices.TearDown;
begin
  SetPluginHostServices(Default(TPluginHostServices));
  PluginEventsUnregister('t.one');
  PluginEventsUnregister('t.two');
end;

procedure TTestPluginServices.TestWithoutAWindowEveryServiceFails;
var
  S: string;
begin
  SetPluginHostServices(Default(TPluginHostServices));
  Assert.IsFalse(PluginDocInfo(S), 'doc info');
  Assert.IsFalse(PluginDocGetText(1, S), 'doc text');
  Assert.IsFalse(PluginDocReplace(1, 'x'), 'doc replace');
  Assert.IsFalse(PluginDocSetCursor(0, 0), 'doc cursor');
  Assert.IsFalse(PluginPanelInfo(S), 'panel info');
  Assert.IsFalse(PluginPanelGoto(0, 'file:///C:/'), 'panel goto');
  Assert.IsFalse(PluginPanelRefresh, 'panel refresh');
end;

procedure TTestPluginServices.TestServicesReachTheWindow;
var
  Svc: TPluginHostServices;
  Text, Json: string;
  Replaced, Side, Row, Col, Refreshed: Integer;
  Uri: string;
begin
  Svc := Default(TPluginHostServices);
  Svc.DocInfo := function: string begin Result := '{"row":3}'; end;
  Svc.DocGetText :=
    function(AWhat: Integer; out AText: string): Boolean
    begin
      AText := 'text' + IntToStr(AWhat);
      Result := True;
    end;
  Svc.DocReplace :=
    function(AWhat: Integer; const AText: string): Boolean
    begin
      Inc(Replaced);
      Text := AText;
      Result := True;
    end;
  Svc.DocSetCursor :=
    function(ARow, ACol: Integer): Boolean
    begin
      Row := ARow;
      Col := ACol;
      Result := True;
    end;
  Svc.PanelInfo := function: string begin Result := '{"active":"left"}'; end;
  Svc.PanelGoto :=
    function(ASide: Integer; const AURI: string): Boolean
    begin
      Side := ASide;
      Uri := AURI;
      Result := True;
    end;
  Svc.PanelRefresh := procedure begin Inc(Refreshed); end;
  SetPluginHostServices(Svc);
  Replaced := 0;
  Refreshed := 0;
  Assert.IsTrue(PluginDocInfo(Json) and (Json = '{"row":3}'), 'info');
  Assert.IsTrue(PluginDocGetText(2, Text) and (Text = 'text2'), 'text of kind 2');
  Assert.IsTrue(PluginDocReplace(1, 'new') and (Text = 'new') and (Replaced = 1), 'replace');
  Assert.IsTrue(PluginDocSetCursor(4, 5) and (Row = 4) and (Col = 5), 'cursor');
  Assert.IsTrue(PluginPanelInfo(Json) and (Json = '{"active":"left"}'), 'panel info');
  Assert.IsTrue(PluginPanelGoto(-1, 'file:///C:/x') and (Side = -1) and (Uri = 'file:///C:/x'), 'goto');
  Assert.IsTrue(PluginPanelRefresh and (Refreshed = 1), 'refresh');
end;

procedure TTestPluginServices.TestArgumentsAreChecked;
var
  Svc: TPluginHostServices;
  Calls: Integer;
  Text: string;
begin
  Svc := Default(TPluginHostServices);
  Svc.DocGetText := function(AWhat: Integer; out AText: string): Boolean begin Inc(Calls); AText := ''; Result := True; end;
  Svc.DocReplace := function(AWhat: Integer; const AText: string): Boolean begin Inc(Calls); Result := True; end;
  Svc.PanelGoto := function(ASide: Integer; const AURI: string): Boolean begin Inc(Calls); Result := True; end;
  SetPluginHostServices(Svc);
  Calls := 0;
  Assert.IsFalse(PluginDocGetText(3, Text), 'unknown kind of text');
  Assert.IsFalse(PluginDocGetText(-1, Text), 'negative kind');
  Assert.IsFalse(PluginDocReplace(9, 'x'), 'unknown kind of replacement');
  Assert.IsFalse(PluginPanelGoto(2, 'file:///C:/'), 'unknown side');
  Assert.IsFalse(PluginPanelGoto(0, ''), 'empty URI');
  Assert.AreEqual(0, Calls, 'the window is not bothered with bad calls');
end;

procedure TTestPluginServices.TestEventsReachSubscribers;
var
  Log: string;
begin
  Log := '';
  PluginSubscribe('t.one', 'doc.saved',
    procedure(const ATopic, APayload: string) begin Log := Log + 'one:' + ATopic + ':' + APayload + ';'; end);
  PluginSubscribe('T.Two', '*',
    procedure(const ATopic, APayload: string) begin Log := Log + 'two:' + ATopic + ';'; end);
  PluginPublishEvent('doc.saved', PluginUriPayload('file:///C:/a.txt'));
  PluginPublishEvent('doc.closed', '{}');
  Assert.AreEqual('one:doc.saved:{"uri":"file:///C:/a.txt"};two:doc.saved;two:doc.closed;', Log);
end;

procedure TTestPluginServices.TestSubscriptionIsReplacedPerTopic;
var
  Log: string;
begin
  Log := '';
  PluginSubscribe('t.one', 'doc.saved', procedure(const ATopic, APayload: string) begin Log := Log + 'old;'; end);
  PluginSubscribe('t.one', 'DOC.SAVED', procedure(const ATopic, APayload: string) begin Log := Log + 'new;'; end);
  PluginPublishEvent('doc.saved', '{}');
  Assert.AreEqual('new;', Log, 'the second handler replaces the first');
end;

procedure TTestPluginServices.TestUnloadedPluginHearsNothing;
var
  Calls: Integer;
begin
  Calls := 0;
  PluginSubscribe('t.one', '*', procedure(const ATopic, APayload: string) begin Inc(Calls); end);
  PluginEventsUnregister('T.ONE');
  PluginPublishEvent('doc.opened', '{}');
  Assert.AreEqual(0, Calls);
end;

procedure TTestPluginServices.TestFaultyHandlerDoesNotStopTheOthers;
var
  Calls: Integer;
begin
  Calls := 0;
  PluginSubscribe('t.one', '*', procedure(const ATopic, APayload: string) begin raise Exception.Create('boom'); end);
  PluginSubscribe('t.two', '*', procedure(const ATopic, APayload: string) begin Inc(Calls); end);
  PluginPublishEvent('doc.opened', '{}');
  Assert.AreEqual(1, Calls, 'the other plugin still hears the event');
end;

procedure TTestPluginServices.TestPanelServicesReachTheWindow;
var
  Svc: TPluginHostServices;
  Json, Uri, Arg: string;
  Side, Mode: Integer;
begin
  Svc := Default(TPluginHostServices);
  Svc.PanelList := function(ASide: Integer): string begin Side := ASide; Result := '{"rows":[]}'; end;
  Svc.PanelSetCursor :=
    function(ASide: Integer; const AURI: string): Boolean
    begin
      Side := ASide;
      Uri := AURI;
      Result := True;
    end;
  Svc.PanelSelect :=
    function(ASide, AMode: Integer; const AArg: string): Boolean
    begin
      Side := ASide;
      Mode := AMode;
      Arg := AArg;
      Result := True;
    end;
  SetPluginHostServices(Svc);
  Assert.IsTrue(PluginPanelList(1, Json) and (Json = '{"rows":[]}') and (Side = 1), 'list of the right panel');
  Assert.IsTrue(PluginPanelSetCursor(0, 'file:///C:/a.txt') and (Uri = 'file:///C:/a.txt') and (Side = 0), 'cursor');
  Assert.IsTrue(PluginPanelSelect(-1, 0, '*.txt') and (Mode = 0) and (Arg = '*.txt') and (Side = -1), 'select by mask');
  Assert.IsTrue(PluginPanelSelect(-1, 2, ''), 'clearing needs no argument');
end;

procedure TTestPluginServices.TestPanelArgumentsAreChecked;
var
  Svc: TPluginHostServices;
  Calls: Integer;
  Json: string;
begin
  Calls := 0;
  Svc := Default(TPluginHostServices);
  Svc.PanelList := function(ASide: Integer): string begin Inc(Calls); Result := 'x'; end;
  Svc.PanelSetCursor := function(ASide: Integer; const AURI: string): Boolean begin Inc(Calls); Result := True; end;
  Svc.PanelSelect := function(ASide, AMode: Integer; const AArg: string): Boolean begin Inc(Calls); Result := True; end;
  SetPluginHostServices(Svc);
  Assert.IsFalse(PluginPanelList(2, Json), 'unknown side');
  Assert.IsFalse(PluginPanelSetCursor(0, ''), 'empty URI');
  Assert.IsFalse(PluginPanelSetCursor(5, 'file:///C:/a'), 'unknown side');
  Assert.IsFalse(PluginPanelSelect(0, 5, 'x'), 'unknown mode');
  Assert.IsFalse(PluginPanelSelect(0, 0, ''), 'a mask is needed');
  Assert.AreEqual(0, Calls, 'the window is not bothered with bad calls');
end;

procedure TTestPluginServices.TestDocSelectionAndLineReachTheWindow;
var
  Svc: TPluginHostServices;
  R1, C2: Integer;
  Text: string;
begin
  Svc := Default(TPluginHostServices);
  Svc.DocSetSelection :=
    function(ARow1, ACol1, ARow2, ACol2: Integer): Boolean
    begin
      R1 := ARow1;
      C2 := ACol2;
      Result := True;
    end;
  Svc.DocLine := function(AIndex: Integer; out AText: string): Boolean begin AText := 'line' + IntToStr(AIndex); Result := True; end;
  SetPluginHostServices(Svc);
  Assert.IsTrue(PluginDocSetSelection(1, 2, 3, 4) and (R1 = 1) and (C2 = 4), 'selection');
  Assert.IsTrue(PluginDocLine(7, Text) and (Text = 'line7'), 'line');
  Assert.IsFalse(PluginDocLine(-1, Text), 'a negative index');
end;

procedure TTestPluginServices.TestPostedWorkRunsOnTheMainThread;
var
  Ran: Boolean;
  Worker: TThread;
  RanOnMain: Boolean;
begin
  Ran := False;
  RanOnMain := False;
  Worker := TThread.CreateAnonymousThread(
    procedure
    begin
      PluginPostToMain('t.one',
        procedure
        begin
          Ran := True;
          RanOnMain := TThread.CurrentThread.ThreadID = MainThreadID;
        end);
    end);
  Worker.FreeOnTerminate := False;
  Worker.Start;
  Worker.WaitFor;
  Worker.Free;
  CheckSynchronize(200);
  Assert.IsTrue(Ran, 'the posted work ran');
  Assert.IsTrue(RanOnMain, 'on the main thread');
end;

procedure TTestPluginServices.TestPostedWorkOfAnUnloadedPluginIsDropped;
var
  Ran: Boolean;
begin
  Ran := False;
  PluginPostToMain('t.one', procedure begin Ran := True; end);
  PluginEventsUnregister('t.one');
  CheckSynchronize(200);
  Assert.IsFalse(Ran, 'work posted before the plugin went is not run after');
  PluginPostToMain('t.one', procedure begin Ran := True; end);
  CheckSynchronize(200);
  Assert.IsTrue(Ran, 'a plugin loaded again can post');
end;

procedure TTestPluginServices.TestProgressStaysUntilEnded;
var
  Shown, Dismissed: string;
  LastKind: TToastKind;
  LastAlways: Boolean;
begin
  SetNoticeHandler(
    procedure(const ARequest: TNoticeRequest)
    begin
      Shown := Shown + ARequest.Arg + '|';
      LastKind := ARequest.Kind;
      LastAlways := ARequest.Always;
      Assert.AreEqual('t.one:job', ARequest.Tag, 'the notice is tagged with the plugin and the job');
    end,
    procedure(const ATag: string)
    begin
      Dismissed := Dismissed + ATag + '|';
    end);
  try
    PluginProgressSet('T.One', 'job', 'Counting', 40);
    PluginProgressSet('T.One', 'job', 'Counting', -1);
    PluginProgressEnd('t.one', 'job');
    Assert.AreEqual('Counting  40%|Counting|', Shown, 'with and without a percentage');
    Assert.AreEqual('t.one:job|', Dismissed, 'ended');
    Assert.IsTrue(LastAlways, 'shown even with notifications off');
  finally
    SetNoticeHandler(nil);
  end;
end;

procedure TTestPluginServices.TestHostInfoNamesTheVersion;
begin
  Assert.IsTrue(Pos('"version"', PluginHostInfoJson) > 0, PluginHostInfoJson);
  Assert.IsTrue(Pos('"language"', PluginHostInfoJson) > 0, 'language');
end;

end.
