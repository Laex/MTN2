unit TestCommandLineQuoting;

{ PlatformQuoteArg builds Windows command-line arguments that the child's
  CommandLineToArgvW parsing reads back unchanged. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCommandLineQuoting = class
  public
    [Test] procedure TestPlainArgumentIsLeftAlone;
    [Test] procedure TestTrailingBackslashDoesNotSwallowNextArgument;
    [Test] procedure TestEmbeddedQuotesSurviveRoundTrip;
    [Test] procedure TestAwkwardArgumentsSurviveRoundTrip;
  end;

implementation

uses
  System.SysUtils, Winapi.Windows, Winapi.ShellAPI, uPlatformProcess;

function ParseBack(const ACommandLine: string): TArray<string>;
var
  Argc: Integer;
  Argv: PPWideChar;
  I: Integer;
begin
  Argv := CommandLineToArgvW(PChar(ACommandLine), Argc);
  Assert.IsNotNull(Argv);
  try
    SetLength(Result, Argc);
    for I := 0 to Argc - 1 do
      Result[I] := string(PPWideChar(PByte(Argv) + I * SizeOf(PWideChar))^);
  finally
    LocalFree(HLOCAL(Argv));
  end;
end;

procedure TTestCommandLineQuoting.TestPlainArgumentIsLeftAlone;
begin
  Assert.AreEqual('status', PlatformQuoteArg('status'));
  Assert.AreEqual('--format=%H', PlatformQuoteArg('--format=%H'));
end;

procedure TTestCommandLineQuoting.TestTrailingBackslashDoesNotSwallowNextArgument;
var
  Args: TArray<string>;
begin
  Args := ParseBack('prog ' + PlatformQuoteArg('C:\My Dir\') + ' ' + PlatformQuoteArg('next'));
  Assert.AreEqual(3, Integer(Length(Args)));
  Assert.AreEqual('C:\My Dir\', Args[1]);
  Assert.AreEqual('next', Args[2]);
end;

procedure TTestCommandLineQuoting.TestEmbeddedQuotesSurviveRoundTrip;
var
  Args: TArray<string>;
begin
  Args := ParseBack('prog ' + PlatformQuoteArg('say "hi" now'));
  Assert.AreEqual(2, Integer(Length(Args)));
  Assert.AreEqual('say "hi" now', Args[1]);
end;

procedure TTestCommandLineQuoting.TestAwkwardArgumentsSurviveRoundTrip;
const
  Cases: array[0..6] of string = ('', 'a b', 'a'#9'b', 'x\"y', 'x\\"y', 'a&b|c', '\\server\share\');
var
  S: string;
  Args: TArray<string>;
begin
  for S in Cases do
  begin
    Args := ParseBack('prog ' + PlatformQuoteArg(S));
    Assert.AreEqual(2, Integer(Length(Args)), S);
    Assert.AreEqual(S, Args[1], S);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCommandLineQuoting);

end.
