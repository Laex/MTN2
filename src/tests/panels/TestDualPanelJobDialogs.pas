unit TestDualPanelJobDialogs;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelJobDialogs = class
  public
    [Test] procedure TestJobOptionMaps;
    [Test] [Category('WindowsOnly')] procedure TestDestAndPack;
    [Test] procedure TestCollectSources;
    [Test] procedure TestPanelFoldersAreSame;
    [Test] procedure TestConfirmIntoSameFolderStaysOpen;
    [Test] procedure TestPackIntoRenamedSevenZip;
    [Test] [Category('WindowsOnly')] procedure TestSearchRootAndSync;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uDialogTypes,
  uDialogHost,
  uVfsTypes,
  uDualPanelTypes,
  uDualPanelUiTypes,
  uDualPanelSelection,
  uDualPanelSync,
  uFindSession,
  uDualPanelJobDialogs,
  uDualPanelJobList,
  uDualPanelJobs,
  uDualPanelJobRules,
  uDualPanelFindDialogs;

procedure TestConfirmIntoSameFolderStaysOpen;
var
  Host: TDialogHost;
  Jobs: TPanelJobList;
  Controller: TJobDialogController;
  Fields: TDialogCommandFields;
  Warning, Dir: string;
begin
  Warning := '';
  Dir := TPath.Combine(TPath.GetTempPath, 'MTN2_SameFolderConfirm');
  Host := TDialogHost.Create(nil);
  Jobs := TPanelJobList.Create(nil, nil,
    procedure begin end,
    procedure(const ATitle, AMessage: string)
    begin
      Host.Open(BuildCopyMoveDialog(ATitle, AMessage,
        JobConfirmDestText(pjkCopy, PathToFileUri(Dir))), nil);
    end,
    procedure(const APath, ANewLine, AExistingLine: string) begin end,
    procedure(const APath, AHeadline, AQuestion, AErrorLine: string;
      AOfferPermanent: Boolean) begin end,
    procedure(const AHeadline, APath, AErrorLine: string) begin end,
    procedure(ASucceeded: Boolean) begin end,
    procedure(const AOriginSrc, AOriginDst: string) begin end,
    procedure(const AOriginSrc: string) begin end);
  Controller := TJobDialogController.Create(Host, Jobs, nil, nil);
  Controller.OnWarn :=
    procedure(const AMessage: string)
    begin
      Warning := AMessage;
    end;
  try
    Jobs.BeginJob(TArray<string>.Create(PathToFileUri(TPath.Combine(Dir, 'a.txt'))),
      PathToFileUri(Dir), pjkCopy);
    Assert.IsTrue(Jobs.Phase = pjpConfirm, 'the confirm dialog is up');
    Fields := Default(TDialogCommandFields);
    Fields.DestPath := Host.GetInputValue('job_dest');
    Fields.ExistingIdx := 0;
    Controller.DispatchCommand(hdkJobConfirm, 'ok', Fields);
    Assert.IsTrue(Jobs.Phase = pjpConfirm, 'confirming into the source folder starts nothing');
    Assert.IsTrue(Host.Visible, 'the dialog stays open');
    Assert.AreEqual(JobSameFolderWarning, Warning, 'a warning says why');
  finally
    Controller.Free;
    Jobs.Free;
    Host.Free;
  end;
end;

procedure TestPanelFoldersAreSame;
begin
  Assert.IsTrue(PanelFoldersAreSame('file:///C:/Work', 'file:///C:/Work'), 'identical folders');
  Assert.IsTrue(PanelFoldersAreSame('file:///C:/Work/', 'file:///C:/Work'), 'a trailing slash does not matter');
  Assert.IsFalse(PanelFoldersAreSame('file:///C:/Work', 'file:///C:/Other'), 'different folders');
  Assert.IsFalse(PanelFoldersAreSame('file:///C:/Work', 'file:///C:/Work/sub'), 'a subfolder is another folder');
  Assert.IsTrue(PanelFoldersAreSame('sftp://u@h/path/', 'sftp://u@h/path'), 'the same remote folder');
  Assert.IsFalse(PanelFoldersAreSame('sftp://u@h/a', 'sftp://u@h/b'), 'different remote folders');
