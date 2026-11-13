unit TestConsoleSelectionKeys;

{ Keyboard selection in the console: where it starts, where it stops, what a
  key does to it, and how a selection inside the command line is edited. The
  window gets its output directly and records what it would send to the shell. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConsoleSelectionKeys = class
  public
    [Test] procedure TestShiftLeftSelectsFromTheInputCursor;
    [Test] procedure TestShiftLeftStopsAtTheEndOfThePrompt;
    [Test] procedure TestShiftHomeSelectsTheInputOnly;
    [Test] procedure TestShiftRightOnAnEmptyInputSelectsNothing;
    [Test] procedure TestSelectionStopsAtTheLastRowWithText;
    [Test] procedure TestPlainKeyEndsTheSelectionAndRestoresTailFollowing;
    [Test] procedure TestTypingReplacesTheSelectedInput;
    [Test] procedure TestDelRemovesTheSelectedInput;
    [Test] procedure TestSelectionAcrossRowsIsNotEdited;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uThemeRegistry, uConsoleWindow, uShellProfiles;

type
  TProbeConsole = class(TConsoleWindow)
  public
    Sent: string;
    procedure SendRaw(const AText: string); override;
    procedure Feed(const AText: string);
    /// <summary>One key through HandleInput; True when the console consumed it.</summary>
    function Press(AKey: Word; AShift: TShiftState = []; AChar: Char = #0): Boolean;
    function Selected: string;
    function Selecting: Boolean;
    function LastRow: Integer;
    function FollowingTail: Boolean;
  end;

procedure TProbeConsole.SendRaw(const AText: string);
begin
  Sent := Sent + AText;
end;

procedure TProbeConsole.Feed(const AText: string);
begin
  AppendOutput(AText);
end;

function TProbeConsole.Press(AKey: Word; AShift: TShiftState; AChar: Char): Boolean;
begin
  Result := HandleInput(AKey, AShift, AChar);
end;

function TProbeConsole.Selected: string;
begin
  Result := SelectedText;
end;

function TProbeConsole.Selecting: Boolean;
begin
  Result := HasSelection;
end;

function TProbeConsole.LastRow: Integer;
begin
  Result := LastSelectableRow;
end;

function TProbeConsole.FollowingTail: Boolean;
begin
  Result := FHistory.FollowTail;
end;

function NewConsole(const AOutput: string): TProbeConsole;
begin
  Result := TProbeConsole.Create(CreateThemeByName('NDN'), 1);
  Result.Resize(100, 30);
  Result.Feed(AOutput);
end;

procedure PressTimes(AWin: TProbeConsole; AKey: Word; AShift: TShiftState; ACount: Integer);
var
  I: Integer;
begin
  for I := 1 to ACount do
    AWin.Press(AKey, AShift);
end;

procedure TTestConsoleSelectionKeys.TestShiftLeftSelectsFromTheInputCursor;
var
  Win: TProbeConsole;
begin
  Win := NewConsole('PS C:\Work> dir /b');
  try
    PressTimes(Win, vkLeft, [ssShift], 3);
    Assert.AreEqual(' /b', Win.Selected);
  finally
    Win.Free;
  end;
end;

procedure TTestConsoleSelectionKeys.TestShiftLeftStopsAtTheEndOfThePrompt;
var
  Win: TProbeConsole;
begin
  Win := NewConsole('PS C:\Work> dir /b');
  try
    PressTimes(Win, vkLeft, [ssShift], 40);
    Assert.AreEqual('dir /b', Win.Selected);
  finally
    Win.Free;
  end;
end;

procedure TTestConsoleSelectionKeys.TestShiftHomeSelectsTheInputOnly;
var
  Win: TProbeConsole;
begin
  Win := NewConsole('PS C:\Work> dir /b');
  try
    Win.Press(vkHome, [ssShift]);
    Assert.AreEqual('dir /b', Win.Selected);
  finally
    Win.Free;
  end;
end;

procedure TTestConsoleSelectionKeys.TestShiftRightOnAnEmptyInputSelectsNothing;
var
  Win: TProbeConsole;
begin
  Win := NewConsole('PS C:\Work>');
  try
    PressTimes(Win, vkRight, [ssShift], 2);
    Assert.IsFalse(Win.Selecting, 'nothing after the cursor to select');
  finally
    Win.Free;
  end;
end;

procedure TTestConsoleSelectionKeys.TestSelectionStopsAtTheLastRowWithText;
var
  Win: TProbeConsole;
begin
  Win := NewConsole('one'#13#10'PS C:\Work> dir');
  try
    PressTimes(Win, vkDown, [ssShift], 5);
    PressTimes(Win, vkNext, [ssShift], 2);
    Assert.IsTrue(Win.CursorRow <= Win.LastRow, 'the cursor stays on a row with text');
    Assert.IsFalse(Win.Selected.Contains(#13), 'no empty rows in the selection');
  finally
    Win.Free;
  end;
end;

procedure TTestConsoleSelectionKeys.TestPlainKeyEndsTheSelectionAndRestoresTailFollowing;
var
  Win: TProbeConsole;
begin
  Win := NewConsole('PS C:\Work> dir /b');
  try
    PressTimes(Win, vkLeft, [ssShift], 2);
    Assert.IsTrue(Win.Selecting);
    Assert.IsFalse(Win.FollowingTail, 'a selection unpins the tail');
    Win.Press(vkLeft);
    Assert.IsFalse(Win.Selecting, 'a plain key ends the selection');
    Assert.IsTrue(Win.FollowingTail, 'the shell gets its arrows again');
    Assert.AreEqual(#27'[D', Win.Sent, 'the arrow itself still reaches the shell');
  finally
    Win.Free;
  end;
end;

procedure TTestConsoleSelectionKeys.TestTypingReplacesTheSelectedInput;
var
  Win: TProbeConsole;
  Erase: string;
begin
  Win := NewConsole('PS C:\Work> dir /b');
  try
    Erase := StringOfChar(ProfileBackspaceChar(Win.ProfileId), 3);
    PressTimes(Win, vkLeft, [ssShift], 3);
    Win.Press(Ord('X'), [ssShift], 'X');
    Assert.IsTrue(Win.Sent.StartsWith(Erase), 'the selection is backspaced first: ' + Win.Sent);
    Assert.IsTrue(Win.Sent.EndsWith('X'), 'then the typed character follows: ' + Win.Sent);
    Assert.IsFalse(Win.Selecting);
  finally
    Win.Free;
  end;
end;

procedure TTestConsoleSelectionKeys.TestDelRemovesTheSelectedInput;
var
  Win: TProbeConsole;
begin
  Win := NewConsole('PS C:\Work> dir /b');
  try
    PressTimes(Win, vkLeft, [ssShift], 2);
    Assert.IsTrue(Win.Press(vkDelete), 'Del is consumed by the edit');
    Assert.AreEqual(StringOfChar(ProfileBackspaceChar(Win.ProfileId), 2), Win.Sent);
    Assert.IsFalse(Win.Selecting);
  finally
    Win.Free;
  end;
end;

procedure TTestConsoleSelectionKeys.TestSelectionAcrossRowsIsNotEdited;
var
  Win: TProbeConsole;
begin
  Win := NewConsole('old output'#13#10'PS C:\Work> dir');
  try
    Win.Press(vkUp, [ssShift]);
    Assert.IsTrue(Win.Selecting);
    Win.Press(vkDelete);
    Assert.AreEqual(#27'[3~', Win.Sent, 'Del goes to the shell as a plain key');
    Assert.IsFalse(Win.Selecting);
  finally
    Win.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsoleSelectionKeys);

end.
