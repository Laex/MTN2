unit uDualPanelTypes;

{ Dual Panel state structures (SDS §3.3) and panel row model for the Pull
  contract. Stage 5 fills rows from IVirtualFileSystem list results. }

interface

uses
  System.SysUtils, System.Math, System.IOUtils, uVfsTypes;

type
  /// <summary>Per-panel column layout (Ctrl+` opens mode menu).</summary>
  TPanelColumnMode = (
    pcmBrief,    // Name only
    pcmSize,     // Name | Size
    pcmDate,     // Name | Size | Modified
    pcmFull,     // Name | Size | Modified | Attr  (default)
    pcmCreated,  // Name | Size | Created | Attr
    pcmTypes,    // Name | Ext | Size | Type | Attr
    pcmCustom    // Name | user-picked subset (see uPanelColumns.GCustomColumnsConfig)
  );

  /// <summary>Active list sort key (click column headers / Ctrl+F12 to change).
  /// Header cycle per column: ascending → descending → none.</summary>
  TPanelSortColumn = (
    pscNone,
    pscName,
    pscExt,
    pscSize,
    pscModified,
    pscCreated,
    pscAccessed,
    pscAttr,
    pscType
  );

  TTab = record
    Id: Cardinal;
    Title: string;            // Panel Tab caption (e.g. 'home', 'documents')
    CurrentURI: string;       // e.g. 'file:///D:/Work'
    History: TArray<string>;
    HistoryIndex: Integer;
    CursorIndex: Integer;
    ScrollOffset: Integer;
    SelectedURIs: TArray<string>; // multi-select by row URI (Stage 6)
    /// <summary>Ephemeral: ws:// folder this tab left via a dir-link Enter.
    /// Empty unless this tab (not the other panel) entered from Workspace.</summary>
    WorkspaceBackUri: string;
    /// <summary>file:// of that dir-link target. `..` rewrites only here.</summary>
    WorkspaceBackTarget: string;
  end;

  TPanelSide = (psLeft, psRight);

  /// <summary>Panel content mode. Ctrl+L toggles Info on the adjacent panel.</summary>
  TPanelViewKind = (pvkFiles, pvkInfo, pvkQuickView);

  /// <summary>Last visited directory path per drive letter (A–Z) for one panel.</summary>
  TPanelDriveDirs = array['A'..'Z'] of string;

  TPanelState = record
    Tabs: TArray<TTab>;
    ActiveTabIndex: Integer;
    DriveDirs: TPanelDriveDirs;
    ColumnMode: TPanelColumnMode;
    SortColumn: TPanelSortColumn;
    SortDescending: Boolean;
    ViewKind: TPanelViewKind;
    ShowHiddenFiles: Boolean;  // Ctrl+H toggle — Hidden/System files in listing
  end;

  TDualPanelState = record
    LeftPanel: TPanelState;
    RightPanel: TPanelState;
    ActiveSide: TPanelSide;
    LeftVisible: Boolean;   // FAR Ctrl+F1 — hide/show left
    RightVisible: Boolean;  // FAR Ctrl+F2 — hide/show right
  end;

  /// <summary>Dual Panel Tabs: panels snapshot, Viewer/Editor document, or a
  /// live Terminal Workspace session.</summary>
  TWorkspaceKind = (wkPanels, wkDocument, wkTerminal);

  TDualPanelWorkspaceTab = record
    Id: Cardinal;
    Title: string;
    /// <summary>User renamed the tab. Document tabs then keep Title instead
    /// of tracking the editor caption (filename and dirty mark).</summary>
    TitleCustom: Boolean;
    Kind: TWorkspaceKind;   // default wkPanels
    State: TDualPanelState; // used when Kind = wkPanels
    DocURI: string;         // used when Kind = wkDocument
    ViewOnly: Boolean;
    /// <summary>Workspace Id that opened this Viewer/Editor; 0 = unknown.</summary>
    OriginWorkspaceId: Cardinal;
    /// <summary>Shell profile id; used when Kind = wkTerminal (set at
    /// creation, ephemeral like the tab itself — not persisted).</summary>
    TermProfileId: string;
  end;

  TDualPanelWindowState = record
    WorkspaceTabs: TArray<TDualPanelWorkspaceTab>;
    ActiveWorkspaceIndex: Integer;
  end;

  // Logical row returned by panel Pull (no style fields — theme decides colour).
  // Stores full metadata so Host can switch column modes without re-listing.
  TPanelRow = record
    Id: string;
    Text: string;             // display name (dirs may end with '/')
    Extension: string;        // incl. leading '.', empty for dirs/parent
    Size: Int64;
    SizeText: string;
    DateText: string;         // modified
    CreatedText: string;
    AccessedText: string;
    AttrText: string;         // FAR-style 'RHSAL'
    IsDirectory: Boolean;
    IsParent: Boolean;
    IsHidden: Boolean;
    IsReadOnly: Boolean;
    IsSystem: Boolean;
    IsArchive: Boolean;
    IsCompressed: Boolean;
    IsEncrypted: Boolean;
    IsTemporary: Boolean;
    IsOffline: Boolean;
    IsLink: Boolean;
    FileType: string;
    URI: string;
    TargetURI: string;        // same as URI unless VFS set a redirect
    ModificationTime: TDateTime;
    CreationTime: TDateTime;
    AccessTime: TDateTime;
    /// <summary>Alt+F7 content-search hit (find:// rows only); 0/'' elsewhere.</summary>
    MatchLine: Integer;
    MatchSnippet: string;
  end;

  TPanelRows = TArray<TPanelRow>;

