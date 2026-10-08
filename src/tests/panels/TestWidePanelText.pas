unit TestWidePanelText;

{ Panel text with wide (CJK) characters is cut, padded and shortened by cells,
  not by characters, so columns keep their width. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWidePanelText = class
  public
    [Test] procedure TestPadRightCountsCells;
    [Test] procedure TestPadRightNeverSplitsWideCharacter;
    [Test] procedure TestEllipsizeKeepsNameWithinCells;
    [Test] procedure TestEllipsizeLeavesAsciiAlone;
    [Test] procedure TestRowNameFitsColumn;
    [Test] procedure TestCursorInfoLineFitsWidth;
    [Test] procedure TestWorkspaceTabHitTestUsesCells;
    [Test] procedure TestPanelTabTitleFitsCells;
  end;

implementation

uses
  System.SysUtils,
  uCharWidth, uPanelColumns, uDualPanelTypes, uDualPanelPanelDraw, uDualPanelTabs, uVfsTypes;

const
  cHan = #$6F22;
  cHira = #$3072;
  cKata = #$30AB;

function Repeated(const AText: string; ACount: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to ACount do
    Result := Result + AText;
end;

procedure TTestWidePanelText.TestPadRightCountsCells;
begin
  Assert.AreEqual(8, TextDisplayWidth(PadRight(cHan + cHira, 8)));
  Assert.AreEqual(cHan + cHira + '    ', PadRight(cHan + cHira, 8));
  Assert.AreEqual(5, TextDisplayWidth(PadRight('a' + cHan, 5)));
end;

procedure TTestWidePanelText.TestPadRightNeverSplitsWideCharacter;
begin
  // Three cells: the second wide character does not fit, a blank takes its place.
  Assert.AreEqual(cHan + ' ', PadRight(cHan + cHira + cKata, 3));
  Assert.AreEqual(cHan + cHira, PadRight(cHan + cHira + cKata, 4));
end;

procedure TTestWidePanelText.TestEllipsizeKeepsNameWithinCells;
var
  Name, Shortened: string;
begin
  Name := Repeated(cHan, 20) + '.txt';
  Shortened := EllipsizeKeepingExt(Name, 16);
  Assert.IsTrue(TextDisplayWidth(Shortened) <= 16, 'width ' + IntToStr(TextDisplayWidth(Shortened)));
  Assert.IsTrue(Shortened.EndsWith('.txt'), 'extension kept');
  Assert.IsTrue(Pos('...', Shortened) > 0, 'ellipsis present');
  // Short enough in characters, too wide in cells.
  Shortened := EllipsizeKeepingExt(Repeated(cHira, 10), 12);
  Assert.IsTrue(TextDisplayWidth(Shortened) <= 12);
  Assert.IsTrue(Pos('...', Shortened) > 0);
  // Fits: unchanged.
  Assert.AreEqual(Repeated(cHira, 5), EllipsizeKeepingExt(Repeated(cHira, 5), 10));
end;

procedure TTestWidePanelText.TestEllipsizeLeavesAsciiAlone;
begin
  Assert.AreEqual('short.txt', EllipsizeKeepingExt('short.txt', 40));
  Assert.AreEqual(12, Length(EllipsizeKeepingExt('VeryLongFileNameWithoutExt', 12)));
end;

procedure TTestWidePanelText.TestRowNameFitsColumn;
var
  Row: TPanelRow;
  Text: string;
begin
  Row := Default(TPanelRow);
  Row.Text := Repeated(cKata, 30) + '.dat';
  Row.Extension := '.dat';
  Text := FormatPanelRowName(Row, 20, False);
  Assert.AreEqual(20, TextDisplayWidth(Text), 'name column width');
  Text := FormatPanelRowName(Row, 21, True);
  Assert.AreEqual(21, TextDisplayWidth(Text), 'name column width without the extension');
end;

procedure TTestWidePanelText.TestCursorInfoLineFitsWidth;
var
  Row: TPanelRow;
  Line: string;
begin
  Row := Default(TPanelRow);
  Row.Text := Repeated(cHan, 40);
  Row.SizeText := '1234';
  Row.DateText := '2026-10-08';
  Line := FormatPanelCursorInfoLine(Row, 40);
  Assert.AreEqual(40, TextDisplayWidth(Line));
  Assert.IsTrue(Line.EndsWith('2026-10-08'));
end;

procedure TTestWidePanelText.TestWorkspaceTabHitTestUsesCells;
var
  Tabs: TArray<TDualPanelWorkspaceTab>;
  Index: Integer;
  IsClose: Boolean;
begin
  SetLength(Tabs, 2);
  Tabs[0].Title := cHan + cHira;
  Tabs[1].Title := 'b';
  // "[" + 4 cells + " x]" = 8 cells; the next tab starts after a one-cell gap.
  Assert.IsTrue(HitWorkspaceTabAtCol(Tabs, 7, Index, IsClose));
  Assert.AreEqual(0, Index);
  Assert.IsTrue(HitWorkspaceTabAtCol(Tabs, 9, Index, IsClose));
  Assert.AreEqual(1, Index, 'second tab starts after the first one in cells');
  Assert.IsTrue(HitWorkspaceTabAtCol(Tabs, 6, Index, IsClose));
  Assert.IsTrue(IsClose, 'close mark column counts cells');
  Assert.AreEqual(6, TabCaptionCloseCol(0, WorkspaceTabCaption(Tabs[0].Title, True), True, False));
  // 8 + gap + 5 + gap: where the [+] button starts.
  Assert.AreEqual(15, WorkspaceTabsEndCol(Tabs));
end;

procedure TTestWidePanelText.TestPanelTabTitleFitsCells;
var
  Title: string;
begin
  Title := VfsUriDirTabTitle('file:///C:/' + Repeated(cHan, 20), 12);
  Assert.IsTrue(TextDisplayWidth(Title) <= 12, 'width ' + IntToStr(TextDisplayWidth(Title)));
  Assert.IsTrue(Title.StartsWith('C:'), 'drive letter kept');
end;

end.
