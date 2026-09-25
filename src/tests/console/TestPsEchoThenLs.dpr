program TestPsEchoThenLs;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty in '..\..\Core\uConPty.pas',
  uShellProfiles in '..\..\Core\uShellProfiles.pas';

var
  G: string;

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
  G := '';
  with TConPtySession.Create do
  try
    ProfileId := cShellProfilePowerShell;
    OnOutput := procedure(const AText: string) begin G := G + AText; end;
    Assert(StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), LastError);
    Pump(2000);
    WriteInput('echo hello1'#10);
    Pump(3000);
    Writeln('after echo len=', Length(G), ' hello=', Pos('hello1', G) > 0);
    WriteInput('Get-ChildItem | Out-String -Width 4096'#10);
    Pump(15000);
    Writeln('after ls len=', Length(G), ' Mode=', Pos('Mode', G) > 0);
    Terminate;
  finally
    Free;
  end;
end.
