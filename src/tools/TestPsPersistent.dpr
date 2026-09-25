program TestPsPersistent;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.Math, Winapi.Windows,
  uConPty in '..\Core\uConPty.pas',
  uShellProfiles in '..\Core\uShellProfiles.pas';

var
  GOutput: string;
  GExited: Boolean;
  GExitCode: DWORD;

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
  GExited := False;
  with TConPtySession.Create do
  try
    ProfileId := cShellProfilePowerShell;
    OnOutput := procedure(const AText: string)
      begin
        GOutput := GOutput + AText;
      end;
    OnExit := procedure(ACode: DWORD)
      begin
        GExited := True;
        GExitCode := ACode;
      end;
    Assert(StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), LastError);

    WriteInput('echo hello1'#13#10);
    Pump(2000);
    Assert(not GExited, 'PowerShell exited after echo');

    WriteInput('dir'#13#10);
    Pump(8000);
    Assert(not GExited, 'PowerShell exited after dir (pipe backpressure bug)');
    Assert(IsRunning, 'PowerShell not running after dir');

    WriteInput('echo hello2'#13#10);
    Pump(8000);
    Assert(not GExited, 'PowerShell exited after second command');
    Assert(IsRunning, 'PowerShell must stay running after dir + echo');

    Terminate;
    Pump(500);
    Writeln('TestPsPersistent passed.');
  finally
    Free;
  end;
end.
