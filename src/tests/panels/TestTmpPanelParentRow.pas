unit TestTmpPanelParentRow;

{ The Temporary panel is flat: it shows ".." only when the tab knows the place
  it was opened from. The top folder of a plugin scheme (docker:///, svc:///,
  ...) shows ".." back to the folder the panel was opened from, also for a tab
  that has no back marker (restored session, history step). }

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
    [Test] procedure TestPluginRootLeadsBackToTheFolderItWasOpenedFrom;
    [Test] procedure TestPluginRootWithoutMarkerTakesFolderFromHistory;
    [Test] procedure TestOnlyPluginRootsGetAReturnFolder;
    [Test] procedure TestWorkspaceRootLeadsBackToTheFolderItWasOpenedFrom;
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

function PluginTab(const AUri, ABack: string; const AHistory: TArray<string>;
  AIndex: Integer): TTab;
begin
  Result := Default(TTab);
  Result.CurrentURI := AUri;
  Result.WorkspaceBackUri := ABack;
  Result.History := AHistory;
  Result.HistoryIndex := AIndex;
end;

procedure TTestTmpPanelParentRow.TestPluginRootLeadsBackToTheFolderItWasOpenedFrom;
var
  Root: string;
  Rows: TPanelRows;
  Ret: string;
begin
  for Root in ['docker:///', 'svc:///', 'proc:///', 'reg:///', 'ftp:///', 'net:///'] do
  begin
    Ret := PluginRootReturnUri(PluginTab(Root, 'file:///C:/Work/', nil, -1));
    Assert.AreEqual('file:///C:/Work/', Ret, Root + ' returns to the folder the panel was opened from');
    Rows := RowsFromVfsItems(Root, OneItem, Ret);
    Assert.AreEqual(2, Integer(Length(Rows)), Root);
    Assert.IsTrue(Rows[0].IsParent, Root + ' starts with ".."');
    Assert.AreEqual('file:///C:/Work/', Rows[0].URI, Root);
  end;
end;

procedure TTestTmpPanelParentRow.TestPluginRootWithoutMarkerTakesFolderFromHistory;
var
  Tab: TTab;
begin
  Tab := PluginTab('docker:///', '',
    ['file:///C:/Old/', 'file:///C:/Work/', 'docker:///', 'docker:///containers', 'docker:///'], 4);
  Assert.AreEqual('file:///C:/Work/', PluginRootReturnUri(Tab), 'the nearest earlier local folder');
  Tab.HistoryIndex := 0;
  Assert.AreEqual('file:///C:/Old/', PluginRootReturnUri(Tab), 'history is read from the current step back');
  Assert.AreEqual('', PluginRootReturnUri(PluginTab('docker:///', '', ['docker:///'], 0)),
    'no earlier folder: no way back');
end;

procedure TTestTmpPanelParentRow.TestOnlyPluginRootsGetAReturnFolder;
begin
  Assert.AreEqual('', PluginRootReturnUri(PluginTab('docker:///containers', 'file:///C:/Work/', nil, -1)),
    'a deeper folder goes up by its own parent');
  Assert.AreEqual('', PluginRootReturnUri(PluginTab('file:///C:/Work/', 'file:///C:/Other/', nil, -1)),
    'a local folder is not a plugin root');
end;

procedure TTestTmpPanelParentRow.TestWorkspaceRootLeadsBackToTheFolderItWasOpenedFrom;
var
  Tab: TTab;
  Rows: TPanelRows;
  Ret: string;
begin
  Tab := PluginTab('ws:///', '', ['file:///C:/Old/', 'file:///C:/Work/', 'ws:///'], 2);
  Assert.AreEqual('file:///C:/Work/', PluginRootReturnUri(Tab), 'history gives the folder');
  Tab.WorkspaceOriginUri := 'file:///C:/Other/';
  Ret := PluginRootReturnUri(Tab);
  Assert.AreEqual('file:///C:/Other/', Ret, 'the remembered origin wins');
  Rows := RowsFromVfsItems('ws:///', OneItem, Ret);
  Assert.IsTrue(Rows[0].IsParent, 'Workspace starts with ".."');
  Assert.AreEqual('file:///C:/Other/', Rows[0].URI);
  Assert.AreEqual('', PluginRootReturnUri(PluginTab('ws:///', '', ['ws:///'], 0)),
    'no earlier folder: no way back');
end;

procedure TTestTmpPanelParentRow.TestRowKnowsItsFolder;
var
  Items: TArray<TVfsEntry>;
  Rows: TPanelRows;
begin
  Items := OneItem;
{$IFDEF MSWINDOWS}
  Items[0].TargetURI := 'file:///C:/Work/Docs/a.txt';
  Rows := RowsFromVfsItems('tmp:///', Items);
  Assert.AreEqual('C:\Work\Docs', Rows[0].DirText);
{$ELSE}
  Items[0].TargetURI := 'file:///work/docs/a.txt';
  Rows := RowsFromVfsItems('tmp:///', Items);
  Assert.AreEqual('/work/docs', Rows[0].DirText);
{$ENDIF}
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