function MakeTab(AId: Cardinal; const ATitle, AURI: string): TTab;
function MakePanelRow(const AText: string; AIsDir: Boolean;
  ASize: Int64 = -1; const ASizeText: string = ''; const ADateText: string = '';
  const AURI: string = ''; AIsParent: Boolean = False;
  AIsHidden: Boolean = False; const AAttrText: string = '';
  AIsLink: Boolean = False): TPanelRow;
function MakePanelRowFromEntry(const AEntry: TVfsEntry;
  const ADisplayName, ASizeText, AURI: string): TPanelRow;
/// <summary>Logical PANEL_PLUGIN file_type for theme coloring.</summary>
function ClassifyPanelFileType(const AName: string;
  AIsDirectory, AIsParent: Boolean): string;
function FormatSizeShort(ABytes: Int64): string;
procedure PanelTotals(const ARows: TPanelRows; out ABytes: Int64;
  out AFiles, AFolders: Integer);
procedure PanelSelectionTotals(const ATab: TTab; const ARows: TPanelRows;
  out ABytes: Int64; out AFiles, AFolders: Integer);
function ActiveTab(const APanel: TPanelState): TTab;
procedure SetActiveTab(var APanel: TPanelState; const ATab: TTab);
/// <summary>Deep-copy panel tabs + layout settings; assigns fresh tab Ids.</summary>
function ClonePanelState(const APanel: TPanelState; var ANextId: Cardinal): TPanelState;
/// <summary>Session tab caption from active left/right directories (e.g. "Work | Docs").</summary>
function MakePanelsWorkspaceTitle(const AState: TDualPanelState): string;
procedure ClearPanelDriveDirs(var ADirs: TPanelDriveDirs);
procedure RememberPanelDriveDir(var ADirs: TPanelDriveDirs; const APathOrUri: string);
function ResolvePanelDriveUri(const ADirs: TPanelDriveDirs; ALetter: Char;
  const ARootPath: string): string;
procedure SeedPanelDriveDirs(var APanel: TPanelState);
function FormatFileDate(const AValue: TDateTime): string;
function RowsFromVfsItems(const ADirURI: string;
  const AItems: TArray<TVfsEntry>;
  const AWorkspaceReturnUri: string = ''): TPanelRows;
function LoadingRows: TPanelRows;
function ErrorRows(const ADirURI, AMessage: string;
  const AWorkspaceReturnUri: string = ''): TPanelRows;
function TabIsSelected(const ATab: TTab; const AURI: string): Boolean;
/// <summary>Sorted VfsUriKey of every selected URI. Build once per loop over
/// rows and test with SelectionKeysHas: TabIsSelected per row is
/// O(rows * selected) SameVfsUri calls, which froze the UI on large
/// selections (every repaint runs several such loops).</summary>
function TabSelectionKeys(const ATab: TTab): TArray<string>;
function SelectionKeysHas(const AKeys: TArray<string>; const AURI: string): Boolean;
/// <summary>Toggle selection of every selectable row in ARows[ALo..AHi]
/// (same result as TabToggleSelected per row, without the quadratic cost).</summary>
procedure TabToggleSelectedRange(var ATab: TTab; const ARows: TPanelRows;
  ALo, AHi: Integer);
procedure TabClearSelection(var ATab: TTab);
procedure TabToggleSelected(var ATab: TTab; const AURI: string);
procedure TabSetSelected(var ATab: TTab; const AURI: string; ASelected: Boolean);
procedure TabSelectAllVisible(var ATab: TTab; const ARows: TPanelRows);
procedure TabSelectByMask(var ATab: TTab; const ARows: TPanelRows;
  const AMask: string; AIncludeFolders: Boolean = False);
procedure TabUnselectByMask(var ATab: TTab; const ARows: TPanelRows;
  const AMask: string; AIncludeFolders: Boolean = False);
/// <summary>FAR Alt+Gray+/−: same name stem (no last extension) as AStem.</summary>
procedure TabSelectByNameStem(var ATab: TTab; const ARows: TPanelRows;
  const AStem: string; AUnselect: Boolean; AIncludeFolders: Boolean = False);
function FileNameStem(const AName: string): string;
/// <summary>Fit AText into AMaxLen. When the name has a real extension,
/// keeps it visible: ``prefix...suffix.ext``. Otherwise mid-ellipsis.
/// Replaces the old trailing ``~`` truncation used in panel lists/status.</summary>
function EllipsizeKeepingExt(const AText: string; AMaxLen: Integer): string;
function PanelRowMaskName(const ARow: TPanelRow): string;
function PanelRowIsDirectory(const ARow: TPanelRow): Boolean;
function TabHasSelectedDirectories(const ATab: TTab;
  const ARows: TPanelRows): Boolean;
