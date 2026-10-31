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
    [Test] procedure TestAutoLayoutOptionSurvivesARoundTrip;
    [Test] procedure TestColorSampleParsing;
    [Test] procedure TestDirSyncRadios;
    [Test] procedure TestFileDiffDialog;
    [Test] procedure TestArchivePasswordParsing;
    [Test] procedure TestSelectMaskDialog;
    [Test] procedure TestSetAttrDialog;
    [Test] procedure TestDisplayDialog;
    [Test] procedure TestInterfaceDialog;
    [Test] procedure TestDeleteErrorDialog;
    [Test] procedure TestJobProgressDialogs;
    [Test] procedure TestControlTypesParse;
    [Test] procedure TestTristateCheckbox;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  uDialogTypes,
  uDialogJson,
  uDialogLocaleLayout;

procedure TestValidateAllDialogs;
var
  LDialogFiles: TArray<string>;
  LFile: string;
  LContent: string;
  LDecl: TDialogDeclaration;
  LSuccess: Boolean;
  LCount: Integer;
begin
  LDialogFiles := TDirectory.GetFiles('../../dialogs', '*.json');
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
    TFile.ReadAllText('../../dialogs/colorcodingedit.json', TEncoding.UTF8), LDecl),
    'colorcodingedit.json failed to parse');
  I := FindControlById(LDecl, 'cc_normal_sample');
  Assert.IsTrue(I >= 0, 'cc_normal_sample control not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckColorSample, 'cc_normal_sample is not dckColorSample');
  Assert.IsTrue(LDecl.Controls[I].FgSourceId = 'cc_normal_fg', 'cc_normal_sample.FgSourceId wrong: "' + LDecl.Controls[I].FgSourceId + '"');
  Assert.IsTrue(LDecl.Controls[I].BgSourceId = 'cc_normal_bg', 'cc_normal_sample.BgSourceId wrong: "' + LDecl.Controls[I].BgSourceId + '"');
  Assert.IsTrue(Trim(LDecl.Controls[I].Text) = 'filename.txt', 'cc_normal_sample.Text wrong: "' + LDecl.Controls[I].Text + '"');
  Writeln('  cc_normal_sample: Kind=dckColorSample, FgSourceId/BgSourceId wired correctly');

  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('../../dialogs/colorpicker.json', TEncoding.UTF8), LDecl),
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
    TFile.ReadAllText('../../dialogs/dirsync.json', TEncoding.UTF8), LDecl),
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
    TFile.ReadAllText('../../dialogs/filediff.json', TEncoding.UTF8), LDecl),
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
    TFile.ReadAllText('../../dialogs/archivepassword.json', TEncoding.UTF8), LDecl),
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
    TFile.ReadAllText('../../dialogs/selectmask.json', TEncoding.UTF8), LDecl),
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
    TFile.ReadAllText('../../dialogs/setattr.json', TEncoding.UTF8), LDecl),
    'setattr.json failed to parse');
  I := FindControlById(LDecl, 'attr_ro');
  Assert.IsTrue(I >= 0, 'attr_ro checkbox not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckCheckbox, 'attr_ro is not checkbox');
  Assert.IsTrue(LDecl.Controls[I].Tristate, 'attr_ro is tri-state');
  I := FindControlById(LDecl, 'change_owner');
  Assert.IsTrue(I >= 0, 'change_owner checkbox not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckCheckbox, 'change_owner is not checkbox');
  Assert.IsTrue(not LDecl.Controls[I].Checked, 'change_owner starts unchecked');
  I := FindControlById(LDecl, 'recurse');
  Assert.IsTrue(I >= 0, 'recurse checkbox not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckCheckbox, 'recurse is not checkbox');
  I := FindControlById(LDecl, 'owner');
  Assert.IsTrue(I >= 0, 'owner input not found');
  Writeln('  setattr.json: tri-state attribute boxes + owner + recurse');
end;

procedure TestDisplayDialog;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('../../dialogs/display.json', TEncoding.UTF8), LDecl),
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

procedure TestInterfaceDialog;
const
  cChecks: array[0..11] of string = ('show_title_bar', 'show_menu_bar', 'show_key_bar',
    'show_status_line', 'notifications', 'key_hints', 'alt_menu', 'file_drag',
    'select_folders', 'pack_same_panel', 'editor_autoindent', 'exact_sizes');
var
  LDecl: TDialogDeclaration;
  I, K: Integer;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('../../dialogs/interface.json', TEncoding.UTF8), LDecl),
    'interface.json failed to parse');
  for K := Low(cChecks) to High(cChecks) do
  begin
    I := FindControlById(LDecl, cChecks[K]);
    Assert.IsTrue(I >= 0, cChecks[K] + ' checkbox not found');
    Assert.IsTrue(LDecl.Controls[I].Kind = dckCheckbox, cChecks[K] + ' is not checkbox');
  end;
  I := FindControlById(LDecl, 'reset_hints');
  Assert.IsTrue(I >= 0, 'reset hints button not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckButton, 'reset_hints is not a button');
  I := FindControlById(LDecl, 'language');
  Assert.IsTrue(I >= 0, 'language dropdown not found');
  Assert.IsTrue(LDecl.Controls[I].Kind = dckDropDown, 'language is not dropdown');
  Assert.IsTrue(FindControlById(LDecl, 'fonts') < 0, 'font list belongs to display.json');
end;

procedure TestControlTypesParse;
const
  cJson =
    '{"type":"dialog","title":"T","width":40,"height":16,"children":[' +
    '{"type":"label","id":"lb","text":"Hi","accent":true,"marked":true,"col":3,"row":2,"width":4},' +
    '{"type":"input","id":"pw","value":"s","password":true,"history":"h","readonly":true,' +
      '"colorpick":true,"datepick":true},' +
    '{"type":"input","id":"nm","value":"v","history":"masks"},' +
    '{"type":"checkbox","id":"ck","text":"C","checked":true},' +
    '{"type":"radiobox","id":"rb","text":"R","checked":true},' +
    '{"type":"radio","id":"rb2","group":"grp","text":"R2"},' +
    '{"type":"status","id":"st","text":"Ready"},' +
    '{"type":"separator","width":4},' +
    '{"type":"colorsample","id":"cs","text":"t","fgFrom":"f","bgFrom":"b","panelState":"selected",' +
      '"styleFrom":"s","baseStyle":"bold","fgFallback":"ff","bgFallback":"bf"},' +
    '{"type":"colorpicker","id":"cp"},' +
    '{"type":"datepicker","id":"dp"},' +
    '{"type":"list","id":"ls","selected":1,"items":["a",2,null],"frame":true,"keycommands":true},' +
    '{"type":"dropdown","id":"dd","selected":1,"items":["a","b"]},' +
    '{"type":"dropdownlist","id":"dl","selected":1,"items":["a","b"]},' +
    '{"type":"drop_down","id":"du","selected":1,"items":["a","b"]},' +
    '{"type":"combo","id":"cb","selected":1,"items":["a","b"]},' +
    '{"type":"radio_group","id":"g","text":"G","selected":1,"items":["a","b"],' +
      '"item_ids":["ia","ib"],"itemIds":["xa","xb"]},' +
    '{"type":"radiogroup","id":"g2","text":"G2","items":["a","b"],"itemIds":["ca","cb"]},' +
    '{"type":"radio_group","id":"ge2","text":"E","items":["a"],"item_ids":[],"itemIds":["no"]},' +
    '{"type":"radio_group","id":"gc","text":"C","children":[' +
      '{"type":"label","text":"nope"},1,{"type":"radio","id":"r1","text":"One"},' +
      '{"type":"radiobox","id":"r2","text":"Two","checked":true}]},' +
    '{"type":"radio_group","id":"ge","text":"E2","selected":0,"children":[' +
      '{"type":"radio","id":"e1","text":"One"},{"type":"radio","id":"e2","text":"Two","checked":true}]},' +
    '{"type":"button_row","children":[' +
      '{"type":"button","id":"ok","text":"OK","default":true},"x",' +
      '{"type":"dialog","children":[{"type":"button","id":"cancel","text":"Cancel","cancel":true}]}]},' +
    '{"type":"nope","id":"z"}]}';
var
  Decl: TDialogDeclaration;
  C: TDialogControl;
  Raised: Boolean;

  function ById(const AId: string): TDialogControl;
  var
    I: Integer;
  begin
    I := FindControlById(Decl, AId);
    Assert.IsTrue(I >= 0, AId + ' is missing');
    Result := Decl.Controls[I];
  end;

begin
  Assert.IsTrue(TryParseDialogJson(cJson, Decl), 'parses');
  Assert.IsTrue(Length(Decl.Controls) = 23, 'unknown type and non-objects add nothing');
  Assert.IsTrue(FindControlById(Decl, 'z') < 0, 'unknown type is skipped');

  C := ById('lb');
  Assert.IsTrue(C.Kind = dckLabel, 'label');
  Assert.AreEqual('Hi', C.Text);
  Assert.IsTrue(C.Accent, 'accent');
  Assert.IsTrue(C.Marked, 'marked');
  Assert.AreEqual(3, C.Col);
  Assert.AreEqual(2, C.Row);
  Assert.AreEqual(4, C.BoxW);

  C := ById('pw');
  Assert.IsTrue(C.Kind = dckInput, 'password input');
  Assert.AreEqual('s', C.Edit.Text);
  Assert.IsTrue(C.Password, 'password');
  Assert.AreEqual('', C.History, 'password drops history');
  Assert.IsTrue(C.ReadOnly and C.ColorPick and C.DatePick, 'input flags');

  C := ById('nm');
  Assert.AreEqual('v', C.Edit.Text);
  Assert.AreEqual('masks', C.History);

  C := ById('ck');
  Assert.IsTrue((C.Kind = dckCheckbox) and C.Checked, 'checkbox');

  C := ById('rb');
  Assert.IsTrue(C.Kind = dckRadio, 'radiobox');
  Assert.AreEqual('rb', C.Group, 'empty group falls back to id');
  Assert.IsTrue(C.Checked, 'radiobox checked');
  C := ById('rb2');
  Assert.AreEqual('grp', C.Group);

  C := ById('st');
  Assert.IsTrue((C.Kind = dckStatus) and (C.Text = 'Ready'), 'status');

  C := Decl.Controls[FindControlById(Decl, 'st') + 1];
  Assert.IsTrue(IsHRuleText(C.Text), 'separator');
  Assert.AreEqual(4, Length(C.Text));
  Assert.AreEqual(4, C.BoxW);

  C := ById('cs');
  Assert.IsTrue(C.Kind = dckColorSample, 'color sample');
  Assert.AreEqual('f', C.FgSourceId);
  Assert.AreEqual('b', C.BgSourceId);
  Assert.IsTrue(C.PanelState = cspsSelected, 'panel state');
  Assert.AreEqual('s', C.StyleSourceId);
  Assert.AreEqual('bold', C.BaseStyle);
  Assert.AreEqual('ff', C.FgFallbackId);
  Assert.AreEqual('bf', C.BgFallbackId);

  Assert.IsTrue(ById('cp').Kind = dckColorPicker, 'color picker');
  Assert.IsTrue(ById('dp').Kind = dckDatePicker, 'date picker');

  C := ById('ls');
  Assert.IsTrue(C.Kind = dckList, 'list');
  Assert.IsTrue(Length(C.Items) = 3, 'list items');
  Assert.AreEqual('a', C.Items[0]);
  Assert.AreEqual('', C.Items[1], 'a non-string item is empty');
  Assert.AreEqual('', C.Items[2]);
  Assert.AreEqual(1, C.SelectedIndex);
  Assert.IsTrue(C.Framed and C.KeyCommands, 'list flags');

  C := ById('dd');
  Assert.IsTrue(C.Kind = dckDropDown, 'dropdown');
  Assert.AreEqual(1, C.SelectedIndex);
  Assert.AreEqual('b', C.Items[1]);
  Assert.IsTrue(ById('dl').Kind = dckDropDown, 'dropdownlist');
  Assert.IsTrue(ById('du').Kind = dckDropDown, 'drop_down');
  Assert.IsTrue(ById('cb').Kind = dckDropDown, 'combo');

  C := ById('g');
  Assert.IsTrue(C.Kind = dckRadioGroup, 'radio_group');
  Assert.AreEqual('G', C.Text);
  Assert.AreEqual(1, C.SelectedIndex);
  Assert.AreEqual('ia', C.ItemIds[0], 'item_ids wins over itemIds');
  Assert.AreEqual('ib', C.ItemIds[1]);
  C := ById('g2');
  Assert.AreEqual('ca', C.ItemIds[0], 'itemIds is the fallback');
  Assert.AreEqual(0, C.SelectedIndex);
  C := ById('ge2');
  Assert.IsTrue(Length(C.ItemIds) = 0, 'an empty item_ids is kept');

  C := ById('gc');
  Assert.IsTrue(Length(C.Items) = 2, 'radio group children');
  Assert.AreEqual('One', C.Items[0]);
  Assert.AreEqual('Two', C.Items[1]);
  Assert.AreEqual('r1', C.ItemIds[0]);
  Assert.AreEqual('r2', C.ItemIds[1]);
  Assert.AreEqual(1, C.SelectedIndex, 'the checked radio is selected');
  C := ById('ge');
  Assert.AreEqual(0, C.SelectedIndex, 'an explicit selected wins over checked');

  C := ById('ok');
  Assert.IsTrue((C.Kind = dckButton) and C.IsDefault, 'button row');
  C := ById('cancel');
  Assert.IsTrue(C.IsCancel, 'a nested dialog is flattened');
  Assert.AreEqual(FindControlById(Decl, 'ok') + 1, FindControlById(Decl, 'cancel'));

  Assert.IsFalse(TryParseDialogJson(
    '{"type":"dialog","title":"T","children":[{"type":"nope"}]}', Decl),
    'only an unknown control does not make a dialog');

  Raised := False;
  try
    TryParseDialogJson(
      '{"type":"dialog","title":"T","width":40,"height":8,"children":[' +
      '{"type":"list","id":"l","items":"no"}]}', Decl);
  except
    on E: EInvalidCast do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'a non-array items value is rejected');
