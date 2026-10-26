unit uHelpContext;

{ Context F1: which help topic (a file in <exe>\resource\<language>\help\) fits what
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
    /// <summary>Topic the open dialog asks for itself ('' = the one its kind
    /// maps to), e.g. the command picked in the command palette.</summary>
    DialogTopic: string;
  end;

const
  cHelpIndexTopic = 'index.md';

/// <summary>Dialogs that read F1 themselves: the key-capture field of the
/// keymap editor records any key, and the built-in key summary is already
/// help.</summary>
function DialogKindTakesF1(AKind: THostDialogKind): Boolean;
/// <summary>Topic for a modal dialog ('' = the contents page). A topic is a
/// file name, optionally followed by #id: the line that starts with the
/// marker &lt;!--id--&gt; in that file (the same in every language).</summary>
function HelpTopicForDialog(AKind: THostDialogKind): string;
/// <summary>Topic for a panel folder: archives, SFTP, Recycle Bin / system
/// folders and search results have their own pages.</summary>
function HelpTopicForPanelUri(const AURI: string): string;
/// <summary>Topic that explains a top menu command, by the action's name
/// (the enum identifier, or 'plugin:...' for a plugin's item).</summary>
function HelpTopicForMenuAction(const AActionName: string): string;
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
    hdkMkDir, hdkNewFile, hdkRename, hdkCopyInPlace, hdkCreateLink, hdkDescribe:
      Result := 'fileops.md';
    hdkJobConfirm, hdkOverwriteAsk, hdkOverwriteRename:
      Result := 'fileops.md#copy';
    hdkSetAttributes:
      Result := 'fileops.md#attributes';
    hdkChecksumOptions, hdkChecksumResult:
      Result := 'fileops.md#checksums';
    hdkMultiRename:
      Result := 'fileops.md#multi-rename';
    hdkExportList:
      Result := 'fileops.md#export-list';
    hdkDeleteError, hdkIOError:
      Result := 'jobs.md#errors';
    hdkJobList, hdkJobProgress:
      Result := 'jobs.md#job-list';
    hdkStopConfirm:
      Result := 'jobs.md#stop';
    hdkSearch, hdkTmpSaveList, hdkPanelFilter:
      Result := 'search.md';
    hdkSelectMask, hdkUnselectMask:
      Result := 'selection.md';
    hdkFolderHistory, hdkCmdHistory, hdkFolderHotlist,
    hdkFolderHotlistAdd, hdkFolderHotlistRename:
      Result := 'history.md';
    hdkFileHistory:
      Result := 'history.md#file-history';
    hdkCommandPalette:
      Result := 'topmenu.md';
    hdkDirSync:
      Result := 'sync.md#dir-sync';
    hdkCompareResult:
      Result := 'sync.md#compare-files';
    hdkTerminalProfile:
      Result := 'terminals.md#profiles';
    hdkTerminalEnv:
      Result := 'environment.md#choice';
    hdkConsoleProfile:
      Result := 'cmdline.md#console-profile';
    hdkConsoleSave:
      Result := 'cmdline.md#save-output';
    hdkColorCoding, hdkColorCodingEdit:
      Result := 'settings.md#color-coding';
    hdkColorPicker, hdkThemePicker:
      Result := 'settings.md#color-picker';
    hdkTheme, hdkThemeNew, hdkThemeName, hdkThemeDelete, hdkThemeEditor,
    hdkThemeItems, hdkThemeColors, hdkThemeText, hdkThemeChoice:
      Result := 'settings.md#theme';
    hdkDisplay:
      Result := 'settings.md#display';
    hdkInterface:
      Result := 'settings.md#interface';
    hdkColumnsConfig:
      Result := 'settings.md#columns';
    hdkConsoleOptions:
      Result := 'settings.md#console';
    hdkExternalTools:
      Result := 'settings.md#external-tools';
    hdkMarkdownColors, hdkMarkdownImport, hdkMarkdownPicker:
      Result := 'settings.md#markdown-colors';
    hdkSettingsExport, hdkSettingsImport:
      Result := 'settings.md#settings-file';
    hdkConfigLocation:
      Result := 'settings.md#location';
    hdkPluginList, hdkPluginInfo, hdkPluginPerms:
      Result := 'settings.md#plugins';
    // hdkHost: the opener names the topic (TDualPanelWindow.ShowHostDialog).
    hdkArchivePassword:
      Result := 'archives.md#password';
    hdkWorkspaceLibrary, hdkWorkspaceSave, hdkWorkspaceRename,
    hdkWorkspaceConfirm:
      Result := 'workspaces.md#saved';
    hdkWorkspaceTabRename:
      Result := 'workspaces.md#workspaces';
    hdkSshConnections, hdkSshConnectionEdit, hdkSshConnectionConfirm:
      Result := 'ssh.md';
    hdkAssociations, hdkAssociationEdit, hdkAssociationConfirm:
      Result := 'associations.md';
    hdkUserMenuEdit:
      Result := 'usermenu.md#item';
    hdkUserMenuConfirm:
      Result := 'usermenu.md';
    hdkUserMenuPrompt:
      Result := 'usermenu.md#substitutions';
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

function HelpTopicForMenuAction(const AActionName: string): string;
type
  TTopicRule = record
    Prefix, Topic: string;
  end;
const
  // The first rule whose prefix starts the name wins, so the specific
  // prefixes come before the general ones.
  cRules: array[0..74] of TTopicRule = (
    (Prefix: 'tmaFileSelect'; Topic: 'selection.md'),
    (Prefix: 'tmaFileUnselect'; Topic: 'selection.md'),
    (Prefix: 'tmaFileInvertSelect'; Topic: 'selection.md'),
    (Prefix: 'tmaFileRestoreSelection'; Topic: 'selection.md'),
    (Prefix: 'tmaFileView'; Topic: 'viewer.md'),
    (Prefix: 'tmaFileExternal'; Topic: 'viewer.md'),
    (Prefix: 'tmaFileEdit'; Topic: 'viewer.md'),
    (Prefix: 'tmaFilePack'; Topic: 'archives.md#pack'),
    (Prefix: 'tmaFileUnpack'; Topic: 'archives.md#pack'),
    (Prefix: 'tmaFileCompare'; Topic: 'sync.md#compare-files'),
    (Prefix: 'tmaFileRestore'; Topic: 'drives.md'),
    (Prefix: 'tmaFileJobList'; Topic: 'jobs.md#job-list'),
    (Prefix: 'tmaFileRunInBackground'; Topic: 'jobs.md'),
    (Prefix: 'tmaFileRunInNewTab'; Topic: 'terminals.md'),
    (Prefix: 'tmaFileSetAttributes'; Topic: 'fileops.md#attributes'),
    (Prefix: 'tmaFileChecksums'; Topic: 'fileops.md#checksums'),
    (Prefix: 'tmaFileMultiRename'; Topic: 'fileops.md#multi-rename'),
    (Prefix: 'tmaFileExportList'; Topic: 'fileops.md#export-list'),
    (Prefix: 'tmaFile'; Topic: 'fileops.md'),
    (Prefix: 'tmaEdit'; Topic: 'text.md'),
    (Prefix: 'tmaLeftDrive'; Topic: 'drives.md'),
    (Prefix: 'tmaRightDrive'; Topic: 'drives.md'),
    (Prefix: 'tmaLeftSort'; Topic: 'view.md'),
    (Prefix: 'tmaRightSort'; Topic: 'view.md'),
    (Prefix: 'tmaLeftColumnModes'; Topic: 'view.md'),
    (Prefix: 'tmaRightColumnModes'; Topic: 'view.md'),
    (Prefix: 'tmaLeft'; Topic: 'panels.md'),
    (Prefix: 'tmaRight'; Topic: 'panels.md'),
    (Prefix: 'tmaCmdPalette'; Topic: 'topmenu.md'),
    (Prefix: 'tmaCmdQuickView'; Topic: 'panels.md'),
    (Prefix: 'tmaCmdFind'; Topic: 'search.md'),
    (Prefix: 'tmaCmdLiveFilter'; Topic: 'search.md'),
    (Prefix: 'tmaCmdDirSync'; Topic: 'sync.md#dir-sync'),
    (Prefix: 'tmaCmdCompareFolders'; Topic: 'sync.md#compare-folders'),
    (Prefix: 'tmaCmdUserMenu'; Topic: 'usermenu.md'),
    (Prefix: 'tmaCmdHistory'; Topic: 'history.md'),
    (Prefix: 'tmaCmdFolderHistory'; Topic: 'history.md'),
    (Prefix: 'tmaCmdFileHistory'; Topic: 'history.md#file-history'),
    (Prefix: 'tmaCmdFolderHotlist'; Topic: 'history.md'),
    (Prefix: 'tmaCmdCmdHistory'; Topic: 'history.md'),
    (Prefix: 'tmaCmdWorkspace'; Topic: 'workspaces.md#saved'),
    (Prefix: 'tmaCmdSsh'; Topic: 'ssh.md'),
    (Prefix: 'tmaCmdAssociations'; Topic: 'associations.md'),
    (Prefix: 'tmaCmdJobList'; Topic: 'jobs.md#job-list'),
    (Prefix: 'tmaCmdRecycleBin'; Topic: 'drives.md'),
    (Prefix: 'tmaCmdDriveRoot'; Topic: 'drives.md'),
    (Prefix: 'tmaCmdNewTerminal'; Topic: 'terminals.md#profiles'),
    (Prefix: 'tmaCmdConsoleProfile'; Topic: 'cmdline.md#console-profile'),
    (Prefix: 'tmaCmdSaveConsoleOutput'; Topic: 'cmdline.md#save-output'),
    (Prefix: 'tmaCmdConsole'; Topic: 'cmdline.md'),
    (Prefix: 'tmaCmdSyncConsoleDir'; Topic: 'cmdline.md'),
    (Prefix: 'tmaCmdClearConsole'; Topic: 'cmdline.md'),
    (Prefix: 'tmaCmdFocusCmdLine'; Topic: 'cmdline.md'),
    (Prefix: 'tmaCmdInsert'; Topic: 'cmdline.md'),
    (Prefix: 'tmaOptKeymap'; Topic: 'keymap.md'),
    (Prefix: 'tmaOptReloadKeymap'; Topic: 'keymap.md'),
    (Prefix: 'tmaOptZoom'; Topic: 'screen.md'),
    (Prefix: 'tmaOptResetZoom'; Topic: 'screen.md'),
    (Prefix: 'tmaOptDisplay'; Topic: 'settings.md#display'),
    (Prefix: 'tmaOptColumnsConfig'; Topic: 'settings.md#columns'),
    (Prefix: 'tmaOptTheme'; Topic: 'settings.md#theme'),
    (Prefix: 'tmaOptInterface'; Topic: 'settings.md#interface'),
    (Prefix: 'tmaOptConsoleOptions'; Topic: 'settings.md#console'),
    (Prefix: 'tmaOptExportSettings'; Topic: 'settings.md#settings-file'),
    (Prefix: 'tmaOptImportSettings'; Topic: 'settings.md#settings-file'),
    (Prefix: 'tmaOptConfigLocation'; Topic: 'settings.md#location'),
    (Prefix: 'tmaOptColorCoding'; Topic: 'settings.md#color-coding'),
    (Prefix: 'tmaOptShowPlugins'; Topic: 'settings.md#plugins'),
    (Prefix: 'tmaOptExternalTools'; Topic: 'settings.md#external-tools'),
    (Prefix: 'tmaOptMarkdownColors'; Topic: 'settings.md#markdown-colors'),
    (Prefix: 'tmaOptEnvironment'; Topic: 'environment.md'),
    (Prefix: 'tmaOptToggleMouse'; Topic: 'text.md#mouse'),
    (Prefix: 'tmaOpt'; Topic: 'settings.md'),
    (Prefix: 'tmaHelpUpdates'; Topic: 'updates.md'),
    (Prefix: 'tmaCmd'; Topic: 'panels.md'));
var
  I: Integer;
begin
  for I := Low(cRules) to High(cRules) do
    if StartsStr(cRules[I].Prefix, AActionName) then
      Exit(cRules[I].Topic);
  Result := 'topmenu.md';
end;

function HelpTopicForScreen(const AScreen: THelpScreen): string;
begin
  if AScreen.ConsoleMode then
    Exit('cmdline.md');
  if AScreen.TopMenuActive then
    Exit('topmenu.md');
  if AScreen.DialogKind <> hdkNone then
  begin
    if AScreen.DialogTopic <> '' then
      Exit(AScreen.DialogTopic);
    Exit(HelpTopicForDialog(AScreen.DialogKind));
  end;
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
