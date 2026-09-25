unit uShellProfiles;

{ Shell profile catalog for Terminal Workspaces (Stage 21).
  Resolves profile id → CreateProcess command line + working directory.
  Supports automatic discovery of Windows Subsystem for Linux (WSL/WSL2) distros.

  CROSS-PLATFORM (Этап 23): the profile set itself (cmd/PowerShell/pwsh/WSL)
  is Windows-specific, not just the CreateProcess plumbing -- a POSIX build
  needs its own profile catalog (bash/zsh/fish, no WSL-discovery concept),
  reusing the TShellProfileInfo/TShellProfileArray shape, not this data. }

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
function ShellProfileAvailable(const AProfileId: string): Boolean;
/// <summary>Resolve profile to a CreateProcess command line and cwd.
/// Returns False when the profile is unknown or its executable is missing.</summary>
function ResolveShellCmdLine(const AProfileId, ACwd: string;
  out ACmdLine, AWorkingDir: string): Boolean;
function NormalizeShellProfileId(const AProfileId: string): string;
function GetInstalledWslDistros: TArray<string>;
/// <summary>False for utility VMs that register as WSL distros but are not
/// interactive user shells (Docker Desktop engine/data, etc.).</summary>
function IsInteractiveWslDistro(const ADistroName: string): Boolean;
function GetWslExePath(out AWslExe: string): Boolean;
/// <summary>Builds a clean, safe wsl.exe command line for a given profile or input string and optional Cwd.</summary>
function BuildWslCommandLine(const AProfileOrCmd, ACwd: string; out ACmdLine: string): Boolean;
function GetSshExePath(out ASshExe: string): Boolean;
/// <summary>Builds ssh.exe &lt;args&gt; user@host for a "ssh:&lt;connection-id&gt;" profile id, looking the
/// connection up in uSshConnections.pas. Cwd has no meaning for a remote shell and is ignored.</summary>
function BuildSshCommandLine(const AProfileId: string; out ACmdLine: string): Boolean;
/// <summary>Locates Git for Windows' bash.exe via the GitForWindows registry
/// key (native and Wow6432Node views) or common install locations. Not
/// added to PATH by a typical install, unlike cmd/PowerShell, so a full
/// resolved path is needed rather than a bare exe name.</summary>
function GetGitBashExePath(out AGitBashExe: string): Boolean;
function ProfileReturnSeq(const AProfileId: string): string;
/// <summary>Silent setup line sent once right after the shell starts, before
/// the user can type anything; '' if the profile needs none. PowerShell/pwsh
/// piped stdin (no real console) hangs indefinitely when a command reports a
/// non-terminating error — PowerShell's error view tries to query console
/// dimensions that don't exist for a pipe. Forcing SilentlyContinue avoids
/// that hang (at the cost of not showing the error text).</summary>
function ProfileInitCommand(const AProfileId: string): string;
/// <summary>Output encoding by profile. Always True (UTF-8): real ConPTY
/// (Stage 22) normalizes every profile's console output to UTF-8 before it
/// reaches TConPtySession, including cmd.exe's OEM866 console writes.</summary>
function ProfileOutputEncoding(const AProfileId: string): Boolean;
/// <summary>Always False: real ConPTY gives every profile genuine console
/// line-editing/echo via conhost, so no profile needs the local
/// line-buffer/echo simulation the old pipe backend required.</summary>
function ProfileUsesLineBufferedInput(const AProfileId: string): Boolean;
/// <summary>Rewrite a PS command so its top-level result never reaches the
/// format engine — piped stdout (no real console) hangs indefinitely
/// rendering any non-string object (Get-Date, Get-Process, Out-String,
/// Format-Table, ... all confirmed). ls/dir/gci get a clean, known-good
/// rewrite; other simple expressions get a generic ToString() pipeline
/// wrapper (see IsSimplePsExpression); anything with ';'/'{'/'='/statement
/// keywords is left untouched to avoid changing what it does.</summary>
function PsPipeSafeCommand(const ACmd: string): string;
function ProfileBackspaceChar(const AProfileId: string): Char;
/// <summary>True for cmd/PowerShell/pwsh: real Windows conhost line-editing
/// erases a character by repositioning the cursor via CUP (ESC[row;colH),
/// overwriting with spaces, then repositioning back -- confirmed
/// empirically. conhost's column doesn't map onto this app's primary
/// scrollback buffer (different coordinate systems), so the erase must be
/// applied locally on keypress and the resulting echo suppressed instead
/// (see TConsoleBuffer.NotePendingLocalBackspace). False for WSL: bash's own
/// line editing under its Linux pty erases with a simple, non-CUP echo that
/// already applies correctly through the normal backspace path.</summary>
function ProfileNeedsBackspaceWorkaround(const AProfileId: string): Boolean;
/// <summary>Quote a path for cmd.exe / cd /d. Appends "." to drive roots so the
/// closing quote is not escaped by a trailing backslash (C:\ → "C:\.").</summary>
function QuoteCmdExePath(const APath: string): string;
function BuildCmdCdLine(const ACwd: string): string;
/// <summary>Profile-aware `cd` line for cwd sync. cmd → `cd /d &lt;path&gt;`;
/// WSL → `cd '/mnt/...'` (drive letter mapped to /mnt/x). Returns '' when ACwd is empty.</summary>
function BuildCdLineForProfile(const AProfileId, ACwd: string): string;

