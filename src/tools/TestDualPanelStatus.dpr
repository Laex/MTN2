program TestDualPanelStatus;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.UITypes,
  uTerminalTypes in '..\Core\uTerminalTypes.pas',
  uThemeTypes in '..\Core\uThemeTypes.pas',
  uKeymap in '..\Core\uKeymap.pas',
  uFunctionBar in '..\Core\uFunctionBar.pas',
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uDualPanelTypes in '..\Core\uDualPanelTypes.pas',
  uDualPanelUiTypes in '..\Core\uDualPanelUiTypes.pas',
  uDualPanelStatus in '..\Core\uDualPanelStatus.pas';

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

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

procedure TestPosAndTruncate;
begin
  Writeln('Pos / truncate / selection');
  Expect(FormatPanelPosText(0, 5) = '0/0', 'empty list');
  Expect(FormatPanelPosText(10, 0) = '1/10', 'first is 1-based');
  Expect(FormatPanelPosText(10, 9) = '10/10', 'last');
  Expect(FormatPanelPosText(10, 99) = '10/10', 'clamp high');
  Expect(TruncateStatusPath('abcdefghij', 8) = '?defghij', 'path ellipsis');
  Expect(TruncateStatusPath('short', 40) = 'short', 'short path kept');
  Expect(TruncateStatusItem('abcdefghijklmnopqrstuvwxyz12', 28) =
    'abcdefghijklmnopqrstuvwxyz12', 'item at limit kept');
  Expect(TruncateStatusItem('abcdefghijklmnopqrstuvwxyz123', 28) =
    'abcdefghijklmnopqrstuv...123', 'item mid-ellipsis');
  Expect(Copy(TruncateStatusItem('LongDocumentNameHere.docx', 20), 16, 5) =
    '.docx', 'item keeps extension');
  Expect(Pos('...', TruncateStatusItem('LongDocumentNameHere.docx', 20)) > 0,
    'item uses ellipsis');
  Expect(Length(TruncateStatusItem('LongDocumentNameHere.docx', 20)) = 20,
    'item fits width');
  Expect(FormatStatusSelText(1024, 2, 1) = 'Sel 1 K (3)', 'sel totals');
end;

procedure TestChromeAndDefault;
var
  Info: TPanelChromeStatus;
  Segs: TArray<string>;
