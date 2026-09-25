unit uSshConnections;

{ Saved SSH/SFTP connection profiles (server/login accounts), shared by the
  SSH console (uShellProfiles.pas, profile id "ssh:<id>") and the sftp://
  VFS provider (uSftpVfs.pas). One JSON store (sshconnections.json), same
  storage pattern as uWorkspaceLibrary.pas (workspaces.json).

  No passwords are stored -- only an optional IdentityFile path. Auth falls
  back to ssh-agent / ~/.ssh/config / default key files, exactly like a
  manually typed `ssh user@host` would. }

interface

uses
  System.SysUtils, System.Classes;

type
  TSshConnection = record
    Id: string;
    Name: string;
    Host: string;
    Port: Integer;         // 0 = default (22)
    User: string;
    IdentityFile: string;  // '' = rely on ssh-agent / ~/.ssh/config / default keys
  end;

function SshConnectionsGet: TArray<TSshConnection>;
function SshConnectionsFindById(const AId: string; out AConn: TSshConnection): Boolean;
/// <summary>Best-effort match by host/port/user, used to recover a saved
/// IdentityFile for a "sftp://user@host:port/path" URI that was typed
/// directly rather than opened via the Connections dialog. No match is not
/// an error -- callers fall back to ssh-agent / ~/.ssh/config, same as a
/// bare `ssh user@host` typed by hand.</summary>
function SshConnectionsFindByTarget(const AHost: string; APort: Integer;
  const AUser: string; out AConn: TSshConnection): Boolean;
function SshConnectionAdd(const AName, AHost: string; APort: Integer;
  const AUser, AIdentityFile: string): TSshConnection;
function SshConnectionUpdate(const AConn: TSshConnection): Boolean;
function SshConnectionDelete(const AId: string): Boolean;
function SshConnectionDisplayLabel(const AConn: TSshConnection): string;
/// <summary>"[user@]host[:port]" -- the uVfsTypes.pas sftp:// authority
/// component for this connection (see MakeSftpUri).</summary>
function SshConnectionAuthority(const AConn: TSshConnection): string;

/// <summary>Builds the ssh.exe/sftp.exe host argument list shared by both
/// consumers: ['-p'/'​-P', port] (if Port &lt;&gt; 0), ['-i', identity] (if set).
/// AHostArg is always appended last as "user@host" (or just "host" if User
/// is empty). APortFlag is '-p' for ssh.exe, '-P' for sftp.exe (they differ).</summary>
function SshConnectionArgs(const AConn: TSshConnection; const APortFlag: string): TArray<string>;

procedure SshConnectionsUsePath(const APath: string);
procedure SshConnectionsResetForTests;

implementation

uses
  System.IOUtils, System.JSON, System.Generics.Collections, uConfigLocation;

const
  cFileName = 'sshconnections.json';

var
  GLoaded: Boolean = False;
  GItems: TList<TSshConnection>;
  GStoragePathOverride: string;

function StoragePath: string;
begin
  if GStoragePathOverride <> '' then
    Exit(GStoragePathOverride);
  Result := GetConfigFilePath(cFileName);
end;

procedure EnsureList;
begin
  if GItems = nil then
    GItems := TList<TSshConnection>.Create;
end;

function NewConnectionId: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := LowerCase(Copy(GUIDToString(G), 2, 36));
end;

function ConnFromJson(Obj: TJSONObject): TSshConnection;
var
  PortVal: Integer;
begin
  Result := Default(TSshConnection);
  if Obj = nil then
    Exit;
  if not Obj.TryGetValue<string>('id', Result.Id) then
    Result.Id := '';
  Result.Id := Trim(Result.Id);
  if not Obj.TryGetValue<string>('name', Result.Name) then
    Result.Name := Result.Id;
  Result.Name := Trim(Result.Name);
  if not Obj.TryGetValue<string>('host', Result.Host) then
    Result.Host := '';
  Result.Host := Trim(Result.Host);
  if not Obj.TryGetValue<Integer>('port', PortVal) then
    PortVal := 0;
  Result.Port := PortVal;
  if not Obj.TryGetValue<string>('user', Result.User) then
    Result.User := '';
  Result.User := Trim(Result.User);
  if not Obj.TryGetValue<string>('identityFile', Result.IdentityFile) then
    Result.IdentityFile := '';
end;

function ConnToJson(const AConn: TSshConnection): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', AConn.Id);
  Result.AddPair('name', AConn.Name);
  Result.AddPair('host', AConn.Host);
  Result.AddPair('port', TJSONNumber.Create(AConn.Port));
  Result.AddPair('user', AConn.User);
  if AConn.IdentityFile <> '' then
    Result.AddPair('identityFile', AConn.IdentityFile);
end;

procedure SaveLocked;
var
  Path: string;
  Root: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  if GItems = nil then
    Exit;
  Path := StoragePath;
  Root := TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(1));
    Arr := TJSONArray.Create;
    Root.AddPair('items', Arr);
    for I := 0 to GItems.Count - 1 do
      Arr.AddElement(ConnToJson(GItems[I]));
    ForceDirectories(ExtractFilePath(Path));
    TFile.WriteAllText(Path, Root.ToJSON, TEncoding.UTF8);
  finally
    Root.Free;
  end;
end;

procedure EnsureLoaded;
var
  Path, Content: string;
  RootVal: TJSONValue;
  Root: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  Conn: TSshConnection;
