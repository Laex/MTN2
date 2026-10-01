unit TestThemeDialogs;

{ The theme picker and editor dialogs (TThemeDialogController): customizing a
  built-in theme writes a new user theme, a user theme is edited in place,
  names cannot clash, Cancel reselects the active theme. The config folder
  is redirected to a throwaway folder, so the user's themes are never touched. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestThemeDialogs = class
  public
    [Test] procedure TestCustomizeBuiltInSavesNewTheme;
    [Test] procedure TestCancelReselectsActiveTheme;
    [Test] procedure TestUserThemeIsEditedInPlace;
    [Test] procedure TestNewThemeNameMustBeFree;
    [Test] procedure TestBlankThemeStandsAlone;
    [Test] procedure TestDeleteUserTheme;
    [Test] procedure TestBuiltInCannotBeDeleted;
    [Test] procedure TestColoringOfBuiltInAsksForName;
    [Test] procedure TestColoringOfUserThemeSavesInPlace;
    [Test] procedure TestGlyphAndChoiceEdits;
    [Test] procedure TestBadColorStaysInDialog;
    [Test] procedure TestColorReferenceEdit;
    [Test] procedure TestUntouchedRowsStayInherited;
    [Test] procedure TestMarkdownForm;
    [Test] procedure TestBasesEdit;
    [Test] procedure TestMarkdownColorsGoToTheTheme;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.UITypes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uTerminalTypes, uThemeTypes,
  uThemeSpec, uThemeRegistry, uColorCoding, uMarkdownColors, uConfigLocation, uStrings,
  uDualPanelThemeDialogs;

type
  TRig = class
  public
    Dir: string;
    Dialog: TDialogHost;
    Ctrl: TThemeDialogController;
    Kind: THostDialogKind;
    ActiveId: string;
    Selected: string;
    Previews: Integer;
    LastPreview: TThemeSpec;
    InfoText: string;
    constructor Create;
    destructor Destroy; override;
    procedure Pick(const AListId: string; ACount, AIndex: Integer);
    function ThemeRow(const AId: string): Integer;
    /// <summary>Selects item AIndex of a dropdown the way the keyboard does.</summary>
    procedure SetDropDown(const AId: string; AIndex: Integer);
  end;

constructor TRig.Create;
begin
  inherited Create;
  SetLocale('');
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-theme-test-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Dir);
  SetConfigDirectoryOverride(Dir);
  ActiveId := 'Nord';
  Dialog := TDialogHost.Create(nil);
  Ctrl := TThemeDialogController.Create(Dialog,
    procedure(const AControlId, AValuesJson: string)
    begin
    end,
    procedure(AKind: THostDialogKind)
    begin
      Kind := AKind;
    end,
    procedure
    begin
    end,
    function: Boolean
    begin
      Result := True;
    end,
    procedure
    begin
    end,
    function: string
    begin
      Result := ActiveId;
    end,
    procedure(const AThemeId: string)
    begin
      Selected := AThemeId;
      ActiveId := AThemeId;
    end,
    procedure(const ASpec: TThemeSpec)
    begin
      Inc(Previews);
      LastPreview := ASpec;
    end,
    procedure(const ATitle, ADetail: string)
    begin
      InfoText := ADetail;
    end);
end;

destructor TRig.Destroy;
begin
  Ctrl.Free;
  Dialog.Free;
  SetConfigDirectoryOverride('');
  try
    TDirectory.Delete(Dir, True);
  except
    // The folder is in the temp area; a leftover does no harm.
  end;
  inherited;
end;

procedure TRig.Pick(const AListId: string; ACount, AIndex: Integer);
var
  Items: TArray<string>;
  I: Integer;
begin
  SetLength(Items, ACount);
  for I := 0 to ACount - 1 do
    Items[I] := IntToStr(I);
  Dialog.SetListItems(AListId, Items, AIndex);
end;

procedure TRig.SetDropDown(const AId: string; AIndex: Integer);
var
  Key: Word;
  Ch: Char;
  I: Integer;
begin
  Dialog.FocusControlById(AId);
  Key := vkHome;
  Ch := #0;
  Dialog.HandleInput(Key, [], Ch);
  for I := 1 to AIndex do
  begin
    Key := vkDown;
    Ch := #0;
    Dialog.HandleInput(Key, [], Ch);
  end;
end;