end;

procedure TestJobProgressDialogs;
var
  LDecl: TDialogDeclaration;
  I: Integer;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('../../dialogs/jobprogress.json', TEncoding.UTF8), LDecl),
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
  I := FindControlById(LDecl, 'skipped');
  Assert.IsTrue(I >= 0, 'skipped label');
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
    TFile.ReadAllText('../../dialogs/jobprogressdelete.json', TEncoding.UTF8), LDecl),
    'jobprogressdelete.json failed to parse');
  I := FindControlById(LDecl, 'src');
  Assert.IsTrue(I >= 0, 'delete src');
  I := FindControlById(LDecl, 'file_bar');
  Assert.IsTrue(I >= 0, 'delete file_bar');
  I := FindControlById(LDecl, 'background');
  Assert.IsTrue(I >= 0, 'delete background');
  Writeln('  jobprogressdelete.json: path + bar + Background/Cancel');

  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('../../dialogs/jobprogresserror.json', TEncoding.UTF8), LDecl),
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
    TFile.ReadAllText('../../dialogs/deleteerror.json', TEncoding.UTF8), LDecl),
    'deleteerror.json failed to parse');
  Assert.IsTrue(LDecl.Height >= 13, 'deleteerror dialog is tall enough for a wrapped OS message');
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