implementation

uses
  System.Classes, System.IOUtils, Winapi.Windows, System.Win.Registry,
  uSshConnections;

function FileExistsInPath(const AExeName: string): Boolean;
var
  Buf: array[0..MAX_PATH] of Char;
  FilePart: PChar;
begin
  Result := False;
  FillChar(Buf, SizeOf(Buf), 0);
  FilePart := nil;
  if SearchPath(nil, PChar(AExeName), nil, MAX_PATH, Buf, FilePart) > 0 then
    Result := Buf[0] <> #0;
end;

function GetWslExePath(out AWslExe: string): Boolean;
var
  WinDir, SysnativePath, System32Path: string;
begin
  Result := False;
  AWslExe := '';

  // 1. Standard search in PATH (for native x64 processes)
  if FileExistsInPath('wsl.exe') then
  begin
    AWslExe := 'wsl.exe';
    Exit(True);
  end;

  WinDir := GetEnvironmentVariable('SystemRoot');
  if WinDir = '' then
    WinDir := 'C:\Windows';

  // 2. Direct System32 check (x64)
  System32Path := TPath.Combine(WinDir, 'System32\wsl.exe');
  if FileExists(System32Path) then
  begin
    AWslExe := System32Path;
    Exit(True);
  end;

  // 3. Fallback for Sysnative (if ever built as 32-bit WOW64)
  SysnativePath := TPath.Combine(WinDir, 'Sysnative\wsl.exe');
  if FileExists(SysnativePath) then
  begin
    AWslExe := SysnativePath;
    Exit(True);
  end;
end;

function QuotePath(const APath: string): string;
begin
  Result := '"' + StringReplace(APath, '"', '', [rfReplaceAll]) + '"';
end;

var
  GWslDistrosCache: TArray<string>;
  GWslCacheValid: Boolean = False;

// One Lxss subkey = one installed distro; false if it has no (non-empty)
// DistributionName value, e.g. a stale/incomplete registration.
function TryReadWslDistroName(const AKeyName: string; out ADistroName: string): Boolean;
var
  SubReg: TRegistry;
begin
  Result := False;
  ADistroName := '';
  SubReg := TRegistry.Create;
  try
    SubReg.RootKey := HKEY_CURRENT_USER;
    if not SubReg.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Lxss\' + AKeyName) then
      Exit;
    if not SubReg.ValueExists('DistributionName') then
      Exit;
    ADistroName := SubReg.ReadString('DistributionName');
    Result := ADistroName <> '';
  finally
    SubReg.Free;
  end;
end;

function GetInstalledWslDistros: TArray<string>;
var
  Reg: TRegistry;
  SubKeys: TStringList;
  KeyName, DistroName: string;
begin
  if GWslCacheValid then
    Exit(GWslDistrosCache);

  SetLength(GWslDistrosCache, 0);
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Lxss') then
    begin
      SubKeys := TStringList.Create;
      try
        Reg.GetKeyNames(SubKeys);
        for KeyName in SubKeys do
          if TryReadWslDistroName(KeyName, DistroName) then
          begin
            SetLength(GWslDistrosCache, Length(GWslDistrosCache) + 1);
            GWslDistrosCache[High(GWslDistrosCache)] := DistroName;
          end;
      finally
        SubKeys.Free;
      end;
    end;
  finally
    Reg.Free;
  end;

  GWslCacheValid := True;
  Result := GWslDistrosCache;
end;

function IsInteractiveWslDistro(const ADistroName: string): Boolean;
var
  Lower: string;
