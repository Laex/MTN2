program TestDualPanelJobDialogs;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uDialogTypes in '..\..\Core\uDialogTypes.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uDualPanelTypes in '..\..\Core\uDualPanelTypes.pas',
  uDualPanelUiTypes in '..\..\Core\uDualPanelUiTypes.pas',
  uDualPanelSelection in '..\..\Core\uDualPanelSelection.pas',
  uDualPanelSync in '..\..\Core\uDualPanelSync.pas',
  uFindSession in '..\..\Core\uFindSession.pas',
  uDualPanelJobDialogs in '..\..\Core\uDualPanelJobDialogs.pas',
  uDualPanelJobRules in '..\..\Core\uDualPanelJobRules.pas',
  uDualPanelFindDialogs in '..\..\Core\uDualPanelFindDialogs.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

procedure TestJobOptionMaps;
begin
  Writeln('Job option maps');
  Expect(JobOverwriteModeFromIndex(-1) = jomAsk, 'negative index -> ask');
  Expect(JobOverwriteModeFromIndex(0) = jomAsk, '0 -> ask');
  Expect(JobOverwriteModeFromIndex(1) = jomOverwrite, '1 -> overwrite');
  Expect(JobOverwriteModeFromIndex(2) = jomSkip, '2 -> skip');
  Expect(JobRetryLimitFromIndex(0) = 0, 'retry 0 -> 0');
  Expect(JobRetryLimitFromIndex(1) = 1, 'retry 1 -> 1');
  Expect(JobRetryLimitFromIndex(2) = 3, 'retry 2 -> 3');
  Expect(JobRetryLimitFromIndex(-1) = 1, 'retry other -> 1');
  Expect(JobConflictActionFromCommand(cDlgCmdOverwrite) = jcaOverwrite, 'overwrite cmd');
  Expect(JobConflictActionFromCommand(cDlgCmdSkip) = jcaSkip, 'skip cmd');
  Expect(JobConflictActionFromCommand(cDlgCmdAppend) = jcaAppend, 'append cmd');
  Expect(JobConflictActionFromCommand(cDlgCmdCancel) = jcaCancel, 'cancel cmd');
  Expect(JobConfirmWantsBackground(cDlgCmdBackground), 'background confirm cmd');
  Expect(not JobConfirmWantsBackground(cDlgCmdOk), 'ok stays foreground');
  Expect(JobDeleteFailActionFromCommand(cDlgCmdOk, True) = jdaPermanent, 'recycle ok -> permanent');
  Expect(JobDeleteFailActionFromCommand(cDlgCmdRetry, False) = jdaRetry, 'wipe retry');
  Expect(JobDeleteFailActionFromCommand(cDlgCmdSkip, True) = jdaSkip, 'skip');
  Expect(JobDeleteFailActionFromCommand(cDlgCmdSkipAll, False) = jdaSkipAll, 'skip all');
  Expect(JobDeleteFailActionFromCommand(cDlgCmdCancel, True) = jdaCancel, 'cancel delete');
end;

procedure TestDestAndPack;
var
  Err: string;
  Src: TArray<string>;
