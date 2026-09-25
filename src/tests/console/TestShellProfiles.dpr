program TestShellProfiles;

uses
  System.SysUtils, System.IOUtils,
  uShellProfiles in '..\..\Core\uShellProfiles.pas',
  uSshConnections in '..\..\Core\uSshConnections.pas';

procedure TestNormalization;
begin
  Assert(NormalizeShellProfileId('cmd.exe') = cShellProfileCmd, 'cmd.exe normalization failed');
  Assert(NormalizeShellProfileId('powershell.exe') = cShellProfilePowerShell, 'powershell.exe normalization failed');
  Assert(NormalizeShellProfileId('pwsh.exe') = cShellProfilePwsh, 'pwsh.exe normalization failed');
  Assert(NormalizeShellProfileId('wsl.exe') = cShellProfileWsl, 'wsl.exe normalization failed');
  Assert(NormalizeShellProfileId('WSL:Ubuntu-24.04') = 'wsl:Ubuntu-24.04', 'wsl:Ubuntu-24.04 normalization failed');
  Writeln('OK: TestNormalization passed');
end;

procedure TestInteractiveWslDistro;
begin
  Assert(IsInteractiveWslDistro('Ubuntu-24.04'), 'Ubuntu is interactive');
  Assert(IsInteractiveWslDistro('Debian'), 'Debian is interactive');
  Assert(not IsInteractiveWslDistro('docker-desktop'), 'docker-desktop is a utility VM');
  Assert(not IsInteractiveWslDistro('docker-desktop-data'), 'docker-desktop-data is a utility VM');
  Assert(not IsInteractiveWslDistro(''), 'empty name is not interactive');
  Assert(not ShellProfileAvailable('wsl:docker-desktop'),
    'docker-desktop must not be an available shell profile');
  Writeln('OK: TestInteractiveWslDistro passed');
end;

procedure TestResolveCmdLine;
var
  CmdLine, WorkingDir: string;
begin
  Assert(ResolveShellCmdLine(cShellProfileCmd, 'C:\Test', CmdLine, WorkingDir), 'Cmd resolve failed');
  Assert(CmdLine = 'cmd.exe /d /q /k', 'Cmd cmdline mismatch');
  Assert(WorkingDir = 'C:\Test', 'Cmd working dir mismatch');

  Assert(ResolveShellCmdLine(cShellProfilePowerShell, 'C:\Test', CmdLine, WorkingDir),
    'PowerShell resolve failed');
  Assert(CmdLine = 'powershell.exe -NoLogo',
    'PowerShell cmdline mismatch: ' + CmdLine);

  Assert(ResolveShellCmdLine(cShellProfilePwsh, 'C:\Test', CmdLine, WorkingDir),
    'pwsh resolve failed');
  Assert(CmdLine = 'pwsh.exe -NoLogo',
    'pwsh cmdline mismatch: ' + CmdLine);

  Assert(QuoteCmdExePath('D:\Program Files\MTN2\') = '"D:\Program Files\MTN2"',
    'QuoteCmdExePath must strip trailing backslash before quote');
  Assert(BuildCmdCdLine('C:\') = 'cd /d C:\'#13#10, 'BuildCmdCdLine drive root');

  Assert(ResolveShellCmdLine(cShellProfileWsl, 'C:\Test', CmdLine, WorkingDir), 'WSL resolve failed');
  Assert(CmdLine.Contains('wsl.exe') and CmdLine.Contains('--cd C:\Test'), 'WSL cmdline mismatch: ' + CmdLine);
  Assert(not CmdLine.Contains('stdbuf'), 'WSL must not require stdbuf: ' + CmdLine);
  Assert(not CmdLine.Contains('--exec'), 'WSL must use the distro default shell: ' + CmdLine);
  Assert(WorkingDir = '', 'WSL working dir mismatch');

  if ShellProfileAvailable('wsl:Ubuntu-24.04') then
  begin
    Assert(ResolveShellCmdLine('wsl:Ubuntu-24.04', 'C:\Test', CmdLine, WorkingDir), 'WSL distro resolve failed');
    Assert(CmdLine.Contains('wsl.exe -d Ubuntu-24.04'), 'WSL distro cmdline mismatch: ' + CmdLine);
    Assert(CmdLine.Contains('--cd C:\Test'), 'WSL distro cd mismatch: ' + CmdLine);
    Assert(WorkingDir = '', 'WSL distro working dir mismatch');
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
  Assert(Length(Profiles) > 0, 'No profiles enumerated');
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
  Assert(FoundCmd, 'Cmd profile not found in enumeration');
  Assert(FoundWsl, 'WSL profile not found in enumeration');
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

    Assert(NormalizeShellProfileId(ProfileId) = ProfileId,
      'ssh: profile id should normalize unchanged (opaque connection id)');

    Assert(ShellProfileTitle(ProfileId) = 'SSH (Test Box)', 'ssh: profile title mismatch: ' +
      ShellProfileTitle(ProfileId));
    Assert(ShellProfileTitle(cShellProfileSshPrefix + 'not-a-real-id') = 'SSH (unknown connection)',
      'ssh: profile title for unknown id mismatch');

    Profiles := EnumerateShellProfiles;
    FoundSsh := False;
    for P in Profiles do
      if P.Id = ProfileId then
        FoundSsh := True;
    Assert(FoundSsh, 'Saved SSH connection not found in EnumerateShellProfiles');

    // ssh.exe may not be installed in every CI/sandbox environment -- only
    // assert command-line shape when the profile reports itself available,
    // mirroring how the WSL distro test above guards on availability.
    if ShellProfileAvailable(ProfileId) then
    begin
      Assert(ResolveShellCmdLine(ProfileId, 'C:\Ignored', CmdLine, WorkingDir),
        'ssh: profile resolve failed');
      Assert(CmdLine.Contains('ssh.exe'), 'ssh: cmdline missing ssh.exe: ' + CmdLine);
      Assert(CmdLine.Contains('-p 2222'), 'ssh: cmdline missing port: ' + CmdLine);
      Assert(CmdLine.Contains('-i'), 'ssh: cmdline missing identity flag: ' + CmdLine);
      Assert(CmdLine.Contains('bob@box.example.com'), 'ssh: cmdline missing user@host: ' + CmdLine);
      Assert(WorkingDir = '', 'ssh: profile has no local cwd');
      Assert(ProfileReturnSeq(ProfileId) = #10, 'ssh: profile should submit with a lone LF');
      Assert(BuildCdLineForProfile(ProfileId, 'C:\Local\Path') = '',
        'ssh: profile has no cwd sync line');
    end;

    Assert(not ResolveShellCmdLine(cShellProfileSshPrefix + 'not-a-real-id', 'C:\Ignored',
      CmdLine, WorkingDir), 'ssh: profile resolve should fail for an unknown connection id');
  finally
    if TFile.Exists(TempFile) then
      TFile.Delete(TempFile);
    SshConnectionsResetForTests;
  end;
  Writeln('OK: TestSshProfile passed');
end;

begin
  try
    Writeln('Running ShellProfiles tests...');
    TestNormalization;
    TestInteractiveWslDistro;
    TestResolveCmdLine;
    TestEnumeration;
    TestSshProfile;
    Writeln('ALL ShellProfiles tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
