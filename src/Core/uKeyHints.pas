unit uKeyHints;

{ One-line key hints for the state the program is in: search results, an
  archive, a temporary panel, a workspace, an SFTP or plugin folder, the
  Recycle Bin, selected files, tabs, the console, a terminal, the viewer, the
  hex view, the editor, a command typed under the panels. A hint names the keys that are useful there; the keys are
  read from the live keymap, so a rebound key shows its new chord. Each hint is
  offered once per run, and not at all when the hints are switched off. }

interface

uses
  uKeymap;

type
  // The Seen bit set records the ordinal of each situation: new ones are
  // appended, never inserted.
  THintSituation = (hsNone, hsFindResults, hsArchive, hsTempPanel, hsWorkspace,
    hsSftp, hsCommandLine, hsConsoleProgram, hsSelection, hsQuickView,
    hsInfoPanel, hsRecycleBin, hsPluginFolder, hsPanelTabs, hsWorkspaces,
    hsJobs, hsConsole, hsTerminal, hsViewer, hsHexView, hsMarkdown, hsEditor,
    hsMenu, hsManySelected, hsArchiveFile, hsLongFolder, hsFolderTravel,
    hsSameNameFolders, hsEditorSelection);

  THintSituations = set of THintSituation;

  TKeyHintTracker = class
  private
    FEnabled: Boolean;
    FShown: set of THintSituation;
    function GetSeen: Integer;
    procedure SetSeen(AValue: Integer);
  public
    constructor Create(AEnabled: Boolean);
    /// <summary>The hint text for ASituation the first time it is asked for,
    /// '' afterwards, for hsNone and while the hints are off.</summary>
    function Take(ASituation: THintSituation; const AProfile: TKeymapProfile): string;
    property Enabled: Boolean read FEnabled write FEnabled;
    /// <summary>The hints shown so far as a bit set (bit = ordinal of the
    /// situation), kept in the session file so each hint appears once for good.
    /// Zero makes every hint due again.</summary>
    property Seen: Integer read GetSeen write SetSeen;
  end;

/// <summary>The situation of a panel showing AURI (hsNone for a plain folder).</summary>
function HintSituationOfUri(const AURI: string): THintSituation;

/// <summary>Last path segment of a file:// URI, else ''.</summary>
function FileUriLeafName(const AURI: string): string;

/// <summary>True when both sides are file:// folders with the same leaf name
/// but different URIs (compare / sync candidate).</summary>
function SameNameDistinctFolders(const ALeftUri, ARightUri: string): Boolean;

/// <summary>Hints for an open document surface (viewer / hex / markdown /
/// editor). Empty when the doc is not ready.</summary>
function DocumentHintSituations(AReady, AHex, AMarkdown, AViewOnly,
  AHasSelection: Boolean): THintSituations;

/// <summary>Hints for the dual-panel file surface (not console mode). Callers
/// pass live counts and chrome flags; URI scheme mapping stays in
/// HintSituationOfUri.</summary>
function PanelSurfaceHintSituations(AUriSituation: THintSituation;
  ACmdLineFocusedNonEmpty: Boolean; ASelectedCount, AHistoryLen,
  ARowCount: Integer; AArchiveFile, AQuickView, AInfoPanel,
  APanelTabs: Boolean; const ALeftUri, ARightUri: string): THintSituations;

/// <summary>The English template of a hint. {Name} stands for the keys of the
/// keymap action called Name (the keymap.json name).</summary>
function KeyHintTemplate(ASituation: THintSituation): string;

/// <summary>ATemplate with every {Name} replaced by the first keys of that
/// action in AProfile; an unknown or unbound name becomes '?'.</summary>
function ExpandKeyHint(const ATemplate: string; const AProfile: TKeymapProfile): string;

/// <summary>AText as one or two toast lines of at most AMaxCols cells each: a
/// text that does not fit is broken after the last comma that fits (else at
/// the last space), the rest going to ALine2. ALine2 is '' for a text that
/// fits.</summary>
procedure WrapKeyHint(const AText: string; AMaxCols: Integer;
  out ALine1, ALine2: string);

/// <summary>The hint of ASituation in the current language, keys filled in.</summary>
function KeyHintText(ASituation: THintSituation; const AProfile: TKeymapProfile): string;

implementation

uses
  System.SysUtils, uVfsTypes, uStrings, uCharWidth;

const
  cSituationKey: array[THintSituation] of string = (
    '', 'find', 'archive', 'temp', 'workspace', 'sftp', 'cmdline', 'program',
    'selection', 'quickview', 'info', 'recycle', 'plugin', 'tabs', 'workspaces',
    'jobs', 'console', 'terminal', 'viewer', 'hex', 'markdown', 'editor', 'menu',
    'manyselected', 'archivefile', 'longfolder', 'travel', 'samename', 'editorsel');

constructor TKeyHintTracker.Create(AEnabled: Boolean);
begin
  inherited Create;
  FEnabled := AEnabled;
  FShown := [];
end;

function TKeyHintTracker.GetSeen: Integer;
var
  S: THintSituation;
