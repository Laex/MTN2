unit uNetUi;

{ The plugin's dialogs and the glue to the host: translated texts, the
  questions asked while a worker thread waits (password, SSH host key,
  certificate), and the editor of saved sessions.

  A worker thread cannot show a dialog; it posts the request to the main thread
  (PostToMain), the dialog is shown there, and the worker waits for the answer.
  The request object is reference counted so the answer can arrive after the
  worker gave up (cancel, timeout) without touching freed memory. }

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.JSON,
  uPluginHostAbi, uNetTypes, uNetManager;

const
  cPluginId: UTF8String = 'mtn.net';

type
  TNetUiPrompter = class(TInterfacedObject, INetPrompter)
  public
    function AskSecret(const ASession: TNetSession; AKeyPassphrase, ARetry: Boolean;
      AOp: TNetOp; out ASecret: string; out ASave: Boolean): Boolean;
    function TrustHostKey(const ASession: TNetSession; const AFingerprint: string;
      AChanged: Boolean; AOp: TNetOp): Boolean;
    function TrustCertificate(const ASession: TNetSession; const AMessage: string;
      AOp: TNetOp): Boolean;
  end;

/// <summary>Connects the unit to the host table and the session manager.</summary>
procedure NetUiAttach(AHost: PHostApiTable; AManager: TNetManager);
procedure NetUiDetach;
/// <summary>Text for AKey in the current language, or ADefault.</summary>
function Tr(const AKey, ADefault: string): string;
procedure SaveSessionsToHost;
function LoadSessionsFromHost: string;
/// <summary>The editor of one saved session; AName '' makes a new one.</summary>
procedure EditSession(const AName: string);
/// <summary>Opens the list of sessions in the active panel.</summary>
procedure OpenSessionList;
/// <summary>True when the active panel shows the list of sessions; fills the
/// session under the cursor ('' when the cursor is not on a session).</summary>
function ActivePanelIsSessionList(out ACursorSession: string): Boolean;
procedure ShowInfo(const AText: string; AWarning: Boolean = False);
/// <summary>Library information and the "disconnect all" button (the plugin's settings dialog).</summary>
procedure ShowSettings;
/// <summary>The function-bar labels while a panel shows the list of connections
/// (the host's JSON layout of SetPanelFBar).</summary>
function SessionListFBarJson: string;
/// <summary>Copies the connections saved for the built-in sftp:// into the list;
/// the result says how many were added and how many were already there.</summary>
function ImportBuiltInSftp(out AAdded, ASkipped: Integer): Boolean;
/// <summary>Asks for an address and opens it in the active panel.</summary>
procedure ShowOpenAddress;
/// <summary>Asks for permissions (octal) and applies them to the files selected
/// in the active panel, or to the one under the cursor.</summary>
procedure ShowChangePermissions;
/// <summary>Event handler for panel.dir: shows the connection of the folder in the status line.</summary>
procedure PanelDirChanged(AUserData: Pointer; ATopic, APayloadJson: PAnsiChar); cdecl;

implementation

uses
  System.IOUtils, uVfsTypes, uNetSecrets, uNetSessions, uNetCurlApi, uNetVfs, uNetClient;

const
  cWaitSliceMs = 200;
  cAnswerTimeoutMs = 10 * 60 * 1000;
  cBusyRetryMs = 400;

var
  GHost: PHostApiTable;
  GManager: TNetManager;
  GShuttingDown: Boolean;

type
  TDialogRequest = class(TInterfacedObject)
  public
    Decl: UTF8String;
    Event: TEvent;
    ControlId: string;
    ValuesJson: string;
    Failed: Boolean;
    Answered: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TDialogRequest.Create;
begin
  inherited Create;
  Event := TEvent.Create(nil, True, False, '');
end;

destructor TDialogRequest.Destroy;
begin
  Event.Free;
  inherited Destroy;
end;

procedure NetUiAttach(AHost: PHostApiTable; AManager: TNetManager);
begin
  GHost := AHost;
  GManager := AManager;
  GShuttingDown := False;
end;

procedure NetUiDetach;
begin
  GShuttingDown := True;
  GHost := nil;
  GManager := nil;
end;

function Tr(const AKey, ADefault: string): string;
var
  Buf: array[0..1023] of AnsiChar;
  Len: Int64;
  Big: TBytes;
begin
  Result := ADefault;
  if (GHost = nil) or not Assigned(GHost.Translate) then
    Exit;
  Len := GHost.Translate(PAnsiChar(cPluginId), PAnsiChar(UTF8String(AKey)),
    PAnsiChar(UTF8String(ADefault)), @Buf[0], SizeOf(Buf));
  if (Len >= 0) and (Len < SizeOf(Buf)) then
    Result := string(UTF8String(PAnsiChar(@Buf[0])))
  else if Len >= SizeOf(Buf) then
  begin
    SetLength(Big, Len + 1);
    Len := GHost.Translate(PAnsiChar(cPluginId), PAnsiChar(UTF8String(AKey)),
      PAnsiChar(UTF8String(ADefault)), PAnsiChar(@Big[0]), Length(Big));
    if (Len >= 0) and (Len < Length(Big)) then
      Result := string(UTF8String(PAnsiChar(@Big[0])));
  end;
end;

procedure ShowInfo(const AText: string; AWarning: Boolean);
begin
  if (GHost <> nil) and Assigned(GHost.ShowMessage) then
    GHost.ShowMessage(PAnsiChar(UTF8String(AText)), Ord(AWarning));
end;

function LoadSessionsFromHost: string;
var
  Buf: TBytes;
  Len: Int64;
