unit TestPanelGrouping;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPanelGrouping = class
  public
    [Test] procedure NoGroupingGivesKeyZero;
    [Test] procedure ParentRowAndFoldersKeepTheirOwnKeys;
    [Test] procedure FileKindsMapToTypeGroups;
    [Test] procedure AgeClassesFollowTheCalendarDay;
    [Test] procedure RowsAreOrderedByGroupThenByTheSortColumn;
    [Test] procedure GroupingIsSavedInTheSession;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.DateUtils,
  uVfsTypes,
  uDualPanelTypes,
  uPanelColumns, uListExport,
  uSession;

function FileRow(const AName: string; AModified: TDateTime): TPanelRow;
begin
  Result := MakePanelRow(AName, False, 10);
  Result.ModificationTime := AModified;
end;

procedure TTestPanelGrouping.NoGroupingGivesKeyZero;
begin
  Assert.AreEqual(0, PanelRowGroupKey(pgbNone, FileRow('a.png', Now), Now));
end;

procedure TTestPanelGrouping.ParentRowAndFoldersKeepTheirOwnKeys;
var
  Parent, Dir: TPanelRow;
begin
  Parent := MakePanelRow('..', True, -1, '', '', '', True);
  Dir := MakePanelRow('sub', True);
  Assert.AreEqual(0, PanelRowGroupKey(pgbType, Parent, Now), 'parent by type');
  Assert.AreEqual(0, PanelRowGroupKey(pgbDate, Parent, Now), 'parent by date');
  Assert.AreEqual(1, PanelRowGroupKey(pgbType, Dir, Now), 'folder by type');
  Assert.AreEqual(1, PanelRowGroupKey(pgbDate, Dir, Now), 'folder by date');
end;

procedure TTestPanelGrouping.FileKindsMapToTypeGroups;
begin
  Assert.AreEqual(2, PanelRowGroupKey(pgbType, FileRow('Photo.JPG', Now), Now), 'image');
  Assert.AreEqual(3, PanelRowGroupKey(pgbType, FileRow('a.mp3', Now), Now), 'audio');
  Assert.AreEqual(4, PanelRowGroupKey(pgbType, FileRow('a.mkv', Now), Now), 'video');
  Assert.AreEqual(5, PanelRowGroupKey(pgbType, FileRow('a.pdf', Now), Now), 'document');
  Assert.AreEqual(6, PanelRowGroupKey(pgbType, FileRow('a.zip', Now), Now), 'archive');
  Assert.AreEqual(7, PanelRowGroupKey(pgbType, FileRow('a.exe', Now), Now), 'program');
  Assert.AreEqual(8, PanelRowGroupKey(pgbType, FileRow('a.pas', Now), Now), 'code');
  Assert.AreEqual(9, PanelRowGroupKey(pgbType, FileRow('a.unknown', Now), Now), 'other');
  Assert.AreEqual(9, PanelRowGroupKey(pgbType, FileRow('noext', Now), Now), 'no extension');
end;

procedure TTestPanelGrouping.AgeClassesFollowTheCalendarDay;
var
  Moment: TDateTime;
begin
  Moment := EncodeDateTime(2026, 6, 15, 12, 0, 0, 0);
  Assert.AreEqual(20, PanelRowGroupKey(pgbDate, FileRow('a', EncodeDateTime(2026, 6, 15, 0, 1, 0, 0)), Moment), 'today');
  Assert.AreEqual(21, PanelRowGroupKey(pgbDate, FileRow('a', EncodeDateTime(2026, 6, 14, 23, 0, 0, 0)), Moment), 'yesterday');
  Assert.AreEqual(22, PanelRowGroupKey(pgbDate, FileRow('a', EncodeDateTime(2026, 6, 10, 9, 0, 0, 0)), Moment), 'last 7 days');
  Assert.AreEqual(23, PanelRowGroupKey(pgbDate, FileRow('a', EncodeDateTime(2026, 5, 20, 9, 0, 0, 0)), Moment), 'last 30 days');
  Assert.AreEqual(24, PanelRowGroupKey(pgbDate, FileRow('a', EncodeDateTime(2025, 12, 1, 9, 0, 0, 0)), Moment), 'last year');
  Assert.AreEqual(25, PanelRowGroupKey(pgbDate, FileRow('a', EncodeDateTime(2020, 1, 1, 9, 0, 0, 0)), Moment), 'older');
  Assert.AreEqual(29, PanelRowGroupKey(pgbDate, FileRow('a', 0), Moment), 'no date');
