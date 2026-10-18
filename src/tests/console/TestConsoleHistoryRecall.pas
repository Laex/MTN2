unit TestConsoleHistoryRecall;

{ Up / Down at a cmd prompt recall the commands of the shared history, and Down
  past the newest brings back the line that was being typed. Runs against a
  live cmd session behind a console window. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConsoleHistoryRecall = class
  public
    [Test] procedure RecallWalksTheHistoryAndRestoresTheDraft;
    [Test] procedure TypingEndsTheRecall;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, Winapi.Windows,
  uThemeRegistry, uConsoleWindow;

type
  TProbeConsole = class(TConsoleWindow)
  public
    function InputLine: string;
  end;

function TProbeConsole.InputLine: string;
begin
  Result := FHistory.GetInputAfterPrompt;
end;

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

procedure Press(AWin: TConsoleWindow; AKey: Word; AChar: Char = #0);
var
  K: Word;
  Ch: Char;
begin
  K := AKey;
  Ch := AChar;
  AWin.HandleInput(K, [], Ch);
end;

procedure Type_(AWin: TConsoleWindow; const AText: string);
var
  I: Integer;
begin
  for I := 1 to Length(AText) do
    Press(AWin, Ord(UpCase(AText[I])), AText[I]);
end;

procedure ExpectLine(AWin: TProbeConsole; const AExpected, AStep: string);
var
  I: Integer;
begin
  for I := 1 to 60 do
  begin
    Pump(100);
    if AWin.InputLine = AExpected then
      Break;
  end;
  Assert.AreEqual(AExpected, AWin.InputLine, AStep);
end;

function NewConsole: TProbeConsole;
begin
  Result := TProbeConsole.Create(CreateThemeByName('NDN'), 1, 'cmd');
  Result.OnGetCmdHistory :=
    function: TArray<string>
    begin
      Result := ['echo two', 'echo one'];
    end;
  Result.Resize(100, 30);
  Assert.IsTrue(Result.EnsureShell(GetCurrentDir), 'the shell starts');
  Pump(3000);
end;

procedure TTestConsoleHistoryRecall.RecallWalksTheHistoryAndRestoresTheDraft;
var
  Win: TProbeConsole;
begin
  Win := NewConsole;
  try
    Type_(Win, 'abc');
    ExpectLine(Win, 'abc', 'typed text');
    Press(Win, vkUp);
    ExpectLine(Win, 'echo two', 'Up: newest command');
    Press(Win, vkUp);
    ExpectLine(Win, 'echo one', 'Up: older command');
    Press(Win, vkUp);
    ExpectLine(Win, 'echo one', 'Up at the oldest stays');
    Press(Win, vkDown);
    ExpectLine(Win, 'echo two', 'Down: newer command');
    Press(Win, vkDown);
    ExpectLine(Win, 'abc', 'Down past the newest: the typed line comes back');
    Press(Win, vkDown);
    ExpectLine(Win, 'abc', 'Down on the typed line changes nothing');
  finally
    Win.CloseConsole;
    Win.Free;
  end;
end;

procedure TTestConsoleHistoryRecall.TypingEndsTheRecall;
var
  Win: TProbeConsole;
begin
  Win := NewConsole;
  try
    Press(Win, vkUp);
    ExpectLine(Win, 'echo two', 'recalled');
    Type_(Win, 'z');
    ExpectLine(Win, 'echo twoz', 'typing edits the recalled line');
    Press(Win, vkUp);
    ExpectLine(Win, 'echo two', 'a new recall starts from the edited line');
    Press(Win, vkDown);
    ExpectLine(Win, 'echo twoz', 'and Down brings the edited line back');
  finally
    Win.CloseConsole;
    Win.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsoleHistoryRecall);

end.