begin
  Result := '';
  if (GHost = nil) or not Assigned(GHost.GetSetting) then
    Exit;
  SetLength(Buf, 64 * 1024);
  Len := GHost.GetSetting(PAnsiChar(cPluginId), 'sessions', PAnsiChar(@Buf[0]), Length(Buf));
  if Len = -2 then
  begin
    SetLength(Buf, 4 * 1024 * 1024);
    Len := GHost.GetSetting(PAnsiChar(cPluginId), 'sessions', PAnsiChar(@Buf[0]), Length(Buf));
  end;
  if Len > 0 then
    Result := TEncoding.UTF8.GetString(Buf, 0, Len);
end;

procedure SaveOnMain(AUserData: Pointer); cdecl;
begin
  try
    if (GHost <> nil) and (GManager <> nil) and Assigned(GHost.SetSetting) then
      GHost.SetSetting(PAnsiChar(cPluginId), 'sessions', PAnsiChar(UTF8String(GManager.SessionsJson)));
  except
    // A settings file that cannot be written leaves the change for this run only.
  end;
end;

procedure SaveSessionsToHost;
begin
  // The manager may report a change from any thread; settings are written on the main one.
  if (GHost <> nil) and Assigned(GHost.PostToMain) then
    GHost.PostToMain(PAnsiChar(cPluginId), @SaveOnMain, nil);
end;

{ JSON dialog builder }

type
  TDlg = class
  private
    FRoot: TJSONObject;
    FChildren: TJSONArray;
    function Box(const AType: string; ACol, ARow, AWidth: Integer): TJSONObject;
  public
    constructor Create(const ATitle: string; AWidth, AHeight: Integer);
    destructor Destroy; override;
    procedure Text(const AText: string; ACol, ARow: Integer);
    procedure Input(const AId, AValue: string; ACol, ARow, AWidth: Integer; APassword: Boolean = False);
    procedure Check(const AId, AText: string; AChecked: Boolean; ACol, ARow, AWidth: Integer);
    procedure Drop(const AId: string; const AItems: array of string; ASelected, ACol, ARow, AWidth: Integer);
    procedure Button(const AId, AText: string; ACol, ARow, AWidth: Integer; ADefault, ACancel: Boolean);
    function Json: UTF8String;
  end;

constructor TDlg.Create(const ATitle: string; AWidth, AHeight: Integer);
begin
  inherited Create;
  FRoot := TJSONObject.Create;
  FRoot.AddPair('type', 'dialog');
  FRoot.AddPair('version', '2.0');
  FRoot.AddPair('title', ATitle);
  FRoot.AddPair('width', TJSONNumber.Create(AWidth));
  FRoot.AddPair('height', TJSONNumber.Create(AHeight));
  FChildren := TJSONArray.Create;
  FRoot.AddPair('children', FChildren);
end;

destructor TDlg.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

