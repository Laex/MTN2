program TestDialogJson;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  uDialogTypes in '..\..\Core\uDialogTypes.pas',
  uDialogJson in '..\..\Core\uDialogJson.pas';

procedure TestValidateAllDialogs;
var
  LDialogFiles: TArray<string>;
  LFile: string;
  LContent: string;
  LDecl: TDialogDeclaration;
  LSuccess: Boolean;
  LCount: Integer;
begin
  LDialogFiles := TDirectory.GetFiles('..\..\dialogs', '*.json');
  Assert(Length(LDialogFiles) > 0, 'No dialog JSON files found in ..\..\dialogs');

  LCount := 0;
  for LFile in LDialogFiles do
  begin
    LContent := TFile.ReadAllText(LFile, TEncoding.UTF8);
    LSuccess := TryParseDialogJson(LContent, LDecl);
    if not LSuccess then
      raise Exception.CreateFmt('Failed to parse dialog JSON file: %s', [ExtractFileName(LFile)]);

    Inc(LCount);
    Writeln('  Validated dialog: ', ExtractFileName(LFile), ' (title: "', LDecl.Title, '", controls: ', Length(LDecl.Controls), ')');
  end;

  Writeln(Format('OK: Validated all %d dialog JSON files successfully', [LCount]));
end;

function FindControlById(const ADecl: TDialogDeclaration; const AId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ADecl.Controls) do
    if SameText(ADecl.Controls[I].Id, AId) then
      Exit(I);
  Result := -1;
end;

procedure TestColorSampleParsing;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\colorcodingedit.json', TEncoding.UTF8), LDecl),
    'colorcodingedit.json failed to parse');
  I := FindControlById(LDecl, 'cc_normal_sample');
  Assert(I >= 0, 'cc_normal_sample control not found');
  Assert(LDecl.Controls[I].Kind = dckColorSample, 'cc_normal_sample is not dckColorSample');
  Assert(LDecl.Controls[I].FgSourceId = 'cc_normal_fg', 'cc_normal_sample.FgSourceId wrong: "' + LDecl.Controls[I].FgSourceId + '"');
  Assert(LDecl.Controls[I].BgSourceId = 'cc_normal_bg', 'cc_normal_sample.BgSourceId wrong: "' + LDecl.Controls[I].BgSourceId + '"');
  Assert(Trim(LDecl.Controls[I].Text) = 'filename.txt', 'cc_normal_sample.Text wrong: "' + LDecl.Controls[I].Text + '"');
  Writeln('  cc_normal_sample: Kind=dckColorSample, FgSourceId/BgSourceId wired correctly');

  Assert(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\colorpicker.json', TEncoding.UTF8), LDecl),
    'colorpicker.json failed to parse');
  I := FindControlById(LDecl, 'preview');
  Assert(I >= 0, 'preview control not found in colorpicker.json');
  Assert(LDecl.Controls[I].Kind = dckColorSample, 'preview is not dckColorSample');
  // fgFrom/bgFrom are left blank in the JSON itself — BuildColorPickerDialog
  // patches them at open time via DialogSetColorSampleSources (AIsBg-dependent).
  Assert(LDecl.Controls[I].FgSourceId = '', 'preview.FgSourceId should start blank (patched at Build time)');
  Assert(LDecl.Controls[I].BgSourceId = '', 'preview.BgSourceId should start blank (patched at Build time)');
  Writeln('  colorpicker.json''s preview: Kind=dckColorSample, sources blank until BuildColorPickerDialog patches them');

  Writeln('OK: colorsample control parsing verified');
end;

procedure TestDirSyncRadios;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\dirsync.json', TEncoding.UTF8), LDecl),
    'dirsync.json failed to parse');
  I := FindControlById(LDecl, 'oneway');
  Assert(I >= 0, 'oneway radio not found');
  Assert(LDecl.Controls[I].Kind = dckRadio, 'oneway is not dckRadio');
  Assert(SameText(LDecl.Controls[I].Group, 'sync_mode'), 'oneway group is sync_mode');
  Assert(LDecl.Controls[I].Checked, 'oneway is the default');
  I := FindControlById(LDecl, 'twoway');
  Assert(I >= 0, 'twoway radio not found');
  Assert(LDecl.Controls[I].Kind = dckRadio, 'twoway is not dckRadio');
  Assert(SameText(LDecl.Controls[I].Group, 'sync_mode'), 'twoway group is sync_mode');
  Assert(not LDecl.Controls[I].Checked, 'twoway starts unchecked');
  I := FindControlById(LDecl, 'bydate');
  Assert(I >= 0, 'bydate radio not found');
  Assert(LDecl.Controls[I].Kind = dckRadio, 'bydate is not dckRadio');
  Assert(SameText(LDecl.Controls[I].Group, 'compare_by'), 'bydate group is compare_by');
  Assert(LDecl.Controls[I].Checked, 'bydate is the default');
  I := FindControlById(LDecl, 'bycontent');
  Assert(I >= 0, 'bycontent radio not found');
  Assert(LDecl.Controls[I].Kind = dckRadio, 'bycontent is not dckRadio');
  Assert(SameText(LDecl.Controls[I].Group, 'compare_by'), 'bycontent group is compare_by');
  Assert(not LDecl.Controls[I].Checked, 'bycontent starts unchecked');
  Writeln('  dirsync.json: one-way/two-way radios share group sync_mode');
  Writeln('  dirsync.json: date/content radios share group compare_by');
  Writeln('OK: dirsync two-way radio parsing verified');
