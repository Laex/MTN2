unit TestConsoleShellCwd;

{ The console follows its shell: the folder the shell is in (read from the
  prompt on Windows, from the shell process on Linux) and the moment a command
  has finished. Runs against a live shell. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConsoleShellCwd = class
  public
    [Test] procedure TestPromptCwdFollowsCd;
    [Test] procedure TestReturnToPanelsWhenCommandIsDone;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, uThemeRegistry, uConsoleWindow;

type
  TReturnCounter = class
  public
    Count: Integer;
    procedure Back(Sender: TObject);
  end;

procedure TReturnCounter.Back(Sender: TObject);
begin
  Inc(Count);
end;

procedure Pump(AMs: Integer);
var
  Stop: UInt64;
begin
  Stop := TThread.GetTickCount64 + UInt64(AMs);
  while TThread.GetTickCount64 < Stop do
  begin
    CheckSynchronize(10);
    Sleep(5);
  end;
end;

function SameFolder(const A, B: string): Boolean;
begin
  Result := SameText(ExcludeTrailingPathDelimiter(A), ExcludeTrailingPathDelimiter(B));
end;

function NewConsole(const ADir: string): TConsoleWindow;
begin
  Result := TConsoleWindow.Create(CreateThemeByName('NDN'), 1);
  Result.RestartOnExit := False;
  Result.Resize(100, 30);
  Assert.IsTrue(Result.EnsureShell(ADir), 'the shell starts');
  Pump(2500);
end;

procedure TTestConsoleShellCwd.TestPromptCwdFollowsCd;
var
  Root, Sub: string;
  Win: TConsoleWindow;
  I: Integer;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-cwd-' + TPath.GetGUIDFileName(False));
  Sub := TPath.Combine(Root, 'child');
  TDirectory.CreateDirectory(Sub);
  Win := NewConsole(Root);
  try
    Win.RunCommand('cd child', '');
    for I := 1 to 60 do
    begin
      Pump(100);
      if SameFolder(Win.PromptCwd, Sub) then
        Break;
    end;
    Assert.IsTrue(SameFolder(Win.PromptCwd, Sub), 'the shell is in the child folder: ' + Win.PromptCwd);
  finally
    Win.CloseConsole;
    Win.Free;
    TDirectory.Delete(Root, True);
  end;
end;

procedure TTestConsoleShellCwd.TestReturnToPanelsWhenCommandIsDone;
var
  Win: TConsoleWindow;
  Counter: TReturnCounter;
  I: Integer;
begin
  Counter := TReturnCounter.Create;
  Win := NewConsole(TPath.GetTempPath);
  try
    Win.OnBackToPanels := Counter.Back;
    Win.ReturnToPanelsWhenDone;
    Win.RunCommand('echo done', '');
    for I := 1 to 100 do
    begin
      Pump(100);
      if Counter.Count > 0 then
        Break;
    end;
    Assert.AreEqual(1, Counter.Count, 'back to the panels once the command finished');
  finally
    Win.CloseConsole;
    Win.Free;
    Counter.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsoleShellCwd);

end.
