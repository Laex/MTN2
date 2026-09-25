unit uDualPanelStatus;

{ Status-line segment formatters and status-row paint extracted from
  TDualPanelWindow so chrome strings can be tested without the host. }

interface

uses
  System.SysUtils, System.UITypes,
  uFunctionBar, uDualPanelUiTypes, uDualPanelTypes, uThemeTypes, uTerminalTypes;

type
  TPanelChromeStatus = record
    Path: string;
    JobTitle: string;
    JobMessage: string;
    JobCurrent: string;
    SearchMask: string;
    SearchDir: string;
    SearchFound: Integer;
    SearchResultCount: Integer;
    StubText: string;
    StubDetail: string;
    JobStatus: string;
    DialogKind: THostDialogKind;
  end;

  TChromeOverlayState = record
    DialogVisible: Boolean;
    DialogKind: THostDialogKind;
    DialogChrome: TFunctionBarContext;
    DrivePopupVisible: Boolean;
    UserMenuVisible: Boolean;
    SortMenuVisible: Boolean;
    ColumnModeMenuVisible: Boolean;
    JobPhase: TPanelJobPhase;
    JobPresentation: TJobPresentation;
    JobShowsOverlay: Boolean;
    SearchPhase: TSearchPhase;
    StubVisible: Boolean;
    ConsoleMode: Boolean;
    WorkspaceKind: TWorkspaceKind;
    CurrentURI: string;
  end;

function ResolveChromeContext(const AState: TChromeOverlayState): TFunctionBarContext;
function FormatPanelPosText(ACount, ACursorIndex: Integer): string;
function TruncateStatusPath(const APath: string; AMaxLen: Integer = 40): string;
function TruncateStatusItem(const AText: string; AMaxLen: Integer = 28): string;
function FormatStatusSelText(ABytes: Int64; AFiles, AFolders: Integer): string;
function FormatTerminalStatus(AAssigned, ARunning: Boolean;
  const AProfileTitle: string): TArray<string>;
function TryFormatChromeStatus(ACtx: TFunctionBarContext;
  const AInfo: TPanelChromeStatus; out ASegs: TArray<string>): Boolean;
function FormatDefaultPanelStatus(const ASideLabel, APath, APosText,
  AColumnMode, AItemText, AFreeText: string; AIsPanels, ACmdFocused: Boolean): TArray<string>;

type
  TStatusChromeFn = function: TFunctionBarContext of object;

  TStatusOverlaySnapshot = record
    DialogKind: THostDialogKind;
    JobTitle, JobMessage, JobCurrent, JobStatus: string;
    SearchMask, SearchDir: string;
    SearchFound, SearchResultCount: Integer;
    StubText, StubDetail: string;
  end;

  TPanelStatusSnapshot = record
    Kind: TWorkspaceKind;
    TermAssigned, TermRunning: Boolean;
    TermTitle: string;
    SideLabel, Path, PosText, ColMode, ItemText, FreeText, JobStatus: string;
    CmdFocused: Boolean;
    Chrome: TPanelChromeStatus;
  end;

  TDualPanelStatusHost = record
    ChromeContext: TStatusChromeFn;
  end;

function StatusPathLabel(const AURI: string): string;
function PanelSideStatusLabel(ASide: TPanelSide): string;
function StatusItemText(AHasSelection: Boolean; const ASelText: string;
  AHasCursorItem: Boolean; const ACursorText: string): string;
function MakeChromeStatus(const APath: string;
  const ASnap: TStatusOverlaySnapshot): TPanelChromeStatus;
function AssembleStatusSegments(const AHost: TDualPanelStatusHost;
  const ASnap: TPanelStatusSnapshot): TArray<string>;
procedure DrawAppStatusLineRow(const ABuffer: TTerminalGrid;
  const ATheme: IThemeRenderer; AY, AWidth: Integer;
  const ASegs: TArray<string>; AFallbackFg, AFallbackBg: TAlphaColor);

implementation

uses
  uVfsTypes, uStrings;

// Status line captions are translated where they are built, never as whole
// segments: a segment can also be a path or a file name, and a file called
// "Copy" must not come out translated. Keys: status.<English text>.
function S(const AText: string): string;
begin
  Result := T('status.' + AText, AText);
end;

// "Enter=OK": the key name stays as is, only the action is translated.
function H(const AKey, AAction, ASep: string): string;
begin
  Result := AKey + ASep + S(AAction);
