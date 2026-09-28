unit TestShellSessions;

{ Live PowerShell and cmd sessions over real ConPTY (TConPtySession): the
  everyday scenarios the console relies on - list a directory, run several
  commands in a row, a command followed by a listing - each checked against
  the shell's actual output. Commands print markers built by the shell
  (PowerShell string concatenation, cmd's ^ escape), so the echo of the
  typed command line never counts as its output. Waits end as soon as the
  expected text arrives. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestShellSessions = class
  public
    [Test] procedure PowerShellListsDirectory;
    [Test] procedure PowerShellRunsCommandsInOrder;
    [Test] procedure PowerShellCommandThenListing;
    [Test] procedure CmdListsDirectory;
    [Test] procedure CmdRunsCommandsInOrder;
  end;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty,
  uShellProfiles;

const
  cStartTimeoutMs = 20000;
  cStepTimeoutMs = 15000;

type
  TShellRun = class
  private
    FPty: TConPtySession;
    FProfile: string;
    FOutput: string;
  public
    constructor Create(const AProfile: string);
    destructor Destroy; override;
    procedure Send(const ALine: string);
    /// <summary>Pumps messages until AText appears in the output after
    /// AFrom (a position from Mark), or the timeout passes.</summary>
    function WaitFor(const AText: string; ATimeoutMs: Integer; AFrom: Integer = 1): Boolean;
    function Mark: Integer;
    property Output: string read FOutput;
    property Pty: TConPtySession read FPty;
  end;

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

constructor TShellRun.Create(const AProfile: string);
begin
  inherited Create;
  FProfile := AProfile;
  FPty := TConPtySession.Create;
  FPty.ProfileId := AProfile;
  FPty.OnOutput :=
    procedure(const AText: string)
    begin
      FOutput := FOutput + AText;
    end;
  if not FPty.StartShell(AProfile, GetCurrentDir, 120, 30) then
    raise Exception.Create('StartShell failed: ' + FPty.LastError);
end;

destructor TShellRun.Destroy;
begin
  FPty.Terminate;
  Pump(300);
  FPty.Free;
  inherited Destroy;
end;

procedure TShellRun.Send(const ALine: string);
begin
  FPty.WriteInput(ALine + ProfileReturnSeq(FProfile));
end;

function TShellRun.Mark: Integer;
begin
  Result := Length(FOutput) + 1;
end;

function TShellRun.WaitFor(const AText: string; ATimeoutMs, AFrom: Integer): Boolean;
var
  UntilTick: UInt64;
begin
  UntilTick := GetTickCount64 + UInt64(ATimeoutMs);
  repeat
    if Pos(AText, FOutput, AFrom) > 0 then
      Exit(True);
    Pump(50);
  until GetTickCount64 >= UntilTick;
  Result := Pos(AText, FOutput, AFrom) > 0;
end;

// A prompt means the shell is ready for input: "PS " for PowerShell, the
// ">" after the current path for cmd.
function WaitForPrompt(ARun: TShellRun; const APrompt: string): Boolean;
begin
  Result := ARun.WaitFor(APrompt, cStartTimeoutMs);
end;

procedure TTestShellSessions.PowerShellListsDirectory;
var
  Run: TShellRun;
begin
  Run := TShellRun.Create(cShellProfilePowerShell);
  try
    Assert.IsTrue(WaitForPrompt(Run, 'PS '), 'no PowerShell prompt');
    Run.Send('Get-ChildItem');
    // Format-Table header of a file listing.
    Assert.IsTrue(Run.WaitFor('Mode', cStepTimeoutMs), 'no listing: ' + Copy(Run.Output, 1, 300));
    Assert.IsTrue(Run.Pty.IsRunning, 'PowerShell exited after the listing');
  finally
    Run.Free;
  end;
end;

procedure TTestShellSessions.PowerShellRunsCommandsInOrder;
var
  Run: TShellRun;
  PosA, PosB: Integer;
begin
  Run := TShellRun.Create(cShellProfilePowerShell);
  try
    Assert.IsTrue(WaitForPrompt(Run, 'PS '), 'no PowerShell prompt');
    // Sent back to back, the second before the first has finished.
    Run.Send('''mtn'' + ''_ps_first''');
    Run.Send('''mtn'' + ''_ps_second''');
    Assert.IsTrue(Run.WaitFor('mtn_ps_second', cStepTimeoutMs), 'second command gave no output');
    PosA := Pos('mtn_ps_first', Run.Output);
    PosB := Pos('mtn_ps_second', Run.Output);
    Assert.IsTrue(PosA > 0, 'first command gave no output');
    Assert.IsTrue(PosA < PosB, 'outputs out of order');
  finally
    Run.Free;
  end;
end;

procedure TTestShellSessions.PowerShellCommandThenListing;
var
  Run: TShellRun;
  From: Integer;
begin
  Run := TShellRun.Create(cShellProfilePowerShell);
  try
    Assert.IsTrue(WaitForPrompt(Run, 'PS '), 'no PowerShell prompt');
    Run.Send('''mtn'' + ''_ps_before''');
    Assert.IsTrue(Run.WaitFor('mtn_ps_before', cStepTimeoutMs), 'command gave no output');
    From := Run.Mark;
    Run.Send('Get-ChildItem');
    Assert.IsTrue(Run.WaitFor('Mode', cStepTimeoutMs, From), 'no listing after a command');
    Assert.IsTrue(Run.Pty.IsRunning, 'PowerShell exited');
  finally
    Run.Free;
  end;
end;

procedure TTestShellSessions.CmdListsDirectory;
var
  Run: TShellRun;
begin
  Run := TShellRun.Create(cShellProfileCmd);
  try
    Assert.IsTrue(WaitForPrompt(Run, '>'), 'no cmd prompt');
    Run.Send('dir /a:d');
    // Directory entries are "<DIR>" in every cmd language.
    Assert.IsTrue(Run.WaitFor('<DIR>', cStepTimeoutMs), 'no listing: ' + Copy(Run.Output, 1, 300));
    Assert.IsTrue(Run.Pty.IsRunning, 'cmd exited after the listing');
  finally
    Run.Free;
  end;
end;

procedure TTestShellSessions.CmdRunsCommandsInOrder;
var
  Run: TShellRun;
  PosA, PosB: Integer;
begin
  Run := TShellRun.Create(cShellProfileCmd);
  try
    Assert.IsTrue(WaitForPrompt(Run, '>'), 'no cmd prompt');
    Run.Send('echo mtn^_cmd_first');
    Run.Send('echo mtn^_cmd_second');
    Assert.IsTrue(Run.WaitFor('mtn_cmd_second', cStepTimeoutMs), 'second command gave no output');
    PosA := Pos('mtn_cmd_first', Run.Output);
    PosB := Pos('mtn_cmd_second', Run.Output);
    Assert.IsTrue(PosA > 0, 'first command gave no output');
    Assert.IsTrue(PosA < PosB, 'outputs out of order');
  finally
    Run.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestShellSessions);

end.
