program TestCdDirQuote;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty in '..\..\Core\uConPty.pas',
  uShellProfiles in '..\..\Core\uShellProfiles.pas';

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

procedure TestCdThenDir(const ACwd, ALabel: string);
var
  Pty: TConPtySession;
  OutText: string;
begin
  Writeln('TestCdThenDir: ', ALabel);
  OutText := '';
  Pty := TConPtySession.Create;
  try
    Pty.OnOutput := procedure(const AText: string)
      begin
        OutText := OutText + AText;
      end;
    Pty.ProfileId := 'cmd';
    if not Pty.StartShell('cmd', GetCurrentDir, 80, 25) then
      raise Exception.Create(Pty.LastError);
    Pump(600);
    OutText := '';
    Pty.WriteInput(BuildCmdCdLine(ACwd));
    Pump(600);
    OutText := '';
    Pty.WriteInput('dir'#13#10);
    Pump(2500);
    if Pos('dir"', OutText) > 0 then
      raise Exception.CreateFmt('cmd saw dir" after cd to %s: %s',
        [ACwd, Copy(OutText, 1, 300)]);
    if Pos('не является', OutText) > 0 then
      if Pos('dir', OutText) > 0 then
        raise Exception.CreateFmt('dir failed after cd to %s: %s',
          [ACwd, Copy(OutText, 1, 300)]);
    Writeln('  OK  ', ALabel);
    Pty.Terminate;
    Pump(200);
  finally
    Pty.Free;
  end;
end;

begin
  try
    TestCdThenDir('C:\', 'drive root');
    TestCdThenDir('D:\Program Files\MTN2\', 'spaced path with trailing slash');
    TestCdThenDir('D:\Work\Delphi\MTN2\src\tools', 'normal path');
    Writeln('TestCdDirQuote passed.');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.Message);
      Halt(1);
    end;
  end;
end.