begin
  Writeln('Chrome / default status');
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

  Expect(TryFormatChromeStatus(fbcDrive, Info, Segs) and (Segs[0] = 'Drive'),
    'drive chrome');
  Expect(TryFormatChromeStatus(fbcJob, Info, Segs) and (Segs[0] = 'Copy') and
    (Segs[2] = 'a.txt'), 'job chrome');
  Expect(TryFormatChromeStatus(fbcSearchRunning, Info, Segs) and
    (Segs[0] = 'Find 4'), 'search running');
  Expect(TryFormatChromeStatus(fbcStubEdit, Info, Segs) and (Segs[0] = 'MkDir'),
    'mkdir stub edit');
  Info.DialogKind := hdkWorkspaceLibrary;
  Expect(TryFormatChromeStatus(fbcWorkspaceLibrary, Info, Segs) and
    (Segs[0] = 'Workspaces') and (Pos('Ins=Save', string.Join(' ', Segs)) > 0),
    'workspace library status');
  Info.DialogKind := hdkTheme;
  Expect(TryFormatChromeStatus(fbcDialogList, Info, Segs) and (Segs[0] = 'Theme'),
    'theme list status');
  Info.DialogKind := hdkDisplay;
  Expect(TryFormatChromeStatus(fbcDialogList, Info, Segs) and (Segs[0] = 'Display'),
    'display list status');
  Info.DialogKind := hdkNone;
  Expect(TryFormatChromeStatus(fbcDialogList, Info, Segs) and (Segs[0] = 'Code page'),
    'encoding list status');
  Expect(not TryFormatChromeStatus(fbcPanels, Info, Segs), 'panels uses default');

  Segs := FormatDefaultPanelStatus('Left', 'C:\', '1/2', 'Full', 'readme.md',
    '1.2G', True, False);
  Expect((Length(Segs) = 6) and (Segs[0] = 'Left') and (Segs[3] = 'Full') and
    (Segs[4] = 'readme.md'), 'default panel segs');
  Segs := FormatDefaultPanelStatus('Right', 'C:\', '1/2', 'Full', 'x', '', True, True);
  Expect(Segs[4] = 'Cmdline', 'cmdline wins over item');
  Segs := FormatTerminalStatus(False, False, '');
  Expect((Length(Segs) = 1) and (Segs[0] = 'Terminal'), 'no terminal');
  Segs := FormatTerminalStatus(True, True, 'PowerShell');
  Expect((Segs[0] = 'PowerShell') and (Segs[1] = 'Running'), 'running terminal');
end;

procedure TestChromeContext;
var
  S: TChromeOverlayState;
begin
  Writeln('Chrome context');
  S := Default(TChromeOverlayState);
  S.WorkspaceKind := wkPanels;
  Expect(ResolveChromeContext(S) = fbcPanels, 'plain panels');

  S.DialogVisible := True;
  S.DialogKind := hdkSearch;
  Expect(ResolveChromeContext(S) = fbcSearchDialog, 'search dialog');
  S.DialogKind := hdkJobConfirm;
  Expect(ResolveChromeContext(S) = fbcJob, 'job confirm dialog');
  S.DialogKind := hdkJobProgress;
  Expect(ResolveChromeContext(S) = fbcJobRunning, 'job progress dialog');
  S.DialogKind := hdkMkDir;
  S.DialogChrome := fbcStubEdit;
  Expect(ResolveChromeContext(S) = fbcStubEdit, 'mkdir uses stub-edit chrome');
  S.DialogKind := hdkWorkspaceLibrary;
  S.DialogChrome := fbcStubEdit;
  Expect(ResolveChromeContext(S) = fbcWorkspaceLibrary, 'workspaces list chrome');
  S.DialogKind := hdkFolderHotlist;
  Expect(ResolveChromeContext(S) = fbcFolderHotlist, 'hotlist chrome');
  S.DialogKind := hdkColorCoding;
  Expect(ResolveChromeContext(S) = fbcColorCoding, 'color coding chrome');
  S.DialogKind := hdkColorCodingEdit;
  Expect(ResolveChromeContext(S) = fbcColorCodingEdit, 'color edit chrome');
  S.DialogKind := hdkTheme;
  Expect(ResolveChromeContext(S) = fbcDialogList, 'theme list chrome');
  S.DialogKind := hdkDisplay;
  Expect(ResolveChromeContext(S) = fbcDialogList, 'display list chrome');
  S.DialogKind := hdkWorkspaceSave;
  Expect(ResolveChromeContext(S) = fbcStubEdit, 'workspace save chrome');
  S.StubVisible := True;
  Expect(ResolveChromeContext(S) = fbcStub, 'stub sits above dialog chrome');
  S.StubVisible := False;

  S := Default(TChromeOverlayState);
  S.DrivePopupVisible := True;
  Expect(ResolveChromeContext(S) = fbcDrive, 'drive popup');
  S.DrivePopupVisible := False;
  S.SortMenuVisible := True;
  Expect(ResolveChromeContext(S) = fbcUserMenu, 'sort menu');
  S.SortMenuVisible := False;
  S.JobPhase := pjpRunning;
  S.JobPresentation := jpForeground;
  S.JobShowsOverlay := True;
  Expect(ResolveChromeContext(S) = fbcJobRunning, 'foreground running job');
  S.JobPresentation := jpBackground;
  S.JobShowsOverlay := False;
  Expect(ResolveChromeContext(S) = fbcPanels, 'background running uses panel keys');
  S.JobPhase := pjpNone;
  S.SearchPhase := spResults;
  Expect(ResolveChromeContext(S) = fbcSearchResults, 'search results');
  S.SearchPhase := spNone;
  S.ConsoleMode := True;
  Expect(ResolveChromeContext(S) = fbcConsole, 'console');
  S.ConsoleMode := False;
  S.WorkspaceKind := wkTerminal;
  Expect(ResolveChromeContext(S) = fbcTerminal, 'terminal workspace');
  S.WorkspaceKind := wkPanels;
  S.CurrentURI := 'sys://folders';
  Expect(ResolveChromeContext(S) = fbcSysFolders, 'sys folders');
  S.CurrentURI := 'recycle:///';
  Expect(ResolveChromeContext(S) = fbcRecycleBin, 'recycle bin');
  S.CurrentURI := 'tmp:///';
  Expect(ResolveChromeContext(S) = fbcTmpPanel, 'tmp panel');
  S.CurrentURI := 'ws:///';
  Expect(ResolveChromeContext(S) = fbcWorkspace, 'workspace root');
  S.CurrentURI := 'ws:///group';
  Expect(ResolveChromeContext(S) = fbcWorkspace, 'workspace nested');
end;

procedure TestPathSideAndItem;
begin
  Writeln('Path / side / item');
  Expect(StatusPathLabel('recycle://C:/') = 'Recycle Bin', 'recycle title');
  Expect(StatusPathLabel('tmp:///') = 'Temporary', 'tmp title');
  Expect(StatusPathLabel('ws:///') = 'Workspace', 'ws title');
  Expect(StatusPathLabel('ws:///group') = 'Workspace\group', 'ws nested title');
  Expect(StatusPathLabel('file:///C:/Work') = FileUriToPath('file:///C:/Work'),
    'file URI becomes path');
  Expect(StatusPathLabel('file://localhost') = 'file://localhost',
    'empty path falls back to URI');
  Expect(PanelSideStatusLabel(psLeft) = 'Left', 'left side');
  Expect(PanelSideStatusLabel(psRight) = 'Right', 'right side');
  Expect(StatusItemText(True, 'Sel 1 K (3)', True, 'readme.md') = 'Sel 1 K (3)',
    'selection wins over cursor');
  Expect(StatusItemText(False, '', True, 'abcdefghijklmnopqrstuvwxyz123') =
    TruncateStatusItem('abcdefghijklmnopqrstuvwxyz123'), 'cursor truncated');
  Expect(StatusItemText(False, '', False, 'x') = '', 'empty when neither');
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
  Writeln('Assemble / paint');
  Overlay := Default(TStatusOverlaySnapshot);
  Overlay.JobTitle := 'Copy';
  Overlay.JobMessage := '50%';
  Overlay.JobCurrent := 'a.txt';
  Expect(MakeChromeStatus('C:\Work', Overlay).Path = 'C:\Work', 'chrome path');
  Expect(MakeChromeStatus('C:\Work', Overlay).JobTitle = 'Copy', 'chrome job');

  Spy := TChromeSpy.Create;
  try
    Host := Default(TDualPanelStatusHost);
    Host.ChromeContext := Spy.Get;
    Snap := Default(TPanelStatusSnapshot);
    Snap.Kind := wkTerminal;
    Snap.TermAssigned := False;
    Segs := AssembleStatusSegments(Host, Snap);
    Expect((Length(Segs) = 1) and (Segs[0] = 'Terminal'), 'terminal without chrome');
    Expect(Spy.Calls = 0, 'terminal skips ChromeContext');

    Snap := Default(TPanelStatusSnapshot);
    Snap.Kind := wkPanels;
    Snap.Chrome := MakeChromeStatus('C:\', Overlay);
    Spy.Ctx := fbcJob;
    Segs := AssembleStatusSegments(Host, Snap);
    Expect((Segs[0] = 'Copy') and (Segs[2] = 'a.txt'), 'job chrome via host');
    Expect(Spy.Calls = 1, 'chrome asks ChromeContext once');

    Spy.Calls := 0;
    Spy.Ctx := fbcPanels;
    Snap.SideLabel := 'Left';
    Snap.Path := 'C:\';
    Snap.PosText := '1/2';
    Snap.ColMode := 'Full';
    Snap.ItemText := 'readme.md';
    Snap.FreeText := '1.2G';
    Segs := AssembleStatusSegments(Host, Snap);
    Expect((Length(Segs) = 6) and (Segs[0] = 'Left') and (Segs[3] = 'Full') and
      (Segs[4] = 'readme.md'), 'default when chrome declines');
    Expect(Spy.Calls = 1, 'default still asks ChromeContext');
  finally
    Spy.Free;
  end;

  AllocTerminalGrid(Grid, 20, 3);
  ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, '#');
  Segs := TArray<string>.Create('Left', 'C:\');
  DrawAppStatusLineRow(Grid, nil, 1, 20, Segs, $FF000000, $FF00AAAA);
  Expect(Grid[1][0].CharValue = ' ', 'fallback fills col 0');
  Expect(Grid[1][1].CharValue = 'L', 'text starts at col 1');
  Joined := string.Join('  ', Segs);
  Expect(Grid[1][Length(Joined)].CharValue = '\', 'joined path last char');
  Expect((Grid[1][1].FgColor = $FF000000) and (Grid[1][1].BgColor = $FF00AAAA),
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
  Writeln('F-bar replace hint');
  Hit.Kind := fbhHint;
  Hit.FKeyNum := 0;
  Hit.HintKey := 'F7';
  Expect(FunctionBarHitToInput(Hit, [ssCtrl], Key, KeyChar, Shift),
    'F7 hint maps');
  Expect(Key = vkF7, 'F7 hint is vkF7');
  Expect(ssCtrl in Shift, 'F7 hint keeps Ctrl');

  FunctionBarGetItems(fbcTmpPanel, [], Items, Letters);
  Expect(Pos('Remove', Items[6]) > 0, 'tmp F7 is Remove not MkDir');
  Expect((Length(Letters) > 0) and (Pos('CPgUp', Letters[0]) > 0),
    'tmp F-bar shows Ctrl+PgUp');
  FunctionBarGetItems(fbcTmpPanel, [ssAlt, ssShift], Items, Letters);
  Expect(Pos('SavLst', Items[1]) > 0, 'tmp Alt+Shift+F2 SavLst');
  Expect(Pos('GoTo', Items[2]) > 0, 'tmp Alt+Shift+F3 GoTo');
  FunctionBarGetItems(fbcPanels, [], Items, Letters);
  Expect(Pos('MkDir', Items[6]) > 0, 'file panel F7 stays MkDir');
  FunctionBarGetItems(fbcWorkspace, [], Items, Letters);
  Expect(Pos('MkDir', Items[6]) > 0, 'workspace F7 stays MkDir');
  Expect(Pos('Unlink', Items[7]) > 0, 'workspace F8 is Unlink not Del');
  Expect((Length(Letters) > 0) and (Pos('CtAlt+Ent', Letters[0]) > 0),
    'workspace F-bar shows Ctrl+Alt+Enter');
  FunctionBarGetItems(fbcWorkspace, [ssCtrl, ssAlt], Items, Letters);
  Expect((Length(Letters) > 0) and (Pos('Ent:GoTo', Letters[0]) > 0),
    'workspace Ctrl+Alt F-bar shows Enter GoTo');

  FunctionBarGetItems(fbcWorkspaceLibrary, [], Items, Letters);
  Expect(Pos('Ren', Items[1]) > 0, 'workspace library F2 is Ren');
  Expect((Length(Letters) >= 4) and (Pos('Ins:Save', Letters[1]) > 0) and
    (Pos('Del:Del', Letters[2]) > 0), 'workspace library Ins/Del hints');
  FunctionBarGetItems(fbcFolderHotlist, [], Items, Letters);
  Expect(Pos('Ren', Items[1]) > 0, 'hotlist F2 is Ren');
  Expect((Length(Letters) >= 2) and (Pos('Del:Del', Letters[1]) > 0),
    'hotlist Del hint');
  FunctionBarGetItems(fbcColorCoding, [], Items, Letters);
  Expect(Pos('Edit', Items[3]) > 0, 'color coding F4 is Edit');
  Expect((Length(Letters) >= 1) and (Pos('Ins:Add', Letters[0]) > 0),
    'color coding Ins hint');
  FunctionBarGetItems(fbcColorCodingEdit, [], Items, Letters);
  Expect((Length(Letters) >= 1) and (Pos('F9:Pick', Letters[0]) > 0),
    'color edit F9 hint');
  FunctionBarGetItems(fbcStubEdit, [], Items, Letters);
  Expect((Length(Letters) >= 2) and (Pos('Enter:OK', Letters[0]) > 0),
    'input dialog Enter/Esc');

  Hit.HintKey := 'Ins';
  Expect(FunctionBarHitToInput(Hit, [], Key, KeyChar, Shift) and (Key = vkInsert),
    'Ins hint maps to vkInsert');
  Hit.HintKey := 'Del';
  Expect(FunctionBarHitToInput(Hit, [], Key, KeyChar, Shift) and (Key = vkDelete),
    'Del hint maps to vkDelete');
end;

begin
  try
    TestPosAndTruncate;
    TestChromeAndDefault;
    TestChromeContext;
    TestPathSideAndItem;
    TestAssembleAndPaint;
    TestReplaceHintMapsToF7;
    Writeln('All DualPanelStatus tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.Message);
      Halt(1);
    end;
  end;
end.