function TRig.ThemeRow(const AId: string): Integer;
var
  Infos: TArray<TThemeInfo>;
  I: Integer;
begin
  Infos := GetAvailableThemes;
  for I := 0 to High(Infos) do
    if SameText(Infos[I].Id, AId) then
      Exit(I);
  Result := -1;
end;

function ThemeSectionIndex(const ASection: string): Integer;
var
  Sections: TArray<string>;
begin
  Sections := ThemeColorSections + ['markdown', 'attrs', 'glyphs', 'frames', 'theme'];
  for Result := 0 to High(Sections) do
    if SameText(Sections[Result], ASection) then
      Exit;
  Result := -1;
end;

// Opens the picker, customizes `AId`, and opens section `ASection`.
procedure CustomizeAndOpenSection(ARig: TRig; const AId, ASection: string);
var
  Row: Integer;
begin
  ARig.Ctrl.OpenPicker;
  Assert.AreEqual(Ord(hdkTheme), Ord(ARig.Kind));
  Row := ARig.ThemeRow(AId);
  ARig.Pick('themes', Length(GetAvailableThemes), Row);
  ARig.Ctrl.DispatchCommand(hdkTheme, 'customize');
  Assert.AreEqual(Ord(hdkThemeEditor), Ord(ARig.Kind));
  Row := ThemeSectionIndex(ASection);
  Assert.IsTrue(Row >= 0, 'section ' + ASection);
  ARig.Pick('sections', Length(ThemeColorSections) + 5, Row);
  ARig.Ctrl.DispatchCommand(hdkThemeEditor, 'edit');
  // Colors open a form with a row per role; the other sections are lists.
  if (ASection = 'markdown') or (ThemeSectionIndex(ASection) < Length(ThemeColorSections)) then
    Assert.AreEqual(Ord(hdkThemeColors), Ord(ARig.Kind))
  else
    Assert.AreEqual(Ord(hdkThemeItems), Ord(ARig.Kind));
end;

// Item index of a role inside its own section's list.
function RoleRowInSection(ARole: TThemeColorRole): Integer;
var
  R: TThemeColorRole;
begin
  Result := 0;
  for R := Low(TThemeColorRole) to High(TThemeColorRole) do
  begin
    if R = ARole then
      Exit;
    if SameText(ThemeColorRoleSection(R), ThemeColorRoleSection(ARole)) then
      Inc(Result);
  end;
end;

// Types a color into the row of a role in the colors form and accepts it.
procedure SetRoleColor(ARig: TRig; ARole: TThemeColorRole; const AHex: string);
begin
  Assert.AreEqual(Ord(hdkThemeColors), Ord(ARig.Kind));
  ARig.Dialog.SetInputValue('c_' + IntToStr(RoleRowInSection(ARole)), AHex);
  ARig.Ctrl.DispatchCommand(hdkThemeColors, 'ok');
end;

function UserThemePath(ARig: TRig; const AId: string): string;
begin
  Result := TPath.Combine(TPath.Combine(ARig.Dir, 'themes'), AId + cThemeFileExt);
end;

function SetSlotCount(const ADoc: TThemeDoc): Integer;
var
  R: TThemeColorRole;
begin
  Result := 0;
  for R := Low(TThemeColorRole) to High(TThemeColorRole) do
    if ADoc.Colors[R].Has then
      Inc(Result);
end;

procedure TTestThemeDialogs.TestCustomizeBuiltInSavesNewTheme;
var
  Rig: TRig;
  Doc: TThemeDoc;
  NameValue: string;
