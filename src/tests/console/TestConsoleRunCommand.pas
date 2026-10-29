unit TestConsoleRunCommand;

{ A command sent to the background console from outside (a user-menu item):
  it runs even when the shell has to be started for it, the panels follow a
  folder change it makes, and it is not glued to text left on the shell's
  input line. Runs against a live cmd session. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConsoleRunCommand = class
  public
    [Test] procedure ColdShellCdIsSeenBeforeReturningToPanels;
    [Test] procedure PendingInputIsDroppedBeforeTheCommand;
    [Test] procedure PendingRedirectWithCursorInsideIsDropped;
    [Test] procedure PendingInputIsDroppedBeforeTheFolderSync;
    [Test] procedure HomeAndEndMoveWithinTheInputLine;
    [Test] procedure CtrlHomeAndCtrlEndScrollTheOutput;
    [Test] procedure TabCompletesTheWordInTheShell;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, System.IOUtils, Winapi.Windows,
  uThemeRegistry, uConsoleWindow;

type
  TProbeConsole = class(TConsoleWindow)
  public
    function InputLine: string;
    function BufferHas(const AText: string): Boolean;
    function FollowsTail: Boolean;
  end;

  TReturnProbe = class
  public
    Fired: Boolean;
    Changed: Boolean;
    Cwd: string;
    Win: TConsoleWindow;
    procedure Back(Sender: TObject);
  end;

function TProbeConsole.InputLine: string;
begin
  Result := FHistory.GetInputAfterPrompt;
end;

function TProbeConsole.FollowsTail: Boolean;
begin
  Result := FHistory.FollowTail;
end;

function TProbeConsole.BufferHas(const AText: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to FHistory.LineCount - 1 do
    if Pos(AText, FHistory.GetLine(I)) > 0 then
      Exit(True);
end;

procedure TReturnProbe.Back(Sender: TObject);
begin
  if Fired then
    Exit;
  Fired := True;
  Changed := Win.TakeCwdChange(Cwd);
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

function NewConsole: TProbeConsole;
begin
  Result := TProbeConsole.Create(CreateThemeByName('NDN'), 1, 'cmd');
  Result.RestartOnExit := False;
  Result.Resize(100, 30);
end;

procedure TTestConsoleRunCommand.ColdShellCdIsSeenBeforeReturningToPanels;
var
  Root, Sub: string;
  Win: TProbeConsole;
  Probe: TReturnProbe;
  I: Integer;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-run-' + TPath.GetGUIDFileName(False));
  Sub := TPath.Combine(Root, 'child');
  TDirectory.CreateDirectory(Sub);
  Win := NewConsole;
  Probe := TReturnProbe.Create;
  try
    Probe.Win := Win;
    Win.OnBackToPanels := Probe.Back;
    // The order the panels use for a user-menu command.
    Win.RunCommand('cd child', Root);
    Win.ReturnToPanelsWhenDone;
    for I := 1 to 150 do
    begin
      Pump(100);
      if Probe.Fired then
        Break;
    end;
    Assert.IsTrue(Probe.Fired, 'the console hands the panels back');
    Assert.IsTrue(Probe.Changed, 'the folder change is already visible when it does');
    Assert.AreEqual(ExcludeTrailingPathDelimiter(Sub),
      ExcludeTrailingPathDelimiter(Probe.Cwd), 'the new folder');
  finally
    Win.CloseConsole;
    Win.Free;
    Probe.Free;
    TDirectory.Delete(Root, True);
  end;
end;

procedure TTestConsoleRunCommand.PendingInputIsDroppedBeforeTheCommand;
var
  Win: TProbeConsole;
  I: Integer;
begin
  Win := NewConsole;
  try
    Assert.IsTrue(Win.EnsureShell(GetCurrentDir), 'the shell starts');
    Pump(3000);
    Type_(Win, 'abc');
    for I := 1 to 60 do
    begin
      Pump(100);
      if Win.InputLine = 'abc' then
        Break;
    end;
    Assert.AreEqual('abc', Win.InputLine, 'text left on the input line');
    Win.RunCommand('echo fresh', '');
    Pump(2500);
    Assert.IsFalse(Win.BufferHas('abcecho fresh'), 'the command is not glued to the old text');
    Assert.IsTrue(Win.BufferHas('echo fresh'), 'the command ran');
  finally
    Win.CloseConsole;
    Win.Free;
  end;
end;

procedure TTestConsoleRunCommand.PendingRedirectWithCursorInsideIsDropped;
var
  Root: string;
  Win: TProbeConsole;
  I: Integer;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-run-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Root);
  Win := NewConsole;
  try
    Win.WorkingDir := Root;
    Assert.IsTrue(Win.EnsureShell(Root), 'the shell starts');
    Pump(3000);
    Type_(Win, 'echo 1 > outf');
    for I := 1 to 60 do
    begin
      Pump(100);
      if Win.InputLine = 'echo 1 > outf' then
        Break;
    end;
    Assert.AreEqual('echo 1 > outf', Win.InputLine, 'text left on the input line');
    // Cursor in the middle of the line, not at its end.
    for I := 1 to 4 do
      Press(Win, vkLeft);
    Pump(500);
    Win.RunCommand('echo fresh', Root);
    Pump(2500);
    Assert.IsTrue(Win.BufferHas('fresh'), 'the command ran');
    Assert.IsFalse(TFile.Exists(TPath.Combine(Root, 'outf')),
      'the old input line was not executed');
    Assert.AreEqual(Integer(0), Integer(Length(TDirectory.GetFiles(Root))),
      'the command was not glued to the old text');
  finally
    Win.CloseConsole;
    Win.Free;
    TDirectory.Delete(Root, True);
  end;
end;

procedure TTestConsoleRunCommand.PendingInputIsDroppedBeforeTheFolderSync;
var
  Root, Sub: string;
  Win: TProbeConsole;
  I: Integer;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-run-' + TPath.GetGUIDFileName(False));
  Sub := TPath.Combine(Root, 'child');
  TDirectory.CreateDirectory(Sub);
  Win := NewConsole;
  try
    Win.WorkingDir := Root;
    Assert.IsTrue(Win.EnsureShell(Root), 'the shell starts');
    Pump(3000);
    Type_(Win, 'abc');
    for I := 1 to 60 do
    begin
      Pump(100);
      if Win.InputLine = 'abc' then
        Break;
    end;
    Assert.AreEqual('abc', Win.InputLine, 'text left on the input line');
    Win.SyncWorkingDir(Sub);
    Pump(2500);
    Assert.IsFalse(Win.BufferHas('abccd'), 'the folder change is not glued to the old text');
    Assert.IsTrue(Win.BufferHas('child>'), 'the shell is in the new folder');
  finally
    Win.CloseConsole;
    Win.Free;
    TDirectory.Delete(Root, True);
  end;
end;

procedure TTestConsoleRunCommand.HomeAndEndMoveWithinTheInputLine;
var
  Win: TProbeConsole;
  I: Integer;
begin
  Win := NewConsole;
  try
    Assert.IsTrue(Win.EnsureShell(GetCurrentDir), 'the shell starts');
    Pump(3000);
    Type_(Win, 'abc');
    for I := 1 to 60 do
    begin
      Pump(100);
      if Win.InputLine = 'abc' then
        Break;
    end;
    Press(Win, vkHome);
    Pump(500);
    Type_(Win, 'x');
    Press(Win, vkEnd);
    Pump(500);
    Type_(Win, 'y');
    for I := 1 to 60 do
    begin
      Pump(100);
      if Win.InputLine = 'xabcy' then
        Break;
    end;
    Assert.AreEqual('xabcy', Win.InputLine, 'Home and End moved the cursor within the line');
    Press(Win, vkLeft);
    Pump(300);
    Assert.IsTrue(Win.FollowsTail, 'the console still follows the shell');
  finally
    Win.CloseConsole;
    Win.Free;
  end;
end;

procedure TTestConsoleRunCommand.CtrlHomeAndCtrlEndScrollTheOutput;
var
  Win: TProbeConsole;
  K: Word;
  Ch: Char;
begin
  Win := NewConsole;
  try
    Assert.IsTrue(Win.EnsureShell(GetCurrentDir), 'the shell starts');
    Pump(3000);
    Assert.IsTrue(Win.FollowsTail, 'the console starts at the live prompt');
    K := vkHome;
    Ch := #0;
    Win.HandleInput(K, [ssCtrl], Ch);
    Assert.AreEqual(Word(0), K, 'Ctrl+Home is consumed');
    Assert.IsFalse(Win.FollowsTail, 'Ctrl+Home scrolls to the start of the output');
    K := vkEnd;
    Win.HandleInput(K, [ssCtrl], Ch);
    Assert.AreEqual(Word(0), K, 'Ctrl+End is consumed');
    Assert.IsTrue(Win.FollowsTail, 'Ctrl+End returns to the live prompt');
  finally
    Win.CloseConsole;
    Win.Free;
  end;
end;

procedure TTestConsoleRunCommand.TabCompletesTheWordInTheShell;
var
  Root: string;
  Win: TProbeConsole;
  I: Integer;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-run-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(TPath.Combine(Root, 'uniquefolder'));
  Win := NewConsole;
  try
    Win.WorkingDir := Root;
    Assert.IsTrue(Win.EnsureShell(Root), 'the shell starts');
    Pump(3000);
    Type_(Win, 'cd uniq');
    Press(Win, vkTab);
    for I := 1 to 60 do
    begin
      Pump(100);
      if SameText(Win.InputLine, 'cd uniquefolder') then
        Break;
    end;
    Assert.IsTrue(SameText(Win.InputLine, 'cd uniquefolder'), 'Tab completed the folder name');
  finally
    Win.CloseConsole;
    Win.Free;
    TDirectory.Delete(Root, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsoleRunCommand);

end.
