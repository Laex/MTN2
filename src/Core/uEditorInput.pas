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

function DispatchEditorKeys(const AHost: TEditorKeymapHost; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char; AViewH: Integer): Boolean;
begin
  Result := True;

  // F6 — Viewer ↔ Editor
  if (AKey = vkF6) and not (ssCtrl in AShift) and not (ssAlt in AShift) and
     not (ssShift in AShift) then
  begin
    AHost.ToggleViewMode();
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;

  // F4 — Hex in text/hex Viewer; Raw (render ↔ source) while Markdown is on.
  // Ctrl+H is always Hex, including Markdown (F-bar Ctrl+H:Hex / Ctrl+M:Raw).
  if (AKey = vkF4) and not (ssCtrl in AShift) and not (ssAlt in AShift) and
     not (ssShift in AShift) then
  begin
    if HostMarkdownMode(AHost) then
      AHost.ToggleMarkdownMode()
    else
      AHost.ToggleHexMode();
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;
  if (ssCtrl in AShift) and not (ssAlt in AShift) and
     ((AKey = Ord('H')) or (AKey = Ord('h'))) then
  begin
    AHost.ToggleHexMode();
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;

  // Ctrl+M — Markdown render ↔ raw text. Do not match Ord('m'): that is
  // vkSubtract, so Ctrl+- (zoom out) looked like this chord.
  if (ssCtrl in AShift) and not (ssAlt in AShift) and not (ssShift in AShift) and
     ((AKey = vkM) or (AKeyChar = 'm') or (AKeyChar = 'M')) then
  begin
    AHost.ToggleMarkdownMode();
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;

  // F8 / Shift+F8 — encoding (also exits Hex via re-decode)
  if (AKey = vkF8) and not (ssCtrl in AShift) and not (ssAlt in AShift) then
  begin
    if ssShift in AShift then
      AHost.OpenEncodingDialog()
    else
      AHost.CycleEncoding();
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;

  // Alt+F8 — goto line
  if (AKey = vkF8) and (ssAlt in AShift) and not (ssCtrl in AShift) then
  begin
    AHost.OpenGotoDialog();
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;

  // Ctrl+H / Ctrl+F7 — replace (Editor only). Ctrl+H is already consumed by
  // the Hex toggle above; this branch keeps the original Ctrl+F7 path.
  if (((AKey = vkF7) and (ssCtrl in AShift) and not (ssAlt in AShift)) or
      ((ssCtrl in AShift) and not (ssAlt in AShift) and
       ((AKey = Ord('H')) or (AKey = Ord('h'))))) and
     HostCanEdit(AHost) then
  begin
    AHost.OpenReplaceDialog();
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;

  // Shift+F7 / Alt+F7 — find next / previous
  if (AKey = vkF7) and (ssShift in AShift) and not (ssCtrl in AShift) and
     not (ssAlt in AShift) then
  begin
    if HostFindEmpty(AHost) then
      AHost.OpenFindPrompt()
    else
      AHost.FindNextOrPrev(True);
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;
  if (AKey = vkF7) and (ssAlt in AShift) and not (ssCtrl in AShift) then
  begin
    if HostFindEmpty(AHost) then
      AHost.OpenFindPrompt()
    else
      AHost.FindNextOrPrev(False);
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;

  // Ctrl+F / F7 — Find prompt
  if ((ssCtrl in AShift) and not (ssAlt in AShift) and
      ((AKey = Ord('F')) or (AKey = Ord('f')))) or
     (AKey = vkF7) or ((AKeyChar = '/') and not (ssCtrl in AShift) and
     not (ssAlt in AShift) and not HostCanEdit(AHost)) then
  begin
    // '/' opens find in ViewOnly; in edit mode '/' is a normal character.
    if (AKey = vkF7) or HostViewOnly(AHost) or (ssCtrl in AShift) then
    begin
      AHost.OpenFindPrompt();
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
  end;
  if AKey = vkF3 then
  begin
    if HostFindEmpty(AHost) then
      AHost.OpenFindPrompt()
    else
      AHost.FindNextOrPrev(not (ssShift in AShift));
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;

  if (AKey = vkF2) and not (ssCtrl in AShift) and not (ssAlt in AShift) and
     not (ssShift in AShift) then
  begin
    if HostCanEdit(AHost) then
      AHost.SaveDoc()
    else if HostViewOnly(AHost) and not HostMarkdownMode(AHost) then
      AHost.ToggleWordWrap()
    else
      Exit(False);
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;

  if HostCanEdit(AHost) and (ssCtrl in AShift) and
     ((AKey = Ord('S')) or (AKey = Ord('s')) or
      (AKeyChar = 's') or (AKeyChar = 'S')) then
  begin
    AHost.SaveDoc();
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;

  // Extra-keyboard clipboard keys: Ctrl+Insert copy, Shift+Insert paste,
  // Ctrl+Delete / Shift+Delete cut — same actions as Ctrl+C/V/X below.
  if (AKey = vkInsert) and (ssCtrl in AShift) and not (ssShift in AShift) and
     not (ssAlt in AShift) then
  begin
    AHost.CopySelectionOrLine();
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;
  if (AKey = vkInsert) and (ssShift in AShift) and not (ssCtrl in AShift) and
     not (ssAlt in AShift) and HostCanEdit(AHost) then
  begin
    AHost.PasteText();
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;
  if (AKey = vkDelete) and (ssCtrl in AShift) and not (ssShift in AShift) and
     not (ssAlt in AShift) and HostCanEdit(AHost) then
  begin
    AHost.CutSelectionOrLine();
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;
  if (AKey = vkDelete) and (ssShift in AShift) and not (ssCtrl in AShift) and
     not (ssAlt in AShift) and HostCanEdit(AHost) then
  begin
    AHost.CutSelectionOrLine();
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;

  if (ssCtrl in AShift) and not (ssAlt in AShift) then
  begin
    if (AKey = Ord('A')) or (AKey = Ord('a')) or (AKeyChar = 'a') or
       (AKeyChar = 'A') then
    begin
      AHost.SelectAll();
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
    if (AKey = Ord('C')) or (AKey = Ord('c')) or (AKeyChar = 'c') or
       (AKeyChar = 'C') then
    begin
      AHost.CopySelectionOrLine();
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
    if (AKey = Ord('U')) or (AKey = Ord('u')) or (AKeyChar = 'u') or
       (AKeyChar = 'U') then
    begin
      AHost.ClearSelection();
      AHost.NotifyHost();
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
    if HostCanEdit(AHost) and ((AKey = Ord('X')) or (AKey = Ord('x')) or
       (AKeyChar = 'x') or (AKeyChar = 'X')) then
    begin
      AHost.CutSelectionOrLine();
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
    if HostCanEdit(AHost) and ((AKey = Ord('V')) or (AKey = Ord('v')) or
       (AKeyChar = 'v') or (AKeyChar = 'V')) then
    begin
      AHost.PasteText();
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
    if HostCanEdit(AHost) and ((AKey = Ord('Z')) or (AKey = Ord('z')) or
       (AKeyChar = 'z') or (AKeyChar = 'Z')) then
    begin
      if ssShift in AShift then
        AHost.RedoEdit()
      else
        AHost.UndoEdit();
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
    // Far: Ctrl+Y / Ctrl+D = delete line (Redo is Ctrl+Shift+Z only).
    if HostCanEdit(AHost) and ((AKey = Ord('Y')) or (AKey = Ord('y')) or
       (AKeyChar = 'y') or (AKeyChar = 'Y') or (AKey = Ord('D')) or
       (AKey = Ord('d')) or (AKeyChar = 'd') or (AKeyChar = 'D')) then
    begin
      AHost.DeleteCurrentLine();
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
    if HostCanEdit(AHost) and ((AKey = Ord('K')) or (AKey = Ord('k')) or
       (AKeyChar = 'k') or (AKeyChar = 'K')) then
    begin
      AHost.DeleteToEndOfLine();
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
    if HostCanEdit(AHost) and not (ssShift in AShift) and
       ((AKey = Ord('N')) or (AKey = Ord('n')) or
        (AKeyChar = 'n') or (AKeyChar = 'N')) then
    begin
      AHost.InsertBlankLineBelow();
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
    if (AKey = vkLeft) or (AKey = vkRight) then
    begin
      AHost.MoveWord(AKey = vkRight, ssShift in AShift);
      ConsumeKey(AKey, AKeyChar, False);
      Exit;
    end;
    if (AKey = vkHome) or (AKey = vkEnd) then
    begin
      if AKey = vkHome then
        AHost.GotoFileHome(ssShift in AShift)
      else
        AHost.GotoFileEnd(ssShift in AShift);
      ConsumeKey(AKey, AKeyChar, False);
      Exit;
    end;
  end;

  if HostViewOnly(AHost) and not (ssCtrl in AShift) and not (ssAlt in AShift) and
     not (ssShift in AShift) and
     ((AKey = vkNumpad5) or (AKey = vkClear)) then
  begin
    // Viewer: numpad 5 = F10 (close).
    AHost.RequestClose();
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;

  case AKey of
    vkEscape, vkF10:
      begin
        AHost.RequestClose();
        ConsumeKey(AKey, AKeyChar, False);
      end;
    vkUp: AHost.MoveCursor(-1, 0, ssShift in AShift);
    vkDown: AHost.MoveCursor(1, 0, ssShift in AShift);
    vkLeft: AHost.MoveCursor(0, -1, ssShift in AShift);
    vkRight: AHost.MoveCursor(0, 1, ssShift in AShift);
    vkPrior:
      begin
        AHost.BreakInsertCoalesce();
        AHost.MoveCursor(-AViewH, 0, ssShift in AShift);
      end;
    vkNext:
      begin
        AHost.BreakInsertCoalesce();
        AHost.MoveCursor(AViewH, 0, ssShift in AShift);
      end;
    vkHome:
      begin
        AHost.GotoLineHome(ssShift in AShift);
        ConsumeKey(AKey, AKeyChar, False);
      end;
    vkEnd:
      begin
        AHost.GotoLineEnd(ssShift in AShift);
        ConsumeKey(AKey, AKeyChar, False);
      end;
    vkBack:
      begin
        AHost.DoBackspace();
        ConsumeKey(AKey, AKeyChar, False);
      end;
    vkDelete:
      begin
        AHost.DoDelete();
        ConsumeKey(AKey, AKeyChar, False);
      end;
    vkReturn:
      begin
        AHost.DoEnter();
        ConsumeKey(AKey, AKeyChar, False);
      end;
  else
    if (AKeyChar >= ' ') and (Ord(AKeyChar) <> 127) and
       not (ssCtrl in AShift) and not (ssAlt in AShift) then
    begin
      AHost.InsertChar(AKeyChar);
      ConsumeKey(AKey, AKeyChar, True);
    end
    else if HostViewOnly(AHost) and (AKeyChar = '/') then
    begin
      AHost.OpenFindPrompt();
      ConsumeKey(AKey, AKeyChar, True);
    end
    else
      Result := False;
  end;
  if Result and (AKey <> 0) then
    AKey := 0;
end;

end.
