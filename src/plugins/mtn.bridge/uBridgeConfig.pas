unit uBridgeConfig;

{ The server list of mtn.bridge: the JSON the user keeps in the plugin settings, the
  checks it must pass, and the consent record. A server runs only when the user approved
  its exact command line; a changed command needs a new approval. Nothing here reads
  search results, file names or documents: the list comes from the settings alone. }

interface

uses
  System.SysUtils;

const
  cDefaultStartTimeoutMs = 10000;
  cMinStartTimeoutMs = 1000;
  cMaxStartTimeoutMs = 60000;
  cMaxServers = 16;
  cMaxServerNameLength = 32;

type
  TBridgeServerConfig = record
    Name: string;
    Command: string;
    Args: TArray<string>;
    /// <summary>Working folder; '' = the folder of the host.</summary>
    Dir: string;
    /// <summary>Extra "NAME=VALUE" environment entries.</summary>
    Env: TArray<string>;
    StartTimeoutMs: Integer;
    /// <summary>The tools the server may offer; empty = all of them.</summary>
    Allow: TArray<string>;
  end;

/// <summary>Parses the settings value. False with AError set when the list is not valid;
/// AServers then holds nothing.</summary>
function ParseBridgeServers(const AJson: string; out AServers: TArray<TBridgeServerConfig>;
  out AError: string): Boolean;

/// <summary>The command line as the user sees it when asked to approve it: program,
/// arguments, folder and environment, every argument in quotes when it needs them.</summary>
function BridgeCommandText(const AServer: TBridgeServerConfig): string;

/// <summary>A fingerprint of everything that decides what the server runs.</summary>
function BridgeConsentKey(const AServer: TBridgeServerConfig): string;

/// <summary>Approvals are stored as a JSON object: server name -> consent key.</summary>
function BridgeIsApproved(const AApprovalsJson: string; const AServer: TBridgeServerConfig): Boolean;
function BridgeWithApproval(const AApprovalsJson: string; const AServer: TBridgeServerConfig): string;

function BridgeToolAllowed(const AServer: TBridgeServerConfig; const ATool: string): Boolean;

implementation

uses
  System.JSON, System.Hash, System.Generics.Collections;

function ValidName(const AName: string): Boolean;
var
  C: Char;
begin
  Result := (AName <> '') and (Length(AName) <= cMaxServerNameLength);
  if Result then
    for C in AName do
      if not CharInSet(C, ['a'..'z', '0'..'9', '_', '-']) then
        Exit(False);
end;

function ReadStrings(AValue: TJSONValue; out AList: TArray<string>): Boolean;
var
  I: Integer;
begin
  SetLength(AList, 0);
  if AValue = nil then
    Exit(True);
  if not (AValue is TJSONArray) then
    Exit(False);
  for I := 0 to TJSONArray(AValue).Count - 1 do
  begin
    if not (TJSONArray(AValue).Items[I] is TJSONString) then
      Exit(False);
    SetLength(AList, Length(AList) + 1);
    AList[High(AList)] := TJSONArray(AValue).Items[I].Value;
  end;
  Result := True;
end;

function ReadEnv(AValue: TJSONValue; out AList: TArray<string>): Boolean;
var
  Pair: TJSONPair;
begin
  SetLength(AList, 0);
  if AValue = nil then
    Exit(True);
  if not (AValue is TJSONObject) then
    Exit(False);
  for Pair in TJSONObject(AValue) do
  begin
    if (Pair.JsonString.Value = '') or (Pos('=', Pair.JsonString.Value) > 0) or
       not (Pair.JsonValue is TJSONString) then
      Exit(False);
    SetLength(AList, Length(AList) + 1);
    AList[High(AList)] := Pair.JsonString.Value + '=' + Pair.JsonValue.Value;
  end;
  Result := True;
end;

function ReadServer(AItem: TJSONValue; out AServer: TBridgeServerConfig;
  out AError: string): Boolean;
var
  Obj: TJSONObject;
  Timeout: Integer;
begin
  Result := False;
  AServer := Default(TBridgeServerConfig);
  if not (AItem is TJSONObject) then
  begin
    AError := 'a server entry is not an object';
    Exit;
  end;
  Obj := TJSONObject(AItem);
  AServer.Name := Obj.GetValue<string>('name', '');
  if not ValidName(AServer.Name) then
  begin
    AError := 'bad server name "' + AServer.Name + '" (a-z, 0-9, _ and -, up to 32 characters)';
    Exit;
  end;
  AServer.Command := Trim(Obj.GetValue<string>('command', ''));
  if AServer.Command = '' then
  begin
    AError := 'server "' + AServer.Name + '" has no command';
    Exit;
  end;
  AServer.Dir := Obj.GetValue<string>('cwd', '');
  Timeout := Obj.GetValue<Integer>('startTimeoutMs', cDefaultStartTimeoutMs);
  if Timeout < cMinStartTimeoutMs then
    Timeout := cMinStartTimeoutMs;
  if Timeout > cMaxStartTimeoutMs then
    Timeout := cMaxStartTimeoutMs;
  AServer.StartTimeoutMs := Timeout;
  if not ReadStrings(Obj.GetValue('args'), AServer.Args) or
     not ReadStrings(Obj.GetValue('allow'), AServer.Allow) or
     not ReadEnv(Obj.GetValue('env'), AServer.Env) then
  begin
    AError := 'server "' + AServer.Name + '": args, allow and env must be strings';
    Exit;
  end;
  Result := True;