begin
  Lower := LowerCase(Trim(ADistroName));
  Result := (Lower <> '') and
    not Lower.StartsWith('docker-desktop');
end;

function TryFindWslDistroName(const ADistroIdPart: string; out ARealDistroName: string): Boolean;
var
  Distros: TArray<string>;
  D: string;
begin
  Result := False;
  ARealDistroName := ADistroIdPart;
  Distros := GetInstalledWslDistros;
  for D in Distros do
  begin
    if SameText(D, ADistroIdPart) then
    begin
      ARealDistroName := D;
      Exit(True);
    end;
  end;
end;

function NormalizeShellProfileId(const AProfileId: string): string;
var
  Trimmed, Lower: string;
  DistroName, RealName: string;
begin
  Trimmed := Trim(AProfileId);
  Lower := LowerCase(Trimmed);
  if (Lower = '') or (Lower = 'cmd.exe') or (Lower = cShellProfileCmd) then
    Exit(cShellProfileCmd);
  if (Lower = 'powershell.exe') or (Lower = 'windows powershell') or (Lower = cShellProfilePowerShell) then
    Exit(cShellProfilePowerShell);
  if (Lower = 'pwsh.exe') or (Lower = 'powershell core') or (Lower = cShellProfilePwsh) then
    Exit(cShellProfilePwsh);
  if (Lower = 'git bash') or (Lower = 'git-bash') or (Lower = 'bash') or
     (Lower = cShellProfileGitBash) then
    Exit(cShellProfileGitBash);
  if (Lower = 'wsl.exe') or (Lower = cShellProfileWsl) then
    Exit(cShellProfileWsl);

  if Lower.StartsWith(cShellProfileWslPrefix) then
  begin
    DistroName := Trim(Copy(Trimmed, Length(cShellProfileWslPrefix) + 1, MaxInt));
    if TryFindWslDistroName(DistroName, RealName) then
      Exit(cShellProfileWslPrefix + RealName)
    else
      Exit(cShellProfileWslPrefix + DistroName);
  end;

  if Lower.StartsWith(cShellProfileSshPrefix) then
    // Connection id is opaque (a GUID) -- no discovery/rewrite needed, unlike WSL distro names.
    Exit(Trimmed);

  Result := Trimmed;
end;

function ShellProfileAvailable(const AProfileId: string): Boolean;
var
  Id, DistroPart, RealName, WslExe, GitBashExe: string;
  Conn: TSshConnection;
begin
  Id := NormalizeShellProfileId(AProfileId);
  if Id = cShellProfileCmd then
    Exit(FileExistsInPath('cmd.exe'));
  if Id = cShellProfilePowerShell then
    Exit(FileExistsInPath('powershell.exe'));
  if Id = cShellProfilePwsh then
    Exit(FileExistsInPath('pwsh.exe'));
  if Id = cShellProfileGitBash then
    Exit(GetGitBashExePath(GitBashExe));
  if Id = cShellProfileWsl then
    Exit(GetWslExePath(WslExe));

  if Id.StartsWith(cShellProfileWslPrefix) then
  begin
    if not GetWslExePath(WslExe) then
      Exit(False);
    DistroPart := Copy(Id, Length(cShellProfileWslPrefix) + 1, MaxInt);
    if DistroPart = '' then
      Exit(True);
    if not IsInteractiveWslDistro(DistroPart) then
      Exit(False);
    Exit(TryFindWslDistroName(DistroPart, RealName));
  end;

  if Id.StartsWith(cShellProfileSshPrefix) then
  begin
    if not GetSshExePath(WslExe) then
      Exit(False);
    Exit(SshConnectionsFindById(Copy(Id, Length(cShellProfileSshPrefix) + 1, MaxInt), Conn));
  end;

  Result := False;
end;

function ShellProfileTitle(const AProfileId: string): string;
var
  Id, DistroPart, RealName: string;
  Conn: TSshConnection;
begin
  Id := NormalizeShellProfileId(AProfileId);
  if Id = cShellProfileCmd then
    Exit('Command Prompt');
  if Id = cShellProfilePowerShell then
    Exit('Windows PowerShell');
  if Id = cShellProfilePwsh then
    Exit('PowerShell');
  if Id = cShellProfileGitBash then
    Exit('Git Bash');
  if Id = cShellProfileWsl then
    Exit('WSL');

  if Id.StartsWith(cShellProfileWslPrefix) then
  begin
    DistroPart := Copy(Id, Length(cShellProfileWslPrefix) + 1, MaxInt);
    if TryFindWslDistroName(DistroPart, RealName) then
      Exit('WSL (' + RealName + ')')
    else
      Exit('WSL (' + DistroPart + ')');
  end;

  if Id.StartsWith(cShellProfileSshPrefix) then
  begin
    if SshConnectionsFindById(Copy(Id, Length(cShellProfileSshPrefix) + 1, MaxInt), Conn) then
      Exit('SSH (' + Conn.Name + ')')
    else
      Exit('SSH (unknown connection)');
  end;

  Result := AProfileId;
