program ExportDialogJson;

{$APPTYPE CONSOLE}

{ Validates src/dialogs/*.json (source of truth for RCDATA in MTN2.rc).
  Does not regenerate layouts from Pascal — edit JSON, then rebuild MTN2. }

uses
  System.SysUtils, System.IOUtils,
  uTerminalTypes in '..\..\Core\uTerminalTypes.pas',
  uInputLine in '..\..\Core\uInputLine.pas',
  uTextEncoding in '..\..\Core\uTextEncoding.pas',
  uDialogTypes in '..\..\Core\uDialogTypes.pas',
  uDialogJson in '..\..\Core\uDialogJson.pas',
  uDialogResources in '..\..\Core\uDialogResources.pas';

const
  cDialogFiles: array[0..12] of string = (
    'confirm.json',
    'delete.json',
    'help.json',
    'input.json',
    'asksave.json',
    'search.json',
    'copymove.json',
    'gotoline.json',
    'encoding.json',
    'replace.json',
    'overwriteask.json',
    'deleteerror.json',
    'folderhistory.json'
  );

  cDialogRes: array[0..11] of string = (
    cResDialogConfirm,
    cResDialogDelete,
    cResDialogHelp,
    cResDialogInput,
    cResDialogAskSave,
    cResDialogSearch,
    cResDialogCopyMove,
    cResDialogGotoLine,
    cResDialogEncoding,
    cResDialogReplace,
    cResDialogOverwriteAsk,
    cResDialogDeleteError
  );

function ResolveDialogsDir: string;
var
  ExeDir, Walk, Candidate: string;
begin
  if ParamCount >= 1 then
    Exit(ExpandFileName(ParamStr(1)));

  ExeDir := ExtractFilePath(ParamStr(0));
  Walk := ExeDir;
  while Walk <> '' do
  begin
    Candidate := TPath.Combine(Walk, 'dialogs');
    if TDirectory.Exists(Candidate) and
       TFile.Exists(TPath.Combine(Candidate, 'confirm.json')) then
      Exit(Candidate);
    Candidate := TPath.Combine(TPath.Combine(Walk, 'src'), 'dialogs');
    if TDirectory.Exists(Candidate) and
       TFile.Exists(TPath.Combine(Candidate, 'confirm.json')) then
      Exit(Candidate);
    if SameText(Walk, ExpandFileName(TPath.Combine(Walk, '..'))) then
      Break;
    Walk := ExpandFileName(TPath.Combine(Walk, '..'));
  end;
  Result := TPath.Combine(GetCurrentDir, 'dialogs');
end;

var
  Dir, Path: string;
  I, Fail: Integer;
  Decl: TDialogDeclaration;
  Json: string;
begin
  Dir := ResolveDialogsDir;
  Writeln('Validating dialogs in ', Dir);
  Fail := 0;
  for I := Low(cDialogFiles) to High(cDialogFiles) do
  begin
    Path := TPath.Combine(Dir, cDialogFiles[I]);
    if not TFile.Exists(Path) then
    begin
      Writeln('MISSING ', cDialogFiles[I]);
      Inc(Fail);
      Continue;
    end;
    Json := TFile.ReadAllText(Path, TEncoding.UTF8);
    if (Length(Json) > 0) and (Ord(Json[1]) = $FEFF) then
      Delete(Json, 1, 1);
    if not TryParseDialogJson(Json, Decl) then
    begin
      Writeln('PARSE FAIL ', cDialogFiles[I]);
      Inc(Fail);
      Continue;
    end;
    // Also exercise RequireDialogResource (RCDATA or dialogs\ fallback).
    try
      RequireDialogResource(cDialogRes[I], Decl);
      Writeln('OK  ', cDialogFiles[I], ' -> ', cDialogRes[I],
        ' (', Length(Decl.Controls), ' controls)');
    except
      on E: Exception do
      begin
        Writeln('LOAD FAIL ', cDialogFiles[I], ': ', E.Message);
        Inc(Fail);
      end;
    end;
  end;
  if Fail > 0 then
  begin
    Writeln('Failed: ', Fail);
    Halt(1);
  end;
  Writeln('All dialog JSON OK.');
end.
