unit TestColumnSets;

{ Named sets of the Custom column mode: built-in ones, a file, and saving. }

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
    [Test] procedure BuiltInSetsAreListedAlphabetically;
    [Test] procedure SavedSetIsFoundWithoutRegardToCase;
    [Test] procedure SavingTheSameNameReplacesTheSet;
    [Test] procedure SavedSetReplacesABuiltInOne;
    [Test] procedure BlankNameIsRefused;
    [Test] procedure BrokenFileKeepsTheBuiltInSets;
    [Test] procedure DeletedSetIsGone;
    [Test] procedure DeletingAnOverrideRestoresTheBuiltInSet;
    [Test] procedure BuiltInSetCannotBeDeleted;
    [Test] procedure RenamedSetKeepsItsColumns;
    [Test] procedure RenameToATakenNameIsRefused;
    [Test] procedure RenameMayChangeOnlyTheCase;
    [Test] procedure BuiltInSetCannotBeRenamed;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uPanelColumns, uColumnSets;

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

procedure TTestColumnSets.BuiltInSetsAreListedAlphabetically;
var
  Sets: TArray<TColumnSet>;
  I: Integer;
begin
  Sets := ColumnSets;
  Assert.IsTrue(Length(Sets) >= 3, 'there are built-in sets');
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

procedure TTestColumnSets.SavedSetReplacesABuiltInOne;
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

procedure TTestColumnSets.BrokenFileKeepsTheBuiltInSets;
var
  S: TColumnSet;
begin
  TFile.WriteAllText(FPath, '{ not json', TEncoding.UTF8);
  Assert.IsTrue(ColumnSetFind('Dates', S), 'built-in set survives');
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

procedure TTestColumnSets.DeletingAnOverrideRestoresTheBuiltInSet;
var
  S: TColumnSet;
begin
  ColumnSetSave('Minimal', Cfg(True, True, True));
  Assert.IsTrue(ColumnSetDelete('Minimal'));
  Assert.IsTrue(ColumnSetFind('Minimal', S), 'built-in set is back');
  Assert.IsFalse(SameColumnsConfig(S.Config, Cfg(True, True, True)), 'built-in columns');
end;

procedure TTestColumnSets.BuiltInSetCannotBeDeleted;
var
  S: TColumnSet;
begin
  Assert.IsTrue(ColumnSetIsBuiltIn('dates'));
  Assert.IsFalse(ColumnSetDelete('Dates'), 'nothing stored to delete');
  Assert.IsTrue(ColumnSetFind('Dates', S));
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
  Assert.IsFalse(ColumnSetRename('Mine', 'Dates'), 'built-in name taken');
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

procedure TTestColumnSets.BuiltInSetCannotBeRenamed;
begin
  Assert.IsFalse(ColumnSetRename('Dates', 'Calendar'));
end;

end.