end;

function EnumerateShellProfiles: TShellProfileArray;
  procedure Add(const AId: string; const ATitle: string = '');
  var
    N: Integer;
    T: string;
  begin
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N].Id := AId;
    if ATitle <> '' then
      T := ATitle
    else
      T := ShellProfileTitle(AId);
    Result[N].Title := T;
    Result[N].Available := ShellProfileAvailable(AId);
  end;

var
  Distros: TArray<string>;
  D, WslExe: string;
  Conns: TArray<TSshConnection>;
  Conn: TSshConnection;
begin
  SetLength(Result, 0);
  Add(cShellProfileCmd);
  Add(cShellProfilePowerShell);
  Add(cShellProfilePwsh);
  Add(cShellProfileGitBash);
  Add(cShellProfileWsl);

  if GetWslExePath(WslExe) then
  begin
    Distros := GetInstalledWslDistros;
    for D in Distros do
      if IsInteractiveWslDistro(D) then
        Add(cShellProfileWslPrefix + D, 'WSL (' + D + ')');
  end;

  Conns := SshConnectionsGet;
  for Conn in Conns do
    Add(cShellProfileSshPrefix + Conn.Id, 'SSH (' + Conn.Name + ')');
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

function BuildWslCommandLine(const AProfileOrCmd, ACwd: string; out ACmdLine: string): Boolean;
var
  WslExe, InputStr, DistroName, RealDistro, ExtraArgs, CleanCwd: string;
begin
  ACmdLine := '';
  Result := GetWslExePath(WslExe);
  if not Result then
    Exit;

  InputStr := Trim(AProfileOrCmd);
  CleanCwd := Trim(ACwd);
  DistroName := '';
  ExtraArgs := '';

  if InputStr.StartsWith(cShellProfileWslPrefix, True) then
  begin
    DistroName := Trim(Copy(InputStr, Length(cShellProfileWslPrefix) + 1, MaxInt));
  end
  else if SameText(InputStr, 'wsl') or SameText(InputStr, 'wsl.exe') then
  begin
    DistroName := '';
  end
  else if LowerCase(InputStr).StartsWith('wsl.exe ') then
  begin
    ExtraArgs := Trim(Copy(InputStr, 9, MaxInt));
  end
  else if LowerCase(InputStr).StartsWith('wsl ') then
  begin
    ExtraArgs := Trim(Copy(InputStr, 5, MaxInt));
  end
  else
  begin
    DistroName := InputStr;
  end;

  ACmdLine := QuoteArgIfNeeded(WslExe);

  if (DistroName <> '') and not SameText(DistroName, 'wsl') then
  begin
    if TryFindWslDistroName(DistroName, RealDistro) then
      DistroName := RealDistro;
    ACmdLine := ACmdLine + ' -d ' + QuoteArgIfNeeded(DistroName);
  end;

  if CleanCwd <> '' then
    ACmdLine := ACmdLine + ' --cd ' + QuoteArgIfNeeded(CleanCwd);

  if ExtraArgs <> '' then
    ACmdLine := ACmdLine + ' ' + ExtraArgs;
  // No --exec stdbuf/bash: docker-desktop and other minimal distros have
  // neither binary, and a real ConPTY already looks like a tty so GNU
  // stdbuf is unnecessary. Let wsl.exe start the distro's default shell.

  Result := True;
end;

function GetSshExePath(out ASshExe: string): Boolean;
begin
  // Windows 10 1809+ ships OpenSSH's ssh.exe in System32\OpenSSH, on PATH by
  // default; same binary name and CLI on Linux/macOS (POSIX build target).
  Result := FileExistsInPath('ssh.exe');
  if Result then
    ASshExe := 'ssh.exe'
  else
    ASshExe := '';
end;

