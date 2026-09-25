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

implementation

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
  Name: string;
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