end;

procedure TestJobOptionMaps;
begin
  Assert.IsTrue(JobOverwriteModeFromIndex(-1) = jomAsk, 'negative index -> ask');
  Assert.IsTrue(JobOverwriteModeFromIndex(0) = jomAsk, '0 -> ask');
  Assert.IsTrue(JobOverwriteModeFromIndex(1) = jomOverwrite, '1 -> overwrite');
  Assert.IsTrue(JobOverwriteModeFromIndex(2) = jomSkip, '2 -> skip');
  Assert.IsTrue(JobRetryLimitFromIndex(0) = 0, 'retry 0 -> 0');
  Assert.IsTrue(JobRetryLimitFromIndex(1) = 1, 'retry 1 -> 1');
  Assert.IsTrue(JobRetryLimitFromIndex(2) = 3, 'retry 2 -> 3');
  Assert.IsTrue(JobRetryLimitFromIndex(-1) = 1, 'retry other -> 1');
  Assert.IsTrue(JobConflictActionFromCommand(cDlgCmdOverwrite) = jcaOverwrite, 'overwrite cmd');
  Assert.IsTrue(JobConflictActionFromCommand(cDlgCmdSkip) = jcaSkip, 'skip cmd');
  Assert.IsTrue(JobConflictActionFromCommand(cDlgCmdAppend) = jcaAppend, 'append cmd');
  Assert.IsTrue(JobConflictActionFromCommand(cDlgCmdCancel) = jcaCancel, 'cancel cmd');
  Assert.IsTrue(JobConfirmWantsBackground(cDlgCmdBackground), 'background confirm cmd');
  Assert.IsTrue(not JobConfirmWantsBackground(cDlgCmdOk), 'ok stays foreground');
  Assert.IsTrue(JobDeleteFailActionFromCommand(cDlgCmdOk, True) = jdaPermanent, 'recycle ok -> permanent');
  Assert.IsTrue(JobDeleteFailActionFromCommand(cDlgCmdRetry, False) = jdaRetry, 'wipe retry');
  Assert.IsTrue(JobDeleteFailActionFromCommand(cDlgCmdSkip, True) = jdaSkip, 'skip');
  Assert.IsTrue(JobDeleteFailActionFromCommand(cDlgCmdSkipAll, False) = jdaSkipAll, 'skip all');
  Assert.IsTrue(JobDeleteFailActionFromCommand(cDlgCmdCancel, True) = jdaCancel, 'cancel delete');
end;

procedure TestDestAndPack;
var
  Err: string;
  Src: TArray<string>;