function GetGitBashExePath(out AGitBashExe: string): Boolean;
var
  InstallPath, Candidate: string;

  function TryInstallPathFromKey(ARoot: HKEY; const AKeyPath: string): string;
  var
    R: TRegistry;
  begin
    Result := '';
    R := TRegistry.Create;
    try
      R.RootKey := ARoot;
      if R.OpenKeyReadOnly(AKeyPath) and R.ValueExists('InstallPath') then
        Result := R.ReadString('InstallPath');
    finally
      R.Free;
    end;
  end;

begin
  Result := False;
  AGitBashExe := '';

  // 1. Git for Windows' installer registers its install location; check
  // both registry views (Wow6432Node for a 32-bit app on 64-bit Windows)
  // and both machine/user scope, same shape as GetWslExePath's fallbacks.
  InstallPath := TryInstallPathFromKey(HKEY_LOCAL_MACHINE, 'SOFTWARE\GitForWindows');
  if InstallPath = '' then
    InstallPath := TryInstallPathFromKey(HKEY_LOCAL_MACHINE, 'SOFTWARE\WOW6432Node\GitForWindows');
  if InstallPath = '' then
    InstallPath := TryInstallPathFromKey(HKEY_CURRENT_USER, 'SOFTWARE\GitForWindows');
  if InstallPath <> '' then
  begin
    Candidate := TPath.Combine(InstallPath, 'bin\bash.exe');
    if FileExists(Candidate) then
    begin
      AGitBashExe := Candidate;
      Exit(True);
    end;
  end;

  // 2. Common install locations, for portable installs or a registry key
  // that a non-standard installer didn't write. Deliberately not falling
  // back to FileExistsInPath('bash.exe') -- %SystemRoot%\System32\bash.exe
  // is the legacy WSL launcher, not Git's, and would silently resolve to
  // the wrong shell.
  Candidate := TPath.Combine(GetEnvironmentVariable('ProgramFiles'), 'Git\bin\bash.exe');
  if FileExists(Candidate) then
  begin
    AGitBashExe := Candidate;
    Exit(True);
  end;
  Candidate := TPath.Combine(GetEnvironmentVariable('ProgramFiles(x86)'), 'Git\bin\bash.exe');
  if FileExists(Candidate) then
  begin
    AGitBashExe := Candidate;
    Exit(True);
  end;
  Candidate := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Programs\Git\bin\bash.exe');
  if FileExists(Candidate) then
  begin
    AGitBashExe := Candidate;
    Exit(True);
  end;
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
  ACmdLine := QuoteArgIfNeeded(SshExe);
  // -tt forces a real remote pty even when local stdin/stdout are redirected
  // through ConPTY pipes rather than a console handle -- without it some
  // servers fall back to a non-interactive session and skip the shell prompt.
  ACmdLine := ACmdLine + ' -tt';
  Args := SshConnectionArgs(Conn, '-p');
  for Arg in Args do
    ACmdLine := ACmdLine + ' ' + QuoteArgIfNeeded(Arg);
  Result := True;
end;

function BuildInteractivePsCmdLine(const AExeName: string): string;
begin
  // Real ConPTY is a console: start an interactive host. The old pipe-backend
  // line (-NoLogo -NoExit -File -) treated stdin as a script; `exit` then only
  // ended that script and -NoExit dropped into a REPL, so the process never
  // died and the background console could not RestartOnExit (cmd /k does).
  Result := AExeName + ' -NoLogo';
end;

function ResolveShellCmdLine(const AProfileId, ACwd: string;
  out ACmdLine, AWorkingDir: string): Boolean;
var
  Id, Cwd, GitBashExe: string;
begin
  Result := False;
  ACmdLine := '';
  AWorkingDir := '';
  Id := NormalizeShellProfileId(AProfileId);
  Cwd := Trim(ACwd);
  if not ShellProfileAvailable(Id) then
    Exit;

  if Id = cShellProfileCmd then
  begin
    ACmdLine := 'cmd.exe /d /q /k';
    AWorkingDir := Cwd;
    Exit(True);
  end;
  if Id = cShellProfilePowerShell then
  begin
    ACmdLine := BuildInteractivePsCmdLine('powershell.exe');
    AWorkingDir := Cwd;
    Exit(True);
  end;
  if Id = cShellProfilePwsh then
  begin
    ACmdLine := BuildInteractivePsCmdLine('pwsh.exe');
    AWorkingDir := Cwd;
    Exit(True);
  end;
  if Id = cShellProfileGitBash then
  begin
    if not GetGitBashExePath(GitBashExe) then
      Exit(False);
    // --login -i: a real login+interactive bash, same as Git Bash's own
    // shortcut, so profile/rc files (aliases, prompt) load as expected.
    ACmdLine := QuoteArgIfNeeded(GitBashExe) + ' --login -i';
    AWorkingDir := Cwd; // MSYS runtime maps the inherited Windows cwd on its own.
    Exit(True);
  end;
  if (Id = cShellProfileWsl) or Id.StartsWith(cShellProfileWslPrefix) then
  begin
    if not BuildWslCommandLine(Id, Cwd, ACmdLine) then
      Exit(False);
    AWorkingDir := ''; // WSL cwd is embedded via --cd
    Exit(True);
  end;
  if Id.StartsWith(cShellProfileSshPrefix) then
  begin
    if not BuildSshCommandLine(Id, ACmdLine) then
      Exit(False);
    AWorkingDir := ''; // remote shell has no local cwd
    Exit(True);
  end;
