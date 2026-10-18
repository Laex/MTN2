unit uShellProfiles;

{ Shell profile catalog for Terminal Workspaces, Posix build: the login
  shells listed in /etc/shells (the user's own first) and SSH connections.
  Resolves profile id -> command line + working directory.

  The profile ids of the Windows-only shells stay declared so shared code
  compiles; they are never available here. The Windows build lives in
  Platform\Windows; each project puts exactly one of the two directories on
  its unit search path. }

interface

uses
  System.SysUtils;

type
  TShellProfileInfo = record
    Id: string;
    Title: string;
    Available: Boolean;
  end;

  TShellProfileArray = TArray<TShellProfileInfo>;

const
  cShellProfileCmd = 'cmd';
  cShellProfilePowerShell = 'powershell';
  cShellProfilePwsh = 'pwsh';
  cShellProfileGitBash = 'gitbash';
  cShellProfileWsl = 'wsl';
  cShellProfileWslPrefix = 'wsl:';
  cShellProfileSshPrefix = 'ssh:';

function FileExistsInPath(const AExeName: string): Boolean;
function EnumerateShellProfiles: TShellProfileArray;
function ShellProfileTitle(const AProfileId: string): string;
/// <summary>ABase and the shell of the profile: "Console - bash".</summary>
function TitleWithShell(const ABase, AProfileId: string): string;
function ShellProfileAvailable(const AProfileId: string): Boolean;
/// <summary>Resolve profile to a command line and cwd. Returns False when the
/// profile is unknown or its executable is missing.</summary>
function ResolveShellCmdLine(const AProfileId, ACwd: string;
  out ACmdLine, AWorkingDir: string): Boolean;
/// <summary>The profile whose shell AProfileId starts: a copy of a profile
/// ("bash#2") resolves to the profile it was copied from. An empty id is the
/// user's login shell.</summary>
function NormalizeShellProfileId(const AProfileId: string): string;
/// <summary>Like NormalizeShellProfileId, but a copy keeps its "#N" suffix, so
/// per-copy settings can be looked up.</summary>
function CanonicalShellProfileId(const AProfileId: string): string;
/// <summary>The "#N" suffix of a profile copy id, '' for a profile.</summary>
function ShellProfileCopySuffix(const AProfileId: string): string;
function GetInstalledWslDistros: TArray<string>;
function IsInteractiveWslDistro(const ADistroName: string): Boolean;
function GetWslExePath(out AWslExe: string): Boolean;
function BuildWslCommandLine(const AProfileOrCmd, ACwd: string; out ACmdLine: string): Boolean;
function GetSshExePath(out ASshExe: string): Boolean;
/// <summary>Builds ssh &lt;args&gt; user@host for a "ssh:&lt;connection-id&gt;" profile id, looking the
/// connection up in uSshConnections.pas. Cwd has no meaning for a remote shell and is ignored.</summary>
function BuildSshCommandLine(const AProfileId: string; out ACmdLine: string): Boolean;
function GetGitBashExePath(out AGitBashExe: string): Boolean;
/// <summary>The bytes the Enter key sends to the profile's shell.</summary>
function ProfileReturnSeq(const AProfileId: string): string;
/// <summary>No prompt is parsed on this platform: always False.</summary>
function ShellCwdFromPrompt(const AProfileId, ALine: string; out APath: string): Boolean;
/// <summary>True where ShellCwdFromPrompt can recognize the prompt of the profile, so that
/// prompts can be counted; False: the console follows the shell process instead.</summary>
function ProfilePromptIsParsable(const AProfileId: string): Boolean;
/// <summary>Setup line sent once right after the shell starts; always ''.</summary>
function ProfileInitCommand(const AProfileId: string): string;
/// <summary>Output is UTF-8 for every profile.</summary>
function ProfileOutputEncoding(const AProfileId: string): Boolean;
/// <summary>Always False: the pty's own line discipline does the line editing.</summary>
function ProfileUsesLineBufferedInput(const AProfileId: string): Boolean;
/// <summary>PowerShell-specific rewrite; the command is returned unchanged.</summary>
function PsPipeSafeCommand(const ACmd: string): string;
/// <summary>The character the Backspace key sends (DEL).</summary>
function ProfileBackspaceChar(const AProfileId: string): Char;
/// <summary>Always False: a Linux pty erases with an ordinary echo.</summary>
function ProfileNeedsBackspaceWorkaround(const AProfileId: string): Boolean;
function QuoteCmdExePath(const APath: string): string;
function BuildCmdCdLine(const ACwd: string): string;
/// <summary>`cd '&lt;path&gt;'` ending in the profile's own Enter; '' for ssh
/// profiles and an empty ACwd.</summary>
function BuildCdLineForProfile(const AProfileId, ACwd: string): string;

implementation

uses
  System.Classes, System.IOUtils, uSshConnections;

function FileExistsInPath(const AExeName: string): Boolean;
begin
  Result := FileSearch(AExeName, GetEnvironmentVariable('PATH')) <> '';
end;

function QuoteArgIfNeeded(const S: string): string;
var
  T: string;
begin
  T := Trim(S);
  if (T = '') or T.Contains(' ') or T.Contains('"') or T.Contains(#9) then
    Result := '"' + StringReplace(T, '"', '', [rfReplaceAll]) + '"'
  else
    Result := T;
end;

function ShellBaseName(const AShellPath: string): string;
begin
  Result := ExtractFileName(AShellPath);
end;

/// <summary>Absolute path of the shell called AName: its /etc/shells entry,
/// else the first match in PATH; '' when it is not installed.</summary>
function ShellPathOf(const AName: string): string;
var
  Lines: TStringList;
  Line: string;
begin
  Result := '';
  if AName = '' then
    Exit;
  if AName.StartsWith('/') then
    begin
      if TFile.Exists(AName) then
        Result := AName;
      Exit;
    end;
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile('/etc/shells');
    except
      Lines.Clear;
    end;
    for Line in Lines do
      if (Trim(Line) <> '') and (Trim(Line)[1] = '/') and
         (ShellBaseName(Trim(Line)) = AName) and TFile.Exists(Trim(Line)) then
        Exit(Trim(Line));
  finally
    Lines.Free;
  end;
  Result := FileSearch(AName, GetEnvironmentVariable('PATH'));
end;

function LoginShellName: string;
begin
  Result := ShellBaseName(GetEnvironmentVariable('SHELL'));
  if (Result = '') or (ShellPathOf(Result) = '') then
    Result := 'sh';
end;

function ShellProfileCopySuffix(const AProfileId: string): string;
var
  S: string;
  I: Integer;
begin
  Result := '';
  S := Trim(AProfileId);
  I := Length(S);
  while (I > 0) and CharInSet(S[I], ['0'..'9']) do
    Dec(I);
  if (I > 1) and (I < Length(S)) and (S[I] = '#') then
    Result := Copy(S, I, MaxInt);
end;

function NormalizeShellProfileId(const AProfileId: string): string;
var
  Trimmed, Suffix: string;
begin
  Trimmed := Trim(AProfileId);
  Suffix := ShellProfileCopySuffix(Trimmed);
  if Suffix <> '' then
    Trimmed := Copy(Trimmed, 1, Length(Trimmed) - Length(Suffix));
  if Trimmed = '' then
    Exit(LoginShellName);
  Result := Trimmed;
end;

function CanonicalShellProfileId(const AProfileId: string): string;
begin
  Result := NormalizeShellProfileId(AProfileId) + ShellProfileCopySuffix(AProfileId);
end;

function GetSshExePath(out ASshExe: string): Boolean;
begin
  Result := FileExistsInPath('ssh');
  if Result then
    ASshExe := 'ssh'
  else
    ASshExe := '';
end;

function ShellProfileAvailable(const AProfileId: string): Boolean;
var
  Id, SshExe: string;
  Conn: TSshConnection;
begin
  Id := NormalizeShellProfileId(AProfileId);
  if Id.StartsWith(cShellProfileSshPrefix) then
  begin
    if not GetSshExePath(SshExe) then
      Exit(False);
    Exit(SshConnectionsFindById(Copy(Id, Length(cShellProfileSshPrefix) + 1, MaxInt), Conn));
  end;
  Result := ShellPathOf(Id) <> '';
end;

function ShellProfileTitle(const AProfileId: string): string;
var
  Id: string;
  Conn: TSshConnection;
begin
  Id := NormalizeShellProfileId(AProfileId);
  if Id.StartsWith(cShellProfileSshPrefix) then
  begin
    if SshConnectionsFindById(Copy(Id, Length(cShellProfileSshPrefix) + 1, MaxInt), Conn) then
      Exit('SSH (' + Conn.Name + ')')
    else
      Exit('SSH (unknown connection)');
  end;
  Result := Id;
end;

function TitleWithShell(const ABase, AProfileId: string): string;
begin
  Result := ABase + ' - ' + ShellProfileTitle(AProfileId);
end;

function EnumerateShellProfiles: TShellProfileArray;
  procedure Add(const AId, ATitle: string);
  var
    N: Integer;
  begin
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N].Id := AId;
    Result[N].Title := ATitle;
    Result[N].Available := ShellProfileAvailable(AId);
  end;

var
  Lines, Names: TStringList;
  Line, Name: string;
  Conns: TArray<TSshConnection>;
  Conn: TSshConnection;
begin
  SetLength(Result, 0);
  Names := TStringList.Create;
  Lines := TStringList.Create;
  try
    Names.CaseSensitive := True;
    Names.Add(LoginShellName);
    try
      Lines.LoadFromFile('/etc/shells');
    except
      Lines.Clear;
    end;
    for Line in Lines do
    begin
      Name := Trim(Line);
      if (Name = '') or (Name[1] <> '/') then
        Continue;
      Name := ShellBaseName(Name);
      // nologin, false and similar entries are not interactive shells.
      if Name.Contains('nologin') or (Name = 'false') or (Name = 'git-shell') then
        Continue;
      if Names.IndexOf(Name) < 0 then
        Names.Add(Name);
    end;
    for Name in Names do
      Add(Name, Name);
  finally
    Lines.Free;
    Names.Free;
  end;
  Conns := SshConnectionsGet;
  for Conn in Conns do
    Add(cShellProfileSshPrefix + Conn.Id, 'SSH (' + Conn.Name + ')');
end;

function GetInstalledWslDistros: TArray<string>;
begin
  SetLength(Result, 0);
end;

function IsInteractiveWslDistro(const ADistroName: string): Boolean;
begin
  Result := False;
end;

function GetWslExePath(out AWslExe: string): Boolean;
begin
  AWslExe := '';
  Result := False;
end;

function BuildWslCommandLine(const AProfileOrCmd, ACwd: string; out ACmdLine: string): Boolean;
begin
  ACmdLine := '';
  Result := False;
end;

function GetGitBashExePath(out AGitBashExe: string): Boolean;
begin
  AGitBashExe := '';
  Result := False;
end;

function BuildSshCommandLine(const AProfileId: string; out ACmdLine: string): Boolean;
var
  SshExe, ConnId: string;
  Conn: TSshConnection;
  Args: TArray<string>;
  Arg: string;
begin
  ACmdLine := '';
  Result := GetSshExePath(SshExe);
  if not Result then
    Exit;
  ConnId := Copy(Trim(AProfileId), Length(cShellProfileSshPrefix) + 1, MaxInt);
  if not SshConnectionsFindById(ConnId, Conn) then
    Exit(False);
  // -tt forces a remote pty even when local stdin/stdout are not a terminal.
  ACmdLine := QuoteArgIfNeeded(SshExe) + ' -tt';
  Args := SshConnectionArgs(Conn, '-p');
  for Arg in Args do
    ACmdLine := ACmdLine + ' ' + QuoteArgIfNeeded(Arg);
  Result := True;
end;

function ResolveShellCmdLine(const AProfileId, ACwd: string;
  out ACmdLine, AWorkingDir: string): Boolean;
var
  Id, ShellPath: string;
begin
  Result := False;
  ACmdLine := '';
  AWorkingDir := '';
  Id := NormalizeShellProfileId(AProfileId);
  if not ShellProfileAvailable(Id) then
    Exit;
  if Id.StartsWith(cShellProfileSshPrefix) then
  begin
    if not BuildSshCommandLine(Id, ACmdLine) then
      Exit(False);
    Exit(True); // a remote shell has no local cwd
  end;
  ShellPath := ShellPathOf(Id);
  ACmdLine := QuoteArgIfNeeded(ShellPath) + ' -i';
  AWorkingDir := Trim(ACwd);
  Result := True;
end;

function ProfileReturnSeq(const AProfileId: string): string;
begin
  Result := #13;
end;

function ProfilePromptIsParsable(const AProfileId: string): Boolean;
begin
  Result := False;
end;

function ShellCwdFromPrompt(const AProfileId, ALine: string; out APath: string): Boolean;
begin
  APath := '';
  Result := False;
end;

function ProfileInitCommand(const AProfileId: string): string;
begin
  Result := '';
end;

function ProfileOutputEncoding(const AProfileId: string): Boolean;
begin
  Result := True;
end;

function ProfileUsesLineBufferedInput(const AProfileId: string): Boolean;
begin
  Result := False;
end;

function PsPipeSafeCommand(const ACmd: string): string;
begin
  Result := ACmd;
end;

function ProfileBackspaceChar(const AProfileId: string): Char;
begin
  Result := #127;
end;

function ProfileNeedsBackspaceWorkaround(const AProfileId: string): Boolean;
begin
  Result := False;
end;

function QuoteCmdExePath(const APath: string): string;
begin
  Result := '"' + APath + '"';
end;

function BuildCmdCdLine(const ACwd: string): string;
begin
  Result := '';
end;

function BuildCdLineForProfile(const AProfileId, ACwd: string): string;
begin
  Result := '';
  if (Trim(ACwd) = '') or NormalizeShellProfileId(AProfileId).StartsWith(cShellProfileSshPrefix) then
    Exit;
  Result := 'cd ''' + StringReplace(ACwd, '''', '''\''''', [rfReplaceAll]) + '''' +
    ProfileReturnSeq(AProfileId);
end;

end.