function TDlg.Box(const AType: string; ACol, ARow, AWidth: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', AType);
  Result.AddPair('col', TJSONNumber.Create(ACol));
  Result.AddPair('row', TJSONNumber.Create(ARow));
  Result.AddPair('width', TJSONNumber.Create(AWidth));
  Result.AddPair('height', TJSONNumber.Create(1));
  FChildren.AddElement(Result);
end;

procedure TDlg.Text(const AText: string; ACol, ARow: Integer);
var
  C: TJSONObject;
begin
  C := Box('label', ACol, ARow, Length(AText) + 1);
  C.AddPair('text', AText);
end;

procedure TDlg.Input(const AId, AValue: string; ACol, ARow, AWidth: Integer; APassword: Boolean);
var
  C: TJSONObject;
begin
  C := Box('input', ACol, ARow, AWidth);
  C.AddPair('id', AId);
  C.AddPair('value', AValue);
  if APassword then
    C.AddPair('password', TJSONTrue.Create);
end;

procedure TDlg.Check(const AId, AText: string; AChecked: Boolean; ACol, ARow, AWidth: Integer);
var
  C: TJSONObject;
begin
  C := Box('checkbox', ACol, ARow, AWidth);
  C.AddPair('id', AId);
  C.AddPair('text', AText);
  C.AddPair('checked', TJSONBool.Create(AChecked));
end;

procedure TDlg.Drop(const AId: string; const AItems: array of string; ASelected, ACol, ARow,
  AWidth: Integer);
var
  C: TJSONObject;
  Arr: TJSONArray;
  S: string;
begin
  C := Box('dropdown', ACol, ARow, AWidth);
  C.AddPair('id', AId);
  Arr := TJSONArray.Create;
  for S in AItems do
    Arr.Add(S);
  C.AddPair('items', Arr);
  C.AddPair('selected', TJSONNumber.Create(ASelected));
end;

procedure TDlg.Button(const AId, AText: string; ACol, ARow, AWidth: Integer; ADefault, ACancel: Boolean);
var
  C: TJSONObject;
begin
  C := Box('button', ACol, ARow, AWidth);
  C.AddPair('id', AId);
  C.AddPair('text', AText);
  if ADefault then
    C.AddPair('default', TJSONTrue.Create);
  if ACancel then
    C.AddPair('cancel', TJSONTrue.Create);
end;

function TDlg.Json: UTF8String;
begin
  Result := UTF8String(FRoot.ToJSON);
end;

function ValueStr(const AValues: TJSONObject; const AId: string): string;
var
  V: TJSONValue;
begin
  V := AValues.GetValue(AId);
  if V is TJSONString then
    Result := TJSONString(V).Value
  else if V <> nil then
    Result := V.Value
  else
    Result := '';
end;

function ValueBool(const AValues: TJSONObject; const AId: string): Boolean;
var
  V: TJSONValue;
begin
  V := AValues.GetValue(AId);
  Result := (V is TJSONBool) and TJSONBool(V).AsBoolean;
end;

function IndexOfText(const AItems: array of string; const AText: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AItems) do
    if AItems[I] = AText then
      Exit(I);
  Result := 0;
end;

{ blocking questions }

procedure ShowRequestOnMain(AUserData: Pointer); cdecl; forward;

procedure DialogAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Req: TDialogRequest;
begin
  Req := TDialogRequest(AUserData);
  try
    Req.ControlId := string(UTF8String(AControlId));
    if AValuesJson <> nil then
      Req.ValuesJson := string(UTF8String(AValuesJson));
    Req.Answered := True;
    Req.Event.SetEvent;
  finally
    // Drops the reference taken for the main thread.
    Req._Release;
  end;
end;

procedure ShowRequestOnMain(AUserData: Pointer); cdecl;
var
  Req: TDialogRequest;
  R: Int64;
begin
  Req := TDialogRequest(AUserData);
  try
    R := -1;
    if (GHost <> nil) and Assigned(GHost.ShowDialog) then
      R := GHost.ShowDialog(PAnsiChar(cPluginId), PAnsiChar(Req.Decl), @DialogAnswer, Req);
    if R <> 0 then
    begin
      // Another dialog is open (or the panels are not on screen): the worker retries.
      Req.Failed := True;
      Req.Event.SetEvent;
      Req._Release;
    end;
  except
    Req.Failed := True;
    Req.Event.SetEvent;
    Req._Release;
  end;
end;

// Shows ADecl on the main thread and waits for the answer. False when the user
// cancelled the operation or no answer came.
function AskDialog(const ADecl: UTF8String; AOp: TNetOp; out AControl, AValues: string): Boolean;
var
  Req: TDialogRequest;
  Hold: IInterface;
  Waited, Tries: Integer;
begin
  AControl := '';
  AValues := '';
  Result := False;
  if (GHost = nil) or not Assigned(GHost.PostToMain) then
    Exit;
  Req := TDialogRequest.Create;
  Hold := Req;
  Req.Decl := ADecl;
  for Tries := 1 to 300 do
  begin
    Req.Failed := False;
    Req.Event.ResetEvent;
    // One reference for the main thread, released by the answer or a refusal.
    Req._AddRef;
    if GHost.PostToMain(PAnsiChar(cPluginId), @ShowRequestOnMain, Req) <> 0 then
    begin
      Req._Release;
      Exit;
    end;
    Waited := 0;
    while Req.Event.WaitFor(cWaitSliceMs) <> wrSignaled do
    begin
      Inc(Waited, cWaitSliceMs);
      if GShuttingDown or NetCancelled(AOp) or (Waited > cAnswerTimeoutMs) then
        Exit;
    end;
    if Req.Answered then
    begin
      AControl := Req.ControlId;
      AValues := Req.ValuesJson;
      Exit(True);
    end;
    if not Req.Failed then
      Exit;
    // Busy: wait a moment and ask again.
    Sleep(cBusyRetryMs);
    if GShuttingDown or NetCancelled(AOp) then
      Exit;
  end;
end;

function Describe(const S: TNetSession): string;
begin
  Result := S.Name;
  if S.Host <> '' then
  begin
    Result := '';
    if S.User <> '' then
      Result := S.User + '@';
    Result := Result + S.Host;
  end;
end;

function TNetUiPrompter.AskSecret(const ASession: TNetSession; AKeyPassphrase, ARetry: Boolean;
  AOp: TNetOp; out ASecret: string; out ASave: Boolean): Boolean;
var
  D: TDlg;
  Control, Values, Title, Prompt: string;
  Obj: TJSONValue;
  Save: Boolean;
begin
  ASecret := '';
  ASave := False;
  Save := SecretsAvailable;
  if AKeyPassphrase then
    Prompt := Format(Tr('ui.ask.passphrase', 'Passphrase of the key for %s:'), [Describe(ASession)])
  else if ASession.Protocol = npS3 then
    Prompt := Format(Tr('ui.ask.secretKey', 'Secret access key for %s:'), [Describe(ASession)])
  else
    Prompt := Format(Tr('ui.ask.password', 'Password for %s:'), [Describe(ASession)]);
  if ARetry then
    Title := Tr('ui.ask.titleRetry', 'Login failed - try again')
  else
    Title := Tr('ui.ask.title', 'Login');
  D := TDlg.Create(Title, 66, 10);
  try
    D.Text(Prompt, 2, 1);
    D.Input('secret', '', 2, 2, 60, True);
    if Save then
      D.Check('save', Tr('ui.ask.save', 'Save the password'), False, 2, 4, 40);
    D.Button('ok', '  ' + Tr('ui.ok', 'OK') + '  ', 18, 6, 12, True, False);
    D.Button('cancel', Tr('ui.cancel', 'Cancel'), 34, 6, 12, False, True);
    if not AskDialog(D.Json, AOp, Control, Values) then
      Exit(False);
  finally
    D.Free;
  end;
  if Control <> 'ok' then
    Exit(False);
  Obj := TJSONObject.ParseJSONValue(Values);
  try
    if Obj is TJSONObject then
    begin
      ASecret := ValueStr(TJSONObject(Obj), 'secret');
      ASave := Save and ValueBool(TJSONObject(Obj), 'save');
    end;
  finally
    Obj.Free;
  end;
  Result := ASecret <> '';
end;

function TNetUiPrompter.TrustHostKey(const ASession: TNetSession; const AFingerprint: string;
  AChanged: Boolean; AOp: TNetOp): Boolean;
var
  D: TDlg;
  Control, Values, Title: string;
begin
  if AChanged then
    Title := Tr('ui.hostkey.titleChanged', 'WARNING: the server key has changed')
  else
    Title := Tr('ui.hostkey.title', 'Unknown server key');
  D := TDlg.Create(Title, 72, 14);
  try
    D.Text(Format(Tr('ui.hostkey.server', 'Server: %s'), [ASession.Host]), 2, 1);
    if AChanged then
    begin
      D.Text(Tr('ui.hostkey.changed1', 'The key of this server is not the one you trusted before.'), 2, 3);
      D.Text(Tr('ui.hostkey.changed2', 'Someone may be intercepting the connection.'), 2, 4);
    end
    else
      D.Text(Tr('ui.hostkey.new', 'The authenticity of this server cannot be checked yet.'), 2, 3);
    D.Text(Tr('ui.hostkey.fingerprint', 'SHA-256 fingerprint:'), 2, 6);
    D.Input('fp', 'SHA256:' + AFingerprint, 2, 7, 66);
    D.Button('trust', ' ' + Tr('ui.hostkey.trust', 'Trust and continue') + ' ', 14, 10, 22, False, False);
    D.Button('cancel', Tr('ui.cancel', 'Cancel'), 40, 10, 12, True, True);
    Result := AskDialog(D.Json, AOp, Control, Values) and (Control = 'trust');
  finally
    D.Free;
  end;
end;

function TNetUiPrompter.TrustCertificate(const ASession: TNetSession; const AMessage: string;
  AOp: TNetOp): Boolean;
var
  D: TDlg;
  Control, Values, Msg: string;
begin
  Msg := AMessage;
  if Length(Msg) > 64 then
    Msg := Copy(Msg, 1, 61) + '...';
  D := TDlg.Create(Tr('ui.cert.title', 'Untrusted certificate'), 72, 12);
  try
    D.Text(Format(Tr('ui.cert.server', 'The certificate of %s is not trusted.'), [ASession.Host]), 2, 1);
    D.Text(Msg, 2, 3);
    D.Text(Tr('ui.cert.hint', 'Continue only if you know the server.'), 2, 5);
    D.Button('trust', ' ' + Tr('ui.cert.continue', 'Continue anyway') + ' ', 14, 8, 20, False, False);
    D.Button('cancel', Tr('ui.cancel', 'Cancel'), 38, 8, 12, True, True);
    Result := AskDialog(D.Json, AOp, Control, Values) and (Control = 'trust');
  finally
    D.Free;
  end;
end;

{ the session editor }

type
  TEditState = class
  public
    OldName: string;
    S: TNetSession;
    constructor Create;
  end;

constructor TEditState.Create;
begin
  inherited Create;
  S := DefaultNetSession;
end;

procedure ShowMainEditor(AState: TEditState); forward;
procedure ShowMoreEditor(AState: TEditState); forward;

function ProtocolItems: TArray<string>;
begin
  Result := ['FTP', 'FTPS (TLS)', 'SFTP (SSH)', 'SCP (SSH)', 'WebDAV', 'WebDAV (HTTPS)', 'S3'];
end;

function AuthItems: TArray<string>;
begin
  Result := [Tr('ui.auth.password', 'Password'), Tr('ui.auth.key', 'Key file'),
    Tr('ui.auth.agent', 'SSH agent'), Tr('ui.auth.anonymous', 'Anonymous')];
end;

function PortText(APort: Integer): string;
begin
  if APort > 0 then
    Result := IntToStr(APort)
  else
    Result := '';
end;

procedure RefreshPanels;
begin
  if (GHost <> nil) and Assigned(GHost.PanelRefresh) then
    GHost.PanelRefresh();
end;

procedure ApplyMainValues(AState: TEditState; const AValues: TJSONObject);
var
  S: TNetSession;
begin
  S := AState.S;
  S.Name := Trim(ValueStr(AValues, 'name'));
  S.Protocol := TNetProtocol(IndexOfText(ProtocolItems, ValueStr(AValues, 'protocol')));
  S.Host := Trim(ValueStr(AValues, 'host'));
  S.Port := StrToIntDef(Trim(ValueStr(AValues, 'port')), 0);
  S.User := Trim(ValueStr(AValues, 'user'));
  S.Auth := TNetAuth(IndexOfText(AuthItems, ValueStr(AValues, 'auth')));
  S.Password := ValueStr(AValues, 'secret');
  S.KeyFile := Trim(ValueStr(AValues, 'keyfile'));
  S.KeyPassphrase := ValueStr(AValues, 'passphrase');
  S.RootPath := Trim(ValueStr(AValues, 'root'));
  if S.RootPath = '' then
    S.RootPath := '/';
  S.SavePassword := ValueBool(AValues, 'save');
  AState.S := S;
end;

procedure ApplyMoreValues(AState: TEditState; const AValues: TJSONObject);
var
  S: TNetSession;
begin
  S := AState.S;
  S.Passive := ValueBool(AValues, 'passive');
  S.ImplicitTls := ValueBool(AValues, 'implicit');
  S.VerifyCert := ValueBool(AValues, 'verify');
  S.PathStyle := ValueBool(AValues, 'pathstyle');
  S.Encoding := Trim(ValueStr(AValues, 'encoding'));
  S.Proxy := Trim(ValueStr(AValues, 'proxy'));
  S.TimeoutSec := StrToIntDef(Trim(ValueStr(AValues, 'timeout')), 30);
  S.Region := Trim(ValueStr(AValues, 'region'));
  S.Endpoint := Trim(ValueStr(AValues, 'endpoint'));
  AState.S := S;
end;

// Finishes the editor: validate, store, refresh the panel.
function CommitSession(AState: TEditState): Boolean;
var
  S: TNetSession;
begin
  S := AState.S;
  S.Name := SanitizeSessionName(S.Name);
  if S.Name = '' then
  begin
    ShowInfo(Tr('ui.edit.needName', 'Give the connection a name.'), True);
    Exit(False);
  end;
  if S.Host = '' then
  begin
    ShowInfo(Tr('ui.edit.needHost', 'Give the address of the server.'), True);
    Exit(False);
  end;
  if (S.Port < 0) or (S.Port > 65535) then
  begin
    ShowInfo(Tr('ui.edit.badPort', 'The port must be a number from 1 to 65535.'), True);
    Exit(False);
  end;
  if S.TimeoutSec < 5 then
    S.TimeoutSec := 5;
  if AState.OldName = '' then
    Result := GManager.AddSession(S)
  else
    Result := GManager.UpdateSession(AState.OldName, S);
  if not Result then
    ShowInfo(Tr('ui.edit.nameTaken', 'A connection with this name already exists.'), True)
  else
    RefreshPanels;
end;

procedure MainAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  State: TEditState;
  Obj: TJSONValue;
  Id: string;
begin
  State := TEditState(AUserData);
  try
    Id := string(UTF8String(AControlId));
    if (Id <> 'ok') and (Id <> 'more') then
    begin
      State.Free;
      Exit;
    end;
    Obj := TJSONObject.ParseJSONValue(string(UTF8String(AValuesJson)));
    try
      if Obj is TJSONObject then
        ApplyMainValues(State, TJSONObject(Obj));
    finally
      Obj.Free;
    end;
    if Id = 'more' then
    begin
      ShowMoreEditor(State);
      Exit;
    end;
    if CommitSession(State) then
      State.Free
    else
      ShowMainEditor(State);
  except
    State.Free;
  end;
end;

procedure MoreAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  State: TEditState;
  Obj: TJSONValue;
begin
  State := TEditState(AUserData);
  try
    if string(UTF8String(AControlId)) = 'ok' then
    begin
      Obj := TJSONObject.ParseJSONValue(string(UTF8String(AValuesJson)));
      try
        if Obj is TJSONObject then
          ApplyMoreValues(State, TJSONObject(Obj));
      finally
        Obj.Free;
      end;
    end;
    ShowMainEditor(State);
  except
    State.Free;
  end;
end;

procedure ShowMainEditor(AState: TEditState);
var
  D: TDlg;
  S: TNetSession;
  R: Int64;
begin
  S := AState.S;
  D := TDlg.Create(Tr('ui.edit.title', 'Connection'), 76, 18);
  try
    D.Text(Tr('ui.edit.name', 'Name:'), 2, 1);
    D.Input('name', S.Name, 18, 1, 54);
    D.Text(Tr('ui.edit.protocol', 'Protocol:'), 2, 2);
    D.Drop('protocol', ProtocolItems, Ord(S.Protocol), 18, 2, 24);
    D.Text(Tr('ui.edit.host', 'Server:'), 2, 3);
    D.Input('host', S.Host, 18, 3, 36);
    D.Text(Tr('ui.edit.port', 'Port:'), 56, 3);
    D.Input('port', PortText(S.Port), 62, 3, 10);
    D.Text(Tr('ui.edit.user', 'User / access key:'), 2, 4);
    D.Input('user', S.User, 18, 4, 54);
    D.Text(Tr('ui.edit.auth', 'Log in with:'), 2, 5);
    D.Drop('auth', AuthItems, Ord(S.Auth), 18, 5, 24);
    D.Text(Tr('ui.edit.secret', 'Password / secret:'), 2, 6);
    D.Input('secret', S.Password, 18, 6, 54, True);
    D.Text(Tr('ui.edit.keyfile', 'Key file:'), 2, 7);
    D.Input('keyfile', S.KeyFile, 18, 7, 54);
    D.Text(Tr('ui.edit.passphrase', 'Key passphrase:'), 2, 8);
    D.Input('passphrase', S.KeyPassphrase, 18, 8, 54, True);
    D.Text(Tr('ui.edit.root', 'Start folder:'), 2, 9);
    D.Input('root', S.RootPath, 18, 9, 54);
    if SecretsAvailable then
      D.Check('save', Tr('ui.edit.save', 'Save the password'), S.SavePassword, 18, 11, 40);
    D.Button('ok', '  ' + Tr('ui.ok', 'OK') + '  ', 10, 14, 12, True, False);
    D.Button('more', Tr('ui.edit.more', 'More...'), 26, 14, 14, False, False);
    D.Button('cancel', Tr('ui.cancel', 'Cancel'), 44, 14, 12, False, True);
    R := -1;
    if (GHost <> nil) and Assigned(GHost.ShowDialog) then
      R := GHost.ShowDialog(PAnsiChar(cPluginId), PAnsiChar(D.Json), @MainAnswer, AState);
  finally
    D.Free;
  end;
  if R <> 0 then
  begin
    ShowInfo(Tr('ui.busy', 'Close the open dialog first.'), True);
    AState.Free;
  end;
end;

procedure ShowMoreEditor(AState: TEditState);
var
  D: TDlg;
  S: TNetSession;
  R: Int64;
begin
  S := AState.S;
  D := TDlg.Create(Tr('ui.more.title', 'Connection - more options'), 76, 17);
  try
    D.Check('passive', Tr('ui.more.passive', 'FTP: passive mode'), S.Passive, 2, 1, 50);
    D.Check('implicit', Tr('ui.more.implicit', 'FTPS: implicit TLS (port 990)'), S.ImplicitTls, 2, 2, 50);
    D.Check('verify', Tr('ui.more.verify', 'Check TLS certificates'), S.VerifyCert, 2, 3, 50);
    D.Check('pathstyle', Tr('ui.more.pathstyle', 'S3: address buckets by path'), S.PathStyle, 2, 4, 50);
    D.Text(Tr('ui.more.encoding', 'Encoding of names:'), 2, 6);
    D.Input('encoding', S.Encoding, 24, 6, 30);
    D.Text(Tr('ui.more.proxy', 'Proxy:'), 2, 7);
    D.Input('proxy', S.Proxy, 24, 7, 48);
    D.Text(Tr('ui.more.timeout', 'Timeout, s:'), 2, 8);
    D.Input('timeout', IntToStr(S.TimeoutSec), 24, 8, 8);
    D.Text(Tr('ui.more.region', 'S3: region:'), 2, 9);
    D.Input('region', S.Region, 24, 9, 30);
    D.Text(Tr('ui.more.endpoint', 'WebDAV: base path:'), 2, 10);
    D.Input('endpoint', S.Endpoint, 24, 10, 48);
    D.Button('ok', '  ' + Tr('ui.ok', 'OK') + '  ', 22, 13, 12, True, False);
    D.Button('cancel', Tr('ui.cancel', 'Cancel'), 38, 13, 12, False, True);
    R := -1;
    if (GHost <> nil) and Assigned(GHost.ShowDialog) then
      R := GHost.ShowDialog(PAnsiChar(cPluginId), PAnsiChar(D.Json), @MoreAnswer, AState);
  finally
    D.Free;
  end;
  if R <> 0 then
    AState.Free;
end;

procedure EditSession(const AName: string);
var
  State: TEditState;
begin
  if (GHost = nil) or (GManager = nil) then
    Exit;
  State := TEditState.Create;
  if AName = '' then
  begin
    State.S.Name := GManager.UniqueSessionName(Tr('ui.edit.newName', 'New connection'));
    State.S.SavePassword := SecretsAvailable;
  end
  else
  begin
    if not GManager.FindSession(AName, State.S) then
    begin
      State.Free;
      Exit;
    end;
    State.OldName := AName;
  end;
  ShowMainEditor(State);
end;

procedure OpenSessionList;
begin
  if (GHost <> nil) and Assigned(GHost.PanelGoto) then
    GHost.PanelGoto(-1, 'net:///');
end;

function ActivePanelIsSessionList(out ACursorSession: string): Boolean;
var
  Buf: TBytes;
  Len: Int64;
  Root, SideVal: TJSONValue;
  Side, Uri, Cursor: string;
  T: TNetTarget;
begin
  Result := False;
  ACursorSession := '';
  if (GHost = nil) or not Assigned(GHost.PanelInfo) then
    Exit;
  SetLength(Buf, 64 * 1024);
  Len := GHost.PanelInfo(PAnsiChar(@Buf[0]), Length(Buf));
  if (Len <= 0) or (Len >= Length(Buf)) then
    Exit;
  Root := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Buf, 0, Len));
  try
    if not (Root is TJSONObject) then
      Exit;
    Side := ValueStr(TJSONObject(Root), 'active');
    SideVal := TJSONObject(Root).GetValue(Side);
    if not (SideVal is TJSONObject) then
      Exit;
    Uri := ValueStr(TJSONObject(SideVal), 'uri');
    Cursor := ValueStr(TJSONObject(SideVal), 'cursor');
  finally
    Root.Free;
  end;
  if not ParseNetUri(Uri, T) or not T.IsSessionList then
    Exit;
  Result := True;
  if Cursor <> '' then
  begin
    Cursor := NormalizeNetUri(Cursor);
    if ParseNetUri(Cursor, T) and (T.Scheme = cNetScheme) and (T.Authority <> '') then
      ACursorSession := T.Authority;
  end;