end;

function ResolveChromeContext(const AState: TChromeOverlayState): TFunctionBarContext;
begin
  if AState.StubVisible then
    Exit(fbcStub);
  if AState.DialogVisible then
  begin
    case AState.DialogKind of
      hdkSearch:
        Exit(fbcSearchDialog);
      hdkJobProgress:
        Exit(fbcJobRunning);
      hdkJobConfirm, hdkOverwriteAsk, hdkOverwriteRename, hdkDeleteError,
      hdkTerminalProfile, hdkConsoleProfile:
        Exit(fbcJob);
      hdkWorkspaceLibrary:
        Exit(fbcWorkspaceLibrary);
      hdkFolderHotlist:
        Exit(fbcFolderHotlist);
      hdkFileHistory:
        Exit(fbcFileHistory);
      hdkColorCoding:
        Exit(fbcColorCoding);
      hdkColorCodingEdit:
        Exit(fbcColorCodingEdit);
      hdkFolderHistory, hdkCmdHistory, hdkTheme, hdkColumnsConfig, hdkDisplay,
      hdkColorPicker, hdkTmpSaveList, hdkKeymap, hdkJobList,
      hdkChecksumOptions, hdkChecksumResult:
        Exit(fbcDialogList);
      hdkMkDir, hdkNewFile, hdkRename, hdkCopyInPlace, hdkHelp,
      hdkSelectMask, hdkUnselectMask, hdkDirSync, hdkCreateLink,
      hdkSetAttributes,
      hdkCompareResult, hdkArchivePassword, hdkFolderHotlistAdd,
      hdkFolderHotlistRename, hdkWorkspaceSave, hdkWorkspaceRename,
      hdkWorkspaceTabRename, hdkWorkspaceConfirm, hdkKeymapEdit,
      hdkExternalTools:
        Exit(fbcStubEdit);
    else
      Exit(AState.DialogChrome);
    end;
  end;
  if AState.DrivePopupVisible then
    Exit(fbcDrive);
  if AState.UserMenuVisible then
    Exit(fbcUserMenuEdit);
  if AState.SortMenuVisible or AState.ColumnModeMenuVisible then
    Exit(fbcUserMenu);
  if AState.JobShowsOverlay or
     ((AState.JobPhase in [pjpRunning, pjpError]) and
      (AState.JobPresentation = jpForeground)) then
    Exit(fbcJobRunning);
  if AState.SearchPhase = spRunning then
    Exit(fbcSearchRunning);
  if AState.SearchPhase = spResults then
    Exit(fbcSearchResults);
  if AState.ConsoleMode then
    Exit(fbcConsole);
  if AState.WorkspaceKind = wkTerminal then
    Exit(fbcTerminal);
  if IsSystemFoldersUri(AState.CurrentURI) then
    Exit(fbcSysFolders);
  if IsRecycleBinUri(AState.CurrentURI) then
    Exit(fbcRecycleBin);
  if IsTmpPanelUri(AState.CurrentURI) then
    Exit(fbcTmpPanel);
  if IsWorkspaceUri(AState.CurrentURI) then
    Exit(fbcWorkspace);
  Result := fbcPanels;
end;

function FormatPanelPosText(ACount, ACursorIndex: Integer): string;
var
  Idx: Integer;
begin
  if ACount = 0 then
    Exit('0/0');
  Idx := ACursorIndex;
  if Idx < 0 then
    Idx := 0;
  if Idx > ACount - 1 then
    Idx := ACount - 1;
  Result := Format('%d/%d', [Idx + 1, ACount]);
end;

function TruncateStatusPath(const APath: string; AMaxLen: Integer): string;
begin
  Result := APath;
  if AMaxLen < 2 then
    Exit;
  if Length(Result) > AMaxLen then
    Result := '?' + Copy(Result, Length(Result) - (AMaxLen - 2), MaxInt);
end;

function TruncateStatusItem(const AText: string; AMaxLen: Integer): string;
begin
  Result := EllipsizeKeepingExt(AText, AMaxLen);
end;

function FormatStatusSelText(ABytes: Int64; AFiles, AFolders: Integer): string;
begin
  Result := T('status.selection', 'Sel %s (%d)', [FormatSizeShort(ABytes), AFiles + AFolders]);
end;

