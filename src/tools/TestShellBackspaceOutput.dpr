program TestShellBackspaceOutput;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty in '..\Core\uConPty.pas',
  uShellProfiles in '..\Core\uShellProfiles.pas';

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

procedure DumpBytes(const S: string);
var
  I: Integer;
begin
  Write('bytes(' + IntToStr(Length(S)) + '): ');
  for I := 1 to Length(S) do
  begin
    case S[I] of
      #8: Write('<BS>');
      #13: Write('<CR>');
      #10: Write('<LF>');
      #27: Write('<ESC>');
    else
      if Ord(S[I]) < 32 then
        Write('#', Ord(S[I]))
      else
        Write(S[I]);
    end;
  end;
  Writeln;
end;

procedure TestProfile(const AProfile, AName: string);
var
  Pty: TConPtySession;
  OutBefore, OutAfter: string;
begin
  Writeln('=== ', AName, ' ===');
  if not ShellProfileAvailable(AProfile) then
  begin
    Writeln('SKIP unavailable');
    Exit;
  end;

  Pty := TConPtySession.Create;
  try
    OutBefore := '';
    Pty.OnOutput := procedure(const AText: string)
      begin
        OutBefore := OutBefore + AText;
      end;
    if not Pty.StartShell(AProfile, GetCurrentDir, 80, 25) then
    begin
      Writeln('Start failed: ', Pty.LastError);
      Exit;
    end;

    Pump(1000);
    OutBefore := '';
    Pty.WriteInput('abc');
    Pump(500);
    Writeln('after abc:');
    DumpBytes(OutBefore);

    OutAfter := '';
    Pty.OnOutput := procedure(const AText: string)
      begin
        OutAfter := OutAfter + AText;
      end;
    Pty.WriteInput(#8#8#8);
    Pump(500);
    Writeln('after 3xBS:');
    DumpBytes(OutAfter);

    OutAfter := '';
    Pty.WriteInput('z'#13#10);
    Pump(2000);
    Writeln('after z+enter (result):');
    DumpBytes(OutAfter);

    Pty.Terminate;
    Pump(200);
  finally
    Pty.Free;
  end;
end;

begin
  TestProfile('cmd', 'cmd');
  TestProfile('powershell', 'powershell');
  TestProfile('pwsh', 'pwsh');
end.
