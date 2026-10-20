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

initialization
  TDUnitX.RegisterTestFixture(TTestConsoleRunCommand);

end.
