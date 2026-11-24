unit TestSyncIgnore;

{ Exclusion rules of Directory Sync: gitignore patterns, robocopy job files,
  Obsidian filters and skipped junctions. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSyncIgnore = class
  public
    [Test] procedure TestGlobWildcardsStayInsideOneName;
    [Test] procedure TestGlobDoubleStarCrossesFolders;
    [Test] procedure TestGlobCharacterClass;
    [Test] procedure TestGitignoreNameDirectoryAndNegation;
    [Test] procedure TestGitignoreAnchoredPatterns;
    [Test] procedure TestNestedIgnoreFileAppliesToItsFolder;
    [Test] procedure TestRobocopyFileListsFoldersAndFiles;
    [Test] procedure TestObsidianFiltersAndExtraPatterns;
    [Test] procedure TestJunctionsSkippedOnlyWhenAsked;
    [Test] procedure TestCompareLeavesIgnoredFilesOut;
    [Test] procedure TestNoOptionsMeansNoFilter;
    [Test] procedure TestOnlyMasksKeepMatchingFilesAndEnterFolders;
    [Test] procedure TestCompareWithOnlyMaskLeavesOtherTypesOut;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  uDualPanelSync,
  uSyncIgnore;

function NewRoot(const AName: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-ignore-' + AName);
  if TDirectory.Exists(Result) then
    TDirectory.Delete(Result, True);
  ForceDirectories(Result);
end;

procedure PutFile(const ARoot, ARel, AText: string);
var
  P: string;
begin
  P := TPath.Combine(ARoot, ARel);
  ForceDirectories(TPath.GetDirectoryName(P));
  TFile.WriteAllText(P, AText, TEncoding.UTF8);
end;

function FilterWith(const ARoot: string; AIgnoreFiles, ARcj, AObsidian: Boolean;
  const AExtra: string = ''): ISyncFilter;
var
  O: TSyncFilterOptions;
begin
  O := Default(TSyncFilterOptions);
  O.UseIgnoreFiles := AIgnoreFiles;
  O.UseRobocopyFile := ARcj;
  O.UseObsidian := AObsidian;
  O.Extra := AExtra;
  Result := NewSyncFilter(O, [ARoot]);
end;

procedure TTestSyncIgnore.TestGlobWildcardsStayInsideOneName;
begin
  Assert.IsTrue(SyncGlobMatch('*.log', 'build.log'));
  Assert.IsFalse(SyncGlobMatch('*.log', 'dir/build.log'), '* does not cross a folder');
  Assert.IsTrue(SyncGlobMatch('a?c', 'abc'));
  Assert.IsFalse(SyncGlobMatch('a?c', 'a/c'));
  Assert.IsTrue(SyncGlobMatch('.Trash-*', '.trash-1000'), 'case is ignored');
  Assert.IsFalse(SyncGlobMatch('abc', 'abcd'));
end;

procedure TTestSyncIgnore.TestGlobDoubleStarCrossesFolders;
begin
  Assert.IsTrue(SyncGlobMatch('**/JUNC/**', 'a/b/JUNC/x.txt'));
  Assert.IsTrue(SyncGlobMatch('**/JUNC/**', 'JUNC/x.txt'));
  Assert.IsFalse(SyncGlobMatch('**/JUNC/**', 'JUNC'), '/** needs something inside');
  Assert.IsTrue(SyncGlobMatch('a/**/z', 'a/z'));
  Assert.IsTrue(SyncGlobMatch('a/**/z', 'a/b/c/z'));
  Assert.IsFalse(SyncGlobMatch('a/**/z', 'b/a/z'));
end;

procedure TTestSyncIgnore.TestGlobCharacterClass;
begin
  Assert.IsTrue(SyncGlobMatch('file[0-9].txt', 'file7.txt'));
  Assert.IsFalse(SyncGlobMatch('file[0-9].txt', 'filex.txt'));
  Assert.IsTrue(SyncGlobMatch('file[!0-9].txt', 'filex.txt'));
end;

procedure TTestSyncIgnore.TestGitignoreNameDirectoryAndNegation;
var
  Root: string;
  F: ISyncFilter;
begin
  Root := NewRoot('basic');
  PutFile(Root, '.gitignore',
    '# comment' + sLineBreak + '*.log' + sLineBreak + '!keep.log' + sLineBreak +
    'build/' + sLineBreak);
  F := FilterWith(Root, True, False, False);
  Assert.IsTrue(F.Skip('a.log', False, False));
  Assert.IsTrue(F.Skip('sub' + PathDelim + 'a.log', False, False), 'any depth');
  Assert.IsFalse(F.Skip('keep.log', False, False), 'negated');
  Assert.IsTrue(F.Skip('build', True, False), 'directory rule on a folder');
  Assert.IsFalse(F.Skip('build', False, False), 'directory rule leaves a file alone');
  Assert.IsFalse(F.Skip('readme.md', False, False));
end;

procedure TTestSyncIgnore.TestGitignoreAnchoredPatterns;
var
  Root: string;
  F: ISyncFilter;
begin
  Root := NewRoot('anchored');
  PutFile(Root, '.gitignore', '/top.txt' + sLineBreak + 'docs/tmp' + sLineBreak);
  F := FilterWith(Root, True, False, False);
  Assert.IsTrue(F.Skip('top.txt', False, False));
  Assert.IsFalse(F.Skip('sub' + PathDelim + 'top.txt', False, False), 'only at the root');
  Assert.IsTrue(F.Skip('docs' + PathDelim + 'tmp', False, False));
  Assert.IsFalse(F.Skip('x' + PathDelim + 'docs' + PathDelim + 'tmp', False, False));
end;

procedure TTestSyncIgnore.TestNestedIgnoreFileAppliesToItsFolder;
var
  Root: string;
  F: ISyncFilter;
begin
  Root := NewRoot('nested');
  PutFile(Root, 'sub' + PathDelim + '.gitignore', '*.tmp' + sLineBreak);
  F := FilterWith(Root, True, False, False);
  Assert.IsFalse(F.Skip('sub' + PathDelim + 'a.tmp', False, False), 'not read yet');
  F.EnterDir('sub', TPath.Combine(Root, 'sub'));
  Assert.IsTrue(F.Skip('sub' + PathDelim + 'a.tmp', False, False));
  Assert.IsFalse(F.Skip('other' + PathDelim + 'a.tmp', False, False), 'outside its folder');
end;

procedure TTestSyncIgnore.TestRobocopyFileListsFoldersAndFiles;
var
  Root: string;
  F: ISyncFilter;
begin
  Root := NewRoot('rcj');
  PutFile(Root, 'exclude.rcj',
    ':: generated' + sLineBreak + '/XD' + sLineBreak + #9 + 'Archive' + sLineBreak +
    #9 + '"System Volume Information"' + sLineBreak + #9 + Root + PathDelim +
    '.obsidian' + PathDelim + 'cache' + sLineBreak + '/XF' + sLineBreak + #9 +
    '*.bak' + sLineBreak);
  F := FilterWith(Root, False, True, False);
  Assert.IsTrue(F.Skip('Archive', True, False));
  Assert.IsTrue(F.Skip('x' + PathDelim + 'Archive', True, False), 'a name matches at any depth');
  Assert.IsFalse(F.Skip('Archive', False, False), '/XD names folders only');
  Assert.IsTrue(F.Skip('System Volume Information', True, False), 'quoted name');
  Assert.IsTrue(F.Skip('.obsidian' + PathDelim + 'cache', True, False), 'full path under the root');
  Assert.IsFalse(F.Skip('cache', True, False));
  Assert.IsTrue(F.Skip('old.bak', False, False));
  Assert.IsFalse(F.Skip('old.bak', True, False), '/XF names files only');
end;

procedure TTestSyncIgnore.TestObsidianFiltersAndExtraPatterns;
var
  Root: string;
  F: ISyncFilter;
begin
  Root := NewRoot('obsidian');
  PutFile(Root, '.obsidian' + PathDelim + 'app.json',
    '{"showLineNumber":true,"userIgnoreFilters":["Archive/","**/.venv/**"]}');
  F := FilterWith(Root, False, False, True, 'scratch*; *.tmp');
  Assert.IsTrue(F.Skip('Archive', True, False));
  Assert.IsTrue(F.Skip('p' + PathDelim + '.venv' + PathDelim + 'x.py', False, False));
  Assert.IsTrue(F.Skip('scratch1', True, False), 'first extra pattern');
  Assert.IsTrue(F.Skip('a.tmp', False, False), 'second extra pattern');
  Assert.IsFalse(F.Skip('note.md', False, False));
end;

procedure TTestSyncIgnore.TestJunctionsSkippedOnlyWhenAsked;
var
  O: TSyncFilterOptions;
  F: ISyncFilter;
begin
  O := Default(TSyncFilterOptions);
  F := NewSyncFilter(O, []);
  Assert.IsFalse(F.Skip('link', True, True), 'followed by default');
  O.SkipJunctions := True;
  F := NewSyncFilter(O, []);
  Assert.IsTrue(F.Skip('link', True, True));
  Assert.IsFalse(F.Skip('folder', True, False), 'a plain folder is entered');
  Assert.IsFalse(F.Skip('file', False, True), 'only folders are skipped');
end;

procedure TTestSyncIgnore.TestCompareLeavesIgnoredFilesOut;
var
  Root, Src, Dst: string;
  Items: TArray<TSyncItem>;
  Empty: TArray<TSyncSnapshotEntry>;
  I: Integer;
  F: ISyncFilter;
begin
  Root := NewRoot('compare');
  Src := TPath.Combine(Root, 'src');
  Dst := TPath.Combine(Root, 'dst');
  ForceDirectories(Dst);
  PutFile(Src, '.gitignore', '*.log' + sLineBreak + 'cache/' + sLineBreak);
  PutFile(Src, 'a.txt', 'a');
  PutFile(Src, 'a.log', 'log');
  PutFile(Src, 'cache' + PathDelim + 'x.dat', 'x');
  PutFile(Dst, 'extra.log', 'only on the target');
  SetLength(Empty, 0);
  F := FilterWith(Src, True, False, False);
  Items := CompareDirsTwoWay(Src, Dst, Empty, False, nil, F);
  for I := 0 to High(Items) do
  begin
    Assert.AreNotEqual('a.log', Items[I].RelPath);
    Assert.AreNotEqual('extra.log', Items[I].RelPath, 'ignored on the target as well');
    Assert.IsFalse(Pos('cache', Items[I].RelPath) = 1, 'an ignored folder is not entered');
  end;
  Assert.IsTrue(Length(Items) >= 1, 'a.txt is still missing on the target');
end;

procedure TTestSyncIgnore.TestNoOptionsMeansNoFilter;
var
  O: TSyncFilterOptions;
begin
  O := Default(TSyncFilterOptions);
  Assert.IsFalse(SyncFilterOptionsActive(O));
  O := DefaultSyncFilterOptions;
  Assert.IsTrue(O.SkipJunctions, 'junctions are skipped by default');
  Assert.IsTrue(SyncFilterOptionsActive(O));
  O := Default(TSyncFilterOptions);
  O.Extra := '  ';
  Assert.IsFalse(SyncFilterOptionsActive(O), 'blank extra patterns do not count');
end;

procedure TTestSyncIgnore.TestOnlyMasksKeepMatchingFilesAndEnterFolders;
var
  O: TSyncFilterOptions;
  F: ISyncFilter;
begin
  O := Default(TSyncFilterOptions);
  O.Only := ' *.MD ; *.txt ';
  Assert.IsTrue(SyncFilterOptionsActive(O), 'the masks make the filter active');
  F := NewSyncFilter(O, []);
  Assert.IsFalse(F.Skip('note.md', False, False), 'matching name, any case');
  Assert.IsFalse(F.Skip('sub' + PathDelim + 'a.txt', False, False), 'matched by name in a subfolder');
  Assert.IsTrue(F.Skip('pic.png', False, False), 'other types are left out');
  Assert.IsTrue(F.Skip('sub' + PathDelim + 'x.dat', False, False));
  Assert.IsFalse(F.Skip('sub', True, False), 'folders are still entered');
  O.Only := '  ;  ';
  Assert.IsFalse(SyncFilterOptionsActive(O) and NewSyncFilter(O, []).Skip('pic.png', False, False),
    'blank masks filter nothing');
end;

procedure TTestSyncIgnore.TestCompareWithOnlyMaskLeavesOtherTypesOut;
var
  Root, Src, Dst: string;
  Items: TArray<TSyncItem>;
  Empty: TArray<TSyncSnapshotEntry>;
  O: TSyncFilterOptions;
  I: Integer;
  SawMd: Boolean;
begin
  Root := NewRoot('only');
  Src := TPath.Combine(Root, 'src');
  Dst := TPath.Combine(Root, 'dst');
  ForceDirectories(Dst);
  PutFile(Src, 'a.md', 'a');
  PutFile(Src, 'b.png', 'b');
  PutFile(Src, 'sub' + PathDelim + 'c.md', 'c');
  PutFile(Dst, 'extra.png', 'only on the target');
  SetLength(Empty, 0);
  O := Default(TSyncFilterOptions);
  O.Only := '*.md';
  Items := CompareDirsTwoWay(Src, Dst, Empty, False, nil, NewSyncFilter(O, [Src, Dst]));
  SawMd := False;
  for I := 0 to High(Items) do
  begin
    Assert.IsTrue(SameText(ExtractFileExt(Items[I].RelPath), '.md'),
      'only .md files are listed: ' + Items[I].RelPath);
    SawMd := True;
  end;
  Assert.IsTrue(SawMd, 'the .md files are still compared');
  Assert.AreEqual(2, Integer(Length(Items)), 'a.md and sub\c.md');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSyncIgnore);

end.
