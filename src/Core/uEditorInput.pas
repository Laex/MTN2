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

uses
  uKeyChord;

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
  Ctrl+H is Hex before it could be Replace, Ctrl+F7 is Replace before Find).
  Each group gets the keystroke as K and consumes it through AKey/AKeyChar. }

type
  TKeyOutcome = (
    koPass,      // not this group's key: try the next group
    koHandled,   // action run, key consumed
    koRejected   // this group's key, but nothing to do here: report unhandled
  );

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
function TryModeKeys(const AHost: TEditorKeymapHost; const K: TKeyChord;
  var AKey: Word; var AKeyChar: Char): TKeyOutcome;
begin
  Result := koPass;
  // F6 — Viewer ↔ Editor
  if K.Matches(vkF6) then
  begin
    AHost.ToggleViewMode();
    Exit(Handled(AKey, AKeyChar, False));
  end;

  // F4 — Hex in text/hex Viewer; Raw (render ↔ source) while Markdown is on.
  // Ctrl+H is always Hex, including Markdown (F-bar Ctrl+H:Hex / Ctrl+M:Raw).
  if K.Matches(vkF4) then
  begin
    if HostMarkdownMode(AHost) then
      AHost.ToggleMarkdownMode()
    else
      AHost.ToggleHexMode();
    Exit(Handled(AKey, AKeyChar, True));
  end;
  if K.MatchesAny(vkH, [ssCtrl], [ssShift]) then
  begin
    AHost.ToggleHexMode();
    Exit(Handled(AKey, AKeyChar, True));
  end;

  // Ctrl+M — Markdown render ↔ raw text.
  if K.MatchesLetter('M', [ssCtrl]) then
  begin
    AHost.ToggleMarkdownMode();
    Exit(Handled(AKey, AKeyChar, True));
  end;
end;

{ F8 / Shift+F8 encoding, Alt+F8 goto line. }
function TryEncodingKeys(const AHost: TEditorKeymapHost; const K: TKeyChord;
  var AKey: Word; var AKeyChar: Char): TKeyOutcome;
begin
  Result := koPass;
  // F8 / Shift+F8 — encoding (also exits Hex via re-decode)
  if K.MatchesAny(vkF8, [], [ssShift]) then
  begin
    if ssShift in K.Mods then
      AHost.OpenEncodingDialog()
    else
      AHost.CycleEncoding();
    Exit(Handled(AKey, AKeyChar, False));
  end;
  // Alt+F8 — goto line
  if K.MatchesAny(vkF8, [ssAlt], [ssShift]) then
  begin
    AHost.OpenGotoDialog();
    Exit(Handled(AKey, AKeyChar, False));
  end;
end;

{ Ctrl+F7 replace, Shift/Alt+F7 find next/previous, Ctrl+F / F7 / '/' find
  prompt, F3 / Shift+F3 find again. }
function TrySearchKeys(const AHost: TEditorKeymapHost; const K: TKeyChord;
  var AKey: Word; var AKeyChar: Char): TKeyOutcome;
begin
  Result := koPass;
  // Ctrl+F7 — replace (Editor only). Ctrl+H would be too, but TryModeKeys
  // already took it for Hex.
  if K.MatchesAny(vkF7, [ssCtrl], [ssShift]) and HostCanEdit(AHost) then
  begin
    AHost.OpenReplaceDialog();
    Exit(Handled(AKey, AKeyChar, True));
  end;

  // Shift+F7 / Alt+F7 — find next / previous
  if K.Matches(vkF7, [ssShift]) then
  begin
    FindAgain(AHost, True);
    Exit(Handled(AKey, AKeyChar, False));
  end;
  if K.MatchesAny(vkF7, [ssAlt], [ssShift]) then
  begin
    FindAgain(AHost, False);
    Exit(Handled(AKey, AKeyChar, False));
  end;

  // Ctrl+F / F7 — Find prompt. '/' opens find in ViewOnly; in edit mode '/'
  // is a normal character.
  if K.MatchesAny(vkF, [ssCtrl], [ssShift]) or (K.Key = vkF7) or
     ((K.Ch = '/') and K.HasMods([], [ssShift]) and not HostCanEdit(AHost)) then
    if (K.Key = vkF7) or HostViewOnly(AHost) or (ssCtrl in K.Mods) then
    begin
      AHost.OpenFindPrompt();
      Exit(Handled(AKey, AKeyChar, True));
    end;

  if K.Key = vkF3 then
  begin
    FindAgain(AHost, not (ssShift in K.Mods));
    Exit(Handled(AKey, AKeyChar, False));
  end;
end;

{ F2 save (Editor) / word wrap (Viewer), Ctrl+S save. }
function TrySaveKeys(const AHost: TEditorKeymapHost; const K: TKeyChord;
  var AKey: Word; var AKeyChar: Char): TKeyOutcome;