begin
  if GLoaded then
    Exit;
  GLoaded := True;
  EnsureList;
  GItems.Clear;
  Path := StoragePath;
  if not TFile.Exists(Path) then
    Exit;
  try
    Content := TFile.ReadAllText(Path, TEncoding.UTF8);
    RootVal := TJSONObject.ParseJSONValue(Content);
    if not (RootVal is TJSONObject) then
    begin
      RootVal.Free;
      Exit;
    end;
    Root := TJSONObject(RootVal);
    try
      if not Root.TryGetValue<TJSONArray>('items', Arr) then
        Exit;
      for I := 0 to Arr.Count - 1 do
      begin
        if not (Arr.Items[I] is TJSONObject) then
          Continue;
        Conn := ConnFromJson(TJSONObject(Arr.Items[I]));
        if (Conn.Id = '') or (Conn.Host = '') then
          Continue;
        GItems.Add(Conn);
      end;
    finally
      Root.Free;
    end;
  except
    GItems.Clear;
  end;
end;

function SshConnectionsGet: TArray<TSshConnection>;
begin
  EnsureLoaded;
  Result := GItems.ToArray;
end;

function SshConnectionsFindById(const AId: string; out AConn: TSshConnection): Boolean;
var
  I: Integer;
begin
  EnsureLoaded;
  for I := 0 to GItems.Count - 1 do
    if SameText(GItems[I].Id, AId) then
    begin
      AConn := GItems[I];
      Exit(True);
    end;
  Result := False;
end;

function SshConnectionsFindByTarget(const AHost: string; APort: Integer;
  const AUser: string; out AConn: TSshConnection): Boolean;
var
  I: Integer;
  EffPort: Integer;
begin
  EnsureLoaded;
  for I := 0 to GItems.Count - 1 do
  begin
    EffPort := GItems[I].Port;
    if EffPort = 0 then
      EffPort := 22;
    if SameText(GItems[I].Host, AHost) and (EffPort = APort) and
       SameText(GItems[I].User, AUser) then
    begin
      AConn := GItems[I];
      Exit(True);
    end;
  end;
  Result := False;
end;

function SshConnectionAdd(const AName, AHost: string; APort: Integer;
  const AUser, AIdentityFile: string): TSshConnection;
begin
  EnsureLoaded;
  Result := Default(TSshConnection);
  Result.Id := NewConnectionId;
  Result.Name := Trim(AName);
  if Result.Name = '' then
    Result.Name := Trim(AHost);
  Result.Host := Trim(AHost);
  Result.Port := APort;
  Result.User := Trim(AUser);
  Result.IdentityFile := Trim(AIdentityFile);
  GItems.Add(Result);
  SaveLocked;
end;

function SshConnectionUpdate(const AConn: TSshConnection): Boolean;
var
  I: Integer;
begin
  EnsureLoaded;
  for I := 0 to GItems.Count - 1 do
    if SameText(GItems[I].Id, AConn.Id) then
    begin
      GItems[I] := AConn;
      SaveLocked;
      Exit(True);
    end;
  Result := False;
end;

function SshConnectionDelete(const AId: string): Boolean;
var
  I: Integer;
begin
  EnsureLoaded;
  for I := 0 to GItems.Count - 1 do
    if SameText(GItems[I].Id, AId) then
    begin
      GItems.Delete(I);
      SaveLocked;
      Exit(True);
    end;
  Result := False;
end;

function SshConnectionDisplayLabel(const AConn: TSshConnection): string;
var
  Target: string;
begin
  if AConn.User <> '' then
    Target := AConn.User + '@' + AConn.Host
  else
    Target := AConn.Host;
  if AConn.Port <> 0 then
    Target := Target + ':' + IntToStr(AConn.Port);
  Result := AConn.Name + '  (' + Target + ')';
end;

function SshConnectionAuthority(const AConn: TSshConnection): string;
begin
  if AConn.User <> '' then
    Result := AConn.User + '@' + AConn.Host
  else
    Result := AConn.Host;
  if AConn.Port <> 0 then
    Result := Result + ':' + IntToStr(AConn.Port);
end;

function SshConnectionArgs(const AConn: TSshConnection; const APortFlag: string): TArray<string>;
var
  N: Integer;
  HostArg: string;
begin
  SetLength(Result, 0);
  N := 0;
  if AConn.Port <> 0 then
  begin
    SetLength(Result, N + 2);
    Result[N] := APortFlag;
    Result[N + 1] := IntToStr(AConn.Port);
    Inc(N, 2);
  end;
  if AConn.IdentityFile <> '' then
  begin
    SetLength(Result, N + 2);
    Result[N] := '-i';
    Result[N + 1] := AConn.IdentityFile;
    Inc(N, 2);
  end;
  if AConn.User <> '' then
    HostArg := AConn.User + '@' + AConn.Host
  else
    HostArg := AConn.Host;
  SetLength(Result, N + 1);
  Result[N] := HostArg;
end;

procedure SshConnectionsUsePath(const APath: string);
begin
  GStoragePathOverride := APath;
  GLoaded := False;
end;

procedure SshConnectionsResetForTests;
begin
  GStoragePathOverride := '';
  GLoaded := False;
  if GItems <> nil then
    GItems.Clear;
end;

initialization

finalization
  FreeAndNil(GItems);

end.
