unit uNetSessions;

{ The list of saved sessions and its JSON form (what the plugin keeps in the
  host's settings). Secrets are sealed with uNetSecrets when the session asks
  to save them and are never written in the clear. Pure data: reading and
  writing the settings is the caller's job. }

interface

uses
  System.SysUtils, System.Generics.Collections, uNetTypes;

type
  TNetSessionStore = class
  private
    FItems: TList<TNetSession>;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TNetSession;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    /// <summary>Replaces the list by the one in AJson (a bad document gives an empty list).</summary>
    procedure Load(const AJson: string);
    function ToJson: string;
    function IndexOfName(const AName: string): Integer;
    function Find(const AName: string; out ASession: TNetSession): Boolean;
    /// <summary>The session of the same protocol, host, port and user (the user
    /// may be empty in the address) - the login of a direct address.</summary>
    function FindForServer(AProtocol: TNetProtocol; const AHost: string; APort: Integer;
      const AUser: string; out ASession: TNetSession): Boolean;
    /// <summary>False when the name is empty or already taken.</summary>
    function Add(const ASession: TNetSession): Boolean;
    /// <summary>Replaces the session named AOldName (it may be renamed); False
    /// when it does not exist or the new name belongs to another session.</summary>
    function Update(const AOldName: string; const ASession: TNetSession): Boolean;
    function Delete(const AName: string): Boolean;
    function UniqueName(const ABase: string): string;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TNetSession read GetItem; default;
  end;

/// <summary>A session name fit for the authority of an address: no '/', '\',
/// control characters or surrounding blanks.</summary>
function SanitizeSessionName(const AName: string): string;
function NetAuthName(AAuth: TNetAuth): string;
function NetAuthFromName(const AName: string): TNetAuth;

implementation

uses
  System.JSON, uNetSecrets;

function SanitizeSessionName(const AName: string): string;
var
  I: Integer;
begin
  Result := Trim(AName);
  for I := 1 to Length(Result) do
    if (Result[I] < ' ') or CharInSet(Result[I], ['/', '\']) then
      Result[I] := '_';
end;

function NetAuthName(AAuth: TNetAuth): string;
begin
  case AAuth of
    naKey: Result := 'key';
    naAgent: Result := 'agent';
    naAnonymous: Result := 'anonymous';
  else
    Result := 'password';
  end;
end;

function NetAuthFromName(const AName: string): TNetAuth;
begin
  if SameText(AName, 'key') then
    Result := naKey
  else if SameText(AName, 'agent') then
    Result := naAgent
  else if SameText(AName, 'anonymous') then
    Result := naAnonymous
  else
    Result := naPassword;
end;

constructor TNetSessionStore.Create;
begin
  inherited Create;
  FItems := TList<TNetSession>.Create;
end;

destructor TNetSessionStore.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TNetSessionStore.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TNetSessionStore.GetItem(AIndex: Integer): TNetSession;
begin
  Result := FItems[AIndex];
end;

procedure TNetSessionStore.Clear;
begin
  FItems.Clear;
end;

function TNetSessionStore.IndexOfName(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    if SameText(FItems[I].Name, AName) then
      Exit(I);
  Result := -1;
end;

function TNetSessionStore.Find(const AName: string; out ASession: TNetSession): Boolean;
var
  I: Integer;
begin
  I := IndexOfName(AName);
  Result := I >= 0;
  if Result then
    ASession := FItems[I]
  else
    ASession := DefaultNetSession;
end;

function TNetSessionStore.FindForServer(AProtocol: TNetProtocol; const AHost: string;
  APort: Integer; const AUser: string; out ASession: TNetSession): Boolean;
var
  S: TNetSession;
begin
  for S in FItems do
    if (S.Protocol = AProtocol) and SameText(S.Host, AHost) and
       ((APort = 0) or (NetEffectivePort(S) = APort) or (S.Port = APort)) and
       ((AUser = '') or SameText(S.User, AUser)) then
    begin
      ASession := S;
      Exit(True);
    end;
  ASession := DefaultNetSession;
  Result := False;
end;

function TNetSessionStore.Add(const ASession: TNetSession): Boolean;
var
  S: TNetSession;
begin
  S := ASession;
  S.Name := SanitizeSessionName(S.Name);
  if (S.Name = '') or (IndexOfName(S.Name) >= 0) then
    Exit(False);
  FItems.Add(S);
  Result := True;
end;

function TNetSessionStore.Update(const AOldName: string; const ASession: TNetSession): Boolean;
var
  I, Other: Integer;
  S: TNetSession;
begin
  I := IndexOfName(AOldName);
  if I < 0 then
    Exit(False);
  S := ASession;
  S.Name := SanitizeSessionName(S.Name);
  if S.Name = '' then
    Exit(False);
  Other := IndexOfName(S.Name);
  if (Other >= 0) and (Other <> I) then
    Exit(False);
  FItems[I] := S;
  Result := True;
end;

function TNetSessionStore.Delete(const AName: string): Boolean;
var
  I: Integer;
begin
  I := IndexOfName(AName);
  Result := I >= 0;
  if Result then
    FItems.Delete(I);
end;

function TNetSessionStore.UniqueName(const ABase: string): string;
var
  N: Integer;
begin
  Result := SanitizeSessionName(ABase);
  if Result = '' then
    Result := 'Session';
  if IndexOfName(Result) < 0 then
    Exit;
  N := 2;
  while IndexOfName(Result + ' (' + IntToStr(N) + ')') >= 0 do
    Inc(N);
  Result := Result + ' (' + IntToStr(N) + ')';
end;

function JsonStr(AObj: TJSONObject; const AName, ADefault: string): string;
var
  V: TJSONValue;
begin
  V := AObj.GetValue(AName);
  if V is TJSONString then
    Result := TJSONString(V).Value
  else
    Result := ADefault;
end;

function JsonInt(AObj: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  V: TJSONValue;
begin
  V := AObj.GetValue(AName);
  if V is TJSONNumber then
    Result := TJSONNumber(V).AsInt
  else
    Result := ADefault;
end;

function JsonBool(AObj: TJSONObject; const AName: string; ADefault: Boolean): Boolean;
var
  V: TJSONValue;
begin
  V := AObj.GetValue(AName);
  if V is TJSONBool then
    Result := TJSONBool(V).AsBoolean
  else
    Result := ADefault;
end;

procedure TNetSessionStore.Load(const AJson: string);
var
  Root: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
  Obj: TJSONObject;
  S: TNetSession;
  Proto: TNetProtocol;
  Sealed, Plain: string;
begin
  FItems.Clear;
  if Trim(AJson) = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(AJson);
  if Root = nil then
    Exit;
  try
    if not (Root is TJSONArray) then
      Exit;
    Arr := TJSONArray(Root);
    for I := 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[I] is TJSONObject) then
        Continue;
      Obj := TJSONObject(Arr.Items[I]);
      S := DefaultNetSession;
      S.Name := SanitizeSessionName(JsonStr(Obj, 'name', ''));
      if (S.Name = '') or (IndexOfName(S.Name) >= 0) then
        Continue;
      if not NetSchemeProtocol(JsonStr(Obj, 'protocol', 'ftp'), Proto) then
        Continue;
      S.Protocol := Proto;
      S.Host := JsonStr(Obj, 'host', '');
      S.Port := JsonInt(Obj, 'port', 0);
      S.User := JsonStr(Obj, 'user', '');
      S.Auth := NetAuthFromName(JsonStr(Obj, 'auth', 'password'));
      S.KeyFile := JsonStr(Obj, 'keyFile', '');
      S.RootPath := JsonStr(Obj, 'root', '/');
      S.Proxy := JsonStr(Obj, 'proxy', '');
      S.Encoding := JsonStr(Obj, 'encoding', '');
      S.Region := JsonStr(Obj, 'region', '');
      S.Endpoint := JsonStr(Obj, 'endpoint', '');
      S.PathStyle := JsonBool(Obj, 'pathStyle', True);
      S.Passive := JsonBool(Obj, 'passive', True);
      S.ImplicitTls := JsonBool(Obj, 'implicitTls', False);
      S.VerifyCert := JsonBool(Obj, 'verifyCert', True);
      S.TimeoutSec := JsonInt(Obj, 'timeout', 30);
      S.HostKeySha256 := JsonStr(Obj, 'hostKey', '');
      S.SavePassword := JsonBool(Obj, 'savePassword', False);
      Sealed := JsonStr(Obj, 'pass', '');
      if (Sealed <> '') and UnprotectSecret(Sealed, Plain) then
        S.Password := Plain;
      Sealed := JsonStr(Obj, 'keyPass', '');
      if (Sealed <> '') and UnprotectSecret(Sealed, Plain) then
        S.KeyPassphrase := Plain;
      FItems.Add(S);
    end;
  finally
    Root.Free;
  end;
end;

function TNetSessionStore.ToJson: string;
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  S: TNetSession;
  Sealed: string;
begin
  Arr := TJSONArray.Create;
  try
    for S in FItems do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('name', S.Name);
      Obj.AddPair('protocol', NetProtocolScheme(S.Protocol));
      Obj.AddPair('host', S.Host);
      Obj.AddPair('port', TJSONNumber.Create(S.Port));
      Obj.AddPair('user', S.User);
      Obj.AddPair('auth', NetAuthName(S.Auth));
      Obj.AddPair('keyFile', S.KeyFile);
      Obj.AddPair('root', S.RootPath);
      Obj.AddPair('proxy', S.Proxy);
      Obj.AddPair('encoding', S.Encoding);
      Obj.AddPair('region', S.Region);
      Obj.AddPair('endpoint', S.Endpoint);
      Obj.AddPair('pathStyle', TJSONBool.Create(S.PathStyle));
      Obj.AddPair('passive', TJSONBool.Create(S.Passive));
      Obj.AddPair('implicitTls', TJSONBool.Create(S.ImplicitTls));
      Obj.AddPair('verifyCert', TJSONBool.Create(S.VerifyCert));
      Obj.AddPair('timeout', TJSONNumber.Create(S.TimeoutSec));
      Obj.AddPair('hostKey', S.HostKeySha256);
      Obj.AddPair('savePassword', TJSONBool.Create(S.SavePassword));
      if S.SavePassword and SecretsAvailable then
      begin
        if S.Password <> '' then
        begin
          Sealed := ProtectSecret(S.Password);
          if Sealed <> '' then
            Obj.AddPair('pass', Sealed);
        end;
        if S.KeyPassphrase <> '' then
        begin
          Sealed := ProtectSecret(S.KeyPassphrase);
          if Sealed <> '' then
            Obj.AddPair('keyPass', Sealed);
        end;
      end;
      Arr.AddElement(Obj);
    end;
    Result := Arr.ToJSON;
  finally
    Arr.Free;
  end;
end;

end.
