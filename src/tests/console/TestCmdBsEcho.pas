unit TestCmdBsEcho;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCmdBsEcho = class
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

{ TTestCmdBsEcho }

procedure TTestCmdBsEcho.Run;
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

    // simulate TerminalWorkspace cmd local echo
    Buf.AppendOutputEx('abc');
    DumpLine(Buf, 'local abc');
    Pty.WriteInput('abc');
    Pump(300);
    System.Writeln('shell echo after abc: len=', Length(ShellOut));

    ShellOut := '';
    Buf.AppendOutputEx(#8#8#8);
    DumpLine(Buf, 'local BSx3');
    Pty.WriteInput(#8#8#8);
    Pump(300);
    System.Writeln('shell echo after BS: "', ShellOut, '"');

    Buf.AppendOutputEx(#8#8#8#8#8);
    DumpLine(Buf, 'local BSx6 at prompt');

    ShellOut := '';
    Pty.WriteInput('dir'#13#10);
    Pump(2000);
    DumpLine(Buf, 'after dir');

    Pty.Terminate;
    Pump(200);
  finally
    Pty.Free;
    Buf.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCmdBsEcho);

end.