end;

function LibraryText: string;
begin
  if CurlLoaded then
    Result := Format(Tr('ui.about.ok', 'Network connections use %s'), [CurlVersionText])
  else
    Result := Tr('ui.about.nolib', 'libcurl was not found next to the plugin: connections do not work');
end;

function HostConfigDir: string;
var
  Buf: TBytes;
  Len: Int64;
  Root: TJSONValue;
begin
  Result := '';
  if (GHost = nil) or not Assigned(GHost.HostInfo) then
    Exit;
  SetLength(Buf, 16 * 1024);
  Len := GHost.HostInfo(PAnsiChar(@Buf[0]), Length(Buf));
  if (Len <= 0) or (Len >= Length(Buf)) then
    Exit;
  Root := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Buf, 0, Len));
  try
    if Root is TJSONObject then
      Result := ValueStr(TJSONObject(Root), 'configDir');
  finally
    Root.Free;
  end;
end;

function ImportBuiltInSftp(out AAdded, ASkipped: Integer): Boolean;
var
  Path, Name: string;
  Root: TJSONValue;
  Items: TJSONValue;
  Item: TJSONValue;
  Obj: TJSONObject;
  S, Existing: TNetSession;
  Host: string;
  Port: Integer;
begin
  AAdded := 0;
  ASkipped := 0;
  Result := False;
  if (GManager = nil) or (HostConfigDir = '') then
    Exit;
  Path := IncludeTrailingPathDelimiter(HostConfigDir) + 'sshconnections.json';
  if not FileExists(Path) then
    Exit;
  Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8));
  try
    if not (Root is TJSONObject) then
      Exit;
    Items := TJSONObject(Root).GetValue('items');
    if not (Items is TJSONArray) then
      Exit;
    Result := True;
    for Item in TJSONArray(Items) do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Obj := TJSONObject(Item);
      Host := Trim(ValueStr(Obj, 'host'));
      if Host = '' then
        Continue;
      Port := 0;
      Obj.TryGetValue<Integer>('port', Port);
      S := DefaultNetSession;
      S.Protocol := npSftp;
      S.Host := Host;
      S.Port := Port;
      S.User := Trim(ValueStr(Obj, 'user'));
      if GManager.FindSession(SanitizeSessionName(ValueStr(Obj, 'name')), Existing) or
         GManager.FindServerSession(S.Protocol, S.Host, S.Port, S.User, Existing) then
      begin
        Inc(ASkipped);
        Continue;
      end;
      S.KeyFile := ValueStr(Obj, 'identityFile');
      if S.KeyFile <> '' then
        S.Auth := naKey
      else
        S.Auth := naAgent;
      Name := SanitizeSessionName(ValueStr(Obj, 'name'));
      if Name = '' then
        Name := Host;
      S.Name := GManager.UniqueSessionName(Name);
      if GManager.AddSession(S) then
        Inc(AAdded);
    end;
  finally
    Root.Free;
  end;
