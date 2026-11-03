unit TestTmpPanelParentRow;

{ The Temporary panel is flat: it shows ".." only when the tab knows the place
  it was opened from. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTmpPanelParentRow = class
  public
    [Test] procedure TestNoParentRowWithoutReturnFolder;
    [Test] procedure TestParentRowLeadsBackToReturnFolder;
    [Test] procedure TestPluginSchemeFolderLeadsBackToReturnFolder;
    [Test] procedure TestRowKnowsItsFolder;
    [Test] procedure TestNameCellShowsFolderAfterName;
    [Test] procedure TestNameCellWithoutFolderIsJustTheName;
  end;

implementation

uses
  System.SysUtils, uVfsTypes, uDualPanelTypes, uPanelColumns;

function OneItem: TArray<TVfsEntry>;
begin
  SetLength(Result, 1);
  Result[0] := Default(TVfsEntry);
  Result[0].Name := 'a.txt';
end;

procedure TTestTmpPanelParentRow.TestNoParentRowWithoutReturnFolder;
var
  Rows: TPanelRows;
begin
  Rows := RowsFromVfsItems('tmp:///', OneItem);
  Assert.AreEqual(1, Integer(Length(Rows)));
  Assert.IsFalse(Rows[0].IsParent);
end;

procedure TTestTmpPanelParentRow.TestParentRowLeadsBackToReturnFolder;
var
  Rows: TPanelRows;
begin
  Rows := RowsFromVfsItems('tmp:///', OneItem, 'file:///C:/Work/');
  Assert.AreEqual(2, Integer(Length(Rows)));
  Assert.IsTrue(Rows[0].IsParent, '".." comes first');
  Assert.AreEqual('file:///C:/Work/', Rows[0].URI);
  Assert.IsFalse(Rows[1].IsParent);
end;

procedure TTestTmpPanelParentRow.TestPluginSchemeFolderLeadsBackToReturnFolder;
var
  Rows: TPanelRows;
begin
  Rows := RowsFromVfsItems('net://work/dir', OneItem, 'file:///C:/Work/');
  Assert.AreEqual(2, Integer(Length(Rows)));
  Assert.IsTrue(Rows[0].IsParent);
  Assert.AreEqual('file:///C:/Work/', Rows[0].URI, 'a plugin folder entered mid-tree still leads back');
  Rows := ErrorRows('net://work/dir', 'down', 'file:///C:/Work/');
  Assert.AreEqual('file:///C:/Work/', Rows[0].URI, 'an error listing keeps the way back');
end;

procedure TTestTmpPanelParentRow.TestRowKnowsItsFolder;
var
  Items: TArray<TVfsEntry>;
  Rows: TPanelRows;
begin
  Items := OneItem;
  Items[0].TargetURI := 'file:///C:/Work/Docs/a.txt';
  Rows := RowsFromVfsItems('tmp:///', Items);
  Assert.AreEqual('C:\Work\Docs', Rows[0].DirText);
  Rows := RowsFromVfsItems('file:///C:/Work/', OneItem);
  Assert.AreEqual('', Rows[0].DirText, 'ordinary folders show no extra path');
end;

procedure TTestTmpPanelParentRow.TestNameCellShowsFolderAfterName;
var
  Row: TPanelRow;
  Cell: string;
begin
  Row := MakePanelRow('a.txt', False);
  Row.DirText := 'C:\Work\Docs';
  Cell := FormatPanelRowName(Row, 40);
  Assert.AreEqual(40, Length(Cell));
  Assert.IsTrue(Pos('a.txt', Cell) = 1);
  Assert.IsTrue(Pos('C:\Work\Docs', Cell) > 1);
  Row.DirText := 'C:\Very\Long\Folder\Name\That\Does\Not\Fit\Anywhere';
  Cell := FormatPanelRowName(Row, 40);
  Assert.AreEqual(40, Length(Cell));
  Assert.IsTrue(Pos('...', Cell) > 0, 'a long folder is shortened from the left');
  Assert.IsTrue(Pos('Anywhere', Cell) > 0, 'the end of the folder stays visible');
end;

procedure TTestTmpPanelParentRow.TestNameCellWithoutFolderIsJustTheName;
var
  Row: TPanelRow;
begin
  Row := MakePanelRow('a.txt', False);
  Assert.AreEqual('a.txt' + StringOfChar(' ', 35), FormatPanelRowName(Row, 40));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTmpPanelParentRow);

end.
