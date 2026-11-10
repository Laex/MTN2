unit uDualPanelOperations;

{ Operations Controller: Isolates MkDir, Rename, and path validation logic
  from uDualPanelWindow.pas. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uVfsTypes, uAssociations;

type
  TDualPanelOperationsController = class
  public
    class function ValidateFolderSegments(const AName: string; out ACleanName, ASelectName, AErrorMsg: string): Boolean;
    class function ValidateRenameName(const AName: string; out AErrorMsg: string): Boolean;
  end;

  TActivateCurrentKind = (ackNone, ackFindGoto, ackHistoryBack, ackNavigate,
    ackZipNavigate, ackView, ackEdit, ackShell, ackCommand);

function ClassifyActivateCurrent(AFindHit, ALeaveSynthetic, AIsDirOrParent,
  AIsZip: Boolean; AAssoc: TAssocAction): TActivateCurrentKind;
/// <summary>Why AName cannot be the name of a file or folder on this system
/// (the rules of Windows or of Linux, whichever runs); empty when it can.</summary>
function FileNameProblem(const AName: string): string;

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

end.