begin
  Assert.IsTrue(JobConfirmDestUri(pjkCopy, '', 'file:///C:/dst/') = 'file:///C:/dst/',
    'empty dest keeps fallback');
  Assert.IsTrue(FileUriToPath('tmp:///') = '', 'tmp URI is not a local path');
  Assert.IsTrue(JobConfirmDestUri(pjkCopy, '', 'tmp:///') = 'tmp:///',
    'empty dest keeps tmp fallback');
  Assert.IsTrue(JobConfirmDestUri(pjkCopy, 'tmp:///', 'tmp:///') = 'tmp:///',
    'typed tmp URI is not converted to file://');
  Assert.IsTrue(JobDestRejectedReason(pjkCopy, 'tmp:///') = '',
    'copy onto tmp panel is allowed');
  Assert.IsTrue(FileUriToPath('ws:///') = '', 'ws URI is not a local path');
  Assert.IsTrue(IsWorkspaceUri('ws:///'), 'ws:/// is workspace');
  Assert.IsTrue(not IsWorkspaceUri('wasmdemo:///'), 'wasmdemo is not workspace');
  Assert.IsTrue(JoinVfsUri('ws:///', 'x.txt') = 'ws:///x.txt', 'ws join is hierarchical');
  Assert.IsTrue(JoinVfsUri('ws:///group', 'a.txt') = 'ws:///group/a.txt', 'ws nested join');
  Assert.IsTrue(ParentVfsUri('ws:///group/a.txt') = 'ws:///group', 'ws parent');
  Assert.IsTrue(ParentVfsUri('ws:///group') = 'ws:///', 'ws parent of child is root');
  Assert.IsTrue(ParentVfsUri('ws:///') = 'ws:///', 'ws root parent stays');
  Assert.IsTrue(VfsUriTitle('ws:///') = 'Workspace', 'ws root title');
  Assert.IsTrue(VfsUriTitle('ws:///group') = 'group', 'ws folder title');
  Assert.IsTrue(SameVfsUri('ws:///', 'ws://foo') = False, 'ws root is not a nested folder');
  Assert.IsTrue(SameVfsUri('ws:///a', 'ws:///A'), 'ws path compare is case-insensitive');
  Assert.IsTrue(JobConfirmDestUri(pjkCopy, 'ws:///', 'ws:///') = 'ws:///',
    'typed ws URI is not converted to file://');
  Assert.IsTrue(JobDestRejectedReason(pjkCopy, 'ws:///') = '',
    'copy onto workspace panel is allowed');
  Assert.IsTrue(SameVfsUri('tmp:///', 'tmp://foo'), 'tmp URIs compare as one root');
  Assert.IsTrue(not SameVfsUri('tmp:///', 'sys://folders'), 'tmp is not sys');
  Assert.AreEqual('file:///C:/a.zip!/', JobConfirmDestText(pjkCopy, 'file:///C:/a.zip!/'),
    'an archive destination is shown as its URI');
  Assert.AreEqual('file:///C:/a.zip!/', JobConfirmDestUri(pjkCopy,
    JobConfirmDestText(pjkCopy, 'file:///C:/a.zip!/'), ''),
    'the shown archive URI is read back unchanged');
  Assert.AreEqual('tmp:///', JobConfirmDestText(pjkCopy, 'tmp:///'));
  Assert.AreEqual(IncludeTrailingPathDelimiter('C:\dst'),
    JobConfirmDestText(pjkCopy, PathToFileUri('C:\dst')), 'a folder keeps the trailing slash');
  Assert.AreEqual('C:\out\pack.zip', JobConfirmDestText(pjkPack, PathToFileUri('C:\out\pack.zip')),
    'a pack target has no trailing slash');
  Assert.IsTrue(JobConfirmDestUri(pjkPack, 'C:\out\pack', 'file:///C:/dst/') =
    PathToFileUri('C:\out\pack.zip'), 'pack dest gains .zip');
  Assert.AreEqual(PathToFileUri('C:\out\pack.7z'),
    JobConfirmDestUri(pjkPack, 'C:\out\pack', 'file:///C:/dst/', cPackType7z, cPackTypeZip),
    'a name without extension gets the picked type');
  Assert.AreEqual(PathToFileUri('C:\out\pack.7z'),
    JobConfirmDestUri(pjkPack, 'C:\out\pack.zip', 'file:///C:/dst/', cPackType7z, cPackTypeZip),
    'a changed type replaces the typed extension');
  Assert.AreEqual(PathToFileUri('C:\out\pack.zip'),
    JobConfirmDestUri(pjkPack, 'C:\out\pack.7z', 'file:///C:/dst/', cPackTypeZip, cPackType7z),
    'a changed type replaces .7z too');
  Assert.AreEqual(PathToFileUri('C:\out\pack.7z'),
    JobConfirmDestUri(pjkPack, 'C:\out\pack.7z', 'file:///C:/dst/', cPackTypeZip, cPackTypeZip),
    'an unchanged type keeps the extension typed in the name');
  Assert.AreEqual(PathToFileUri('C:\out\pack.tar.7z'),
    JobConfirmDestUri(pjkPack, 'C:\out\pack.tar', 'file:///C:/dst/', cPackType7z, cPackType7z),
    'an unknown extension is kept and the type is appended');
  Assert.AreEqual(0, JobPackLevelFromIndex(0), 'Store');
  Assert.AreEqual(5, JobPackLevelFromIndex(3), 'Normal');
  Assert.AreEqual(9, JobPackLevelFromIndex(5), 'Ultra');
  Assert.AreEqual(5, JobPackLevelFromIndex(-1), 'no pick -> Normal');
  Assert.AreEqual('.zip', JobPackArchiveExt(cPackTypeZip));
  Assert.AreEqual('.7z', JobPackArchiveExt(cPackType7z));
  Assert.AreEqual(cPackType7z, JobPackTypeFromPath('C:\x\A.7Z'));
  Assert.AreEqual(-1, JobPackTypeFromPath('C:\x\a.rar'));
  Assert.IsTrue(JobConfirmDestUri(pjkPack, 'C:\out\a.7z', 'file:///C:/dst/') =
    PathToFileUri('C:\out\a.7z'), 'pack dest already 7z');
  Assert.IsTrue(JobDestRejectedReason(pjkPack, '7z:///C:/a.7z!/') = '',
    'pack into 7z:// allowed');
  Assert.IsTrue(JobDestRejectedReason(pjkCopy, '7z:///C:/a.7z!/') = '',
    'copy into 7z:// allowed');
  Assert.IsTrue(JobDestRejectedReason(pjkDelete, 'zip://x') = '', 'delete ignores dest');
  Assert.IsTrue(JobDestRejectedReason(pjkCopy, 'file:///C:/a.zip!/inner') = '',
    'copy into a zip is written by the built-in ZIP layer');
  Assert.IsTrue(JobDestRejectedReason(pjkMove, 'file:///C:/a.zip!/') = '',
    'move into a zip allowed');
  Assert.IsTrue(JobDestRejectedReason(pjkCopy, 'file:///C:/a.zip!/b.zip!/x') <> '',
    'copy into a nested archive rejected');
  Assert.IsTrue(JobDestRejectedReason(pjkCopy, 'sys://folders') <> '', 'copy into sys folders rejected');
  Assert.IsTrue(JobDestRejectedReason(pjkCopy, 'sftp://u@h/path') = '',
    'copy onto sftp:// is allowed');
  Assert.IsTrue(JobDestRejectedReason(pjkMove, 'sftp://u@h/path') = '',
    'move onto sftp:// is allowed');
  Assert.IsTrue(JobDestFailTitle(pjkMove) = 'Move failed', 'move title');
  Assert.IsTrue(JobDestFailTitle(pjkPack) = 'Pack failed', 'pack title');
  Assert.IsTrue(JobDestFailTitle(pjkCopy) = 'Copy failed', 'copy title');

  SetLength(Src, 2);
  Src[0] := PathToFileUri('C:\work\proj\a.txt');
  Src[1] := PathToFileUri('C:\work\proj\b.txt');
  Assert.AreEqual('proj.zip', SuggestPackArchiveName(Src), 'name of the source folder');
  Assert.AreEqual('proj.7z', SuggestPackArchiveName(Src, cPackType7z), '7z extension');
  SetLength(Src, 1);
  Src[0] := PathToFileUri('C:\work\proj\sub');
  Assert.AreEqual('proj.zip', SuggestPackArchiveName(Src),
    'a folder is named after the folder that holds it');
  Src[0] := PathToFileUri('C:\a.txt');
  Assert.AreEqual('C.zip', SuggestPackArchiveName(Src), 'drive root -> drive letter');
  Src[0] := 'sys://folders';
  Assert.AreEqual('archive.zip', SuggestPackArchiveName(Src), 'no local folder -> archive');
  SetLength(Src, 0);
  Assert.AreEqual('archive.7z', SuggestPackArchiveName(Src, cPackType7z), 'no sources');
  SetLength(Src, 1);
  Src[0] := 'file:///C:/docs/folder/';
  Assert.IsTrue(not SourcesContainArchive(Src), 'plain file is not archive');
  Src[0] := 'file:///C:/a.zip!/x';
  Assert.IsTrue(SourcesContainArchive(Src), 'zip inner path is archive');

  Src[0] := 'file:///C:/a.txt';
  Assert.IsTrue(not UnpackSourcesAreValid(Src, Err), 'plain file not unpackable');
  Assert.IsTrue(Err <> '', 'unpack error message');
  Src[0] := 'file:///C:/a.zip';
  Assert.IsTrue(UnpackSourcesAreValid(Src, Err), 'zip file unpackable');
  Assert.IsTrue(Err = '', 'no error on zip');
  Src[0] := 'file:///C:/a.zip!/inner';
  Assert.IsTrue(UnpackSourcesAreValid(Src, Err), 'archive chain unpackable');
  SetLength(Src, 0);
  Assert.IsTrue(not UnpackSourcesAreValid(Src, Err), 'empty sources not unpackable');
  Assert.IsTrue(Err = '', 'empty sources silent');