function FormatTerminalStatus(AAssigned, ARunning: Boolean;
  const AProfileTitle: string): TArray<string>;
begin
  if not AAssigned then
    Exit(TArray<string>.Create(S('Terminal')));
  if ARunning then
    Result := TArray<string>.Create(AProfileTitle, S('Running'), H('Esc', 'Close', ':'))
  else
    Result := TArray<string>.Create(AProfileTitle, S('Not running'), H('Esc', 'Close', ':'));
end;

function StubEditStatus(AKind: THostDialogKind): TArray<string>;
begin
  case AKind of
    hdkMkDir:
      Result := TArray<string>.Create(S('MkDir'), H('Enter', 'Create', '='), H('Esc', 'Cancel', '='));
    hdkNewFile:
      Result := TArray<string>.Create(S('New file'), H('Enter', 'Create', '='), H('Esc', 'Cancel', '='));
    hdkArchivePassword:
      Result := TArray<string>.Create(S('Password'), H('Enter', 'OK', '='), H('Esc', 'Cancel', '='));
    hdkRename, hdkFolderHotlistRename, hdkWorkspaceRename, hdkWorkspaceTabRename:
      Result := TArray<string>.Create(S('Rename'), H('Enter', 'Rename', '='), H('Esc', 'Cancel', '='));
    hdkCopyInPlace:
      Result := TArray<string>.Create(S('Copy'), H('Enter', 'Copy', '='), H('Esc', 'Cancel', '='));
    hdkHelp:
      Result := TArray<string>.Create(S('Help'), H('Enter/Esc', 'Close', '='));
    hdkSelectMask:
      Result := TArray<string>.Create(S('Select'), H('Enter', 'OK', '='), H('Esc', 'Cancel', '='));
    hdkUnselectMask:
      Result := TArray<string>.Create(S('Unselect'), H('Enter', 'OK', '='), H('Esc', 'Cancel', '='));
    hdkDirSync:
      Result := TArray<string>.Create(S('Dir sync'), H('Enter', 'Sync', '='), H('Esc', 'Cancel', '='));
    hdkCreateLink:
      Result := TArray<string>.Create(S('Link'), H('Enter', 'Create', '='), H('Esc', 'Cancel', '='));
    hdkSetAttributes:
      Result := TArray<string>.Create(S('Attr'), H('Enter', 'Set', '='), H('Esc', 'Cancel', '='));
    hdkCompareResult:
      Result := TArray<string>.Create(S('Compare'), H('Enter/Esc', 'Close', '='));
    hdkFolderHotlistAdd:
      Result := TArray<string>.Create(S('Hotlist'), H('Enter', 'Add', '='), H('Esc', 'Cancel', '='));
    hdkWorkspaceSave:
      Result := TArray<string>.Create(S('Save workspace'), H('Enter', 'Save', '='), H('Esc', 'Cancel', '='));
    hdkWorkspaceConfirm:
      Result := TArray<string>.Create(S('Workspaces'), H('Enter', 'OK', '='), H('Esc', 'Cancel', '='));
  else
    Result := TArray<string>.Create(S('Dialog'), H('Enter', 'OK', '='), H('Esc', 'Cancel', '='));
  end;
end;

function DialogListStatus(AKind: THostDialogKind): TArray<string>;
begin
  case AKind of
    hdkFolderHistory:
      Result := TArray<string>.Create(S('Folders'), S('^v select'), H('Enter', 'Go', '='), H('Esc', 'Cancel', '='));
    hdkCmdHistory:
      Result := TArray<string>.Create(S('Commands'), S('^v select'), H('Enter', 'OK', '='), H('Esc', 'Cancel', '='));
    hdkTheme:
      Result := TArray<string>.Create(S('Theme'), S('^v select'), H('Enter', 'OK', '='), H('Esc', 'Cancel', '='));
    hdkDisplay:
      Result := TArray<string>.Create(S('Display'), H('Enter', 'OK', '='), H('Esc', 'Cancel', '='));
    hdkColumnsConfig:
      Result := TArray<string>.Create(S('Columns'), H('Enter', 'OK', '='), H('Esc', 'Cancel', '='));
    hdkColorPicker:
      Result := TArray<string>.Create(S('Color'), H('Enter', 'OK', '='), H('Esc', 'Cancel', '='));
    hdkTmpSaveList:
      Result := TArray<string>.Create(S('Save list'), H('Enter', 'Save', '='), H('Esc', 'Cancel', '='));
    hdkChecksumOptions:
      Result := TArray<string>.Create(S('Checksums'), H('Enter', 'OK', '='), H('Esc', 'Cancel', '='));
    hdkChecksumResult:
      Result := TArray<string>.Create(S('Checksums'), S('^v select'), H('Tab', 'Copy/Save', '='),
        H('Esc', 'Close', '='));
  else
    Result := TArray<string>.Create(S('Code page'), S('^v select'), H('Enter', 'Apply', '='), H('Esc', 'Cancel', '='));
  end;
