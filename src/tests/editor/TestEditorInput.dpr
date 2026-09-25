program TestEditorInput;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.UITypes,
  uEditorInput in '..\..\Core\uEditorInput.pas';

type
  TEditorSpy = class
  public
    Last: string;
    CanEditVal: Boolean;
    ViewOnlyVal: Boolean;
    MarkdownModeVal: Boolean;
    FindEmptyVal: Boolean;
    ForwardVal: Boolean;
    ExtendVal: Boolean;
    RowDelta: Integer;
    ColDelta: Integer;
    Ch: Char;
    function CanEdit: Boolean;
    function ViewOnly: Boolean;
    function MarkdownMode: Boolean;
    function FindNeedleEmpty: Boolean;
    procedure ToggleViewMode;
    procedure ToggleHexMode;
    procedure ToggleMarkdownMode;
    procedure OpenEncodingDialog;
    procedure CycleEncoding;
    procedure OpenGotoDialog;
    procedure OpenReplaceDialog;
    procedure OpenFindPrompt;
    procedure FindNextOrPrev(AForward: Boolean);
    procedure SaveDoc;
    procedure ToggleWordWrap;
    procedure CopySelectionOrLine;
    procedure PasteText;
    procedure CutSelectionOrLine;
    procedure SelectAll;
    procedure ClearSelection;
    procedure NotifyHost;
    procedure UndoEdit;
    procedure RedoEdit;
    procedure DeleteCurrentLine;
    procedure DeleteToEndOfLine;
    procedure InsertBlankLineBelow;
    procedure MoveWord(AForward, AExtendSel: Boolean);
    procedure MoveCursor(ARowDelta, AColDelta: Integer; AExtendSel: Boolean);
    procedure BreakInsertCoalesce;
    procedure GotoFileHome(AExtendSel: Boolean);
    procedure GotoFileEnd(AExtendSel: Boolean);
    procedure GotoLineHome(AExtendSel: Boolean);
    procedure GotoLineEnd(AExtendSel: Boolean);
    procedure RequestClose;
    procedure DoBackspace;
    procedure DoDelete;
    procedure DoEnter;
    procedure InsertChar(ACh: Char);
  end;

function TEditorSpy.CanEdit: Boolean;
begin
  Result := CanEditVal;
end;

function TEditorSpy.ViewOnly: Boolean;
begin
  Result := ViewOnlyVal;
end;

function TEditorSpy.MarkdownMode: Boolean;
begin
  Result := MarkdownModeVal;
end;

function TEditorSpy.FindNeedleEmpty: Boolean;
begin
  Result := FindEmptyVal;
end;

procedure TEditorSpy.ToggleViewMode;
begin
  Last := 'view';
end;

procedure TEditorSpy.ToggleHexMode;
begin
  Last := 'hex';
end;

procedure TEditorSpy.ToggleMarkdownMode;
begin
  Last := 'md';
end;

procedure TEditorSpy.OpenEncodingDialog;
begin
  Last := 'encdlg';
end;

procedure TEditorSpy.CycleEncoding;
begin
  Last := 'enccycle';
end;

procedure TEditorSpy.OpenGotoDialog;
begin
  Last := 'goto';
end;

procedure TEditorSpy.OpenReplaceDialog;
begin
  Last := 'replace';
end;

procedure TEditorSpy.OpenFindPrompt;
begin
  Last := 'find';
end;

procedure TEditorSpy.FindNextOrPrev(AForward: Boolean);
begin
  Last := 'findnav';
  ForwardVal := AForward;
end;

procedure TEditorSpy.SaveDoc;
begin
  Last := 'save';
end;

procedure TEditorSpy.ToggleWordWrap;
begin
  Last := 'wrap';
end;

procedure TEditorSpy.CopySelectionOrLine;
begin
  Last := 'copy';
end;

procedure TEditorSpy.PasteText;
begin
  Last := 'paste';
end;

procedure TEditorSpy.CutSelectionOrLine;
begin
  Last := 'cut';