begin
  Rig := TRig.Create;
  try
    CustomizeAndOpenSection(Rig, 'Nord', 'window');
    SetRoleColor(Rig, trWindowBg, '#123456');
    Assert.AreEqual(Ord(hdkThemeEditor), Ord(Rig.Kind), 'back on the editor');
    Assert.IsTrue(Rig.Previews > 0, 'the change is previewed');
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF123456), Rig.LastPreview.Colors[trWindowBg]);
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF2E3440), Rig.LastPreview.Colors[trDesktopBg],
      'the rest of the theme is untouched');

    Rig.Ctrl.DispatchCommand(hdkThemeEditor, 'save');
    Assert.AreEqual(Ord(hdkThemeName), Ord(Rig.Kind), 'a copy of a built-in theme asks for a name');
    NameValue := Rig.Dialog.GetInputValue('name');
    Assert.AreEqual('Nord (custom)', NameValue, 'proposed name');
    Rig.Dialog.SetInputValue('name', 'My Nord');
    Rig.Ctrl.DispatchCommand(hdkThemeName, 'ok');

    Assert.AreEqual('My Nord', Rig.Selected, 'the new theme is selected');
    Assert.IsTrue(TFile.Exists(UserThemePath(Rig, 'My Nord')), 'file written');
    Assert.IsFalse(Rig.Dialog.Visible, 'dialog closed');
    Assert.IsTrue(TryLoadThemeDoc('My Nord', Doc));
    Assert.AreEqual('Nord', ThemeExtendsText(Doc.Extends), 'extends the built-in');
    Assert.AreEqual(1, SetSlotCount(Doc), 'only the changed role is stored');
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF123456), Doc.Colors[trWindowBg].Value);
  finally
    Rig.Free;
  end;
end;

procedure TTestThemeDialogs.TestCancelReselectsActiveTheme;
var
  Rig: TRig;
begin
  Rig := TRig.Create;
  try
    CustomizeAndOpenSection(Rig, 'Dracula', 'window');
    SetRoleColor(Rig, trWindowBg, '#010203');
    Rig.Selected := '';
    Rig.Ctrl.DispatchCommand(hdkThemeEditor, 'cancel');
    Assert.AreEqual('Nord', Rig.Selected, 'the theme that was active is selected again');
    Assert.IsFalse(Rig.Dialog.Visible);
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(Rig.Dir, 'themes')), 'nothing written');
  finally
    Rig.Free;
  end;
end;

procedure TTestThemeDialogs.TestUserThemeIsEditedInPlace;
var
  Rig: TRig;
  Doc: TThemeDoc;
  Before: string;
begin
  Rig := TRig.Create;
  try
    // First a user theme from a built-in.
    CustomizeAndOpenSection(Rig, 'Nord', 'cursor');
    SetRoleColor(Rig, trCursorBg, '#AA0000');
    Rig.Ctrl.DispatchCommand(hdkThemeEditor, 'save');
    Rig.Dialog.SetInputValue('name', 'Red cursor');
    Rig.Ctrl.DispatchCommand(hdkThemeName, 'ok');
    Assert.AreEqual('Red cursor', Rig.Selected);
    Before := TFile.ReadAllText(UserThemePath(Rig, 'Red cursor'));

    // Customizing the user theme edits that file.
    Rig.Selected := '';
    CustomizeAndOpenSection(Rig, 'Red cursor', 'cursor');
    SetRoleColor(Rig, trCursorFg, '#00FF00');
    Rig.Ctrl.DispatchCommand(hdkThemeEditor, 'save');
    Assert.IsFalse(Rig.Dialog.Visible, 'saved at once: no name prompt');
    Assert.AreEqual('Red cursor', Rig.Selected);
    Assert.IsTrue(TryLoadThemeDoc('Red cursor', Doc));
    Assert.AreEqual(2, SetSlotCount(Doc), 'both changes are in the same file');
    Assert.AreNotEqual(Before, TFile.ReadAllText(UserThemePath(Rig, 'Red cursor')));
  finally
    Rig.Free;
  end;
end;

procedure TTestThemeDialogs.TestNewThemeNameMustBeFree;
var
  Rig: TRig;
begin
  Rig := TRig.Create;
  try
    Rig.Ctrl.OpenPicker;
    Rig.Ctrl.DispatchCommand(hdkTheme, 'new');
    Assert.AreEqual(Ord(hdkThemeNew), Ord(Rig.Kind));

    Rig.Dialog.SetInputValue('name', 'Nord');
    Rig.Ctrl.DispatchCommand(hdkThemeNew, 'ok');
    Assert.AreEqual(Ord(hdkThemeNew), Ord(Rig.Kind), 'a built-in id is taken');

    Rig.Dialog.SetInputValue('name', 'Far Classic');
    Rig.Ctrl.DispatchCommand(hdkThemeNew, 'ok');
    Assert.AreEqual(Ord(hdkThemeNew), Ord(Rig.Kind), 'a built-in display name is taken');

    Rig.Dialog.SetInputValue('name', '   ');
    Rig.Ctrl.DispatchCommand(hdkThemeNew, 'ok');
    Assert.AreEqual(Ord(hdkThemeNew), Ord(Rig.Kind), 'an empty name is refused');

    Rig.Dialog.SetInputValue('name', 'a<b>');
    Rig.Ctrl.DispatchCommand(hdkThemeNew, 'ok');
    // Characters a file name cannot hold are replaced, so this one is fine.
    Assert.AreEqual(Ord(hdkThemeEditor), Ord(Rig.Kind));
  finally
    Rig.Free;
  end;
