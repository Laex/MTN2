unit TestMaskGroups;

{ A mask written as @Name stands for the masks of a named group. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMaskGroups = class
  private
    FPath: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure BuiltInGroupExpandsInAMaskList;
    [Test] procedure UnknownGroupStaysALiteralMask;
    [Test] procedure FileGroupAddsAndReplaces;
    [Test] procedure GroupMayUseAnotherGroup;
    [Test] procedure SelfReferenceStopsExpanding;
    [Test] procedure NamesAreSortedAndIncludeFileGroups;
    [Test] procedure SavedGroupExpandsAtOnce;
    [Test] procedure SavingTheSameNameReplacesTheGroup;
    [Test] procedure InvalidNameOrBlankMasksAreRefused;
    [Test] procedure DeletingAReplacedBuiltInGroupRestoresIt;
    [Test] procedure DeletingAGroupNotInTheFileIsRefused;
    [Test] procedure SavingKeepsOtherGroupsOfTheFile;
    [Test] procedure SuggestedNameComesFromTheFirstMask;
    [Test] procedure SuggestedNameIsNumberedWhenTaken;
    [Test] procedure AutoSaveStoresTheMasksUnderTheSuggestedName;
    [Test] procedure AutoSaveSkipsBlankMasksAndPlainGroupReferences;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uFileFind, uMaskGroups;

procedure TTestMaskGroups.Setup;
begin
  FPath := TPath.Combine(TPath.GetTempPath, 'mtn2-maskgroups-test.json');
  if TFile.Exists(FPath) then
    TFile.Delete(FPath);
  MaskGroupsUsePath(FPath);
end;

procedure TTestMaskGroups.TearDown;
begin
  MaskGroupsUsePath('');
  if TFile.Exists(FPath) then
    TFile.Delete(FPath);
end;

procedure TTestMaskGroups.BuiltInGroupExpandsInAMaskList;
var
  Masks: TArray<string>;
begin
  Masks := SplitMasks('@images; *.txt');
  Assert.IsTrue(NameMatchesAnyMask('photo.JPG', Masks), 'group member');
  Assert.IsTrue(NameMatchesAnyMask('notes.txt', Masks), 'plain mask next to the group');
  Assert.IsFalse(NameMatchesAnyMask('tool.exe', Masks), 'not in either');
end;

procedure TTestMaskGroups.UnknownGroupStaysALiteralMask;
var
  Masks: TArray<string>;
begin
  Masks := SplitMasks('@nothing');
  Assert.AreEqual(1, Integer(Length(Masks)));
  Assert.AreEqual('@nothing', Masks[0]);
  Assert.IsFalse(NameMatchesAnyMask('a.txt', Masks), 'an unknown group does not select everything');
end;

procedure TTestMaskGroups.FileGroupAddsAndReplaces;
var
  Masks: TArray<string>;
begin
  TFile.WriteAllText(FPath,
    '{"groups":{"Logs":"*.log;*.log.*","Images":"*.xyz"}}', TEncoding.UTF8);
  MaskGroupsUsePath(FPath);
  Masks := SplitMasks('@Logs');
  Assert.IsTrue(NameMatchesAnyMask('app.log.1', Masks), 'new group from the file');
  Masks := SplitMasks('@Images');
  Assert.IsTrue(NameMatchesAnyMask('a.xyz', Masks), 'the file replaces a built-in group');
  Assert.IsFalse(NameMatchesAnyMask('a.png', Masks), 'the built-in members are gone');
end;

procedure TTestMaskGroups.GroupMayUseAnotherGroup;
var
  Masks: TArray<string>;
begin
  TFile.WriteAllText(FPath,
    '{"groups":{"Media":"@Audio;@Video","Odd":"*.q"}}', TEncoding.UTF8);
  MaskGroupsUsePath(FPath);
  Masks := SplitMasks('@Media');
  Assert.IsTrue(NameMatchesAnyMask('a.mp3', Masks), 'through Audio');
  Assert.IsTrue(NameMatchesAnyMask('a.mkv', Masks), 'through Video');
end;

procedure TTestMaskGroups.SelfReferenceStopsExpanding;
var
  Masks: TArray<string>;
begin
  TFile.WriteAllText(FPath, '{"groups":{"Loop":"@Loop;*.ok"}}', TEncoding.UTF8);
  MaskGroupsUsePath(FPath);
  Masks := SplitMasks('@Loop');
  Assert.IsTrue(NameMatchesAnyMask('a.ok', Masks), 'the real mask still works');
end;

procedure TTestMaskGroups.NamesAreSortedAndIncludeFileGroups;
var
  Names: TArray<string>;
  I: Integer;
  Found: Boolean;
begin
  TFile.WriteAllText(FPath, '{"groups":{"Aaa":"*.a"}}', TEncoding.UTF8);
  MaskGroupsUsePath(FPath);
  Names := MaskGroupNames;
  Found := False;
  for I := 0 to High(Names) do
  begin
    if Names[I] = 'Aaa' then
      Found := True;
    if I > 0 then
      Assert.IsTrue(CompareText(Names[I - 1], Names[I]) <= 0, 'alphabetical');
  end;
  Assert.IsTrue(Found, 'group from the file is listed');
end;

procedure TTestMaskGroups.SavedGroupExpandsAtOnce;
begin
  Assert.IsTrue(MaskGroupSave('Logs', '*.log;*.out'), 'saved');
  Assert.IsTrue(NameMatchesAnyMask('a.out', SplitMasks('@logs')), 'used straight away');
  Assert.IsTrue(MaskGroupInFile('LOGS'), 'listed as a file group');
  Assert.IsFalse(MaskGroupIsBuiltIn('Logs'));
end;

procedure TTestMaskGroups.SavingTheSameNameReplacesTheGroup;
var
  Masks: TArray<string>;
  Count: Integer;
  Name: string;
begin
  MaskGroupSave('Logs', '*.log');
  MaskGroupSave('LOGS', '*.out');
  Masks := SplitMasks('@Logs');
  Assert.IsTrue(NameMatchesAnyMask('a.out', Masks), 'the later one wins');
  Assert.IsFalse(NameMatchesAnyMask('a.log', Masks), 'the earlier masks are gone');
  Count := 0;
  for Name in MaskGroupNames do
    if SameText(Name, 'Logs') then
      Inc(Count);
  Assert.AreEqual(1, Count, 'one group of that name');
end;

procedure TTestMaskGroups.InvalidNameOrBlankMasksAreRefused;
begin
  Assert.IsFalse(MaskGroupSave('', '*.a'), 'blank name');
  Assert.IsFalse(MaskGroupSave('two words', '*.a'), 'space in the name');
  Assert.IsFalse(MaskGroupSave('a;b', '*.a'), 'separator in the name');
  Assert.IsFalse(MaskGroupSave('@x', '*.a'), 'at sign in the name');
  Assert.IsFalse(MaskGroupSave('Ok', '   '), 'blank masks');
  Assert.IsFalse(TFile.Exists(FPath), 'nothing is written');
end;

procedure TTestMaskGroups.DeletingAReplacedBuiltInGroupRestoresIt;
var
  Masks: TArray<string>;
begin
  MaskGroupSave('Images', '*.xyz');
  Assert.IsTrue(MaskGroupDelete('images'), 'deleted');
  Masks := SplitMasks('@Images');
  Assert.IsTrue(NameMatchesAnyMask('a.png', Masks), 'the built-in members are back');
  Assert.IsFalse(NameMatchesAnyMask('a.xyz', Masks), 'the replacement is gone');
  Assert.IsTrue(MaskGroupIsBuiltIn('Images'));
end;

procedure TTestMaskGroups.DeletingAGroupNotInTheFileIsRefused;
begin
  Assert.IsFalse(MaskGroupDelete('Audio'), 'a built-in group is not in the file');
  Assert.IsFalse(MaskGroupDelete('Nothing'));
end;

procedure TTestMaskGroups.SuggestedNameComesFromTheFirstMask;
begin
  Assert.AreEqual('log', MaskGroupSuggestName('*.log;*.out'));
  Assert.AreEqual('Masks', MaskGroupSuggestName('*.*'));
end;

procedure TTestMaskGroups.SuggestedNameIsNumberedWhenTaken;
begin
  MaskGroupSave('log', '*.log');
  Assert.AreEqual('log2', MaskGroupSuggestName('*.log;*.out'));
  Assert.AreEqual('Images2', MaskGroupSuggestName('Images*'), 'a built-in name counts as taken');
end;

procedure TTestMaskGroups.AutoSaveStoresTheMasksUnderTheSuggestedName;
var
  Name: string;
begin
  Name := MaskGroupSaveAuto('*.log;*.out');
  Assert.AreEqual('log', Name);
  Assert.IsTrue(NameMatchesAnyMask('a.out', SplitMasks('@log')), 'group works');
end;

procedure TTestMaskGroups.AutoSaveSkipsBlankMasksAndPlainGroupReferences;
begin
  Assert.AreEqual('', MaskGroupSaveAuto('   '));
  Assert.AreEqual('', MaskGroupSaveAuto('@Images'));
  Assert.IsFalse(TFile.Exists(FPath), 'nothing is written');
end;

procedure TTestMaskGroups.SavingKeepsOtherGroupsOfTheFile;
begin
  TFile.WriteAllText(FPath, '{"groups":{"Aaa":"*.a"}}', TEncoding.UTF8);
  MaskGroupsUsePath(FPath);
  MaskGroupSave('Bbb', '*.b');
  Assert.IsTrue(NameMatchesAnyMask('x.a', SplitMasks('@Aaa')), 'old group kept');
  Assert.IsTrue(NameMatchesAnyMask('x.b', SplitMasks('@Bbb')), 'new group added');
end;

end.
