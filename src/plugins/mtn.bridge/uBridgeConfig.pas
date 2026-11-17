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
  /// <summary>How the messages reach the server: one JSON message per line over the
  /// stdin and stdout of a program, or one HTTP POST per message to a URL.</summary>
  TBridgeTransport = (btStdio, btHttp);

  TBridgeServerConfig = record
    Name: string;
    Transport: TBridgeTransport;
    /// <summary>btStdio: the program.</summary>
    Command: string;
    Args: TArray<string>;
    /// <summary>Working folder; '' = the folder of the host.</summary>
    Dir: string;
    /// <summary>Extra "NAME=VALUE" environment entries.</summary>
    Env: TArray<string>;
    /// <summary>btHttp: the address the messages are posted to (http:// or https://).</summary>
    Url: string;
    /// <summary>btHttp: extra "NAME=VALUE" request headers.</summary>
    Headers: TArray<string>;
    StartTimeoutMs: Integer;
    /// <summary>The tools the server may offer; empty = all of them.</summary>
    Allow: TArray<string>;
  end;

/// <summary>Parses the settings value. False with AError set when the list is not valid;
/// AServers then holds nothing.</summary>
function ParseBridgeServers(const AJson: string; out AServers: TArray<TBridgeServerConfig>;
  out AError: string): Boolean;

/// <summary>The settings value of a list: what ParseBridgeServers reads back.</summary>
function BridgeServersToJson(const AServers: TArray<TBridgeServerConfig>): string;

/// <summary>Checks one entry the way the settings list does: the name, the transport
/// fields that belong together and the values that end up in a command line or a header.</summary>
function ValidateBridgeServer(const AServer: TBridgeServerConfig; out AError: string): Boolean;

/// <summary>True for an http:// or https:// address with a host and no blanks.</summary>
function BridgeUrlValid(const AUrl: string): Boolean;

/// <summary>One line for a list: the program with its arguments, or the URL.</summary>
function BridgeTargetText(const AServer: TBridgeServerConfig): string;

/// <summary>Cuts a line into words: blanks separate them and double quotes group them, with
/// the backslash rules of a Windows command line (a backslash counts only before a quote).</summary>
function BridgeSplitWords(const AText: string): TArray<string>;

/// <summary>The line that BridgeSplitWords turns back into the same words.</summary>
function BridgeJoinWords(const AWords: TArray<string>): string;

/// <summary>What the user sees when asked to approve a server: for a program, the command
/// line with arguments, folder and environment, every argument in quotes when it needs them;
/// for an address, the URL and the headers.</summary>
function BridgeCommandText(const AServer: TBridgeServerConfig): string;

/// <summary>A fingerprint of everything that decides what the server runs.</summary>
function BridgeConsentKey(const AServer: TBridgeServerConfig): string;

/// <summary>Approvals are stored as a JSON object: server name -> consent key.</summary>
function BridgeIsApproved(const AApprovalsJson: string; const AServer: TBridgeServerConfig): Boolean;
function BridgeWithApproval(const AApprovalsJson: string; const AServer: TBridgeServerConfig): string;

function BridgeToolAllowed(const AServer: TBridgeServerConfig; const ATool: string): Boolean;

implementation

uses
  System.JSON, System.Hash, System.StrUtils, System.Generics.Collections;

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

// A JSON object of strings as "NAME=VALUE" entries; used for the environment and the headers.
function ReadPairs(AValue: TJSONValue; out AList: TArray<string>): Boolean;
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

function BridgeUrlValid(const AUrl: string): Boolean;
var
  Rest, Host: string;
  P: Integer;
  C: Char;