end;

function SessionListFBarJson: string;
var
  Root, Section: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Section := TJSONObject.Create;
    Section.AddPair('F3', '');
    Section.AddPair('F4', Tr('ui.fbar.edit', 'Edit'));
    Section.AddPair('F5', '');
    Section.AddPair('F6', '');
    Section.AddPair('F7', Tr('ui.fbar.new', 'New'));
    Section.AddPair('F8', Tr('ui.fbar.delete', 'Delete'));
    Root.AddPair('root', Section);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure SettingsAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Added, Skipped: Integer;
begin
  try
    if (string(UTF8String(AControlId)) = 'disconnect') and (GManager <> nil) then
    begin
      GManager.Disconnect;
      ShowInfo(Tr('ui.settings.done', 'The connections were closed.'));
    end
    else if string(UTF8String(AControlId)) = 'import' then
    begin
      if not ImportBuiltInSftp(Added, Skipped) then
        ShowInfo(Tr('ui.import.none', 'No saved sftp:// connections were found.'), True)
      else
        ShowInfo(Format(Tr('ui.import.done', 'Imported connections: %d, already in the list: %d.'),
          [Added, Skipped]));
    end;
  except
    // Closing connections is best effort.
  end;
end;

procedure ShowSettings;
var
  D: TDlg;
  Lib: string;
