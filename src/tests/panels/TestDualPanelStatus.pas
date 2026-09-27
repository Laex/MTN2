unit TestDualPanelStatus;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelStatus = class
  public
    [Test] procedure TestPosAndTruncate;
    [Test] procedure TestChromeAndDefault;
    [Test] procedure TestChromeContext;
    [Test] procedure TestPathSideAndItem;
    [Test] procedure TestAssembleAndPaint;
    [Test] procedure TestReplaceHintMapsToF7;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uTerminalTypes,
  uThemeTypes,
  uKeymap,
  uFunctionBar,
  uVfsTypes,
  uDualPanelTypes,
  uDualPanelUiTypes,
  uDualPanelStatus;

type
  TChromeSpy = class
  public
    Calls: Integer;
    Ctx: TFunctionBarContext;
    function Get: TFunctionBarContext;
  end;

function TChromeSpy.Get: TFunctionBarContext;
begin
  Inc(Calls);
  Result := Ctx;
end;

procedure TestPosAndTruncate;
begin
  Assert.IsTrue(FormatPanelPosText(0, 5) = '0/0', 'empty list');
  Assert.IsTrue(FormatPanelPosText(10, 0) = '1/10', 'first is 1-based');
  Assert.IsTrue(FormatPanelPosText(10, 9) = '10/10', 'last');
  Assert.IsTrue(FormatPanelPosText(10, 99) = '10/10', 'clamp high');
  Assert.IsTrue(TruncateStatusPath('abcdefghij', 8) = '?defghij', 'path ellipsis');
  Assert.IsTrue(TruncateStatusPath('short', 40) = 'short', 'short path kept');
  Assert.IsTrue(TruncateStatusItem('abcdefghijklmnopqrstuvwxyz12', 28) =
    'abcdefghijklmnopqrstuvwxyz12', 'item at limit kept');
  Assert.IsTrue(TruncateStatusItem('abcdefghijklmnopqrstuvwxyz123', 28) =
    'abcdefghijklmnopqrstuv...123', 'item mid-ellipsis');
  Assert.IsTrue(Copy(TruncateStatusItem('LongDocumentNameHere.docx', 20), 16, 5) =
    '.docx', 'item keeps extension');
  Assert.IsTrue(Pos('...', TruncateStatusItem('LongDocumentNameHere.docx', 20)) > 0,
    'item uses ellipsis');
  Assert.IsTrue(Length(TruncateStatusItem('LongDocumentNameHere.docx', 20)) = 20,
    'item fits width');
  Assert.IsTrue(FormatStatusSelText(1024, 2, 1) = 'Sel 1 K (3)', 'sel totals');
end;

procedure TestChromeAndDefault;
var
  Info: TPanelChromeStatus;
  Segs: TArray<string>;
