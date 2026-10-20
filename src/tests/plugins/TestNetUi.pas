unit TestNetUi;

{ The dialogs of the network plugin (uNetUi) against a stand-in for the host
  table: the questions a worker thread asks, the session editor and the lookup
  of the session under the cursor of the active panel. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNetUi = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestTextsFallBackToTheEnglishDefault;
    [Test] procedure TestActivePanelOnTheSessionListNamesTheCursorSession;
    [Test] procedure TestActivePanelElsewhereIsNotTheSessionList;
    [Test] procedure TestPasswordQuestionReturnsTheTypedSecretAndSaveFlag;
    [Test] procedure TestPasswordQuestionCancelledReturnsFalse;
    [Test] procedure TestHostKeyQuestionShowsTheFingerprintAndNeedsTrust;
    [Test] procedure TestBusyHostIsRetriedUntilTheDialogOpens;
    [Test] procedure TestEditorAddsANewSession;
    [Test] procedure TestTranslatedEditorHasNoOverlappingControls;
    [Test] procedure TestEditorUpdatesAndRenamesASession;
    [Test] procedure TestEditorKeepsOpenOnInvalidInput;
    [Test] procedure TestMoreOptionsReturnToTheMainDialog;
    [Test] procedure TestChangesAreSavedThroughTheHost;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.SyncObjs, System.Math, uPluginHostAbi,
  uDialogTypes, uDialogJson, uDialogLocaleLayout, uNetTypes,
  uNetManager, uNetSessions, uNetSecrets, uNetUi;

type
  TAnswerFn = procedure(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;

var
  GHost: THostApiTable;
  GManager: TNetManager;
  GPanelJson: UTF8String;
  GDialogs: TStringList;
  GAnswer: TAnswerFn;
  GAnswerData: Pointer;
  GScriptControl: string;
  GScriptValues: string;
  GScriptBusy: Integer;
  GRefreshCalls: Integer;
  GMessages: TStringList;
  GSettings: TStringList;
  GStored: string;

function FakePostToMain(APluginId: PAnsiChar; ACallback: THostMainCallback; AUserData: Pointer): Int64; cdecl;
begin
  // The real host runs it on the main thread a moment later; here at once.
  ACallback(AUserData);
  Result := 0;
end;

function FakeShowDialog(APluginId, ADeclJson: PAnsiChar; AOnCommand: THostDialogCommandCallback;
  AUserData: Pointer): Int64; cdecl;
var
  Control, Values: UTF8String;
begin
  GDialogs.Add(string(UTF8String(ADeclJson)));
  if GScriptBusy > 0 then
  begin
    Dec(GScriptBusy);
    Exit(-1);
  end;
  GAnswer := TAnswerFn(AOnCommand);
  GAnswerData := AUserData;
  if GScriptControl <> '' then
  begin
    Control := UTF8String(GScriptControl);
    Values := UTF8String(GScriptValues);
    AOnCommand(AUserData, PAnsiChar(Control), PAnsiChar(Values));
  end;
  Result := 0;
end;

function FakePanelInfo(ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
begin
  Result := Length(GPanelJson);
  if Result < ABufSize then
  begin
    Move(PAnsiChar(GPanelJson)^, ABuf^, Result);
    ABuf[Result] := #0;
  end;
end;

function FakePanelRefresh: Int64; cdecl;
begin
  Inc(GRefreshCalls);
  Result := 0;
end;

function FakeShowMessage(AText: PAnsiChar; AKind: Int64): Int64; cdecl;
begin
  GMessages.Add(string(UTF8String(AText)));
  Result := 0;
end;

function FakeSetSetting(APluginId, AKey, AValue: PAnsiChar): Int64; cdecl;
begin
  GStored := string(UTF8String(AValue));
  GSettings.Add(string(UTF8String(AKey)));
  Result := 0;
end;

function FakeGetSetting(APluginId, AKey: PAnsiChar; ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
begin
  Result := -1;
end;

function FakeTranslate(APluginId, AKey, ADefault: PAnsiChar; ABuf: PAnsiChar;
  ABufSize: Int64): Int64; cdecl;
var
  Key, Text: UTF8String;
begin
  Key := UTF8String(AKey);
  Text := UTF8String(ADefault);
  if Key = 'ui.edit.user' then
    Text := UTF8String('Пользователь / ключ доступа:')
  else if Key = 'ui.edit.secret' then
    Text := UTF8String('Пароль / секретный ключ:')
  else if Key = 'ui.edit.root' then
    Text := UTF8String('Начальная папка:');
  Result := Length(Text);
  if Result < ABufSize then
  begin
    Move(PAnsiChar(Text)^, ABuf^, Result);
    ABuf[Result] := #0;
  end;
end;

procedure TTestNetUi.Setup;
begin
  GDialogs := TStringList.Create;
  GMessages := TStringList.Create;
  GSettings := TStringList.Create;
  GScriptControl := '';
  GScriptValues := '';
  GScriptBusy := 0;
  GRefreshCalls := 0;
  GStored := '';
  GAnswer := nil;
  GAnswerData := nil;
  GPanelJson := '';
  FillChar(GHost, SizeOf(GHost), 0);
  GHost.AbiVersion := cPluginAbiVersion;
  GHost.PostToMain := FakePostToMain;
  GHost.ShowDialog := FakeShowDialog;
  GHost.PanelInfo := FakePanelInfo;
  GHost.PanelRefresh := FakePanelRefresh;
  GHost.ShowMessage := FakeShowMessage;
  GHost.SetSetting := FakeSetSetting;
  GHost.GetSetting := FakeGetSetting;
  GManager := TNetManager.Create;
  NetUiAttach(@GHost, GManager);
end;

procedure TTestNetUi.TearDown;
begin
  NetUiDetach;
  FreeAndNil(GManager);
  FreeAndNil(GDialogs);
  FreeAndNil(GMessages);
  FreeAndNil(GSettings);
end;

procedure TTestNetUi.TestTextsFallBackToTheEnglishDefault;
begin
  // The stand-in host has no Translate: the default text is used.
  Assert.AreEqual('Default text', Tr('ui.unknown', 'Default text'));
end;

procedure TTestNetUi.TestActivePanelOnTheSessionListNamesTheCursorSession;
var
  Name: string;
begin
  GPanelJson := '{"active":"right","left":{"uri":"file:///C:/","cursor":"file:///C:/a"},' +
    '"right":{"uri":"net:///","cursor":"net:///Work%20Box","cursorIsDirectory":true,"selected":[]}}';
  Assert.IsTrue(ActivePanelIsSessionList(Name));
  // The host joins the row name onto net:/// without encoding.
  GPanelJson := '{"active":"right","left":{"uri":"file:///C:/"},' +
    '"right":{"uri":"net:///","cursor":"net:///Work Box","selected":[]}}';
  Assert.IsTrue(ActivePanelIsSessionList(Name));
  Assert.AreEqual('Work Box', Name);
  GPanelJson := '{"active":"left","left":{"uri":"net:///"},"right":{"uri":"net://x/","cursor":"net://x/f"}}';
  Assert.IsTrue(ActivePanelIsSessionList(Name));
  Assert.AreEqual('', Name, 'no row under the cursor');
end;

procedure TTestNetUi.TestActivePanelElsewhereIsNotTheSessionList;
var
  Name: string;
begin
  GPanelJson := '{"active":"left","left":{"uri":"net://Work/dir","cursor":"net://Work/dir/a"},' +
    '"right":{"uri":"net:///"}}';
  Assert.IsFalse(ActivePanelIsSessionList(Name), 'the other panel being the list does not count');
  GPanelJson := '{"active":"left","left":{"uri":"file:///C:/"}}';
  Assert.IsFalse(ActivePanelIsSessionList(Name));
  GPanelJson := 'not json';
  Assert.IsFalse(ActivePanelIsSessionList(Name));
end;

procedure TTestNetUi.TestPasswordQuestionReturnsTheTypedSecretAndSaveFlag;
var
  P: TNetUiPrompter;
  Ref: INetPrompter;
  S: TNetSession;
  Secret: string;
  Save: Boolean;
  Op: TNetOp;
begin
  P := TNetUiPrompter.Create;
  Ref := P;
  S := DefaultNetSession;
  S.Name := 'Box';
  S.Host := 'example.org';
  S.User := 'bob';
  GScriptControl := 'ok';
  GScriptValues := '{"secret":"hunter2","save":true}';
  Op := TNetOp.Create;
  try
    Assert.IsTrue(P.AskSecret(S, False, False, Op, Secret, Save));
    Assert.AreEqual('hunter2', Secret);
    Assert.AreEqual(SecretsAvailable, Save, 'saving is offered only where passwords can be sealed');
    Assert.IsTrue(Pos('bob@example.org', GDialogs[0]) > 0, 'the question names the account');
    Assert.IsTrue(Pos('"password":true', GDialogs[0]) > 0, 'the field hides what is typed');
  finally
    Op.Free;
  end;
end;

procedure TTestNetUi.TestPasswordQuestionCancelledReturnsFalse;
var
  P: TNetUiPrompter;
  Ref: INetPrompter;
  S: TNetSession;
  Secret: string;
  Save: Boolean;
  Op: TNetOp;
begin
  P := TNetUiPrompter.Create;
  Ref := P;
  S := DefaultNetSession;
  S.Host := 'h';
  GScriptControl := 'cancel';
  GScriptValues := '{"secret":"x"}';
  Op := TNetOp.Create;
  try
    Assert.IsFalse(P.AskSecret(S, False, True, Op, Secret, Save));
    Assert.IsTrue(Pos('Login failed', GDialogs[0]) > 0, 'a retry says the last login failed');
  finally
    Op.Free;
  end;
end;

procedure TTestNetUi.TestHostKeyQuestionShowsTheFingerprintAndNeedsTrust;
var
  P: TNetUiPrompter;
  Ref: INetPrompter;
  S: TNetSession;
  Op: TNetOp;
begin
  P := TNetUiPrompter.Create;
  Ref := P;
  S := DefaultNetSession;
  S.Host := 'ssh.example.org';
  Op := TNetOp.Create;
  try
    GScriptControl := 'trust';
    GScriptValues := '{}';
    Assert.IsTrue(P.TrustHostKey(S, 'abcDEF123', False, Op));
    Assert.IsTrue(Pos('SHA256:abcDEF123', GDialogs[0]) > 0, 'the fingerprint is shown');
    GScriptControl := 'cancel';
    Assert.IsFalse(P.TrustHostKey(S, 'abcDEF123', True, Op));
    Assert.IsTrue(Pos('has changed', GDialogs[1]) > 0, 'a changed key is a warning');
  finally
    Op.Free;
  end;
end;

procedure TTestNetUi.TestBusyHostIsRetriedUntilTheDialogOpens;
var
  P: TNetUiPrompter;
  Ref: INetPrompter;
  S: TNetSession;
  Secret: string;
  Save: Boolean;
  Op: TNetOp;
begin
  P := TNetUiPrompter.Create;
  Ref := P;
  S := DefaultNetSession;
  S.Host := 'h';
  GScriptControl := 'ok';
  GScriptValues := '{"secret":"pw"}';
  GScriptBusy := 2;
  Op := TNetOp.Create;
  try
    Assert.IsTrue(P.AskSecret(S, False, False, Op, Secret, Save), 'asked again after the host was busy');
    Assert.AreEqual(3, GDialogs.Count, 'two refusals and the answered one');
  finally
    Op.Free;
  end;
end;

const
  cMainValues =
    '{"name":"Box","protocol":"SFTP (SSH)","host":"h.example","port":"2222","user":"u",' +
    '"auth":"Key file","secret":"","keyfile":"C:\\keys\\id","passphrase":"pp","root":"/home/u","save":true}';

procedure TTestNetUi.TestEditorAddsANewSession;
var
  S: TNetSession;
begin
  EditSession('');
  Assert.IsTrue(GDialogs.Count = 1, 'the editor opened');
  Assert.IsTrue(Pos('New connection', GDialogs[0]) > 0, 'a free default name');
  GAnswer(GAnswerData, 'ok', PAnsiChar(UTF8String(cMainValues)));
  Assert.IsTrue(GManager.FindSession('Box', S), 'the session was added');
  Assert.IsTrue(S.Protocol = npSftp);
  Assert.AreEqual('h.example', S.Host);
  Assert.AreEqual(2222, S.Port);
  Assert.IsTrue(S.Auth = naKey);
  Assert.AreEqual('C:\keys\id', S.KeyFile);
  Assert.AreEqual('pp', S.KeyPassphrase);
  Assert.AreEqual('/home/u', S.RootPath);
  Assert.IsTrue(GRefreshCalls > 0, 'the panel is refreshed');
end;

procedure TTestNetUi.TestTranslatedEditorHasNoOverlappingControls;
var
  Decl: TDialogDeclaration;
  I, J, W: Integer;
begin
  GHost.Translate := FakeTranslate;
  EditSession('');
  Assert.IsTrue(GDialogs.Count = 1, 'the editor opened');
  Assert.IsTrue(TryParseDialogJson(GDialogs[0], Decl), 'the declaration parses');
  FitDialogToTranslatedText(Decl);
  for I := 0 to High(Decl.Controls) do
  begin
    W := Decl.Controls[I].BoxW;
    if Decl.Controls[I].Kind = dckLabel then
      W := Length(Decl.Controls[I].Text);
    Assert.IsTrue(Decl.Controls[I].Col + W <= Decl.Width - 2,
      Decl.Controls[I].Id + ' stays inside the frame');
    for J := I + 1 to High(Decl.Controls) do
      if (Decl.Controls[I].Row = Decl.Controls[J].Row) and
         (Decl.Controls[I].Col < Decl.Controls[J].Col + Max(Decl.Controls[J].BoxW, 1)) and
         (Decl.Controls[J].Col < Decl.Controls[I].Col + Max(W, 1)) then
        Assert.Fail('controls overlap on row ' + IntToStr(Decl.Controls[I].Row) + ': ' +
          Decl.Controls[I].Text + ' / ' + Decl.Controls[J].Text);
  end;
end;

procedure TTestNetUi.TestEditorUpdatesAndRenamesASession;
var
  S: TNetSession;
begin
  S := DefaultNetSession;
  S.Name := 'Old';
  S.Host := 'old.example';
  Assert.IsTrue(GManager.AddSession(S));
  EditSession('Old');
  Assert.IsTrue(Pos('old.example', GDialogs[0]) > 0, 'the editor shows the saved values');
  GAnswer(GAnswerData, 'ok', PAnsiChar(UTF8String(cMainValues)));
  Assert.IsFalse(GManager.FindSession('Old', S), 'the old name is gone');
  Assert.IsTrue(GManager.FindSession('Box', S), 'the session has the new name');
  Assert.AreEqual('h.example', S.Host);
  Assert.IsTrue(GManager.SessionCount = 1);
end;

procedure TTestNetUi.TestEditorKeepsOpenOnInvalidInput;
var
  S: TNetSession;
begin
  EditSession('');
  // No server given: the editor says so and opens again with the typed text.
  GAnswer(GAnswerData, 'ok', PAnsiChar(UTF8String(
    StringReplace(cMainValues, '"host":"h.example"', '"host":""', []))));
  Assert.IsFalse(GManager.FindSession('Box', S));
  Assert.IsTrue(GMessages.Count = 1, 'a message names the problem');
  Assert.IsTrue(GDialogs.Count = 2, 'the editor opened again');
  Assert.IsTrue(Pos('"value":"Box"', GDialogs[1]) > 0, 'the typed name is kept');
  GAnswer(GAnswerData, 'ok', PAnsiChar(UTF8String(cMainValues)));
  Assert.IsTrue(GManager.FindSession('Box', S), 'a corrected form is accepted');
end;

procedure TTestNetUi.TestMoreOptionsReturnToTheMainDialog;
var
  S: TNetSession;
begin
  EditSession('');
  GAnswer(GAnswerData, 'more', PAnsiChar(UTF8String(cMainValues)));
  Assert.IsTrue(GDialogs.Count = 2);
  Assert.IsTrue(Pos('more options', GDialogs[1]) > 0, 'the second dialog opened');
  GAnswer(GAnswerData, 'ok', PAnsiChar(UTF8String(
    '{"passive":false,"implicit":true,"verify":false,"pathstyle":false,"encoding":"windows-1251",' +
    '"proxy":"socks5h://p:1080","timeout":"45","region":"eu-west-1","endpoint":"/dav"}')));
  Assert.IsTrue(GDialogs.Count = 3, 'the main dialog is shown again');
  Assert.IsTrue(Pos('"value":"h.example"', GDialogs[2]) > 0, 'with the values typed before');
  GAnswer(GAnswerData, 'ok', PAnsiChar(UTF8String(cMainValues)));
  Assert.IsTrue(GManager.FindSession('Box', S));
  Assert.IsFalse(S.Passive);
  Assert.IsTrue(S.ImplicitTls);
  Assert.IsFalse(S.VerifyCert);
  Assert.AreEqual('windows-1251', S.Encoding);
  Assert.AreEqual('socks5h://p:1080', S.Proxy);
  Assert.AreEqual(45, S.TimeoutSec);
  Assert.AreEqual('eu-west-1', S.Region);
  Assert.AreEqual('/dav', S.Endpoint);
end;

procedure TTestNetUi.TestChangesAreSavedThroughTheHost;
var
  Done: TEvent;
begin
  Done := TEvent.Create(nil, True, False, '');
  try
    GManager.OnStoreChanged := SaveSessionsToHost;
    EditSession('');
    GAnswer(GAnswerData, 'ok', PAnsiChar(UTF8String(cMainValues)));
    Assert.IsTrue(GSettings.IndexOf('sessions') >= 0, 'the list was stored under "sessions"');
    Assert.IsTrue(Pos('"name":"Box"', GStored) > 0, 'with the new session in it');
  finally
    Done.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNetUi);

end.