begin
  if GHost = nil then
    Exit;
  Lib := LibraryText;
  if Length(Lib) > 66 then
    Lib := Copy(Lib, 1, 63) + '...';
  D := TDlg.Create(Tr('ui.settings.title', 'Network connections'), 72, 12);
  try
    D.Text(Lib, 2, 1);
    if SecretsAvailable then
      D.Text(Tr('ui.settings.sealed', 'Saved passwords are sealed for your Windows account.'), 2, 3)
    else
      D.Text(Tr('ui.settings.notSealed', 'Passwords are not saved on this system; they are asked for per run.'), 2, 3);
    D.Button('import', Tr('ui.settings.import', 'Import connections from sftp://'), 8, 5, 40, False, False);
    D.Button('disconnect', Tr('ui.settings.disconnect', 'Close connections'), 8, 7, 22, False, False);
    D.Button('close', Tr('ui.close', 'Close'), 36, 7, 12, True, True);
    if Assigned(GHost.ShowDialog) then
      GHost.ShowDialog(PAnsiChar(cPluginId), PAnsiChar(D.Json), @SettingsAnswer, nil);
  finally
    D.Free;
  end;
end;

procedure OpenAddressAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Obj: TJSONValue;
  Address: string;
begin
  try
    if string(UTF8String(AControlId)) <> 'ok' then
      Exit;
    Obj := TJSONObject.ParseJSONValue(string(UTF8String(AValuesJson)));
    try
      if Obj is TJSONObject then
        Address := Trim(ValueStr(TJSONObject(Obj), 'address'));
    finally
      Obj.Free;
    end;
    if (Address <> '') and (GHost <> nil) and Assigned(GHost.PanelGoto) then
      GHost.PanelGoto(-1, PAnsiChar(UTF8String(NormalizeNetUri(Address))));
  except
    // A bad address is simply not opened.
  end;