end;

function ProfileReturnSeq(const AProfileId: string): string;
var
  NormId: string;
begin
  NormId := NormalizeShellProfileId(AProfileId);
  if (NormId = cShellProfileWsl) or NormId.StartsWith(cShellProfileWslPrefix) or
     NormId.StartsWith(cShellProfileSshPrefix) or (NormId = cShellProfileGitBash) then
    // WSL/Linux bash, Git Bash (MSYS bash), and ssh.exe forwarding to a
    // remote bash-like shell:
    // the pty's icrnl setting already turns our CR into LF,
    // so sending CRLF lands as two line terminators — bash executes the
    // command on the CR-turned-LF, then treats the literal trailing LF as a
    // second, empty Enter press, which redraws the prompt a second time
    // (visible as a duplicated prompt after every command). A lone LF
    // submits exactly once.
    Result := #10
  else if (NormId = cShellProfilePowerShell) or (NormId = cShellProfilePwsh) then
    // PowerShell/pwsh under real ConPTY (a genuine console, unlike the old
    // piped-stdin backend this CRLF choice predates): a lone CR submits the
    // line correctly, and PSReadLine's own multi-line/predictive-text
    // machinery treats the extra trailing LF as its own edit keystroke
    // (matching Ctrl+J's raw byte) rather than a harmless second Enter --
    // confirmed empirically: every submitted command left a stray ">>"
    // continuation-prompt line behind, even though the command itself ran
    // correctly. A lone CR avoids feeding it that extra byte.
    Result := #13
  else
    // cmd (piped stdin, no real console -- or a genuine console today, but
    // unconfirmed whether a lone CR is equally safe there): a lone CR may
    // be interpreted as ^M when icrnl is off, so Enter would not submit
    // input — CRLF is required here.
    Result := #13#10;
end;

function ProfileInitCommand(const AProfileId: string): string;
begin
  // PowerShell/pwsh sessions used to set $ErrorActionPreference =
  // 'SilentlyContinue' on start; confirmed everything works correctly
  // without it, so no profile sends an init command anymore.
  Result := '';
end;

function ProfileOutputEncoding(const AProfileId: string): Boolean;
begin
  // Real ConPTY (Stage 22) normalizes every profile's console output to a
  // UTF-8 VT stream before it ever reaches TConPtySession's pipe -- conhost
  // translates cmd.exe's OEM866 console buffer writes the same way it
  // translates PowerShell/WSL's native UTF-8, so there is no longer a
  // profile-dependent choice to make here. Confirmed empirically: under the
  // old pipe backend cmd emitted raw OEM866 (needed CP866 decode); under
  // real ConPTY it emits UTF-8 (CP866 decode of it produces mojibake).
  Result := True;
end;

function ProfileUsesLineBufferedInput(const AProfileId: string): Boolean;
begin
  // Real ConPTY (Stage 22) gives every profile a genuine console with real
  // line-editing and character echo from conhost itself -- the local
  // line-buffer/echo simulation below existed only because the old pipe
  // backend had none at all. Keeping it running on top of real echo double-
  // echoes typed commands and corrupts the primary buffer's prompt-tracking
  // heuristics (confirmed by manual testing: "dir" appearing twice, garbled
  // `dir` output). Every profile now uses the same raw-passthrough path WSL
  // already used successfully under the old pipe backend.
  Result := False;
end;

