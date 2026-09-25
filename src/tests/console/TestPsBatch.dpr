program TestPsBatch;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.Math, Winapi.Windows,
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
    ProfileId := cShellProfilePowerShell;
    OnOutput := procedure(const AText: string) begin GOutput := GOutput + AText; end;
    Assert(StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), LastError);
    Pump(2000);

    WriteInput('echo hello1'#13#10'dir'#13#10'echo hello2'#13#10);
    Pump(10000);

    Writeln('hello1=', Pos('hello1', GOutput) > 0);
    Writeln('hello2=', Pos('hello2', GOutput) > 0);
    Writeln('Mode=', Pos('Mode', GOutput) > 0);
    Writeln('len=', Length(GOutput));
    Terminate;
  finally
    Free;
  end;
end.
