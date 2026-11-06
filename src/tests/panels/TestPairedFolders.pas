unit TestPairedFolders;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPairedFolders = class
  private
    FBase: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure StepIntoFolderFollowsToTheFolderOfTheSameName;
    [Test] procedure StepIntoFolderStaysWithoutAFolderOfTheSameName;
    [Test] procedure StepIntoFolderIgnoresAFileOfTheSameName;
    [Test] procedure StepUpFollowsToTheParent;
    [Test] procedure StepsOtherThanOneLevelDoNotMove;
    [Test] procedure FoldersThatAreNotPlainLocalNeverMove;
    [Test] procedure FlagIsSavedInTheSession;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uVfsTypes,
  uDualPanelTypes,
  uPanelColumns, uListExport,
  uSession;

procedure TTestPairedFolders.Setup;
begin
  FBase := TPath.Combine(TPath.GetTempPath, 'mtn2_paired_folders_test');
  if TDirectory.Exists(FBase) then
    TDirectory.Delete(FBase, True);
  TDirectory.CreateDirectory(TPath.Combine(FBase, 'Left' + PathDelim + 'sub' + PathDelim + 'deep'));
  TDirectory.CreateDirectory(TPath.Combine(FBase, 'Left' + PathDelim + 'only'));
  TDirectory.CreateDirectory(TPath.Combine(FBase, 'Left' + PathDelim + 'file'));
  TDirectory.CreateDirectory(TPath.Combine(FBase, 'Right' + PathDelim + 'sub'));
  TFile.WriteAllText(TPath.Combine(FBase, 'Right' + PathDelim + 'file'), 'x');
end;

procedure TTestPairedFolders.TearDown;
begin
  if TDirectory.Exists(FBase) then
    TDirectory.Delete(FBase, True);
end;

procedure TTestPairedFolders.StepIntoFolderFollowsToTheFolderOfTheSameName;
var
  Left, Right, Target: string;
begin
  Left := PathToFileUri(TPath.Combine(FBase, 'Left'));
  Right := PathToFileUri(TPath.Combine(FBase, 'Right'));
  Target := PairedFolderTarget(Left, JoinFileUri(Left, 'sub'), Right);
  Assert.IsTrue(SameVfsUri(Target, JoinFileUri(Right, 'sub')),
    'the other panel enters its own "sub"');
end;

procedure TTestPairedFolders.StepIntoFolderStaysWithoutAFolderOfTheSameName;
var
  Left, Right: string;
begin
  Left := PathToFileUri(TPath.Combine(FBase, 'Left'));
  Right := PathToFileUri(TPath.Combine(FBase, 'Right'));
  Assert.AreEqual('', PairedFolderTarget(Left, JoinFileUri(Left, 'only'), Right),
    'no "only" in the other panel: it stays');
end;

procedure TTestPairedFolders.StepIntoFolderIgnoresAFileOfTheSameName;
var
  Left, Right: string;
begin
  Left := PathToFileUri(TPath.Combine(FBase, 'Left'));
  Right := PathToFileUri(TPath.Combine(FBase, 'Right'));
  Assert.AreEqual('', PairedFolderTarget(Left, JoinFileUri(Left, 'file'), Right),
    'a file named like the folder is not a place to enter');
end;

procedure TTestPairedFolders.StepUpFollowsToTheParent;
var
  Sub, Right, Target: string;
begin
  Sub := PathToFileUri(TPath.Combine(FBase, 'Left' + PathDelim + 'sub'));
  Right := PathToFileUri(TPath.Combine(FBase, 'Right' + PathDelim + 'sub'));
  Target := PairedFolderTarget(Sub, ParentFileUri(Sub), Right);
  Assert.IsTrue(SameVfsUri(Target, PathToFileUri(TPath.Combine(FBase, 'Right'))),
    'the other panel goes up as well');
end;

