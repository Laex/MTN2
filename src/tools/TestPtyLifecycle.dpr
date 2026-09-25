program TestPtyLifecycle;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty in '..\Core\uConPty.pas',
  uShellProfiles in '..\Core\uShellProfiles.pas';

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

procedure TestTerminateClearsCallbacks;
var
  Pty: TConPtySession;
  Marker: string;
begin
  Writeln('TestTerminateClearsCallbacks');
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

    Assert(Pty.StartShell(cShellProfileCmd, GetCurrentDir, 80, 25),
      'StartShell failed: ' + Pty.LastError);
    Pty.WriteInput('echo ' + Marker + #13#10);
    Pump(3000);
    Assert(Pos(Marker, GOutput) > 0, 'expected shell output before terminate');

    Pty.Terminate;
    Pump(500);
    Assert(not Pty.IsRunning, 'shell must stop after Terminate');

    // Queued flushes after Terminate must not append (epoch + nil callbacks).
    GOutput := '';
    Pump(500);
    Assert(GOutput = '', 'no output after Terminate with cleared callbacks');
  finally
    Pty.Free;
  end;
end;

begin
  try
    TestTerminateClearsCallbacks;
    Writeln('TestPtyLifecycle passed.');
  except
    on E: Exception do
    begin
      Writeln('Test failed: ', E.Message);
      Halt(1);
    end;
  end;
end.