procedure TestTristateCheckbox;
var
  LDecl: TDialogDeclaration;
  I: Integer;
  C: TDialogControl;
begin
  Assert.IsTrue(TryParseDialogJson(
    '{"type":"dialog","version":"2.0","title":"T","width":40,"height":8,"children":[' +
    '{"type":"checkbox","id":"a","text":"A","tristate":true,"unknown":true,' +
    '"col":1,"row":1,"width":20,"height":1},' +
    '{"type":"checkbox","id":"b","text":"B","col":1,"row":2,"width":20,"height":1}]}',
    LDecl), 'tri-state dialog parses');
  I := FindControlById(LDecl, 'a');
  C := LDecl.Controls[I];
  Assert.IsTrue(C.Tristate and C.Unknown, 'starts at "don''t care"');
  Assert.AreEqual(0, DialogCheckboxState(C));
  DialogToggleCheckbox(C);
  Assert.AreEqual(2, DialogCheckboxState(C), 'first click checks it');
  DialogToggleCheckbox(C);
  Assert.AreEqual(1, DialogCheckboxState(C), 'second click unchecks it');
  DialogToggleCheckbox(C);
  Assert.AreEqual(0, DialogCheckboxState(C), 'third click is back at "don''t care"');

  C := LDecl.Controls[FindControlById(LDecl, 'b')];
  Assert.IsFalse(C.Tristate, 'a plain checkbox stays two-state');
  DialogToggleCheckbox(C);
  Assert.AreEqual(2, DialogCheckboxState(C));
  DialogToggleCheckbox(C);
  Assert.AreEqual(1, DialogCheckboxState(C));

  Assert.IsTrue(TryParseDialogJson(DeclarationToJson(LDecl), LDecl),
    'a tri-state dialog survives a round trip');
  C := LDecl.Controls[FindControlById(LDecl, 'a')];
  Assert.IsTrue(C.Tristate and C.Unknown, 'the tri-state flags survive a round trip');