end;

procedure ShowOpenAddress;
var
  D: TDlg;
begin
  if GHost = nil then
    Exit;
  D := TDlg.Create(Tr('ui.open.title', 'Open address'), 72, 10);
  try
    D.Text(Tr('ui.open.prompt', 'Address (ftp://, ftps://, nsftp://, scp://, dav://, davs://, s3:// or net://):'), 2, 1);
    D.Input('address', 'ftp://', 2, 2, 66);
    D.Button('ok', '  ' + Tr('ui.ok', 'OK') + '  ', 20, 5, 12, True, False);
    D.Button('cancel', Tr('ui.cancel', 'Cancel'), 36, 5, 12, False, True);
    if Assigned(GHost.ShowDialog) then
      GHost.ShowDialog(PAnsiChar(cPluginId), PAnsiChar(D.Json), @OpenAddressAnswer, nil);
  finally
    D.Free;
  end;
end;

{ permissions }

type
  TTextNote = class
  public
    Text: string;
    Warning: Boolean;
    Refresh: Boolean;
  end;

procedure NoteOnMain(AUserData: Pointer); cdecl;
var
  Note: TTextNote;
begin
  Note := TTextNote(AUserData);
  try
    if Note.Text <> '' then
      ShowInfo(Note.Text, Note.Warning);
    if Note.Refresh and (GHost <> nil) and Assigned(GHost.PanelRefresh) then
      GHost.PanelRefresh();
  finally
    Note.Free;
  end;
end;

procedure PostNote(const AText: string; AWarning, ARefresh: Boolean);
var
  Note: TTextNote;
begin
  if (GHost = nil) or not Assigned(GHost.PostToMain) then
    Exit;
  Note := TTextNote.Create;
  Note.Text := AText;
  Note.Warning := AWarning;
  Note.Refresh := ARefresh;
  if GHost.PostToMain(PAnsiChar(cPluginId), @NoteOnMain, Note) <> 0 then
    Note.Free;
end;

type
  TChmodJob = class
  public
    Uris: TArray<string>;
    Mode: Cardinal;
  end;

function ParseOctal(const AText: string; out AMode: Cardinal): Boolean;
var
  C: Char;
begin
  AMode := 0;
  Result := (AText <> '') and (Length(AText) <= 4);
  for C in AText do
    if (C < '0') or (C > '7') then
      Exit(False)
    else
      AMode := AMode * 8 + Cardinal(Ord(C) - Ord('0'));
end;

procedure RunChmod(AJob: TChmodJob);
var
  Uri: string;
  Op: TNetOp;
  R: TNetResult;
  Failed: string;
  Mode: Cardinal;