end;

procedure TTestThemeDialogs.TestBlankThemeStandsAlone;
var
  Rig: TRig;
  Doc: TThemeDoc;
  Spec, Default: TThemeSpec;
begin
  Rig := TRig.Create;
  try
    Rig.Ctrl.OpenPicker;
    Rig.Ctrl.DispatchCommand(hdkTheme, 'new');
    Rig.Dialog.SetInputValue('name', 'Blank one');
    Rig.SetDropDown('base', 0);
    Rig.Ctrl.DispatchCommand(hdkThemeNew, 'ok');
    Assert.AreEqual(Ord(hdkThemeEditor), Ord(Rig.Kind));
    Rig.Ctrl.DispatchCommand(hdkThemeEditor, 'save');
    Assert.AreEqual('Blank one', Rig.Selected, 'the name was chosen up front: no second prompt');
    Assert.IsTrue(TryLoadThemeDoc('Blank one', Doc));
    Assert.AreEqual('', ThemeExtendsText(Doc.Extends), 'stands alone');
    Assert.IsTrue(SetSlotCount(Doc) = Ord(High(TThemeColorRole)) + 1, 'every role written');
    Assert.IsTrue(TryLoadThemeSpec('Blank one', Spec));
    Assert.IsTrue(TryLoadThemeSpec(DefaultThemeId, Default));
    Assert.AreEqual<TAlphaColor>(Default.Colors[trWindowBg], Spec.Colors[trWindowBg]);
    Assert.AreEqual<TAlphaColor>(Default.Colors[trCursorBg], Spec.Colors[trCursorBg]);
  finally
    Rig.Free;
  end;
end;

procedure TTestThemeDialogs.TestDeleteUserTheme;
var
  Rig: TRig;
begin
  Rig := TRig.Create;
  try
    CustomizeAndOpenSection(Rig, 'Nord', 'scroll');
    SetRoleColor(Rig, trScrollFg, '#111111');
    Rig.Ctrl.DispatchCommand(hdkThemeEditor, 'save');
    Rig.Dialog.SetInputValue('name', 'To delete');
    Rig.Ctrl.DispatchCommand(hdkThemeName, 'ok');
    Assert.IsTrue(ThemeExists('To delete'));

    Rig.Selected := '';
    Rig.Ctrl.OpenPicker;
    Rig.Pick('themes', Length(GetAvailableThemes), Rig.ThemeRow('To delete'));
    Rig.Ctrl.DispatchCommand(hdkTheme, 'delete');
    Assert.AreEqual(Ord(hdkThemeDelete), Ord(Rig.Kind), 'asks first');
    Rig.Ctrl.DispatchCommand(hdkThemeDelete, 'no');
    Assert.IsTrue(ThemeExists('To delete'), 'declined');

    Rig.Ctrl.OpenPicker;
    Rig.Pick('themes', Length(GetAvailableThemes), Rig.ThemeRow('To delete'));
    Rig.Ctrl.DispatchCommand(hdkTheme, 'delete');
    Rig.Ctrl.DispatchCommand(hdkThemeDelete, 'yes');
    Assert.IsFalse(ThemeExists('To delete'), 'deleted');
    Assert.AreEqual(Ord(hdkTheme), Ord(Rig.Kind), 'back on the picker');
  finally
    Rig.Free;
  end;
end;

procedure TTestThemeDialogs.TestBuiltInCannotBeDeleted;
var
  Rig: TRig;
begin
  Rig := TRig.Create;
  try
    Rig.Ctrl.OpenPicker;
    Rig.Pick('themes', Length(GetAvailableThemes), Rig.ThemeRow('Nord'));
    Rig.Ctrl.DispatchCommand(hdkTheme, 'delete');
    Assert.AreEqual(Ord(hdkTheme), Ord(Rig.Kind), 'no confirmation for a built-in theme');
    Assert.IsTrue(Rig.Dialog.Visible);
    Assert.IsTrue(ThemeExists('Nord'));
  finally
    Rig.Free;
  end;