function CollectSelectedDirectoryUris(const ATab: TTab;
  const ARows: TPanelRows): TArray<string>;
procedure TabInvertSelection(var ATab: TTab; const ARows: TPanelRows);
/// <summary>Inclusive index range to invert for Shift+nav. ADelta is the move
/// delta before clamp; AExcludeLanding omits ATo (Brief Left/Right).</summary>
function ShiftNavInvertRange(AFrom, ATo, ADelta: Integer; AExcludeLanding: Boolean;
  out ALo, AHi: Integer): Boolean;

implementation

uses
  System.Generics.Collections, System.Generics.Defaults, uFindSession, uFileFind;

function MakeTab(AId: Cardinal; const ATitle, AURI: string): TTab;
begin
  Result.Id := AId;
  Result.Title := ATitle;
  Result.CurrentURI := AURI;
  SetLength(Result.History, 1);
  Result.History[0] := AURI;
  Result.HistoryIndex := 0;
  Result.CursorIndex := 0;
  Result.ScrollOffset := 0;
  SetLength(Result.SelectedURIs, 0);
  Result.WorkspaceBackUri := '';
  Result.WorkspaceBackTarget := '';
end;

function IsExecutablePanelFileExt(const AExt: string): Boolean;
begin
  Result := (AExt = '.exe') or (AExt = '.com') or (AExt = '.bat') or (AExt = '.cmd') or
    (AExt = '.msi') or (AExt = '.ps1') or (AExt = '.vbs') or (AExt = '.lnk');
end;

function IsMediaPanelFileExt(const AExt: string): Boolean;
begin
  Result := (AExt = '.png') or (AExt = '.jpg') or (AExt = '.jpeg') or (AExt = '.gif') or
    (AExt = '.bmp') or (AExt = '.ico') or (AExt = '.webp') or (AExt = '.svg') or
    (AExt = '.mp3') or (AExt = '.mp4') or (AExt = '.avi') or (AExt = '.mkv') or
    (AExt = '.wav') or (AExt = '.flac') or (AExt = '.pdf');
end;

function ClassifyPanelFileType(const AName: string;
  AIsDirectory, AIsParent: Boolean): string;
var
  Ext, Base: string;
begin
  if AIsParent or AIsDirectory then
    Exit('directory');
  Base := AName;
  // Display names may append '/' for directories — strip just in case.
  if (Base <> '') and (Base[Length(Base)] = '/') then
    Base := Copy(Base, 1, Length(Base) - 1);
  Ext := LowerCase(TPath.GetExtension(Base));
  if IsZipFileName(Base) or IsSevenZipFileName(Base) then
    Exit('archive');
  if IsExecutablePanelFileExt(Ext) then
    Exit('executable');
  if IsMediaPanelFileExt(Ext) then
    Exit('media');
  Result := 'document';
end;

function MakePanelRow(const AText: string; AIsDir: Boolean;
  ASize: Int64; const ASizeText, ADateText, AURI: string; AIsParent: Boolean;
  AIsHidden: Boolean; const AAttrText: string; AIsLink: Boolean): TPanelRow;
var
  Base: string;
begin
  Result.Id := AURI;
  if Result.Id = '' then
    Result.Id := AText;
  Result.Text := AText;
  Result.Extension := '';
  Result.Size := ASize;
  Result.SizeText := ASizeText;
  Result.DateText := ADateText;
  Result.CreatedText := '';
  Result.AccessedText := '';
  if AAttrText <> '' then
    Result.AttrText := AAttrText
  else
    Result.AttrText := '-----';
  Result.IsDirectory := AIsDir;
  Result.IsParent := AIsParent;
  Result.IsHidden := AIsHidden and not AIsParent;
  Result.IsReadOnly := False;
  Result.IsSystem := False;
  Result.IsArchive := False;
  Result.IsCompressed := False;
  Result.IsEncrypted := False;
  Result.IsTemporary := False;
  Result.IsOffline := False;
  Result.IsLink := AIsLink and not AIsParent;
  Result.FileType := ClassifyPanelFileType(AText, AIsDir, AIsParent);
  Result.URI := AURI;
  Result.TargetURI := AURI;
  Result.ModificationTime := 0;
  Result.CreationTime := 0;
  Result.AccessTime := 0;
  Result.MatchLine := 0;
  Result.MatchSnippet := '';
  Base := AText;
  if (Base <> '') and (Base[Length(Base)] = '/') then
    Base := Copy(Base, 1, Length(Base) - 1);
  if AIsDir or AIsParent then
    Result.Extension := ''
  else
    Result.Extension := LowerCase(TPath.GetExtension(Base));
end;

function MakePanelRowFromEntry(const AEntry: TVfsEntry;
  const ADisplayName, ASizeText, AURI: string): TPanelRow;
