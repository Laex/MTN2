unit uDialogHostKeys;

{ Keyboard routing for TDialogHost. The host fills TDialogKeyOps with method
  pointers into its private helpers; the free functions below own the order
  and the per-control branches so HandleInputCore stays a short dispatcher. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogTypes;

type
  TDialogYesNoAnswer = (dyaNone, dyaYes, dyaNo);

  TDialogKeyBoolFn = function: Boolean of object;
  TDialogKeyIntFn = function: Integer of object;
  TDialogKeyIntIntFn = function(AValue: Integer): Integer of object;
  TDialogKeySetIntProc = procedure(AValue: Integer) of object;
  TDialogKeyIndexFn = function(AIndex: Integer): Boolean of object;
  TDialogKeyIndexProc = procedure(AIndex: Integer) of object;
  TDialogKeyNextFocusFn = function(AFrom: Integer; AForward: Boolean): Integer of object;
  TDialogKeyControlFn = function(AIndex: Integer): TDialogControl of object;
  TDialogKeySetControlProc = procedure(AIndex: Integer; const AControl: TDialogControl) of object;
  TDialogKeyIdFn = function(const AId: string): Integer of object;
  TDialogKeyIdProc = procedure(const AId: string) of object;
  TDialogKeyListSelProc = procedure(AControlIndex, ASelected: Integer) of object;
  TDialogKeyYesNoFn = function(AYes: Boolean): Boolean of object;
  TDialogKeyCharFn = function(ACh: Char): Boolean of object;
  TDialogKeyNormFn = function(var AKey: Word; var AKeyChar: Char): Boolean of object;
  TDialogKeyProc = procedure of object;

  /// <summary>Primitives the key handlers need from the open dialog host.</summary>
  TDialogKeyOps = record
    Visible: TDialogKeyBoolFn;
    CursorVisible: TDialogKeyBoolFn;
    ShowCursor: TDialogKeyProc;
    NotifyChanged: TDialogKeyProc;
    FireAccept: TDialogKeyProc;
    FireCancel: TDialogKeyProc;
    FireCommand: TDialogKeyIdProc;
    PressButton: TDialogKeyIndexProc;
    SelectRadio: TDialogKeyIndexProc;
    CommitDropDown: TDialogKeyProc;
    CloseDropDown: TDialogKeyProc;
    OpenDropDown: TDialogKeyIndexProc;
    IsHistoryInput: TDialogKeyIndexFn;
    RemoveDropHoverFromHistory: TDialogKeyProc;
    EnsureDropHoverInView: TDialogKeyProc;
    NormalizeAcceptKey: TDialogKeyNormFn;
    NextFocusable: TDialogKeyNextFocusFn;
    FocusedIsInput: TDialogKeyBoolFn;
    TryYesNoButton: TDialogKeyYesNoFn;
    TryMnemonic: TDialogKeyCharFn;
    ButtonIndexById: TDialogKeyIdFn;
    SetListSelectedIndex: TDialogKeyListSelProc;
    ListViewHeight: TDialogKeyIntIntFn;
    FocusIndex: TDialogKeyIntFn;
    SetFocusIndex: TDialogKeySetIntProc;
    DropOpenIndex: TDialogKeyIntFn;
    DropHover: TDialogKeyIntFn;
    SetDropHover: TDialogKeySetIntProc;
    DropPopupViewHeight: TDialogKeyIntFn;
    ControlCount: TDialogKeyIntFn;
    GetControl: TDialogKeyControlFn;
    SetControl: TDialogKeySetControlProc;
  end;

/// <summary>y/n (and Cyrillic да/нет) mapped to Yes/No buttons.</summary>
function DialogYesNoAnswer(AKey: Word; AKeyChar: Char): TDialogYesNoAnswer;

/// <summary>True when mnemonic / YesNo hotkeys run: Alt held, or focus is not
/// in an input field.</summary>
function DialogMnemonicKeysActive(AShift: TShiftState;
  AFocusedIsInput: Boolean): Boolean;

/// <summary>Uppercase letter candidates to try as dialog mnemonics, in order:
/// typed letter, layout alternate, then physical A..Z when different.</summary>
function DialogMnemonicLetterCandidates(AKey: Word; AKeyChar: Char): TArray<Char>;

/// <summary>Join non-empty AParts with '; ', dropping a trailing empty slot
/// (Backspace on a multi hotkey field).</summary>
function HotKeyMultiJoinExceptLast(const AParts: TArray<string>): string;

/// <summary>Append AChord to ACurrent with '; ', or replace when ACurrent is
/// blank. Duplicate chords leave ACurrent unchanged.</summary>
function HotKeyMultiAppendChord(const ACurrent, AChord: string): string;

/// <summary>Multi-chord hotkey field text after one keystroke.</summary>
function HotKeyMultiText(const ACurrent: string; AKey: Word; AKeyChar: Char;
  AShift: TShiftState): string;

/// <summary>Low byte of AKey when hosts pack modifier flags above $FF.</summary>
function NormalizeDialogVirtualKey(AKey: Word): Word;

/// <summary>True for Esc / Tab / Enter that leave a hotkey field alone.</summary>
function HotKeyFieldIgnoresNavKey(AKey: Word): Boolean;

type
  /// <summary>What a focused hotkey input does with one keystroke after nav
  /// keys are filtered. hkfaSwallow keeps the field; hkfaApply writes AChord.</summary>
  THotKeyFieldKeyAction = (hkfaSwallow, hkfaApply);

/// <summary>AMulti selects HotKeyMultiText; otherwise Back/Del clear and other
/// chords come from InputChordText. Empty single chords swallow.</summary>
function ClassifyHotKeyFieldKey(AMulti: Boolean; const ACurrent: string;
  AKey: Word; AKeyChar: Char; AShift: TShiftState;
  out AChord: string): THotKeyFieldKeyAction;

/// <summary>New DropDown hover index after Up/Down/Home/End/PgUp/PgDn.
/// ALast is High(Items); AViewH is the popup page size (at least 1).
/// Non-nav keys leave AHover unchanged.</summary>
function DropDownHoverAfterNavKey(AHover, ALast, AViewH: Integer;
  AKey: Word): Integer;

/// <summary>New list/radio/dropdown selection after arrow keys. ALast is
/// High(Items); AViewH is the list page height (at least 1). APageScroll:
/// True for dckList PgUp/PgDn; False steps by 1 (radio/dropdown).</summary>
function ListSelectedIndexAfterNavKey(ASelected, ALast, AViewH: Integer;
  AKey: Word; APageScroll: Boolean): Integer;

/// <summary>Key-command id for a list with KeyCommands, or '' when the chord
/// is not a list command. Does not cover Del-as-Delete-button.</summary>
function ClassifyListKeyCommand(AKey: Word; AKeyChar: Char;
  AShift: TShiftState): string;

/// <summary>True for Up/Down/Home/End/PgUp/PgDn used by list/radio/dropdown
/// selection movement.</summary>
function IsListSelectionNavKey(AKey: Word): Boolean;

/// <summary>'' = pass the key to InputLine; 'password-copy' / 'readonly-edit'
/// = swallow without changing the field.</summary>
function ClassifyFocusedInputGuard(APassword, AReadOnly: Boolean;
  AKey: Word; AKeyChar: Char; AShift: TShiftState): string;

type
  /// <summary>What an open DropDown does with a key after accept/space
  /// normalization. odkaSwallow keeps the popup up and eats the key.</summary>
  TOpenDropDownKeyAction = (odkaCommit, odkaClose, odkaDeleteHistory,
    odkaTabAway, odkaNavHover, odkaSwallow);

/// <summary>AAcceptOrSpace is True after NormalizeAcceptKey or Space.
/// AIsHistoryInput gates Del as "forget highlighted history entry".</summary>
function ClassifyOpenDropDownKey(AKey: Word; AKeyChar: Char;
  AAcceptOrSpace, AIsHistoryInput: Boolean): TOpenDropDownKeyAction;

/// <summary>True for F4 / Alt+Down / Space on a closed focused DropDown.</summary>
function ShouldOpenFocusedDropDown(AKey: Word; AKeyChar: Char;
  AShift: TShiftState): Boolean;

/// <summary>True for Ctrl+G on an input whose History is masks / findmask.</summary>
function IsMaskHistoryGroupSaveChord(AKey: Word; AShift: TShiftState;
  const AHistory: string): Boolean;

function DialogHandleOpenDropDownKeys(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
function DialogHandleDialogNavKeys(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
function DialogHandleClosedDropDownKeys(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
function DialogHandleFocusedSpaceKey(const Ops: TDialogKeyOps; var AKey: Word;
  var AKeyChar: Char): Boolean;
function DialogHandleMnemonicKeys(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
function DialogHandleHotKeyInput(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
function DialogHandleFocusedPickerKeys(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
function DialogHandleListCommandKeys(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
function DialogHandleListNavKeys(const Ops: TDialogKeyOps; var AKey: Word): Boolean;
function DialogHandleFocusedInputKeys(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
function DialogHandleFocusArrowKeys(const Ops: TDialogKeyOps; var AKey: Word): Boolean;
function DialogHandleInputCore(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;

implementation

uses
  System.Math, System.Character, System.StrUtils,
  uKeyChord, uInputLine, uMaskGroups, uPluginInputChord,
  uColorPickerControl, uDatePickerControl;

function DialogYesNoAnswer(AKey: Word; AKeyChar: Char): TDialogYesNoAnswer;
begin
  // By meaning first: y / д (Да) = Yes, n / н (Нет) = No, in any case. Then
  // the physical key, for any other layout (the Russian т sits on N and
  // answers No; н sits on Y but its meaning wins).
  case AKeyChar of
    'y', 'Y', #$0434, #$0414: Exit(dyaYes);
    'n', 'N', #$043D, #$041D: Exit(dyaNo);
  end;
  if AKey = vkY then
    Exit(dyaYes);
  if AKey = vkN then
    Exit(dyaNo);
  Result := dyaNone;
end;

function DialogMnemonicKeysActive(AShift: TShiftState;
  AFocusedIsInput: Boolean): Boolean;
begin
  Result := (ssAlt in AShift) or (not AFocusedIsInput);
end;

function DialogMnemonicLetterCandidates(AKey: Word; AKeyChar: Char): TArray<Char>;
var
  Ch, Alt: Char;
begin
  SetLength(Result, 0);
  Ch := #0;
  if AKeyChar.IsLetter then
    Ch := AKeyChar.ToUpper;
  if Ch <> #0 then
  begin
    Alt := TextKeyLayoutAlternate(AKeyChar).ToUpper;
    if (Alt <> #0) and (Alt <> Ch) then
      Result := [Ch, Alt]
    else
      Result := [Ch];
  end;
  if (AKey >= vkA) and (AKey <= vkZ) and (Char(AKey) <> Ch) then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Char(AKey);
  end;
end;

function HotKeyMultiJoinExceptLast(const AParts: TArray<string>): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AParts) - 1 do
    if AParts[I] <> '' then
    begin
      if Result <> '' then
        Result := Result + '; ';
      Result := Result + AParts[I];
    end;
end;

function HotKeyMultiAppendChord(const ACurrent, AChord: string): string;
var
  Parts: TArray<string>;
  P: string;
  I: Integer;
begin
  if AChord = '' then
    Exit(ACurrent);
  Parts := ACurrent.Split([';']);
  for I := 0 to High(Parts) do
    Parts[I] := Trim(Parts[I]);
  for P in Parts do
    if SameText(P, AChord) then
      Exit(ACurrent);
  if Trim(ACurrent) = '' then
    Result := AChord
  else
    Result := Trim(ACurrent) + '; ' + AChord;
end;

function HotKeyMultiText(const ACurrent: string; AKey: Word; AKeyChar: Char;
  AShift: TShiftState): string;
var
  Parts: TArray<string>;
  Chord: string;
  I: Integer;
begin
  Parts := ACurrent.Split([';']);
  for I := 0 to High(Parts) do
    Parts[I] := Trim(Parts[I]);
  if AShift * [ssShift, ssCtrl, ssAlt] = [] then
  begin
    if AKey = vkDelete then
      Exit('');
    if AKey = vkBack then
      Exit(HotKeyMultiJoinExceptLast(Parts));
  end;
  Chord := KeystrokeBindingText(AKey, AKeyChar, AShift);
  Result := HotKeyMultiAppendChord(ACurrent, Chord);
end;

function NormalizeDialogVirtualKey(AKey: Word): Word;
begin
  if AKey > $FF then
    Result := AKey and $FF
  else
    Result := AKey;
end;

function HotKeyFieldIgnoresNavKey(AKey: Word): Boolean;
begin
  Result := (AKey = vkEscape) or (AKey = vkTab) or (AKey = vkReturn);
end;

function ClassifyHotKeyFieldKey(AMulti: Boolean; const ACurrent: string;
  AKey: Word; AKeyChar: Char; AShift: TShiftState;
  out AChord: string): THotKeyFieldKeyAction;
begin
  AChord := '';
  if AMulti then
  begin
    AChord := HotKeyMultiText(ACurrent, AKey, AKeyChar, AShift);
    if AChord = ACurrent then
      Exit(hkfaSwallow);
    Exit(hkfaApply);
  end;
  if (AShift * [ssShift, ssCtrl, ssAlt] = []) and
     ((AKey = vkBack) or (AKey = vkDelete)) then
  begin
    AChord := '';
    Exit(hkfaApply);
  end;
  AChord := InputChordText(AKey, AKeyChar, AShift);
  // A bare modifier names no key yet; the field keeps its value.
  if AChord = '' then
    Exit(hkfaSwallow);
  Result := hkfaApply;
end;

function DropDownHoverAfterNavKey(AHover, ALast, AViewH: Integer;
  AKey: Word): Integer;
var
  ViewH: Integer;
begin
  ViewH := Max(AViewH, 1);
  if AKey = vkUp then
    Result := EnsureRange(AHover - 1, 0, ALast)
  else if AKey = vkDown then
    Result := EnsureRange(AHover + 1, 0, ALast)
  else if AKey = vkHome then
    Result := 0
  else if AKey = vkEnd then
    Result := ALast
  else if AKey = vkPrior then
    Result := EnsureRange(AHover - ViewH, 0, ALast)
  else if AKey = vkNext then
    Result := EnsureRange(AHover + ViewH, 0, ALast)
  else
    Result := AHover;
end;

function ListSelectedIndexAfterNavKey(ASelected, ALast, AViewH: Integer;
  AKey: Word; APageScroll: Boolean): Integer;
var
  ViewH: Integer;
begin
  ViewH := Max(AViewH, 1);
  if AKey = vkUp then
    Result := ASelected - 1
  else if AKey = vkDown then
    Result := ASelected + 1
  else if AKey = vkHome then
    Result := 0
  else if AKey = vkEnd then
    Result := ALast
  else if AKey = vkPrior then
  begin
    if APageScroll then
      Result := ASelected - ViewH
    else
      Result := ASelected - 1;
  end
  else if AKey = vkNext then
  begin
    if APageScroll then
      Result := ASelected + ViewH
    else
      Result := ASelected + 1;
  end
  else
    Result := ASelected;
end;

function ClassifyListKeyCommand(AKey: Word; AKeyChar: Char;
  AShift: TShiftState): string;
var
  K: TKeyChord;
begin
  Result := '';
  K := TKeyChord.Make(AKey, AKeyChar, AShift);
  if (AKey = vkSpace) or (AKeyChar = ' ') then
    Exit('toggle');
  if K.MatchesAny(vkUp, [ssCtrl], [ssShift, ssAlt]) then
    Exit('up');
  if K.MatchesAny(vkDown, [ssCtrl], [ssShift, ssAlt]) then
    Exit('down');
  if AShift * [ssShift, ssCtrl, ssAlt] = [] then
    case AKey of
      vkDelete: Exit('delete');
      vkF2: Exit('f2');
      vkF4: Exit('f4');
      vkF5: Exit('f5');
    end;
end;

function IsListSelectionNavKey(AKey: Word): Boolean;
begin
  Result := (AKey = vkUp) or (AKey = vkDown) or (AKey = vkHome) or
    (AKey = vkEnd) or (AKey = vkPrior) or (AKey = vkNext);
end;

function ClassifyFocusedInputGuard(APassword, AReadOnly: Boolean;
  AKey: Word; AKeyChar: Char; AShift: TShiftState): string;
var
  K: TKeyChord;
begin
  Result := '';
  K := TKeyChord.Make(AKey, AKeyChar, AShift);
  if APassword and (K.MatchesAny(vkC, [ssCtrl], [ssShift, ssAlt]) or
     K.MatchesAny(vkX, [ssCtrl], [ssShift, ssAlt]) or
     K.MatchesAny(vkInsert, [ssCtrl], [ssShift, ssAlt])) then
    Exit('password-copy');
  if AReadOnly and (K.IsPrintable or (AKey = vkBack) or (AKey = vkDelete) or
     K.MatchesAny(vkX, [ssCtrl], [ssShift, ssAlt]) or
     K.MatchesAny(vkV, [ssCtrl], [ssShift, ssAlt]) or
     K.MatchesAny(vkInsert, [ssShift], [ssCtrl, ssAlt])) then
    Exit('readonly-edit');
end;

function ClassifyOpenDropDownKey(AKey: Word; AKeyChar: Char;
  AAcceptOrSpace, AIsHistoryInput: Boolean): TOpenDropDownKeyAction;
begin
  if AAcceptOrSpace then
    Exit(odkaCommit);
  if AKey = vkEscape then
    Exit(odkaClose);
  if (AKey = vkDelete) and AIsHistoryInput then
    Exit(odkaDeleteHistory);
  if AKey = vkTab then
    Exit(odkaTabAway);
  if (AKey = vkUp) or (AKey = vkDown) or (AKey = vkHome) or (AKey = vkEnd) or
     (AKey = vkPrior) or (AKey = vkNext) then
    Exit(odkaNavHover);
  Result := odkaSwallow;
end;

function ShouldOpenFocusedDropDown(AKey: Word; AKeyChar: Char;
  AShift: TShiftState): Boolean;
var
  K: TKeyChord;
begin
  K := TKeyChord.Make(AKey, AKeyChar, AShift);
  Result := (AKey = vkF4) or K.MatchesAny(vkDown, [ssAlt], [ssCtrl, ssShift]) or
    (AKey = vkSpace) or (AKeyChar = ' ');
end;

function IsMaskHistoryGroupSaveChord(AKey: Word; AShift: TShiftState;
  const AHistory: string): Boolean;
begin
  Result := (AKey = Ord('G')) and (ssCtrl in AShift) and not (ssAlt in AShift) and
    (SameText(AHistory, 'masks') or SameText(AHistory, 'findmask'));
end;

function DialogHandleOpenDropDownKeys(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  ViewH, Last, DropIdx: Integer;
  C: TDialogControl;
  Action: TOpenDropDownKeyAction;
begin
  DropIdx := Ops.DropOpenIndex();
  Result := DropIdx >= 0;
  if not Result then
    Exit;

  // Open DropDown: Enter commits, Esc collapses (does not cancel dialog).
  // Every key is consumed: one that fell through would accept or cancel the
  // dialog behind the popup.
  Action := ClassifyOpenDropDownKey(AKey, AKeyChar,
    Ops.NormalizeAcceptKey(AKey, AKeyChar) or (AKey = vkSpace) or (AKeyChar = ' '),
    Ops.IsHistoryInput(DropIdx));
  case Action of
    odkaCommit:
      begin
        Ops.CommitDropDown();
        AKey := 0;
        AKeyChar := #0;
      end;
    odkaClose:
      begin
        Ops.CloseDropDown();
        AKey := 0;
        AKeyChar := #0;
      end;
    odkaDeleteHistory:
      begin
        Ops.RemoveDropHoverFromHistory();
        AKey := 0;
        AKeyChar := #0;
      end;
    odkaTabAway:
      begin
        Ops.CloseDropDown();
        Ops.SetFocusIndex(Ops.NextFocusable(Ops.FocusIndex(), not (ssShift in AShift)));
        Ops.NotifyChanged();
        AKey := 0;
      end;
    odkaNavHover:
      begin
        C := Ops.GetControl(DropIdx);
        if Length(C.Items) > 0 then
        begin
          Last := High(C.Items);
          ViewH := Max(Ops.DropPopupViewHeight(), 1);
          Ops.SetDropHover(DropDownHoverAfterNavKey(Ops.DropHover(), Last, ViewH, AKey));
          Ops.EnsureDropHoverInView();
          Ops.NotifyChanged();
        end;
        AKey := 0;
      end;
  else
    AKey := 0;
    AKeyChar := #0;
  end;
end;

function DialogHandleDialogNavKeys(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
begin
  if Ops.NormalizeAcceptKey(AKey, AKeyChar) then
  begin
    Ops.FireAccept();
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;

  if AKey = vkEscape then
  begin
    Ops.FireCancel();
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;

  if AKey = vkTab then
  begin
    Ops.SetFocusIndex(Ops.NextFocusable(Ops.FocusIndex(), not (ssShift in AShift)));
    Ops.NotifyChanged();
    AKey := 0;
    Exit(True);
  end;

  Result := False;
end;

function DialogHandleClosedDropDownKeys(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  K: TKeyChord;
  GroupName: string;
  Focus: Integer;
  C: TDialogControl;
begin
  K := TKeyChord.Make(AKey, AKeyChar, AShift);
  Focus := Ops.FocusIndex();

  // History input: Ctrl+Down / Alt+Down drop the history down.
  if Ops.IsHistoryInput(Focus) and IsHistoryDropDownChord(K) then
  begin
    Ops.OpenDropDown(Focus);
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;

  // Mask field: Ctrl+G saves the masks as a group (named after the first mask)
  // and puts the reference @Name in the field.
  if (Focus >= 0) and (Focus < Ops.ControlCount()) then
  begin
    C := Ops.GetControl(Focus);
    if (C.Kind = dckInput) and
       IsMaskHistoryGroupSaveChord(AKey, AShift, C.History) then
    begin
      GroupName := MaskGroupSaveAuto(C.Edit.Text);
      if GroupName <> '' then
      begin
        InputLineSetText(C.Edit, '@' + GroupName);
        Ops.SetControl(Focus, C);
        Ops.NotifyChanged();
      end;
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
  end;

  // Open DropDown: Space / Alt+Down / F4. A DropDown key that is none of
  // these falls through, so arrows can still move its selection.
  if (Focus >= 0) and (Focus < Ops.ControlCount()) then
  begin
    C := Ops.GetControl(Focus);
    if (C.Kind = dckDropDown) and ShouldOpenFocusedDropDown(AKey, AKeyChar, AShift) then
    begin
      Ops.OpenDropDown(Focus);
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
  end;

  Result := False;
end;

function DialogHandleFocusedSpaceKey(const Ops: TDialogKeyOps; var AKey: Word;
  var AKeyChar: Char): Boolean;
var
  Focus: Integer;
  C: TDialogControl;
begin
  Focus := Ops.FocusIndex();
  if (Focus >= 0) and (Focus < Ops.ControlCount()) and
     ((AKey = vkSpace) or (AKeyChar = ' ')) then
  begin
    C := Ops.GetControl(Focus);
    if C.Kind = dckCheckbox then
    begin
      DialogToggleCheckbox(C);
      Ops.SetControl(Focus, C);
      Ops.NotifyChanged();
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
    if C.Kind = dckRadio then
    begin
      Ops.SelectRadio(Focus);
      Ops.NotifyChanged();
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
    if C.Kind = dckRadioGroup then
    begin
      // Space keeps current selection (already exclusive).
      Ops.NotifyChanged();
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
    if C.Kind = dckButton then
    begin
      Ops.PressButton(Focus);
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
  end;

  Result := False;
end;

function DialogHandleMnemonicKeys(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Ch: Char;
begin
  // Hot-keys run for Alt, and for any key while focus is not in an input.
  // A miss leaves the key alone: zeroing it here would swallow the letter a
  // list, picker or input still has to handle.
  if DialogMnemonicKeysActive(AShift, Ops.FocusedIsInput()) then
  begin
    case DialogYesNoAnswer(AKey, AKeyChar) of
      dyaYes:
        if Ops.TryYesNoButton(True) then
        begin
          AKey := 0;
          AKeyChar := #0;
          Exit(True);
        end;
      dyaNo:
        if Ops.TryYesNoButton(False) then
        begin
          AKey := 0;
          AKeyChar := #0;
          Exit(True);
        end;
    end;
    // Typed letter, layout alternate, then physical A..Z.
    for Ch in DialogMnemonicLetterCandidates(AKey, AKeyChar) do
      if Ops.TryMnemonic(Ch) then
      begin
        AKey := 0;
        AKeyChar := #0;
        Exit(True);
      end;
  end;

  Result := False;
end;

function DialogHandleHotKeyInput(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Focus: Integer;
  C: TDialogControl;
  Chord: string;
begin
  Focus := Ops.FocusIndex();
  if not ((Focus >= 0) and (Focus < Ops.ControlCount())) then
    Exit(False);
  C := Ops.GetControl(Focus);
  if not ((C.Kind = dckInput) and C.HotKey) then
    Exit(False);
  if HotKeyFieldIgnoresNavKey(AKey) then
    Exit(False);
  // Some hosts add a flag above the low byte (Alt+Shift+T arrives as $154);
  // the virtual key is the low byte.
  AKey := NormalizeDialogVirtualKey(AKey);
  case ClassifyHotKeyFieldKey(C.HotKeyMulti, C.Edit.Text, AKey, AKeyChar, AShift, Chord) of
    hkfaSwallow:
      begin
        AKey := 0;
        AKeyChar := #0;
        Exit(True);
      end;
    hkfaApply:
      begin
        InputLineSetText(C.Edit, Chord);
        InputLineSelectAll(C.Edit);
        Ops.SetControl(Focus, C);
        AKey := 0;
        AKeyChar := #0;
        Ops.NotifyChanged();
        Exit(True);
      end;
  end;
  Result := False;
end;

function DialogHandleFocusedPickerKeys(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Focus: Integer;
  C: TDialogControl;
begin
  Focus := Ops.FocusIndex();
  if (Focus < 0) or (Focus >= Ops.ControlCount()) then
    Exit(False);
  C := Ops.GetControl(Focus);
  if C.Kind = dckDatePicker then
  begin
    DatePickerHandleKey(C.Cal, AKey, AShift, AKeyChar);
    Ops.SetControl(Focus, C);
    AKey := 0;
    AKeyChar := #0;
    Ops.NotifyChanged();
    Exit(True);
  end;

  if C.Kind = dckColorPicker then
  begin
    ColorPickerHandleKey(C.Picker, AKey, AShift, AKeyChar);
    Ops.SetControl(Focus, C);
    AKey := 0;
    AKeyChar := #0;
    Ops.NotifyChanged();
    Exit(True);
  end;

  Result := False;
end;

function DialogHandleListCommandKeys(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  KeyCmd: string;
  BtnIdx, Focus: Integer;
  C: TDialogControl;
begin
  Focus := Ops.FocusIndex();

  if (Focus >= 0) and (Focus < Ops.ControlCount()) then
  begin
    C := Ops.GetControl(Focus);
    if (C.Kind = dckList) and C.KeyCommands then
    begin
      KeyCmd := ClassifyListKeyCommand(AKey, AKeyChar, AShift);
      if KeyCmd <> '' then
      begin
        AKey := 0;
        AKeyChar := #0;
        Ops.FireCommand(KeyCmd);
        Exit(True);
      end;
    end;

    // Del in a list does what the dialog's Delete button does. Without that
    // button the key is left unchanged.
    if (C.Kind = dckList) and (AKey = vkDelete) and
       (AShift * [ssShift, ssCtrl, ssAlt] = []) then
    begin
      BtnIdx := Ops.ButtonIndexById(cDlgCmdDelete);
      if BtnIdx >= 0 then
      begin
        AKey := 0;
        AKeyChar := #0;
        Ops.PressButton(BtnIdx);
        Exit(True);
      end;
    end;
  end;

  Result := False;
end;

function DialogHandleListNavKeys(const Ops: TDialogKeyOps; var AKey: Word): Boolean;
var
  Focus: Integer;
  C: TDialogControl;
begin
  Focus := Ops.FocusIndex();
  if (Focus >= 0) and (Focus < Ops.ControlCount()) then
  begin
    C := Ops.GetControl(Focus);
    if (C.Kind in [dckList, dckRadioGroup, dckDropDown]) and
       IsListSelectionNavKey(AKey) then
    begin
      if Length(C.Items) > 0 then
      begin
        Ops.SetListSelectedIndex(Focus,
          ListSelectedIndexAfterNavKey(C.SelectedIndex, High(C.Items),
            Ops.ListViewHeight(Focus), AKey, C.Kind = dckList));
        Ops.NotifyChanged();
      end;
      AKey := 0;
      Exit(True);
    end;
  end;

  Result := False;
end;

function DialogHandleFocusedInputKeys(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Focus: Integer;
  C: TDialogControl;
  LineRes: TInputLineResult;
  Guard: string;
begin
  if not Ops.FocusedIsInput() then
    Exit(False);

  Focus := Ops.FocusIndex();
  // Copy/writeback: dynarray-of-record field as var can drop edits otherwise.
  C := Ops.GetControl(Focus);
  Guard := ClassifyFocusedInputGuard(C.Password, C.ReadOnly, AKey, AKeyChar, AShift);
  if Guard <> '' then
  begin
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  LineRes := InputLineHandleInput(C.Edit, AKey, AShift, AKeyChar);
  Ops.SetControl(Focus, C);
  case LineRes of
    ilrSubmit:
      Ops.FireAccept();
    ilrCancel:
      Ops.FireCommand(cDlgCmdCancel);
  else
    Ops.NotifyChanged();
  end;
  Result := True;
end;

function DialogHandleFocusArrowKeys(const Ops: TDialogKeyOps; var AKey: Word): Boolean;
begin
  if (AKey = vkLeft) or (AKey = vkRight) or (AKey = vkUp) or (AKey = vkDown) then
  begin
    Ops.SetFocusIndex(Ops.NextFocusable(Ops.FocusIndex(),
      (AKey = vkRight) or (AKey = vkDown)));
    Ops.NotifyChanged();
    AKey := 0;
    Exit(True);
  end;
  Result := False;
end;

function DialogHandleInputCore(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
begin
  Result := False;
  if not Ops.Visible() then
    Exit;

  if not Ops.CursorVisible() then
    Ops.ShowCursor();

  Result := True;

  if DialogHandleHotKeyInput(Ops, AKey, AShift, AKeyChar) then
    Exit;
  if DialogHandleOpenDropDownKeys(Ops, AKey, AShift, AKeyChar) then
    Exit;
  if DialogHandleDialogNavKeys(Ops, AKey, AShift, AKeyChar) then
    Exit;
  if DialogHandleClosedDropDownKeys(Ops, AKey, AShift, AKeyChar) then
    Exit;
  if DialogHandleFocusedSpaceKey(Ops, AKey, AKeyChar) then
    Exit;
  if DialogHandleMnemonicKeys(Ops, AKey, AShift, AKeyChar) then
    Exit;
  if DialogHandleFocusedPickerKeys(Ops, AKey, AShift, AKeyChar) then
    Exit;
  if DialogHandleListCommandKeys(Ops, AKey, AShift, AKeyChar) then
    Exit;
  if DialogHandleListNavKeys(Ops, AKey) then
    Exit;
  if DialogHandleFocusedInputKeys(Ops, AKey, AShift, AKeyChar) then
    Exit;
  if DialogHandleFocusArrowKeys(Ops, AKey) then
    Exit;

  // A key no control took is still consumed, so the window under the dialog
  // does not see it.
  AKey := 0;
  AKeyChar := #0;
end;

end.
