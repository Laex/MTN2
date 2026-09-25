program TestPsDirBetween;

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

begin
  GOutput := '';
  with TConPtySession.Create do
  try
    ProfileId := cShellProfilePowerShell;
    OnOutput := procedure(const AText: string) begin GOutput := GOutput + AText; end;
    Assert(StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), LastError);
    Pump(2000);
    WriteInput('echo hello1'#13#10);
    Pump(2000);
    Writeln('after hello1 hello2=', Pos('hello2', GOutput), ' Mode=', Pos('Mode', GOutput));
    WriteInput('dir'#13#10);
    Pump(8000);
    Writeln('after dir len=', Length(GOutput), ' hello2=', Pos('hello2', GOutput), ' Mode=', Pos('Mode', GOutput));
    WriteInput('echo hello2'#13#10);
    Pump(8000);
    Writeln('after hello2 len=', Length(GOutput), ' hello2=', Pos('hello2', GOutput));
    Terminate;
  finally
    Free;
  end;
end.
