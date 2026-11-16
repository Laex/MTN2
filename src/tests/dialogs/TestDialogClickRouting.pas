unit TestDialogClickRouting;

{ Characterization of TDialogHost.HandleClickCore order: frame cancel,
  open dropdown popup, then per-control hits. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogClickRouting = class
  public
    [Test] procedure OutsideClickCancels;
    [Test] procedure CheckboxClickToggles;
    [Test] procedure ButtonClickFiresWithoutPressTimer;
    [Test] procedure DropDownFieldOpensAndCloses;
    [Test] procedure OpenDropDownClickOutsideClosesThenHitsControl;
    [Test] procedure ListClickSelectsRow;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDialogJson, uTerminalTypes, uThemeTypes;

const
  cClick =
    '{"type":"dialog","version":"2.0","title":"Click","width":44,"height":12,' +
    '"children":[' +
    '{"type":"checkbox","id":"opt","text":"&Option","checked":false,' +
    '"col":1,"row":0,"width":20,"height":1},' +
    '{"type":"list","id":"files","items":["one","two","three"],"selected":0,' +
    '"col":1,"row":1,"width":20,"height":3},' +
    '{"type":"dropdown","id":"mode","items":["a","b","c"],"selected":0,' +
    '"col":1,"row":5,"width":12,"height":1},' +
    '{"type":"button","id":"ok","text":"OK","default":true,' +
    '"col":1,"row":7,"width":10,"height":1},' +
    '{"type":"button","id":"cancel","text":"Cancel","cancel":true,' +
    '"col":14,"row":7,"width":12,"height":1}' +
    ']}';

var
  Fired: string;

procedure Layout(AHost: TDialogHost);
var
  Grid: TTerminalGrid;
begin
  AllocTerminalGrid(Grid, 60, 20);
  ClearTerminalGrid(Grid, TAlphaColorRec.White, TAlphaColorRec.Navy, ' ');
  AHost.Draw(Grid, 60, 20);
end;

function OpenClick(AOnCommand: TDialogCommandEvent = nil): TDialogHost;
begin
  Result := TDialogHost.Create(nil);
  Assert.IsTrue(Result.OpenJson(cClick, AOnCommand), 'click dialog opens');
  Layout(Result);
end;

procedure TTestDialogClickRouting.OutsideClickCancels;
var
  Host: TDialogHost;
begin
  Fired := '';
  Host := OpenClick(
    procedure(const AControlId, AValuesJson: string)
    begin
      Fired := Fired + AControlId + ';';
    end);
  try
    Assert.IsTrue(Host.HandleClick(0, 0), 'outside click is handled');
    Assert.IsTrue(Pos('cancel;', Fired) > 0, 'outside click cancels');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogClickRouting.CheckboxClickToggles;
var
  Host: TDialogHost;
  R: TRectI;
  Idx: Integer;
begin
  Host := OpenClick(nil);
  try
    Assert.IsFalse(Host.GetCheckbox('opt'));
    Idx := -1;
    for var I := 0 to Host.ControlCount - 1 do
      if Host.GetControl(I).Id = 'opt' then
      begin
        Idx := I;
        Break;
      end;
    Assert.IsTrue(Idx >= 0, 'checkbox present');
    R := Host.ControlBoundsAt(Idx);
    Assert.IsTrue(Host.HandleClick(R.Left, R.Top), 'checkbox click handled');
    Assert.IsTrue(Host.GetCheckbox('opt'), 'checkbox toggles on');
    Assert.AreEqual('opt', Host.FocusedControlId);
  finally
    Host.Free;
  end;
end;

procedure TTestDialogClickRouting.ButtonClickFiresWithoutPressTimer;
var
  Host: TDialogHost;
  R: TRectI;
  Idx: Integer;
begin
  GDialogButtonPressStart := nil;
  Fired := '';
  Host := OpenClick(
    procedure(const AControlId, AValuesJson: string)
    begin
      Fired := Fired + AControlId + ';';
    end);
  try
    for Idx := 0 to Host.ControlCount - 1 do
      if Host.GetControl(Idx).Id = 'ok' then
        Break;
    R := Host.ControlBoundsAt(Idx);
    Assert.IsTrue(Host.HandleClick(R.Left + 1, R.Top), 'button click handled');
    Assert.AreEqual('ok;', Fired, 'button fires at once without a press timer');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogClickRouting.DropDownFieldOpensAndCloses;
var
  Host: TDialogHost;
  R: TRectI;
  Idx: Integer;
begin
  Host := OpenClick(nil);
  try
    for Idx := 0 to Host.ControlCount - 1 do
      if Host.GetControl(Idx).Id = 'mode' then
        Break;
    R := Host.ControlBoundsAt(Idx);
    Assert.IsTrue(Host.HandleClick(R.Left, R.Top), 'dropdown click opens');
    Assert.IsTrue(Host.DropDownOpen, 'dropdown is open');
    Assert.IsTrue(Host.HandleClick(R.Left, R.Top), 'second click closes');
    Assert.IsFalse(Host.DropDownOpen, 'dropdown is closed');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogClickRouting.OpenDropDownClickOutsideClosesThenHitsControl;
var
  Host: TDialogHost;
  DropR, CheckR: TRectI;
  DropIdx, CheckIdx: Integer;
begin
  Host := OpenClick(nil);
  try
    for DropIdx := 0 to Host.ControlCount - 1 do
      if Host.GetControl(DropIdx).Id = 'mode' then
        Break;
    for CheckIdx := 0 to Host.ControlCount - 1 do
      if Host.GetControl(CheckIdx).Id = 'opt' then
        Break;
    DropR := Host.ControlBoundsAt(DropIdx);
    CheckR := Host.ControlBoundsAt(CheckIdx);
    Assert.IsTrue(Host.HandleClick(DropR.Left, DropR.Top));
    Assert.IsTrue(Host.DropDownOpen);
    Assert.IsFalse(Host.GetCheckbox('opt'));
    // Click the checkbox while the popup is open: popup closes, checkbox toggles.
    Assert.IsTrue(Host.HandleClick(CheckR.Left, CheckR.Top));
    Assert.IsFalse(Host.DropDownOpen, 'popup closed by the outside click');
    Assert.IsTrue(Host.GetCheckbox('opt'), 'checkbox still received the click');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogClickRouting.ListClickSelectsRow;
var
  Host: TDialogHost;
  R: TRectI;
  Idx: Integer;
begin
  Host := OpenClick(nil);
  try
    for Idx := 0 to Host.ControlCount - 1 do
      if Host.GetControl(Idx).Id = 'files' then
        Break;
    R := Host.ControlBoundsAt(Idx);
    Assert.AreEqual(0, Host.GetListSelectedIndex('files'));
    Assert.IsTrue(Host.HandleClick(R.Left, R.Top + 1), 'second row click');
    Assert.AreEqual(1, Host.GetListSelectedIndex('files'));
    Assert.AreEqual('files', Host.FocusedControlId);
  finally
    Host.Free;
  end;
end;

end.