begin
  Failed := '';
  Mode := AJob.Mode;
  for Uri in AJob.Uris do
  begin
    Op := TNetOp.Create;
    try
      R := GManager.Execute(NormalizeNetUri(Uri), Op,
        function(AClient: TNetClient; const APath: string): TNetResult
        begin
          Result := AClient.SetMode(APath, Mode, Op);
        end);
      if R <> nrOk then
      begin
        Failed := PosixLastSegment(Uri) + ': ' + Op.ErrorText;
        Break;
      end;
    finally
      Op.Free;
    end;
  end;
  if Failed = '' then
    PostNote('', False, True)
  else
    PostNote(Failed, True, True);
end;

procedure ChmodAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Job: TChmodJob;
  Obj: TJSONValue;
  Text: string;
begin
  Job := TChmodJob(AUserData);
  try
    if string(UTF8String(AControlId)) <> 'ok' then
    begin
      Job.Free;
      Exit;
    end;
    Obj := TJSONObject.ParseJSONValue(string(UTF8String(AValuesJson)));
    try
      if Obj is TJSONObject then
        Text := Trim(ValueStr(TJSONObject(Obj), 'mode'));
    finally
      Obj.Free;
    end;
    if not ParseOctal(Text, Job.Mode) then
    begin
      ShowInfo(Tr('ui.chmod.bad', 'Permissions are written as octal digits, for example 644 or 755.'), True);
      Job.Free;
      Exit;
    end;
    // The change runs on a thread of its own: it may need a login.
    TThread.CreateAnonymousThread(
      procedure
      begin
        try
          RunChmod(Job);
        finally
          Job.Free;
        end;
      end).Start;
  except
    Job.Free;
  end;
end;

function SelectedUris: TArray<string>;
var
  Buf: TBytes;
  Len: Int64;
  Root, SideVal, Sel: TJSONValue;
  Side, Cursor: string;
  I: Integer;
  List: TStringList;
begin
  SetLength(Result, 0);
  if (GHost = nil) or not Assigned(GHost.PanelInfo) then
    Exit;
  SetLength(Buf, 256 * 1024);
  Len := GHost.PanelInfo(PAnsiChar(@Buf[0]), Length(Buf));
  if (Len <= 0) or (Len >= Length(Buf)) then
    Exit;
  Root := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Buf, 0, Len));
  List := TStringList.Create;
  try
    if not (Root is TJSONObject) then
      Exit;
    Side := ValueStr(TJSONObject(Root), 'active');
    SideVal := TJSONObject(Root).GetValue(Side);
    if not (SideVal is TJSONObject) then
      Exit;
    Sel := TJSONObject(SideVal).GetValue('selected');
    if Sel is TJSONArray then
      for I := 0 to TJSONArray(Sel).Count - 1 do
        List.Add(TJSONArray(Sel).Items[I].Value);
    if List.Count = 0 then
    begin
      Cursor := ValueStr(TJSONObject(SideVal), 'cursor');
      if Cursor <> '' then
        List.Add(Cursor);
    end;
    Result := List.ToStringArray;
  finally
    List.Free;
    Root.Free;
  end;
end;

procedure ShowChangePermissions;
var
  Job: TChmodJob;
  Uris: TArray<string>;
  Uri: string;
  T: TNetTarget;
  D: TDlg;
  Ok: Boolean;
begin
  if (GHost = nil) or (GManager = nil) then
    Exit;
  Uris := SelectedUris;
  Ok := Length(Uris) > 0;
  for Uri in Uris do
    if not ParseNetUri(NormalizeNetUri(Uri), T) or T.IsSessionList or (T.Path = '/') then
      Ok := False;
  if not Ok then
  begin
    ShowInfo(Tr('ui.chmod.none', 'Select files on a server first.'), True);
    Exit;
  end;
  Job := TChmodJob.Create;
  Job.Uris := Uris;
  D := TDlg.Create(Tr('ui.chmod.title', 'Permissions'), 56, 9);
  try
    D.Text(Tr('ui.chmod.prompt', 'Permissions (octal, for example 644):'), 2, 1);
    D.Input('mode', '644', 2, 2, 12);
    D.Button('ok', '  ' + Tr('ui.ok', 'OK') + '  ', 12, 5, 12, True, False);
    D.Button('cancel', Tr('ui.cancel', 'Cancel'), 28, 5, 12, False, True);
    if not Assigned(GHost.ShowDialog) or
       (GHost.ShowDialog(PAnsiChar(cPluginId), PAnsiChar(D.Json), @ChmodAnswer, Job) <> 0) then
      Job.Free;
  finally
    D.Free;
  end;
end;

{ status line }

procedure PanelDirChanged(AUserData: Pointer; ATopic, APayloadJson: PAnsiChar); cdecl;
var
  Obj: TJSONValue;
  Uri, Side, Text: string;
  T: TNetTarget;
  S: TNetSession;
  Proto: TNetProtocol;
begin
  try
    if (GHost = nil) or not Assigned(GHost.SetStatusSegment) or (GManager = nil) then
      Exit;
    Obj := TJSONObject.ParseJSONValue(string(UTF8String(APayloadJson)));
    try
      if not (Obj is TJSONObject) then
        Exit;
      Side := ValueStr(TJSONObject(Obj), 'side');
      Uri := NormalizeNetUri(ValueStr(TJSONObject(Obj), 'uri'));
    finally
      Obj.Free;
    end;
    Text := '';
    if ParseNetUri(Uri, T) and not T.IsSessionList then
    begin
      if T.IsDirect then
      begin
        NetSchemeProtocol(T.Scheme, Proto);
        Text := NetProtocolCaption(Proto) + ' ' + T.Authority;
      end
      else if GManager.FindSession(T.Authority, S) then
        Text := NetProtocolCaption(S.Protocol) + ' ' + S.Name;
    end;
    // One segment per side: the status line shows the connection of each panel.
    GHost.SetStatusSegment(PAnsiChar(cPluginId), PAnsiChar(UTF8String('conn.' + Side)),
      PAnsiChar(UTF8String(Text)));
  except
    // The status text is decoration.
  end;
end;

end.