begin
  Result := MakePanelRow(ADisplayName, AEntry.IsDirectory, AEntry.Size, ASizeText,
    FormatFileDate(AEntry.ModificationTime), AURI, False, AEntry.IsHidden,
    FormatVfsAttrText(AEntry), AEntry.IsLink);
  // Directories never have an "extension" — even when VFS reports none and
  // the name itself contains a dot (e.g. "My.Folder"). MakePanelRow already
  // got this right via AIsDir above; don't let the file-only fallback below
  // clobber it (Text carries a trailing '/' for dirs — see RowsFromVfsItems
  // — so stripping Extension's length back out of Text would eat into the
  // name itself, not just the fake extension).
  if not AEntry.IsDirectory then
  begin
    Result.Extension := AEntry.Extension;
    if Result.Extension = '' then
      Result.Extension := LowerCase(TPath.GetExtension(AEntry.Name));
  end;
  Result.CreatedText := FormatFileDate(AEntry.CreationTime);
  Result.AccessedText := FormatFileDate(AEntry.AccessTime);
  Result.IsReadOnly := AEntry.IsReadOnly;
  Result.IsSystem := AEntry.IsSystem;
  Result.IsArchive := AEntry.IsArchive;
  Result.IsCompressed := AEntry.IsCompressed;
  Result.IsEncrypted := AEntry.IsEncrypted;
  Result.IsTemporary := AEntry.IsTemporary;
  Result.IsOffline := AEntry.IsOffline;
  Result.ModificationTime := AEntry.ModificationTime;
  Result.CreationTime := AEntry.CreationTime;
  Result.AccessTime := AEntry.AccessTime;
  Result.MatchSnippet := AEntry.MatchSnippet;
  if Result.MatchSnippet <> '' then
    Result.MatchLine := AEntry.MatchLine;
  if AEntry.TargetURI <> '' then
    Result.TargetURI := AEntry.TargetURI
  else
    Result.TargetURI := AURI;
  Result.FileType := ClassifyPanelFileType(AEntry.Name, AEntry.IsDirectory, False);
end;

function FormatSizeShort(ABytes: Int64): string;
begin
  if ABytes < 0 then
    Exit('0');
  if ABytes < 1024 then
    Result := IntToStr(ABytes)
  else if ABytes < 1024 * 1024 then
    Result := Format('%.0f K', [ABytes / 1024])
  else if ABytes < Int64(1024) * 1024 * 1024 then
    Result := Format('%.1f M', [ABytes / (1024 * 1024)])
  else
    Result := Format('%.1f G', [ABytes / (Int64(1024) * 1024 * 1024)]);
end;

procedure PanelTotals(const ARows: TPanelRows; out ABytes: Int64;
  out AFiles, AFolders: Integer);
var
  R: TPanelRow;
begin
  ABytes := 0;
  AFiles := 0;
  AFolders := 0;
  for R in ARows do
  begin
    if R.IsParent then
      Continue;
    if R.IsDirectory then
    begin
      Inc(AFolders);
      if R.Size > 0 then
        Inc(ABytes, R.Size);
    end
    else
    begin
      Inc(AFiles);
      if R.Size > 0 then
        Inc(ABytes, R.Size);
    end;
  end;
end;

procedure PanelSelectionTotals(const ATab: TTab; const ARows: TPanelRows;
  out ABytes: Int64; out AFiles, AFolders: Integer);
var
  R: TPanelRow;
  Keys: TArray<string>;
begin
  ABytes := 0;
  AFiles := 0;
  AFolders := 0;
  if Length(ATab.SelectedURIs) = 0 then
    Exit;
  Keys := TabSelectionKeys(ATab);
  for R in ARows do
  begin
    if R.IsParent or (R.URI = '') then
      Continue;
    if not SelectionKeysHas(Keys, R.URI) then
      Continue;
    if R.IsDirectory then
    begin
      Inc(AFolders);
      if R.Size > 0 then
        Inc(ABytes, R.Size);
    end
    else
    begin
      Inc(AFiles);
      if R.Size > 0 then
        Inc(ABytes, R.Size);
    end;
  end;
end;

function ActiveTab(const APanel: TPanelState): TTab;
begin
  if (Length(APanel.Tabs) = 0) or (APanel.ActiveTabIndex < 0) or
     (APanel.ActiveTabIndex > High(APanel.Tabs)) then
  begin
    Result := MakeTab(0, 'empty', 'file:///');
    Exit;
  end;
  Result := APanel.Tabs[APanel.ActiveTabIndex];
end;

function PanelSideCaption(const APanel: TPanelState): string;
var
  Tab: TTab;
begin
  Tab := ActiveTab(APanel);
  Result := Trim(Tab.Title);
  if Result = '' then
  begin
    if Tab.CurrentURI <> '' then
      Result := VfsUriTitle(Tab.CurrentURI)
    else
      Result := '?';
  end;
end;

function ClonePanelState(const APanel: TPanelState; var ANextId: Cardinal): TPanelState;
var
  I: Integer;
