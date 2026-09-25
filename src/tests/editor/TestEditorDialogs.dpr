program TestEditorDialogs;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.UITypes,
  uDialogTypes in '..\..\Core\uDialogTypes.pas',
  uTextEncoding in '..\..\Core\uTextEncoding.pas',
  uEditorDialogs in '..\..\Core\uEditorDialogs.pas',
  uTerminalTypes in '..\..\Core\uTerminalTypes.pas',
  uDialogHost in '..\..\Core\uDialogHost.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

procedure TestAskSaveHotkey;
begin
  Writeln('Ask-save hotkeys');
  Expect(EditorAskSaveHotkey(Ord('Y'), #0) = cDlgCmdYes, 'Y key is Yes');
  Expect(EditorAskSaveHotkey(Ord('S'), #0) = cDlgCmdYes, 'S key is Yes');
  Expect(EditorAskSaveHotkey(Ord('N'), #0) = cDlgCmdNo, 'N key is No');
  Expect(EditorAskSaveHotkey(Ord('D'), #0) = cDlgCmdNo, 'D key is No');
  Expect(EditorAskSaveHotkey(0, 'y') = cDlgCmdYes, 'typed y is Yes');
  Expect(EditorAskSaveHotkey(0, #$0414) = cDlgCmdYes, 'Cyrillic D is Yes');
  Expect(EditorAskSaveHotkey(0, #$043D) = cDlgCmdNo, 'Cyrillic n is No');
  Expect(EditorAskSaveHotkey(vkEscape, #0) = '', 'Esc is not a letter hotkey');
  Expect(EditorAskSaveAction(cDlgCmdYes) = esaYes, 'yes cmd');
  Expect(EditorAskSaveAction(cDlgCmdNo) = esaNo, 'no cmd');
  Expect(EditorAskSaveAction(cDlgCmdCancel) = esaCancel, 'cancel cmd');
  Expect(EditorAskSaveAction('') = esaCancel, 'empty is cancel');
end;

procedure TestReplaceAndEncoding;
var
  Name: string;
  Idx: Integer;
begin
  Writeln('Replace / encoding helpers');
  Expect(EditorReplaceAction(cDlgCmdReplaceOne) = eraOne, 'replace one');
  Expect(EditorReplaceAction(cDlgCmdReplaceAll) = eraAll, 'replace all');
  Expect(EditorReplaceAction(cDlgCmdCancel) = eraNone, 'cancel is none');
  Expect(EditorReplaceShouldRun(cDlgCmdReplaceOne, 'foo'), 'one with needle runs');
  Expect(EditorReplaceShouldRun(cDlgCmdReplaceAll, 'foo'), 'all with needle runs');
  Expect(not EditorReplaceShouldRun(cDlgCmdReplaceOne, ''), 'empty find does not run');
  Expect(not EditorReplaceShouldRun(cDlgCmdReplaceOne, '   '), 'blank find does not run');
  Expect(not EditorReplaceShouldRun(cDlgCmdCancel, 'foo'), 'cancel does not run');
  Expect(EditorEncodingAccepted(cDlgCmdOk), 'ok accepts encoding');
  Expect(EditorEncodingAccepted(cDlgCmdYes), 'yes accepts encoding');
  Expect(EditorEncodingAccepted('encoding'), 'list id accepts encoding');
  Expect(not EditorEncodingAccepted(cDlgCmdCancel), 'cancel rejects encoding');

  Name := 'keep';
  Idx := 7;
  EditorMergeEncodingJson('', Name, Idx);
  Expect(Name = 'keep', 'empty json keeps name');
  Expect(Idx = 7, 'empty json keeps index');

  EditorMergeEncodingJson('{"encoding":"UTF-8"}', Name, Idx);
  Expect(Name = 'UTF-8', 'string encoding overwrites name');
  Expect(Idx = 7, 'string encoding leaves index');

  EditorMergeEncodingJson('{"encoding":2}', Name, Idx);
  Expect(Idx = 2, 'numeric encoding overwrites index');
end;

procedure NoopDialogCommand(const AControlId, AValuesJson: string);
begin
end;

function GridHasText(const AGrid: TTerminalGrid; const ANeedle: string): Boolean;
var
  Y, X: Integer;
  Line: string;
begin
  Result := False;
  for Y := 0 to High(AGrid) do
  begin
    Line := '';
    for X := 0 to High(AGrid[Y]) do
      Line := Line + AGrid[Y][X].CharValue;
    if Pos(ANeedle, Line) > 0 then
      Exit(True);
  end;
end;

procedure TestCodePageListLastRow;
var
  Host: TDialogHost;
  Decl: TDialogDeclaration;
  Grid: TTerminalGrid;
  Key: Word;
  Ch: Char;
  I: Integer;
  Items: TArray<string>;
begin
  Writeln('Code page list last row / scroll');
  Host := TDialogHost.Create(nil);
  try
    Items := TextEncodingListItems;
    Decl.Version := cDialogProtocolV2;
    Decl.Title := 'Code page';
    Decl.Width := 28;
    Decl.Height := 9;
    Decl.IsWarning := False;
    SetLength(Decl.Controls, 1);
    Decl.Controls[0] := WithControlBox(MakeList('encoding', Items, 0), 1, 1, 24, 6);
    Host.Open(Decl, NoopDialogCommand);

    AllocTerminalGrid(Grid, 80, 25);
    ClearTerminalGrid(Grid, $FF000000, $FFFFFFFF, ' ');
    Host.Draw(Grid, 80, 25);
    Expect(GridHasText(Grid, 'OEM'), 'all 6 encodings visible including last (OEM)');

    for I := 1 to High(Items) do
    begin
      Key := vkDown;
      Ch := #0;
      Host.HandleInput(Key, [], Ch);
    end;
    Key := vkDown;
    Ch := #0;
    Host.HandleInput(Key, [], Ch);
    Expect(Host.GetListSelectedText('encoding') = 'OEM',
      'Down past last item stays on OEM');
    ClearTerminalGrid(Grid, $FF000000, $FFFFFFFF, ' ');
    Host.Draw(Grid, 80, 25);
    Expect(GridHasText(Grid, 'OEM'), 'OEM still drawn after Down on last row');

    SetLength(Items, 10);
    for I := 0 to High(Items) do
      Items[I] := 'Row-' + IntToStr(I);
    Decl.Controls[0] := WithControlBox(MakeList('encoding', Items, 0), 1, 1, 24, 6);
    Host.Open(Decl, NoopDialogCommand);
    for I := 1 to 7 do
    begin
      Key := vkDown;
      Ch := #0;
      Host.HandleInput(Key, [], Ch);
    end;
    Expect(Host.GetListSelectedIndex('encoding') = 7, 'scrolled selection is item 7');
    Expect(Host.GetListSelectedText('encoding') = 'Row-7', 'scrolled selection text is Row-7');
    ClearTerminalGrid(Grid, $FF000000, $FFFFFFFF, ' ');
    Host.Draw(Grid, 80, 25);
    Expect(GridHasText(Grid, 'Row-7'), 'scrolled list draws the selected row');
    Expect(not GridHasText(Grid, 'Row-0'), 'first row scrolled out of view');
  finally
    Host.Free;
  end;
end;

procedure TestDropDownPopupScroll;
var
  Host: TDialogHost;
  Decl: TDialogDeclaration;
  Grid: TTerminalGrid;
  Key: Word;
  Ch: Char;
  Items: TArray<string>;
  I: Integer;
begin
  Writeln('DropDown popup scroll');
  SetLength(Items, 13);
  for I := 0 to High(Items) do
    Items[I] := 'Size-' + IntToStr(I);
  Host := TDialogHost.Create(nil);
  try
    Decl.Version := cDialogProtocolV2;
    Decl.Title := 'Font / Display';
    Decl.Width := 54;
    Decl.Height := 20;
    Decl.IsWarning := False;
    SetLength(Decl.Controls, 1);
    Decl.Controls[0] := WithControlBox(MakeDropDown('font_size', Items, 5), 10, 9, 12, 1);
    Host.Open(Decl, NoopDialogCommand);

    AllocTerminalGrid(Grid, 80, 25);
    ClearTerminalGrid(Grid, $FF000000, $FFFFFFFF, ' ');
    Host.Draw(Grid, 80, 25);

    Key := vkSpace;
    Ch := #0;
    Host.HandleInput(Key, [], Ch);
    ClearTerminalGrid(Grid, $FF000000, $FFFFFFFF, ' ');
    Host.Draw(Grid, 80, 25);
    Expect(GridHasText(Grid, 'Size-5'), 'open popup shows the selected size');
    Expect(not GridHasText(Grid, 'Size-12'), 'popup is clipped; last sizes start off-screen');

    Key := vkEnd;
    Ch := #0;
    Host.HandleInput(Key, [], Ch);
    ClearTerminalGrid(Grid, $FF000000, $FFFFFFFF, ' ');
    Host.Draw(Grid, 80, 25);
    Expect(GridHasText(Grid, 'Size-12'), 'End scrolls popup to last size');
    Expect(not GridHasText(Grid, 'Size-0'), 'first size scrolled out after End');

    Key := vkReturn;
    Ch := #0;
    Host.HandleInput(Key, [], Ch);
    Expect(Host.GetListSelectedText('font_size') = 'Size-12', 'Enter commits scrolled item');
  finally
    Host.Free;
  end;
end;

begin
  try
    TestAskSaveHotkey;
    TestReplaceAndEncoding;
    TestCodePageListLastRow;
    TestDropDownPopupScroll;
    Writeln('All EditorDialogs tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.Message);
      Halt(1);
    end;
  end;
end.