begin
  Writeln('Dest / pack / unpack');
  Expect(JobConfirmDestUri(pjkCopy, '', 'file:///C:/dst/') = 'file:///C:/dst/',
    'empty dest keeps fallback');
  Expect(FileUriToPath('tmp:///') = '', 'tmp URI is not a local path');
  Expect(JobConfirmDestUri(pjkCopy, '', 'tmp:///') = 'tmp:///',
    'empty dest keeps tmp fallback');
  Expect(JobConfirmDestUri(pjkCopy, 'tmp:///', 'tmp:///') = 'tmp:///',
    'typed tmp URI is not converted to file://');
  Expect(JobDestRejectedReason(pjkCopy, 'tmp:///') = '',
    'copy onto tmp panel is allowed');
  Expect(FileUriToPath('ws:///') = '', 'ws URI is not a local path');
  Expect(IsWorkspaceUri('ws:///'), 'ws:/// is workspace');
  Expect(not IsWorkspaceUri('wasmdemo:///'), 'wasmdemo is not workspace');
  Expect(JoinVfsUri('ws:///', 'x.txt') = 'ws:///x.txt', 'ws join is hierarchical');
  Expect(JoinVfsUri('ws:///group', 'a.txt') = 'ws:///group/a.txt', 'ws nested join');
  Expect(ParentVfsUri('ws:///group/a.txt') = 'ws:///group', 'ws parent');
  Expect(ParentVfsUri('ws:///group') = 'ws:///', 'ws parent of child is root');
  Expect(ParentVfsUri('ws:///') = 'ws:///', 'ws root parent stays');
  Expect(VfsUriTitle('ws:///') = 'Workspace', 'ws root title');
  Expect(VfsUriTitle('ws:///group') = 'group', 'ws folder title');
  Expect(SameVfsUri('ws:///', 'ws://foo') = False, 'ws root is not a nested folder');
  Expect(SameVfsUri('ws:///a', 'ws:///A'), 'ws path compare is case-insensitive');
  Expect(JobConfirmDestUri(pjkCopy, 'ws:///', 'ws:///') = 'ws:///',
    'typed ws URI is not converted to file://');
  Expect(JobDestRejectedReason(pjkCopy, 'ws:///') = '',
    'copy onto workspace panel is allowed');
  Expect(SameVfsUri('tmp:///', 'tmp://foo'), 'tmp URIs compare as one root');
  Expect(not SameVfsUri('tmp:///', 'sys://folders'), 'tmp is not sys');
  Expect(JobConfirmDestUri(pjkPack, 'C:\out\pack', 'file:///C:/dst/') =
    PathToFileUri('C:\out\pack.zip'), 'pack dest gains .zip');
  Expect(JobConfirmDestUri(pjkPack, 'C:\out\a.7z', 'file:///C:/dst/') =
    PathToFileUri('C:\out\a.7z'), 'pack dest already 7z');
  Expect(JobDestRejectedReason(pjkPack, '7z:///C:/a.7z!/') = '',
    'pack into 7z:// allowed');
  Expect(JobDestRejectedReason(pjkCopy, '7z:///C:/a.7z!/') = '',
    'copy into 7z:// allowed');
  Expect(JobDestRejectedReason(pjkDelete, 'zip://x') = '', 'delete ignores dest');
  Expect(JobDestRejectedReason(pjkCopy, 'file:///C:/a.zip!/inner') <> '',
    'copy into archive rejected');
  Expect(JobDestRejectedReason(pjkCopy, 'sys://folders') <> '', 'copy into sys folders rejected');
  Expect(JobDestRejectedReason(pjkCopy, 'sftp://u@h/path') = '',
    'copy onto sftp:// is allowed');
  Expect(JobDestRejectedReason(pjkMove, 'sftp://u@h/path') = '',
    'move onto sftp:// is allowed');
  Expect(JobDestFailTitle(pjkMove) = 'Move failed', 'move title');
  Expect(JobDestFailTitle(pjkPack) = 'Pack failed', 'pack title');
  Expect(JobDestFailTitle(pjkCopy) = 'Copy failed', 'copy title');

  SetLength(Src, 2);
  Src[0] := 'file:///C:/a.txt';
  Src[1] := 'file:///C:/b.txt';
  Expect(SuggestPackZipName(Src) = 'archive.zip', 'multi -> archive.zip');
  SetLength(Src, 1);
  Src[0] := 'file:///C:/docs/file.txt';
  Expect(SuggestPackZipName(Src) = 'file.zip', 'single file -> file.zip');
  Src[0] := 'file:///C:/docs/folder/';
  Expect(SuggestPackZipName(Src) = ChangeFileExt('folder', '') + '.zip',
    'single dir -> folder.zip');
  Expect(not SourcesContainArchive(Src), 'plain file is not archive');
  Src[0] := 'file:///C:/a.zip!/x';
  Expect(SourcesContainArchive(Src), 'zip inner path is archive');

  Src[0] := 'file:///C:/a.txt';
  Expect(not UnpackSourcesAreValid(Src, Err), 'plain file not unpackable');
  Expect(Err <> '', 'unpack error message');
  Src[0] := 'file:///C:/a.zip';
  Expect(UnpackSourcesAreValid(Src, Err), 'zip file unpackable');
  Expect(Err = '', 'no error on zip');
  Src[0] := 'file:///C:/a.zip!/inner';
  Expect(UnpackSourcesAreValid(Src, Err), 'archive chain unpackable');
  SetLength(Src, 0);
  Expect(not UnpackSourcesAreValid(Src, Err), 'empty sources not unpackable');
  Expect(Err = '', 'empty sources silent');