begin
  Result := koPass;
  if K.Matches(vkF2) then
  begin
    if HostCanEdit(AHost) then
      AHost.SaveDoc()
    else if HostViewOnly(AHost) and not HostMarkdownMode(AHost) then
      AHost.ToggleWordWrap()
    else
      Exit(koRejected);
    Exit(Handled(AKey, AKeyChar, True));
  end;

  if HostCanEdit(AHost) and K.MatchesLetter('S', [ssCtrl], [ssShift, ssAlt]) then
  begin
    AHost.SaveDoc();
    Exit(Handled(AKey, AKeyChar, True));
  end;
end;

{ Extra-keyboard clipboard keys: Ctrl+Insert copy, Shift+Insert paste,
  Ctrl+Delete / Shift+Delete cut — same actions as Ctrl+C/V/X. }
function TryClipboardKeys(const AHost: TEditorKeymapHost; const K: TKeyChord;
  var AKey: Word; var AKeyChar: Char): TKeyOutcome;
begin
  Result := koPass;
  if K.Matches(vkInsert, [ssCtrl]) then
    AHost.CopySelectionOrLine()
  else if K.Matches(vkInsert, [ssShift]) and HostCanEdit(AHost) then
    AHost.PasteText()
  else if (K.Matches(vkDelete, [ssCtrl]) or K.Matches(vkDelete, [ssShift])) and
          HostCanEdit(AHost) then
    AHost.CutSelectionOrLine()
  else
    Exit;
  Result := Handled(AKey, AKeyChar, True);
end;

{ Ctrl (no Alt) letter chords, Ctrl+Left/Right word moves, Ctrl+Home/End. }
function TryCtrlKeys(const AHost: TEditorKeymapHost; const K: TKeyChord;
  var AKey: Word; var AKeyChar: Char): TKeyOutcome;

  function CtrlLetter(AUpper: Char): Boolean;
  begin
    Result := K.MatchesLetter(AUpper, [ssCtrl], [ssShift]);
  end;

var
  CanEdit, Extend: Boolean;
begin
  Result := koPass;
  if not K.HasMods([ssCtrl], [ssShift]) then
    Exit;
  CanEdit := HostCanEdit(AHost);
  Extend := ssShift in K.Mods;

  if CtrlLetter('A') then
    AHost.SelectAll()
  else if CtrlLetter('C') then
    AHost.CopySelectionOrLine()
  else if CtrlLetter('U') then
  begin
    AHost.ClearSelection();
    AHost.NotifyHost();
  end
  else if CanEdit and CtrlLetter('X') then
    AHost.CutSelectionOrLine()
  else if CanEdit and CtrlLetter('V') then
    AHost.PasteText()
  else if CanEdit and CtrlLetter('Z') then
  begin
    if Extend then
      AHost.RedoEdit()
    else
      AHost.UndoEdit();
  end
  // Far: Ctrl+Y / Ctrl+D = delete line (Redo is Ctrl+Shift+Z only).
  else if CanEdit and (CtrlLetter('Y') or CtrlLetter('D')) then
    AHost.DeleteCurrentLine()
  else if CanEdit and CtrlLetter('K') then
    AHost.DeleteToEndOfLine()
  else if CanEdit and K.MatchesLetter('N', [ssCtrl]) then
    AHost.InsertBlankLineBelow()
  else
  begin
    case K.Key of
      vkLeft, vkRight:
        AHost.MoveWord(K.Key = vkRight, Extend);
      vkHome:
        AHost.GotoFileHome(Extend);
      vkEnd:
        AHost.GotoFileEnd(Extend);
    else
      Exit;
    end;
    Exit(Handled(AKey, AKeyChar, False));
  end;
  Result := Handled(AKey, AKeyChar, True);
end;

{ Unmodified navigation / editing keys and typed characters. }
function TryBasicKeys(const AHost: TEditorKeymapHost; const K: TKeyChord;
  var AKey: Word; var AKeyChar: Char; AViewH: Integer): TKeyOutcome;
var
  Extend: Boolean;
begin
  // Viewer: numpad 5 = F10 (close).
  if HostViewOnly(AHost) and (K.Matches(vkNumpad5) or K.Matches(vkClear)) then
  begin
    AHost.RequestClose();
    Exit(Handled(AKey, AKeyChar, True));
  end;

  Extend := ssShift in K.Mods;
  case K.Key of
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
    if K.IsPrintable and K.HasMods([], [ssShift]) then
      AHost.InsertChar(K.Ch)
    else if HostViewOnly(AHost) and (K.Ch = '/') then
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
  K: TKeyChord;
  R: TKeyOutcome;
begin
  K := TKeyChord.Make(AKey, AKeyChar, AShift);
  R := TryModeKeys(AHost, K, AKey, AKeyChar);
  if R = koPass then
    R := TryEncodingKeys(AHost, K, AKey, AKeyChar);
  if R = koPass then
    R := TrySearchKeys(AHost, K, AKey, AKeyChar);
  if R = koPass then
    R := TrySaveKeys(AHost, K, AKey, AKeyChar);
  if R = koPass then
    R := TryClipboardKeys(AHost, K, AKey, AKeyChar);
  if R = koPass then
    R := TryCtrlKeys(AHost, K, AKey, AKeyChar);
  if R = koPass then
    R := TryBasicKeys(AHost, K, AKey, AKeyChar, AViewH);
  Result := R = koHandled;
end;

end.
