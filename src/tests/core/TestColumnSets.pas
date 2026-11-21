unit TestColumnSets;

{ Named sets of the Custom column mode: the sets file, saving,
  renaming and deleting. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestColumnSets = class
  private
    FPath: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure MissingFileHasNoSets;
    [Test] procedure ExistingFileListsOnlyItsSets;
    [Test] procedure SetsAreListedAlphabetically;
    [Test] procedure SavedSetIsFoundWithoutRegardToCase;
    [Test] procedure SavingTheSameNameReplacesTheSet;
    [Test] procedure BlankNameIsRefused;
    [Test] procedure BrokenFileListsNoSetsButSavingWorks;
    [Test] procedure DeletedSetIsGone;
    [Test] procedure RenamedSetKeepsItsColumns;
    [Test] procedure RenameToATakenNameIsRefused;
    [Test] procedure RenameMayChangeOnlyTheCase;
    [Test] procedure PluginColumnsAreStoredPerScheme;
    [Test] procedure SavingWithoutPluginsKeepsThoseOfTheSet;
    [Test] procedure PresetModesHaveTheirColumns;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uDualPanelTypes, uPanelColumns, uColumnSets;

function Cfg(AExt, ASize, AModified: Boolean): TCustomColumnsConfig;
begin
  Result := Default(TCustomColumnsConfig);
  Result.ShowExt := AExt;
  Result.ShowSize := ASize;
  Result.ShowModified := AModified;
end;

procedure TTestColumnSets.Setup;
begin
  FPath := TPath.Combine(TPath.GetTempPath, 'mtn2-columnsets-test.json');
  if TFile.Exists(FPath) then
    TFile.Delete(FPath);
  ColumnSetsUsePath(FPath);
end;

procedure TTestColumnSets.TearDown;
begin
  ColumnSetsUsePath('');
  if TFile.Exists(FPath) then
    TFile.Delete(FPath);
end;

procedure TTestColumnSets.MissingFileHasNoSets;
begin
  Assert.IsFalse(TFile.Exists(FPath));
  Assert.AreEqual<Integer>(0, Length(ColumnSets), 'no sets');
  Assert.IsFalse(TFile.Exists(FPath), 'listing writes nothing');
end;

procedure TTestColumnSets.ExistingFileListsOnlyItsSets;
var
  S: TColumnSet;
begin
  TFile.WriteAllText(FPath, '{ "sets": { "Mine": { "size": true } } }', TEncoding.UTF8);
  Assert.AreEqual<Integer>(1, Length(ColumnSets), 'only the set of the file');
  Assert.IsTrue(ColumnSetFind('Mine', S));
end;

procedure TTestColumnSets.SetsAreListedAlphabetically;
var
  Sets: TArray<TColumnSet>;
  I: Integer;
begin
  ColumnSetSave('Zed', Cfg(True, False, False));
  ColumnSetSave('alpha', Cfg(False, True, False));
  ColumnSetSave('Mid', Cfg(False, False, True));
  Sets := ColumnSets;
  Assert.AreEqual<Integer>(3, Length(Sets));
  for I := 1 to High(Sets) do
    Assert.IsTrue(CompareText(Sets[I - 1].Name, Sets[I].Name) <= 0, 'alphabetical');
end;

procedure TTestColumnSets.SavedSetIsFoundWithoutRegardToCase;
var
  S: TColumnSet;
begin
  Assert.IsTrue(ColumnSetSave('Mine', Cfg(True, False, True)), 'saved');
  Assert.IsTrue(ColumnSetFind('mINE', S), 'found');
  Assert.IsTrue(SameColumnsConfig(S.Config, Cfg(True, False, True)), 'same columns');
end;

procedure TTestColumnSets.SavingTheSameNameReplacesTheSet;
var
  S: TColumnSet;
  Count: Integer;
  Item: TColumnSet;
begin
  ColumnSetSave('Mine', Cfg(True, False, False));
  ColumnSetSave('MINE', Cfg(False, True, True));
  Count := 0;
  for Item in ColumnSets do
    if SameText(Item.Name, 'Mine') then
      Inc(Count);
  Assert.AreEqual(1, Count, 'one set of that name');
  Assert.IsTrue(ColumnSetFind('Mine', S));
  Assert.IsTrue(SameColumnsConfig(S.Config, Cfg(False, True, True)), 'the later one wins');
end;

procedure TTestColumnSets.BlankNameIsRefused;
begin
  Assert.IsFalse(ColumnSetSave('   ', Cfg(True, True, True)));
  Assert.IsFalse(TFile.Exists(FPath), 'nothing is written');
end;

procedure TTestColumnSets.BrokenFileListsNoSetsButSavingWorks;
var
  S: TColumnSet;
begin
  TFile.WriteAllText(FPath, '{ not json', TEncoding.UTF8);
  Assert.AreEqual<Integer>(0, Length(ColumnSets), 'nothing is listed');
  Assert.IsTrue(ColumnSetSave('Mine', Cfg(True, False, False)), 'saving over a broken file works');
  Assert.IsTrue(ColumnSetFind('Mine', S));
end;

procedure TTestColumnSets.DeletedSetIsGone;
var
  S: TColumnSet;
begin
  ColumnSetSave('Mine', Cfg(True, False, False));
  Assert.IsTrue(ColumnSetDelete('mine'), 'deleted');
  Assert.IsFalse(ColumnSetFind('Mine', S), 'no longer listed');
  Assert.IsFalse(ColumnSetIsStored('Mine'));
end;

procedure TTestColumnSets.RenamedSetKeepsItsColumns;
var
  S: TColumnSet;
begin
  ColumnSetSave('Mine', Cfg(True, False, True));
  Assert.IsTrue(ColumnSetRename('Mine', ' Yours '), 'renamed');
  Assert.IsFalse(ColumnSetFind('Mine', S), 'old name is gone');
  Assert.IsTrue(ColumnSetFind('Yours', S), 'new name is there');
  Assert.IsTrue(SameColumnsConfig(S.Config, Cfg(True, False, True)), 'same columns');
end;

procedure TTestColumnSets.RenameToATakenNameIsRefused;
begin
  ColumnSetSave('Mine', Cfg(True, False, True));
  ColumnSetSave('Other', Cfg(False, True, False));
  Assert.IsFalse(ColumnSetRename('Mine', 'other'), 'stored name taken');
  Assert.IsFalse(ColumnSetRename('Mine', '  '), 'blank name');
  Assert.IsTrue(ColumnSetIsStored('Mine'), 'set is untouched');
end;

procedure TTestColumnSets.RenameMayChangeOnlyTheCase;
var
  S: TColumnSet;
  Item: TColumnSet;
  Count: Integer;
begin
  ColumnSetSave('Mine', Cfg(True, False, True));
  Assert.IsTrue(ColumnSetRename('Mine', 'MINE'));
  Count := 0;
  for Item in ColumnSets do
    if SameText(Item.Name, 'Mine') then
    begin
      Inc(Count);
      S := Item;
    end;
  Assert.AreEqual(1, Count);
  Assert.AreEqual('MINE', S.Name);
end;

function PluginSet(const AScheme: string; const AIds: array of string): TArray<TSetPluginColumns>;
var
  I: Integer;
begin
  SetLength(Result, 1);
  Result[0].Scheme := AScheme;
  SetLength(Result[0].Ids, Length(AIds));
  for I := 0 to High(AIds) do
    Result[0].Ids[I] := AIds[I];
end;

procedure TTestColumnSets.PluginColumnsAreStoredPerScheme;
var
  S: TColumnSet;
  Ids: TArray<string>;
begin
  Assert.IsTrue(ColumnSetSave('Photos', Cfg(False, True, True), PluginSet('file', ['camera', 'year'])));
  Assert.IsTrue(ColumnSetSave('Photos', Cfg(False, True, True), PluginSet('zip', ['ratio'])));
  Assert.IsTrue(ColumnSetFind('Photos', S));
  Assert.IsTrue(ColumnSetPluginIds(S, 'file', Ids), 'the first scheme stays');
  Assert.AreEqual<Integer>(2, Length(Ids));
  Assert.AreEqual('camera', Ids[0]);
  Assert.IsTrue(ColumnSetPluginIds(S, 'zip', Ids), 'the second scheme is added');
  Assert.AreEqual<Integer>(1, Length(Ids));
  Assert.IsFalse(ColumnSetPluginIds(S, 'ftp', Ids), 'a scheme the set does not mention');
  Assert.IsTrue(ColumnSetSave('Photos', Cfg(False, True, True), PluginSet('file', [])));
  ColumnSetFind('Photos', S);
  Assert.IsTrue(ColumnSetPluginIds(S, 'file', Ids) and (Length(Ids) = 0),
    'a scheme saved with no plugin columns says so');
end;

procedure TTestColumnSets.SavingWithoutPluginsKeepsThoseOfTheSet;
var
  S: TColumnSet;
  Ids: TArray<string>;
begin
  ColumnSetSave('Photos', Cfg(False, True, True), PluginSet('file', ['camera']));
  ColumnSetSave('Photos', Cfg(True, True, True));
  ColumnSetFind('Photos', S);
  Assert.IsTrue(S.Config.ShowExt, 'the columns are replaced');
  Assert.IsTrue(ColumnSetPluginIds(S, 'file', Ids) and (Length(Ids) = 1), 'the plugin columns stay');
  Assert.IsTrue(ColumnSetRename('Photos', 'Pictures'));
  ColumnSetFind('Pictures', S);
  Assert.IsTrue(ColumnSetPluginIds(S, 'file', Ids), 'a renamed set keeps them');
end;

procedure TTestColumnSets.PresetModesHaveTheirColumns;
var
  C: TCustomColumnsConfig;
begin
  Assert.IsFalse(PresetColumnsConfig(pcmBrief, C), 'Brief has no columns');
  Assert.IsFalse(PresetColumnsConfig(pcmCustom, C), 'Custom is not a preset');
  Assert.IsTrue(PresetColumnsConfig(pcmFull, C));
  Assert.IsTrue(C.ShowSize and C.ShowModified and C.ShowAttr and not C.ShowCreated);
  Assert.IsTrue(PresetColumnsConfig(pcmTypes, C));
  Assert.IsTrue(C.ShowExt and C.ShowType and C.ShowSize and C.ShowAttr);
  Assert.IsTrue(PresetColumnsConfig(pcmSize, C));
  Assert.IsTrue(C.ShowSize and not C.ShowModified and not C.ShowAttr);
end;

end.
