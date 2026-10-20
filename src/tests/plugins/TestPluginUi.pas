unit TestPluginUi;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginUi = class
  public
    [Test] procedure TestNoHostShowsNothing;
    [Test] procedure TestInvalidDeclarationIsRefused;
    [Test] procedure TestAnswerReachesThePluginOnce;
    [Test] procedure TestHostThatCannotShowReportsFailure;
    [Test] procedure TestUnloadedPluginGetsNoAnswer;
    [Test] procedure TestFaultyCallbackIsContained;
    [Test] procedure TestDialogLoadsFromPluginFolderByName;
    [Test] procedure TestLongLabelWidensAndAlignsPluginDialog;
    [Test] procedure TestProtocolOneDialogKeepsAuthoredLayout;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uDialogTypes,
  uPluginUi;

const
  cDialogJson =
    '{"type":"dialog","title":"Ask","children":[' +
    '{"type":"input","id":"name","value":"x"},' +
    '{"type":"button","id":"ok","text":"OK","default":true}]}';

  cWideJson =
    '{"version":"2.0","type":"dialog","title":"Ask","width":40,"height":8,"children":[' +
    '{"type":"label","id":"lbl_a","text":"A rather long caption:","col":1,"row":0,"width":8},' +
    '{"type":"input","id":"a","value":"","col":10,"row":0,"width":27},' +
    '{"type":"label","id":"lbl_b","text":"Size:","col":1,"row":1,"width":8},' +
    '{"type":"input","id":"b","value":"","col":10,"row":1,"width":27}]}';
  cV1Json =
    '{"type":"dialog","title":"Ask","width":40,"height":8,"children":[' +
    '{"type":"label","id":"lbl_a","text":"A rather long caption:","col":1,"row":0,"width":8},' +
    '{"type":"input","id":"a","value":"","col":10,"row":0,"width":27}]}';

var
  GPending: TProc<string, string>;
  GShown: Integer;
  GTitle: string;
  GShownDecl: TDialogDeclaration;

function ColOf(const ADecl: TDialogDeclaration; const AId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ADecl.Controls) do
    if ADecl.Controls[I].Id = AId then
      Exit(ADecl.Controls[I].Col);
  Result := -1;
end;

procedure InstallHost(ACanShow: Boolean);
begin
  GPending := nil;
  GShown := 0;
  GTitle := '';
  SetPluginDialogHost(
    function(const ADecl: TDialogDeclaration; const AOnCommand: TProc<string, string>): Boolean
    begin
      Result := ACanShow;
      if Result then
      begin
        Inc(GShown);
        GTitle := ADecl.Title;
        GShownDecl := ADecl;
        GPending := AOnCommand;
      end;
    end);
end;

procedure TestNoHostShowsNothing;
begin
  SetPluginDialogHost(nil);
  Assert.IsTrue(not PluginShowDialog('t.ui', cDialogJson,
    procedure(const AControlId, AValuesJson: string) begin end), 'no host window');
end;

procedure TestInvalidDeclarationIsRefused;
var
  Cb: TPluginDialogCallback;
begin
  InstallHost(True);
  try
    Cb := procedure(const AControlId, AValuesJson: string) begin end;
    Assert.IsTrue(not PluginShowDialog('t.ui', '', Cb), 'empty JSON');
    Assert.IsTrue(not PluginShowDialog('t.ui', 'not json', Cb), 'invalid JSON');
    Assert.IsTrue(not PluginShowDialog('', cDialogJson, Cb), 'no plugin id');
    Assert.IsTrue(not PluginShowDialog('t.ui', cDialogJson, nil), 'no callback');
    Assert.IsTrue(not PluginShowDialog('t.ui', StringOfChar(' ', 300000) + cDialogJson, Cb),
      'oversized declaration');
    Assert.IsTrue(GShown = 0, 'the host was never asked');
  finally
    SetPluginDialogHost(nil);
  end;
end;

procedure TestAnswerReachesThePluginOnce;
var
  Calls: Integer;
  Id, Values: string;
begin
  Calls := 0;
  InstallHost(True);
  try
    Assert.IsTrue(PluginShowDialog('t.ui', cDialogJson,
      procedure(const AControlId, AValuesJson: string)
      begin
        Inc(Calls);
        Id := AControlId;
        Values := AValuesJson;
      end), 'dialog shown');
    Assert.IsTrue(GTitle = 'Ask', 'the host got the parsed declaration');
    Assert.IsTrue(Calls = 0, 'no answer before the user acts');
    GPending('ok', '{"name":"x"}');
    Assert.IsTrue((Calls = 1) and (Id = 'ok') and (Values = '{"name":"x"}'),
      'control id and values come back');
    GPending('ok', '{"name":"y"}');
    Assert.IsTrue(Calls = 1, 'one dialog, one answer');
  finally
    SetPluginDialogHost(nil);
  end;
end;

procedure TestHostThatCannotShowReportsFailure;
begin
  InstallHost(False);
  try
    Assert.IsTrue(not PluginShowDialog('t.ui', cDialogJson,
      procedure(const AControlId, AValuesJson: string) begin end),
      'another dialog is open / not over the panels');
  finally
    SetPluginDialogHost(nil);
  end;
