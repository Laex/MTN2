unit TestEditorDialogs;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorDialogs = class
  public
    [Test] procedure TestAskSaveHotkey;
    [Test] procedure TestReplaceAndEncoding;
    [Test] procedure TestCodePageListLastRow;
    [Test] procedure TestDropDownPopupScroll;
  end;

implementation

uses
  System.SysUtils, System.UITypes,
  uDialogTypes,
  uTextEncoding,
  uEditorDialogs,
  uTerminalTypes,
  uDialogHost;

procedure TestAskSaveHotkey;
begin
  Assert.IsTrue(EditorAskSaveHotkey(Ord('Y'), #0) = cDlgCmdYes, 'Y key is Yes');
  Assert.IsTrue(EditorAskSaveHotkey(Ord('S'), #0) = cDlgCmdYes, 'S key is Yes');
  Assert.IsTrue(EditorAskSaveHotkey(Ord('N'), #0) = cDlgCmdNo, 'N key is No');
  Assert.IsTrue(EditorAskSaveHotkey(Ord('D'), #0) = cDlgCmdNo, 'D key is No');
  Assert.IsTrue(EditorAskSaveHotkey(0, 'y') = cDlgCmdYes, 'typed y is Yes');
  Assert.IsTrue(EditorAskSaveHotkey(0, #$0414) = cDlgCmdYes, 'Cyrillic D is Yes');
  Assert.IsTrue(EditorAskSaveHotkey(0, #$043D) = cDlgCmdNo, 'Cyrillic n is No');
  Assert.IsTrue(EditorAskSaveHotkey(vkEscape, #0) = '', 'Esc is not a letter hotkey');
  Assert.IsTrue(EditorAskSaveHotkey(vkF10, #0) = '', 'F10 (= Ord(''y'')) is not Yes');
  Assert.IsTrue(EditorAskSaveHotkey(vkF4, #0) = '', 'F4 (= Ord(''s'')) is not Yes');
  Assert.IsTrue(EditorAskSaveHotkey(vkNumpad4, #0) = '', 'Num4 (= Ord(''d'')) is not No');
  Assert.IsTrue(EditorAskSaveAction(cDlgCmdYes) = esaYes, 'yes cmd');
  Assert.IsTrue(EditorAskSaveAction(cDlgCmdNo) = esaNo, 'no cmd');
  Assert.IsTrue(EditorAskSaveAction(cDlgCmdCancel) = esaCancel, 'cancel cmd');
  Assert.IsTrue(EditorAskSaveAction('') = esaCancel, 'empty is cancel');
end;

procedure TestReplaceAndEncoding;
var
  Name: string;
  Idx: Integer;
begin
  Assert.IsTrue(EditorReplaceAction(cDlgCmdReplaceOne) = eraOne, 'replace one');
  Assert.IsTrue(EditorReplaceAction(cDlgCmdReplaceAll) = eraAll, 'replace all');
  Assert.IsTrue(EditorReplaceAction(cDlgCmdCancel) = eraNone, 'cancel is none');
  Assert.IsTrue(EditorReplaceShouldRun(cDlgCmdReplaceOne, 'foo'), 'one with needle runs');
  Assert.IsTrue(EditorReplaceShouldRun(cDlgCmdReplaceAll, 'foo'), 'all with needle runs');
  Assert.IsTrue(not EditorReplaceShouldRun(cDlgCmdReplaceOne, ''), 'empty find does not run');
  Assert.IsTrue(not EditorReplaceShouldRun(cDlgCmdReplaceOne, '   '), 'blank find does not run');
  Assert.IsTrue(not EditorReplaceShouldRun(cDlgCmdCancel, 'foo'), 'cancel does not run');
  Assert.IsTrue(EditorEncodingAccepted(cDlgCmdOk), 'ok accepts encoding');
  Assert.IsTrue(EditorEncodingAccepted(cDlgCmdYes), 'yes accepts encoding');
  Assert.IsTrue(EditorEncodingAccepted('encoding'), 'list id accepts encoding');
  Assert.IsTrue(not EditorEncodingAccepted(cDlgCmdCancel), 'cancel rejects encoding');

  Name := 'keep';
  Idx := 7;
  EditorMergeEncodingJson('', Name, Idx);
  Assert.IsTrue(Name = 'keep', 'empty json keeps name');
  Assert.IsTrue(Idx = 7, 'empty json keeps index');

  EditorMergeEncodingJson('{"encoding":"UTF-8"}', Name, Idx);
  Assert.IsTrue(Name = 'UTF-8', 'string encoding overwrites name');
  Assert.IsTrue(Idx = 7, 'string encoding leaves index');

  EditorMergeEncodingJson('{"encoding":2}', Name, Idx);
  Assert.IsTrue(Idx = 2, 'numeric encoding overwrites index');
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
    Assert.IsTrue(GridHasText(Grid, 'OEM'), 'all 6 encodings visible including last (OEM)');

    for I := 1 to High(Items) do
    begin
      Key := vkDown;
      Ch := #0;
      Host.HandleInput(Key, [], Ch);
    end;
    Key := vkDown;
    Ch := #0;
    Host.HandleInput(Key, [], Ch);
    Assert.IsTrue(Host.GetListSelectedText('encoding') = 'OEM',
      'Down past last item stays on OEM');
    ClearTerminalGrid(Grid, $FF000000, $FFFFFFFF, ' ');
    Host.Draw(Grid, 80, 25);
    Assert.IsTrue(GridHasText(Grid, 'OEM'), 'OEM still drawn after Down on last row');

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
    Assert.IsTrue(Host.GetListSelectedIndex('encoding') = 7, 'scrolled selection is item 7');
    Assert.IsTrue(Host.GetListSelectedText('encoding') = 'Row-7', 'scrolled selection text is Row-7');
    ClearTerminalGrid(Grid, $FF000000, $FFFFFFFF, ' ');
    Host.Draw(Grid, 80, 25);
    Assert.IsTrue(GridHasText(Grid, 'Row-7'), 'scrolled list draws the selected row');
    Assert.IsTrue(not GridHasText(Grid, 'Row-0'), 'first row scrolled out of view');
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
    Assert.IsTrue(GridHasText(Grid, 'Size-5'), 'open popup shows the selected size');
    Assert.IsTrue(not GridHasText(Grid, 'Size-12'), 'popup is clipped; last sizes start off-screen');

    Key := vkEnd;
    Ch := #0;
    Host.HandleInput(Key, [], Ch);
    ClearTerminalGrid(Grid, $FF000000, $FFFFFFFF, ' ');
    Host.Draw(Grid, 80, 25);
    Assert.IsTrue(GridHasText(Grid, 'Size-12'), 'End scrolls popup to last size');
    Assert.IsTrue(not GridHasText(Grid, 'Size-0'), 'first size scrolled out after End');

    Key := vkReturn;
    Ch := #0;
    Host.HandleInput(Key, [], Ch);
    Assert.IsTrue(Host.GetListSelectedText('font_size') = 'Size-12', 'Enter commits scrolled item');
  finally
    Host.Free;
  end;
end;

{ TTestEditorDialogs }

procedure TTestEditorDialogs.TestAskSaveHotkey;
begin
  TestEditorDialogs.TestAskSaveHotkey;
end;

procedure TTestEditorDialogs.TestReplaceAndEncoding;
begin
  TestEditorDialogs.TestReplaceAndEncoding;
end;

procedure TTestEditorDialogs.TestCodePageListLastRow;
begin
  TestEditorDialogs.TestCodePageListLastRow;
end;

procedure TTestEditorDialogs.TestDropDownPopupScroll;
begin
  TestEditorDialogs.TestDropDownPopupScroll;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorDialogs);

end.
