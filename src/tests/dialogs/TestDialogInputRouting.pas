unit TestDialogInputRouting;

{ Characterization of TDialogHost.HandleInputCore order: which control wins
  when several could take the same key, and that a button press from a prior
  Open does not fire after a later Open bumps the generation. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogInputRouting = class
  public
    [TearDown] procedure TearDown;
    [Test] procedure HotKeyCaptureBeatsMnemonic;
    [Test] procedure OpenDropDownConsumesEnterAndEsc;
    [Test] procedure DialogNavBeatsFocusedList;
    [Test] procedure ListArrowsBeatFocusMove;
    [Test] procedure UnusedKeyIsConsumed;
    [Test] procedure ReopenDropsPendingPress;
    [Test] procedure DropDownHoverAfterNavKeyClamps;
    [Test] procedure ListSelectedIndexAfterNavKeySteps;
    [Test] procedure ListKeyCommandClassification;
    [Test] procedure DropHoverAfterScrollBarClickSteps;
    [Test] procedure OpenDropDownClickHitsItemColGates;
    [Test] procedure OpenDropDownKeyClassification;
    [Test] procedure ClosedDropDownOpenAndMaskChords;
    [Test] procedure ListSelectionNavKeyAndInputGuards;
    [Test] procedure HotKeyMultiJoinAndAppend;
    [Test] procedure MnemonicKeysActiveAndLetterCandidates;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, System.Character,
  uDialogHost, uDialogTypes, uDialogJson, uDialogHostKeys, uDialogHostClicks,
  uInputLine;

const
  cRouting =
    '{"type":"dialog","version":"2.0","title":"Route","width":44,"height":12,' +
    '"children":[' +
    '{"type":"input","id":"key","value":"","hotkey":true,"col":1,"row":0,"width":20,"height":1},' +
    '{"type":"list","id":"files","items":["one","two","three"],"selected":0,' +
    '"col":1,"row":1,"width":20,"height":3},' +
    '{"type":"dropdown","id":"mode","items":["a","b","c"],"selected":0,' +
    '"col":1,"row":5,"width":12,"height":1},' +
    '{"type":"button","id":"yes","text":"&Yes","col":1,"row":7,"width":10,"height":1},' +
    '{"type":"button","id":"no","text":"&No","cancel":true,"col":14,"row":7,"width":10,"height":1},' +
    '{"type":"button","id":"ok","text":"OK","default":true,"col":28,"row":7,"width":10,"height":1}' +
    ']}';

var
  Fired: string;

procedure Press(AHost: TDialogHost; var AKey: Word; AShift: TShiftState;
  var AChar: Char);
begin
  AHost.HandleInput(AKey, AShift, AChar);
end;

procedure PressKey(AHost: TDialogHost; AKey: Word; AShift: TShiftState = [];
  AChar: Char = #0);
var
  Key: Word;
  Ch: Char;
begin
  Key := AKey;
  Ch := AChar;
  Press(AHost, Key, AShift, Ch);
end;

function OpenRouting(AOnCommand: TDialogCommandEvent = nil): TDialogHost;
begin
  Result := TDialogHost.Create(nil);
  Assert.IsTrue(Result.OpenJson(cRouting, AOnCommand), 'routing dialog opens');
end;

procedure TTestDialogInputRouting.TearDown;
begin
  GDialogPressHoldKey := 0;
  CancelDialogButtonPress;
  FlushDialogButtonPress;
  GDialogButtonPressStart := nil;
  Fired := '';
end;

procedure TTestDialogInputRouting.HotKeyCaptureBeatsMnemonic;
var
  Host: TDialogHost;
begin
  Fired := '';
  Host := OpenRouting(
    procedure(const AControlId, AValuesJson: string)
    begin
      Fired := Fired + AControlId + ';';
    end);
  try
    Host.FocusControlById('key');
    PressKey(Host, Ord('Y'), [], 'y');
    Assert.AreEqual('Y', Host.GetInputValue('key'),
      'a focused hotkey field stores the letter');
    Assert.AreEqual('', Fired, 'the Yes mnemonic does not run');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogInputRouting.OpenDropDownConsumesEnterAndEsc;
var
  Host: TDialogHost;
  Key: Word;
  Ch: Char;
begin
  Fired := '';
  Host := OpenRouting(
    procedure(const AControlId, AValuesJson: string)
    begin
      Fired := Fired + AControlId + ';';
    end);
  try
    Host.FocusControlById('mode');
    PressKey(Host, vkF4);
    Assert.IsTrue(Host.DropDownOpen, 'F4 opens the dropdown');

    Key := vkReturn;
    Ch := #0;
    Press(Host, Key, [], Ch);
    Assert.IsFalse(Host.DropDownOpen, 'Enter commits the popup');
    Assert.AreEqual(0, Key, 'Enter is consumed');
    Assert.AreEqual('', Fired, 'Enter does not accept the dialog');

    PressKey(Host, vkF4);
    Assert.IsTrue(Host.DropDownOpen, 'F4 opens again');
    Key := vkEscape;
    Ch := #0;
    Press(Host, Key, [], Ch);
    Assert.IsFalse(Host.DropDownOpen, 'Esc collapses the popup');
    Assert.AreEqual(0, Key, 'Esc is consumed');
    Assert.AreEqual('', Fired, 'Esc does not cancel the dialog');
    Assert.IsTrue(Host.Visible, 'the dialog stays open');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogInputRouting.DialogNavBeatsFocusedList;
var
  Host: TDialogHost;
begin
  Fired := '';
  Host := OpenRouting(
    procedure(const AControlId, AValuesJson: string)
    begin
      Fired := Fired + AControlId + ';';
    end);
  try
    Host.FocusControlById('files');
    Assert.AreEqual(0, Host.GetListSelectedIndex('files'));
    PressKey(Host, vkTab);
    Assert.AreEqual('mode', Host.FocusedControlId,
      'Tab moves focus instead of staying on the list');
    Assert.AreEqual(0, Host.GetListSelectedIndex('files'),
      'Tab does not change the list selection');

    Host.FocusControlById('files');
    PressKey(Host, vkReturn);
    Assert.IsTrue(Pos('ok;', Fired) > 0, 'Enter accepts via the default button');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogInputRouting.ListArrowsBeatFocusMove;
var
  Host: TDialogHost;
begin
  Host := OpenRouting(nil);
  try
    Host.FocusControlById('files');
    Assert.AreEqual(0, Host.GetListSelectedIndex('files'));
    PressKey(Host, vkDown);
    Assert.AreEqual(1, Host.GetListSelectedIndex('files'),
      'Down moves the list selection');
    Assert.AreEqual('files', Host.FocusedControlId,
      'Down does not move dialog focus off the list');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogInputRouting.UnusedKeyIsConsumed;
var
  Host: TDialogHost;
  Key: Word;
  Ch: Char;
begin
  Host := OpenRouting(nil);
  try
    Host.FocusControlById('yes');
    Key := vkF7;
    Ch := #0;
    Press(Host, Key, [], Ch);
    Assert.AreEqual(0, Key, 'an unused key is cleared');
    Assert.AreEqual(#0, Ch, 'the unused key char is cleared');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogInputRouting.ReopenDropsPendingPress;
var
  Host: TDialogHost;
  Starts: Integer;
begin
  Starts := 0;
  GDialogButtonPressStart :=
    procedure
    begin
      Inc(Starts);
    end;
  Fired := '';
  Host := OpenRouting(
    procedure(const AControlId, AValuesJson: string)
    begin
      Fired := Fired + AControlId + ';';
    end);
  try
    PressKey(Host, vkReturn);
    Assert.IsTrue(DialogButtonPressPending, 'Enter starts a press');
    Assert.AreEqual(1, Starts, 'press timer started');
    Assert.AreEqual('', Fired, 'nothing runs while pressed');

    Assert.IsTrue(Host.OpenJson(cRouting,
      procedure(const AControlId, AValuesJson: string)
      begin
        Fired := Fired + AControlId + ';';
      end), 'reopen bumps the generation');
    FlushDialogButtonPress;
    Assert.AreEqual('', Fired,
      'a press from the prior Open does not fire after reopen');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogInputRouting.DropDownHoverAfterNavKeyClamps;
begin
  Assert.IsTrue(DropDownHoverAfterNavKey(2, 9, 4, vkUp) = 1, 'up');
  Assert.IsTrue(DropDownHoverAfterNavKey(0, 9, 4, vkUp) = 0, 'up clamps');
  Assert.IsTrue(DropDownHoverAfterNavKey(2, 9, 4, vkDown) = 3, 'down');
  Assert.IsTrue(DropDownHoverAfterNavKey(9, 9, 4, vkDown) = 9, 'down clamps');
  Assert.IsTrue(DropDownHoverAfterNavKey(5, 9, 4, vkHome) = 0, 'home');
  Assert.IsTrue(DropDownHoverAfterNavKey(5, 9, 4, vkEnd) = 9, 'end');
  Assert.IsTrue(DropDownHoverAfterNavKey(5, 9, 4, vkPrior) = 1, 'pgup');
  Assert.IsTrue(DropDownHoverAfterNavKey(5, 9, 4, vkNext) = 9, 'pgdn clamps');
  Assert.IsTrue(DropDownHoverAfterNavKey(5, 9, 0, vkPrior) = 4,
    'view height floors at 1');
  Assert.IsTrue(DropDownHoverAfterNavKey(5, 9, 4, vkLeft) = 5,
    'non-nav key leaves hover');
end;

procedure TTestDialogInputRouting.ListSelectedIndexAfterNavKeySteps;
begin
  Assert.IsTrue(ListSelectedIndexAfterNavKey(2, 9, 4, vkUp, True) = 1, 'up');
  Assert.IsTrue(ListSelectedIndexAfterNavKey(2, 9, 4, vkDown, True) = 3, 'down');
  Assert.IsTrue(ListSelectedIndexAfterNavKey(5, 9, 4, vkHome, True) = 0, 'home');
  Assert.IsTrue(ListSelectedIndexAfterNavKey(5, 9, 4, vkEnd, True) = 9, 'end');
  Assert.IsTrue(ListSelectedIndexAfterNavKey(5, 9, 4, vkPrior, True) = 1,
    'list pgup');
  Assert.IsTrue(ListSelectedIndexAfterNavKey(5, 9, 4, vkNext, True) = 9,
    'list pgdn');
  Assert.IsTrue(ListSelectedIndexAfterNavKey(5, 9, 4, vkPrior, False) = 4,
    'radio pgup steps one');
  Assert.IsTrue(ListSelectedIndexAfterNavKey(5, 9, 4, vkNext, False) = 6,
    'radio pgdn steps one');
  Assert.IsTrue(ListSelectedIndexAfterNavKey(5, 9, 0, vkPrior, True) = 4,
    'view height floors at 1');
end;

procedure TTestDialogInputRouting.ListKeyCommandClassification;
begin
  Assert.AreEqual('toggle', ClassifyListKeyCommand(vkSpace, #0, []), 'space');
  Assert.AreEqual('toggle', ClassifyListKeyCommand(0, ' ', []), 'space char');
  Assert.AreEqual('up', ClassifyListKeyCommand(vkUp, #0, [ssCtrl]), 'ctrl+up');
  Assert.AreEqual('down', ClassifyListKeyCommand(vkDown, #0, [ssCtrl]),
    'ctrl+down');
  Assert.AreEqual('delete', ClassifyListKeyCommand(vkDelete, #0, []), 'del');
  Assert.AreEqual('f2', ClassifyListKeyCommand(vkF2, #0, []), 'f2');
  Assert.AreEqual('f4', ClassifyListKeyCommand(vkF4, #0, []), 'f4');
  Assert.AreEqual('f5', ClassifyListKeyCommand(vkF5, #0, []), 'f5');
  Assert.AreEqual('', ClassifyListKeyCommand(vkUp, #0, []), 'bare up');
  Assert.AreEqual('', ClassifyListKeyCommand(vkDelete, #0, [ssCtrl]),
    'ctrl+del not a list cmd');
end;

procedure TTestDialogInputRouting.DropHoverAfterScrollBarClickSteps;
begin
  Assert.IsTrue(DropHoverAfterScrollBarClick(2, 9, 5, 10, 10, 14) = 1,
    'top arrow');
  Assert.IsTrue(DropHoverAfterScrollBarClick(2, 9, 5, 14, 10, 14) = 3,
    'bottom arrow');
  Assert.IsTrue(DropHoverAfterScrollBarClick(0, 9, 5, 10, 10, 14) = 0,
    'top clamps');
  Assert.IsTrue(DropHoverAfterScrollBarClick(9, 9, 5, 14, 10, 14) = 9,
    'bottom clamps');
  // track: Round((12-10-1)*9 / Max(5-3,1)) = Round(4.5) -> 4
  Assert.IsTrue(DropHoverAfterScrollBarClick(0, 9, 5, 12, 10, 14) = 4,
    'track maps');
end;

procedure TTestDialogInputRouting.OpenDropDownClickHitsItemColGates;
begin
  Assert.IsTrue(OpenDropDownClickHitsItemCol(5, 2, 10, False), 'no bar inside');
  Assert.IsTrue(OpenDropDownClickHitsItemCol(10, 2, 10, False), 'no bar right');
  Assert.IsTrue(not OpenDropDownClickHitsItemCol(10, 2, 10, True),
    'bar column excluded');
  Assert.IsTrue(OpenDropDownClickHitsItemCol(9, 2, 10, True), 'left of bar');
  Assert.IsTrue(not OpenDropDownClickHitsItemCol(1, 2, 10, False), 'left of popup');
end;

procedure TTestDialogInputRouting.OpenDropDownKeyClassification;
begin
  Assert.AreEqual(Ord(odkaCommit),
    Ord(ClassifyOpenDropDownKey(vkReturn, #0, True, False)), 'accept');
  Assert.AreEqual(Ord(odkaCommit),
    Ord(ClassifyOpenDropDownKey(vkSpace, ' ', True, False)), 'space via flag');
  Assert.AreEqual(Ord(odkaClose),
    Ord(ClassifyOpenDropDownKey(vkEscape, #0, False, False)), 'esc');
  Assert.AreEqual(Ord(odkaDeleteHistory),
    Ord(ClassifyOpenDropDownKey(vkDelete, #0, False, True)), 'del history');
  Assert.AreEqual(Ord(odkaSwallow),
    Ord(ClassifyOpenDropDownKey(vkDelete, #0, False, False)), 'del non-history');
  Assert.AreEqual(Ord(odkaTabAway),
    Ord(ClassifyOpenDropDownKey(vkTab, #0, False, False)), 'tab');
  Assert.AreEqual(Ord(odkaNavHover),
    Ord(ClassifyOpenDropDownKey(vkDown, #0, False, False)), 'nav');
  Assert.AreEqual(Ord(odkaSwallow),
    Ord(ClassifyOpenDropDownKey(Ord('A'), 'a', False, False)), 'other');
end;

procedure TTestDialogInputRouting.ClosedDropDownOpenAndMaskChords;
begin
  Assert.IsTrue(ShouldOpenFocusedDropDown(vkF4, #0, []), 'f4');
  Assert.IsTrue(ShouldOpenFocusedDropDown(vkSpace, ' ', []), 'space');
  Assert.IsTrue(ShouldOpenFocusedDropDown(vkDown, #0, [ssAlt]), 'alt+down');
  Assert.IsTrue(not ShouldOpenFocusedDropDown(vkDown, #0, []), 'bare down');
  Assert.IsTrue(IsMaskHistoryGroupSaveChord(Ord('G'), [ssCtrl], 'masks'),
    'masks');
  Assert.IsTrue(IsMaskHistoryGroupSaveChord(Ord('G'), [ssCtrl], 'findmask'),
    'findmask');
  Assert.IsTrue(not IsMaskHistoryGroupSaveChord(Ord('G'), [ssCtrl], 'path'),
    'other history');
  Assert.IsTrue(not IsMaskHistoryGroupSaveChord(Ord('G'), [ssCtrl, ssAlt], 'masks'),
    'ctrl+alt+g');
end;

procedure TTestDialogInputRouting.ListSelectionNavKeyAndInputGuards;
begin
  Assert.IsTrue(IsListSelectionNavKey(vkUp), 'up');
  Assert.IsTrue(IsListSelectionNavKey(vkNext), 'pgdn');
  Assert.IsTrue(not IsListSelectionNavKey(vkLeft), 'left');
  Assert.AreEqual('password-copy',
    ClassifyFocusedInputGuard(True, False, Ord('C'), 'c', [ssCtrl]),
    'password ctrl+c');
  Assert.AreEqual('',
    ClassifyFocusedInputGuard(False, False, Ord('C'), 'c', [ssCtrl]),
    'normal ctrl+c');
  Assert.AreEqual('readonly-edit',
    ClassifyFocusedInputGuard(False, True, vkBack, #0, []), 'readonly back');
  Assert.AreEqual('',
    ClassifyFocusedInputGuard(False, True, vkLeft, #0, []), 'readonly left');
end;

procedure TTestDialogInputRouting.HotKeyMultiJoinAndAppend;
begin
  Assert.AreEqual('A; B', HotKeyMultiJoinExceptLast(['A', 'B', 'C']), 'drop last');
  Assert.AreEqual('', HotKeyMultiJoinExceptLast(['A']), 'single');
  Assert.AreEqual('Ctrl+X', HotKeyMultiAppendChord('', 'Ctrl+X'), 'first');
  Assert.AreEqual('Ctrl+X; Alt+Y', HotKeyMultiAppendChord('Ctrl+X', 'Alt+Y'),
    'append');
  Assert.AreEqual('Ctrl+X', HotKeyMultiAppendChord('Ctrl+X', 'Ctrl+X'), 'dup');
  Assert.AreEqual('Ctrl+X', HotKeyMultiAppendChord('Ctrl+X', ''), 'empty chord');
end;

procedure TTestDialogInputRouting.MnemonicKeysActiveAndLetterCandidates;
var
  Letters: TArray<Char>;
begin
  Assert.IsTrue(DialogMnemonicKeysActive([ssAlt], True), 'alt on input');
  Assert.IsTrue(DialogMnemonicKeysActive([], False), 'non-input');
  Assert.IsTrue(not DialogMnemonicKeysActive([], True), 'bare input');

  Letters := DialogMnemonicLetterCandidates(vkA, 'a');
  Assert.IsTrue(Length(Letters) = 2, 'typed + layout alternate');
  Assert.IsTrue(Letters[0] = 'A', 'typed upper');
  Assert.IsTrue(Letters[1] = TextKeyLayoutAlternate('a').ToUpper, 'layout alternate');

  Letters := DialogMnemonicLetterCandidates(vkB, #0);
  Assert.IsTrue(Length(Letters) = 1, 'physical only');
  Assert.IsTrue(Letters[0] = 'B', 'physical B');
end;

end.
