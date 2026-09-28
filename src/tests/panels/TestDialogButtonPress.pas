unit TestDialogButtonPress;

{ Dialog button press: a pressed button is drawn one cell right without its
  shadow; a key runs the command only when the press is released (the press
  timer is a counting stub here); the mouse runs it on release over the same
  button; Esc and hosts without a press timer run commands at once. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogButtonPress = class
  public
    [TearDown] procedure TearDown;
    [Test] procedure TestPressedDrawing;
    [Test] procedure TestKeyRunsOnRelease;
    [Test] procedure TestNextKeyRunsPendingFirst;
    [Test] procedure TestCloseDropsPress;
    [Test] procedure TestMouseRunsOnReleaseOverButton;
    [Test] procedure TestEscAndNoTimerRunAtOnce;
    [Test] procedure TestPressButtonThen;
  end;

implementation

uses
  System.SysUtils, System.UITypes,
  uTerminalTypes, uThemeTypes, uDialogTypes, uDialogJson, uDialogHost, uNDNTheme;

const
  W = 60;
  H = 20;
  cLowerHalf = #$2584;
  cUpperHalf = #$2580;
  cDialogJson =
    '{"type":"dialog","version":"2.0","title":"Press","width":40,"height":8,' +
    '"children":[' +
    '{"type":"label","text":"Question","col":1,"row":0,"width":30,"height":1},' +
    '{"type":"button","id":"ok","text":"OK","default":true,"col":4,"row":3,"width":10,"height":1},' +
    '{"type":"button","id":"cancel","text":"Cancel","cancel":true,"col":20,"row":3,"width":12,"height":1}' +
    ']}';

var
  Fired: string;
  Starts: Integer;

function OpenHost: TDialogHost;
var
  Decl: TDialogDeclaration;
begin
  Assert.IsTrue(TryParseDialogJson(cDialogJson, Decl), 'dialog json');
  Result := TDialogHost.Create(TNDNTheme.Create);
  Result.Open(Decl,
    procedure(const AControlId, AValuesJson: string)
    begin
      Fired := Fired + AControlId + ';';
    end);
  Fired := '';
end;

procedure UsePressTimer;
begin
  Starts := 0;
  GDialogButtonPressStart :=
    procedure
    begin
      Inc(Starts);
    end;
end;

function ButtonIndex(AHost: TDialogHost; const AId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to AHost.ControlCount - 1 do
    if AHost.GetControl(I).Id = AId then
      Exit(I);
  Result := -1;
end;

function ColumnOf(const AGrid: TTerminalGrid; ARow: Integer; ACh: Char): Integer;
var
  X: Integer;
begin
  for X := 0 to High(AGrid[ARow]) do
    if AGrid[ARow][X].CharValue = ACh then
      Exit(X);
  Result := -1;
end;

function Render(AHost: TDialogHost): TTerminalGrid;
begin
  AllocTerminalGrid(Result, W, H);
  ClearTerminalGrid(Result, TAlphaColorRec.White, TAlphaColorRec.Navy, ' ');
  AHost.Draw(Result, W, H);
end;

procedure SendKey(AHost: TDialogHost; AKey: Word; AChar: Char = #0);
var
  Key: Word;
  Ch: Char;
begin
  Key := AKey;
  Ch := AChar;
  AHost.HandleInput(Key, [], Ch);
end;

procedure TTestDialogButtonPress.TearDown;
begin
  FlushDialogButtonPress;
  GDialogButtonPressStart := nil;
end;

procedure TTestDialogButtonPress.TestPressedDrawing;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
  R: TRectI;
  Ok, Caption: Integer;
begin
  UsePressTimer;
  Host := OpenHost;
  try
    Ok := ButtonIndex(Host, 'ok');
    Grid := Render(Host);
    R := Host.ControlBoundsAt(Ok);
    Caption := ColumnOf(Grid, R.Top, '<');
    Assert.IsTrue((Caption >= R.Left) and (Caption <= R.Right), 'caption inside the face');
    Assert.IsTrue(Grid[R.Top][R.Right + 1].CharValue = cLowerHalf, 'right shadow');
    Assert.IsTrue(Grid[R.Bottom + 1][R.Left + 1].CharValue = cUpperHalf, 'shadow below');

    SendKey(Host, vkReturn);
    Assert.IsTrue(Host.PressedButton = Ok, 'Enter presses the default button');
    Grid := Render(Host);
    Assert.IsTrue(ColumnOf(Grid, R.Top, '<') = Caption + 1, 'pressed face one cell right');
    Assert.IsTrue(Grid[R.Top][R.Right + 1].CharValue <> cLowerHalf,
      'pressed face covers the right shadow');
    Assert.IsTrue(Grid[R.Bottom + 1][R.Left + 1].CharValue <> cUpperHalf,
      'no shadow below a pressed button');
    Assert.IsTrue(Grid[R.Top][R.Left].BgColor <> Grid[R.Top][R.Left + 1].BgColor,
      'vacated cell shows the dialog body');

    FlushDialogButtonPress;
    Grid := Render(Host);
    Assert.IsTrue(ColumnOf(Grid, R.Top, '<') = Caption, 'released face back in place');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogButtonPress.TestKeyRunsOnRelease;
var
  Host: TDialogHost;
begin
  UsePressTimer;
  Host := OpenHost;
  try
    SendKey(Host, vkReturn);
    Assert.IsTrue(Fired = '', 'nothing runs while the button is down');
    Assert.IsTrue(Starts = 1, 'press timer started');
    Assert.IsTrue(DialogButtonPressPending, 'press pending');
    FlushDialogButtonPress;
    Assert.IsTrue(Fired = 'ok;', 'command runs on release');
    Assert.IsTrue(Host.PressedButton = -1, 'button released');
    FlushDialogButtonPress;
    Assert.IsTrue(Fired = 'ok;', 'runs once');

    // Space on the focused button and its hotkey letter press it too.
    SendKey(Host, vkTab);
    SendKey(Host, vkSpace, ' ');
    Assert.IsTrue(Host.PressedButton = ButtonIndex(Host, 'cancel'), 'Space presses the focused button');
    FlushDialogButtonPress;
    Assert.IsTrue(Fired = 'ok;cancel;', 'Space: command on release');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogButtonPress.TestNextKeyRunsPendingFirst;
var
  Host: TDialogHost;
begin
  UsePressTimer;
  Host := OpenHost;
  try
    SendKey(Host, vkReturn);
    SendKey(Host, vkReturn);
    Assert.IsTrue(Fired = 'ok;', 'the second press releases the first');
    Assert.IsTrue(DialogButtonPressPending, 'second press pending');
    FlushDialogButtonPress;
    Assert.IsTrue(Fired = 'ok;ok;', 'each key runs its command exactly once');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogButtonPress.TestCloseDropsPress;
var
  Host: TDialogHost;
begin
  UsePressTimer;
  Host := OpenHost;
  try
    SendKey(Host, vkReturn);
    Host.Close;
    Assert.IsFalse(DialogButtonPressPending, 'closing the dialog drops the press');
    FlushDialogButtonPress;
    Assert.IsTrue(Fired = '', 'a closed dialog runs nothing');
  finally
    Host.Free;
  end;
  UsePressTimer;
  Host := OpenHost;
  SendKey(Host, vkReturn);
  Host.Free;
  Assert.IsFalse(DialogButtonPressPending, 'freeing the host drops the press');
end;

procedure TTestDialogButtonPress.TestMouseRunsOnReleaseOverButton;
const
  DX = 7;
  DY = 3;
var
  Host: TDialogHost;
  R: TRectI;
  Ok: Integer;
begin
  UsePressTimer;
  Host := OpenHost;
  try
    Render(Host);
    Ok := ButtonIndex(Host, 'ok');
    R := Host.ControlBoundsAt(Ok);

    // Screen cells are the dialog's own plus (DX, DY), as for a window
    // that does not start at the top-left corner.
    DialogButtonMouseDown(R.Left + 1 + DX, R.Top + DY);
    Assert.IsTrue(Host.HandleClick(R.Left + 1, R.Top), 'click on the button handled');
    Assert.IsTrue(Fired = '', 'nothing runs on mouse down');
    Assert.IsTrue(DialogButtonCaptured and (Host.PressedButton = Ok), 'button held');

    Assert.IsTrue(DialogButtonCaptureMove(R.Right + 5 + DX, R.Top + DY), 'moving off changes the look');
    Assert.IsTrue(Host.PressedButton = -1, 'pops up while the pointer is off it');
    Assert.IsTrue(DialogButtonCaptureMove(R.Left + DX, R.Top + DY), 'moving back changes the look');
    Assert.IsTrue(Host.PressedButton = Ok, 'pressed again over it');

    DialogButtonCaptureRelease(R.Right + 5 + DX, R.Top + DY);
    Assert.IsTrue(Fired = '', 'release off the button runs nothing');
    Assert.IsFalse(DialogButtonCaptured, 'capture ends on release');
    Assert.IsTrue(Host.PressedButton = -1, 'released');

    DialogButtonMouseDown(R.Left + DX, R.Top + DY);
    Host.HandleClick(R.Left, R.Top);
    DialogButtonCaptureRelease(R.Right + DX, R.Top + DY);
    Assert.IsTrue(Fired = 'ok;', 'release over the button runs it');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogButtonPress.TestEscAndNoTimerRunAtOnce;
var
  Host: TDialogHost;
  R: TRectI;
begin
  UsePressTimer;
  Host := OpenHost;
  try
    SendKey(Host, vkEscape);
    Assert.IsTrue(Fired = 'cancel;', 'Esc cancels at once');
    Assert.IsFalse(DialogButtonPressPending, 'no press for Esc');
  finally
    Host.Free;
  end;

  GDialogButtonPressStart := nil;
  Host := OpenHost;
  try
    SendKey(Host, vkReturn);
    Assert.IsTrue(Fired = 'ok;', 'without a press timer Enter runs at once');
    Render(Host);
    R := Host.ControlBoundsAt(ButtonIndex(Host, 'cancel'));
    Host.HandleClick(R.Left, R.Top);
    Assert.IsTrue(Fired = 'ok;cancel;', 'without a press timer a click runs at once');
    Assert.IsFalse(DialogButtonCaptured, 'and holds nothing');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogButtonPress.TestPressButtonThen;
var
  Host: TDialogHost;
  Ran: Integer;
begin
  UsePressTimer;
  Host := OpenHost;
  try
    Ran := 0;
    Host.PressButtonThen('cancel',
      procedure
      begin
        Inc(Ran);
      end);
    Assert.IsTrue((Ran = 0) and (Host.PressedButton = ButtonIndex(Host, 'cancel')),
      'known button: pressed first');
    FlushDialogButtonPress;
    Assert.IsTrue(Ran = 1, 'action on release');

    Host.PressButtonThen('missing',
      procedure
      begin
        Inc(Ran);
      end);
    Assert.IsTrue(Ran = 2, 'no such button: runs at once');
    Assert.IsTrue(Fired = '', 'the host command is not involved');
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogButtonPress);

end.
