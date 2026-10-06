unit TestDialogJson;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogJson = class
  public
    [Test] procedure TestValidateAllDialogs;
    [Test] procedure TestListFlagsSurviveARoundTrip;
    [Test] procedure TestColorSampleParsing;
    [Test] procedure TestDirSyncRadios;
    [Test] procedure TestFileDiffDialog;
    [Test] procedure TestArchivePasswordParsing;
    [Test] procedure TestSelectMaskDialog;
    [Test] procedure TestSetAttrDialog;
    [Test] procedure TestDisplayDialog;
    [Test] procedure TestDeleteErrorDialog;
    [Test] procedure TestJobProgressDialogs;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  uDialogTypes,
  uDialogJson;

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
  Assert.IsTrue(Length(LDialogFiles) > 0, 'No dialog JSON files found in ..\..\dialogs');

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
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\colorcodingedit.json', TEncoding.UTF8), LDecl),
    'colorcodingedit.json failed to parse');
  I := FindControlById(LDecl, 'cc_normal_sample');
  Assert.IsTrue(I >= 0, 'cc_normal_sample control not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckColorSample, 'cc_normal_sample is not dckColorSample');
  Assert.IsTrue(LDecl.Controls[I].FgSourceId = 'cc_normal_fg', 'cc_normal_sample.FgSourceId wrong: "' + LDecl.Controls[I].FgSourceId + '"');
  Assert.IsTrue(LDecl.Controls[I].BgSourceId = 'cc_normal_bg', 'cc_normal_sample.BgSourceId wrong: "' + LDecl.Controls[I].BgSourceId + '"');
  Assert.IsTrue(Trim(LDecl.Controls[I].Text) = 'filename.txt', 'cc_normal_sample.Text wrong: "' + LDecl.Controls[I].Text + '"');
  Writeln('  cc_normal_sample: Kind=dckColorSample, FgSourceId/BgSourceId wired correctly');

  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\colorpicker.json', TEncoding.UTF8), LDecl),
    'colorpicker.json failed to parse');
  I := FindControlById(LDecl, 'picker');
  Assert.IsTrue(I >= 0, 'picker control not found in colorpicker.json');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckColorPicker, 'picker is not dckColorPicker');

end;

