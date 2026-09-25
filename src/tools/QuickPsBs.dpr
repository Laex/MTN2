program QuickPsBs;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, Winapi.Windows,
  uConsoleBuffer in ''..\Core\uConsoleBuffer.pas'',
  uANSIParser in ''..\Core\uANSIParser.pas'',
  uTerminalTypes in ''..\Core\uTerminalTypes.pas'',
  uConPty in ''..\Core\uConPty.pas'';
procedure Pump(AMs: Integer); var UntilTick: UInt64; Msg: TMsg;
begin UntilTick := GetTickCount64 + UInt64(AMs);
  while GetTickCount64 < UntilTick do begin while PeekMessage(Msg,0,0,0,PM_REMOVE) do begin TranslateMessage(Msg); DispatchMessage(Msg); end; CheckSynchronize; Sleep(5); end; end;
var Buf: TConsoleBuffer; Pty: TConPtySession; I: Integer;
begin
  Buf := TConsoleBuffer.Create; Pty := TConPtySession.Create;
  try
    Pty.OnOutput := procedure(const AText: string) begin Buf.AppendOutputEx(AText); end;
    Pty.StartShell(''powershell'', GetCurrentDir, 80, 25); Pump(1200);
    Pty.WriteInput(''x''); Pump(300); Pty.WriteInput(#8); Pump(300);
    for I := 1 to 10 do begin
      Pty.WriteInput(#8); Pump(200);
      Writeln(I, '': '', Buf.GetLine(Buf.LineCount - 1));
    end;
    Pty.Terminate; Pump(200);
  finally Pty.Free; Buf.Free; end;
end.