end;

procedure TTestThemeDialogs.TestColoringOfBuiltInAsksForName;
var
  Rig: TRig;
  Groups: TArray<TColorCodingGroup>;
  Saved: TArray<TColorCodingGroup>;
  Doc: TThemeDoc;
begin
  Rig := TRig.Create;
  try
    Groups := GetActiveColorCodingGroups;
    Assert.IsTrue(Length(Groups) > 0, 'the default theme brings color coding groups');
    Groups[0].Name := 'Renamed group';
    Rig.Ctrl.SaveColoring(Groups);
    Assert.AreEqual(Ord(hdkThemeName), Ord(Rig.Kind));
    Rig.Dialog.SetInputValue('name', 'Nord with colors');
    Rig.Ctrl.DispatchCommand(hdkThemeName, 'ok');
    Assert.AreEqual('Nord with colors', Rig.Selected);
    Assert.IsTrue(TryLoadThemeDoc('Nord with colors', Doc));
    Assert.AreEqual('Nord', ThemeExtendsText(Doc.Extends));
    Assert.IsTrue(Doc.HasFileColoring);
    Saved := Doc.FileColoring;
    Assert.AreEqual('Renamed group', Saved[0].Name);
    Assert.IsTrue(Rig.ThemeRow('Nord') >= 0, 'the built-in theme is still there');
  finally
    Rig.Free;
  end;
end;

procedure TTestThemeDialogs.TestColoringOfUserThemeSavesInPlace;
var
  Rig: TRig;
  Groups: TArray<TColorCodingGroup>;
  Doc: TThemeDoc;
begin
  Rig := TRig.Create;
  try
    Groups := GetActiveColorCodingGroups;
    Rig.Ctrl.SaveColoring(Groups);
    Rig.Dialog.SetInputValue('name', 'Colors user');
    Rig.Ctrl.DispatchCommand(hdkThemeName, 'ok');
    Assert.AreEqual('Colors user', Rig.ActiveId);

    Rig.Selected := '';
    Groups[0].Name := 'Changed again';
    Rig.Ctrl.SaveColoring(Groups);
    Assert.IsFalse(Rig.Dialog.Visible, 'a user theme is updated without asking');
    Assert.AreEqual('Colors user', Rig.Selected, 'reselected after saving');
    Assert.IsTrue(TryLoadThemeDoc('Colors user', Doc));
    Assert.AreEqual('Changed again', Doc.FileColoring[0].Name);
  finally
    Rig.Free;
  end;
end;

procedure TTestThemeDialogs.TestGlyphAndChoiceEdits;
var
  Rig: TRig;
  Spec: TThemeSpec;