begin
  Result.ActiveTabIndex := APanel.ActiveTabIndex;
  Result.DriveDirs := APanel.DriveDirs;
  Result.ColumnMode := APanel.ColumnMode;
  Result.SortColumn := APanel.SortColumn;
  Result.SortDescending := APanel.SortDescending;
  Result.ViewKind := APanel.ViewKind;
  Result.ShowHiddenFiles := APanel.ShowHiddenFiles;
  SetLength(Result.Tabs, Length(APanel.Tabs));
  for I := 0 to High(APanel.Tabs) do
  begin
    Result.Tabs[I] := APanel.Tabs[I];
    Result.Tabs[I].Id := ANextId;
    Inc(ANextId);
    Result.Tabs[I].History := Copy(APanel.Tabs[I].History);
    Result.Tabs[I].SelectedURIs := Copy(APanel.Tabs[I].SelectedURIs);
  end;
  if (Result.ActiveTabIndex < 0) or (Result.ActiveTabIndex > High(Result.Tabs)) then
    Result.ActiveTabIndex := 0;
end;

function MakePanelsWorkspaceTitle(const AState: TDualPanelState): string;
var
  LeftCap, RightCap: string;
begin
  LeftCap := PanelSideCaption(AState.LeftPanel);
  RightCap := PanelSideCaption(AState.RightPanel);
  if (not AState.LeftVisible) and AState.RightVisible then
    Exit(RightCap);
  if AState.LeftVisible and (not AState.RightVisible) then
    Exit(LeftCap);
  Result := LeftCap + ' | ' + RightCap;
end;

procedure SetActiveTab(var APanel: TPanelState; const ATab: TTab);
begin
  if (Length(APanel.Tabs) = 0) or (APanel.ActiveTabIndex < 0) or
     (APanel.ActiveTabIndex > High(APanel.Tabs)) then
    Exit;
  APanel.Tabs[APanel.ActiveTabIndex] := ATab;
end;

procedure ClearPanelDriveDirs(var ADirs: TPanelDriveDirs);
var
  L: Char;
begin
  for L := 'A' to 'Z' do
    ADirs[L] := '';
end;

procedure RememberPanelDriveDir(var ADirs: TPanelDriveDirs; const APathOrUri: string);
var
  Path: string;
  Letter: Char;
begin
  if APathOrUri = '' then
    Exit;
  if Pos('://', APathOrUri) > 0 then
    Path := FileUriToPath(APathOrUri)
  else
    Path := APathOrUri;
  Letter := DriveLetterOf(Path);
  if Letter = #0 then
    Exit;
  // Store directory path (not URI) so DirectoryExists checks stay simple.
  ADirs[Letter] := ExcludeTrailingPathDelimiter(Path);
  if ADirs[Letter] = '' then
    ADirs[Letter] := Path;
end;

function ResolvePanelDriveUri(const ADirs: TPanelDriveDirs; ALetter: Char;
  const ARootPath: string): string;
var
  Mem: string;
begin
  ALetter := UpCase(ALetter);
  if (ALetter < 'A') or (ALetter > 'Z') then
    Exit(PathToFileUri(ARootPath));
  Mem := ADirs[ALetter];
  if Mem <> '' then
  begin
    if (Length(Mem) = 2) and (Mem[2] = ':') then
      Mem := Mem + PathDelim;
    // No LocalPathIsDirectory pre-check here on purpose: GetFileAttributes
    // is a synchronous Win32 call that can block for a long time on an
    // unresponsive network drive, and this function runs on the UI thread
    // (NavigatePanelToDrive), before ListDirectoryAsync's own background
    // dispatch even starts (uPanelModel.pas.Open) -- selecting such a drive
    // in Change Drive / Ctrl+Left+Right would freeze the window right here,
    // never even reaching Open's own async handling or slow-navigation
    // watchdog. If the remembered folder no longer exists, the async
    // listing reports "Path not found" the same way any other missing-folder
    // navigation does -- no need to duplicate that check synchronously.
    Exit(PathToFileUri(Mem));
  end;
  Result := PathToFileUri(ARootPath);
end;

procedure SeedPanelDriveDirs(var APanel: TPanelState);
var
  I: Integer;
begin
  for I := 0 to High(APanel.Tabs) do
    RememberPanelDriveDir(APanel.DriveDirs, APanel.Tabs[I].CurrentURI);
end;

function FormatFileDate(const AValue: TDateTime): string;
begin
  if AValue <= 0 then
    Result := ''
  else
    Result := FormatDateTime('dd.mm.yy hh:nn', AValue);
end;

function ParentRowUri(const ADirURI, AWorkspaceReturnUri: string): string;
begin
  if IsFindUri(ADirURI) then
    Exit(FindSessionParentFileUri(ADirURI));
  if AWorkspaceReturnUri <> '' then
    Exit(AWorkspaceReturnUri);
  Result := ParentFileUri(ADirURI);
end;

function RowsFromVfsItems(const ADirURI: string;
  const AItems: TArray<TVfsEntry>;
  const AWorkspaceReturnUri: string): TPanelRows;
var
  I, Base: Integer;
  ParentURI, ChildURI, NameText, SizeText: string;
  Attr: TVfsEntry;
  ShowParent: Boolean;
