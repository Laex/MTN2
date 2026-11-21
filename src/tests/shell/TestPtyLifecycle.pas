unit TestPtyLifecycle;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPtyLifecycle = class
  public
    [Test] procedure TestTerminateClearsCallbacks;
    [Test] procedure TestHasChildProcessWhileCommandRuns;
    [Test] procedure TestConsoleChildCountsButGuiChildDoesNot;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, Winapi.Windows,
  uConPty,
  uShellProfiles;

var
  GOutput: string;
  GExitCalls: Integer;

procedure Pump(AMs: Integer);
var
  UntilTick: UInt64;
  Msg: TMsg;
begin
  UntilTick := GetTickCount64 + UInt64(AMs);
  while GetTickCount64 < UntilTick do
  begin
    while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
    CheckSynchronize;
    Sleep(5);
  end;
end;

// A persistent shell at its prompt has no child process (conhost.exe is the
// pseudoconsole's host and does not count); while a command runs it has one.
procedure TestHasChildProcessWhileCommandRuns;
var
  Pty: TConPtySession;
  Busy: Boolean;
  UntilTick: UInt64;
begin
  Pty := TConPtySession.Create;
  try
    Pty.OnOutput := procedure(const AText: string)
      begin
      end;
    Assert.IsTrue(Pty.StartShell(cShellProfileCmd, GetCurrentDir, 80, 25),
      'StartShell failed: ' + Pty.LastError);
    Pump(1500);
    Assert.IsFalse(Pty.HasChildProcess, 'shell at its prompt is not busy');

    Pty.WriteInput('ping -n 4 127.0.0.1' + #13#10);
    Busy := False;
    UntilTick := GetTickCount64 + 2000;
    while not Busy and (GetTickCount64 < UntilTick) do
    begin
      Pump(100);
      Busy := Pty.HasChildProcess;
    end;
    Assert.IsTrue(Busy, 'shell running ping is busy');

    UntilTick := GetTickCount64 + 10000;
    while Busy and (GetTickCount64 < UntilTick) do
    begin
      Pump(200);
      Busy := Pty.HasChildProcess;
    end;
    Assert.IsFalse(Busy, 'free again once the command ends');
  finally
    Pty.Free;
  end;
end;

// A console command counts as a console child; a GUI program the shell
// launched and left running is a child too, but not a console one.
procedure TestConsoleChildCountsButGuiChildDoesNot;
var
  Pty: TConPtySession;
  Script: string;
  Seen: Boolean;
  UntilTick: UInt64;
begin
  Script := TPath.Combine(TPath.GetTempPath, 'mtn_gui_child.vbs');
  TFile.WriteAllText(Script, 'WScript.Sleep 6000');
  Pty := TConPtySession.Create;
  try
    Pty.OnOutput := procedure(const AText: string)
      begin
      end;
    Assert.IsTrue(Pty.StartShell(cShellProfileCmd, GetCurrentDir, 80, 25),
      'StartShell failed: ' + Pty.LastError);
    Pump(1500);
    Assert.IsFalse(Pty.HasConsoleChildProcess, 'bare prompt has no console child');

    Pty.WriteInput('ping -n 4 127.0.0.1' + #13#10);
    Seen := False;
    UntilTick := GetTickCount64 + 2000;
    while not Seen and (GetTickCount64 < UntilTick) do
    begin
      Pump(100);
      Seen := Pty.HasConsoleChildProcess;
    end;
    Assert.IsTrue(Seen, 'a running console command is a console child');

    UntilTick := GetTickCount64 + 10000;
    while Seen and (GetTickCount64 < UntilTick) do
    begin
      Pump(200);
      Seen := Pty.HasConsoleChildProcess;
    end;
    Assert.IsFalse(Seen, 'the command ended');

    Pty.WriteInput('start wscript.exe //B //Nologo "' + Script + '"' + #13#10);
    Seen := False;
    UntilTick := GetTickCount64 + 3000;
    while not Seen and (GetTickCount64 < UntilTick) do
    begin
      Pump(100);
      Seen := Pty.HasChildProcess;
    end;
    Assert.IsTrue(Seen, 'the launched GUI program is a child of the shell');
    Assert.IsFalse(Pty.HasConsoleChildProcess, 'a GUI child is not a console child');
  finally
    Pty.Free;
    TFile.Delete(Script);
  end;
end;

procedure TestTerminateClearsCallbacks;
var
  Pty: TConPtySession;
  Marker: string;
begin
  Marker := 'LIFE_' + IntToStr(GetTickCount64);
  GOutput := '';
  GExitCalls := 0;

  Pty := TConPtySession.Create;
  try
    Pty.OnOutput := procedure(const AText: string)
      begin
        GOutput := GOutput + AText;
      end;
    Pty.OnExit := procedure(ACode: DWORD)
      begin
        Inc(GExitCalls);
      end;

    Assert.IsTrue(Pty.StartShell(cShellProfileCmd, GetCurrentDir, 80, 25),
      'StartShell failed: ' + Pty.LastError);
    Pty.WriteInput('echo ' + Marker + #13#10);
    Pump(3000);
    Assert.IsTrue(Pos(Marker, GOutput) > 0, 'expected shell output before terminate');

    Pty.Terminate;
    Pump(500);
    Assert.IsTrue(not Pty.IsRunning, 'shell must stop after Terminate');

    // Queued flushes after Terminate must not append (epoch + nil callbacks).
    GOutput := '';
    Pump(500);
    Assert.IsTrue(GOutput = '', 'no output after Terminate with cleared callbacks');
  finally
    Pty.Free;
  end;
end;

{ TTestPtyLifecycle }

procedure TTestPtyLifecycle.TestTerminateClearsCallbacks;
begin
  TestPtyLifecycle.TestTerminateClearsCallbacks;
end;

procedure TTestPtyLifecycle.TestHasChildProcessWhileCommandRuns;
begin
  TestPtyLifecycle.TestHasChildProcessWhileCommandRuns;
end;

procedure TTestPtyLifecycle.TestConsoleChildCountsButGuiChildDoesNot;
begin
  TestPtyLifecycle.TestConsoleChildCountsButGuiChildDoesNot;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPtyLifecycle);

end.
