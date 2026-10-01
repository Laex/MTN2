unit TestPtyPromptCount;

{ A finished command shows up as one more prompt line in the console
  buffer; TConsoleWindow uses that to know when to hand back the panels. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPtyPromptCount = class
  public
    [Test] procedure FinishedCommandAddsEmptyPrompt;
  end;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty, uConsoleBuffer, uShellProfiles;

procedure Pump(AMs: Integer);
var
  UntilTick: UInt64;
begin
  UntilTick := GetTickCount64 + UInt64(AMs);
  while GetTickCount64 < UntilTick do
  begin
    CheckSynchronize;
    Sleep(5);
  end;
end;

function Prompts(ABuf: TConsoleBuffer): Integer;
var
  I: Integer;
  Path: string;
begin
  Result := 0;
  for I := 0 to ABuf.LineCount - 1 do
    if ShellCwdFromPrompt('cmd', ABuf.GetLine(I), Path) then
      Inc(Result);
end;

procedure TTestPtyPromptCount.FinishedCommandAddsEmptyPrompt;
var
  Pty: TConPtySession;
  Buf: TConsoleBuffer;
  Before, After: Integer;
  I: Integer;
begin
  Buf := TConsoleBuffer.Create;
  Pty := TConPtySession.Create;
  try
    Pty.OnOutput := procedure(const AText: string)
      begin
        Buf.AppendOutputEx(AText, 80, 25);
      end;
    Assert.IsTrue(Pty.StartShell('cmd', GetCurrentDir, 80, 25), 'StartShell: ' + Pty.LastError);
    Pump(2000);
    Before := Prompts(Buf);
    Assert.IsTrue(Before >= 1, 'the first prompt is recognized');
    Pty.WriteInput('echo done' + #13);
    After := Before;
    for I := 1 to 60 do
    begin
      Pump(100);
      After := Prompts(Buf);
      if After > Before then
        Break;
    end;
    Assert.IsTrue(After > Before, 'another prompt appears once the command finished');
  finally
    Pty.Terminate;
    Pty.Free;
    Buf.Free;
  end;
end;

end.
