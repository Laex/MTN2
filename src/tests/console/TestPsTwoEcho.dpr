program TestPsTwoEcho;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty in '..\..\Core\uConPty.pas',
  uShellProfiles in '..\..\Core\uShellProfiles.pas';

var
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

begin
  GAll := '';
  with TConPtySession.Create do
  try
    ProfileId := cShellProfilePowerShell;
    OnOutput := procedure(const AText: string) begin GAll := GAll + AText; end;
    Assert(StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), LastError);
    Pump(2000);

    WriteInput('echo hello1'#13#10);
    Pump(3000);
    Writeln('after1 tail=', Copy(GAll, 1, 80));

    WriteInput('echo hello2'#13#10);
    Pump(3000);
    Writeln('after2 len=', Length(GAll), ' err=', LastError, ' hello2=', Pos('hello2', GAll) > 0);

    WriteInput('echo hello3'#13#10);
    Pump(3000);
    Writeln('after3 len=', Length(GAll), ' hello3=', Pos('hello3', GAll) > 0);

    Terminate;
  finally
    Free;
  end;
end.
