unit uEditorInput;

{ Editor/Viewer key dispatch extracted from TEditorWindow.HandleInput.
  Host stays a thin facade: dialog/find-prompt routing stays on the window;
  this unit owns the keymap table and consume-key contract. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes;

type
  TEditorProc = procedure of object;
  TEditorBoolFn = function: Boolean of object;
  TEditorExtendProc = procedure(AExtendSel: Boolean) of object;
  TEditorFindProc = procedure(AForward: Boolean) of object;
  TEditorMoveProc = procedure(ARowDelta, AColDelta: Integer;
    AExtendSel: Boolean) of object;
  TEditorWordProc = procedure(AForward, AExtendSel: Boolean) of object;
  TEditorCharProc = procedure(ACh: Char) of object;

  TEditorKeymapHost = record
    CanEdit: TEditorBoolFn;
    ViewOnly: TEditorBoolFn;
    MarkdownMode: TEditorBoolFn;
    FindNeedleEmpty: TEditorBoolFn;
    ToggleViewMode: TEditorProc;
    ToggleHexMode: TEditorProc;
    ToggleMarkdownMode: TEditorProc;
    OpenEncodingDialog: TEditorProc;
    CycleEncoding: TEditorProc;
    OpenGotoDialog: TEditorProc;
    OpenReplaceDialog: TEditorProc;
    OpenFindPrompt: TEditorProc;
    FindNextOrPrev: TEditorFindProc;
    SaveDoc: TEditorProc;
    ToggleWordWrap: TEditorProc;
    CopySelectionOrLine: TEditorProc;
    PasteText: TEditorProc;
    CutSelectionOrLine: TEditorProc;
    SelectAll: TEditorProc;
    ClearSelection: TEditorProc;
    NotifyHost: TEditorProc;
    UndoEdit: TEditorProc;
    RedoEdit: TEditorProc;
    DeleteCurrentLine: TEditorProc;
    DeleteToEndOfLine: TEditorProc;
    InsertBlankLineBelow: TEditorProc;
    MoveWord: TEditorWordProc;
    MoveCursor: TEditorMoveProc;
    BreakInsertCoalesce: TEditorProc;
    GotoFileHome: TEditorExtendProc;
    GotoFileEnd: TEditorExtendProc;
    GotoLineHome: TEditorExtendProc;
    GotoLineEnd: TEditorExtendProc;
    RequestClose: TEditorProc;
    DoBackspace: TEditorProc;
    DoDelete: TEditorProc;
    DoEnter: TEditorProc;
    InsertChar: TEditorCharProc;
  end;

function DispatchEditorKeys(const AHost: TEditorKeymapHost; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char; AViewH: Integer): Boolean;

implementation

procedure ConsumeKey(var AKey: Word; var AKeyChar: Char; AClearChar: Boolean);
begin
  AKey := 0;
  if AClearChar then
    AKeyChar := #0;
end;

function HostCanEdit(const AHost: TEditorKeymapHost): Boolean;
begin
  Result := Assigned(AHost.CanEdit) and AHost.CanEdit();
end;

function HostViewOnly(const AHost: TEditorKeymapHost): Boolean;
begin
  Result := Assigned(AHost.ViewOnly) and AHost.ViewOnly();
end;

function HostMarkdownMode(const AHost: TEditorKeymapHost): Boolean;
begin
  Result := Assigned(AHost.MarkdownMode) and AHost.MarkdownMode();
end;

function HostFindEmpty(const AHost: TEditorKeymapHost): Boolean;
begin
  Result := Assigned(AHost.FindNeedleEmpty) and AHost.FindNeedleEmpty();
end;

{ ---- Dispatch helpers -------------------------------------------------------

  DispatchEditorKeys tries the key groups below in a fixed order; the first
  group that claims the key wins, so the order is part of the keymap (e.g.
  Ctrl+H is Hex before it could be Replace, Ctrl+F7 is Replace before Find). }

type
  TKeyOutcome = (
    koPass,      // not this group's key: try the next group
    koHandled,   // action run, key consumed
    koRejected   // this group's key, but nothing to do here: report unhandled
  );

function Mods(AShift: TShiftState): TShiftState; inline;
begin
  Result := AShift * [ssShift, ssCtrl, ssAlt];
end;

function CtrlNoAlt(AShift: TShiftState): Boolean; inline;
begin
  Result := (ssCtrl in AShift) and not (ssAlt in AShift);
end;

/// <summary>Key is the uppercase letter AUpper by virtual key code. Letter
/// virtual keys are always uppercase; Ord(lowercase) is a different key
/// (Ord('s') = vkF4, Ord('k') = vkAdd), so it must not match.</summary>
function IsLetterVk(AKey: Word; AUpper: Char): Boolean; inline;
begin
  Result := AKey = Ord(AUpper);
end;

/// <summary>IsLetterVk, or the typed character is AUpper in either case.</summary>
function IsLetter(AKey: Word; AKeyChar, AUpper: Char): Boolean; inline;
begin
  Result := IsLetterVk(AKey, AUpper) or
    (AKeyChar = AUpper) or (Ord(AKeyChar) = Ord(AUpper) + 32);
end;

function Handled(var AKey: Word; var AKeyChar: Char;
  AClearChar: Boolean): TKeyOutcome;
begin
  ConsumeKey(AKey, AKeyChar, AClearChar);
  Result := koHandled;
end;

/// <summary>F7-family "find again": opens the prompt while there is no needle.</summary>
procedure FindAgain(const AHost: TEditorKeymapHost; AForward: Boolean);
begin
  if HostFindEmpty(AHost) then
    AHost.OpenFindPrompt()
  else
    AHost.FindNextOrPrev(AForward);
end;

{ F6 view/edit, F4 / Ctrl+H hex, Ctrl+M markdown. }
function TryModeKeys(const AHost: TEditorKeymapHost; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): TKeyOutcome;
begin
  Result := koPass;
  // F6 — Viewer ↔ Editor
  if (AKey = vkF6) and (Mods(AShift) = []) then
  begin
    AHost.ToggleViewMode();
    Exit(Handled(AKey, AKeyChar, False));
  end;

  // F4 — Hex in text/hex Viewer; Raw (render ↔ source) while Markdown is on.
  // Ctrl+H is always Hex, including Markdown (F-bar Ctrl+H:Hex / Ctrl+M:Raw).
  if (AKey = vkF4) and (Mods(AShift) = []) then
  begin
    if HostMarkdownMode(AHost) then
      AHost.ToggleMarkdownMode()
    else
      AHost.ToggleHexMode();
    Exit(Handled(AKey, AKeyChar, True));
  end;
  if CtrlNoAlt(AShift) and IsLetterVk(AKey, 'H') then
  begin
    AHost.ToggleHexMode();
    Exit(Handled(AKey, AKeyChar, True));
  end;

  // Ctrl+M — Markdown render ↔ raw text. Do not match Ord('m'): that is
  // vkSubtract, so Ctrl+- (zoom out) looked like this chord.
  if (Mods(AShift) = [ssCtrl]) and
     ((AKey = vkM) or (AKeyChar = 'm') or (AKeyChar = 'M')) then
  begin
    AHost.ToggleMarkdownMode();
    Exit(Handled(AKey, AKeyChar, True));
  end;
end;

{ F8 / Shift+F8 encoding, Alt+F8 goto line. }
function TryEncodingKeys(const AHost: TEditorKeymapHost; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): TKeyOutcome;
begin
  Result := koPass;
  if AKey <> vkF8 then
    Exit;
  // F8 / Shift+F8 — encoding (also exits Hex via re-decode)
  if not (ssCtrl in AShift) and not (ssAlt in AShift) then
  begin
    if ssShift in AShift then
      AHost.OpenEncodingDialog()
    else
      AHost.CycleEncoding();
    Exit(Handled(AKey, AKeyChar, False));
  end;
  // Alt+F8 — goto line
  if (ssAlt in AShift) and not (ssCtrl in AShift) then
  begin
    AHost.OpenGotoDialog();
    Exit(Handled(AKey, AKeyChar, False));
  end;
end;

{ Ctrl+F7 replace, Shift/Alt+F7 find next/previous, Ctrl+F / F7 / '/' find
  prompt, F3 / Shift+F3 find again. }
function TrySearchKeys(const AHost: TEditorKeymapHost; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): TKeyOutcome;
begin
  Result := koPass;
  // Ctrl+F7 — replace (Editor only). Ctrl+H would be too, but TryModeKeys
  // already took it for Hex.
  if (AKey = vkF7) and CtrlNoAlt(AShift) and HostCanEdit(AHost) then
  begin
    AHost.OpenReplaceDialog();
    Exit(Handled(AKey, AKeyChar, True));
  end;

  // Shift+F7 / Alt+F7 — find next / previous
  if (AKey = vkF7) and (Mods(AShift) = [ssShift]) then
  begin
    FindAgain(AHost, True);
    Exit(Handled(AKey, AKeyChar, False));
  end;
  if (AKey = vkF7) and (ssAlt in AShift) and not (ssCtrl in AShift) then
  begin
    FindAgain(AHost, False);
    Exit(Handled(AKey, AKeyChar, False));
  end;

  // Ctrl+F / F7 — Find prompt. '/' opens find in ViewOnly; in edit mode '/'
  // is a normal character.
  if (CtrlNoAlt(AShift) and IsLetterVk(AKey, 'F')) or (AKey = vkF7) or
     ((AKeyChar = '/') and not (ssCtrl in AShift) and
      not (ssAlt in AShift) and not HostCanEdit(AHost)) then
    if (AKey = vkF7) or HostViewOnly(AHost) or (ssCtrl in AShift) then
    begin
      AHost.OpenFindPrompt();
      Exit(Handled(AKey, AKeyChar, True));
    end;

  if AKey = vkF3 then
  begin
    FindAgain(AHost, not (ssShift in AShift));
    Exit(Handled(AKey, AKeyChar, False));
  end;
end;

{ F2 save (Editor) / word wrap (Viewer), Ctrl+S save. }
function TrySaveKeys(const AHost: TEditorKeymapHost; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): TKeyOutcome;
begin
  Result := koPass;
  if (AKey = vkF2) and (Mods(AShift) = []) then
  begin
    if HostCanEdit(AHost) then
      AHost.SaveDoc()
    else if HostViewOnly(AHost) and not HostMarkdownMode(AHost) then
      AHost.ToggleWordWrap()
    else
      Exit(koRejected);
    Exit(Handled(AKey, AKeyChar, True));
  end;

  if HostCanEdit(AHost) and (ssCtrl in AShift) and IsLetter(AKey, AKeyChar, 'S') then
  begin
    AHost.SaveDoc();
    Exit(Handled(AKey, AKeyChar, True));
  end;
end;

{ Extra-keyboard clipboard keys: Ctrl+Insert copy, Shift+Insert paste,
  Ctrl+Delete / Shift+Delete cut — same actions as Ctrl+C/V/X. }
function TryClipboardKeys(const AHost: TEditorKeymapHost; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): TKeyOutcome;
var
  M: TShiftState;
begin
  Result := koPass;
  M := Mods(AShift);
  if (AKey = vkInsert) and (M = [ssCtrl]) then
    AHost.CopySelectionOrLine()
  else if (AKey = vkInsert) and (M = [ssShift]) and HostCanEdit(AHost) then
    AHost.PasteText()
  else if (AKey = vkDelete) and ((M = [ssCtrl]) or (M = [ssShift])) and
          HostCanEdit(AHost) then
    AHost.CutSelectionOrLine()
  else
    Exit;
  Result := Handled(AKey, AKeyChar, True);
end;

{ Ctrl (no Alt) letter chords, Ctrl+Left/Right word moves, Ctrl+Home/End. }
function TryCtrlKeys(const AHost: TEditorKeymapHost; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): TKeyOutcome;
var
  CanEdit: Boolean;
begin
  Result := koPass;
  if not CtrlNoAlt(AShift) then
    Exit;
  CanEdit := HostCanEdit(AHost);

  if IsLetter(AKey, AKeyChar, 'A') then
    AHost.SelectAll()
  else if IsLetter(AKey, AKeyChar, 'C') then
    AHost.CopySelectionOrLine()
  else if IsLetter(AKey, AKeyChar, 'U') then
  begin
    AHost.ClearSelection();
    AHost.NotifyHost();
  end
  else if CanEdit and IsLetter(AKey, AKeyChar, 'X') then
    AHost.CutSelectionOrLine()
  else if CanEdit and IsLetter(AKey, AKeyChar, 'V') then
    AHost.PasteText()
  else if CanEdit and IsLetter(AKey, AKeyChar, 'Z') then
  begin
    if ssShift in AShift then
      AHost.RedoEdit()
    else
      AHost.UndoEdit();
  end
  // Far: Ctrl+Y / Ctrl+D = delete line (Redo is Ctrl+Shift+Z only).
  else if CanEdit and (IsLetter(AKey, AKeyChar, 'Y') or IsLetter(AKey, AKeyChar, 'D')) then
    AHost.DeleteCurrentLine()
  else if CanEdit and IsLetter(AKey, AKeyChar, 'K') then
    AHost.DeleteToEndOfLine()
  else if CanEdit and not (ssShift in AShift) and IsLetter(AKey, AKeyChar, 'N') then
    AHost.InsertBlankLineBelow()
  else
  begin
    case AKey of
      vkLeft, vkRight:
        AHost.MoveWord(AKey = vkRight, ssShift in AShift);
      vkHome:
        AHost.GotoFileHome(ssShift in AShift);
      vkEnd:
        AHost.GotoFileEnd(ssShift in AShift);
    else
      Exit;
    end;
    Exit(Handled(AKey, AKeyChar, False));
  end;
  Result := Handled(AKey, AKeyChar, True);
end;

{ Unmodified navigation / editing keys and typed characters. }
function TryBasicKeys(const AHost: TEditorKeymapHost; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char; AViewH: Integer): TKeyOutcome;
var
  Extend: Boolean;
begin
  // Viewer: numpad 5 = F10 (close).
  if HostViewOnly(AHost) and (Mods(AShift) = []) and
     ((AKey = vkNumpad5) or (AKey = vkClear)) then
  begin
    AHost.RequestClose();
    Exit(Handled(AKey, AKeyChar, True));
  end;

  Extend := ssShift in AShift;
  case AKey of
    vkEscape, vkF10: AHost.RequestClose();
    vkUp:            AHost.MoveCursor(-1, 0, Extend);
    vkDown:          AHost.MoveCursor(1, 0, Extend);
    vkLeft:          AHost.MoveCursor(0, -1, Extend);
    vkRight:         AHost.MoveCursor(0, 1, Extend);
    vkPrior:
      begin
        AHost.BreakInsertCoalesce();
        AHost.MoveCursor(-AViewH, 0, Extend);
      end;
    vkNext:
      begin
        AHost.BreakInsertCoalesce();
        AHost.MoveCursor(AViewH, 0, Extend);
      end;
    vkHome:          AHost.GotoLineHome(Extend);
    vkEnd:           AHost.GotoLineEnd(Extend);
    vkBack:          AHost.DoBackspace();
    vkDelete:        AHost.DoDelete();
    vkReturn:        AHost.DoEnter();
  else
    if (AKeyChar >= ' ') and (Ord(AKeyChar) <> 127) and
       not (ssCtrl in AShift) and not (ssAlt in AShift) then
      AHost.InsertChar(AKeyChar)
    else if HostViewOnly(AHost) and (AKeyChar = '/') then
      AHost.OpenFindPrompt()
    else
      Exit(koPass);
    Exit(Handled(AKey, AKeyChar, True));
  end;
  Result := Handled(AKey, AKeyChar, False);
end;

function DispatchEditorKeys(const AHost: TEditorKeymapHost; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char; AViewH: Integer): Boolean;
var
  R: TKeyOutcome;
begin
  R := TryModeKeys(AHost, AKey, AShift, AKeyChar);
  if R = koPass then
    R := TryEncodingKeys(AHost, AKey, AShift, AKeyChar);
  if R = koPass then
    R := TrySearchKeys(AHost, AKey, AShift, AKeyChar);
  if R = koPass then
    R := TrySaveKeys(AHost, AKey, AShift, AKeyChar);
  if R = koPass then
    R := TryClipboardKeys(AHost, AKey, AShift, AKeyChar);
  if R = koPass then
    R := TryCtrlKeys(AHost, AKey, AShift, AKeyChar);
  if R = koPass then
    R := TryBasicKeys(AHost, AKey, AShift, AKeyChar, AViewH);
  Result := R = koHandled;
end;

end.