end;

procedure TEditorSpy.SelectAll;
begin
  Last := 'selectall';
end;

procedure TEditorSpy.ClearSelection;
begin
  Last := 'clearsel';
end;

procedure TEditorSpy.NotifyHost;
begin
  Last := Last + '+notify';
end;

procedure TEditorSpy.UndoEdit;
begin
  Last := 'undo';
end;

procedure TEditorSpy.RedoEdit;
begin
  Last := 'redo';
end;

procedure TEditorSpy.DeleteCurrentLine;
begin
  Last := 'delline';
end;

procedure TEditorSpy.DeleteToEndOfLine;
begin
  Last := 'deleol';
end;

procedure TEditorSpy.InsertBlankLineBelow;
begin
  Last := 'blank';
end;

procedure TEditorSpy.MoveWord(AForward, AExtendSel: Boolean);
begin
  Last := 'word';
  ForwardVal := AForward;
  ExtendVal := AExtendSel;
end;

procedure TEditorSpy.MoveCursor(ARowDelta, AColDelta: Integer; AExtendSel: Boolean);
begin
  Last := 'move';
  RowDelta := ARowDelta;
  ColDelta := AColDelta;
  ExtendVal := AExtendSel;
end;

procedure TEditorSpy.BreakInsertCoalesce;
begin
  Last := 'break';
end;

procedure TEditorSpy.GotoFileHome(AExtendSel: Boolean);
begin
  Last := 'filehome';
  ExtendVal := AExtendSel;
end;

procedure TEditorSpy.GotoFileEnd(AExtendSel: Boolean);
begin
  Last := 'fileend';
  ExtendVal := AExtendSel;
end;

procedure TEditorSpy.GotoLineHome(AExtendSel: Boolean);
begin
  Last := 'linehome';
  ExtendVal := AExtendSel;
end;

procedure TEditorSpy.GotoLineEnd(AExtendSel: Boolean);
begin
  Last := 'lineend';
  ExtendVal := AExtendSel;
end;

procedure TEditorSpy.RequestClose;
begin
  Last := 'close';
end;

procedure TEditorSpy.DoBackspace;
begin
  Last := 'back';
end;

procedure TEditorSpy.DoDelete;
begin
  Last := 'del';
end;

procedure TEditorSpy.DoEnter;
begin
  Last := 'enter';
end;

procedure TEditorSpy.InsertChar(ACh: Char);
begin
  Last := 'ins';
  Ch := ACh;
end;

procedure BindSpy(var AHost: TEditorKeymapHost; ASpy: TEditorSpy);
begin
  FillChar(AHost, SizeOf(AHost), 0);
  AHost.CanEdit := ASpy.CanEdit;
  AHost.ViewOnly := ASpy.ViewOnly;
  AHost.MarkdownMode := ASpy.MarkdownMode;
  AHost.FindNeedleEmpty := ASpy.FindNeedleEmpty;
  AHost.ToggleViewMode := ASpy.ToggleViewMode;
  AHost.ToggleHexMode := ASpy.ToggleHexMode;
  AHost.ToggleMarkdownMode := ASpy.ToggleMarkdownMode;
  AHost.OpenEncodingDialog := ASpy.OpenEncodingDialog;
  AHost.CycleEncoding := ASpy.CycleEncoding;
  AHost.OpenGotoDialog := ASpy.OpenGotoDialog;
  AHost.OpenReplaceDialog := ASpy.OpenReplaceDialog;
  AHost.OpenFindPrompt := ASpy.OpenFindPrompt;
  AHost.FindNextOrPrev := ASpy.FindNextOrPrev;
  AHost.SaveDoc := ASpy.SaveDoc;
  AHost.ToggleWordWrap := ASpy.ToggleWordWrap;
  AHost.CopySelectionOrLine := ASpy.CopySelectionOrLine;
  AHost.PasteText := ASpy.PasteText;
  AHost.CutSelectionOrLine := ASpy.CutSelectionOrLine;
  AHost.SelectAll := ASpy.SelectAll;
  AHost.ClearSelection := ASpy.ClearSelection;
  AHost.NotifyHost := ASpy.NotifyHost;
  AHost.UndoEdit := ASpy.UndoEdit;
  AHost.RedoEdit := ASpy.RedoEdit;
  AHost.DeleteCurrentLine := ASpy.DeleteCurrentLine;
  AHost.DeleteToEndOfLine := ASpy.DeleteToEndOfLine;
  AHost.InsertBlankLineBelow := ASpy.InsertBlankLineBelow;
  AHost.MoveWord := ASpy.MoveWord;
  AHost.MoveCursor := ASpy.MoveCursor;
  AHost.BreakInsertCoalesce := ASpy.BreakInsertCoalesce;
  AHost.GotoFileHome := ASpy.GotoFileHome;
  AHost.GotoFileEnd := ASpy.GotoFileEnd;
  AHost.GotoLineHome := ASpy.GotoLineHome;
  AHost.GotoLineEnd := ASpy.GotoLineEnd;
  AHost.RequestClose := ASpy.RequestClose;
  AHost.DoBackspace := ASpy.DoBackspace;
  AHost.DoDelete := ASpy.DoDelete;
  AHost.DoEnter := ASpy.DoEnter;
  AHost.InsertChar := ASpy.InsertChar;
