unit uTestRunner;

{ Shared DUnitX console runner for the src\tests\<group>\<Group>Tests.dpr
  programs. Each group program lists its Test*.pas fixture units in its uses
  clause (they self-register in their initialization sections) and calls
  RunRegisteredTests. Command line is DUnitX's own (-h lists it); the ones
  run-tests.ps1 passes:

    --xmlfile:<path>        NUnit XML report for CI
    --exclude:Manual        skip fixtures tagged [Category('Manual')]
    --run:<Unit.TFixture>   only these fixtures (comma-separated)
    --consolemode:Quiet     one line per failure instead of per test

  Exit code is 0 when every test passed, 1 otherwise. }

interface

procedure RunRegisteredTests;

/// <summary>For a fixture that had to abandon a worker thread still blocked in
/// a system call: once the reports are written, end the process without unit
/// finalization, so the worker waking on a torn-down heap can't crash the
/// exit.</summary>
procedure SkipFinalizationOnExit;

implementation

uses
  Winapi.Windows, System.SysUtils,
  DUnitX.TestFramework, DUnitX.Loggers.Console, DUnitX.Loggers.Xml.NUnit;

var
  GSkipFinalization: Boolean;

procedure SkipFinalizationOnExit;
begin
  GSkipFinalization := True;
end;

procedure RunRegisteredTests;
var
  Runner: ITestRunner;
  Results: IRunResults;
begin
  try
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    // Several fixtures are live-shell probes that only log what they see.
    Runner.FailsOnNoAsserts := False;
    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
      Runner.AddLogger(TDUnitXConsoleLogger.Create(TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet));
    if TDUnitX.Options.XMLOutputFile <> '' then
      Runner.AddLogger(TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile));
    Results := Runner.Execute;
    if not Results.AllPassed then
      System.ExitCode := EXIT_ERRORS;
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      Write('Done.. press <Enter> key to quit.');
      Readln;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := EXIT_ERRORS;
    end;
  end;
  if GSkipFinalization then
  begin
    // Releasing the runner frees the loggers, which closes the XML report.
    Results := nil;
    Runner := nil;
    Flush(Output);
    ExitProcess(System.ExitCode);
  end;
end;

end.
