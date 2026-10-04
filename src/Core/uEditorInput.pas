unit uEditorInput;

{ Editor/Viewer key dispatch extracted from TEditorWindow.HandleInput.
  Host stays a thin facade: dialog/find-prompt routing stays on the window;
  this unit maps keymap actions (uKeymap: contexts Document, Viewer, Editor,
  Markdown) onto the host and owns the keys that are not commands. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, uKeymap;

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
    OpenFindDialog: TEditorProc;
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

/// <summary>Keymap commands (ActiveKeymap) first, then cursor keys and
/// typing. True when the key was used; AKey/AKeyChar are then consumed.</summary>
function DispatchEditorKeys(const AHost: TEditorKeymapHost; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char; AViewH: Integer): Boolean;
/// <summary>The keymap contexts a document looks keys up in, most specific
/// first (Global not included).</summary>
function EditorKeymapChain(AViewOnly, AMarkdown: Boolean): TArray<TKeymapContext>;
/// <summary>DispatchEditorKeys against AProfile instead of ActiveKeymap.</summary>
function DispatchEditorKeysWith(const AProfile: TKeymapProfile;
  const AHost: TEditorKeymapHost; var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char; AViewH: Integer): Boolean;

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

{ ---- Dispatch ---------------------------------------------------------------

  Commands come from the keymap (uKeymap): the keystroke is looked up along
  the document's context chain -- Markdown (while rendering it), then Viewer
  or Editor, then Document -- and the action found is run (see TActionRun
  for one that does not apply right now). What is not a command stays here: '/' and numpad 5 in the viewer, Ctrl+arrows /
  Home / End, cursor movement and typing. }

function EditorKeymapChain(AViewOnly, AMarkdown: Boolean): TArray<TKeymapContext>;
begin
  if AViewOnly then
    Result := [kcViewer, kcDocument]
  else
    Result := [kcEditor, kcDocument];
  if AMarkdown then
    Result := [kcMarkdown] + Result;
end;

function DocumentChain(const AHost: TEditorKeymapHost): TArray<TKeymapContext>;
begin
  Result := EditorKeymapChain(HostViewOnly(AHost), HostMarkdownMode(AHost));
end;

/// <summary>F7-family "find again": opens the prompt while there is no needle.</summary>
procedure FindAgain(const AHost: TEditorKeymapHost; AForward: Boolean);
begin
  if HostFindEmpty(AHost) then
    AHost.OpenFindDialog()
  else
    AHost.FindNextOrPrev(AForward);
end;

type
  TActionRun = (
    arDone,    // ran: the key is used
    arPass,    // an editor command on a read-only document: the key goes on
               // to the cursor / editing keys (Del still offers to unlock)
    arReject   // does not apply here (word wrap over rendered Markdown): unused
  );

function RunAction(const AHost: TEditorKeymapHost; AAction: TKeymapAction): TActionRun;
begin
  Result := arDone;
  case AAction of
    kaDocToggleEdit:
      AHost.ToggleViewMode();
    kaDocHex:
      AHost.ToggleHexMode();
    kaDocMarkdown, kaMarkdownSource:
      AHost.ToggleMarkdownMode();
    kaDocEncodingNext:
      AHost.CycleEncoding();
    kaDocEncoding:
      AHost.OpenEncodingDialog();
    kaDocGotoLine:
      AHost.OpenGotoDialog();
    kaDocFind:
      AHost.OpenFindDialog();
    kaDocFindNext:
      FindAgain(AHost, True);
    kaDocFindPrev:
      FindAgain(AHost, False);
    kaDocCopy:
      AHost.CopySelectionOrLine();
    kaDocSelectAll:
      AHost.SelectAll();
    kaDocClearSelection:
      begin
        AHost.ClearSelection();
        AHost.NotifyHost();
      end;
    kaDocClose:
      AHost.RequestClose();
    kaViewerWordWrap:
      if HostViewOnly(AHost) and not HostMarkdownMode(AHost) then
        AHost.ToggleWordWrap()
      else
        Result := arReject;
  else
    // Editor commands change the text: only while it can be edited.
    if not HostCanEdit(AHost) then
      Exit(arPass);
    case AAction of
      kaEditorSave:
        AHost.SaveDoc();
      kaEditorReplace:
        AHost.OpenReplaceDialog();
      kaEditorPaste:
        AHost.PasteText();
      kaEditorCut:
        AHost.CutSelectionOrLine();
      kaEditorUndo:
        AHost.UndoEdit();
      kaEditorRedo:
        AHost.RedoEdit();
      kaEditorDeleteLine:
        AHost.DeleteCurrentLine();
      kaEditorDeleteToEol:
        AHost.DeleteToEndOfLine();
      kaEditorInsertLine:
        AHost.InsertBlankLineBelow();
    else
      Result := arPass;
    end;
  end;
end;

{ Keys that are not keymap commands. }
function DispatchBuiltInKeys(const AHost: TEditorKeymapHost; const K: TKeyChord;
  var AKey: Word; var AKeyChar: Char; AViewH: Integer): Boolean;
var
  Extend: Boolean;
begin
  Result := True;
  Extend := ssShift in K.Mods;

  // Viewer: '/' opens find (a typed character, not a key: not in the keymap);
  // numpad 5 closes like F10.
  if HostViewOnly(AHost) and (K.Ch = '/') and K.HasMods([], [ssShift]) then
  begin
    AHost.OpenFindDialog();
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;
  if HostViewOnly(AHost) and (K.Matches(vkNumpad5) or K.Matches(vkClear)) then
  begin
    AHost.RequestClose();
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;

  // Ctrl+Left/Right word, Ctrl+Home/End file start / end (Shift extends).
  if K.HasMods([ssCtrl], [ssShift]) then
    case K.Key of
      vkLeft, vkRight:
        begin
          AHost.MoveWord(K.Key = vkRight, Extend);
          ConsumeKey(AKey, AKeyChar, False);
          Exit;
        end;
      vkHome:
        begin
          AHost.GotoFileHome(Extend);
          ConsumeKey(AKey, AKeyChar, False);
          Exit;
        end;
      vkEnd:
        begin
          AHost.GotoFileEnd(Extend);
          ConsumeKey(AKey, AKeyChar, False);
          Exit;
        end;
    end;

  // Cursor movement and editing keys, then typed characters.
  case K.Key of
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
    begin
      AHost.InsertChar(K.Ch);
      ConsumeKey(AKey, AKeyChar, True);
    end
    else
      Result := False;
    Exit;
  end;
  ConsumeKey(AKey, AKeyChar, False);
end;

function DispatchEditorKeysWith(const AProfile: TKeymapProfile;
  const AHost: TEditorKeymapHost; var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char; AViewH: Integer): Boolean;
var
  K: TKeyChord;
  Act: TKeymapAction;
begin
  K := TKeyChord.Make(AKey, AKeyChar, AShift);
  Act := MatchActionIn(AProfile, DocumentChain(AHost),
    KeymapLookupKey(AKey, AKeyChar), AShift);
  if Act <> kaNone then
    case RunAction(AHost, Act) of
      arReject:
        Exit(False);
      arDone:
        begin
          // The F-key commands and Esc / F10 leave AKeyChar as it was; the
          // rest (Ctrl+letter chords among them) clear it so no character is
          // typed.
          ConsumeKey(AKey, AKeyChar, not (Act in [kaDocToggleEdit, kaDocEncodingNext,
            kaDocEncoding, kaDocGotoLine, kaDocFindNext, kaDocFindPrev, kaDocClose]));
          Exit(True);
        end;
    end;
  Result := DispatchBuiltInKeys(AHost, K, AKey, AKeyChar, AViewH);
end;

function DispatchEditorKeys(const AHost: TEditorKeymapHost; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char; AViewH: Integer): Boolean;
begin
  Result := DispatchEditorKeysWith(ActiveKeymap, AHost, AKey, AShift, AKeyChar, AViewH);
end;

end.