/// <summary>True if T is a single simple pipeline/expression — safe to
/// append a display wrapper to without changing what it does. Deliberately
/// conservative: any of these makes it False (never wrap, fall back to
/// sending T unchanged) rather than risk corrupting semantics:
///   - ';' (multiple statements — a trailing wrapper would only apply to
///     the last one, changing what the earlier ones do to their output).
///   - '{' / '}' (script block — Where-Object/ForEach-Object filters, or a
///     control-flow/function body).
///   - a literal '=' (PowerShell has no '==' for comparison, so any '=' is
///     almost certainly assignment — appending "| % {"$_"}" to
///     "$x = 5" would pipe 5 through the wrapper *before* assigning it,
///     silently turning $x from Int32 into the string "5").
///   - starts with a keyword that begins a statement rather than an
///     expression (if/for/function/etc.) — piping those is invalid or
///     changes control flow, not display.
///   - already ends in an explicit display/format cmdlet — the user chose
///     that rendering on purpose; wrapping again just mangles it.</summary>
function IsSimplePsExpression(const T: string): Boolean;
const
  cStatementKeywords: array[0..14] of string = (
    'if', 'for', 'foreach', 'while', 'do', 'switch', 'function', 'filter',
    'param', 'try', 'class', 'enum', 'workflow', 'begin', 'trap');
  cDisplayTailPipes: array[0..7] of string = (
    '| out-host', '| out-default', '| out-string', '| format-table',
    '| format-list', '| ft', '| fl', '| % {"$_"}');
var
  I: Integer;
  Word1: string;
  SpacePos: Integer;
begin
  Result := False;
  if (T = '') or (Pos(';', T) > 0) or (Pos('{', T) > 0) or (Pos('}', T) > 0) or
     (Pos('=', T) > 0) then
    Exit;
  SpacePos := Pos(' ', T);
  if SpacePos > 0 then
    Word1 := Copy(T, 1, SpacePos - 1)
  else
    Word1 := T;
  for I := Low(cStatementKeywords) to High(cStatementKeywords) do
    if SameText(Word1, cStatementKeywords[I]) then
      Exit;
  for I := Low(cDisplayTailPipes) to High(cDisplayTailPipes) do
    if T.ToLower.EndsWith(cDisplayTailPipes[I]) then
      Exit;
  Result := True;
end;

function PsPipeSafeCommand(const ACmd: string): string;
var
  T: string;
begin
  T := Trim(ACmd);
  // Piped PS host: table/list formatters (Out-Default's default view for any
  // non-string object) hang indefinitely instead of just printing nothing —
  // confirmed via Get-Date, Get-Process, Out-String, Out-Host all hanging
  // the same way, regardless of console-width hints. Explicit .ToString()-
  // shaped output never hangs, so:
  if SameText(T, 'ls') or SameText(T, 'dir') or SameText(T, 'gci') or
     SameText(T, 'Get-ChildItem') then
    // Known-common case: skip the format engine entirely for a clean list.
    Result := '(Get-ChildItem).Name'
  else if IsSimplePsExpression(T) then
    // General case: force every pipeline item through its own ToString()
    // via the pipeline (not the format engine), so the top-level result is
    // always plain text. Uglier than a real table for object types with no
    // useful ToString (e.g. Get-Process shows "System.Diagnostics.Process
    // (name)"), but that beats a permanent hang.
    Result := T + ' | % {"$_"}'
  else
    Result := T;
end;

function ProfileBackspaceChar(const AProfileId: string): Char;
begin
  // #127 (DEL) for every profile, not just WSL. Confirmed empirically via a
  // byte-level trace: real Windows conhost's own VT-to-console-input
  // translation does NOT correctly apply a bare #8 (BS) to its internal
  // line-edit buffer under ConPTY -- cmd would visually show the erased
  // character (via the app's own local-echo workaround) but the REAL
  // submitted command on Enter was missing everything before the last
  // backspace (e.g. typing "dir", backspacing once, retyping "r" executed
  // bare "r", not "dir"). Switching to #127 makes conhost apply it
  // correctly (own internal buffer matches the visible line), the same way
  // WSL's bash/readline already did. See ProfileNeedsBackspaceWorkaround:
  // conhost's echo for a correctly-applied #127 is also the same simple,
  // non-CUP "\b <space> \b" idiom WSL always used, so the CUP-based local
  // echo workaround is no longer needed for any profile either.
  Result := #127;
end;

function ProfileNeedsBackspaceWorkaround(const AProfileId: string): Boolean;
begin
  // No longer needed for any profile: this workaround existed only because
  // real conhost's erase-echo for a bare #8 (BS) used absolute cursor
  // addressing (CUP) that this app's primary buffer couldn't map onto its
  // own coordinates -- see ProfileBackspaceChar. Now that every profile
  // sends #127 (DEL) instead, conhost applies it correctly to its own
  // internal line-edit buffer AND echoes it the same simple, non-CUP
  // "\b <space> \b" way WSL's bash/readline always did, which the normal
  // (non-workaround) backspace path already handles correctly.
  Result := False;