end;

function TryFormatChromeStatus(ACtx: TFunctionBarContext;
  const AInfo: TPanelChromeStatus; out ASegs: TArray<string>): Boolean;
begin
  Result := True;
  case ACtx of
    fbcConsole:
      ASegs := TArray<string>.Create(S('Console'), AInfo.Path, H('Esc', 'Stop', '='), H('Esc', 'Panels', '='));
    fbcDrive:
      ASegs := TArray<string>.Create(S('Drive'), S('^v select'), H('Enter', 'Go', '='), H('Esc', 'Cancel', '='));
    fbcUserMenu:
      ASegs := TArray<string>.Create(S('User menu'), H('Enter', 'Run', '='), H('Esc', 'Close', '='));
    fbcUserMenuEdit:
      ASegs := TArray<string>.Create(S('User menu'), H('Enter', 'Run', '='), H('Ins', 'Add', '='),
        H('F4', 'Edit', '='), H('Del', 'Delete', '='), H('Shift+F2', 'Main/Folder', '='), H('Esc', 'Close', '='));
    fbcJob:
      ASegs := TArray<string>.Create(AInfo.JobTitle, AInfo.JobMessage, AInfo.JobCurrent);
    fbcJobRunning:
      ASegs := TArray<string>.Create(AInfo.JobTitle, AInfo.JobMessage, AInfo.JobCurrent,
        H('B', 'Background', '='));
    fbcSearchDialog:
      ASegs := TArray<string>.Create(S('Find file'), AInfo.SearchMask, H('Enter', 'Find', '='), H('Esc', 'Cancel', '='));
    fbcSearchRunning:
      ASegs := TArray<string>.Create(
        T('status.findCount', 'Find %d', [AInfo.SearchFound]), AInfo.SearchDir,
        H('Esc', 'Cancel', '='));
    fbcSearchResults:
      ASegs := TArray<string>.Create(
        T('status.resultCount', 'Results %d', [AInfo.SearchResultCount]), AInfo.SearchMask,
        H('Enter', 'Goto', '='), H('Esc', 'Close', '='));
    fbcStubEdit:
      ASegs := StubEditStatus(AInfo.DialogKind);
    fbcDialogList:
      ASegs := DialogListStatus(AInfo.DialogKind);
    fbcWorkspaceLibrary:
      ASegs := TArray<string>.Create(S('Workspaces'), H('Enter', 'Go', '='), H('Ins', 'Save', '='), H('F2', 'Ren', '='),
        H('Del', 'Del', '='));
    fbcFolderHotlist:
      ASegs := TArray<string>.Create(S('Hotlist'), H('Enter', 'Go', '='), H('F2', 'Ren', '='), H('Del', 'Del', '='));
    fbcFileHistory:
      ASegs := TArray<string>.Create(S('File history'), H('Enter', 'Open', '='),
        H('F3', 'View', '='), H('F4', 'Edit', '='), H('Ctrl+Enter', 'Go', '='),
        H('Del', 'Del', '='));
    fbcColorCoding:
      ASegs := TArray<string>.Create(S('Color groups'), H('Ins', 'Add', '='), H('F4', 'Edit', '='), H('Del', 'Del', '='));
    fbcColorCodingEdit:
      ASegs := TArray<string>.Create(S('Color group'), H('F9', 'Pick', '='), H('Enter', 'OK', '='), H('Esc', 'Cancel', '='));
    fbcStub:
      ASegs := TArray<string>.Create(AInfo.StubText, AInfo.StubDetail, H('Esc', 'Close', '='));
  else
    Result := False;
  end;
end;

function FormatDefaultPanelStatus(const ASideLabel, APath, APosText,
  AColumnMode, AItemText, AFreeText: string; AIsPanels, ACmdFocused: Boolean): TArray<string>;
var
  N: Integer;
