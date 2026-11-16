unit uDualPanelOperations;

{ Operations Controller: Isolates MkDir, Rename, and path validation logic
  from uDualPanelWindow.pas. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uVfsTypes, uDualPanelTypes, uAssociations, uVfsRegistry, uZipVfs, uPluginHost;

type
  TDualPanelOperationsController = class
  public
    class function ValidateFolderSegments(const AName: string; out ACleanName, ASelectName, AErrorMsg: string): Boolean;
    class function ValidateRenameName(const AName: string; out AErrorMsg: string): Boolean;
  end;

  TActivateCurrentKind = (ackNone, ackFindGoto, ackHistoryBack, ackNavigate,
    ackZipNavigate, ackView, ackEdit, ackShell, ackCommand);
  TDirectoryExistsFn = reference to function(const APath: string): Boolean;

function ClassifyActivateCurrent(AFindHit, ALeaveSynthetic, AIsDirOrParent,
  AIsZip: Boolean; AAssoc: TAssocAction): TActivateCurrentKind;
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
