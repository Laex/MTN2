unit uExternalTools;

{ External viewer / editor (FAR Alt+F3 / Alt+F4). Two command templates in
  <config>\externaltools.json, set in Options > External viewer/editor...;
  %1 is the quoted file path (appended when the template has no %1, see
  uUserAssociations.BuildAssocCommandLine). An empty template falls back to
  the OS shell: "open" for the viewer, "edit" (then Notepad) for the editor.

  Hand-rolled System.JSON like uUserAssociations: a missing or corrupt file
  means both commands are empty, never a startup error. }

interface

type
  TExternalTools = record
    ViewerCommand: string;
    EditorCommand: string;
  end;

  TExternalLaunchKind = (
    /// <summary>Run CommandLine as a detached process.</summary>
    elkCommand,
    /// <summary>OS "open" for the file (uShellAssoc.ShellOpenFile).</summary>
    elkShellOpen,
    /// <summary>OS "edit" verb, Notepad if none (uShellAssoc.ShellEditFile).</summary>
    elkShellEdit
  );

  TExternalLaunch = record
    Kind: TExternalLaunchKind;
    CommandLine: string;
  end;

function ResolveExternalLaunch(const ATools: TExternalTools; AEdit: Boolean;
  const AFilePath: string): TExternalLaunch;

function DefaultExternalToolsFilePath: string;
/// <summary>Both fields empty when the file is missing or unreadable.</summary>
function LoadExternalTools(const APath: string): TExternalTools;
function SaveExternalTools(const APath: string; const ATools: TExternalTools): Boolean;

/// <summary>Process-wide settings, loaded from the default file on first use.</summary>
function GlobalExternalTools: TExternalTools;
/// <summary>Replaces the global settings and writes the default file.</summary>
function SetGlobalExternalTools(const ATools: TExternalTools): Boolean;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON,
  uConfigLocation, uUserAssociations;

function ResolveExternalLaunch(const ATools: TExternalTools; AEdit: Boolean;
  const AFilePath: string): TExternalLaunch;
var
  Template: string;
begin
  Result := Default(TExternalLaunch);
  if AEdit then
    Template := Trim(ATools.EditorCommand)
  else
    Template := Trim(ATools.ViewerCommand);
  if Template = '' then
  begin
    if AEdit then
      Result.Kind := elkShellEdit
    else
      Result.Kind := elkShellOpen;
    Exit;
  end;
  Result.Kind := elkCommand;
  Result.CommandLine := BuildAssocCommandLine(Template, AFilePath);
end;

function DefaultExternalToolsFilePath: string;
begin
  Result := GetConfigFilePath('externaltools.json');
end;

function LoadExternalTools(const APath: string): TExternalTools;
var
  RootVal: TJSONValue;
  Root: TJSONObject;
begin
  Result := Default(TExternalTools);
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
  try
    RootVal := TJSONObject.ParseJSONValue(TFile.ReadAllText(APath, TEncoding.UTF8));
  except
    Exit;
  end;
  try
    if not (RootVal is TJSONObject) then
      Exit;
    Root := TJSONObject(RootVal);
    Result.ViewerCommand := Root.GetValue<string>('viewer', '');
    Result.EditorCommand := Root.GetValue<string>('editor', '');
  finally
    RootVal.Free;
  end;
end;

function SaveExternalTools(const APath: string; const ATools: TExternalTools): Boolean;
var
  Root: TJSONObject;
  Dir: string;
begin
  Result := False;
  Root := TJSONObject.Create;
  try
    try
      Root.AddPair('viewer', ATools.ViewerCommand);
      Root.AddPair('editor', ATools.EditorCommand);
      Dir := ExtractFilePath(APath);
      if Dir <> '' then
        ForceDirectories(Dir);
      TFile.WriteAllText(APath, Root.ToJSON, TEncoding.UTF8);
      Result := True;
    except
      { leave Result = False }
    end;
  finally
    Root.Free;
  end;
end;

var
  GLoaded: Boolean;
  GTools: TExternalTools;

function GlobalExternalTools: TExternalTools;
begin
  if not GLoaded then
  begin
    GTools := LoadExternalTools(DefaultExternalToolsFilePath);
    GLoaded := True;
  end;
  Result := GTools;
end;

function SetGlobalExternalTools(const ATools: TExternalTools): Boolean;
begin
  GTools := ATools;
  GLoaded := True;
  Result := SaveExternalTools(DefaultExternalToolsFilePath, ATools);
end;

end.