end;

procedure TestPackIntoRenamedSevenZip;
var
  Dir, Archive, Plain: string;
  Sig: TBytes;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-pack-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Dir);
  try
    Archive := TPath.Combine(Dir, 'data.8z');
    Plain := TPath.Combine(Dir, 'notes.8z');
    Sig := TBytes.Create($37, $7A, $BC, $AF, $27, $1C, 0, 4, 0, 0, 0, 0);
    TFile.WriteAllBytes(Archive, Sig);
    TFile.WriteAllText(Plain, 'just text, not an archive');
    Assert.IsTrue(IsSevenZipArchivePath(Archive), 'a renamed 7z file is recognised by its signature');
    Assert.IsFalse(IsSevenZipArchivePath(Plain), 'a text file with the same extension is not');
    Assert.IsFalse(IsSevenZipArchivePath(TPath.Combine(Dir, 'missing.8z')), 'a name that does not exist is not');
    Assert.IsTrue(IsSevenZipArchivePath(TPath.Combine(Dir, 'new.7z')), 'a .7z name needs no file');
    Assert.AreEqual(cPackType7z, JobPackTypeFromPath(Archive), 'the renamed archive packs as 7z');
    Assert.AreEqual(-1, JobPackTypeFromPath(Plain), 'a text file is no archive type');
    Assert.AreEqual(PathToFileUri(Archive),
      JobConfirmDestUri(pjkPack, Archive, 'file:///C:/dst/', cPackTypeZip, cPackTypeZip),
      'files are added to the renamed archive, no extension is appended');
    Assert.AreEqual(PathToFileUri(Plain + '.zip'),
      JobConfirmDestUri(pjkPack, Plain, 'file:///C:/dst/', cPackTypeZip, cPackTypeZip),
      'an unknown name still gets the picked extension');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TestCollectSources;
