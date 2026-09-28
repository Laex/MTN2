unit TestPsRawDump;

{ Diagnostic only (not a pass/fail test): dumps the exact raw bytes PowerShell
  sends over ConPTY at startup and after one WriteInput, with control bytes
  made visible, so a human can see what our ANSI parser / line-buffered
  local-echo logic actually has to deal with. Paste the console output back
  for analysis - this is what TConsoleBuffer.AppendOutputEx receives verbatim. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPsRawDump = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty,
  uShellProfiles;

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

function EscapeDump(const AText: string): string;
var
  C: Char;
  Sb: TStringBuilder;
begin
  Sb := TStringBuilder.Create;
  try
    for C in AText do
    begin
      case Ord(C) of
        27: Sb.Append('\e');
        13: Sb.Append('\r');
        10: Sb.Append('\n' + sLineBreak);
        9:  Sb.Append('\t');
      else
        if (Ord(C) < 32) or (Ord(C) = 127) then
          Sb.Append('\x' + IntToHex(Ord(C), 2))
        else
          Sb.Append(C);
      end;
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

var
  Chunk1, Chunk2: string;
  Chunk2Started: Boolean;

{ TTestPsRawDump }

procedure TTestPsRawDump.Run;
begin
  Chunk1 := '';
  Chunk2 := '';
  Chunk2Started := False;
  with TConPtySession.Create do
  try
    ProfileId := cShellProfilePowerShell;
    OnOutput := procedure(const AText: string)
      begin
        if Chunk2Started then
          Chunk2 := Chunk2 + AText
        else
          Chunk1 := Chunk1 + AText;
      end;
    Assert.IsTrue(StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), LastError);
    Pump(2500);

    System.Writeln('=== raw bytes: startup through first prompt (', Length(Chunk1), ' chars) ===');
    System.Writeln(EscapeDump(Chunk1));
    System.Writeln('=== end startup dump ===');
    System.Writeln;

    Chunk2Started := True;
    WriteInput('(Get-ChildItem).Name' + #13#10);
    Pump(3000);

    System.Writeln('=== raw bytes: after sending "(Get-ChildItem).Name\r\n" (', Length(Chunk2), ' chars) ===');
    System.Writeln(EscapeDump(Chunk2));
    System.Writeln('=== end post-command dump ===');

    Terminate;
  finally
    Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPsRawDump);

end.