end;

procedure TTestPanelGrouping.RowsAreOrderedByGroupThenByTheSortColumn;
var
  Rows: TPanelRows;
  I: Integer;
begin
  SetLength(Rows, 5);
  Rows[0] := FileRow('zeta.exe', Now);
  Rows[1] := FileRow('beta.png', Now);
  Rows[2] := FileRow('alpha.png', Now);
  Rows[3] := FileRow('doc.pdf', Now);
  Rows[4] := MakePanelRow('dir', True);
  for I := 0 to High(Rows) do
    Rows[I].GroupKey := PanelRowGroupKey(pgbType, Rows[I], Now);
  SortPanelRows(Rows, pscName, False, False, '', True);
  Assert.AreEqual('dir', Rows[0].Text, 'folders first');
  Assert.AreEqual('alpha.png', Rows[1].Text, 'images, by name');
  Assert.AreEqual('beta.png', Rows[2].Text, 'images, by name');
  Assert.AreEqual('doc.pdf', Rows[3].Text, 'documents');
  Assert.AreEqual('zeta.exe', Rows[4].Text, 'programs last although the name sorts last too');
end;

procedure TTestPanelGrouping.GroupingIsSavedInTheSession;
var
  Path: string;
  Saved, Loaded: TMtnSession;
  Tab: TTab;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2_grouping_session.json');
  Tab := MakeTab(1, 'C:', 'file:///C:/');
  Saved := Default(TMtnSession);
  Saved.Version := cSessionVersion;
  Saved.Zoom := 1;
  Saved.ListExport := DefaultListExportConfig;
  SetLength(Saved.Panels.WorkspaceTabs, 1);
  Saved.Panels.WorkspaceTabs[0].Id := 1;
  Saved.Panels.WorkspaceTabs[0].Title := 'Workspace';
  Saved.Panels.WorkspaceTabs[0].Kind := wkPanels;
  Saved.Panels.WorkspaceTabs[0].State.LeftVisible := True;
  Saved.Panels.WorkspaceTabs[0].State.RightVisible := True;
  SetLength(Saved.Panels.WorkspaceTabs[0].State.LeftPanel.Tabs, 1);
  Saved.Panels.WorkspaceTabs[0].State.LeftPanel.Tabs[0] := Tab;
  SetLength(Saved.Panels.WorkspaceTabs[0].State.RightPanel.Tabs, 1);
  Saved.Panels.WorkspaceTabs[0].State.RightPanel.Tabs[0] := Tab;
  Saved.Panels.WorkspaceTabs[0].State.LeftPanel.GroupBy := pgbDate;
  Saved.Panels.WorkspaceTabs[0].State.RightPanel.GroupBy := pgbType;
  try
    Assert.IsTrue(SaveSession(Path, Saved), 'save session');
    Assert.IsTrue(TryLoadSession(Path, Loaded), 'load session');
    Assert.IsTrue(Loaded.Panels.WorkspaceTabs[0].State.LeftPanel.GroupBy = pgbDate, 'left by date');
    Assert.IsTrue(Loaded.Panels.WorkspaceTabs[0].State.RightPanel.GroupBy = pgbType, 'right by type');
  finally
    if TFile.Exists(Path) then
      TFile.Delete(Path);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPanelGrouping);

end.
