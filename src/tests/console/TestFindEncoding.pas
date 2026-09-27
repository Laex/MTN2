unit TestFindEncoding;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFindEncoding = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Math, Winapi.Windows,
  uConPty,
  uShellProfiles;

var
  GOutput: string;

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

procedure DumpCodePoints(const S, ALabel: string);
var
  I: Integer;
  Parts: TStringBuilder;
begin
  Parts := TStringBuilder.Create;
  try
    Parts.Append(ALabel).Append(': Len=').Append(S.Length).Append(' CP=');
    for I := 1 to Min(S.Length, 40) do
      Parts.Append(' U+').Append(IntToHex(Ord(S[I]), 4));
    System.Writeln(Parts.ToString);
    System.Writeln('  Text: ', S);
  finally
    Parts.Free;
  end;
end;

{ TTestFindEncoding }

procedure TTestFindEncoding.Run;
begin
  GOutput := '';
  with TConPtySession.Create do
  try
    ProfileId := cShellProfileCmd;
    OnOutput := procedure(const AText: string)
      begin
        GOutput := GOutput + AText;
      end;
    Assert.IsTrue(StartShell(cShellProfileCmd, 'D:\Work', 80, 25), LastError);
    WriteInput('find'#13#10);
    Pump(4000);
    DumpCodePoints(Copy(GOutput, Pos('FIND:', GOutput), 80), 'find line');
    DumpCodePoints(Copy(GOutput, Pos('(c)', GOutput), 80), 'copyright line');
    Assert.IsTrue(Pos('FIND:', GOutput) > 0, 'missing FIND:');
    Assert.IsTrue(Pos(WideChar($041D), Copy(GOutput, Pos('FIND:', GOutput), 80)) > 0,
      'find message must decode as Cyrillic (U+041D), not box-drawing mojibake');
    Terminate;
  finally
    Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFindEncoding);

end.
