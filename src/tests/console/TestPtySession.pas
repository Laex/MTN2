unit TestPtySession;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPtySession = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty;

var
  GOutput: string;
  GExited: Boolean;
  GExitCode: DWORD;

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

procedure WaitForMarker(const AMarker: string; ATimeoutMs: Integer);
var
  UntilTick: UInt64;
begin
  UntilTick := GetTickCount64 + UInt64(ATimeoutMs);
  while GetTickCount64 < UntilTick do
  begin
    Pump(50);
    if Pos(AMarker, GOutput) > 0 then
      Exit;
  end;
  raise Exception.CreateFmt('Timeout waiting for marker "%s". Output=%s',
    [AMarker, Copy(GOutput, 1, 400)]);
end;

procedure RunTests;
var
  Pty: TConPtySession;
  Marker, CyrSuffix: string;
begin
  CyrSuffix := WideChar($0422) + WideChar($0435) + WideChar($0441) + WideChar($0442) + '_' +
    WideChar($041F) + WideChar($0438) + WideChar($0432) + WideChar($0435) + WideChar($0442);
  Marker := 'MTN2_STAGE16_' + IntToStr(GetTickCount64);

  Pty := TConPtySession.Create;
  try
    GOutput := '';
    GExited := False;
    GExitCode := 0;

    Pty.OnOutput := procedure(const AText: string)
      begin
        GOutput := GOutput + AText;
      end;
    Pty.OnExit := procedure(ACode: DWORD)
      begin
        GExited := True;
        GExitCode := ACode;
      end;

    Assert.IsTrue(Pty.StartShell('cmd', GetCurrentDir, 80, 25), 'StartShell should succeed: ' + Pty.LastError);

    Assert.IsTrue(Pty.IsRunning, 'Shell should be running');
    Assert.IsTrue(Pty.Persistent, 'Shell should be persistent');

    Pty.WriteInput('echo ' + Marker + #13#10);
    Assert.IsTrue(Pty.LastError = '', 'WriteInput error: ' + Pty.LastError);
    WaitForMarker(Marker, 8000);

    Pty.WriteInput('echo ' + Marker + '_B' + #13#10);
    WaitForMarker(Marker + '_B', 8000);

    Pty.WriteInput('echo ' + Marker + '_' + CyrSuffix + #13#10);
    WaitForMarker(Marker + '_' + CyrSuffix, 8000);

    // Test native Windows find.exe output decoding (ASCII marker in output).
    Pty.WriteInput('find' + #13#10);
    WaitForMarker('FIND:', 8000);
    Assert.IsTrue((Pos('Неправильный', GOutput) > 0) or (Pos('FIND:', GOutput) > 0),
      'Output must include find usage or localized error');

    Assert.IsTrue(Pty.IsRunning, 'Shell should still be running after two commands');

    Pty.Terminate;
    Pump(200);
    Assert.IsTrue(not Pty.IsRunning, 'Shell should stop after Terminate');
  finally
    Pty.Free;
  end;

  // One-shot fallback still works.
  Pty := TConPtySession.Create;
  try
    GOutput := '';
    GExited := False;
    Assert.IsTrue(Pty.Start('echo ' + Marker + '_ONESHOT', GetCurrentDir, 80, 25,
      procedure(const AText: string)
      begin
        GOutput := GOutput + AText;
      end,
      procedure(ACode: DWORD)
      begin
        GExited := True;
        GExitCode := ACode;
      end), 'One-shot Start should succeed: ' + Pty.LastError);
    WaitForMarker(Marker + '_ONESHOT', 8000);
    Pump(500);
    Assert.IsTrue(GExited or (not Pty.IsRunning), 'One-shot should exit');
  finally
    Pty.Free;
  end;

  Writeln('TestPtySession passed successfully.');
end;

{ TTestPtySession }

procedure TTestPtySession.Run;
begin
  RunTests;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPtySession);

end.
