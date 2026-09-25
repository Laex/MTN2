program TestEditorSearchUndo;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uEditorSearch in '..\Core\uEditorSearch.pas',
  uEditorUndo in '..\Core\uEditorUndo.pas';

procedure TestEditorSearch;
var
  LLines: TArray<string>;
  LOptions: TSearchOptions;
  LRes: TSearchResult;
  LReplaced: string;
begin
  SetLength(LLines, 2);
  LLines[0] := 'Hello World';
  LLines[1] := 'Modern Terminal Navigator';

  LOptions.MatchCase := False;
  LOptions.WholeWord := False;
  LOptions.SearchBackwards := False;

  LRes := TEditorSearchEngine.FindInText(LLines, 'terminal', 0, 0, LOptions);
  Assert(LRes.Found, 'Should find substring "terminal"');
  Assert(LRes.LineIndex = 1, 'Found line index should be 1');

  LRes := TEditorSearchEngine.FindInText(LLines, 'Hello', 0, 0, LOptions);
  Assert(LRes.Found and (LRes.LineIndex = 0) and (LRes.ColIndex = 0),
    'Hello at start of first line');

  LOptions.MatchCase := True;
  LRes := TEditorSearchEngine.FindInText(LLines, 'terminal', 0, 0, LOptions);
  Assert(not LRes.Found, 'case-sensitive miss');

  LReplaced := TEditorSearchEngine.ReplaceInLine('Hello World', 'World', 'MTN2', 6, False);
  Assert(LReplaced = 'Hello MTN2', 'Replacement should match "Hello MTN2"');

  LOptions.MatchCase := True;
  LRes := TEditorSearchEngine.FindNextWrapped(LLines, 'Hello', 0, 1, LOptions);
  Assert(LRes.Found and (LRes.LineIndex = 0) and (LRes.ColIndex = 0),
    'wrap finds Hello before cursor on the same line');
  LRes := TEditorSearchEngine.FindNextWrapped(LLines, 'World', 0, 0, LOptions);
  Assert(LRes.Found and (LRes.LineIndex = 0) and (LRes.ColIndex = 6),
    'forward from start finds World on the first line');
  LRes := TEditorSearchEngine.FindNextWrapped(LLines, 'Modern', 1, 10, LOptions);
  Assert(LRes.Found and (LRes.LineIndex = 1) and (LRes.ColIndex = 0),
    'wrap from mid-second-line finds Modern at the start of that line');

  SetLength(LLines, 1);
  LLines[0] := 'foo foo foo';
  LOptions.MatchCase := False;
  LRes := TEditorSearchEngine.FindNextWrapped(LLines, 'foo', 0, 0, LOptions);
  Assert(LRes.Found and (LRes.ColIndex = 0), 'first foo in line');
  LRes := TEditorSearchEngine.FindNextWrapped(LLines, 'foo', 0, 3, LOptions);
  Assert(LRes.Found and (LRes.ColIndex = 4), 'Shift+F7 second foo in the same line');
  LRes := TEditorSearchEngine.FindNextWrapped(LLines, 'foo', 0, 7, LOptions);
  Assert(LRes.Found and (LRes.ColIndex = 8), 'third foo in the same line');
  LRes := TEditorSearchEngine.FindNextWrapped(LLines, 'foo', 0, 11, LOptions);
  Assert(LRes.Found and (LRes.ColIndex = 0), 'wrap back to first foo');

  LRes := TEditorSearchEngine.FindPrevWrapped(LLines, 'foo', 0, 8, LOptions);
  Assert(LRes.Found and (LRes.ColIndex = 4), 'Alt+F7 previous foo on the same line');
  LRes := TEditorSearchEngine.FindPrevWrapped(LLines, 'foo', 0, 0, LOptions);
  Assert(LRes.Found and (LRes.ColIndex = 8), 'prev wrap to last foo');

  Writeln('OK: TestEditorSearch passed');
end;

procedure TestEditorUndo;
var
  LBuffer: TEditorUndoBuffer;
  LEntry, LPopped: TEditorUndoEntry;
begin
  LBuffer := TEditorUndoBuffer.Create;
  try
    Assert(not LBuffer.CanUndo, 'Should not can undo initially');
    Assert(not LBuffer.CanRedo, 'Should not can redo initially');
    LEntry.Lines := TArray<string>.Create('A');
    LEntry.CursorRow := 0;
    LEntry.CursorCol := 1;
    LBuffer.PushState(LEntry);
    Assert(LBuffer.CanUndo, 'Should can undo after push');
    Assert(LBuffer.UndoCount = 1, 'undo count 1');

    LPopped := LBuffer.PopUndoState;
    Assert((Length(LPopped.Lines) = 1) and (LPopped.Lines[0] = 'A'),
      'PopUndoState restores lines');
    Assert(LPopped.CursorCol = 1, 'cursor col restored');
    Assert(not LBuffer.CanUndo, 'undo stack empty after pop');
    LBuffer.PushRedo(LPopped);
    Assert(LBuffer.CanRedo, 'PushRedo enables redo');
    LPopped := LBuffer.PopRedoState;
    Assert(LPopped.Lines[0] = 'A', 'PopRedoState returns the entry');
    Assert(not LBuffer.CanRedo, 'redo stack empty after pop');
  finally
    LBuffer.Free;
  end;

  Writeln('OK: TestEditorUndo passed');
end;

begin
  try
    TestEditorSearch;
    TestEditorUndo;
    Writeln('All EditorSearchUndo tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
