unit TestCmdBackspaceFlow;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCmdBackspaceFlow = class
  public
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestCrElWipesPrompt;
    [Test] procedure TestUncPromptBackspace;
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

procedure SimulateCmdLocalEchoSession;
var
  Buf: TConsoleBuffer;
  Pty: TConPtySession;
  Chunk: string;
begin
  Buf := TConsoleBuffer.Create;
  Pty := TConPtySession.Create;
  try
    Pty.OnOutput := procedure(const AText: string)
      begin
        Chunk := AText;
        Buf.AppendOutputEx(AText);
      end;
    if not Pty.StartShell('cmd', GetCurrentDir, 80, 25) then
      raise Exception.Create(Pty.LastError);

    Pump(800);
    DumpLine(Buf, 'after prompt');

    // local echo typing
    Buf.AppendOutputEx('dir');
    DumpLine(Buf, 'after type dir');

    // local echo backspace x3
    Buf.AppendOutputEx(#8#8#8);
    DumpLine(Buf, 'after BSx3 at dir');

    Buf.AppendOutputEx(#8#8#8);
    DumpLine(Buf, 'after BSx3 at prompt');

    // send real backspaces to cmd too
    Pty.WriteInput('echo test'#13#10);
    Pump(1500);
    DumpLine(Buf, 'after echo test');

    Pty.Terminate;
    Pump(200);
  finally
    Pty.Free;
    Buf.Free;
  end;
end;

procedure TestCrElWipesPrompt;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    // Prompt and typed command arrive as separate chunks in production (see
    // TestConsoleBufferCmd.TestCmdEchoBackspaceSpace) — a combined string here
    // would hit FixPromptNewlines' unrelated prompt-glued-to-content split.
    Buf.AppendOutputEx('D:\Work\MTN2>');
    Buf.AppendOutputEx('abc');
    DumpLine(Buf, 'initial');
    // CR+EL alone must not wipe before the redraw arrives
    Buf.AppendOutputEx(#13#27'[K');
    DumpLine(Buf, 'after CR+EL only');
    Assert.AreEqual('D:\Work\MTN2>abc', Buf.GetLine(Buf.LineCount - 1), 'CR+EL deferred until redraw');
    Buf.AppendOutputEx('D:\Work\MTN2>ab');
    DumpLine(Buf, 'after rewrite');
    Assert.AreEqual('D:\Work\MTN2>ab', Buf.GetLine(Buf.LineCount - 1), 'redraw after deferred EL');
    Buf.AppendOutputEx(#13'D:\Work\MTN2>a'#27'[K');
    Assert.AreEqual('D:\Work\MTN2>a', Buf.GetLine(Buf.LineCount - 1), 'after full backspace redraw');
  finally
    Buf.Free;
  end;
end;

procedure TestUncPromptBackspace;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('\\server\share>abc');
    Buf.AppendOutputEx(#8#8#8#8);
    Assert.AreEqual('\\server\share>', Buf.GetLine(Buf.LineCount - 1), 'UNC prompt protected');
  finally
    Buf.Free;
  end;
end;

{ TTestCmdBackspaceFlow }

procedure TTestCmdBackspaceFlow.TearDownFixture;
begin
  SimulateCmdLocalEchoSession;
end;

procedure TTestCmdBackspaceFlow.TestCrElWipesPrompt;
begin
  TestCmdBackspaceFlow.TestCrElWipesPrompt;
end;

procedure TTestCmdBackspaceFlow.TestUncPromptBackspace;
begin
  TestCmdBackspaceFlow.TestUncPromptBackspace;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCmdBackspaceFlow);

end.
