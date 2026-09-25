program TestPsDirOnly2;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty in '..\..\Core\uConPty.pas',
  uShellProfiles in '..\..\Core\uShellProfiles.pas';

var
  GOutput: string;
  CmdLine, Wd: string;

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
    Assert(ResolveShellCmdLine(cShellProfilePowerShell, GetCurrentDir, CmdLine, Wd), 'resolve');
    Writeln('cmdline=', Copy(CmdLine, 1, 120));
    Assert(StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), LastError);
    Pump(2000);
    WriteInput('ls'#10);
    Pump(15000);
    Writeln('len=', Length(GOutput), ' Mode=', Pos('Mode', GOutput) > 0, ' err=', LastError);
    Writeln(Copy(GOutput, 1, 200));
    Terminate;
  finally
    Free;
  end;
end.