end;

procedure TestFileDiffDialog;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\filediff.json', TEncoding.UTF8), LDecl),
    'filediff.json failed to parse');
  I := FindControlById(LDecl, 'diff');
  Assert(I >= 0, 'diff list not found');
  Assert(LDecl.Controls[I].Kind = dckList, 'diff is not dckList');
  I := FindControlById(LDecl, 'left_name');
  Assert(I >= 0, 'left_name label not found');
  Writeln('  filediff.json: list + left/right name labels');
  Writeln('OK: filediff dialog parsing verified');
end;

procedure TestArchivePasswordParsing;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\archivepassword.json', TEncoding.UTF8), LDecl),
    'archivepassword.json failed to parse');
  I := FindControlById(LDecl, 'password');
  Assert(I >= 0, 'password control not found');
  Assert(LDecl.Controls[I].Kind = dckInput, 'password is not dckInput');
  Assert(LDecl.Controls[I].Password, 'password control must have Password=True');
  Writeln('  archivepassword.json: password input is masked');
  Writeln('OK: archive password dialog parsing verified');
end;

procedure TestSelectMaskDialog;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\selectmask.json', TEncoding.UTF8), LDecl),
    'selectmask.json failed to parse');
  I := FindControlById(LDecl, 'name');
  Assert(I >= 0, 'name input not found');
  I := FindControlById(LDecl, 'select_folders');
  Assert(I >= 0, 'select_folders checkbox not found');
  Assert(LDecl.Controls[I].Kind = dckCheckbox, 'select_folders is not checkbox');
  Writeln('  selectmask.json: mask input + Select folders checkbox');
  Writeln('OK: select mask dialog parsing verified');
end;

procedure TestSetAttrDialog;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\setattr.json', TEncoding.UTF8), LDecl),
    'setattr.json failed to parse');
  I := FindControlById(LDecl, 'attr_ro');
  Assert(I >= 0, 'attr_ro dropdown not found');
  Assert(LDecl.Controls[I].Kind = dckDropDown, 'attr_ro is not dropdown');
  Assert(Length(LDecl.Controls[I].Items) = 3, 'attr_ro Keep/Set/Clear');
  I := FindControlById(LDecl, 'change_owner');
  Assert(I >= 0, 'change_owner checkbox not found');
  Assert(LDecl.Controls[I].Kind = dckCheckbox, 'change_owner is not checkbox');
  Assert(not LDecl.Controls[I].Checked, 'change_owner starts unchecked');
  I := FindControlById(LDecl, 'recurse');
  Assert(I >= 0, 'recurse checkbox not found');
  Assert(LDecl.Controls[I].Kind = dckCheckbox, 'recurse is not checkbox');
  I := FindControlById(LDecl, 'owner');
  Assert(I >= 0, 'owner input not found');
  Writeln('  setattr.json: Keep/Set/Clear dropdowns + owner + recurse');
  Writeln('OK: set attributes dialog parsing verified');
end;