begin
  Rig := TRig.Create;
  try
    // Glyphs: closeMark is a single character.
    CustomizeAndOpenSection(Rig, 'Nord', 'glyphs');
    Rig.Pick('items', Ord(High(TThemeGlyph)) + 1, Ord(tgCloseMark));
    Rig.Ctrl.DispatchCommand(hdkThemeItems, 'edit');
    Assert.AreEqual(Ord(hdkThemeText), Ord(Rig.Kind));
    Rig.Dialog.SetInputValue('value', 'xx');
    Rig.Ctrl.DispatchCommand(hdkThemeText, 'ok');
    Assert.AreEqual(Ord(hdkThemeText), Ord(Rig.Kind), 'two characters are refused');
    Rig.Dialog.SetInputValue('value', 'z');
    Rig.Ctrl.DispatchCommand(hdkThemeText, 'ok');
    Assert.AreEqual(Ord(hdkThemeItems), Ord(Rig.Kind));
    Assert.AreEqual('z', Rig.LastPreview.Glyphs[tgCloseMark]);

    // A mark keeps its trailing space.
    Rig.Pick('items', Ord(High(TThemeGlyph)) + 1, Ord(tgCheckOn));
    Rig.Ctrl.DispatchCommand(hdkThemeItems, 'edit');
    Assert.AreEqual('[x] ', Rig.Dialog.GetInputValue('value'), 'the current mark is shown whole');
    Rig.Dialog.SetInputValue('value', '[X] ');
    Rig.Ctrl.DispatchCommand(hdkThemeText, 'ok');
    Assert.AreEqual('[X] ', Rig.LastPreview.Glyphs[tgCheckOn]);

    // A caption template must keep the placeholder.
    Rig.Pick('items', Ord(High(TThemeGlyph)) + 1, Ord(tgButtonNormal));
    Rig.Ctrl.DispatchCommand(hdkThemeItems, 'edit');
    Rig.Dialog.SetInputValue('value', '[ button ]');
    Rig.Ctrl.DispatchCommand(hdkThemeText, 'ok');
    Assert.AreEqual(Ord(hdkThemeText), Ord(Rig.Kind), 'no {0}: refused');
    Rig.Dialog.SetInputValue('value', '<{0}>');
    Rig.Ctrl.DispatchCommand(hdkThemeText, 'ok');
    Assert.AreEqual('<{0}>', Rig.LastPreview.Glyphs[tgButtonNormal]);

    // Inherit clears it again.
    Rig.Pick('items', Ord(High(TThemeGlyph)) + 1, Ord(tgButtonNormal));
    Rig.Ctrl.DispatchCommand(hdkThemeItems, 'inherit');
    Assert.AreEqual('[ {0} ]', Rig.LastPreview.Glyphs[tgButtonNormal]);

    // Frames: a choice from the list.
    Rig.Ctrl.DispatchCommand(hdkThemeItems, 'back');
    Rig.Pick('sections', 19, 18);
    Rig.Ctrl.DispatchCommand(hdkThemeEditor, 'edit');
    Rig.Pick('items', 5, Ord(tfsWindow));
    Rig.Ctrl.DispatchCommand(hdkThemeItems, 'edit');
    Assert.AreEqual(Ord(hdkThemeChoice), Ord(Rig.Kind));
    // 0 = inherit, 1 = single, 2 = double.
    Rig.SetDropDown('choice', 2);
    Rig.Ctrl.DispatchCommand(hdkThemeChoice, 'ok');
    Spec := Rig.LastPreview;
    Assert.AreEqual('double', Spec.FrameNames[tfsWindow]);
    Assert.AreEqual(string(#$2554), string(Spec.Frames[tfsWindow].TL));
  finally
    Rig.Free;
  end;
end;

procedure TTestThemeDialogs.TestBadColorStaysInDialog;
var
  Rig: TRig;
begin
  Rig := TRig.Create;
  try
    CustomizeAndOpenSection(Rig, 'Nord', 'window');
    Rig.Dialog.SetInputValue('c_' + IntToStr(RoleRowInSection(trWindowBg)), 'not a color');
    Rig.Ctrl.DispatchCommand(hdkThemeColors, 'ok');
    Assert.AreEqual(Ord(hdkThemeColors), Ord(Rig.Kind), 'the form stays open');
    Assert.IsTrue(Rig.Dialog.Visible);
  finally
    Rig.Free;
  end;
end;

procedure TTestThemeDialogs.TestColorReferenceEdit;
var
  Rig: TRig;
begin
  Rig := TRig.Create;
  try
    CustomizeAndOpenSection(Rig, 'Nord', 'window');
    // Several rows at once: a reference, a palette name, a literal.
    Rig.Dialog.SetInputValue('c_' + IntToStr(RoleRowInSection(trWindowBg)), '@cursor.bg');
    Rig.Dialog.SetInputValue('c_' + IntToStr(RoleRowInSection(trWindowFg)), 'nord8');
    Rig.Dialog.SetInputValue('c_' + IntToStr(RoleRowInSection(trBorderNormal)), '#010203');
    Rig.Ctrl.DispatchCommand(hdkThemeColors, 'ok');
    Assert.AreEqual(Ord(hdkThemeEditor), Ord(Rig.Kind));
    Assert.AreEqual<TAlphaColor>(Rig.LastPreview.Colors[trCursorBg], Rig.LastPreview.Colors[trWindowBg],
      'the role follows the cursor color');
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF88C0D0), Rig.LastPreview.Colors[trWindowFg], 'Nord''s palette name');
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF010203), Rig.LastPreview.Colors[trBorderNormal]);
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF2E3440), Rig.LastPreview.Colors[trDesktopBg], 'other sections untouched');

    // A palette name must exist; a role too. Nothing is applied on an error.
    Rig.Ctrl.DispatchCommand(hdkThemeEditor, 'edit');
    Assert.AreEqual(Ord(hdkThemeColors), Ord(Rig.Kind));
    Rig.Dialog.SetInputValue('c_' + IntToStr(RoleRowInSection(trBorderFocus)), 'nosuchcolor');
    Rig.Ctrl.DispatchCommand(hdkThemeColors, 'ok');
    Assert.AreEqual(Ord(hdkThemeColors), Ord(Rig.Kind), 'an unknown palette name is refused');
    Rig.Dialog.SetInputValue('c_' + IntToStr(RoleRowInSection(trBorderFocus)), '@no.such.role');
    Rig.Ctrl.DispatchCommand(hdkThemeColors, 'ok');
    Assert.AreEqual(Ord(hdkThemeColors), Ord(Rig.Kind), 'an unknown role is refused');
    Rig.Ctrl.DispatchCommand(hdkThemeColors, 'cancel');
    Assert.AreEqual(Ord(hdkThemeEditor), Ord(Rig.Kind), 'cancel returns to the editor');
  finally
    Rig.Free;
  end;
