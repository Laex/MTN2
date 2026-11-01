unit uGitMarks;

{ Per-file git state of one folder for the name colors in the panels: which rows
  of the folder are staged, changed, new or in conflict. A folder row takes the
  most urgent state of what changed inside it. }

interface

uses
  System.SysUtils;

/// <summary>JSON object name -> role ("ok" staged, "warn" changed, "info" new,
/// "error" conflict) for the rows of the folder whose path from the working tree
/// root is APrefix ("" at the root, "sub/dir/" otherwise). AStatusZ is the output
/// of "git status --porcelain=v1 -z".</summary>
function GitMarksJson(const AStatusZ, APrefix: string): string;

/// <summary>The marks of ADir; False when it is not in a working tree or git did
/// not answer.</summary>
function ReadGitMarks(const ADir: string; const ACancelled: TFunc<Boolean>;
  out AJson: string): Boolean;

/// <summary>The folders of both panels in the JSON of the host's PanelInfo (local
/// "file:" folders only, without duplicates).</summary>
function PanelFolderUris(const APanelInfoJson: string): TArray<string>;

implementation

uses
  System.Classes, System.JSON, System.Generics.Collections, uGitRepo;

function Severity(const ARole: string): Integer;
begin
  if ARole = 'error' then
    Result := 4
  else if ARole = 'warn' then
    Result := 3
  else if ARole = 'ok' then
    Result := 2
  else if ARole = 'info' then
    Result := 1
  else
    Result := 0;
end;

function RoleOf(X, Y: Char): string;
begin
  if (X = 'U') or (Y = 'U') or ((X = 'A') and (Y = 'A')) or ((X = 'D') and (Y = 'D')) then
    Exit('error');
  if (X = '?') and (Y = '?') then
    Exit('info');
  if (X = '!') and (Y = '!') then
    Exit('');
  if Y <> ' ' then
    Exit('warn');
  if X <> ' ' then
    Exit('ok');
  Result := '';
end;

function GitMarksJson(const AStatusZ, APrefix: string): string;
var
  Tokens: TArray<string>;
  Roles: TDictionary<string, string>;
  Obj: TJSONObject;
  Token, Path, Role, Name, Old: string;
  I, Slash: Integer;
  Pair: TPair<string, string>;
begin
  Roles := TDictionary<string, string>.Create;
  try
    Tokens := AStatusZ.Split([#0]);
    I := 0;
    while I < Length(Tokens) do
    begin
      Token := Tokens[I];
      Inc(I);
      if Length(Token) < 4 then
        Continue;
      // A rename or copy is followed by the path it came from.
      if CharInSet(Token[1], ['R', 'C']) or CharInSet(Token[2], ['R', 'C']) then
        Inc(I);
      Role := RoleOf(Token[1], Token[2]);
      if Role = '' then
        Continue;
      Path := Copy(Token, 4, MaxInt);
      if (APrefix <> '') and not Path.StartsWith(APrefix) then
        Continue;
      Path := Copy(Path, Length(APrefix) + 1, MaxInt);
      Slash := Pos('/', Path);
      if Slash > 0 then
        Name := Copy(Path, 1, Slash - 1)
      else
        Name := Path;
      if Name = '' then
        Continue;
      if not Roles.TryGetValue(Name, Old) or (Severity(Role) > Severity(Old)) then
        Roles.AddOrSetValue(Name, Role);
    end;
    Obj := TJSONObject.Create;
    try
      for Pair in Roles do
        Obj.AddPair(Pair.Key, Pair.Value);
      Result := Obj.ToJSON;
    finally
      Obj.Free;
    end;
  finally
    Roles.Free;
  end;
end;

function ReadGitMarks(const ADir: string; const ACancelled: TFunc<Boolean>;
  out AJson: string): Boolean;
var
  Prefix, Status: string;
  Code: Cardinal;
begin
  AJson := '';
  Result := False;
  if not IsInsideGitWorkTree(ADir) then
    Exit;
  if not RunGit(['-C', ADir, '--no-optional-locks', 'rev-parse', '--show-prefix'],
       ACancelled, Prefix, Code) or (Code <> 0) then
    Exit;
  Prefix := Trim(Prefix);
  if not RunGit(['-C', ADir, '--no-optional-locks', 'status', '--porcelain=v1', '-z'],
       ACancelled, Status, Code) or (Code <> 0) then
    Exit;
  AJson := GitMarksJson(Status, Prefix);
  Result := True;
end;

function PanelFolderUris(const APanelInfoJson: string): TArray<string>;
var
  Root, Side: TJSONValue;
  Uris: TList<string>;
  Name, Uri: string;
begin
  Result := nil;
  if APanelInfoJson = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(APanelInfoJson);
  try
    if not (Root is TJSONObject) then
      Exit;
    Uris := TList<string>.Create;
    try
      for Name in ['left', 'right'] do
      begin
        Side := Root.GetValue<TJSONValue>(Name, nil);
        if (Side is TJSONObject) and Side.TryGetValue<string>('uri', Uri) and
           Uri.StartsWith('file:', True) and not Uris.Contains(Uri) then
          Uris.Add(Uri);
      end;
      Result := Uris.ToArray;
    finally
      Uris.Free;
    end;
  finally
    Root.Free;
  end;
end;

end.