begin
  ShowParent := (not IsFileUriDriveRoot(ADirURI) or (AWorkspaceReturnUri <> '')) and
    not IsTmpPanelUri(ADirURI);
  if ShowParent then
  begin
    ParentURI := ParentRowUri(ADirURI, AWorkspaceReturnUri);
    if ParentURI = '' then
    begin
      SetLength(Result, Length(AItems));
      Base := 0;
    end
    else
    begin
      SetLength(Result, Length(AItems) + 1);
      Result[0] := MakePanelRow('..', True, -1, '<UP>', '', ParentURI, True);
      Base := 1;
    end;
  end
  else
  begin
    SetLength(Result, Length(AItems));
    Base := 0;
  end;
  for I := 0 to High(AItems) do
  begin
    Attr := AItems[I];
    if Attr.TargetURI <> '' then
      ChildURI := Attr.TargetURI
    else
      ChildURI := JoinFileUri(ADirURI, Attr.Name);
    if Attr.IsDirectory then
    begin
      NameText := Attr.Name + '/';
      if Attr.IsLink then
        SizeText := '<JUNC>'
      else
        SizeText := '<DIR>';
    end
    else
    begin
      NameText := Attr.Name;
      if Attr.IsLink then
        SizeText := '<LINK>'
      else
        SizeText := FormatSizeShort(Attr.Size);
    end;
    Result[Base + I] := MakePanelRowFromEntry(Attr, NameText, SizeText, ChildURI);
  end;
end;

function LoadingRows: TPanelRows;
begin
  SetLength(Result, 1);
  Result[0] := MakePanelRow('Reading...', False, -1, '', '', '', False);
end;

function ErrorRows(const ADirURI, AMessage: string;
  const AWorkspaceReturnUri: string): TPanelRows;
var
  Msg: string;
  ParentURI: string;
  ShowParent: Boolean;
begin
  Msg := AMessage;
  if Msg = '' then
    Msg := 'Error';
  // Always keep ".." so the user can leave Access denied / missing folders.
  ShowParent := ((ADirURI <> '') and not IsFileUriDriveRoot(ADirURI)) or
    (AWorkspaceReturnUri <> '');
  if ShowParent then
  begin
    ParentURI := ParentRowUri(ADirURI, AWorkspaceReturnUri);
    if ParentURI = '' then
    begin
      SetLength(Result, 1);
      Result[0] := MakePanelRow(Msg, False, -1, '', '', '', False);
    end
    else
    begin
      SetLength(Result, 2);
      Result[0] := MakePanelRow('..', True, -1, '<UP>', '', ParentURI, True);
      Result[1] := MakePanelRow(Msg, False, -1, '', '', '', False);
    end;
  end
  else
  begin
    SetLength(Result, 1);
    Result[0] := MakePanelRow(Msg, False, -1, '', '', '', False);
  end;
end;

function TabIsSelected(const ATab: TTab; const AURI: string): Boolean;
var
  S: string;
begin
  Result := False;
  if AURI = '' then
    Exit;
  for S in ATab.SelectedURIs do
    if SameVfsUri(S, AURI) then
      Exit(True);
end;

function SortedKeysHas(const AKeys: TArray<string>; const AKey: string): Boolean;
var
  Lo, Hi, Mid, C: Integer;
begin
  Lo := 0;
  Hi := High(AKeys);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) shr 1;
    C := CompareStr(AKeys[Mid], AKey);
    if C = 0 then
      Exit(True);
    if C < 0 then
      Lo := Mid + 1
    else
      Hi := Mid - 1;
  end;
  Result := False;
end;

function SortKeys(const AKeys: TArray<string>): TArray<string>;
begin
  Result := AKeys;
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const L, R: string): Integer
    begin
      Result := CompareStr(L, R);
    end));
end;

function TabSelectionKeys(const ATab: TTab): TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Length(ATab.SelectedURIs));
  for I := 0 to High(ATab.SelectedURIs) do
    Result[I] := VfsUriKey(ATab.SelectedURIs[I]);
  Result := SortKeys(Result);
end;

function SelectionKeysHas(const AKeys: TArray<string>; const AURI: string): Boolean;
begin
  Result := (AURI <> '') and (Length(AKeys) > 0) and
    SortedKeysHas(AKeys, VfsUriKey(AURI));
end;

procedure TabToggleSelectedRange(var ATab: TTab; const ARows: TPanelRows;
  ALo, AHi: Integer);
var
  Keys, Drop, Add, Kept: TArray<string>;
  K: string;
  I, N: Integer;