var
  Tab: TTab;
  Rows: TPanelRows;
  Src: TArray<string>;
begin
  Tab := MakeTab(1, 't', 'file:///C:/');
  SetLength(Rows, 3);
  Rows[0] := MakePanelRow('..', True, -1, '', '', 'file:///C:/parent', True);
  Rows[1] := MakePanelRow('a.txt', False, 1, '1', '', 'file:///C:/a.txt');
  Rows[2] := MakePanelRow('b.txt', False, 1, '1', '', 'file:///C:/b.txt');
  Tab.CursorIndex := 0;
  Src := CollectPanelJobSources(Tab, Rows);
  Assert.IsTrue(Length(Src) = 0, 'parent cursor is not a source');
  Tab.CursorIndex := 1;
  Src := CollectPanelJobSources(Tab, Rows);
  Assert.IsTrue((Length(Src) = 1) and (Src[0] = 'file:///C:/a.txt'), 'cursor file is source');
  TabSetSelected(Tab, Rows[1].URI, True);
  TabSetSelected(Tab, Rows[2].URI, True);
  Src := CollectPanelJobSources(Tab, Rows);
  Assert.IsTrue(Length(Src) = 2, 'selection collects both files');
  Assert.IsTrue(Src[0] = 'file:///C:/a.txt', 'selection order follows rows');
end;

procedure TestSearchRootAndSync;
var
  Items: TArray<TSyncItem>;
  Sources, Dests: TArray<string>;
  Root: string;
