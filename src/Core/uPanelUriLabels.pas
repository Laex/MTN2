unit uPanelUriLabels;

{ Pure URI-building and display-label helpers used by the dual-panel host's
  folder history / folder hotlist dialogs and initial workspace setup.
  Extracted from uDualPanelWindow.pas (health/refactor pass) — none of these
  touch TDualPanelWindow state, so they live here as free functions. }

interface

uses
  System.SysUtils, System.IOUtils,
  uVfsTypes, uFolderHotlist, uPanelColumns;

function HomeUri: string;
function DocumentsUri: string;
function ProjectsUri: string;

function PanelItemFullPath(const AURI, APanelURI: string; AIsParent: Boolean): string;

function FolderHistoryDisplayLabel(const AURI: string): string;
/// <summary>Fit a history path into AMaxLen, keeping the drive (or UNC
/// prefix) and the end of the path. Middle is replaced with '...'.
/// Non-path labels keep a short head and the tail.</summary>
function FitFolderHistoryLabel(const ALabel: string; AMaxLen: Integer): string;

function FolderHotlistDisplayLabel(const AEntry: TFolderHotlistEntry): string;

implementation

function HomeUri: string;
begin
  Result := PathToFileUri(TPath.GetHomePath);
end;

function DocumentsUri: string;
begin
  Result := PathToFileUri(TPath.GetDocumentsPath);
end;

function ProjectsUri: string;
begin
  if TDirectory.Exists('D:\Work') then
    Result := PathToFileUri('D:\Work')
  else
    Result := HomeUri;
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
  { Column widths for the "Directory hotlist" list — it has no native
    multi-column support (dckList is one string per row), so rows and the
    header (dialogs/folderhotlist.json) are hand-aligned to these same
    widths via uPanelColumns.PadRight/PadLeft. Name + 1 + Path + 1 + Hotkey
    is 1 short of the list's usable text width — its declared width (58)
    minus 1 for TDialogHost's own scrollbar column (uDialogHost.pas
    reserves R.Width - 1), i.e. 57 usable — so TDialogHost's own
    right-padding (it pads every row out to that full width) leaves one
    blank column between the Hotkey text and the scrollbar. }
  cHotlistNameW = 20;
  cHotlistPathW = 28;
  cHotlistHotkeyW = 6;

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
  Result := PadRight(AEntry.Name, cHotlistNameW) + ' ' +
    PadRight(Path, cHotlistPathW) + ' ' +
    PadLeft(FolderHotlistKeyLabel(AEntry.HotKey), cHotlistHotkeyW);
end;

end.