begin
  ALo := Max(ALo, 0);
  AHi := Min(AHi, High(ARows));
  if ALo > AHi then
    Exit;
  Keys := TabSelectionKeys(ATab);
  for I := ALo to AHi do
  begin
    if ARows[I].IsParent or (ARows[I].URI = '') then
      Continue;
    K := VfsUriKey(ARows[I].URI);
    if SortedKeysHas(Keys, K) then
      Drop := Drop + [K]
    else
      Add := Add + [ARows[I].URI];
  end;
  if Length(Drop) > 0 then
  begin
    Drop := SortKeys(Drop);
    SetLength(Kept, Length(ATab.SelectedURIs));
    N := 0;
    for I := 0 to High(ATab.SelectedURIs) do
      if not SortedKeysHas(Drop, VfsUriKey(ATab.SelectedURIs[I])) then
      begin
        Kept[N] := ATab.SelectedURIs[I];
        Inc(N);
      end;
    SetLength(Kept, N);
    ATab.SelectedURIs := Kept;
  end;
  ATab.SelectedURIs := ATab.SelectedURIs + Add;
end;

procedure TabClearSelection(var ATab: TTab);
begin
  SetLength(ATab.SelectedURIs, 0);
end;

procedure TabToggleSelected(var ATab: TTab; const AURI: string);
var
  I, N: Integer;
begin
  if AURI = '' then
    Exit;
  for I := 0 to High(ATab.SelectedURIs) do
    if SameVfsUri(ATab.SelectedURIs[I], AURI) then
    begin
      N := Length(ATab.SelectedURIs);
      if I < N - 1 then
        ATab.SelectedURIs[I] := ATab.SelectedURIs[N - 1];
      SetLength(ATab.SelectedURIs, N - 1);
      Exit;
    end;
  N := Length(ATab.SelectedURIs);
  SetLength(ATab.SelectedURIs, N + 1);
  ATab.SelectedURIs[N] := AURI;
end;

procedure TabSetSelected(var ATab: TTab; const AURI: string; ASelected: Boolean);
begin
  if AURI = '' then
    Exit;
  if TabIsSelected(ATab, AURI) = ASelected then
    Exit;
  TabToggleSelected(ATab, AURI);
end;

procedure TabSelectAllVisible(var ATab: TTab; const ARows: TPanelRows);
var
  R: TPanelRow;
  N: Integer;
begin
  SetLength(ATab.SelectedURIs, 0);
  for R in ARows do
  begin
    if R.IsParent or (R.URI = '') then
      Continue;
    N := Length(ATab.SelectedURIs);
    SetLength(ATab.SelectedURIs, N + 1);
    ATab.SelectedURIs[N] := R.URI;
  end;
end;

