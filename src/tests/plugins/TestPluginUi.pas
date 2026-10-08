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

var
  GPending: TProc<string, string>;
  GShown: Integer;
  GTitle: string;

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