end;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

procedure TestDispatch;
var
  Spy: TEditorSpy;
  Host: TEditorKeymapHost;
  Key: Word;
  KeyChar: Char;
begin
  Spy := TEditorSpy.Create;
  try
    BindSpy(Host, Spy);
    Spy.CanEditVal := True;
    Spy.ViewOnlyVal := False;
    Spy.FindEmptyVal := True;

    Writeln('Consume-key / action map');

    Key := vkF1;
    KeyChar := #0;
    Expect(not DispatchEditorKeys(Host, Key, [], KeyChar, 10), 'F1 is unhandled');
    Expect(Key = vkF1, 'unhandled leaves AKey');
    Expect(KeyChar = #0, 'unhandled leaves AKeyChar');

    Key := vkF6;
    KeyChar := 'x';
    Expect(DispatchEditorKeys(Host, Key, [], KeyChar, 10), 'F6 handled');
    Expect(Spy.Last = 'view', 'F6 toggles view');
    Expect(Key = 0, 'F6 consumes AKey');
    Expect(KeyChar = 'x', 'F6 leaves AKeyChar');

    Key := Ord('H');
    KeyChar := 'h';
    Expect(DispatchEditorKeys(Host, Key, [ssCtrl], KeyChar, 10), 'Ctrl+H handled');
    Expect(Spy.Last = 'hex', 'Ctrl+H is hex, not replace');
    Expect(Key = 0, 'Ctrl+H consumes AKey');
    Expect(KeyChar = #0, 'Ctrl+H consumes AKeyChar');

    Key := vkF4;
    KeyChar := 'x';
    Expect(DispatchEditorKeys(Host, Key, [], KeyChar, 10), 'editor F4 handled');
    Expect(Spy.Last = 'hex', 'editor F4 is hex');

    Spy.CanEditVal := False;
    Spy.ViewOnlyVal := True;
    Spy.MarkdownModeVal := True;
    Spy.Last := 'keep';
    Key := vkF4;
    KeyChar := 'x';
    Expect(DispatchEditorKeys(Host, Key, [], KeyChar, 10), 'markdown F4 handled');
    Expect(Spy.Last = 'md', 'markdown F4 is Raw, not Hex');

    Key := Ord('H');
    KeyChar := 'h';
    Expect(DispatchEditorKeys(Host, Key, [ssCtrl], KeyChar, 10), 'markdown Ctrl+H');
    Expect(Spy.Last = 'hex', 'markdown Ctrl+H stays Hex');

    Key := Ord('M');
    KeyChar := 'm';
    Expect(DispatchEditorKeys(Host, Key, [ssCtrl], KeyChar, 10), 'markdown Ctrl+M');
    Expect(Spy.Last = 'md', 'Ctrl+M toggles markdown');

    Spy.Last := 'keep';
    Key := vkSubtract;
    KeyChar := #0;
    Expect(not DispatchEditorKeys(Host, Key, [ssCtrl], KeyChar, 10),
      'Ctrl+Minus is not Ctrl+M');
    Expect(Spy.Last = 'keep', 'vkSubtract does not toggle markdown');
    Expect(Key = vkSubtract, 'Ctrl+Minus leaves AKey');

    Spy.Last := 'keep';
    Key := vkF2;
    KeyChar := 'x';
    Expect(not DispatchEditorKeys(Host, Key, [], KeyChar, 10),
      'markdown F2 is not wrap');
    Expect(Spy.Last = 'keep', 'markdown F2 does not toggle wrap');
    Expect(Key = vkF2, 'markdown F2 leaves AKey');

    Spy.MarkdownModeVal := False;
    Spy.CanEditVal := True;
    Spy.ViewOnlyVal := False;

    Key := vkF7;
    KeyChar := 'x';
    Expect(DispatchEditorKeys(Host, Key, [ssCtrl], KeyChar, 10), 'Ctrl+F7 handled');
    Expect(Spy.Last = 'replace', 'Ctrl+F7 opens replace when CanEdit');
    Expect(Key = 0, 'Ctrl+F7 consumes AKey');
    Expect(KeyChar = #0, 'Ctrl+F7 consumes AKeyChar');

    Key := vkF8;
    KeyChar := 'x';
    Expect(DispatchEditorKeys(Host, Key, [], KeyChar, 10), 'F8 handled');
    Expect(Spy.Last = 'enccycle', 'F8 cycles encoding');
    Expect(KeyChar = 'x', 'F8 leaves AKeyChar');

    Key := vkF8;
    Expect(DispatchEditorKeys(Host, Key, [ssShift], KeyChar, 10), 'Shift+F8 handled');
    Expect(Spy.Last = 'encdlg', 'Shift+F8 opens encoding dialog');

    Key := vkF8;
    Expect(DispatchEditorKeys(Host, Key, [ssAlt], KeyChar, 10), 'Alt+F8 handled');
    Expect(Spy.Last = 'goto', 'Alt+F8 opens goto');

    Key := vkF2;
    KeyChar := 'x';
    Expect(DispatchEditorKeys(Host, Key, [], KeyChar, 10), 'F2 handled');
    Expect(Spy.Last = 'save', 'F2 saves when CanEdit');
    Expect(KeyChar = #0, 'F2 consumes AKeyChar');

    Spy.CanEditVal := False;
    Spy.ViewOnlyVal := True;
    Key := vkF2;
    KeyChar := 'x';
    Expect(DispatchEditorKeys(Host, Key, [], KeyChar, 10), 'viewer F2 handled');
    Expect(Spy.Last = 'wrap', 'F2 toggles wrap in viewer');

    Key := vkF7;
    KeyChar := 'x';
    Expect(DispatchEditorKeys(Host, Key, [ssCtrl], KeyChar, 10), 'viewer Ctrl+F7');
    Expect(Spy.Last = 'find', 'Ctrl+F7 opens find when not CanEdit');

    Key := vkUp;
    KeyChar := 'x';
    Expect(DispatchEditorKeys(Host, Key, [ssShift], KeyChar, 10), 'Up handled');
    Expect(Spy.Last = 'move', 'Up moves cursor');
    Expect(Spy.RowDelta = -1, 'Up row delta');
    Expect(Spy.ExtendVal, 'Shift+Up extends');
    Expect(Key = 0, 'Up consumes AKey via tail');
    Expect(KeyChar = 'x', 'Up leaves AKeyChar');

    Key := vkLeft;
    KeyChar := 'x';
    Expect(DispatchEditorKeys(Host, Key, [], KeyChar, 10), 'viewer Left handled');
    Expect(Spy.Last = 'move', 'Left moves cursor');
    Expect((Spy.RowDelta = 0) and (Spy.ColDelta = -1), 'Left col delta');

    Key := vkRight;
    KeyChar := 'x';
    Expect(DispatchEditorKeys(Host, Key, [ssShift], KeyChar, 10),
      'viewer Shift+Right handled');
    Expect(Spy.Last = 'move', 'Shift+Right moves cursor');
    Expect((Spy.RowDelta = 0) and (Spy.ColDelta = 1), 'Shift+Right col delta');
    Expect(Spy.ExtendVal, 'Shift+Right extends selection');

    Key := vkRight;
    KeyChar := 'x';
    Expect(DispatchEditorKeys(Host, Key, [], KeyChar, 10), 'viewer Right handled');
    Expect(Spy.Last = 'move', 'Right moves cursor');
    Expect((Spy.RowDelta = 0) and (Spy.ColDelta = 1), 'Right col delta');

    Key := 0;
    KeyChar := '/';
    Expect(DispatchEditorKeys(Host, Key, [], KeyChar, 10), 'viewer slash handled');
    Expect(Spy.Last = 'find', 'viewer slash opens find');
    Expect(KeyChar = #0, 'slash consumes AKeyChar');

    Spy.CanEditVal := True;
    Spy.ViewOnlyVal := False;
    Key := 0;
    KeyChar := 'a';
    Expect(DispatchEditorKeys(Host, Key, [], KeyChar, 10), 'printable handled');
    Expect(Spy.Last = 'ins', 'inserts char');
    Expect(Spy.Ch = 'a', 'inserted a');
    Expect(KeyChar = #0, 'insert consumes AKeyChar');

    Key := Ord('Z');
    KeyChar := 'z';
    Expect(DispatchEditorKeys(Host, Key, [ssCtrl], KeyChar, 10), 'Ctrl+Z handled');
    Expect(Spy.Last = 'undo', 'Ctrl+Z undo');
    Key := Ord('Z');
    KeyChar := 'z';
    Expect(DispatchEditorKeys(Host, Key, [ssCtrl, ssShift], KeyChar, 10),
      'Ctrl+Shift+Z handled');
    Expect(Spy.Last = 'redo', 'Ctrl+Shift+Z redo');

    Key := Ord('N');
    KeyChar := 'n';
    Expect(DispatchEditorKeys(Host, Key, [ssCtrl], KeyChar, 10), 'Ctrl+N handled');
    Expect(Spy.Last = 'blank', 'Ctrl+N inserts blank line');

    Key := vkInsert;
    KeyChar := #0;
    Expect(DispatchEditorKeys(Host, Key, [ssCtrl], KeyChar, 10), 'Ctrl+Ins handled');
    Expect(Spy.Last = 'copy', 'Ctrl+Ins copies');
    Key := vkInsert;
    KeyChar := #0;
    Expect(DispatchEditorKeys(Host, Key, [ssShift], KeyChar, 10), 'Shift+Ins handled');
    Expect(Spy.Last = 'paste', 'Shift+Ins pastes');
    Key := vkDelete;
    KeyChar := #0;
    Expect(DispatchEditorKeys(Host, Key, [ssCtrl], KeyChar, 10), 'Ctrl+Del handled');
    Expect(Spy.Last = 'cut', 'Ctrl+Del cuts');

    Spy.Last := 'keep';
    Key := Ord('N');
    KeyChar := 'n';
    Expect(not DispatchEditorKeys(Host, Key, [ssCtrl, ssShift], KeyChar, 10),
      'Ctrl+Shift+N is host new-terminal');
    Expect(Spy.Last = 'keep', 'Ctrl+Shift+N does not insert a line');
    Expect(Key = Ord('N'), 'Ctrl+Shift+N leaves AKey');
  finally
    Spy.Free;
  end;
end;

begin
  try
    TestDispatch;
    Writeln('All EditorInput tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.Message);
      Halt(1);
    end;
  end;
end.
