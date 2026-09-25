program TestPsSequence;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty in '..\Core\uConPty.pas',
  uShellProfiles in '..\Core\uShellProfiles.pas';

var
  Pty: TConPtySession;
  GAll: string;

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

procedure Send(const ACmd: string);
var
  Delta: string;
  Before: Integer;
begin
  Before := Length(GAll);
  Delta := '';
  Pty.OnOutput := procedure(const AText: string)
    begin
      GAll := GAll + AText;
      Delta := Delta + AText;
    end;
  Writeln('>> ', ACmd, ' running=', Pty.IsRunning);
  Pty.WriteInput(ACmd + #13#10);
  if Pty.LastError <> '' then
    Writeln('   WriteInput error: ', Pty.LastError);
  Pump(5000);
  Writeln('   delta=', Length(GAll) - Before, ' running=', Pty.IsRunning,
    ' has hello2=', Pos('hello2', Delta) > 0, ' has Mode=', Pos('Mode', Delta) > 0);
end;

begin
  GAll := '';
  Pty := TConPtySession.Create;
  try
    Pty.ProfileId := cShellProfilePowerShell;
    Assert(Pty.StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), Pty.LastError);
    Pump(2000);
    Send('echo hello1');
    Send('dir');
    Send('echo hello2');
    Send('pwd');
    Writeln('total len=', Length(GAll));
    Pty.Terminate;
  finally
    Pty.Free;
  end;
end.