end;

procedure TestUnloadedPluginGetsNoAnswer;
var
  Calls: Integer;
begin
  Calls := 0;
  InstallHost(True);
  try
    PluginShowDialog('t.gone', cDialogJson,
      procedure(const AControlId, AValuesJson: string) begin Inc(Calls); end);
    PluginShowDialog('t.stays', cDialogJson,
      procedure(const AControlId, AValuesJson: string) begin Inc(Calls, 10); end);
    PluginUiUnregister('T.GONE');
    GPending('ok', '{}');
    Assert.IsTrue(Calls = 10, 'only the plugin that is still loaded is called');
  finally
    SetPluginDialogHost(nil);
  end;
end;

procedure TestFaultyCallbackIsContained;
begin
  InstallHost(True);
  try
    PluginShowDialog('t.ui', cDialogJson,
      procedure(const AControlId, AValuesJson: string)
      begin
        raise Exception.Create('plugin failure');
      end);
    GPending('ok', '{}');
    Assert.IsTrue(True, 'the host flow survives a callback that raises');
  finally
    SetPluginDialogHost(nil);
  end;
end;

{ TTestPluginUi }

procedure TTestPluginUi.TestNoHostShowsNothing;
begin
  TestPluginUi.TestNoHostShowsNothing;
end;

procedure TestDialogLoadsFromPluginFolderByName;
var
  Dir: string;
  Noop: TPluginDialogCallback;
begin
  Noop := procedure(const AControlId, AValuesJson: string) begin end;
  Dir := TPath.Combine(TPath.Combine(TPath.Combine(
    ExtractFilePath(ParamStr(0)), 'plugins'), 't.ui.file'), 'dialogs');
  TDirectory.CreateDirectory(Dir);
  InstallHost(True);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'ask.json'), cDialogJson, TEncoding.UTF8);
    Assert.IsTrue(PluginShowDialog('t.ui.file', 'ask', Noop), 'named file shown');
    Assert.AreEqual('Ask', GTitle);
    Assert.IsTrue(not PluginShowDialog('t.ui.file', 'missing', Noop), 'missing file');
    Assert.IsTrue(not PluginShowDialog('t.ui.file', '..sk', Noop), 'path escape refused');
    Assert.IsTrue(not PluginShowDialog('t.ui.other', 'ask', Noop),
      'another plugin cannot read the file');
  finally
    SetPluginDialogHost(nil);
    TDirectory.Delete(TPath.GetDirectoryName(Dir), True);
  end;
end;

procedure TestLongLabelWidensAndAlignsPluginDialog;
begin
  InstallHost(True);
  try
    Assert.IsTrue(PluginShowDialog('t.ui', cWideJson,
      procedure(const AControlId, AValuesJson: string) begin end), 'dialog shown');
    Assert.AreEqual(1 + Length('A rather long caption:') + 1, ColOf(GShownDecl, 'a'),
      'the field moved past the longer caption');
    Assert.AreEqual(ColOf(GShownDecl, 'a'), ColOf(GShownDecl, 'b'),
      'fields of one label column stay aligned');
  finally
    SetPluginDialogHost(nil);
  end;
end;

procedure TestProtocolOneDialogKeepsAuthoredLayout;
begin
  InstallHost(True);
  try
    Assert.IsTrue(PluginShowDialog('t.ui', cV1Json,
      procedure(const AControlId, AValuesJson: string) begin end), 'dialog shown');
    Assert.AreEqual(10, ColOf(GShownDecl, 'a'), 'protocol 1 is shown as authored');
    Assert.AreEqual(40, GShownDecl.Width, 'width untouched');
  finally
    SetPluginDialogHost(nil);
  end;
end;

procedure TTestPluginUi.TestLongLabelWidensAndAlignsPluginDialog;
begin
  TestPluginUi.TestLongLabelWidensAndAlignsPluginDialog;
end;

procedure TTestPluginUi.TestProtocolOneDialogKeepsAuthoredLayout;
begin
  TestPluginUi.TestProtocolOneDialogKeepsAuthoredLayout;
end;

procedure TTestPluginUi.TestInvalidDeclarationIsRefused;
begin
  TestPluginUi.TestInvalidDeclarationIsRefused;
end;

procedure TTestPluginUi.TestAnswerReachesThePluginOnce;
begin
  TestPluginUi.TestAnswerReachesThePluginOnce;
end;

procedure TTestPluginUi.TestHostThatCannotShowReportsFailure;
begin
  TestPluginUi.TestHostThatCannotShowReportsFailure;
end;

procedure TTestPluginUi.TestUnloadedPluginGetsNoAnswer;
begin
  TestPluginUi.TestUnloadedPluginGetsNoAnswer;
end;

procedure TTestPluginUi.TestFaultyCallbackIsContained;
begin
  TestPluginUi.TestFaultyCallbackIsContained;
end;

procedure TTestPluginUi.TestDialogLoadsFromPluginFolderByName;
begin
  TestPluginUi.TestDialogLoadsFromPluginFolderByName;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPluginUi);

end.