end;

{ TTestDialogJson }

procedure TTestDialogJson.TestTristateCheckbox;
begin
  TestDialogJson.TestTristateCheckbox;
end;

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

procedure TTestDialogJson.TestAutoLayoutOptionSurvivesARoundTrip;
const
  cBody =
    '"version":"2.0","title":"T","width":40,"height":8,"children":[' +
    '{"type":"label","id":"a","text":"A rather long caption:","col":1,"row":0,"width":8},' +
    '{"type":"input","id":"b","value":"","col":10,"row":0,"width":27}]}';
var
  Decl, Back: TDialogDeclaration;
begin
  Assert.IsTrue(TryParseDialogJson('{"type":"dialog",' + cBody, Decl), 'parses');
  Assert.IsFalse(Decl.NoAutoLayout, 'automatic layout is on by default');
  Assert.IsTrue(Pos('autoLayout', DeclarationToJson(Decl)) = 0, 'default is not written');

  Assert.IsTrue(TryParseDialogJson('{"type":"dialog","autoLayout":false,' + cBody, Decl), 'parses');
  Assert.IsTrue(Decl.NoAutoLayout, 'autoLayout false turns it off');
  FitDialogToTranslatedText(Decl);
  Assert.AreEqual(40, Decl.Width, 'width is kept');
  Assert.AreEqual(10, Decl.Controls[1].Col, 'columns are kept');
  Assert.IsFalse(DialogCaptionsOverflow(Decl), 'no caption fitting either');
  Assert.IsTrue(TryParseDialogJson(DeclarationToJson(Decl), Back), 'the written JSON parses again');
  Assert.IsTrue(Back.NoAutoLayout, 'the option is written');

  Assert.IsTrue(TryParseDialogJson('{"type":"dialog","autoLayout":true,' + cBody, Decl), 'parses');
  Assert.IsFalse(Decl.NoAutoLayout, 'autoLayout true keeps it on');
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

procedure TTestDialogJson.TestInterfaceDialog;
begin
  TestDialogJson.TestInterfaceDialog;
end;

procedure TTestDialogJson.TestDeleteErrorDialog;
begin
  TestDialogJson.TestDeleteErrorDialog;
end;

procedure TTestDialogJson.TestJobProgressDialogs;
begin
  TestDialogJson.TestJobProgressDialogs;
end;

procedure TTestDialogJson.TestControlTypesParse;
begin
  TestDialogJson.TestControlTypesParse;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogJson);

end.