end;

function QuoteCmdExePath(const APath: string): string;
var
  S: string;
  NeedsQuote: Boolean;
begin
  S := Trim(APath);
  if S = '' then
    Exit('');
  NeedsQuote := (Pos(' ', S) > 0) or (Pos('"', S) > 0) or (Pos('&', S) > 0) or
    (Pos('(', S) > 0) or (Pos(')', S) > 0) or (Pos('%', S) > 0);
  if NeedsQuote then
  begin
    // cmd.exe: a trailing \ immediately before the closing " escapes it, so
    // "C:\" is parsed as C:" and `cd /d` lands on the per-drive current dir
    // instead of the root. Canonical fix: append "." so the path becomes
    // "C:\.", which is the same directory and keeps the quote unescaped.
    // Only drive roots (X:\) and the bare root form are affected; ordinary
    // paths never end in \ once Trim is done.
    if (Length(S) = 3) and (S[2] = ':') and (S[3] = '\') and
       CharInSet(UpCase(S[1]), ['A'..'Z']) then
      S := S + '.'
    else
    begin
      while (Length(S) > 1) and (S[Length(S)] = '\') do
        SetLength(S, Length(S) - 1);
    end;
    Result := '"' + StringReplace(S, '"', '', [rfReplaceAll]) + '"';
  end
  else
    Result := S;
end;

function BuildCmdCdLine(const ACwd: string): string;
var
  Path: string;
begin
  Path := Trim(ACwd);
  if Path = '' then
    Exit('');
  Result := 'cd /d ' + QuoteCmdExePath(Path) + #13#10;
end;

function WindowsPathToWslPath(const APath: string): string;
var
  P: string;
begin
  // C:\foo\bar → /mnt/c/foo/bar. UNC and relative paths fall back to the raw
  // string; WSL bash will report an error rather than be misled.
  P := Trim(APath);
  if (Length(P) >= 3) and CharInSet(UpCase(P[1]), ['A'..'Z']) and
     (P[2] = ':') and ((P[3] = '\') or (P[3] = '/')) then
    Result := '/mnt/' + LowerCase(P[1]) +
      StringReplace(Copy(P, 3, MaxInt), '\', '/', [rfReplaceAll])
  else
    Result := P;
end;

/// <summary>C:\foo\bar -> /c/foo/bar, MSYS2/Git Bash's mount convention
/// (unlike WSL's /mnt/c/...). UNC and relative paths fall back to the raw
/// string, same rationale as WindowsPathToWslPath.</summary>
function WindowsPathToGitBashPath(const APath: string): string;
var
  P: string;
begin
  P := Trim(APath);
  if (Length(P) >= 3) and CharInSet(UpCase(P[1]), ['A'..'Z']) and
     (P[2] = ':') and ((P[3] = '\') or (P[3] = '/')) then
    Result := '/' + LowerCase(P[1]) +
      StringReplace(Copy(P, 3, MaxInt), '\', '/', [rfReplaceAll])
  else
    Result := P;
end;

function BuildCdLineForProfile(const AProfileId, ACwd: string): string;
var
  NormId, LinuxPath: string;
begin
  NormId := NormalizeShellProfileId(AProfileId);
  if (NormId = cShellProfileWsl) or NormId.StartsWith(cShellProfileWslPrefix) then
  begin
    LinuxPath := WindowsPathToWslPath(ACwd);
    if LinuxPath = '' then
      Exit('');
    // Single-quote the path; bash accepts 'cd "/mnt/c/My Files"' safely.
    // bash does not understand cmd's /d flag, so a plain cd is emitted.
    Result := 'cd ' + QuoteArgIfNeeded(LinuxPath) + #13#10;
  end
  else if NormId = cShellProfileGitBash then
  begin
    LinuxPath := WindowsPathToGitBashPath(ACwd);
    if LinuxPath = '' then
      Exit('');
    Result := 'cd ' + QuoteArgIfNeeded(LinuxPath) + #13#10;
  end
  else if NormId.StartsWith(cShellProfileSshPrefix) then
    // Local Windows path has no meaning on the remote host; no cwd to sync.
    Result := ''
  else
    Result := BuildCmdCdLine(ACwd);
end;

end.