begin
  Info.Path := 'C:\Work';
  Info.DialogKind := hdkMkDir;
  Info.JobTitle := 'Copy';
  Info.JobMessage := '50%';
  Info.JobCurrent := 'a.txt';
  Info.SearchMask := '*.pas';
  Info.SearchDir := 'D:\';
  Info.SearchFound := 4;
  Info.SearchResultCount := 12;
  Info.StubText := 'Stub';
  Info.StubDetail := 'Detail';

  Assert.IsTrue(TryFormatChromeStatus(fbcDrive, Info, Segs) and (Segs[0] = 'Drive'),
    'drive chrome');
  Assert.IsTrue(TryFormatChromeStatus(fbcJob, Info, Segs) and (Segs[0] = 'Copy') and
    (Segs[2] = 'a.txt'), 'job chrome');
  Assert.IsTrue(TryFormatChromeStatus(fbcSearchRunning, Info, Segs) and
    (Segs[0] = 'Find 4'), 'search running');
  Assert.IsTrue(TryFormatChromeStatus(fbcStubEdit, Info, Segs) and (Segs[0] = 'MkDir'),
    'mkdir stub edit');
  Info.DialogKind := hdkWorkspaceLibrary;
  Assert.IsTrue(TryFormatChromeStatus(fbcWorkspaceLibrary, Info, Segs) and
    (Segs[0] = 'Workspaces') and (Pos('Ins=Save', string.Join(' ', Segs)) > 0),
    'workspace library status');
  Info.DialogKind := hdkTheme;
  Assert.IsTrue(TryFormatChromeStatus(fbcDialogList, Info, Segs) and (Segs[0] = 'Theme'),
    'theme list status');
  Info.DialogKind := hdkDisplay;
  Assert.IsTrue(TryFormatChromeStatus(fbcDialogList, Info, Segs) and (Segs[0] = 'Display'),
    'display list status');
  Info.DialogKind := hdkNone;
  Assert.IsTrue(TryFormatChromeStatus(fbcDialogList, Info, Segs) and (Segs[0] = 'Code page'),
    'encoding list status');
  Assert.IsTrue(not TryFormatChromeStatus(fbcPanels, Info, Segs), 'panels uses default');

  Segs := FormatDefaultPanelStatus('Left', 'C:\', '1/2', 'Full', 'readme.md',
    '1.2G', True, False);
  Assert.IsTrue((Length(Segs) = 6) and (Segs[0] = 'Left') and (Segs[3] = 'Full') and
    (Segs[4] = 'readme.md'), 'default panel segs');
  Segs := FormatDefaultPanelStatus('Right', 'C:\', '1/2', 'Full', 'x', '', True, True);
  Assert.IsTrue(Segs[4] = 'Cmdline', 'cmdline wins over item');
  Segs := FormatTerminalStatus(False, False, '');
  Assert.IsTrue((Length(Segs) = 1) and (Segs[0] = 'Terminal'), 'no terminal');
  Segs := FormatTerminalStatus(True, True, 'PowerShell');
  Assert.IsTrue((Segs[0] = 'PowerShell') and (Segs[1] = 'Running'), 'running terminal');
end;

procedure TestChromeContext;
var
  S: TChromeOverlayState;
begin
  S := Default(TChromeOverlayState);
  S.WorkspaceKind := wkPanels;
  Assert.IsTrue(ResolveChromeContext(S) = fbcPanels, 'plain panels');

  S.DialogVisible := True;
  S.DialogKind := hdkSearch;
  Assert.IsTrue(ResolveChromeContext(S) = fbcSearchDialog, 'search dialog');
  S.DialogKind := hdkJobConfirm;
  Assert.IsTrue(ResolveChromeContext(S) = fbcJob, 'job confirm dialog');
  S.DialogKind := hdkJobProgress;
  Assert.IsTrue(ResolveChromeContext(S) = fbcJobRunning, 'job progress dialog');
  S.DialogKind := hdkMkDir;
  S.DialogChrome := fbcStubEdit;
  Assert.IsTrue(ResolveChromeContext(S) = fbcStubEdit, 'mkdir uses stub-edit chrome');
  S.DialogKind := hdkWorkspaceLibrary;
  S.DialogChrome := fbcStubEdit;
  Assert.IsTrue(ResolveChromeContext(S) = fbcWorkspaceLibrary, 'workspaces list chrome');
  S.DialogKind := hdkFolderHotlist;
  Assert.IsTrue(ResolveChromeContext(S) = fbcFolderHotlist, 'hotlist chrome');
  S.DialogKind := hdkColorCoding;
  Assert.IsTrue(ResolveChromeContext(S) = fbcColorCoding, 'color coding chrome');
  S.DialogKind := hdkColorCodingEdit;
  Assert.IsTrue(ResolveChromeContext(S) = fbcColorCodingEdit, 'color edit chrome');
  S.DialogKind := hdkTheme;
  Assert.IsTrue(ResolveChromeContext(S) = fbcDialogList, 'theme list chrome');
  S.DialogKind := hdkDisplay;
  Assert.IsTrue(ResolveChromeContext(S) = fbcDialogList, 'display list chrome');
  S.DialogKind := hdkWorkspaceSave;
  Assert.IsTrue(ResolveChromeContext(S) = fbcStubEdit, 'workspace save chrome');
  S.StubVisible := True;
  Assert.IsTrue(ResolveChromeContext(S) = fbcStub, 'stub sits above dialog chrome');
  S.StubVisible := False;

  S := Default(TChromeOverlayState);
  S.DrivePopupVisible := True;
  Assert.IsTrue(ResolveChromeContext(S) = fbcDrive, 'drive popup');
  S.DrivePopupVisible := False;
  S.SortMenuVisible := True;
  Assert.IsTrue(ResolveChromeContext(S) = fbcUserMenu, 'sort menu');
  S.SortMenuVisible := False;
  S.JobPhase := pjpRunning;
  S.JobPresentation := jpForeground;
  S.JobShowsOverlay := True;
  Assert.IsTrue(ResolveChromeContext(S) = fbcJobRunning, 'foreground running job');
  S.JobPresentation := jpBackground;
  S.JobShowsOverlay := False;
  Assert.IsTrue(ResolveChromeContext(S) = fbcPanels, 'background running uses panel keys');
  S.JobPhase := pjpNone;
  S.SearchPhase := spResults;
  Assert.IsTrue(ResolveChromeContext(S) = fbcSearchResults, 'search results');
  S.SearchPhase := spNone;
  S.ConsoleMode := True;
  Assert.IsTrue(ResolveChromeContext(S) = fbcConsole, 'console');
  S.ConsoleMode := False;
  S.WorkspaceKind := wkTerminal;
  Assert.IsTrue(ResolveChromeContext(S) = fbcTerminal, 'terminal workspace');
  S.WorkspaceKind := wkPanels;
  S.CurrentURI := 'sys://folders';
  Assert.IsTrue(ResolveChromeContext(S) = fbcSysFolders, 'sys folders');
  S.CurrentURI := 'recycle:///';
  Assert.IsTrue(ResolveChromeContext(S) = fbcRecycleBin, 'recycle bin');
  S.CurrentURI := 'tmp:///';
  Assert.IsTrue(ResolveChromeContext(S) = fbcTmpPanel, 'tmp panel');
  S.CurrentURI := 'ws:///';
  Assert.IsTrue(ResolveChromeContext(S) = fbcWorkspace, 'workspace root');
  S.CurrentURI := 'ws:///group';
  Assert.IsTrue(ResolveChromeContext(S) = fbcWorkspace, 'workspace nested');
end;

procedure TestPathSideAndItem;
begin
  Assert.IsTrue(StatusPathLabel('recycle://C:/') = 'Recycle Bin', 'recycle title');
  Assert.IsTrue(StatusPathLabel('tmp:///') = 'Temporary', 'tmp title');
  Assert.IsTrue(StatusPathLabel('ws:///') = 'Workspace', 'ws title');
  Assert.IsTrue(StatusPathLabel('ws:///group') = 'Workspace\group', 'ws nested title');
  Assert.IsTrue(StatusPathLabel('file:///C:/Work') = FileUriToPath('file:///C:/Work'),
    'file URI becomes path');
  Assert.IsTrue(StatusPathLabel('file://localhost') = 'file://localhost',
    'empty path falls back to URI');
  Assert.IsTrue(PanelSideStatusLabel(psLeft) = 'Left', 'left side');
  Assert.IsTrue(PanelSideStatusLabel(psRight) = 'Right', 'right side');
  Assert.IsTrue(StatusItemText(True, 'Sel 1 K (3)', True, 'readme.md') = 'Sel 1 K (3)',
    'selection wins over cursor');
  Assert.IsTrue(StatusItemText(False, '', True, 'abcdefghijklmnopqrstuvwxyz123') =
    TruncateStatusItem('abcdefghijklmnopqrstuvwxyz123'), 'cursor truncated');
  Assert.IsTrue(StatusItemText(False, '', False, 'x') = '', 'empty when neither');
end;

procedure TestAssembleAndPaint;
var
  Spy: TChromeSpy;
  Host: TDualPanelStatusHost;
  Snap: TPanelStatusSnapshot;
  Overlay: TStatusOverlaySnapshot;
  Segs: TArray<string>;
  Grid: TTerminalGrid;
  Joined: string;
begin
  Overlay := Default(TStatusOverlaySnapshot);
  Overlay.JobTitle := 'Copy';
  Overlay.JobMessage := '50%';
  Overlay.JobCurrent := 'a.txt';
  Assert.IsTrue(MakeChromeStatus('C:\Work', Overlay).Path = 'C:\Work', 'chrome path');
  Assert.IsTrue(MakeChromeStatus('C:\Work', Overlay).JobTitle = 'Copy', 'chrome job');

  Spy := TChromeSpy.Create;
  try
    Host := Default(TDualPanelStatusHost);
    Host.ChromeContext := Spy.Get;
    Snap := Default(TPanelStatusSnapshot);
    Snap.Kind := wkTerminal;
    Snap.TermAssigned := False;
    Segs := AssembleStatusSegments(Host, Snap);
    Assert.IsTrue((Length(Segs) = 1) and (Segs[0] = 'Terminal'), 'terminal without chrome');
    Assert.IsTrue(Spy.Calls = 0, 'terminal skips ChromeContext');

    Snap := Default(TPanelStatusSnapshot);
    Snap.Kind := wkPanels;
    Snap.Chrome := MakeChromeStatus('C:\', Overlay);
    Spy.Ctx := fbcJob;
    Segs := AssembleStatusSegments(Host, Snap);
    Assert.IsTrue((Segs[0] = 'Copy') and (Segs[2] = 'a.txt'), 'job chrome via host');
    Assert.IsTrue(Spy.Calls = 1, 'chrome asks ChromeContext once');

    Spy.Calls := 0;
    Spy.Ctx := fbcPanels;
    Snap.SideLabel := 'Left';
    Snap.Path := 'C:\';
    Snap.PosText := '1/2';
    Snap.ColMode := 'Full';
    Snap.ItemText := 'readme.md';
    Snap.FreeText := '1.2G';
    Segs := AssembleStatusSegments(Host, Snap);
    Assert.IsTrue((Length(Segs) = 6) and (Segs[0] = 'Left') and (Segs[3] = 'Full') and
      (Segs[4] = 'readme.md'), 'default when chrome declines');
    Assert.IsTrue(Spy.Calls = 1, 'default still asks ChromeContext');
  finally
    Spy.Free;
  end;

  AllocTerminalGrid(Grid, 20, 3);
  ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, '#');
  Segs := TArray<string>.Create('Left', 'C:\');
  DrawAppStatusLineRow(Grid, nil, 1, 20, Segs, $FF000000, $FF00AAAA);
  Assert.IsTrue(Grid[1][0].CharValue = ' ', 'fallback fills col 0');
  Assert.IsTrue(Grid[1][1].CharValue = 'L', 'text starts at col 1');
  Joined := string.Join('  ', Segs);
  Assert.IsTrue(Grid[1][Length(Joined)].CharValue = '\', 'joined path last char');
  Assert.IsTrue((Grid[1][1].FgColor = $FF000000) and (Grid[1][1].BgColor = $FF00AAAA),
    'fallback colors');
end;

procedure TestReplaceHintMapsToF7;
var
  Hit: TFunctionBarHit;
  Key: Word;
  KeyChar: Char;
  Shift: TShiftState;
  Items, Letters: TArray<string>;
begin
  Hit.Kind := fbhHint;
  Hit.FKeyNum := 0;
  Hit.HintKey := 'F7';
  Assert.IsTrue(FunctionBarHitToInput(Hit, [ssCtrl], Key, KeyChar, Shift),
    'F7 hint maps');
  Assert.IsTrue(Key = vkF7, 'F7 hint is vkF7');
  Assert.IsTrue(ssCtrl in Shift, 'F7 hint keeps Ctrl');

  FunctionBarGetItems(fbcTmpPanel, [], Items, Letters);
  Assert.IsTrue(Pos('Remove', Items[6]) > 0, 'tmp F7 is Remove not MkDir');
  Assert.IsTrue((Length(Letters) > 0) and (Pos('CPgUp', Letters[0]) > 0),
    'tmp F-bar shows Ctrl+PgUp');
  FunctionBarGetItems(fbcTmpPanel, [ssAlt, ssShift], Items, Letters);
  Assert.IsTrue(Pos('SavLst', Items[1]) > 0, 'tmp Alt+Shift+F2 SavLst');
  Assert.IsTrue(Pos('GoTo', Items[2]) > 0, 'tmp Alt+Shift+F3 GoTo');
  FunctionBarGetItems(fbcPanels, [], Items, Letters);
  Assert.IsTrue(Pos('MkDir', Items[6]) > 0, 'file panel F7 stays MkDir');
  FunctionBarGetItems(fbcWorkspace, [], Items, Letters);
  Assert.IsTrue(Pos('MkDir', Items[6]) > 0, 'workspace F7 stays MkDir');
  Assert.IsTrue(Pos('Unlink', Items[7]) > 0, 'workspace F8 is Unlink not Del');
  Assert.IsTrue((Length(Letters) > 0) and (Pos('CtAlt+Ent', Letters[0]) > 0),
    'workspace F-bar shows Ctrl+Alt+Enter');
  FunctionBarGetItems(fbcWorkspace, [ssCtrl, ssAlt], Items, Letters);
  Assert.IsTrue((Length(Letters) > 0) and (Pos('Ent:GoTo', Letters[0]) > 0),
    'workspace Ctrl+Alt F-bar shows Enter GoTo');

  FunctionBarGetItems(fbcWorkspaceLibrary, [], Items, Letters);
  Assert.IsTrue(Pos('Ren', Items[1]) > 0, 'workspace library F2 is Ren');
  Assert.IsTrue((Length(Letters) >= 4) and (Pos('Ins:Save', Letters[1]) > 0) and
    (Pos('Del:Del', Letters[2]) > 0), 'workspace library Ins/Del hints');
  FunctionBarGetItems(fbcFolderHotlist, [], Items, Letters);
  Assert.IsTrue(Pos('Ren', Items[1]) > 0, 'hotlist F2 is Ren');
  Assert.IsTrue((Length(Letters) >= 2) and (Pos('Del:Del', Letters[1]) > 0),
    'hotlist Del hint');
  FunctionBarGetItems(fbcColorCoding, [], Items, Letters);
  Assert.IsTrue(Pos('Edit', Items[3]) > 0, 'color coding F4 is Edit');
  Assert.IsTrue((Length(Letters) >= 1) and (Pos('Ins:Add', Letters[0]) > 0),
    'color coding Ins hint');
  FunctionBarGetItems(fbcColorCodingEdit, [], Items, Letters);
  Assert.IsTrue((Length(Letters) >= 1) and (Pos('F9:Pick', Letters[0]) > 0),
    'color edit F9 hint');
  FunctionBarGetItems(fbcStubEdit, [], Items, Letters);
  Assert.IsTrue((Length(Letters) >= 2) and (Pos('Enter:OK', Letters[0]) > 0),
    'input dialog Enter/Esc');

  Hit.HintKey := 'Ins';
  Assert.IsTrue(FunctionBarHitToInput(Hit, [], Key, KeyChar, Shift) and (Key = vkInsert),
    'Ins hint maps to vkInsert');
  Hit.HintKey := 'Del';
  Assert.IsTrue(FunctionBarHitToInput(Hit, [], Key, KeyChar, Shift) and (Key = vkDelete),
    'Del hint maps to vkDelete');
end;

{ TTestDualPanelStatus }

procedure TTestDualPanelStatus.TestPosAndTruncate;
begin
  TestDualPanelStatus.TestPosAndTruncate;
end;

procedure TTestDualPanelStatus.TestChromeAndDefault;
begin
  TestDualPanelStatus.TestChromeAndDefault;
end;

procedure TTestDualPanelStatus.TestChromeContext;
begin
  TestDualPanelStatus.TestChromeContext;
end;

procedure TTestDualPanelStatus.TestPathSideAndItem;
begin
  TestDualPanelStatus.TestPathSideAndItem;
end;

procedure TTestDualPanelStatus.TestAssembleAndPaint;
begin
  TestDualPanelStatus.TestAssembleAndPaint;
end;

procedure TTestDualPanelStatus.TestReplaceHintMapsToF7;
begin
  TestDualPanelStatus.TestReplaceHintMapsToF7;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelStatus);

end.