end;

procedure TestCollectSources;
var
  Tab: TTab;
  Rows: TPanelRows;
  Src: TArray<string>;
begin
  Writeln('CollectPanelJobSources');
  Tab := MakeTab(1, 't', 'file:///C:/');
  SetLength(Rows, 3);
  Rows[0] := MakePanelRow('..', True, -1, '', '', 'file:///C:/parent', True);
  Rows[1] := MakePanelRow('a.txt', False, 1, '1', '', 'file:///C:/a.txt');
  Rows[2] := MakePanelRow('b.txt', False, 1, '1', '', 'file:///C:/b.txt');
  Tab.CursorIndex := 0;
  Src := CollectPanelJobSources(Tab, Rows);
  Expect(Length(Src) = 0, 'parent cursor is not a source');
  Tab.CursorIndex := 1;
  Src := CollectPanelJobSources(Tab, Rows);
  Expect((Length(Src) = 1) and (Src[0] = 'file:///C:/a.txt'), 'cursor file is source');
  TabSetSelected(Tab, Rows[1].URI, True);
  TabSetSelected(Tab, Rows[2].URI, True);
  Src := CollectPanelJobSources(Tab, Rows);
  Expect(Length(Src) = 2, 'selection collects both files');
  Expect(Src[0] = 'file:///C:/a.txt', 'selection order follows rows');
end;

procedure TestSearchRootAndSync;
var
  Items: TArray<TSyncItem>;
  Sources, Dests: TArray<string>;
  Root: string;
begin
  Writeln('Search root / dirsync');
  Root := ResolveSearchRootPath('file:///C:/');
  Expect((Root <> '') and (Root[Length(Root)] = PathDelim),
    'drive-root search path has delimiter');
  Expect(ResolveSearchRootPath('find://missing') = '', 'unknown find uri -> empty');
  Expect(Pos('zip', LowerCase(ResolveSearchRootPath('file:///C:/temp/a.zip!/inner'))) = 0,
    'archive search root is the zip parent dir');
  Expect(DirSyncUrisAreLocalFolders('file:///C:/a', 'file:///D:/b'), 'two file uris ok');
  Expect(not DirSyncUrisAreLocalFolders('file:///C:/a.zip!/x', 'file:///D:/b'),
    'archive src rejected');
  Expect(not DirSyncUrisAreLocalFolders('file:///C:/a', 'find://1'), 'find dst rejected');

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
  Expect(FormatDirSyncStatus(Items) = '3 to copy (2 missing, 1 newer)', 'status text');
  CollectDirSyncJobPairs(Items, Sources, Dests);
  Expect((Length(Sources) = 3) and (Sources[1] = Items[1].SrcURI), 'sync sources');
  Expect(Dests[2] = Items[2].DstURI, 'sync dests');
  Items[2].Reason := srNewerOnDst;
  SetLength(Items, 4);
  Items[3].RelPath := 'd.txt';
  Items[3].SrcURI := 'file:///D:/dst/d.txt';
  Items[3].DstURI := 'file:///C:/src/d.txt';
  Items[3].Reason := srConflict;
  Expect(Pos('conflict', FormatDirSyncStatus(Items)) > 0, 'two-way status names conflicts');
  CollectDirSyncJobPairs(Items, Sources, Dests, True);
  Expect(Length(Sources) = 3, 'two-way job skips the conflict');
  CollectDirSyncJobPairs(Items, Sources, Dests, False);
  Expect(Length(Sources) = 2, 'one-way job skips reverse and conflict');
end;

begin
  try
    TestJobOptionMaps;
    TestDestAndPack;
    TestCollectSources;
    TestSearchRootAndSync;
    Writeln('All DualPanelJobDialogs tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
