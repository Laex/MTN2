program TestInspectLxss;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.SyncObjs, Winapi.Windows,
  uShellProfiles, uConPty;

procedure Inspect;
var
  Pty: TConPtySession;
  Done: Boolean;
  WaitCount: Integer;
begin
  Writeln('=== Testing TConPtySession with wsl:Ubuntu-24.04 ===');
  Done := False;
  Pty := TConPtySession.Create;
  try
    Pty.OnOutput := procedure(const AText: string)
      begin
        Writeln('[PtyOut] ', AText);
      end;
    Pty.OnExit := procedure(ACode: DWORD)
      begin
        Writeln('[PtyExit] ExitCode = ', ACode);
        Done := True;
      end;

    if Pty.StartShell('wsl:Ubuntu-24.04', 'D:\Work', 80, 25) then
    begin
      Writeln('StartShell returned True');
      Pty.WriteInput(#10);
      WaitCount := 0;
      while not Done and (WaitCount < 50) do
      begin
        Sleep(100);
        Inc(WaitCount);
      end;
    end
    else
      Writeln('StartShell failed: ', Pty.LastError);
  finally
    Pty.Free;
  end;
end;

begin
  try
    Inspect;
  except
    on E: Exception do
      Writeln('Error: ', E.Message);
  end;
end.
