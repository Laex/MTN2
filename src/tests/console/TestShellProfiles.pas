unit TestShellProfiles;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestShellProfiles = class
  public
    [Test] procedure TestNormalization;
    [Test] procedure TestInteractiveWslDistro;
    [Test] procedure TestResolveCmdLine;
    [Test] procedure TestEnumeration;
    [Test] procedure TestSshProfile;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uShellProfiles,
  uSshConnections;

procedure TestNormalization;
begin
  Assert.IsTrue(NormalizeShellProfileId('cmd.exe') = cShellProfileCmd, 'cmd.exe normalization failed');
  Assert.IsTrue(NormalizeShellProfileId('powershell.exe') = cShellProfilePowerShell, 'powershell.exe normalization failed');
  Assert.IsTrue(NormalizeShellProfileId('pwsh.exe') = cShellProfilePwsh, 'pwsh.exe normalization failed');
  Assert.IsTrue(NormalizeShellProfileId('wsl.exe') = cShellProfileWsl, 'wsl.exe normalization failed');
  Assert.IsTrue(NormalizeShellProfileId('WSL:Ubuntu-24.04') = 'wsl:Ubuntu-24.04', 'wsl:Ubuntu-24.04 normalization failed');
  Writeln('OK: TestNormalization passed');
end;

procedure TestInteractiveWslDistro;
begin
  Assert.IsTrue(IsInteractiveWslDistro('Ubuntu-24.04'), 'Ubuntu is interactive');
  Assert.IsTrue(IsInteractiveWslDistro('Debian'), 'Debian is interactive');
  Assert.IsTrue(not IsInteractiveWslDistro('docker-desktop'), 'docker-desktop is a utility VM');
  Assert.IsTrue(not IsInteractiveWslDistro('docker-desktop-data'), 'docker-desktop-data is a utility VM');
  Assert.IsTrue(not IsInteractiveWslDistro(''), 'empty name is not interactive');
  Assert.IsTrue(not ShellProfileAvailable('wsl:docker-desktop'),
    'docker-desktop must not be an available shell profile');
  Writeln('OK: TestInteractiveWslDistro passed');
end;

procedure TestResolveCmdLine;
var
  CmdLine, WorkingDir: string;