function PanelRowMaskName(const ARow: TPanelRow): string;
begin
  Result := ARow.Text;
  while (Result <> '') and ((Result[Length(Result)] = '/') or
    (Result[Length(Result)] = '\')) do
    Delete(Result, Length(Result), 1);
end;

function FileNameStem(const AName: string): string;
var
  Ext: string;
begin
  Ext := ExtractFileExt(AName);
  if (Ext <> '') and not SameText(Ext, AName) then
    Result := Copy(AName, 1, Length(AName) - Length(Ext))
  else
    Result := AName;
end;

function EllipsizeKeepingExt(const AText: string; AMaxLen: Integer): string;
var
  Ext, Stem: string;
  Budget, PrefixLen, SuffixLen: Integer;
begin
  Result := AText;
  if AMaxLen < 1 then
    Exit('');
  if Length(Result) <= AMaxLen then
    Exit;
  if AMaxLen < 4 then
    Exit(Copy(Result, 1, AMaxLen));

  Ext := ExtractFileExt(Result);
  // Dotfiles (".gitignore") and whole-string "extensions" have no stem to keep.
  if (Ext = '') or SameText(Ext, Result) or (Length(Ext) + 4 > AMaxLen) then
  begin
    Budget := AMaxLen - 3;
    SuffixLen := Min(3, Budget div 4);
    PrefixLen := Budget - SuffixLen;
    Result := Copy(Result, 1, PrefixLen) + '...' +
      Copy(Result, Length(Result) - SuffixLen + 1, SuffixLen);
    Exit;
  end;

  Stem := Copy(Result, 1, Length(Result) - Length(Ext));
  Budget := AMaxLen - Length(Ext) - 3;
  if Budget < 1 then
  begin
    // Extension alone with ellipsis — prefer showing the extension.
    Result := Copy('...' + Ext, 1, AMaxLen);
    Exit;
  end;
  // Prefer the start of the stem; keep a short end so the join before the
  // extension stays recognizable (Total Commander / Explorer style).
  SuffixLen := Min(3, Budget div 4);
  if SuffixLen > Length(Stem) then
    SuffixLen := 0;
  PrefixLen := Budget - SuffixLen;
  if PrefixLen + SuffixLen > Length(Stem) then
  begin
    PrefixLen := Length(Stem) - SuffixLen;
    if PrefixLen < 0 then
    begin
      PrefixLen := 0;
      SuffixLen := Min(SuffixLen, Length(Stem));
    end;
  end;
  Result := Copy(Stem, 1, PrefixLen) + '...' +
    Copy(Stem, Length(Stem) - SuffixLen + 1, SuffixLen) + Ext;
end;

function PanelRowIsDirectory(const ARow: TPanelRow): Boolean;
begin
  if ARow.IsParent then
    Exit(False);
  if ARow.IsDirectory then
    Exit(True);
  if SameText(Trim(ARow.SizeText), '<DIR>') then
    Exit(True);
  Result := (ARow.Text <> '') and
    ((ARow.Text[Length(ARow.Text)] = '/') or (ARow.Text[Length(ARow.Text)] = '\'));
end;

function TabRowSelectable(const ARow: TPanelRow; AIncludeFolders: Boolean): Boolean;
begin
  Result := (not ARow.IsParent) and (ARow.URI <> '') and
    (AIncludeFolders or not PanelRowIsDirectory(ARow));
end;

procedure TabSelectByMask(var ATab: TTab; const ARows: TPanelRows;
  const AMask: string; AIncludeFolders: Boolean);
var
  R: TPanelRow;
  Masks: TArray<string>;
begin
  Masks := SplitMasks(AMask);
  for R in ARows do
  begin
    // FAR default: Gray+/Gray− do not select folders (Select folders = off).
    if not TabRowSelectable(R, AIncludeFolders) then
      Continue;
    if NameMatchesAnyMask(PanelRowMaskName(R), Masks) and
       not TabIsSelected(ATab, R.URI) then
      TabToggleSelected(ATab, R.URI);
  end;
end;

procedure TabUnselectByMask(var ATab: TTab; const ARows: TPanelRows;
  const AMask: string; AIncludeFolders: Boolean);
var
  R: TPanelRow;
  Masks: TArray<string>;
begin
  Masks := SplitMasks(AMask);
  for R in ARows do
  begin
    if not TabRowSelectable(R, AIncludeFolders) then
      Continue;
    if NameMatchesAnyMask(PanelRowMaskName(R), Masks) and
       TabIsSelected(ATab, R.URI) then
      TabToggleSelected(ATab, R.URI);
  end;
end;

procedure TabSelectByNameStem(var ATab: TTab; const ARows: TPanelRows;
  const AStem: string; AUnselect: Boolean; AIncludeFolders: Boolean);
var
  R: TPanelRow;
  Stem: string;
begin
  Stem := Trim(AStem);
  if Stem = '' then
    Exit;
  for R in ARows do
  begin
    if not TabRowSelectable(R, AIncludeFolders) then
      Continue;
    if not SameText(FileNameStem(PanelRowMaskName(R)), Stem) then
      Continue;
    if AUnselect then
    begin
      if TabIsSelected(ATab, R.URI) then
        TabToggleSelected(ATab, R.URI);
    end
    else if not TabIsSelected(ATab, R.URI) then
      TabToggleSelected(ATab, R.URI);
  end;
end;

function TabHasSelectedDirectories(const ATab: TTab;
  const ARows: TPanelRows): Boolean;
begin
  Result := Length(CollectSelectedDirectoryUris(ATab, ARows)) > 0;
end;

function CollectSelectedDirectoryUris(const ATab: TTab;
  const ARows: TPanelRows): TArray<string>;
var
  S, Path: string;
  R: TPanelRow;
  Found: Boolean;
  N: Integer;
begin
  SetLength(Result, 0);
  for S in ATab.SelectedURIs do
  begin
    if S = '' then
      Continue;
    Found := False;
    for R in ARows do
    begin
      if R.IsParent or (R.URI = '') then
        Continue;
      if not SameVfsUri(R.URI, S) then
        Continue;
      Found := True;
      if PanelRowIsDirectory(R) then
      begin
        N := Length(Result);
        SetLength(Result, N + 1);
        Result[N] := R.URI;
      end;
      Break;
    end;
    if not Found then
    begin
      Path := FileUriToPath(S);
      if (Path <> '') and LocalPathIsDirectory(Path) then
      begin
        N := Length(Result);
        SetLength(Result, N + 1);
        Result[N] := S;
      end;
    end;
  end;
end;

procedure TabInvertSelection(var ATab: TTab; const ARows: TPanelRows);
var
  R: TPanelRow;
begin
  for R in ARows do
  begin
    if R.IsParent or (R.URI = '') then
      Continue;
    TabToggleSelected(ATab, R.URI);
  end;
end;

function ShiftNavInvertRange(AFrom, ATo, ADelta: Integer; AExcludeLanding: Boolean;
  out ALo, AHi: Integer): Boolean;
begin
  ALo := AFrom;
  AHi := AFrom;
  // Unit step (Up/Down): invert leaving row only.
  if Abs(ADelta) <= 1 then
    Exit(True);
  if AExcludeLanding then
  begin
    // Brief Left/Right: [From..To) — include the row before landing.
    if ATo > AFrom then
    begin
      ALo := AFrom;
      AHi := ATo - 1;
    end
    else if ATo < AFrom then
    begin
      ALo := ATo + 1;
      AHi := AFrom;
    end;
  end
  else
  begin
    // Home/End/Pg*: inclusive span.
    if AFrom <= ATo then
    begin
      ALo := AFrom;
      AHi := ATo;
    end
    else
    begin
      ALo := ATo;
      AHi := AFrom;
    end;
  end;
  Result := ALo <= AHi;
end;

end.