end;

procedure TTestThemeDialogs.TestUntouchedRowsStayInherited;
var
  Rig: TRig;
  Doc: TThemeDoc;
begin
  Rig := TRig.Create;
  try
    CustomizeAndOpenSection(Rig, 'Nord', 'cursor');
    // The form shows every role's value, but only what was changed is written.
    Assert.AreEqual('#88C0D0', Rig.Dialog.GetInputValue('c_' + IntToStr(RoleRowInSection(trCursorBg))));
    Rig.Dialog.SetInputValue('c_' + IntToStr(RoleRowInSection(trCursorFg)), '#0A0B0C');
    Rig.Ctrl.DispatchCommand(hdkThemeColors, 'ok');
    Rig.Ctrl.DispatchCommand(hdkThemeEditor, 'save');
    Rig.Dialog.SetInputValue('name', 'One change');
    Rig.Ctrl.DispatchCommand(hdkThemeName, 'ok');
    Assert.IsTrue(TryLoadThemeDoc('One change', Doc));
    Assert.IsTrue(Doc.Colors[trCursorFg].Has);
    Assert.IsFalse(Doc.Colors[trCursorBg].Has, 'an untouched row stays inherited');

    // Blanking a row that the theme sets makes it inherit again.
    Rig.Selected := '';
    CustomizeAndOpenSection(Rig, 'One change', 'cursor');
    Rig.Dialog.SetInputValue('c_' + IntToStr(RoleRowInSection(trCursorFg)), '');
    Rig.Ctrl.DispatchCommand(hdkThemeColors, 'ok');
    Rig.Ctrl.DispatchCommand(hdkThemeEditor, 'save');
    Assert.IsTrue(TryLoadThemeDoc('One change', Doc));
    Assert.IsFalse(Doc.Colors[trCursorFg].Has);
  finally
    Rig.Free;
  end;
end;

procedure TTestThemeDialogs.TestMarkdownForm;
var
  Rig: TRig;
begin
  Rig := TRig.Create;
  try
    CustomizeAndOpenSection(Rig, 'Nord', 'markdown');
    // Row 1 is Heading 1: foreground, background, style.
    Assert.AreEqual('#88C0D0', Rig.Dialog.GetInputValue('f_1'), 'the theme''s own color is shown');
    Rig.Dialog.SetInputValue('f_1', '#112233');
    Rig.SetDropDown('y_3', 3);
    Rig.Ctrl.DispatchCommand(hdkThemeColors, 'ok');
    Assert.AreEqual(Ord(hdkThemeEditor), Ord(Rig.Kind));
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF112233), Rig.LastPreview.MdFg[mskH1]);
    Assert.IsTrue(Rig.LastPreview.MdAttrs[mskH3to6] = [ccaItalic], 'the style list sets the attributes');
    Assert.IsTrue(Rig.LastPreview.MdAttrs[mskH1] = [ccaBold], 'an untouched style keeps the theme''s');
  finally
    Rig.Free;
  end;
end;

procedure TTestThemeDialogs.TestBasesEdit;
var
  Rig: TRig;
  Doc: TThemeDoc;