begin
  Root := ResolveSearchRootPath('file:///C:/');
  Assert.IsTrue((Root <> '') and (Root[Length(Root)] = PathDelim),
    'drive-root search path has delimiter');
  Assert.IsTrue(ResolveSearchRootPath('find://missing') = '', 'unknown find uri -> empty');
  Assert.IsTrue(Pos('zip', LowerCase(ResolveSearchRootPath('file:///C:/temp/a.zip!/inner'))) = 0,
    'archive search root is the zip parent dir');
  Assert.IsTrue(DirSyncUrisAreLocalFolders('file:///C:/a', 'file:///D:/b'), 'two file uris ok');
  Assert.IsTrue(not DirSyncUrisAreLocalFolders('file:///C:/a.zip!/x', 'file:///D:/b'),
    'archive src rejected');
  Assert.IsTrue(not DirSyncUrisAreLocalFolders('file:///C:/a', 'find://1'), 'find dst rejected');

  SetLength(Items, 3);
  Items[0].RelPath := 'a.txt';
  Items[0].SrcURI := 'file:///C:/src/a.txt';
  Items[0].DstURI := 'file:///D:/dst/a.txt';
  Items[0].Reason := srMissing;
  Items[1].RelPath := 'b.txt';
  Items[1].SrcURI := 'file:///C:/src/b.txt';
  Items[1].DstURI := 'file:///D:/dst/b.txt';
  Items[1].Reason := srNewer;
  Items[2].RelPath := 'c.txt';
  Items[2].SrcURI := 'file:///C:/src/c.txt';
  Items[2].DstURI := 'file:///D:/dst/c.txt';
  Items[2].Reason := srMissing;
  Assert.IsTrue(FormatDirSyncStatus(Items) = '3 to copy (2 missing, 1 newer)', 'status text');
  CollectDirSyncJobPairs(Items, Sources, Dests);
  Assert.IsTrue((Length(Sources) = 3) and (Sources[1] = Items[1].SrcURI), 'sync sources');
  Assert.IsTrue(Dests[2] = Items[2].DstURI, 'sync dests');
  Items[2].Reason := srNewerOnDst;
  SetLength(Items, 4);
  Items[3].RelPath := 'd.txt';
  Items[3].SrcURI := 'file:///D:/dst/d.txt';
  Items[3].DstURI := 'file:///C:/src/d.txt';
  Items[3].Reason := srConflict;
  Assert.IsTrue(Pos('conflict', FormatDirSyncStatus(Items)) > 0, 'two-way status names conflicts');
  CollectDirSyncJobPairs(Items, Sources, Dests, True);
  Assert.IsTrue(Length(Sources) = 3, 'two-way job skips the conflict');
  CollectDirSyncJobPairs(Items, Sources, Dests, False);
  Assert.IsTrue(Length(Sources) = 2, 'one-way job skips reverse and conflict');
end;

{ TTestDualPanelJobDialogs }

procedure TTestDualPanelJobDialogs.TestPanelFoldersAreSame;
begin
  TestDualPanelJobDialogs.TestPanelFoldersAreSame;
end;

procedure TTestDualPanelJobDialogs.TestConfirmIntoSameFolderStaysOpen;
begin
  TestDualPanelJobDialogs.TestConfirmIntoSameFolderStaysOpen;
end;

procedure TTestDualPanelJobDialogs.TestJobOptionMaps;
begin
  TestDualPanelJobDialogs.TestJobOptionMaps;
end;

procedure TTestDualPanelJobDialogs.TestDestAndPack;
begin
  TestDualPanelJobDialogs.TestDestAndPack;
end;

procedure TTestDualPanelJobDialogs.TestPackIntoRenamedSevenZip;
begin
  TestDualPanelJobDialogs.TestPackIntoRenamedSevenZip;
end;

procedure TTestDualPanelJobDialogs.TestCollectSources;
begin
  TestDualPanelJobDialogs.TestCollectSources;
end;

procedure TTestDualPanelJobDialogs.TestSearchRootAndSync;
begin
  TestDualPanelJobDialogs.TestSearchRootAndSync;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelJobDialogs);

end.