procedure TestDisplayDialog;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\display.json', TEncoding.UTF8), LDecl),
    'display.json failed to parse');
  I := FindControlById(LDecl, 'fonts');
  Assert(I >= 0, 'fonts list not found');
  Assert(LDecl.Controls[I].Kind = dckList, 'fonts is not a list');
  I := FindControlById(LDecl, 'font_size');
  Assert(I >= 0, 'font_size dropdown not found');
  Assert(LDecl.Controls[I].Kind = dckDropDown, 'font_size is not dropdown');
  I := FindControlById(LDecl, 'zoom');
  Assert(I >= 0, 'zoom dropdown not found');
  Assert(LDecl.Controls[I].Kind = dckDropDown, 'zoom is not dropdown');
  I := FindControlById(LDecl, 'blink');
  Assert(I >= 0, 'blink checkbox not found');
  Assert(LDecl.Controls[I].Kind = dckCheckbox, 'blink is not checkbox');
  I := FindControlById(LDecl, 'blink_ms');
  Assert(I >= 0, 'blink_ms dropdown not found');
  Assert(LDecl.Controls[I].Kind = dckDropDown, 'blink_ms is not dropdown');
  I := FindControlById(LDecl, 'panel_icons');
  Assert(I >= 0, 'panel_icons checkbox not found');
  Assert(LDecl.Controls[I].Kind = dckCheckbox, 'panel_icons is not checkbox');
  Writeln('  display.json: fonts, font_size, zoom, blink, blink_ms, panel_icons');
  Writeln('OK: display dialog parsing verified');
end;

procedure TestJobProgressDialogs;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\jobprogress.json', TEncoding.UTF8), LDecl),
    'jobprogress.json failed to parse');
  Assert(LDecl.Width >= 72, 'jobprogress is as wide as the old overlay');
  I := FindControlById(LDecl, 'verb');
  Assert(I >= 0, 'verb label');
  I := FindControlById(LDecl, 'src');
  Assert(I >= 0, 'src label');
  I := FindControlById(LDecl, 'dst');
  Assert(I >= 0, 'dst label');
  I := FindControlById(LDecl, 'file_bar');
  Assert(I >= 0, 'file_bar label');
  I := FindControlById(LDecl, 'files');
  Assert(I >= 0, 'files label');
  I := FindControlById(LDecl, 'bytes');
  Assert(I >= 0, 'bytes label');
  I := FindControlById(LDecl, 'total_bar');
  Assert(I >= 0, 'total_bar label');
  I := FindControlById(LDecl, 'background');
  Assert(I >= 0, 'background button');
  Assert(LDecl.Controls[I].Kind = dckButton, 'background is a button');
  I := FindControlById(LDecl, 'cancel');
  Assert(I >= 0, 'cancel button');
  Assert(LDecl.Controls[I].IsCancel, 'cancel is the cancel button');
  Writeln('  jobprogress.json: verb/src/dst/bars + Background/Cancel');

  Assert(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\jobprogressdelete.json', TEncoding.UTF8), LDecl),
    'jobprogressdelete.json failed to parse');
  I := FindControlById(LDecl, 'src');
  Assert(I >= 0, 'delete src');
  I := FindControlById(LDecl, 'file_bar');
  Assert(I >= 0, 'delete file_bar');
  I := FindControlById(LDecl, 'background');
  Assert(I >= 0, 'delete background');
  Writeln('  jobprogressdelete.json: path + bar + Background/Cancel');

  Assert(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\jobprogresserror.json', TEncoding.UTF8), LDecl),
    'jobprogresserror.json failed to parse');
  I := FindControlById(LDecl, 'message');
  Assert(I >= 0, 'error message');
  I := FindControlById(LDecl, 'ok');
  Assert(I >= 0, 'error close');
  Writeln('  jobprogresserror.json: message + Close');
  Writeln('OK: job progress dialogs parse');
end;

procedure TestDeleteErrorDialog;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\deleteerror.json', TEncoding.UTF8), LDecl),
    'deleteerror.json failed to parse');
  Assert(LDecl.Height >= 14, 'deleteerror dialog is tall enough for a wrapped OS message');
  I := FindControlById(LDecl, 'error_line');
  Assert(I >= 0, 'error_line label not found');
  Assert(LDecl.Controls[I].Kind = dckLabel, 'error_line is not a label');
  Assert(LDecl.Controls[I].BoxH >= 3, 'error_line must wrap across at least 3 rows');
  Assert(LDecl.Controls[I].BoxW >= 78, 'error_line uses the dialog body width');
  I := FindControlById(LDecl, 'path');
  Assert(I >= 0, 'path label not found');
  Writeln('  deleteerror.json: error_line is a 3-row wrapping label');
  Writeln('OK: delete error dialog wrapping layout verified');
end;

begin
  try
    Writeln('Validating RCDATA Dialog JSON specifications...');
    TestValidateAllDialogs;
    TestColorSampleParsing;
    TestDirSyncRadios;
    TestFileDiffDialog;
    TestArchivePasswordParsing;
    TestSelectMaskDialog;
    TestSetAttrDialog;
    TestDisplayDialog;
    TestDeleteErrorDialog;
    TestJobProgressDialogs;
    Writeln('All Dialog JSON tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