end;

function ParseBridgeServers(const AJson: string; out AServers: TArray<TBridgeServerConfig>;
  out AError: string): Boolean;
var
  Root: TJSONValue;
  I, J: Integer;
  Server: TBridgeServerConfig;
begin
  Result := False;
  SetLength(AServers, 0);
  AError := '';
  if Trim(AJson) = '' then
    Exit(True);
  Root := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Root is TJSONArray) then
    begin
      AError := 'the server list is not a JSON array';
      Exit;
    end;
    if TJSONArray(Root).Count > cMaxServers then
    begin
      AError := 'too many servers';
      Exit;
    end;
    for I := 0 to TJSONArray(Root).Count - 1 do
    begin
      if not ReadServer(TJSONArray(Root).Items[I], Server, AError) then
      begin
        SetLength(AServers, 0);
        Exit;
      end;
      for J := 0 to High(AServers) do
        if AServers[J].Name = Server.Name then
        begin
          AError := 'server name "' + Server.Name + '" is used twice';
          SetLength(AServers, 0);
          Exit;
        end;
      SetLength(AServers, Length(AServers) + 1);
      AServers[High(AServers)] := Server;
    end;
    Result := True;
  finally
    Root.Free;
  end;
end;

function Quoted(const AText: string): string;
begin
  if (AText = '') or (Pos(' ', AText) > 0) or (Pos('"', AText) > 0) then
    Result := '"' + StringReplace(AText, '"', '\"', [rfReplaceAll]) + '"'
  else
    Result := AText;
end;

function BridgeCommandText(const AServer: TBridgeServerConfig): string;
var
  Arg, Entry: string;
begin
  Result := Quoted(AServer.Command);
  for Arg in AServer.Args do
    Result := Result + ' ' + Quoted(Arg);
  if AServer.Dir <> '' then
    Result := Result + sLineBreak + 'in ' + Quoted(AServer.Dir);
  for Entry in AServer.Env do
    Result := Result + sLineBreak + 'env ' + Entry;
end;

function BridgeConsentKey(const AServer: TBridgeServerConfig): string;
var
  Env: TArray<string>;
  Canon: TJSONObject;
  Args, EnvArr: TJSONArray;
  S: string;
begin
  Env := Copy(AServer.Env);
  TArray.Sort<string>(Env);
  Canon := TJSONObject.Create;
  try
    Canon.AddPair('command', AServer.Command);
    Args := TJSONArray.Create;
    for S in AServer.Args do
      Args.Add(S);
    Canon.AddPair('args', Args);
    Canon.AddPair('cwd', AServer.Dir);
    EnvArr := TJSONArray.Create;
    for S in Env do
      EnvArr.Add(S);
    Canon.AddPair('env', EnvArr);
    Result := THashSHA2.GetHashString(Canon.ToJSON, SHA256);
  finally
    Canon.Free;
  end;
end;

function BridgeIsApproved(const AApprovalsJson: string; const AServer: TBridgeServerConfig): Boolean;
var
  Root: TJSONValue;
begin
  Result := False;
  Root := TJSONObject.ParseJSONValue(AApprovalsJson);
  try
    if Root is TJSONObject then
      Result := TJSONObject(Root).GetValue<string>(AServer.Name, '') = BridgeConsentKey(AServer);
  finally
    Root.Free;
  end;
end;

function BridgeWithApproval(const AApprovalsJson: string; const AServer: TBridgeServerConfig): string;
var
  Root: TJSONValue;
  Obj: TJSONObject;
begin
  Root := TJSONObject.ParseJSONValue(AApprovalsJson);
  try
    if Root is TJSONObject then
    begin
      Obj := TJSONObject(Root);
      Obj.RemovePair(AServer.Name).Free;
      Obj.AddPair(AServer.Name, BridgeConsentKey(AServer));
      Result := Obj.ToJSON;
    end
    else
    begin
      Obj := TJSONObject.Create;
      try
        Obj.AddPair(AServer.Name, BridgeConsentKey(AServer));
        Result := Obj.ToJSON;
      finally
        Obj.Free;
      end;
    end;
  finally
    Root.Free;
  end;
end;

function BridgeToolAllowed(const AServer: TBridgeServerConfig; const ATool: string): Boolean;
var
  S: string;
begin
  if Length(AServer.Allow) = 0 then
    Exit(True);
  for S in AServer.Allow do
    if SameText(S, ATool) then
      Exit(True);
  Result := False;
end;

end.
