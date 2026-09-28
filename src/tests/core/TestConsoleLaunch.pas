unit TestConsoleLaunch;

{ uConsoleLaunch: which files are console programs (PE subsystem, script
  extensions), where Enter runs them (the background console when it is a
  free Windows shell, else a terminal tab; GUI programs and documents stay
  with the Windows shell), and the line typed into cmd / PowerShell. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConsoleLaunch = class
  public
    [Test] procedure TestDetectKind;
    [Test] procedure TestSystemPrograms;
    [Test] procedure TestChooseTarget;
    [Test] procedure TestLaunchLine;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, uConsoleLaunch, uShellProfiles;

// A minimal PE image: MZ stub pointing at a PE header with ASubsystem.
procedure WritePe(const APath: string; ASubsystem: Word);
var
  B: TBytes;
  PeOffset: Cardinal;
begin
  SetLength(B, 512);
  FillChar(B[0], Length(B), 0);
  B[0] := Ord('M');
  B[1] := Ord('Z');
  PeOffset := $80;
  Move(PeOffset, B[$3C], 4);
  B[PeOffset] := Ord('P');
  B[PeOffset + 1] := Ord('E');
  Move(ASubsystem, B[PeOffset + 4 + 20 + 68], 2);
  TFile.WriteAllBytes(APath, B);
end;

procedure TTestConsoleLaunch.TestDetectKind;
var
  Dir: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-console-launch-test');
  TDirectory.CreateDirectory(Dir);
  try
    WritePe(TPath.Combine(Dir, 'tool.exe'), 3);
    WritePe(TPath.Combine(Dir, 'app.exe'), 2);
    TFile.WriteAllText(TPath.Combine(Dir, 'broken.exe'), 'not a program');
    TFile.WriteAllText(TPath.Combine(Dir, 'build.bat'), '@echo off');
    TFile.WriteAllText(TPath.Combine(Dir, 'setup.CMD'), '@echo off');
    TFile.WriteAllText(TPath.Combine(Dir, 'deploy.ps1'), 'Write-Host 1');
    TFile.WriteAllText(TPath.Combine(Dir, 'readme.txt'), 'text');
    Assert.IsTrue(DetectLaunchFileKind(TPath.Combine(Dir, 'tool.exe')) = lfkConsoleExe,
      'console subsystem');
    Assert.IsTrue(DetectLaunchFileKind(TPath.Combine(Dir, 'app.exe')) = lfkOther,
      'GUI subsystem stays with the Windows shell');
    Assert.IsTrue(DetectLaunchFileKind(TPath.Combine(Dir, 'broken.exe')) = lfkOther,
      'no PE header');
    Assert.IsTrue(DetectLaunchFileKind(TPath.Combine(Dir, 'missing.exe')) = lfkOther,
      'unreadable file');
    Assert.IsTrue(DetectLaunchFileKind(TPath.Combine(Dir, 'build.bat')) = lfkBatch, '.bat');
    Assert.IsTrue(DetectLaunchFileKind(TPath.Combine(Dir, 'setup.CMD')) = lfkBatch,
      '.cmd, any case');
    Assert.IsTrue(DetectLaunchFileKind(TPath.Combine(Dir, 'deploy.ps1')) = lfkPowerShell, '.ps1');
    Assert.IsTrue(DetectLaunchFileKind(TPath.Combine(Dir, 'readme.txt')) = lfkOther, 'document');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestConsoleLaunch.TestSystemPrograms;
var
  Sys: string;
begin
  Sys := TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32');
  if not TFile.Exists(TPath.Combine(Sys, 'cmd.exe')) then
  begin
    Assert.Pass('no System32');
    Exit;
  end;
  Assert.IsTrue(DetectLaunchFileKind(TPath.Combine(Sys, 'cmd.exe')) = lfkConsoleExe,
    'cmd.exe is a console program');
  if TFile.Exists(TPath.Combine(Sys, 'notepad.exe')) then
    Assert.IsTrue(DetectLaunchFileKind(TPath.Combine(Sys, 'notepad.exe')) = lfkOther,
      'notepad.exe is a GUI program');
end;

procedure TTestConsoleLaunch.TestChooseTarget;
begin
  Assert.IsTrue(ChooseConsoleLaunch(lfkOther, cShellProfileCmd, False) = cltShellOpen,
    'not a console program');
  Assert.IsTrue(ChooseConsoleLaunch(lfkConsoleExe, cShellProfileCmd, False) = cltConsole,
    'free cmd console');
  Assert.IsTrue(ChooseConsoleLaunch(lfkBatch, cShellProfilePowerShell, False) = cltConsole,
    'free PowerShell console');
  Assert.IsTrue(ChooseConsoleLaunch(lfkPowerShell, cShellProfilePwsh, False) = cltConsole,
    'free pwsh console');
  Assert.IsTrue(ChooseConsoleLaunch(lfkConsoleExe, cShellProfileCmd, True) = cltTerminal,
    'busy console: a terminal tab');
  Assert.IsTrue(ChooseConsoleLaunch(lfkConsoleExe, cShellProfileWsl, False) = cltTerminal,
    'WSL console: a terminal tab');
  Assert.IsTrue(ChooseConsoleLaunch(lfkBatch, cShellProfileGitBash, False) = cltTerminal,
    'Git Bash console: a terminal tab');
  Assert.AreEqual(cShellProfilePowerShell, TerminalProfileForLaunch(lfkPowerShell),
    '.ps1 tab runs PowerShell');
  Assert.AreEqual(cShellProfileCmd, TerminalProfileForLaunch(lfkBatch), 'other tabs run cmd');
end;

procedure TTestConsoleLaunch.TestLaunchLine;
begin
  Assert.AreEqual('"C:\Tools\my tool.exe"',
    BuildConsoleLaunchLine('C:\Tools\my tool.exe', lfkConsoleExe, cShellProfileCmd), 'cmd: quoted');
  Assert.AreEqual('"C:\b.bat"', BuildConsoleLaunchLine('C:\b.bat', lfkBatch, cShellProfileCmd),
    'cmd: batch file');
  Assert.AreEqual('powershell -NoLogo -File "C:\s p.ps1"',
    BuildConsoleLaunchLine('C:\s p.ps1', lfkPowerShell, cShellProfileCmd),
    'cmd: a script through PowerShell');
  Assert.AreEqual('& ''C:\it''''s\x.ps1''',
    BuildConsoleLaunchLine('C:\it''s\x.ps1', lfkPowerShell, cShellProfilePowerShell),
    'PowerShell: call operator, quote doubled');
  Assert.AreEqual('& ''C:\x.exe''',
    BuildConsoleLaunchLine('C:\x.exe', lfkConsoleExe, cShellProfilePwsh), 'pwsh: call operator');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsoleLaunch);

end.
