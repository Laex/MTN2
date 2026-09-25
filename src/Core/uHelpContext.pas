unit uHelpContext;

{ Context F1: which help topic (a file in <exe>\help\<language>\) fits what
  is on screen. Pure mapping -- TDualPanelWindow.OpenHelp fills THelpScreen
  from its state, so the choice is testable without a window.

  Priority follows input routing: the top menu and a modal dialog own the
  keyboard over everything else, then the panel overlays (user / sort /
  column-mode menus, drive popup, search, job), then the active workspace. }

interface

uses
  uDualPanelTypes, uDualPanelUiTypes;

type
  THelpScreen = record
    ConsoleMode: Boolean;
    TopMenuActive: Boolean;
    /// <summary>hdkNone = no modal dialog.</summary>
    DialogKind: THostDialogKind;
    SearchActive: Boolean;
    JobOverlay: Boolean;
    UserMenu: Boolean;
    SortMenu: Boolean;
    ColumnModeMenu: Boolean;
    DrivePopup: Boolean;
    WorkspaceKind: TWorkspaceKind;
    CmdFocused: Boolean;
    /// <summary>Active panel folder URI (wkPanels only).</summary>
    PanelURI: string;
  end;

const
  cHelpIndexTopic = 'index.md';

/// <summary>Dialogs that read F1 themselves: the key-capture field of the
/// keymap editor records any key, and the built-in key summary is already
/// help.</summary>
function DialogKindTakesF1(AKind: THostDialogKind): Boolean;
/// <summary>Topic for a modal dialog ('' = the contents page).</summary>
function HelpTopicForDialog(AKind: THostDialogKind): string;
/// <summary>Topic for a panel folder: archives, SFTP, Recycle Bin / system
/// folders and search results have their own pages.</summary>
function HelpTopicForPanelUri(const AURI: string): string;
function HelpTopicForScreen(const AScreen: THelpScreen): string;

implementation

uses
  System.SysUtils, System.StrUtils;

function DialogKindTakesF1(AKind: THostDialogKind): Boolean;
begin
  Result := AKind in [hdkKeymapEdit, hdkHelp];
end;

function HelpTopicForDialog(AKind: THostDialogKind): string;
begin
  case AKind of
    hdkMkDir, hdkNewFile, hdkRename, hdkCopyInPlace, hdkJobConfirm,
    hdkOverwriteAsk, hdkOverwriteRename, hdkDeleteError, hdkIOError,
    hdkCreateLink, hdkSetAttributes, hdkChecksumOptions, hdkChecksumResult:
      Result := 'fileops.md';
    hdkJobList, hdkJobProgress:
      Result := 'jobs.md';
    hdkSearch, hdkTmpSaveList:
      Result := 'search.md';
    hdkSelectMask, hdkUnselectMask:
      Result := 'selection.md';
    hdkFolderHistory, hdkCmdHistory, hdkFileHistory, hdkFolderHotlist,
    hdkFolderHotlistAdd, hdkFolderHotlistRename:
      Result := 'history.md';
    hdkDirSync, hdkCompareResult:
      Result := 'sync.md';
    hdkTerminalProfile:
      Result := 'terminals.md';
    hdkConsoleProfile:
      Result := 'cmdline.md';
    hdkColorCoding, hdkColorCodingEdit, hdkColorPicker, hdkTheme, hdkDisplay,
    hdkExternalTools:
      Result := 'settings.md';
    hdkColumnsConfig:
      Result := 'view.md';
    hdkArchivePassword:
      Result := 'archives.md';
    hdkWorkspaceLibrary, hdkWorkspaceSave, hdkWorkspaceRename,
    hdkWorkspaceConfirm, hdkWorkspaceTabRename:
      Result := 'workspaces.md';
    hdkSshConnections, hdkSshConnectionEdit, hdkSshConnectionConfirm:
      Result := 'ssh.md';
    hdkAssociations, hdkAssociationEdit, hdkAssociationConfirm:
      Result := 'associations.md';
    hdkUserMenuEdit, hdkUserMenuConfirm, hdkUserMenuPrompt:
      Result := 'usermenu.md';
    hdkKeymap, hdkKeymapEdit:
      Result := 'keymap.md';
  else
    Result := '';
  end;
end;

function HelpTopicForPanelUri(const AURI: string): string;
var
  Scheme: string;
  P: Integer;
begin
  P := Pos('://', AURI);
  if P > 1 then
    Scheme := LowerCase(Copy(AURI, 1, P - 1))
  else
    Scheme := '';
  // Archive members: file://C:/a.zip!/dir or a plugin scheme (7z://).
  if (Scheme = '7z') or ContainsStr(AURI, '!/') then
    Exit('archives.md');
  if Scheme = 'sftp' then
    Exit('ssh.md');
  if (Scheme = 'recycle') or (Scheme = 'sys') then
    Exit('drives.md');
  if (Scheme = 'find') or (Scheme = 'tmp') then
    Exit('search.md');
  if Scheme = 'ws' then
    Exit('workspaces.md');
  Result := 'panels.md';
end;

function HelpTopicForScreen(const AScreen: THelpScreen): string;
begin
  if AScreen.ConsoleMode then
    Exit('cmdline.md');
  if AScreen.TopMenuActive then
    Exit('topmenu.md');
  if AScreen.DialogKind <> hdkNone then
    Exit(HelpTopicForDialog(AScreen.DialogKind));
  case AScreen.WorkspaceKind of
    wkDocument:
      Exit('viewer.md');
    wkTerminal:
      Exit('terminals.md');
  end;
  if AScreen.SearchActive then
    Exit('search.md');
  if AScreen.JobOverlay then
    Exit('jobs.md');
  if AScreen.UserMenu then
    Exit('usermenu.md');
  if AScreen.SortMenu or AScreen.ColumnModeMenu then
    Exit('view.md');
  if AScreen.DrivePopup then
    Exit('drives.md');
  if AScreen.CmdFocused then
    Exit('cmdline.md');
  Result := HelpTopicForPanelUri(AScreen.PanelURI);
end;

end.
