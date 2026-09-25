program TestCmdBatch;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty in '..\..\Core\uConPty.pas',
  uShellProfiles in '..\..\Core\uShellProfiles.pas';

var
  GOutput: string;

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

begin
  GOutput := '';
  with TConPtySession.Create do
  try
    ProfileId := cShellProfileCmd;
    OnOutput := procedure(const AText: string) begin GOutput := GOutput + AText; end;
    Assert(StartShell(cShellProfileCmd, GetCurrentDir, 80, 25), LastError);
    Pump(1000);
    WriteInput('echo hello1'#13#10'echo hello2'#13#10'dir'#13#10);
    Pump(5000);
    Writeln('hello1=', Pos('hello1', GOutput) > 0);
    Writeln('hello2=', Pos('hello2', GOutput) > 0);
    Writeln('Volume=', Pos('Volume', GOutput) > 0);
    Terminate;
  finally
    Free;
  end;
end.