begin
  SetLength(Result, 6);
  Result[0] := ASideLabel;
  Result[1] := APath;
  Result[2] := APosText;
  N := 3;
  if AIsPanels and (AColumnMode <> '') then
  begin
    Result[N] := AColumnMode;
    Inc(N);
  end;
  if ACmdFocused then
  begin
    Result[N] := S('Cmdline');
    Inc(N);
  end
  else if AItemText <> '' then
  begin
    Result[N] := AItemText;
    Inc(N);
  end;
  if AFreeText <> '' then
  begin
    Result[N] := AFreeText;
    Inc(N);
  end;
  SetLength(Result, N);
end;

function StatusPathLabel(const AURI: string): string;
begin
  if IsRecycleBinUri(AURI) then
    Result := VfsUriTitle(AURI)
  else if IsTmpPanelUri(AURI) then
    Result := VfsUriTitle(AURI)
  else if IsWorkspaceUri(AURI) then
  begin
    Result := VfsUriTitle('ws:///');
    if WorkspaceInnerPath(AURI) <> '' then
      Result := Result + '\' + StringReplace(WorkspaceInnerPath(AURI), '/', '\',
        [rfReplaceAll]);
  end
  else
  begin
    Result := FileUriToPath(AURI);
    if Result = '' then
      Result := AURI;
  end;
end;

function PanelSideStatusLabel(ASide: TPanelSide): string;
begin
  if ASide = psLeft then
    Result := S('Left')
  else
    Result := S('Right');
end;

function StatusItemText(AHasSelection: Boolean; const ASelText: string;
  AHasCursorItem: Boolean; const ACursorText: string): string;
begin
  if AHasSelection then
    Result := ASelText
  else if AHasCursorItem then
    Result := TruncateStatusItem(ACursorText)
  else
    Result := '';
end;

function MakeChromeStatus(const APath: string;
  const ASnap: TStatusOverlaySnapshot): TPanelChromeStatus;
begin
  Result := Default(TPanelChromeStatus);
  Result.Path := APath;
  Result.DialogKind := ASnap.DialogKind;
  Result.JobTitle := ASnap.JobTitle;
  Result.JobMessage := ASnap.JobMessage;
  Result.JobCurrent := ASnap.JobCurrent;
  Result.SearchMask := ASnap.SearchMask;
  Result.SearchDir := ASnap.SearchDir;
  Result.SearchFound := ASnap.SearchFound;
  Result.SearchResultCount := ASnap.SearchResultCount;
  Result.StubText := ASnap.StubText;
  Result.StubDetail := ASnap.StubDetail;
  Result.JobStatus := ASnap.JobStatus;
end;

function AssembleStatusSegments(const AHost: TDualPanelStatusHost;
  const ASnap: TPanelStatusSnapshot): TArray<string>;
begin
  if ASnap.Kind = wkTerminal then
    Exit(FormatTerminalStatus(ASnap.TermAssigned, ASnap.TermRunning, ASnap.TermTitle));
  if TryFormatChromeStatus(AHost.ChromeContext(), ASnap.Chrome, Result) then
    Exit;
  Result := FormatDefaultPanelStatus(ASnap.SideLabel, ASnap.Path, ASnap.PosText,
    ASnap.ColMode, ASnap.ItemText, ASnap.FreeText, ASnap.Kind = wkPanels,
    ASnap.CmdFocused);
  if ASnap.JobStatus <> '' then
    Result := Result + [ASnap.JobStatus]
  else if ASnap.Chrome.JobStatus <> '' then
    Result := Result + [ASnap.Chrome.JobStatus];
end;

procedure DrawAppStatusLineRow(const ABuffer: TTerminalGrid;
  const ATheme: IThemeRenderer; AY, AWidth: Integer;
  const ASegs: TArray<string>; AFallbackFg, AFallbackBg: TAlphaColor);
begin
  if Assigned(ATheme) then
    ATheme.DrawStatusLine(ABuffer, TRectI.Make(0, AY, AWidth - 1, AY), ASegs, [])
  else
  begin
    FillGridRect(ABuffer, 0, AY, AWidth - 1, AY, ' ', AFallbackFg, AFallbackBg);
    if Length(ASegs) > 0 then
      PutGridText(ABuffer, 1, AY, string.Join('  ', ASegs), AFallbackFg, AFallbackBg);
  end;
end;

end.
