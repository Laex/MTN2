program TestPsCharByChar;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.Math, Winapi.Windows,
  uConPty in '..\..\Core\uConPty.pas',
  uShellProfiles in '..\..\Core\uShellProfiles.pas';

var
  GOutput: string;
  Pty: TConPtySession;

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

procedure SendChars(Pty: TConPtySession; const S: string);
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    Pty.WriteInput(S[I]);
end;

begin
  GOutput := '';
  Pty := TConPtySession.Create;
  try
    Pty.ProfileId := cShellProfilePowerShell;
    Pty.OnOutput := procedure(const AText: string) begin GOutput := GOutput + AText; end;
    Assert(Pty.StartShell(cShellProfilePowerShell, 'D:\Work', 80, 25), Pty.LastError);
    Pump(2000);

    SendChars(Pty, 'ls');
    Pty.WriteInput(ProfileReturnSeq(cShellProfilePowerShell));
    Pump(4000);

    Writeln('Output length=', Length(GOutput));
    Writeln('Has Mode/Directory=', (Pos('Mode', GOutput) > 0) or (Pos('----', GOutput) > 0));
    Writeln('--- tail ---');
    Writeln(Copy(GOutput, Max(Length(GOutput)-300, 1), 300));

    if (Pos('Mode', GOutput) = 0) and (Pos('----', GOutput) = 0) then
      raise Exception.Create('ls did not execute with char-by-char input');

    Writeln('TestPsCharByChar passed.');
    Pty.Terminate;
  finally
    Pty.Free;
  end;
end.
