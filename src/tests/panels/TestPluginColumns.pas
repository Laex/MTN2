unit TestPluginColumns;

{ Plugin columns of the file panel: declaration, per-scheme selection, the
  "extra" cells of a listing, formatting, sorting and the session. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginColumns = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestDeclaredColumnsAreClampedAndDeduplicated;
    [Test] procedure TestSelectionDefaultsToDefaultColumns;
    [Test] procedure TestSelectionRoundTripsThroughJson;
    [Test] procedure TestRemovePluginDropsItsColumns;
    [Test] procedure TestListingExtraCells;
    [Test] procedure TestCustomDefsAppendShownPluginColumns;
    [Test] procedure TestNarrowPanelDropsTrailingColumns;
    [Test] procedure TestRowMetaShowsPluginCells;
    [Test] procedure TestFolderCellsFillRowsWithoutListingValue;
    [Test] procedure TestSortByNumericPluginColumn;
    [Test] procedure TestSortByTextPluginColumn;
    [Test] procedure TestHeaderHitFindsPluginColumn;
    [Test] procedure TestHeaderSortCyclesPerPluginColumn;
    [Test] procedure TestColumnsDialogListsPluginColumns;
    [Test] procedure TestPluginRestrictsBuiltinColumns;
    [Test] procedure TestColumnTitlesFollowTheProgramLanguage;
    [Test] procedure TestSessionKeepsPluginSortAndSelection;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uVfsTypes, uVfsCdeclAdapter, uDialogTypes, uDualPanelTypes, uPanelColumns, uPluginColumns, uPluginServices, uStrings,
  uDialogLocaleLayout, uSession;

const
  cScheme = 'demo';
  cDeclared =
    '[{"id":"state","title":"State","width":8,"default":true},' +
    '{"id":"pid","title":"PID","width":6,"align":"right","default":true},' +
    '{"id":"note","title":"Note","width":12,"default":false,"sortable":false}]';

procedure TTestPluginColumns.Setup;
begin
  SetSchemePluginColumns('mtn.test', cScheme, cDeclared);
  ClearSchemeColumnSelections;
  GCustomColumnsConfig := DefaultCustomColumnsConfig;
end;

procedure TTestPluginColumns.TearDown;
begin
  RemovePluginColumns('mtn.test');
  ClearSchemeColumnSelections;
end;

procedure TTestPluginColumns.TestDeclaredColumnsAreClampedAndDeduplicated;
var
  Cols: TPluginColumns;
begin
  SetSchemePluginColumns('mtn.test', cScheme,
    '[{"id":"a","title":"A","width":1},{"id":"a","title":"again"},' +
    '{"title":"no id"},{"id":"b","width":500,"align":"right"}]');
  Cols := SchemePluginColumns(cScheme);
  Assert.AreEqual<Integer>(2, Length(Cols), 'repeated and id-less entries are skipped');
  Assert.AreEqual(cPluginColumnMinWidth, Cols[0].Width, 'width is raised to the minimum');
  Assert.AreEqual(cPluginColumnMaxWidth, Cols[1].Width, 'width is cut to the maximum');
  Assert.IsTrue(Cols[1].AlignRight, 'align right');
  Assert.IsTrue(Cols[0].Sortable, 'sortable by default');
  Assert.AreEqual('b', Cols[1].Title, 'the id is the title when none is given');
  Assert.AreEqual<Integer>(2, Length(SchemePluginColumns(UpperCase(cScheme))), 'scheme is case-insensitive');
end;

procedure TTestPluginColumns.TestSelectionDefaultsToDefaultColumns;
var
  Shown: TPluginColumns;
begin
  Shown := ShownPluginColumns(cScheme);
  Assert.AreEqual<Integer>(2, Length(Shown), 'only default columns before any choice');
  Assert.AreEqual('state', Shown[0].Id);
  Assert.AreEqual('pid', Shown[1].Id);

  SetSchemeColumnSelection(cScheme, ['note']);
  Shown := ShownPluginColumns(cScheme);
  Assert.AreEqual<Integer>(1, Length(Shown), 'the choice replaces the defaults');
  Assert.AreEqual('note', Shown[0].Id);

  SetSchemeColumnSelection(cScheme, []);
  Assert.AreEqual<Integer>(0, Length(ShownPluginColumns(cScheme)), 'an empty choice shows none');
  Assert.AreEqual<Integer>(0, Length(ShownPluginColumns('other')), 'another scheme is unaffected');
end;

procedure TTestPluginColumns.TestSelectionRoundTripsThroughJson;
var
  Json: string;
begin
  SetSchemeColumnSelection(cScheme, ['pid', 'note']);
  Json := SchemeColumnSelectionsToJson;
  ClearSchemeColumnSelections;
  Assert.AreEqual<Integer>(2, Length(ShownPluginColumns(cScheme)), 'defaults again after clearing');
  LoadSchemeColumnSelectionsFromJson(Json);
  Assert.AreEqual<Integer>(2, Length(ShownPluginColumns(cScheme)));
  Assert.AreEqual('pid', ShownPluginColumns(cScheme)[0].Id);
  Assert.AreEqual('note', ShownPluginColumns(cScheme)[1].Id);
  LoadSchemeColumnSelectionsFromJson('not json');
  Assert.AreEqual<Integer>(2, Length(ShownPluginColumns(cScheme)), 'unparsable text leaves the defaults');
end;

procedure TTestPluginColumns.TestRemovePluginDropsItsColumns;
begin
  Assert.AreEqual<Integer>(3, Length(SchemePluginColumns(cScheme)));
  RemovePluginColumns('mtn.test');
  Assert.AreEqual<Integer>(0, Length(SchemePluginColumns(cScheme)));
  SetSchemePluginColumns('mtn.test', cScheme, cDeclared);
  SetSchemePluginColumns('mtn.test', cScheme, '');
  Assert.AreEqual<Integer>(0, Length(SchemePluginColumns(cScheme)), 'an empty declaration removes the columns');
end;

procedure TTestPluginColumns.TestListingExtraCells;
var
  Entries: TArray<TVfsEntry>;
begin
  Entries := EntriesFromJson(
    '[{"name":"a","size":1,"isDir":false,"extra":{"state":"run","pid":{"t":"042","n":42},"cnt":7}},' +
    '{"name":"b","size":2,"isDir":false}]');
  Assert.AreEqual<Integer>(2, Length(Entries));
  Assert.AreEqual<Integer>(3, Length(Entries[0].Extra));
  Assert.AreEqual('run', Entries[0].Extra[0].Text);
  Assert.IsFalse(Entries[0].Extra[0].Numeric, 'a string cell is text');
  Assert.AreEqual('042', Entries[0].Extra[1].Text, 'the shown text is kept');
  Assert.IsTrue(Entries[0].Extra[1].Numeric);
  Assert.AreEqual(42.0, Entries[0].Extra[1].Num, 0.0001);
  Assert.IsTrue(Entries[0].Extra[2].Numeric, 'a bare number is numeric');
  Assert.AreEqual('7', Entries[0].Extra[2].Text);
  Assert.AreEqual<Integer>(0, Length(Entries[1].Extra), 'no extra object, no cells');
end;

procedure TTestPluginColumns.TestCustomDefsAppendShownPluginColumns;
var
  Plain, WithPlugin: TCustomColumnDefs;
begin
  Plain := BuildCustomColumnDefs(GCustomColumnsConfig);
  WithPlugin := BuildCustomColumnDefs(GCustomColumnsConfig, cScheme);
  Assert.AreEqual<Integer>(Length(Plain) + 2, Length(WithPlugin));
  Assert.AreEqual('state', WithPlugin[High(WithPlugin) - 1].PluginId);
  Assert.IsTrue(WithPlugin[High(WithPlugin) - 1].SortCol = pscPlugin);
  Assert.AreEqual('pid', WithPlugin[High(WithPlugin)].PluginId);
  Assert.IsTrue(WithPlugin[High(WithPlugin)].AlignRight);

  SetSchemeColumnSelection(cScheme, ['note']);
  WithPlugin := BuildCustomColumnDefs(GCustomColumnsConfig, cScheme);
  Assert.AreEqual('note', WithPlugin[High(WithPlugin)].PluginId);
  Assert.IsTrue(WithPlugin[High(WithPlugin)].SortCol = pscNone, 'a column that cannot be sorted');
end;

procedure TTestPluginColumns.TestNarrowPanelDropsTrailingColumns;
var
  Wide, Narrow: TCustomColumnDefs;
  I, Total: Integer;
begin
  Wide := BuildCustomColumnDefs(GCustomColumnsConfig, cScheme, MaxPanelMetaWidth(200));
  Assert.AreEqual<Integer>(Length(BuildCustomColumnDefs(GCustomColumnsConfig, cScheme)), Length(Wide),
    'a wide panel keeps every column');

  Narrow := BuildCustomColumnDefs(GCustomColumnsConfig, cScheme, MaxPanelMetaWidth(40));
  Assert.IsTrue(Length(Narrow) < Length(Wide), 'a narrow panel drops columns');
  Total := 0;
  for I := 0 to High(Narrow) do
    Inc(Total, Narrow[I].Width + Ord(I > 0));
  Assert.IsTrue(Total <= MaxPanelMetaWidth(40), 'the kept columns fit beside the name');
  if Length(Narrow) > 0 then
    Assert.AreEqual(Wide[0].Title, Narrow[0].Title, 'leading columns are kept');
end;

function RowWithCells(const AName: string; const ACells: TVfsExtraCells): TPanelRow;
begin
  Result := MakePanelRow(AName, False, 10, '10', '2025-01-01 10:00');
  Result.Extra := ACells;
end;

function TextCell(const AId, AText: string): TVfsExtraCell;
begin
  Result := Default(TVfsExtraCell);
  Result.Id := AId;
  Result.Text := AText;
end;

function NumberCell(const AId: string; AValue: Integer): TVfsExtraCell;
begin
  Result := Default(TVfsExtraCell);
  Result.Id := AId;
  Result.Text := IntToStr(AValue);
  Result.Num := AValue;
  Result.Numeric := True;
end;

procedure TTestPluginColumns.TestRowMetaShowsPluginCells;
var
  Row: TPanelRow;
  Meta, NoPlugin: string;
begin
  Row := RowWithCells('svc', [TextCell('state', 'Running'), NumberCell('pid', 77)]);
  Meta := FormatPanelRowMeta(pcmCustom, Row, 200, cScheme);
  NoPlugin := FormatPanelRowMeta(pcmCustom, Row, 200, '');
  Assert.IsTrue(Pos('Running', Meta) > 0, 'text cell is shown');
  Assert.IsTrue(Pos('    77', Meta) > 0, 'right-aligned number is padded on the left');
  Assert.IsTrue(Pos('Running', NoPlugin) = 0, 'no plugin columns without the scheme');
end;

procedure TTestPluginColumns.TestFolderCellsFillRowsWithoutListingValue;
var
  Row, Own: TPanelRow;
  Text: string;
begin
  SetFolderCells('mtn.test', 'file:///C:/Pics/', '{"a.jpg":{"state":"ready"}}');
  Assert.IsTrue(FolderCellText('FILE:///c:/pics', 'a.jpg', 'state', Text), 'folder key ignores case and the last slash');
  Assert.AreEqual('ready', Text);
  Assert.IsFalse(FolderCellText('file:///C:/Pics/', 'b.jpg', 'state', Text));
  Assert.IsFalse(FolderCellText('file:///C:/Other/', 'a.jpg', 'state', Text));

  Row := RowWithCells('a.jpg', nil);
  Assert.IsTrue(Pos('ready', FormatPanelRowMeta(pcmCustom, Row, 200, cScheme, 'file:///C:/Pics/')) > 0,
    'the cell fills the row');
  Own := RowWithCells('a.jpg', [TextCell('state', 'own')]);
  Assert.IsTrue(Pos('ready', FormatPanelRowMeta(pcmCustom, Own, 200, cScheme, 'file:///C:/Pics/')) = 0,
    'the listing value wins');

  SetFolderCells('mtn.test', 'file:///C:/Pics/', '');
  Assert.IsFalse(FolderCellText('file:///C:/Pics/', 'a.jpg', 'state', Text), 'an empty call drops the cells');
  SetFolderCells('mtn.test', 'file:///C:/Pics/', '{"a.jpg":{"state":"x"}}');
  RemovePluginColumns('mtn.test');
  Assert.IsFalse(FolderCellText('file:///C:/Pics/', 'a.jpg', 'state', Text), 'unloading the plugin drops the cells');
end;

function Names(const ARows: TPanelRows): string;
var
  R: TPanelRow;
begin
  Result := '';
  for R in ARows do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + R.Text;
  end;
end;

procedure TTestPluginColumns.TestSortByNumericPluginColumn;
var
  Rows: TPanelRows;
begin
  SetLength(Rows, 4);
  Rows[0] := RowWithCells('ten', [NumberCell('pid', 10)]);
  Rows[1] := RowWithCells('nine', [NumberCell('pid', 9)]);
  Rows[2] := RowWithCells('hundred', [NumberCell('pid', 100)]);
  Rows[3] := RowWithCells('none', nil);
  SortPanelRows(Rows, pscPlugin, False, False, 'pid');
  Assert.AreEqual('none,nine,ten,hundred', Names(Rows), 'numbers sort by value, a missing cell first');
  SortPanelRows(Rows, pscPlugin, True, False, 'pid');
  Assert.AreEqual('hundred,ten,nine,none', Names(Rows), 'descending');
end;

procedure TTestPluginColumns.TestSortByTextPluginColumn;
var
  Rows: TPanelRows;
begin
  SetLength(Rows, 3);
  Rows[0] := RowWithCells('r1', [TextCell('state', 'job10')]);
  Rows[1] := RowWithCells('r2', [TextCell('state', 'job2')]);
  Rows[2] := RowWithCells('r3', [TextCell('state', 'Alpha')]);
  SortPanelRows(Rows, pscPlugin, False, False, 'state');
  Assert.AreEqual('r3,r2,r1', Names(Rows), 'natural text order');
end;

procedure TTestPluginColumns.TestHeaderHitFindsPluginColumn;
  // The relative column of the first cell of the column PluginId.
  function ColumnStart(const APluginId: string): Integer;
  var
    Defs: TCustomColumnDefs;
    NameW, MetaW, I: Integer;
  begin
    PanelColumnWidths(pcmCustom, 120, NameW, MetaW, cScheme);
    Defs := BuildCustomColumnDefs(GCustomColumnsConfig, cScheme, MaxPanelMetaWidth(120));
    Result := PanelIconReserve + NameW + 1;
    for I := 0 to High(Defs) do
    begin
      if Defs[I].PluginId = APluginId then
        Exit;
      Inc(Result, Defs[I].Width + 1);
    end;
    Result := -1;
  end;

var
  Col: TPanelSortColumn;
  PluginId: string;
begin
  Assert.IsTrue(HitPanelSortColumn(pcmCustom, 120, ColumnStart('pid') + 1, cScheme, Col, PluginId),
    'a hit on a plugin column');
  Assert.IsTrue(Col = pscPlugin);
  Assert.AreEqual('pid', PluginId);
  Assert.IsTrue(HitPanelSortColumn(pcmCustom, 120, ColumnStart('state'), cScheme, Col, PluginId));
  Assert.AreEqual('state', PluginId);

  SetSchemeColumnSelection(cScheme, ['note']);
  Assert.IsFalse(HitPanelSortColumn(pcmCustom, 120, ColumnStart('note') + 1, cScheme, Col, PluginId),
    'a column that cannot be sorted gives no hit');
end;

procedure TTestPluginColumns.TestHeaderSortCyclesPerPluginColumn;
var
  Col: TPanelSortColumn;
  Id: string;
  Desc: Boolean;
begin
  Col := pscName;
  Id := '';
  Desc := False;
  CycleHeaderSort(Col, Id, Desc, pscPlugin, 'state');
  Assert.IsTrue(Col = pscPlugin);
  Assert.AreEqual('state', Id);
  Assert.IsFalse(Desc, 'first click ascending');
  CycleHeaderSort(Col, Id, Desc, pscPlugin, 'pid');
  Assert.AreEqual('pid', Id, 'another plugin column is a new column');
  Assert.IsFalse(Desc, 'ascending again');
  CycleHeaderSort(Col, Id, Desc, pscPlugin, 'pid');
  Assert.IsTrue(Desc, 'same column toggles direction');
  CycleHeaderSort(Col, Id, Desc, pscName, '');
  Assert.IsTrue(Col = pscName);
  Assert.AreEqual('', Id, 'the plugin id is cleared for a built-in column');
end;

function ControlById(const ADecl: TDialogDeclaration; const AId: string): TDialogControl;
var
  C: TDialogControl;
begin
  for C in ADecl.Controls do
    if C.Id = AId then
      Exit(C);
  Result := Default(TDialogControl);
  Result.Row := -1;
end;

procedure TTestPluginColumns.TestColumnsDialogListsPluginColumns;
var
  Plain, Decl: TDialogDeclaration;
begin
  Plain := BuildColumnsConfigDialog(False, True, True, False, False, False, True);
  Decl := BuildColumnsConfigDialog(False, True, True, False, False, False, True, cScheme);
  Assert.AreEqual<Integer>(Length(Plain.Controls) + 3, Length(Decl.Controls), 'one checkbox per declared column');
  Assert.AreEqual<Integer>(Plain.Height + 3, Decl.Height, 'the dialog grows by one row each');
  Assert.IsTrue(ControlById(Decl, 'pcol_0').Checked, 'a default column is checked');
  Assert.IsTrue(ControlById(Decl, 'pcol_1').Checked);
  Assert.IsFalse(ControlById(Decl, 'pcol_2').Checked, 'a column that is not default is not');
  Assert.AreEqual<Integer>(ControlById(Decl, 'col_attr').Row + 1, ControlById(Decl, 'pcol_0').Row,
    'plugin columns follow the built-in ones');
  Assert.AreEqual<Integer>(ControlById(Plain, 'ok').Row + 3, ControlById(Decl, 'ok').Row,
    'the buttons move down');
  SetSchemeColumnSelection(cScheme, ['note']);
  Decl := BuildColumnsConfigDialog(False, True, True, False, False, False, True, cScheme);
  Assert.IsFalse(ControlById(Decl, 'pcol_0').Checked, 'the saved choice is shown');
  Assert.IsTrue(ControlById(Decl, 'pcol_2').Checked);
end;

procedure TTestPluginColumns.TestColumnTitlesFollowTheProgramLanguage;
var
  Dir, PackDir: string;
  Decl: TDialogDeclaration;
  Defs: TCustomColumnDefs;
  Cfg: TCustomColumnsConfig;
  I: Integer;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-plugin-col-' + TGUID.NewGuid.ToString);
  PackDir := TPath.Combine(Dir, 'resource' + PathDelim + 'ru');
  ForceDirectories(PackDir);
  TFile.WriteAllText(TPath.Combine(PackDir, 'locale.json'), '{"version":1}', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(PackDir, 'strings.json'),
    '{"ui":{"col":{"state":"Состояние"}}}', TEncoding.UTF8);
  PluginSetResources('mtn.test', Dir, 1);
  SetSchemePluginColumns('mtn.test', cScheme,
    '[{"id":"state","title":"State","title_key":"ui.col.state","width":10},' +
    '{"id":"pid","title":"PID","width":6}]');
  try
    SetLocale('');
    Decl := BuildColumnsConfigDialog(False, True, True, False, False, False, True, cScheme);
    Assert.AreEqual('State', ControlById(Decl, 'pcol_0').Text, 'English: the declared title');
    SetLocale('ru');
    Decl := BuildColumnsConfigDialog(False, True, True, False, False, False, True, cScheme);
    Assert.AreEqual('Состояние', ControlById(Decl, 'pcol_0').Text, 'the dialog shows the translated title');
    Assert.AreEqual('PID', ControlById(Decl, 'pcol_1').Text, 'a column without a key keeps its title');
    Assert.AreNotEqual('&Size', ControlById(Decl, 'col_size').Text, 'the built-in labels are translated');
    Assert.IsFalse(DialogCaptionsOverflow(Decl), 'the translated labels fit the dialog');
    Cfg := DefaultCustomColumnsConfig;
    Defs := BuildCustomColumnDefs(Cfg, cScheme);
    for I := 0 to High(Defs) do
      if Defs[I].PluginId = 'state' then
        Assert.AreEqual('Состояние', Defs[I].Title, 'the panel header is translated');
    Assert.AreEqual('Состояние', PanelSortColumnCaption(pscPlugin, cScheme, 'state'),
      'the sort menu is translated');
  finally
    SetLocale('');
    PluginEventsUnregister('mtn.test');
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestPluginColumns.TestPluginRestrictsBuiltinColumns;
var
  Cfg: TCustomColumnsConfig;
  Defs: TCustomColumnDefs;
  Plain, Decl: TDialogDeclaration;
  I: Integer;
begin
  Assert.IsTrue(BuiltinColumnAvailable(cScheme, 'attr'), 'an array declaration keeps every built-in column');
  SetSchemePluginColumns('mtn.test', cScheme,
    '{"builtin":["size","modified"],"columns":' + cDeclared + '}');
  Assert.IsTrue(BuiltinColumnAvailable(cScheme, 'Size'));
  Assert.IsFalse(BuiltinColumnAvailable(cScheme, 'attr'));
  Assert.IsTrue(BuiltinColumnAvailable('other', 'attr'), 'other schemes are not restricted');
  Assert.AreEqual<Integer>(3, Length(SchemePluginColumns(cScheme)));

  Cfg := DefaultCustomColumnsConfig;
  Cfg.ShowExt := True;
  Cfg.ShowAttr := True;
  Defs := BuildCustomColumnDefs(Cfg, cScheme);
  for I := 0 to High(Defs) do
    Assert.IsTrue(Defs[I].SortCol in [pscSize, pscModified, pscPlugin, pscNone],
      'excluded built-in columns are not built');

  Plain := BuildColumnsConfigDialog(False, True, True, False, False, False, True);
  Decl := BuildColumnsConfigDialog(False, True, True, False, False, False, True, cScheme);
  Assert.AreEqual<Integer>(Length(Plain.Controls) - 5 + 3, Length(Decl.Controls),
    'five built-in checkboxes are gone, three plugin ones are added');
  Assert.AreEqual<Integer>(Plain.Height - 5 + 3, Decl.Height);
  Assert.AreEqual<Integer>(ControlById(Decl, 'col_modified').Row + 1, ControlById(Decl, 'pcol_0').Row,
    'plugin columns follow the remaining built-in ones');

  SetSchemePluginColumns('mtn.test', cScheme, '{"builtin":[]}');
  Assert.IsFalse(BuiltinColumnAvailable(cScheme, 'size'), 'an empty list excludes all of them');
  SetSchemePluginColumns('mtn.test', cScheme, '');
  Assert.IsTrue(BuiltinColumnAvailable(cScheme, 'size'), 'an empty declaration lifts the restriction');
end;

procedure TTestPluginColumns.TestSessionKeepsPluginSortAndSelection;
var
  Path: string;
  Saved, Loaded: TMtnSession;
  Tab: TTab;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2-plugin-columns-session.json');
  Saved := Default(TMtnSession);
  Saved.Version := cSessionVersion;
  Saved.Zoom := 1.0;
  Tab := MakeTab(1, 'C:', 'file:///C:/');
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
  Saved.Panels.WorkspaceTabs[0].State.LeftPanel.SortColumn := pscPlugin;
  Saved.Panels.WorkspaceTabs[0].State.LeftPanel.SortPluginId := 'state';
  Saved.Panels.WorkspaceTabs[0].State.LeftPanel.SortDescending := True;
  Saved.Panels.WorkspaceTabs[0].State.RightPanel.SortColumn := pscPlugin;
  SetSchemeColumnSelection(cScheme, ['pid']);
  Saved.PluginColumns := SchemeColumnSelectionsToJson;

  Assert.IsTrue(SaveSession(Path, Saved), 'save');
  try
    Assert.IsTrue(TryLoadSession(Path, Loaded), 'load');
    with Loaded.Panels.WorkspaceTabs[0].State do
    begin
      Assert.IsTrue(LeftPanel.SortColumn = pscPlugin);
      Assert.AreEqual('state', LeftPanel.SortPluginId);
      Assert.IsTrue(LeftPanel.SortDescending);
      Assert.IsTrue(RightPanel.SortColumn = pscNone, 'a plugin sort without a column id is dropped');
      Assert.AreEqual('', RightPanel.SortPluginId);
    end;
    LoadSchemeColumnSelectionsFromJson(Loaded.PluginColumns);
    Assert.AreEqual<Integer>(1, Length(ShownPluginColumns(cScheme)));
    Assert.AreEqual('pid', ShownPluginColumns(cScheme)[0].Id);
  finally
    TFile.Delete(Path);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPluginColumns);

end.
