unit uPanelUriLabels;

{ Pure URI-building and display-label helpers used by the dual-panel host's
  folder history / folder hotlist dialogs and initial workspace setup.
  Extracted from uDualPanelWindow.pas (health/refactor pass) - none of these
  touch TDualPanelWindow state, so they live here as free functions. }

interface

uses
  System.SysUtils, System.IOUtils,
  uVfsTypes, uDualPanelTypes, uFolderHotlist, uPanelColumns, uPlatformFolders;

function HomeUri: string;
function DocumentsUri: string;
function ProjectsUri: string;

function PanelItemFullPath(const AURI, APanelURI: string; AIsParent: Boolean): string;
/// <summary>The folder whose map Quick View shows for the cursor row: the folder
/// itself, or the panel's own folder when the cursor is on "..". Empty when the
/// row is not a folder or there is no row.</summary>
function QuickDirectoryTarget(AHasRow: Boolean; const ARow: TPanelRow;
  const APanelURI: string): string;
/// <summary>Paths or bare names for the clipboard: selected rows (parent
/// skipped), or the cursor row when nothing is selected. ANameOnly keeps only
/// the last path segment.</summary>
function CollectClipboardItemTexts(const ATab: TTab; const ARows: TPanelRows;
  ANameOnly: Boolean): TArray<string>;

function FolderHistoryDisplayLabel(const AURI: string): string;
/// <summary>Fit a history path into AMaxLen, keeping the drive (or UNC
/// prefix) and the end of the path. Middle is replaced with '...'.
/// Non-path labels keep a short head and the tail.</summary>
function FitFolderHistoryLabel(const ALabel: string; AMaxLen: Integer): string;

type
  /// <summary>A stretch of a hotlist row drawn in the accent color: Len cells
  /// from column Col of the row text.</summary>
  THotlistAccent = record
    Col, Len: Integer;
  end;

/// <summary>List row of an entry: the key its name declares, fold marker blank,
/// group blank, then name, path and hotkey.</summary>
function FolderHotlistDisplayLabel(const AEntry: TFolderHotlistEntry): string;
/// <summary>The cells of an entry row to accent: its key and its Ctrl+digit.</summary>
function FolderHotlistEntryAccents(const AEntry: TFolderHotlistEntry): TArray<THotlistAccent>;
/// <summary>The cells of a group header row to accent: its key.</summary>
function FolderHotlistGroupAccents(const AGroup: string): TArray<THotlistAccent>;
/// <summary>List row of a group header: the key its name declares, "[-]"
/// (open) or "[+]" (folded) and the group name.</summary>
function FolderHotlistGroupLabel(const AGroup: string; AFolded: Boolean): string;

implementation

function HomeUri: string;
begin
  Result := PathToFileUri(TPath.GetHomePath);
end;

function DocumentsUri: string;
begin
  Result := PathToFileUri(PlatformDocumentsDir);
end;

function ProjectsUri: string;
begin
  Result := PathToFileUri(PlatformProjectsDir);
end;

function CollectClipboardItemTexts(const ATab: TTab; const ARows: TPanelRows;
  ANameOnly: Boolean): TArray<string>;
var
  R: TPanelRow;
  Keys: TArray<string>;
  Text: string;
  N: Integer;

  function ItemText(const ARow: TPanelRow): string;
  begin
    Result := PanelItemFullPath(ARow.URI, ATab.CurrentURI, ARow.IsParent);
    if not ANameOnly or (Result = '') then
      Exit;
    // Archive members ("a.zip!\dir\f") split the same way; a drive root
    // has no name and yields ''.
    Result := PathLastSegment(Result);
  end;

begin
  Result := nil;
  if Length(ATab.SelectedURIs) > 0 then
  begin
    Keys := TabSelectionKeys(ATab);
    // One allocation for the selection. Growing the list per row stalls
    // copying many names to the clipboard.
    SetLength(Result, Length(ARows));
    N := 0;
    for R in ARows do
      if (not R.IsParent) and (R.URI <> '') and SelectionKeysHas(Keys, R.URI) then
      begin
        Text := ItemText(R);
        if Text <> '' then
        begin
          Result[N] := Text;
          Inc(N);
        end;
      end;
    SetLength(Result, N);
  end
  else if (ATab.CursorIndex >= 0) and (ATab.CursorIndex <= High(ARows)) then
  begin
    Text := ItemText(ARows[ATab.CursorIndex]);
    if Text <> '' then
      Result := [Text];
  end;
end;

function QuickDirectoryTarget(AHasRow: Boolean; const ARow: TPanelRow;
  const APanelURI: string): string;
begin
  Result := '';
  if not AHasRow then
    Exit;
  if ARow.IsParent then
    Result := APanelURI
  else if ARow.IsDirectory then
    Result := ARow.URI;
end;

function PanelItemFullPath(const AURI, APanelURI: string; AIsParent: Boolean): string;
var
  Base: string;
  Segs: TArray<string>;
  I: Integer;
  Inner: string;
begin
  Result := '';
  if AIsParent then
  begin
    if HasArchiveChain(APanelURI) then
      Result := ArchiveBasePath(APanelURI)
    else if not IsFindUri(APanelURI) then
      Result := FileUriToPath(ResolveFileUri(APanelURI));
    Exit;
  end;
  if AURI = '' then
    Exit;
  if HasArchiveChain(AURI) and SplitArchiveUri(AURI, Base, Segs) then
  begin
    Result := FileUriToPath(Base);
    for I := 0 to High(Segs) do
      if Segs[I] <> '' then
      begin
        Inner := StringReplace(Segs[I], '/', PathDelim, [rfReplaceAll]);
        Result := Result + '!' + PathDelim + Inner;
      end;
    Exit;
  end;
  if IsFindUri(AURI) then
    Exit;
  Result := FileUriToPath(ResolveFileUri(AURI));
