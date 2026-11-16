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

/// <summary>Multi-chord hotkey field text after one keystroke.</summary>
function HotKeyMultiText(const ACurrent: string; AKey: Word; AKeyChar: Char;
  AShift: TShiftState): string;

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

function HotKeyMultiText(const ACurrent: string; AKey: Word; AKeyChar: Char;
  AShift: TShiftState): string;
var
  Parts: TArray<string>;
  Chord, P: string;
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
    begin
      Result := '';
      for I := 0 to High(Parts) - 1 do
        if Parts[I] <> '' then
        begin
          if Result <> '' then
            Result := Result + '; ';
          Result := Result + Parts[I];
        end;
      Exit;
    end;
  end;
  Chord := KeystrokeBindingText(AKey, AKeyChar, AShift);
  if Chord = '' then
    Exit(ACurrent);
  for P in Parts do
    if SameText(P, Chord) then
      Exit(ACurrent);
  if Trim(ACurrent) = '' then
    Result := Chord
  else
    Result := Trim(ACurrent) + '; ' + Chord;
end;

function DialogHandleOpenDropDownKeys(const Ops: TDialogKeyOps; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  ViewH, Last, DropIdx: Integer;
  C: TDialogControl;
begin
  DropIdx := Ops.DropOpenIndex();
  Result := DropIdx >= 0;
  if not Result then
    Exit;

  // Open DropDown: Enter commits, Esc collapses (does not cancel dialog).
  // Every key is consumed: one that fell through would accept or cancel the
  // dialog behind the popup.
  if Ops.NormalizeAcceptKey(AKey, AKeyChar) or (AKey = vkSpace) or (AKeyChar = ' ') then
  begin
    Ops.CommitDropDown();
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  if AKey = vkEscape then
  begin
    Ops.CloseDropDown();
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  // History list: Del forgets the highlighted entry.
  if (AKey = vkDelete) and Ops.IsHistoryInput(DropIdx) then
  begin
    Ops.RemoveDropHoverFromHistory();
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  if AKey = vkTab then
  begin
    Ops.CloseDropDown();
    Ops.SetFocusIndex(Ops.NextFocusable(Ops.FocusIndex(), not (ssShift in AShift)));
    Ops.NotifyChanged();
    AKey := 0;
    Exit;
  end;
  if (AKey = vkUp) or (AKey = vkDown) or (AKey = vkHome) or (AKey = vkEnd) or
     (AKey = vkPrior) or (AKey = vkNext) then
  begin
    C := Ops.GetControl(DropIdx);
    if Length(C.Items) > 0 then
    begin
      Last := High(C.Items);
      ViewH := Max(Ops.DropPopupViewHeight(), 1);
      if AKey = vkUp then
        Ops.SetDropHover(EnsureRange(Ops.DropHover() - 1, 0, Last))
      else if AKey = vkDown then
        Ops.SetDropHover(EnsureRange(Ops.DropHover() + 1, 0, Last))
      else if AKey = vkHome then
        Ops.SetDropHover(0)
      else if AKey = vkEnd then
        Ops.SetDropHover(Last)
      else if AKey = vkPrior then
        Ops.SetDropHover(EnsureRange(Ops.DropHover() - ViewH, 0, Last))
      else
        Ops.SetDropHover(EnsureRange(Ops.DropHover() + ViewH, 0, Last));
      Ops.EnsureDropHoverInView();
      Ops.NotifyChanged();
    end;
    AKey := 0;
    Exit;
  end;
  AKey := 0;
  AKeyChar := #0;
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
  if (AKey = Ord('G')) and (ssCtrl in AShift) and not (ssAlt in AShift) and
     (Focus >= 0) and (Focus < Ops.ControlCount()) then
  begin
    C := Ops.GetControl(Focus);
    if (C.Kind = dckInput) and
       (SameText(C.History, 'masks') or SameText(C.History, 'findmask')) then
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
    if C.Kind = dckDropDown then
    begin
      if (AKey = vkF4) or K.MatchesAny(vkDown, [ssAlt], [ssCtrl, ssShift]) or
         (AKey = vkSpace) or (AKeyChar = ' ') then
      begin
        Ops.OpenDropDown(Focus);
        AKey := 0;
        AKeyChar := #0;
        Exit(True);
      end;
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
  if (ssAlt in AShift) or not Ops.FocusedIsInput() then
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
    // A hotkey matches the typed letter first (any script: &Удалить takes
    // у), then the same key on the other layout (the Latin e on the У key
    // takes &Удалить), then the physical key, so Latin hotkeys also work
    // from a layout other than JCUKEN.
    Ch := #0;
    if AKeyChar.IsLetter then
      Ch := AKeyChar.ToUpper;
    if (Ch <> #0) and (Ops.TryMnemonic(Ch) or
       Ops.TryMnemonic(TextKeyLayoutAlternate(AKeyChar).ToUpper)) then
    begin
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
    if (AKey >= vkA) and (AKey <= vkZ) and (Char(AKey) <> Ch) and Ops.TryMnemonic(Char(AKey)) then
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
  if (AKey = vkEscape) or (AKey = vkTab) or (AKey = vkReturn) then
    Exit(False);
  // Some hosts add a flag above the low byte (Alt+Shift+T arrives as $154);
  // the virtual key is the low byte.
  if AKey > $FF then
    AKey := AKey and $FF;
  if C.HotKeyMulti then
  begin
    Chord := HotKeyMultiText(C.Edit.Text, AKey, AKeyChar, AShift);
    if Chord = C.Edit.Text then
    begin
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
  end
  else if (AShift * [ssShift, ssCtrl, ssAlt] = []) and ((AKey = vkBack) or (AKey = vkDelete)) then
    Chord := ''
  else
  begin
    Chord := InputChordText(AKey, AKeyChar, AShift);
    // A bare modifier names no key yet; the field keeps its value.
    if Chord = '' then
    begin
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
  end;
  InputLineSetText(C.Edit, Chord);
  InputLineSelectAll(C.Edit);
  Ops.SetControl(Focus, C);
  AKey := 0;
  AKeyChar := #0;
  Ops.NotifyChanged();
  Result := True;
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
  K: TKeyChord;
  KeyCmd: string;
  BtnIdx, Focus: Integer;
  C: TDialogControl;
begin
  K := TKeyChord.Make(AKey, AKeyChar, AShift);
  Focus := Ops.FocusIndex();

  if (Focus >= 0) and (Focus < Ops.ControlCount()) then
  begin
    C := Ops.GetControl(Focus);
    if (C.Kind = dckList) and C.KeyCommands then
    begin
      KeyCmd := '';
      if (AKey = vkSpace) or (AKeyChar = ' ') then
        KeyCmd := 'toggle'
      else if K.MatchesAny(vkUp, [ssCtrl], [ssShift, ssAlt]) then
        KeyCmd := 'up'
      else if K.MatchesAny(vkDown, [ssCtrl], [ssShift, ssAlt]) then
        KeyCmd := 'down'
      else if AShift * [ssShift, ssCtrl, ssAlt] = [] then
        case AKey of
          vkDelete: KeyCmd := 'delete';
          vkF2: KeyCmd := 'f2';
          vkF4: KeyCmd := 'f4';
          vkF5: KeyCmd := 'f5';
        end;
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
       ((AKey = vkUp) or (AKey = vkDown) or (AKey = vkHome) or (AKey = vkEnd) or
        (AKey = vkPrior) or (AKey = vkNext)) then
    begin
      if Length(C.Items) > 0 then
      begin
        if AKey = vkUp then
          Ops.SetListSelectedIndex(Focus, C.SelectedIndex - 1)
        else if AKey = vkDown then
          Ops.SetListSelectedIndex(Focus, C.SelectedIndex + 1)
        else if AKey = vkHome then
          Ops.SetListSelectedIndex(Focus, 0)
        else if AKey = vkEnd then
          Ops.SetListSelectedIndex(Focus, High(C.Items))
        else if (AKey = vkPrior) and (C.Kind = dckList) then
          Ops.SetListSelectedIndex(Focus,
            C.SelectedIndex - Max(Ops.ListViewHeight(Focus), 1))
        else if (AKey = vkNext) and (C.Kind = dckList) then
          Ops.SetListSelectedIndex(Focus,
            C.SelectedIndex + Max(Ops.ListViewHeight(Focus), 1))
        else if AKey = vkPrior then
          Ops.SetListSelectedIndex(Focus, C.SelectedIndex - 1)
        else
          Ops.SetListSelectedIndex(Focus, C.SelectedIndex + 1);
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
  K: TKeyChord;
begin
  if not Ops.FocusedIsInput() then
    Exit(False);

  Focus := Ops.FocusIndex();
  K := TKeyChord.Make(AKey, AKeyChar, AShift);
  // Copy/writeback: dynarray-of-record field as var can drop edits otherwise.
  C := Ops.GetControl(Focus);
  // Password inputs: no Ctrl+C / Ctrl+X / Ctrl+Insert copy-out.
  if C.Password and (K.MatchesAny(vkC, [ssCtrl], [ssShift, ssAlt]) or
     K.MatchesAny(vkX, [ssCtrl], [ssShift, ssAlt]) or
     K.MatchesAny(vkInsert, [ssCtrl], [ssShift, ssAlt])) then
  begin
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  // Read-only inputs: moving, selecting and copying only.
  if C.ReadOnly and (K.IsPrintable or (AKey = vkBack) or (AKey = vkDelete) or
     K.MatchesAny(vkX, [ssCtrl], [ssShift, ssAlt]) or
     K.MatchesAny(vkV, [ssCtrl], [ssShift, ssAlt]) or
     K.MatchesAny(vkInsert, [ssShift], [ssCtrl, ssAlt])) then
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