procedure TTestPairedFolders.StepsOtherThanOneLevelDoNotMove;
var
  Left, Right, Deep, Sibling: string;
begin
  Left := PathToFileUri(TPath.Combine(FBase, 'Left'));
  Right := PathToFileUri(TPath.Combine(FBase, 'Right'));
  Deep := PathToFileUri(TPath.Combine(FBase, 'Left' + PathDelim + 'sub' + PathDelim + 'deep'));
  Sibling := PathToFileUri(TPath.Combine(FBase, 'Right'));
  Assert.AreEqual('', PairedFolderTarget(Left, Deep, Right), 'two levels down is a jump');
  Assert.AreEqual('', PairedFolderTarget(Deep, Left, Right), 'two levels up is a jump');
  Assert.AreEqual('', PairedFolderTarget(Left, Sibling, Right), 'a sibling is a jump');
  Assert.AreEqual('', PairedFolderTarget(Left, Left, Right), 'no move, no step');
end;

procedure TTestPairedFolders.FoldersThatAreNotPlainLocalNeverMove;
var
  Left, Right, Zip: string;
begin
  Left := PathToFileUri(TPath.Combine(FBase, 'Left'));
  Right := PathToFileUri(TPath.Combine(FBase, 'Right'));
  Zip := PathToFileUri(TPath.Combine(FBase, 'Left' + PathDelim + 'a.zip')) + '!/';
  Assert.AreEqual('', PairedFolderTarget(Left, Zip, Right), 'entering an archive');
  Assert.AreEqual('', PairedFolderTarget(Zip, Left, Right), 'leaving an archive');
  Assert.AreEqual('', PairedFolderTarget(Left, JoinFileUri(Left, 'sub'), 'find://7'),
    'the other panel shows search results');
  Assert.AreEqual('', PairedFolderTarget('find://7', Left, Right),
    'the step starts in search results');
end;

procedure TTestPairedFolders.FlagIsSavedInTheSession;
var
  Path: string;
  Saved, Loaded: TMtnSession;
  Tab: TTab;
begin
  Path := TPath.Combine(FBase, 'session.json');
  Tab := MakeTab(1, 'C:', 'file:///C:/');
  Saved := Default(TMtnSession);
  Saved.Version := cSessionVersion;
  Saved.Zoom := 1;
  Saved.CustomColumns := DefaultCustomColumnsConfig;
  Saved.ListExport := DefaultListExportConfig;
  SetLength(Saved.Panels.WorkspaceTabs, 2);
  for var I := 0 to 1 do
  begin
    Saved.Panels.WorkspaceTabs[I].Id := I + 1;
    Saved.Panels.WorkspaceTabs[I].Title := 'Workspace';
    Saved.Panels.WorkspaceTabs[I].Kind := wkPanels;
    Saved.Panels.WorkspaceTabs[I].State.LeftVisible := True;
    Saved.Panels.WorkspaceTabs[I].State.RightVisible := True;
    SetLength(Saved.Panels.WorkspaceTabs[I].State.LeftPanel.Tabs, 1);
    Saved.Panels.WorkspaceTabs[I].State.LeftPanel.Tabs[0] := Tab;
    SetLength(Saved.Panels.WorkspaceTabs[I].State.RightPanel.Tabs, 1);
    Saved.Panels.WorkspaceTabs[I].State.RightPanel.Tabs[0] := Tab;
  end;
  Saved.Panels.WorkspaceTabs[1].State.PairedFolders := True;

  Assert.IsTrue(SaveSession(Path, Saved), 'save session');
  Assert.IsTrue(TryLoadSession(Path, Loaded), 'load session');
  Assert.IsFalse(Loaded.Panels.WorkspaceTabs[0].State.PairedFolders,
    'a tab saved with the flag off loads with it off');
  Assert.IsTrue(Loaded.Panels.WorkspaceTabs[1].State.PairedFolders,
    'a tab saved with the flag on loads with it on');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPairedFolders);

end.