end;

function FolderHistoryDisplayLabel(const AURI: string): string;
var
  Path: string;
begin
  Path := FileUriToPath(AURI);
  if Path <> '' then
    Exit(Path);
  Result := VfsUriTitle(AURI);
  if Result = '' then
    Result := AURI;
end;

function FitFolderHistoryLabel(const ALabel: string; AMaxLen: Integer): string;
var
  Head, TailLen: Integer;
begin
  if AMaxLen < 1 then
    Exit('');
  if Length(ALabel) <= AMaxLen then
    Exit(ALabel);
  if AMaxLen < 4 then
    Exit(Copy(ALabel, 1, AMaxLen));

  // Windows drive: "C:\...\tail"
  if (Length(ALabel) >= 3) and (ALabel[2] = ':') then
  begin
    Head := 2;
    if AMaxLen <= Head + 3 then
      Exit(Copy(ALabel, 1, Head) + Copy('...', 1, AMaxLen - Head));
    TailLen := AMaxLen - Head - 4; // after 'X:\...'
    if TailLen < 1 then
      Exit(Copy(ALabel, 1, AMaxLen));
    Exit(Copy(ALabel, 1, Head) + '\...' +
      Copy(ALabel, Length(ALabel) - TailLen + 1, TailLen));
  end;

  // UNC: "\\...\tail"
  if (Length(ALabel) >= 2) and (ALabel[1] = '\') and (ALabel[2] = '\') then
  begin
    TailLen := AMaxLen - 5;
    if TailLen < 1 then
      Exit('\\' + Copy('...', 1, AMaxLen - 2));
    Exit('\\...' + Copy(ALabel, Length(ALabel) - TailLen + 1, TailLen));
  end;

  Head := AMaxLen - 4;
  if Head > 4 then
    Head := 4;
  if Head < 1 then
    Head := 1;
  TailLen := AMaxLen - 3 - Head;
  if TailLen < 1 then
    Exit(Copy(ALabel, 1, AMaxLen));
  Result := Copy(ALabel, 1, Head) + '...' +
    Copy(ALabel, Length(ALabel) - TailLen + 1, TailLen);
end;

const
  { Column widths for the "Directory hotlist" list - it has no native
    multi-column support (dckList is one string per row), so rows and the
    header (dialogs/folderhotlist.json) are hand-aligned to these same
    widths via uPanelColumns.PadRight/PadLeft. The columns plus their
    separators are 1 short of the list's usable text width (its declared
    width minus 1 for TDialogHost's own scrollbar column), so the row
    padding TDialogHost adds leaves one blank column before the scrollbar. }
  cHotlistMarkW = 3;
  cHotlistKeyW = 1;
  cHotlistGroupW = 14;
  cHotlistNameW = 20;
  cHotlistPathW = 26;
  cHotlistHotkeyW = 6;

function Accent(ACol, ALen: Integer): THotlistAccent;
begin
  Result.Col := ACol;
  Result.Len := ALen;
end;

function KeyText(AKey: Char): string;
begin
  if AKey = #0 then
    Result := ''
  else
    Result := AKey;
end;

function FolderHotlistDisplayLabel(const AEntry: TFolderHotlistEntry): string;
var
  Path: string;
begin
  Path := FileUriToPath(AEntry.URI);
  if Path = '' then
  begin
    Path := VfsUriTitle(AEntry.URI);
    if Path = '' then
      Path := AEntry.URI;
  end;
  Result := PadRight(KeyText(HotlistKeyOf(AEntry.Name)), cHotlistKeyW) + ' ' +
    PadRight('', cHotlistMarkW) + ' ' +
    PadRight('', cHotlistGroupW) + ' ' +
    PadRight(HotlistStripKey(AEntry.Name), cHotlistNameW) + ' ' +
    PadRight(Path, cHotlistPathW) + ' ' +
    PadLeft(FolderHotlistKeyLabel(AEntry.HotKey), cHotlistHotkeyW);
end;

function FolderHotlistGroupLabel(const AGroup: string; AFolded: Boolean): string;
var
  Mark: string;
begin
  if AFolded then
    Mark := '[+]'
  else
    Mark := '[-]';
  Result := PadRight(KeyText(HotlistKeyOf(AGroup)), cHotlistKeyW) + ' ' +
    PadRight(Mark, cHotlistMarkW) + ' ' +
    HotlistStripKey(AGroup);
end;

function FolderHotlistGroupAccents(const AGroup: string): TArray<THotlistAccent>;
begin
  SetLength(Result, 0);
  if HotlistKeyOf(AGroup) <> #0 then
    Result := [Accent(0, cHotlistKeyW)];
end;

function FolderHotlistEntryAccents(const AEntry: TFolderHotlistEntry): TArray<THotlistAccent>;
var
  Label_: string;
  HotCol: Integer;
begin
  SetLength(Result, 0);
  if HotlistKeyOf(AEntry.Name) <> #0 then
    Result := Result + [Accent(0, cHotlistKeyW)];
  Label_ := FolderHotlistKeyLabel(AEntry.HotKey);
  if Label_ <> '' then
  begin
    // The hotkey column is the last one, right-aligned.
    HotCol := cHotlistKeyW + 1 + cHotlistMarkW + 1 + cHotlistGroupW + 1 +
      cHotlistNameW + 1 + cHotlistPathW + 1 + cHotlistHotkeyW - Length(Label_);
    Result := Result + [Accent(HotCol, Length(Label_))];
  end;
end;

end.