procedure TestDirSyncRadios;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\dirsync.json', TEncoding.UTF8), LDecl),
    'dirsync.json failed to parse');
  I := FindControlById(LDecl, 'oneway');
  Assert.IsTrue(I >= 0, 'oneway radio not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckRadio, 'oneway is not dckRadio');
  Assert.IsTrue(SameText(LDecl.Controls[I].Group, 'sync_mode'), 'oneway group is sync_mode');
  Assert.IsTrue(LDecl.Controls[I].Checked, 'oneway is the default');
  I := FindControlById(LDecl, 'twoway');
  Assert.IsTrue(I >= 0, 'twoway radio not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckRadio, 'twoway is not dckRadio');
  Assert.IsTrue(SameText(LDecl.Controls[I].Group, 'sync_mode'), 'twoway group is sync_mode');
  Assert.IsTrue(not LDecl.Controls[I].Checked, 'twoway starts unchecked');
  I := FindControlById(LDecl, 'bydate');
  Assert.IsTrue(I >= 0, 'bydate radio not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckRadio, 'bydate is not dckRadio');
  Assert.IsTrue(SameText(LDecl.Controls[I].Group, 'compare_by'), 'bydate group is compare_by');
  Assert.IsTrue(LDecl.Controls[I].Checked, 'bydate is the default');
  I := FindControlById(LDecl, 'bycontent');
  Assert.IsTrue(I >= 0, 'bycontent radio not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckRadio, 'bycontent is not dckRadio');
  Assert.IsTrue(SameText(LDecl.Controls[I].Group, 'compare_by'), 'bycontent group is compare_by');
  Assert.IsTrue(not LDecl.Controls[I].Checked, 'bycontent starts unchecked');
  Writeln('  dirsync.json: one-way/two-way radios share group sync_mode');
  Writeln('  dirsync.json: date/content radios share group compare_by');
end;

procedure TestFileDiffDialog;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\filediff.json', TEncoding.UTF8), LDecl),
    'filediff.json failed to parse');
  I := FindControlById(LDecl, 'diff');
  Assert.IsTrue(I >= 0, 'diff list not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckList, 'diff is not dckList');
  I := FindControlById(LDecl, 'left_name');
  Assert.IsTrue(I >= 0, 'left_name label not found');
  Writeln('  filediff.json: list + left/right name labels');
end;

procedure TestArchivePasswordParsing;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\archivepassword.json', TEncoding.UTF8), LDecl),
    'archivepassword.json failed to parse');
  I := FindControlById(LDecl, 'password');
  Assert.IsTrue(I >= 0, 'password control not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckInput, 'password is not dckInput');
  Assert.IsTrue(LDecl.Controls[I].Password, 'password control must have Password=True');
  Writeln('  archivepassword.json: password input is masked');
end;

procedure TestSelectMaskDialog;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\selectmask.json', TEncoding.UTF8), LDecl),
    'selectmask.json failed to parse');
  I := FindControlById(LDecl, 'name');
  Assert.IsTrue(I >= 0, 'name input not found');
  I := FindControlById(LDecl, 'select_folders');
  Assert.IsTrue(I >= 0, 'select_folders checkbox not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckCheckbox, 'select_folders is not checkbox');
  Writeln('  selectmask.json: mask input + Select folders checkbox');
end;

procedure TestSetAttrDialog;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\setattr.json', TEncoding.UTF8), LDecl),
    'setattr.json failed to parse');
  I := FindControlById(LDecl, 'attr_ro');
  Assert.IsTrue(I >= 0, 'attr_ro dropdown not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckDropDown, 'attr_ro is not dropdown');
  Assert.IsTrue(Length(LDecl.Controls[I].Items) = 3, 'attr_ro Keep/Set/Clear');
  I := FindControlById(LDecl, 'change_owner');
  Assert.IsTrue(I >= 0, 'change_owner checkbox not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckCheckbox, 'change_owner is not checkbox');
  Assert.IsTrue(not LDecl.Controls[I].Checked, 'change_owner starts unchecked');
  I := FindControlById(LDecl, 'recurse');
  Assert.IsTrue(I >= 0, 'recurse checkbox not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckCheckbox, 'recurse is not checkbox');
  I := FindControlById(LDecl, 'owner');
  Assert.IsTrue(I >= 0, 'owner input not found');
  Writeln('  setattr.json: Keep/Set/Clear dropdowns + owner + recurse');
end;

procedure TestDisplayDialog;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\display.json', TEncoding.UTF8), LDecl),
    'display.json failed to parse');
  I := FindControlById(LDecl, 'fonts');
  Assert.IsTrue(I >= 0, 'fonts list not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckList, 'fonts is not a list');
  I := FindControlById(LDecl, 'font_size');
  Assert.IsTrue(I >= 0, 'font_size dropdown not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckDropDown, 'font_size is not dropdown');
  I := FindControlById(LDecl, 'zoom');
  Assert.IsTrue(I >= 0, 'zoom dropdown not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckDropDown, 'zoom is not dropdown');
  I := FindControlById(LDecl, 'blink');
  Assert.IsTrue(I >= 0, 'blink checkbox not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckCheckbox, 'blink is not checkbox');
  I := FindControlById(LDecl, 'blink_ms');
  Assert.IsTrue(I >= 0, 'blink_ms dropdown not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckDropDown, 'blink_ms is not dropdown');
  I := FindControlById(LDecl, 'panel_icons');
  Assert.IsTrue(I >= 0, 'panel_icons checkbox not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckCheckbox, 'panel_icons is not checkbox');
  Writeln('  display.json: fonts, font_size, zoom, blink, blink_ms, panel_icons');
end;

procedure TestJobProgressDialogs;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\jobprogress.json', TEncoding.UTF8), LDecl),
    'jobprogress.json failed to parse');
  Assert.IsTrue(LDecl.Width >= 72, 'jobprogress is as wide as the old overlay');
  I := FindControlById(LDecl, 'verb');
  Assert.IsTrue(I >= 0, 'verb label');
  I := FindControlById(LDecl, 'src');
  Assert.IsTrue(I >= 0, 'src label');
  I := FindControlById(LDecl, 'dst');
  Assert.IsTrue(I >= 0, 'dst label');
  I := FindControlById(LDecl, 'file_bar');
  Assert.IsTrue(I >= 0, 'file_bar label');
  I := FindControlById(LDecl, 'files');
  Assert.IsTrue(I >= 0, 'files label');
  I := FindControlById(LDecl, 'bytes');
  Assert.IsTrue(I >= 0, 'bytes label');
  I := FindControlById(LDecl, 'total_bar');
  Assert.IsTrue(I >= 0, 'total_bar label');
  I := FindControlById(LDecl, 'background');
  Assert.IsTrue(I >= 0, 'background button');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckButton, 'background is a button');
  I := FindControlById(LDecl, 'cancel');
  Assert.IsTrue(I >= 0, 'cancel button');
  Assert.IsTrue(LDecl.Controls[I].IsCancel, 'cancel is the cancel button');
  Writeln('  jobprogress.json: verb/src/dst/bars + Background/Cancel');

  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\jobprogressdelete.json', TEncoding.UTF8), LDecl),
    'jobprogressdelete.json failed to parse');
  I := FindControlById(LDecl, 'src');
  Assert.IsTrue(I >= 0, 'delete src');
  I := FindControlById(LDecl, 'file_bar');
  Assert.IsTrue(I >= 0, 'delete file_bar');
  I := FindControlById(LDecl, 'background');
  Assert.IsTrue(I >= 0, 'delete background');
  Writeln('  jobprogressdelete.json: path + bar + Background/Cancel');

  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\jobprogresserror.json', TEncoding.UTF8), LDecl),
    'jobprogresserror.json failed to parse');
  I := FindControlById(LDecl, 'message');
  Assert.IsTrue(I >= 0, 'error message');
  I := FindControlById(LDecl, 'ok');
  Assert.IsTrue(I >= 0, 'error close');
  Writeln('  jobprogresserror.json: message + Close');
end;

procedure TestDeleteErrorDialog;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\deleteerror.json', TEncoding.UTF8), LDecl),
    'deleteerror.json failed to parse');
  Assert.IsTrue(LDecl.Height >= 14, 'deleteerror dialog is tall enough for a wrapped OS message');
  I := FindControlById(LDecl, 'error_line');
  Assert.IsTrue(I >= 0, 'error_line label not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckLabel, 'error_line is not a label');
  Assert.IsTrue(LDecl.Controls[I].BoxH >= 3, 'error_line must wrap across at least 3 rows');
  // The client width less one clear cell on each side.
  Assert.IsTrue(LDecl.Controls[I].BoxW = LDecl.Width - 4, 'error_line uses the dialog body width');
  I := FindControlById(LDecl, 'path');
  Assert.IsTrue(I >= 0, 'path label not found');
  Writeln('  deleteerror.json: error_line is a 3-row wrapping label');
end;

{ TTestDialogJson }

procedure TTestDialogJson.TestListFlagsSurviveARoundTrip;
var
  Decl, Back: TDialogDeclaration;
  I: Integer;
  Json: string;
begin
  Assert.IsTrue(TryParseDialogJson(
    '{"type":"dialog","version":"2.0","title":"T","width":40,"height":10,"children":[' +
    '{"type":"list","id":"l","selected":0,"items":["a","b"],"frame":true,"keycommands":true,' +
    '"col":1,"row":1,"width":30,"height":5},' +
    '{"type":"list","id":"p","selected":0,"items":["a"],"col":1,"row":7,"width":30,"height":2}]}',
    Decl), 'parses');
  Json := DeclarationToJson(Decl);
  Assert.IsTrue(TryParseDialogJson(Json, Back), 'the written JSON parses again');
  for I := 0 to High(Back.Controls) do
    if Back.Controls[I].Id = 'l' then
    begin
      Assert.IsTrue(Back.Controls[I].Framed, 'the frame is written');
      Assert.IsTrue(Back.Controls[I].KeyCommands, 'the key commands flag is written');
    end
    else if Back.Controls[I].Id = 'p' then
    begin
      Assert.IsFalse(Back.Controls[I].Framed, 'no frame stays no frame');
      Assert.IsFalse(Back.Controls[I].KeyCommands, 'and no key commands');
    end;
end;

procedure TTestDialogJson.TestValidateAllDialogs;
begin
  TestDialogJson.TestValidateAllDialogs;
end;

procedure TTestDialogJson.TestColorSampleParsing;
begin
  TestDialogJson.TestColorSampleParsing;
end;

procedure TTestDialogJson.TestDirSyncRadios;
begin
  TestDialogJson.TestDirSyncRadios;
end;

procedure TTestDialogJson.TestFileDiffDialog;
begin
  TestDialogJson.TestFileDiffDialog;
end;

procedure TTestDialogJson.TestArchivePasswordParsing;
begin
  TestDialogJson.TestArchivePasswordParsing;
end;

procedure TTestDialogJson.TestSelectMaskDialog;
begin
  TestDialogJson.TestSelectMaskDialog;
end;

procedure TTestDialogJson.TestSetAttrDialog;
begin
  TestDialogJson.TestSetAttrDialog;
end;

procedure TTestDialogJson.TestDisplayDialog;
begin
  TestDialogJson.TestDisplayDialog;
end;

procedure TTestDialogJson.TestDeleteErrorDialog;
begin
  TestDialogJson.TestDeleteErrorDialog;
end;

procedure TTestDialogJson.TestJobProgressDialogs;
begin
  TestDialogJson.TestJobProgressDialogs;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogJson);

end.
