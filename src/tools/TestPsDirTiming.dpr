program TestPsDirTiming;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty in '..\Core\uConPty.pas',
  uShellProfiles in '..\Core\uShellProfiles.pas';

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

procedure Run(const ALabel: string; APumpBefore: Integer);
begin
  GOutput := '';
  with TConPtySession.Create do
  try
    ProfileId := cShellProfilePowerShell;
    OnOutput := procedure(const AText: string) begin GOutput := GOutput + AText; end;
    Assert(StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), LastError);
    if APumpBefore > 0 then
      Pump(APumpBefore);
    WriteInput('dir'#13#10);
    Pump(10000);
    Writeln(ALabel, ' len=', Length(GOutput), ' Mode=', Pos('Mode', GOutput) > 0);
    Terminate;
  finally
    Free;
  end;
end;

begin
  Run('immediate', 0);
  Run('after2s', 2000);
end.