begin
  Assert.IsTrue(ResolveShellCmdLine(cShellProfileCmd, 'C:\Test', CmdLine, WorkingDir), 'Cmd resolve failed');
  Assert.IsTrue(CmdLine = 'cmd.exe /d /q /k', 'Cmd cmdline mismatch');
  Assert.IsTrue(WorkingDir = 'C:\Test', 'Cmd working dir mismatch');

  Assert.IsTrue(ResolveShellCmdLine(cShellProfilePowerShell, 'C:\Test', CmdLine, WorkingDir),
    'PowerShell resolve failed');
  Assert.IsTrue(CmdLine = 'powershell.exe -NoLogo',
    'PowerShell cmdline mismatch: ' + CmdLine);

  Assert.IsTrue(ResolveShellCmdLine(cShellProfilePwsh, 'C:\Test', CmdLine, WorkingDir),
    'pwsh resolve failed');
  Assert.IsTrue(CmdLine = 'pwsh.exe -NoLogo',
    'pwsh cmdline mismatch: ' + CmdLine);

  Assert.IsTrue(QuoteCmdExePath('D:\Program Files\MTN2\') = '"D:\Program Files\MTN2"',
    'QuoteCmdExePath must strip trailing backslash before quote');
  Assert.IsTrue(BuildCmdCdLine('C:\') = 'cd /d C:\'#13#10, 'BuildCmdCdLine drive root');

  // Cwd sync (Ctrl+Shift+O): each shell gets its own syntax and its own Enter.
  Assert.IsTrue(BuildCdLineForProfile(cShellProfileCmd, 'D:\Work\Obsidian') =
    'cd /d D:\Work\Obsidian'#13#10, 'cmd cd line');
  Assert.IsTrue(BuildCdLineForProfile(cShellProfilePowerShell, 'D:\Work\Obsidian') =
    'Set-Location -LiteralPath ''D:\Work\Obsidian'''#13,
    'PowerShell cd line: Set-Location, lone CR (no ">>" continuation)');
  Assert.IsTrue(BuildCdLineForProfile(cShellProfilePwsh, 'C:\My Files\[x] $a') =
    'Set-Location -LiteralPath ''C:\My Files\[x] $a'''#13,
    'pwsh cd line: literal path, nothing expanded');
  Assert.IsTrue(BuildCdLineForProfile(cShellProfilePowerShell, 'C:\Bob''s') =
    'Set-Location -LiteralPath ''C:\Bob''''s'''#13, 'PowerShell quote doubled');
  Assert.IsTrue(BuildCdLineForProfile(cShellProfilePowerShell, 'C:\Bob'#$2019's') =
    'Set-Location -LiteralPath ''C:\Bob'#$2019#$2019's'''#13,
    'PowerShell typographic quote doubled');
  Assert.IsTrue(BuildCdLineForProfile(cShellProfilePowerShell, '') = '', 'empty cwd -> no line');
  Assert.IsTrue(BuildCdLineForProfile(cShellProfileGitBash, 'C:\Work') = 'cd /c/Work'#10,
    'Git Bash cd line: lone LF');
  Assert.IsTrue(BuildCdLineForProfile(cShellProfileWsl, 'C:\Work') = 'cd /mnt/c/Work'#10,
    'WSL cd line: lone LF');

  Assert.IsTrue(ResolveShellCmdLine(cShellProfileWsl, 'C:\Test', CmdLine, WorkingDir), 'WSL resolve failed');
  Assert.IsTrue(CmdLine.Contains('wsl.exe') and CmdLine.Contains('--cd C:\Test'), 'WSL cmdline mismatch: ' + CmdLine);
  Assert.IsTrue(not CmdLine.Contains('stdbuf'), 'WSL must not require stdbuf: ' + CmdLine);
  Assert.IsTrue(not CmdLine.Contains('--exec'), 'WSL must use the distro default shell: ' + CmdLine);
  Assert.IsTrue(WorkingDir = '', 'WSL working dir mismatch');

  if ShellProfileAvailable('wsl:Ubuntu-24.04') then
  begin
    Assert.IsTrue(ResolveShellCmdLine('wsl:Ubuntu-24.04', 'C:\Test', CmdLine, WorkingDir), 'WSL distro resolve failed');
    Assert.IsTrue(CmdLine.Contains('wsl.exe -d Ubuntu-24.04'), 'WSL distro cmdline mismatch: ' + CmdLine);
    Assert.IsTrue(CmdLine.Contains('--cd C:\Test'), 'WSL distro cd mismatch: ' + CmdLine);
    Assert.IsTrue(WorkingDir = '', 'WSL distro working dir mismatch');
  end;

  Writeln('OK: TestResolveCmdLine passed');
end;

procedure TestEnumeration;
var
  Profiles: TShellProfileArray;
  FoundCmd, FoundWsl: Boolean;
  P: TShellProfileInfo;
begin
  Profiles := EnumerateShellProfiles;
  Assert.IsTrue(Length(Profiles) > 0, 'No profiles enumerated');
  FoundCmd := False;
  FoundWsl := False;
  for P in Profiles do
  begin
    if P.Id = cShellProfileCmd then
      FoundCmd := True;
    if P.Id = cShellProfileWsl then
      FoundWsl := True;
    Writeln('Profile: Id=', P.Id, ' Title="', P.Title, '" Available=', P.Available);
  end;
  Assert.IsTrue(FoundCmd, 'Cmd profile not found in enumeration');
  Assert.IsTrue(FoundWsl, 'WSL profile not found in enumeration');
  Writeln('OK: TestEnumeration passed');
end;

procedure TestSshProfile;
var
  TempFile: string;
  Conn: TSshConnection;
  ProfileId, CmdLine, WorkingDir: string;
  Profiles: TShellProfileArray;
  P: TShellProfileInfo;
  FoundSsh: Boolean;
begin
  TempFile := TPath.Combine(TPath.GetTempPath, 'mtn2_test_shellprofiles_ssh.json');
  if TFile.Exists(TempFile) then
    TFile.Delete(TempFile);
  SshConnectionsUsePath(TempFile);
  try
    Conn := SshConnectionAdd('Test Box', 'box.example.com', 2222, 'bob', 'C:\keys\id_ed25519');
    ProfileId := cShellProfileSshPrefix + Conn.Id;

    Assert.IsTrue(NormalizeShellProfileId(ProfileId) = ProfileId,
      'ssh: profile id should normalize unchanged (opaque connection id)');

    Assert.IsTrue(ShellProfileTitle(ProfileId) = 'SSH (Test Box)', 'ssh: profile title mismatch: ' +
      ShellProfileTitle(ProfileId));
    Assert.IsTrue(ShellProfileTitle(cShellProfileSshPrefix + 'not-a-real-id') = 'SSH (unknown connection)',
      'ssh: profile title for unknown id mismatch');

    Profiles := EnumerateShellProfiles;
    FoundSsh := False;
    for P in Profiles do
      if P.Id = ProfileId then
        FoundSsh := True;
    Assert.IsTrue(FoundSsh, 'Saved SSH connection not found in EnumerateShellProfiles');

    // ssh.exe may not be installed in every CI/sandbox environment -- only
    // assert command-line shape when the profile reports itself available,
    // mirroring how the WSL distro test above guards on availability.
    if ShellProfileAvailable(ProfileId) then
    begin
      Assert.IsTrue(ResolveShellCmdLine(ProfileId, 'C:\Ignored', CmdLine, WorkingDir),
        'ssh: profile resolve failed');
      Assert.IsTrue(CmdLine.Contains('ssh.exe'), 'ssh: cmdline missing ssh.exe: ' + CmdLine);
      Assert.IsTrue(CmdLine.Contains('-p 2222'), 'ssh: cmdline missing port: ' + CmdLine);
      Assert.IsTrue(CmdLine.Contains('-i'), 'ssh: cmdline missing identity flag: ' + CmdLine);
      Assert.IsTrue(CmdLine.Contains('bob@box.example.com'), 'ssh: cmdline missing user@host: ' + CmdLine);
      Assert.IsTrue(WorkingDir = '', 'ssh: profile has no local cwd');
      Assert.IsTrue(ProfileReturnSeq(ProfileId) = #10, 'ssh: profile should submit with a lone LF');
      Assert.IsTrue(BuildCdLineForProfile(ProfileId, 'C:\Local\Path') = '',
        'ssh: profile has no cwd sync line');
    end;

    Assert.IsTrue(not ResolveShellCmdLine(cShellProfileSshPrefix + 'not-a-real-id', 'C:\Ignored',
      CmdLine, WorkingDir), 'ssh: profile resolve should fail for an unknown connection id');
  finally
    if TFile.Exists(TempFile) then
      TFile.Delete(TempFile);
    SshConnectionsResetForTests;
  end;
  Writeln('OK: TestSshProfile passed');
end;

{ TTestShellProfiles }

procedure TTestShellProfiles.TestNormalization;
begin
  TestShellProfiles.TestNormalization;
end;

procedure TTestShellProfiles.TestInteractiveWslDistro;
begin
  TestShellProfiles.TestInteractiveWslDistro;
end;

procedure TTestShellProfiles.TestResolveCmdLine;
begin
  TestShellProfiles.TestResolveCmdLine;
end;

procedure TTestShellProfiles.TestEnumeration;
begin
  TestShellProfiles.TestEnumeration;
end;

procedure TTestShellProfiles.TestSshProfile;
begin
  TestShellProfiles.TestSshProfile;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestShellProfiles);

end.
