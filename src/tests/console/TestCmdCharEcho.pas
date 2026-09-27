unit TestCmdCharEcho;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCmdCharEcho = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConsoleBuffer,
  uANSIParser,
  uTerminalTypes,
  uConPty;

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

procedure DumpLine(const ABuf: TConsoleBuffer; const ALabel: string);
begin
  Writeln(ALabel, ': "', ABuf.GetLine(ABuf.LineCount - 1), '"');
end;

var
  Buf: TConsoleBuffer;
  Pty: TConPtySession;
  ShellOut: string;

{ TTestCmdCharEcho }

procedure TTestCmdCharEcho.Run;
begin
  Buf := TConsoleBuffer.Create;
  Pty := TConPtySession.Create;
  try
    Pty.OnOutput := procedure(const AText: string)
      begin
        ShellOut := ShellOut + AText;
        Buf.AppendOutputEx(AText);
      end;
    Pty.StartShell('cmd', GetCurrentDir, 80, 25);
    Pump(800);
    DumpLine(Buf, 'prompt');

    ShellOut := '';
    Buf.AppendOutputEx('a');
    Pty.WriteInput('a');
    Pump(200);
    DumpLine(Buf, 'after a local+shell len=' + IntToStr(Length(ShellOut)));

    ShellOut := '';
    Buf.AppendOutputEx('b');
    Pty.WriteInput('b');
    Pump(200);
    DumpLine(Buf, 'after b');

    ShellOut := '';
    Buf.AppendOutputEx('c');
    Pty.WriteInput('c');
    Pump(200);
    DumpLine(Buf, 'after c');

    ShellOut := '';
    Buf.AppendOutputEx(#8);
    Pty.WriteInput(#8);
    Pump(200);
    DumpLine(Buf, 'after BS shell="' + ShellOut + '"');

    Pty.Terminate;
    Pump(200);
  finally
    Pty.Free;
    Buf.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCmdCharEcho);

end.
