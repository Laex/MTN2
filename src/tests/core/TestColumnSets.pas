unit TestColumnSets;

{ Named sets of the Custom column mode: the file with the starter sets, saving,
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
    [Test] procedure MissingFileIsCreatedWithTheStarterSets;
    [Test] procedure ExistingFileGetsNoStarterSets;
    [Test] procedure SetsAreListedAlphabetically;
    [Test] procedure SavedSetIsFoundWithoutRegardToCase;
    [Test] procedure SavingTheSameNameReplacesTheSet;
    [Test] procedure SavingAStarterSetNameReplacesIt;
    [Test] procedure BlankNameIsRefused;
    [Test] procedure BrokenFileListsNoSetsButSavingWorks;
    [Test] procedure DeletedSetIsGone;
    [Test] procedure DeletedStarterSetStaysDeleted;
    [Test] procedure RenamedSetKeepsItsColumns;
    [Test] procedure RenameToATakenNameIsRefused;
    [Test] procedure RenameMayChangeOnlyTheCase;
    [Test] procedure StarterSetCanBeRenamed;
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

procedure TTestColumnSets.MissingFileIsCreatedWithTheStarterSets;
var
  S: TColumnSet;
begin
  Assert.IsFalse(TFile.Exists(FPath));
  Assert.IsTrue(ColumnSetFind('Minimal', S), 'Minimal');
  Assert.IsTrue(ColumnSetFind('Dates', S), 'Dates');
  Assert.IsTrue(ColumnSetFind('Technical', S), 'Technical');
  Assert.IsTrue(TFile.Exists(FPath), 'the file is written');
  Assert.IsTrue(ColumnSetIsStored('Dates'), 'a starter set is a stored one');
end;

procedure TTestColumnSets.ExistingFileGetsNoStarterSets;
var
  S: TColumnSet;
begin
  TFile.WriteAllText(FPath, '{ "sets": { "Mine": { "size": true } } }', TEncoding.UTF8);
  Assert.AreEqual<Integer>(1, Length(ColumnSets), 'only the set of the file');
  Assert.IsFalse(ColumnSetFind('Dates', S), 'no starter set is added');
end;

procedure TTestColumnSets.SetsAreListedAlphabetically;
var
  Sets: TArray<TColumnSet>;
  I: Integer;
begin
  Sets := ColumnSets;
  Assert.IsTrue(Length(Sets) >= 3, 'the starter sets are there');
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

procedure TTestColumnSets.SavingAStarterSetNameReplacesIt;
var
  S: TColumnSet;
begin
  ColumnSetSave('Minimal', Cfg(True, True, True));
  Assert.IsTrue(ColumnSetFind('Minimal', S));
  Assert.IsTrue(SameColumnsConfig(S.Config, Cfg(True, True, True)));
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

procedure TTestColumnSets.DeletedStarterSetStaysDeleted;
var
  S: TColumnSet;
begin
  Assert.IsTrue(ColumnSetDelete('Minimal'), 'deleted');
  Assert.IsFalse(ColumnSetFind('Minimal', S), 'gone');
  Assert.IsFalse(ColumnSetFind('minimal', S), 'still gone on the next read');
  Assert.IsTrue(ColumnSetFind('Dates', S), 'the others stay');
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
  Assert.IsFalse(ColumnSetRename('Mine', 'Dates'), 'starter set name taken');
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

procedure TTestColumnSets.StarterSetCanBeRenamed;
var
  S: TColumnSet;
  Before: TCustomColumnsConfig;
begin
  ColumnSetFind('Dates', S);
  Before := S.Config;
  Assert.IsTrue(ColumnSetRename('Dates', 'Calendar'));
  Assert.IsFalse(ColumnSetFind('Dates', S), 'old name is gone');
  Assert.IsTrue(ColumnSetFind('Calendar', S));
  Assert.IsTrue(SameColumnsConfig(S.Config, Before), 'same columns');
end;

end.
