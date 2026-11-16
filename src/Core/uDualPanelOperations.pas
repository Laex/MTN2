unit uDualPanelOperations;

{ Operations Controller: Isolates MkDir, Rename, and path validation logic
  from uDualPanelWindow.pas. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uVfsTypes, uDualPanelTypes, uAssociations, uVfsRegistry, uZipVfs, uPluginHost,
  uWorkspaceVfs;

type
  TDualPanelOperationsController = class
  public
    class function ValidateFolderSegments(const AName: string; out ACleanName, ASelectName, AErrorMsg: string): Boolean;
    class function ValidateRenameName(const AName: string; out AErrorMsg: string): Boolean;
  end;

  TActivateCurrentKind = (ackNone, ackFindGoto, ackHistoryBack, ackNavigate,
    ackZipNavigate, ackView, ackEdit, ackShell, ackCommand);
  TDirectoryExistsFn = reference to function(const APath: string): Boolean;
  /// <summary>Pending cursor name / enter-view memory when NavigateSideTo
  /// leaves or enters a folder.</summary>
  TNavigatePendingSelectKind = (npskNone, npskSelect, npskRememberEnterView);
  TNavigatePendingSelect = record
    Kind: TNavigatePendingSelectKind;
    Name: string;
    ApplyViewPos: Boolean;
    ViewPos: Integer;
    RememberDriveDir: Boolean;
    EnterViewKey: string;
    EnterViewValue: Integer;
  end;

function ClassifyActivateCurrent(AFindHit, ALeaveSynthetic, AIsDirOrParent,
  AIsZip: Boolean; AAssoc: TAssocAction): TActivateCurrentKind;
/// <summary>Archive, find, SFTP or generic plugin on either URI: local-disk
/// parent matching and junction back markers do not apply.</summary>
function NavigationEitherSideIsVirtualView(const AFromUri, AToUri: string): Boolean;
/// <summary>What to select after NavigateSideTo changes the folder, and whether
/// to remember the enter view position. AWorkspaceLinkName is
/// WorkspaceLinkNameForTarget(AFromUri); AFindSessionParent is
/// FindSessionParentFileUri(AFromUri) when AFromUri is find://, else ''.</summary>
function DecideNavigatePendingSelect(const AFromUri, AToCanon: string;
  const AWorkspaceBackUri, AWorkspaceBackTarget, AJunctionBackName,
  AWorkspaceLinkName, AFindSessionParent: string; AEitherSideVirtual: Boolean;
  AHasStoredViewPos: Boolean; AStoredViewPos: Integer;
  AFromCursorIndex, AFromScrollOffset: Integer): TNavigatePendingSelect;
/// <summary>Entering ws:/// from a plain folder remembers that folder as
/// WorkspaceOriginUri, unless `..` already points back into Workspace.</summary>
function ShouldRememberWorkspaceOrigin(const AToCanon, AFromUri,
  AWorkspaceBackUri: string): Boolean;
/// <summary>Updates WorkspaceBackUri / BackTarget / JunctionBackName for the
/// navigate from AFromUri to AToCanon. ARawNavigateUri is the URI before
/// ResolveVfsUri (junction detection compares the raw link path to Canon).</summary>
procedure ApplyNavigateTabBackMarkers(var ATab: TTab;
  const ARawNavigateUri, AToCanon, AFromUri: string;
  AEitherSideVirtual: Boolean);
/// <summary>Truncate forward history and append ACanon when AAddToHistory,
/// skipping a duplicate of the current tip.</summary>
procedure AppendTabHistoryNavigate(var ATab: TTab; const ACanon: string;
  AAddToHistory: Boolean);
/// <summary>Why AName cannot be the name of a file or folder on this system
/// (the rules of Windows or of Linux, whichever runs); empty when it can.</summary>
function FileNameProblem(const AName: string): string;
/// <summary>True when a local file:/// folder that listed fine before is now
/// vecNotFound: LeaveRemovedFolder may walk up to an existing parent. A path
/// that never listed keeps its error line.</summary>
function ShouldLeaveRemovedFolder(AError: TVfsErrorCode; const ACur,
  AListedOkUri: string): Boolean;
/// <summary>Nearest ancestor file:/// URI whose local path exists, walking
/// ParentFileUri from ACur (ACur itself is not tried). Empty when none does.
/// ADirectoryExists is the path probe.</summary>
function FindExistingParentFileUri(const ACur: string;
  const ADirectoryExists: TDirectoryExistsFn): string;
/// <summary>A local file named like a ZIP whose content is another archive
/// format (a RAR saved as .zip): the 7z plugin reads it by content, the
/// built-in ZIP cannot.</summary>
function ZipNamedFileIsOtherArchive(const AFileUri: string): Boolean;
/// <summary>An encrypted file at or under one of AURIs, entries of the local
/// ZIP the panel at ATabUri shows. The built-in ZIP layer cannot decrypt, so
/// the file is addressed through the 7z backend (AProbeUri).</summary>
function ZipEncryptedProbe(const ATabUri: string; const AURIs: TArray<string>;
  out AArchivePath, AProbeUri: string): Boolean;
/// <summary>URI to open in the viewer/editor: an encrypted ZIP entry goes
/// through the 7z backend when the plugin can resolve it.</summary>
function ReadableArchiveRowUri(const ARow: TPanelRow): string;

implementation

function FileNameProblem(const AName: string): string;
const
  cReserved: array[0..21] of string = ('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2',
    'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2',
    'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9');
var
  I, Dot: Integer;
  Stem, Reserved: string;
begin
  Result := '';
  if AName = '' then
    Exit('the name is empty');
  if (AName = '.') or (AName = '..') then
    Exit('the name is "." or ".."');
  if Length(AName) > 255 then
    Exit('the name is longer than 255 characters');
  for I := 1 to Length(AName) do
    if (AName[I] < ' ') or (AName[I] = '/') then
      Exit('the name has a character that is not allowed');
{$IFDEF MSWINDOWS}
  for I := 1 to Length(AName) do
    if CharInSet(AName[I], ['\', ':', '*', '?', '"', '<', '>', '|']) then
      Exit('the name has a character that is not allowed: ' + AName[I]);
  if CharInSet(AName[Length(AName)], [' ', '.']) then
    Exit('the name must not end with a space or a dot');
  Dot := Pos('.', AName);
  if Dot > 0 then
    Stem := Copy(AName, 1, Dot - 1)
  else
    Stem := AName;
  for Reserved in cReserved do
    if SameText(TrimRight(Stem), Reserved) then
      Exit('"' + Reserved + '" is a reserved name');
{$ENDIF}
end;

function ContainsInvalidFolderNameChar(const ASeg: string): Boolean;
begin
  Result := (Pos('<', ASeg) > 0) or (Pos('>', ASeg) > 0) or (Pos(':', ASeg) > 0) or
    (Pos('"', ASeg) > 0) or (Pos('|', ASeg) > 0) or (Pos('?', ASeg) > 0) or
    (Pos('*', ASeg) > 0);
end;

class function TDualPanelOperationsController.ValidateFolderSegments(const AName: string;
  out ACleanName, ASelectName, AErrorMsg: string): Boolean;
var
  Name, Norm, Seg: string;
  Parts: TArray<string>;
  I: Integer;
begin
  ACleanName := '';
  ASelectName := '';
  AErrorMsg := '';
  Name := Trim(AName);
  while (Name <> '') and ((Name[1] = '/') or (Name[1] = '\')) do
    Delete(Name, 1, 1);
  if Name = '' then
  begin
    AErrorMsg := 'Name is empty';
    Exit(False);
  end;
  Norm := StringReplace(Name, '/', PathDelim, [rfReplaceAll]);
  if TPath.IsPathRooted(Norm) then
  begin
    AErrorMsg := 'Name must be relative to the current folder';
    Exit(False);
  end;
  Parts := Norm.Split([PathDelim], TStringSplitOptions.ExcludeEmpty);
  if Length(Parts) = 0 then
  begin
    AErrorMsg := 'Name is empty';
    Exit(False);
  end;
  for I := 0 to High(Parts) do
  begin
    Seg := Parts[I];
    if (Seg = '.') or (Seg = '..') then
    begin
      AErrorMsg := 'Invalid folder name';
      Exit(False);
    end;
    if ContainsInvalidFolderNameChar(Seg) then
    begin
      AErrorMsg := 'Name contains invalid characters';
      Exit(False);
    end;
  end;
  ACleanName := string.Join(PathDelim, Parts);
  ASelectName := Parts[0];
  Result := True;
end;

class function TDualPanelOperationsController.ValidateRenameName(const AName: string;
  out AErrorMsg: string): Boolean;
var
  Name, Problem: string;
begin
  AErrorMsg := '';
  Name := Trim(AName);
  if Name = '' then
  begin
    AErrorMsg := 'Name is empty';
    Exit(False);
  end;
  if (Pos('\', Name) > 0) or (Pos('/', Name) > 0) or (Pos(':', Name) > 0) then
  begin
    AErrorMsg := 'Name must not contain path separators';
    Exit(False);
  end;
  Problem := FileNameProblem(Name);
  if Problem <> '' then
  begin
    AErrorMsg := 'Invalid name: ' + Problem;
    Exit(False);
  end;
  Result := True;
end;

function ClassifyActivateCurrent(AFindHit, ALeaveSynthetic, AIsDirOrParent,
  AIsZip: Boolean; AAssoc: TAssocAction): TActivateCurrentKind;
begin
  if AFindHit then
    Exit(ackFindGoto);
  if ALeaveSynthetic then
    Exit(ackHistoryBack);
  if AIsDirOrParent then
    Exit(ackNavigate);
  if AIsZip then
    Exit(ackZipNavigate);
  case AAssoc of
    aaView:
      Result := ackView;
    aaEdit:
      Result := ackEdit;
    aaShell:
      Result := ackShell;
    aaCommand:
      Result := ackCommand;
    aaNavigate:
      Result := ackNavigate;
  else
    Result := ackView;
  end;
end;

function NavigationEitherSideIsVirtualView(const AFromUri, AToUri: string): Boolean;
begin
  Result := HasArchiveChain(AFromUri) or HasArchiveChain(AToUri) or
    IsFindUri(AFromUri) or IsFindUri(AToUri) or
    IsSftpUri(AFromUri) or IsSftpUri(AToUri) or
    IsGenericVfsUri(AFromUri) or IsGenericVfsUri(AToUri);
end;

function DecideNavigatePendingSelect(const AFromUri, AToCanon: string;
  const AWorkspaceBackUri, AWorkspaceBackTarget, AJunctionBackName,
  AWorkspaceLinkName, AFindSessionParent: string; AEitherSideVirtual: Boolean;
  AHasStoredViewPos: Boolean; AStoredViewPos: Integer;
  AFromCursorIndex, AFromScrollOffset: Integer): TNavigatePendingSelect;
var
  OldPath, NewPath, ParentPath: string;
begin
  Result.Kind := npskNone;
  Result.Name := '';
  Result.ApplyViewPos := False;
  Result.ViewPos := -1;
  Result.RememberDriveDir := False;
  Result.EnterViewKey := '';
  Result.EnterViewValue := 0;

  // Leaving a folder via "..": place cursor on that folder in the parent list.
  // Only THIS tab's workspace-enter marker, not a global dir-link lookup -
  // the other panel at the same disk path must `..` to the disk parent.
  if (AWorkspaceBackUri <> '') and
     SameVfsUri(AFromUri, AWorkspaceBackTarget) and
     SameVfsUri(AToCanon, AWorkspaceBackUri) then
  begin
    Result.Kind := npskSelect;
    if AJunctionBackName <> '' then
      Result.Name := AJunctionBackName
    else
      Result.Name := AWorkspaceLinkName;
    Exit;
  end;

  if AEitherSideVirtual then
  begin
    if SameVfsUri(AToCanon, ParentVfsUri(AFromUri)) then
    begin
      // find:// parent is session root file URI - match via FindSessionParentFileUri
      if IsFindUri(AFromUri) then
      begin
        if SameVfsUri(AToCanon, AFindSessionParent) then
        begin
          Result.Kind := npskSelect;
          Result.Name := '';
        end;
      end
      else
      begin
        Result.Kind := npskSelect;
        Result.Name := VfsUriTitle(AFromUri);
      end;
    end
    else if IsFindUri(AFromUri) and
            SameVfsUri(AToCanon, AFindSessionParent) then
    begin
      Result.Kind := npskSelect;
      Result.Name := '';
    end;
    Exit;
  end;

  OldPath := FileUriToPath(AFromUri);
  NewPath := FileUriToPath(AToCanon);
  Result.RememberDriveDir := True;
  ParentPath := FileUriToPath(ResolveFileUri(ParentFileUri(AFromUri)));
  if (OldPath <> '') and SameLocalPath(NewPath, ParentPath) then
  begin
    Result.Kind := npskSelect;
    Result.Name := FileUriTitle(AFromUri);
    Result.ApplyViewPos := True;
    if AHasStoredViewPos then
      Result.ViewPos := AStoredViewPos
    else
      Result.ViewPos := -1;
  end
  else if (OldPath <> '') and (NewPath <> '') and
          SameLocalPath(OldPath,
            FileUriToPath(ResolveFileUri(ParentFileUri(AToCanon)))) then
  begin
    Result.Kind := npskRememberEnterView;
    Result.EnterViewKey := LowerCase(AFromUri);
    Result.EnterViewValue := AFromCursorIndex - AFromScrollOffset;
  end;
end;

function ShouldRememberWorkspaceOrigin(const AToCanon, AFromUri,
  AWorkspaceBackUri: string): Boolean;
begin
  Result := IsWorkspaceUri(AToCanon) and not IsWorkspaceUri(AFromUri) and
    (AFromUri <> '') and not IsFindUri(AFromUri) and
    not IsWorkspaceUri(AWorkspaceBackUri);
end;

procedure ApplyNavigateTabBackMarkers(var ATab: TTab;
  const ARawNavigateUri, AToCanon, AFromUri: string;
  AEitherSideVirtual: Boolean);
var
  OldBackUri, LinkUri, LinkParent: string;
begin
  OldBackUri := ATab.WorkspaceBackUri;
  UpdateWorkspaceBackMarker(ATab.WorkspaceBackUri, ATab.WorkspaceBackTarget,
    AFromUri, AToCanon);
  if ATab.WorkspaceBackUri <> OldBackUri then
    ATab.JunctionBackName := '';
  // The first folder of a remote host or of a plugin scheme (wherever in its
  // tree it is entered) gets a `..` row that leads back to the folder the panel
  // came from.
  if ((IsSftpUri(AToCanon) and IsVfsUriNavigationRoot(AToCanon)) or
      IsGenericVfsUri(AToCanon)) and
     not IsSftpUri(AFromUri) and not IsGenericVfsUri(AFromUri) and
     (AFromUri <> '') and not IsFindUri(AFromUri) and
     not IsWorkspaceUri(AFromUri) then
  begin
    ATab.WorkspaceBackUri := AFromUri;
    ATab.WorkspaceBackTarget := AToCanon;
    ATab.JunctionBackName := '';
  end;
  // Entering a junction/symlink shows its resolved target; `..` there must
  // lead back to the folder that holds the link, not to the target's parent.
  if ((ATab.WorkspaceBackUri = '') or (ATab.JunctionBackName <> '')) and
     not AEitherSideVirtual and not IsWorkspaceUri(ARawNavigateUri) and
     not IsWorkspaceUri(AFromUri) then
  begin
    LinkUri := PathToFileUri(FileUriToPath(ARawNavigateUri));
    LinkParent := ParentFileUri(LinkUri);
    if (LinkParent <> '') and not SameVfsUri(LinkUri, AToCanon) and
       not SameVfsUri(LinkParent, ParentFileUri(AToCanon)) then
    begin
      ATab.WorkspaceBackUri := LinkParent;
      ATab.WorkspaceBackTarget := AToCanon;
      ATab.JunctionBackName := FileUriTitle(LinkUri);
    end;
  end;
  // The Temporary panel has no parent of its own; `..` there leads back to the
  // place the panel was opened from.
  if IsTmpPanelUri(AToCanon) and not IsTmpPanelUri(AFromUri) and
     (AFromUri <> '') then
  begin
    ATab.WorkspaceBackUri := AFromUri;
    ATab.WorkspaceBackTarget := AToCanon;
    ATab.JunctionBackName := '';
  end;
end;

procedure AppendTabHistoryNavigate(var ATab: TTab; const ACanon: string;
  AAddToHistory: Boolean);
begin
  if not AAddToHistory then
    Exit;
  if (ATab.HistoryIndex >= 0) and (ATab.HistoryIndex < High(ATab.History)) then
    SetLength(ATab.History, ATab.HistoryIndex + 1);
  if (Length(ATab.History) = 0) or
     not SameVfsUri(ATab.History[High(ATab.History)], ACanon) then
  begin
    SetLength(ATab.History, Length(ATab.History) + 1);
    ATab.History[High(ATab.History)] := ACanon;
  end;
  ATab.HistoryIndex := High(ATab.History);
end;

function ShouldLeaveRemovedFolder(AError: TVfsErrorCode; const ACur,
  AListedOkUri: string): Boolean;
begin
  Result := (AError = vecNotFound) and (ACur <> '') and
    SameVfsUri(ACur, AListedOkUri) and
    SameText(Copy(ACur, 1, 8), 'file:///') and
    not HasArchiveChain(ACur) and
    not IsFindUri(ACur) and
    not IsWorkspaceUri(ACur);
end;

function FindExistingParentFileUri(const ACur: string;
  const ADirectoryExists: TDirectoryExistsFn): string;
var
  Probe, Last: string;
begin
  Result := '';
  if not Assigned(ADirectoryExists) then
    Exit;
  Probe := ParentFileUri(ACur);
  while (Probe <> '') and not ADirectoryExists(FileUriToPath(Probe)) do
  begin
    Last := Probe;
    Probe := ParentFileUri(Probe);
    if SameVfsUri(Probe, Last) then
      Probe := '';
  end;
  Result := Probe;
end;

function ZipNamedFileIsOtherArchive(const AFileUri: string): Boolean;
var
  Backend: IVirtualFileSystem;
  Path: string;
begin
  Result := False;
  if not AFileUri.StartsWith('file:', True) or HasArchiveChain(AFileUri) then
    Exit;
  Path := FileUriToPath(AFileUri);
  if not TFile.Exists(Path) or FileHasZipSignature(Path) then
    Exit;
  Result := GlobalVfsRegistry.TryResolve(PathToSevenZipRootUri(Path), Backend);
end;

function ZipEncryptedProbe(const ATabUri: string; const AURIs: TArray<string>;
  out AArchivePath, AProbeUri: string): Boolean;
var
  S, Base, Probe: string;
  Segs: TArray<string>;
  Backend: IVirtualFileSystem;
begin
  Result := False;
  AArchivePath := '';
  AProbeUri := '';
  if not IsZipArchiveUri(ATabUri) or HostSevenZipDllMissing then
    Exit;
  AArchivePath := ArchiveBasePath(ATabUri);
  if (AArchivePath = '') or
     not GlobalVfsRegistry.TryResolve(PathToSevenZipRootUri(AArchivePath), Backend) then
    Exit;
  for S in AURIs do
    if SplitArchiveUri(S, Base, Segs) and (Length(Segs) = 1) and
       ZipFindEncryptedEntry(ArchiveBaseLocalPath(Base), Segs[0], Probe) then
    begin
      AProbeUri := JoinVfsUri(PathToSevenZipRootUri(AArchivePath), Probe);
      Exit(True);
    end;
end;

function ReadableArchiveRowUri(const ARow: TPanelRow): string;
var
  Backend: IVirtualFileSystem;
begin
  Result := ARow.URI;
  if ARow.IsEncrypted and not ARow.IsDirectory and IsZipArchiveUri(ARow.URI) and
     not HostSevenZipDllMissing and
     GlobalVfsRegistry.TryResolve(ZipEntryToSevenZipUri(ARow.URI), Backend) then
    Result := ZipEntryToSevenZipUri(ARow.URI);
end;

end.