begin
  Result := False;
  if (AUrl = '') or (Length(AUrl) > 2048) then
    Exit;
  for C in AUrl do
    if (C <= ' ') or (C = #127) then
      Exit;
  if StartsText('http://', AUrl) then
    Rest := Copy(AUrl, 8, MaxInt)
  else if StartsText('https://', AUrl) then
    Rest := Copy(AUrl, 9, MaxInt)
  else
    Exit;
  P := 1;
  while (P <= Length(Rest)) and not CharInSet(Rest[P], ['/', '?', '#']) do
    Inc(P);
  Host := Copy(Rest, 1, P - 1);
  // "user@host" credentials do not belong in an address that is shown and stored as text.
  Result := (Host <> '') and (Pos('@', Host) = 0) and (Host[1] <> ':');
end;

function HasLineBreak(const AText: string): Boolean;
begin
  Result := (Pos(#10, AText) > 0) or (Pos(#13, AText) > 0) or (Pos(#0, AText) > 0);
end;

function PairsClean(const AList: TArray<string>): Boolean;
var
  S: string;
begin
  for S in AList do
    if HasLineBreak(S) then
      Exit(False);
  Result := True;
end;

// "NAME=VALUE" with a name made of the characters an HTTP header name may have.
function HeadersWellFormed(const AList: TArray<string>): Boolean;
var
  S: string;
  P, I: Integer;
begin
  for S in AList do
  begin
    P := Pos('=', S);
    if P < 2 then
      Exit(False);
    for I := 1 to P - 1 do
      if not CharInSet(S[I], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.']) then
        Exit(False);
  end;
  Result := True;
end;

// "NAME=VALUE" with a non-empty name.
function EnvWellFormed(const AList: TArray<string>): Boolean;
var
  S: string;
begin
  for S in AList do
    if Pos('=', S) < 2 then
      Exit(False);
  Result := True;
end;

function ValidateBridgeServer(const AServer: TBridgeServerConfig; out AError: string): Boolean;
var
  Where: string;
begin
  Result := False;
  AError := '';
  if not ValidName(AServer.Name) then
  begin
    AError := 'bad server name "' + AServer.Name + '" (a-z, 0-9, _ and -, up to 32 characters)';
    Exit;
  end;
  Where := 'server "' + AServer.Name + '"';
  if AServer.Transport = btHttp then
  begin
    if (AServer.Command <> '') or (Length(AServer.Args) > 0) or (AServer.Dir <> '') or
       (Length(AServer.Env) > 0) then
      AError := Where + ' has a url, so it cannot have a command, args, cwd or env'
    else if not BridgeUrlValid(AServer.Url) then
      AError := Where + ' needs an http:// or https:// url with a host and no user name'
    else if not PairsClean(AServer.Headers) or not HeadersWellFormed(AServer.Headers) then
      AError := Where + ': a header is NAME=VALUE with a plain name and no line break';
  end
  else
  begin
    if AServer.Url <> '' then
      AError := Where + ' has a command, so it cannot have a url'
    else if Length(AServer.Headers) > 0 then
      AError := Where + ' has a command, so it cannot have headers'
    else if Trim(AServer.Command) = '' then
      AError := Where + ' has no command'
    else if HasLineBreak(AServer.Command) or not PairsClean(AServer.Args) or
            not PairsClean(AServer.Env) then
      AError := Where + ': the command line cannot contain a line break'
    else if not EnvWellFormed(AServer.Env) then
      AError := Where + ': an environment entry is NAME=VALUE';
  end;
  Result := AError = '';
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
  AServer.Command := Trim(Obj.GetValue<string>('command', ''));
  AServer.Url := Trim(Obj.GetValue<string>('url', ''));
  if AServer.Url <> '' then
    AServer.Transport := btHttp;
  AServer.Dir := Obj.GetValue<string>('cwd', '');
  Timeout := Obj.GetValue<Integer>('startTimeoutMs', cDefaultStartTimeoutMs);
  if Timeout < cMinStartTimeoutMs then
    Timeout := cMinStartTimeoutMs;
  if Timeout > cMaxStartTimeoutMs then
    Timeout := cMaxStartTimeoutMs;
  AServer.StartTimeoutMs := Timeout;
  if not ReadStrings(Obj.GetValue('args'), AServer.Args) or
     not ReadStrings(Obj.GetValue('allow'), AServer.Allow) or
     not ReadPairs(Obj.GetValue('env'), AServer.Env) or
     not ReadPairs(Obj.GetValue('headers'), AServer.Headers) then
  begin
    AError := 'server "' + AServer.Name + '": args and allow must be lists of strings, ' +
      'env and headers objects of strings';
    Exit;
  end;
  Result := ValidateBridgeServer(AServer, AError);
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

function PairsToJson(const AList: TArray<string>): TJSONObject;
var
  S: string;
  P: Integer;
begin
  Result := TJSONObject.Create;
  for S in AList do
  begin
    P := Pos('=', S);
    if P > 0 then
      Result.AddPair(Copy(S, 1, P - 1), Copy(S, P + 1, MaxInt));
  end;
end;

function StringsToJson(const AList: TArray<string>): TJSONArray;
var
  S: string;
begin
  Result := TJSONArray.Create;
  for S in AList do
    Result.Add(S);
end;

function BridgeServersToJson(const AServers: TArray<TBridgeServerConfig>): string;
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  S: TBridgeServerConfig;
begin
  Arr := TJSONArray.Create;
  try
    for S in AServers do
    begin
      Obj := TJSONObject.Create;
      Arr.AddElement(Obj);
      Obj.AddPair('name', S.Name);
      if S.Transport = btHttp then
      begin
        Obj.AddPair('url', S.Url);
        if Length(S.Headers) > 0 then
          Obj.AddPair('headers', PairsToJson(S.Headers));
      end
      else
      begin
        Obj.AddPair('command', S.Command);
        if Length(S.Args) > 0 then
          Obj.AddPair('args', StringsToJson(S.Args));
        if S.Dir <> '' then
          Obj.AddPair('cwd', S.Dir);
        if Length(S.Env) > 0 then
          Obj.AddPair('env', PairsToJson(S.Env));
      end;
      if S.StartTimeoutMs <> cDefaultStartTimeoutMs then
        Obj.AddPair('startTimeoutMs', TJSONNumber.Create(S.StartTimeoutMs));
      if Length(S.Allow) > 0 then
        Obj.AddPair('allow', StringsToJson(S.Allow));
    end;
    Result := Arr.ToJSON;
  finally
    Arr.Free;
  end;
end;

// A word the way BridgeSplitWords reads it: quotes only when it needs them, a quote escaped
// by a backslash, and the backslashes before a quote doubled.
function Quoted(const AText: string): string;
var
  I, Slashes: Integer;
  C: Char;
begin
  if (AText <> '') and (Pos(' ', AText) = 0) and (Pos(#9, AText) = 0) and (Pos('"', AText) = 0) then
    Exit(AText);
  Result := '"';
  Slashes := 0;
  for I := 1 to Length(AText) do
  begin
    C := AText[I];
    if C = '\' then
      Inc(Slashes)
    else
    begin
      if C = '"' then
        Result := Result + StringOfChar('\', Slashes * 2 + 1)
      else
        Result := Result + StringOfChar('\', Slashes);
      Result := Result + C;
      Slashes := 0;
    end;
  end;
  Result := Result + StringOfChar('\', Slashes * 2) + '"';
end;

function BridgeJoinWords(const AWords: TArray<string>): string;
var
  W: string;
begin
  Result := '';
  for W in AWords do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Quoted(W);
  end;
end;

function BridgeSplitWords(const AText: string): TArray<string>;
var
  I, N, Slashes: Integer;
  Word: string;
  InWord, InQuote: Boolean;
  C: Char;

  procedure Emit;
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Word;
    Word := '';
    InWord := False;
    InQuote := False;
  end;

begin
  SetLength(Result, 0);
  Word := '';
  InWord := False;
  InQuote := False;
  I := 1;
  N := Length(AText);
  while I <= N do
  begin
    C := AText[I];
    if C = '\' then
    begin
      Slashes := 0;
      while (I <= N) and (AText[I] = '\') do
      begin
        Inc(Slashes);
        Inc(I);
      end;
      InWord := True;
      if (I <= N) and (AText[I] = '"') then
      begin
        Word := Word + StringOfChar('\', Slashes div 2);
        if Odd(Slashes) then
          Word := Word + '"'
        else
          InQuote := not InQuote;
        Inc(I);
      end
      else
        Word := Word + StringOfChar('\', Slashes);
      Continue;
    end;
    if C = '"' then
    begin
      InWord := True;
      InQuote := not InQuote;
    end
    else if ((C = ' ') or (C = #9)) and not InQuote then
    begin
      if InWord then
        Emit;
    end
    else
    begin
      InWord := True;
      Word := Word + C;
    end;
    Inc(I);
  end;
  if InWord then
    Emit;
end;

function BridgeTargetText(const AServer: TBridgeServerConfig): string;
begin
  if AServer.Transport = btHttp then
    Result := AServer.Url
  else
    Result := Trim(Quoted(AServer.Command) + ' ' + BridgeJoinWords(AServer.Args));
end;

function BridgeCommandText(const AServer: TBridgeServerConfig): string;
var
  Arg, Entry: string;
begin
  if AServer.Transport = btHttp then
  begin
    Result := 'POST ' + AServer.Url;
    for Entry in AServer.Headers do
      Result := Result + sLineBreak + 'header ' + Entry;
    Exit;
  end;
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
begin
  if AServer.Transport = btHttp then
    Env := Copy(AServer.Headers)
  else
    Env := Copy(AServer.Env);
  TArray.Sort<string>(Env);
  Canon := TJSONObject.Create;
  try
    // A program keeps the fingerprint it always had, so approvals given earlier stay valid.
    if AServer.Transport = btHttp then
    begin
      Canon.AddPair('url', AServer.Url);
      Canon.AddPair('headers', StringsToJson(Env));
    end
    else
    begin
      Canon.AddPair('command', AServer.Command);
      Canon.AddPair('args', StringsToJson(AServer.Args));
      Canon.AddPair('cwd', AServer.Dir);
      Canon.AddPair('env', StringsToJson(Env));
    end;
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