begin
  Result := 0;
  for S := Succ(hsNone) to High(THintSituation) do
    if S in FShown then
      Result := Result or (1 shl Ord(S));
end;

procedure TKeyHintTracker.SetSeen(AValue: Integer);
var
  S: THintSituation;
begin
  FShown := [];
  for S := Succ(hsNone) to High(THintSituation) do
    if AValue and (1 shl Ord(S)) <> 0 then
      Include(FShown, S);
end;

function TKeyHintTracker.Take(ASituation: THintSituation;
  const AProfile: TKeymapProfile): string;
begin
  Result := '';
  if (not FEnabled) or (ASituation = hsNone) or (ASituation in FShown) then
    Exit;
  Include(FShown, ASituation);
  Result := KeyHintText(ASituation, AProfile);
end;

function HintSituationOfUri(const AURI: string): THintSituation;
begin
  if IsFindUri(AURI) then
    Result := hsFindResults
  else if HasArchiveChain(AURI) then
    Result := hsArchive
  else if IsTmpPanelUri(AURI) then
    Result := hsTempPanel
  else if IsWorkspaceUri(AURI) then
    Result := hsWorkspace
  else if IsSftpUri(AURI) then
    Result := hsSftp
  else if IsRecycleBinUri(AURI) then
    Result := hsRecycleBin
  else if IsGenericVfsUri(AURI) then
    Result := hsPluginFolder
  else
    Result := hsNone;
end;

function FileUriLeafName(const AURI: string): string;
begin
  Result := '';
  if not SameText(Copy(AURI, 1, 7), 'file://') then
    Exit;
  Result := ExtractFileName(FileUriToPath(AURI));
end;

function SameNameDistinctFolders(const ALeftUri, ARightUri: string): Boolean;
var
  LeftName, RightName: string;
begin
  LeftName := FileUriLeafName(ALeftUri);
  RightName := FileUriLeafName(ARightUri);
  Result := (LeftName <> '') and SameText(LeftName, RightName) and
    (not SameVfsUri(ALeftUri, ARightUri));
end;

function DocumentHintSituations(AReady, AHex, AMarkdown, AViewOnly,
  AHasSelection: Boolean): THintSituations;
begin
  Result := [];
  if not AReady then
    Exit;
  if AHex then
    Include(Result, hsHexView)
  else if AMarkdown then
    Include(Result, hsMarkdown)
  else if AViewOnly then
    Include(Result, hsViewer)
  else
  begin
    Include(Result, hsEditor);
    if AHasSelection then
      Include(Result, hsEditorSelection);
  end;
end;

function PanelSurfaceHintSituations(AUriSituation: THintSituation;
  ACmdLineFocusedNonEmpty: Boolean; ASelectedCount, AHistoryLen,
  ARowCount: Integer; AArchiveFile, AQuickView, AInfoPanel,
  APanelTabs: Boolean; const ALeftUri, ARightUri: string): THintSituations;
begin
  Result := [];
  if AUriSituation <> hsNone then
    Include(Result, AUriSituation)
  else if ACmdLineFocusedNonEmpty then
    Include(Result, hsCommandLine);
  if ASelectedCount > 0 then
    Include(Result, hsSelection);
  if ASelectedCount >= 3 then
    Include(Result, hsManySelected);
  if AHistoryLen >= 8 then
    Include(Result, hsFolderTravel);
  if SameNameDistinctFolders(ALeftUri, ARightUri) then
    Include(Result, hsSameNameFolders);
  if ARowCount >= 150 then
    Include(Result, hsLongFolder);
  if AArchiveFile then
    Include(Result, hsArchiveFile);
  if AQuickView then
    Include(Result, hsQuickView);
  if AInfoPanel then
    Include(Result, hsInfoPanel);
  if APanelTabs then
    Include(Result, hsPanelTabs);
end;

procedure WrapKeyHint(const AText: string; AMaxCols: Integer;
  out ALine1, ALine2: string);
var
  Fit, I, Cut: Integer;
