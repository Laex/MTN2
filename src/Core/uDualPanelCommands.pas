unit uDualPanelCommands;

{ Dual Panel Command Handler: Service routines for file operations and dialog
  invocations (Copy, Move, Delete, MkDir, Rename). Extracted from uDualPanelWindow.pas
  to isolate business logic from UI rendering. }

interface

uses
  System.SysUtils, System.Classes,
  uDualPanelTypes, uVfsTypes, uStrings;

type
  /// <summary>Encapsulates file panel command execution and validation.</summary>
  TDualPanelCommandHandler = class
  public
    class function PrepareCopyMoveTarget(const AActiveURI, AOppositeURI: string): string;
    class function ValidateSourceSelection(const ASources: TArray<string>): Boolean;
    class function FormatDeletePrompt(const ASources: TArray<string>): string;
    class function FormatMkDirTarget(const ABaseURI, ANewFolderName: string): string;
  end;

implementation

class function TDualPanelCommandHandler.PrepareCopyMoveTarget(const AActiveURI, AOppositeURI: string): string;
begin
  if AOppositeURI <> '' then
    Result := AOppositeURI
  else
    Result := AActiveURI;
end;

class function TDualPanelCommandHandler.ValidateSourceSelection(const ASources: TArray<string>): Boolean;
begin
  Result := Length(ASources) > 0;
end;

class function TDualPanelCommandHandler.FormatDeletePrompt(const ASources: TArray<string>): string;
begin
  if Length(ASources) = 1 then
    Result := T('ui.delete.promptOne', 'Delete item "%s"?',
      [ExtractFileName(FileUriToPath(ASources[0]))])
  else
    Result := T('ui.delete.promptMany', 'Delete %d selected items?', [Length(ASources)]);
end;

class function TDualPanelCommandHandler.FormatMkDirTarget(const ABaseURI, ANewFolderName: string): string;
var
  LBasePath: string;
begin
  LBasePath := FileUriToPath(ABaseURI);
  Result := PathToFileUri(IncludeTrailingPathDelimiter(LBasePath) + ANewFolderName);
end;

end.