begin
  Rig := TRig.Create;
  try
    // The last section holds the bases.
    Rig.Ctrl.OpenPicker;
    Rig.Pick('themes', Length(GetAvailableThemes), Rig.ThemeRow('Nord'));
    Rig.Ctrl.DispatchCommand(hdkTheme, 'customize');
    Rig.Pick('sections', 20, 19);
    Rig.Ctrl.DispatchCommand(hdkThemeEditor, 'edit');
    Assert.AreEqual(Ord(hdkThemeItems), Ord(Rig.Kind));
    Rig.Pick('items', 1, 0);
    Rig.Ctrl.DispatchCommand(hdkThemeItems, 'edit');
    Assert.AreEqual(Ord(hdkThemeText), Ord(Rig.Kind));
    Assert.AreEqual('Nord', Rig.Dialog.GetInputValue('value'), 'a copy of a built-in theme builds on it');
    Rig.Dialog.SetInputValue('value', 'NoSuchBase');
    Rig.Ctrl.DispatchCommand(hdkThemeText, 'ok');
    Assert.AreEqual(Ord(hdkThemeText), Ord(Rig.Kind), 'a missing base is refused');
    Rig.Dialog.SetInputValue('value', 'Nord; HighContrast');
    Rig.Ctrl.DispatchCommand(hdkThemeText, 'ok');
    Assert.AreEqual(Ord(hdkThemeItems), Ord(Rig.Kind));
    // High Contrast comes later, so its desktop wins over Nord's.
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF000000), Rig.LastPreview.Colors[trDesktopBg]);

    Rig.Ctrl.DispatchCommand(hdkThemeItems, 'back');
    Rig.Ctrl.DispatchCommand(hdkThemeEditor, 'save');
    Rig.Dialog.SetInputValue('name', 'Two bases');
    Rig.Ctrl.DispatchCommand(hdkThemeName, 'ok');
    Assert.IsTrue(TryLoadThemeDoc('Two bases', Doc));
    Assert.AreEqual('Nord; HighContrast', ThemeExtendsText(Doc.Extends));
  finally
    Rig.Free;
  end;
end;

procedure TTestThemeDialogs.TestMarkdownColorsGoToTheTheme;
var
  Rig: TRig;
  Initial, Edited, Shown: TMdColorSet;
  Doc: TThemeDoc;
  Spec: TThemeSpec;
begin
  Rig := TRig.Create;
  try
    MdColorSetClear(Initial);
    Edited := Initial;
    Edited[mskH1].HasFg := True;
    Edited[mskH1].Fg := TAlphaColor($FF00FF00);
    Edited[mskLink].HasStyle := True;
    Edited[mskLink].Style := [ccaItalic];

    Rig.Ctrl.SaveMarkdown(Initial, Initial);
    Assert.IsFalse(Rig.Dialog.Visible, 'no change, nothing to save');

    Rig.Ctrl.SaveMarkdown(Initial, Edited);
    Assert.AreEqual(Ord(hdkThemeName), Ord(Rig.Kind), 'a built-in theme asks for a name');
    Rig.Dialog.SetInputValue('name', 'Green headings');
    Rig.Ctrl.DispatchCommand(hdkThemeName, 'ok');
    Assert.AreEqual('Green headings', Rig.Selected);
    Assert.IsTrue(TryLoadThemeDoc('Green headings', Doc));
    Assert.AreEqual('Nord', ThemeExtendsText(Doc.Extends));
    Assert.IsTrue(Doc.MdFg[mskH1].Has and not Doc.MdBg[mskH1].Has, 'only the changed channel is stored');
    Assert.IsTrue(Doc.MdAttrs[mskLink].Has);
    Assert.IsTrue(TryLoadThemeSpec('Green headings', Spec));
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF00FF00), Spec.MdFg[mskH1]);
    Assert.IsTrue(Spec.MdAttrs[mskLink] = [ccaItalic]);

    // The dialog opens with what this theme sets.
    Shown := Rig.Ctrl.ActiveMarkdownSet;
    Assert.IsTrue(Shown[mskH1].HasFg and (Shown[mskH1].Fg = TAlphaColor($FF00FF00)));
    Assert.IsFalse(Shown[mskBold].HasFg);

    // A user theme is updated in place.
    Edited[mskH1].Fg := TAlphaColor($FF0000FF);
    Rig.Ctrl.SaveMarkdown(Shown, Edited);
    Assert.IsFalse(Rig.Dialog.Visible, 'no name prompt for a user theme');
    Assert.IsTrue(TryLoadThemeSpec('Green headings', Spec));
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF0000FF), Spec.MdFg[mskH1]);
  finally
    Rig.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestThemeDialogs);

end.