begin
  ALine1 := AText;
  ALine2 := '';
  if (AMaxCols < 8) or (TextDisplayWidth(AText) <= AMaxCols) then
    Exit;
  Fit := TextFitChars(AText, AMaxCols);
  Cut := 0;
  for I := 1 to Fit do
    if (AText[I] = ',') or (AText[I] = #$FF0C) or (AText[I] = #$3001) then
      Cut := I;
  if Cut > 0 then
  begin
    ALine1 := Copy(AText, 1, Cut);
    ALine2 := Trim(Copy(AText, Cut + 1, MaxInt));
    Exit;
  end;
  for I := Fit downto 1 do
    if AText[I] = ' ' then
    begin
      ALine1 := Copy(AText, 1, I - 1);
      ALine2 := Copy(AText, I + 1, MaxInt);
      Exit;
    end;
  ALine1 := Copy(AText, 1, Fit);
  ALine2 := Copy(AText, Fit + 1, MaxInt);
end;

function KeyHintTemplate(ASituation: THintSituation): string;
begin
  case ASituation of
    hsFindResults:
      Result := 'Found: Enter goes to file, {View} view, {Edit} edit, ' +
        'Alt+Shift+F3 other panel';
    hsArchive:
      Result := 'Archive: {Copy} unpacks to the other panel, {View} views a file';
    hsTempPanel:
      Result := 'Temp panel: F7 remove, Alt+Shift+F2 save list, ' +
        'Alt+Shift+F3 go to file';
    hsWorkspace:
      Result := 'Workspace: F8 unlink, F7 virtual folder, Alt+Shift+F3 show original';
    hsSftp:
      Result := 'SFTP: {Copy} downloads to the other panel, ' +
        '{SshConnections} connections';
    hsCommandLine:
      Result := 'Enter: run, {RunInBackground}: background, {RunInNewTab}: new tab';
    hsConsoleProgram:
      Result := 'Also: {RunInBackground} runs in background, ' +
        '{RunInNewTab} in a terminal tab';
    hsSelection:
      Result := 'Selected: {Copy} copy, {Move} move, {Delete} delete, ' +
        '{InvertSelection} invert, {UnselectAll} clear';
    hsQuickView:
      Result := 'Quick view: it follows the cursor of the other panel, ' +
        '{QuickView} or Esc closes it';
    hsInfoPanel:
      Result := 'Info panel: {InfoPanel} brings the file list back';
    hsRecycleBin:
      Result := 'Recycle Bin: {Restore} restores, {DeletePermanent} deletes for good';
    hsPluginFolder:
      Result := 'Plugin folder: {Copy} copies to the other panel, {Refresh} refreshes';
    hsPanelTabs:
      Result := 'Panel tabs: {NextPanelTab} next, {PrevPanelTab} previous, ' +
        '{NewTab} new, {CloseTab} close';
    hsWorkspaces:
      Result := 'Workspaces: {NextTab} next, {PrevTab} previous, {NewWorkspace} new';
    hsJobs:
      Result := 'Background jobs: {JobList} opens the list, a click on a chip does too';
    hsConsole:
      Result := 'Console: {AppConsoleToggle} back to the panels, ' +
        '{ShellFind} find in the output, {ShellPaste} paste';
    hsTerminal:
      Result := 'Terminal: {ShellFind} find, {ShellPaste} paste, ' +
        '{NextTab} next workspace';
    hsViewer:
      Result := 'View: {DocFind} find, {DocGotoLine} go to line, {DocHex} hex, ' +
        '{DocEncodingNext} encoding, {ViewerFollow} follow the end';
    hsHexView:
      Result := 'Hex: {DocHex} back to text, {DocFind} find, {DocClose} close';
    hsMarkdown:
      Result := 'Markdown: {MarkdownSource} shows the source, Tab links, {DocFind} finds, ' +
        '{DocClose} closes';
    hsEditor:
      Result := 'Edit: {EditorSave} save, {EditorReplace} replace, ' +
        '{EditorBookmarkToggle} bookmark, {EditorDeleteLine} delete line';
    hsMenu:
      Result := 'Tip: {CommandPalette} finds any command by name and shows its keys';
    hsManySelected:
      Result := 'Several files: {MultiRename} rename by rules, ' +
        '{RestoreSelection} last selection';
    hsArchiveFile:
      Result := 'Archive file: Enter or {FolderDown} opens it as a folder, {Unpack} unpacks it';
    hsLongFolder:
      Result := 'Long folder: {LiveFilter} filters as you type, {ToggleHidden} hidden files, ' +
        '{SortMenu} sorting';
    hsFolderTravel:
      Result := 'Folders: {FolderHistory} history, {FolderHotlist} hotlist, {FolderTree} tree, ' +
        '{FolderHotlistAdd} adds this one';
    hsSameNameFolders:
      Result := 'Same name in both panels: {CompareFolders} marks differences, {DirSync} syncs';
    hsEditorSelection:
      Result := 'Selected lines: {EditorSortLines} sort, {EditorUniqueLines} remove repeats, ' +
        '{EditorShiftRight} indent';
  else
    Result := '';
  end;
end;

function ExpandKeyHint(const ATemplate: string; const AProfile: TKeymapProfile): string;
var
  P, Q: Integer;
  Name, Keys: string;
  Action: TKeymapAction;
begin
  Result := '';
  P := 1;
  while P <= Length(ATemplate) do
  begin
    if ATemplate[P] = '{' then
    begin
      Q := Pos('}', ATemplate, P);
      if Q > P then
      begin
        Name := Copy(ATemplate, P + 1, Q - P - 1);
        Keys := '';
        if TryKeymapActionByName(Name, Action) then
          Keys := KeymapShortcutText(AProfile, Action, 1);
        if Keys = '' then
          Keys := '?';
        Result := Result + Keys;
        P := Q + 1;
        Continue;
      end;
    end;
    Result := Result + ATemplate[P];
    Inc(P);
  end;
end;

function KeyHintText(ASituation: THintSituation; const AProfile: TKeymapProfile): string;
var
  Template: string;
begin
  Template := KeyHintTemplate(ASituation);
  if Template = '' then
    Exit('');
  Result := ExpandKeyHint(T('ui.hint.' + cSituationKey[ASituation], Template), AProfile);
end;

end.
