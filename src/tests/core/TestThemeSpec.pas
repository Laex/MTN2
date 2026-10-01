unit TestThemeSpec;

{ Theme files: parsing and writing, role fallbacks, "extends" chains, and the
  registry of built-in and user themes. User themes live in a throwaway config
  folder. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestThemeSpec = class
  public
    [Test] procedure TestColorText;
    [Test] procedure TestRoleTable;
    [Test] procedure TestFallbackRoles;
    [Test] procedure TestParentValueBeatsChildFallback;
    [Test] procedure TestRoundTrip;
    [Test] procedure TestPaletteNames;
    [Test] procedure TestColorReferences;
    [Test] procedure TestPaletteBoundWhereWritten;
    [Test] procedure TestMarkdownFollowsText;
    [Test] procedure TestMultipleBases;
    [Test] procedure TestColoringDiffAndOrder;
    [Test] procedure TestNewerSchemaIsRefused;
    [Test] procedure TestFrameSets;
    [Test] procedure TestFileColoringMerges;
    [Test] procedure TestBuiltInsLoad;
    [Test] procedure TestBuiltInLooks;
    [Test] procedure TestUnknownThemeFallsBack;
    [Test] procedure TestThemeIdFromName;
    [Test] procedure TestUserThemeRoundTrip;
    [Test] procedure TestBuiltInCannotBeOverwritten;
    [Test] procedure TestMissingAndCircularBases;
    [Test] procedure TestLegacyColoringImport;
    [Test] procedure TestRoleTitles;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.UITypes,
  uTerminalTypes, uThemeTypes, uThemeSpec, uThemeRegistry, uColorCoding,
  uConfigLocation, uMarkdownColors, uThemeNames, uStrings;

type
  TTempConfig = class
  public
    Dir: string;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TTempConfig.Create;
begin
  inherited Create;
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-theme-spec-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Dir);
  SetConfigDirectoryOverride(Dir);
end;

destructor TTempConfig.Destroy;
begin
  SetConfigDirectoryOverride('');
  try
    TDirectory.Delete(Dir, True);
  except
    // In the temp area; a leftover does no harm.
  end;
  inherited;
end;

function HasKey(const AKeys: TArray<string>; const AKey: string): Boolean;
var
  K: string;
begin
  for K in AKeys do
    if K = AKey then
      Exit(True);
  Result := False;
end;

function DocWith(const AExtends: string): TThemeDoc;
begin
  Result := Default(TThemeDoc);
  if AExtends <> '' then
    Result.Extends := [AExtends];
end;

procedure SetColor(var ADoc: TThemeDoc; ARole: TThemeColorRole; AColor: TAlphaColor);
begin
  ADoc.Colors[ARole].Has := True;
  ADoc.Colors[ARole].Value := AColor;
end;

procedure TTestThemeSpec.TestColorText;
var
  C: TAlphaColor;
begin
  Assert.IsTrue(TryParseThemeColor('#112233', C));
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF112233), C);
  Assert.IsTrue(TryParseThemeColor('abcdef', C), 'no hash');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FFABCDEF), C);
  Assert.IsTrue(TryParseThemeColor('#80112233', C), 'with alpha');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($80112233), C);
  Assert.IsFalse(TryParseThemeColor('#12345', C));
  Assert.IsFalse(TryParseThemeColor('#GG0000', C));
  Assert.IsFalse(TryParseThemeColor('', C));
  Assert.AreEqual('#112233', ThemeColorToText(TAlphaColor($FF112233)));
  Assert.AreEqual('#80112233', ThemeColorToText(TAlphaColor($80112233)));
end;

procedure TTestThemeSpec.TestRoleTable;
var
  R, F: TThemeColorRole;
  Keys: TArray<string>;
  Key: string;
  Depth: Integer;
begin
  SetLength(Keys, 0);
  for R := Low(TThemeColorRole) to High(TThemeColorRole) do
  begin
    Key := ThemeColorRoleKey(R);
    Assert.IsTrue(Pos('.', Key) > 1, 'dotted key: ' + Key);
    Assert.IsFalse(HasKey(Keys, Key), 'unique key: ' + Key);
    Keys := Keys + [Key];
    // Fallbacks end at a role without one, never in a loop.
    Depth := 0;
    F := R;
    while ThemeColorRoleFallback(F, F) do
    begin
      Inc(Depth);
      Assert.IsTrue(Depth < 10, 'fallback chain of ' + Key);
    end;
  end;
  Assert.IsTrue(Length(ThemeColorSections) >= 10);
end;

procedure TTestThemeSpec.TestFallbackRoles;
var
  Doc: TThemeDoc;
  Spec: TThemeSpec;
begin
  Doc := DocWith('');
  SetColor(Doc, trWindowFg, TAlphaColor($FF010101));
  SetColor(Doc, trWindowBg, TAlphaColor($FF020202));
  SetColor(Doc, trCursorFg, TAlphaColor($FF030303));
  SetColor(Doc, trCursorBg, TAlphaColor($FF040404));
  SetColor(Doc, trDialogFg, TAlphaColor($FF050505));
  Spec := ResolveThemeSpec([Doc]);
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF020202), Spec.Colors[trEditorBodyBg], 'editor body follows the window');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF030303), Spec.Colors[trEditorSelFg], 'editor selection follows the cursor');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF040404), Spec.Colors[trCheckFocusBg], 'focused checkbox follows the cursor');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF050505), Spec.Colors[trCheckFg], 'checkbox follows the dialog');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF020202), Spec.MdBg[mskText], 'Markdown background is the window');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF010101), Spec.MdFg[mskLink], 'Markdown text color is the window text');
  Assert.AreEqual<TAlphaColor>(TAlphaColor(0), Spec.Colors[trScrollThumb], 'a role nobody sets is 0');
end;

procedure TTestThemeSpec.TestParentValueBeatsChildFallback;
var
  Parent, Child: TThemeDoc;
  Spec: TThemeSpec;
begin
  Parent := DocWith('');
  SetColor(Parent, trCursorFg, TAlphaColor($FF111111));
  SetColor(Parent, trEditorSelFg, TAlphaColor($FF222222));
  Child := DocWith('p');
  SetColor(Child, trCursorFg, TAlphaColor($FF333333));
  Spec := ResolveThemeSpec([Parent, Child]);
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF333333), Spec.Colors[trCursorFg], 'child overrides');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF222222), Spec.Colors[trEditorSelFg],
    'a value the parent set is kept, not replaced by the child''s fallback');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF333333), Spec.Colors[trEditorMatchFg],
    'a role nobody set follows the child''s cursor');
end;

procedure TTestThemeSpec.TestRoundTrip;
var
  Doc, Back: TThemeDoc;
  Json, Err: string;
  Groups: TArray<TColorCodingGroup>;
  FS: TThemeNamedFrameSet;
begin
  Doc := DocWith('NDN');
  Doc.Name := 'Round trip';
  SetColor(Doc, trWindowBg, TAlphaColor($FF0A0B0C));
  SetColor(Doc, trEditorMatchBg, TAlphaColor($80010203));
  Doc.MdFg[mskH1].Has := True;
  Doc.MdFg[mskH1].Value := TAlphaColor($FF445566);
  Doc.MdBg[mskCodeBlock].Has := True;
  Doc.MdBg[mskCodeBlock].Value := TAlphaColor($FF778899);
  Doc.MdAttrs[mskQuote].Has := True;
  Doc.MdAttrs[mskQuote].Value := [ccaBold, ccaItalic];
  Doc.MdAttrs[mskH2].Has := True;
  Doc.MdAttrs[mskH2].Value := [];
  Doc.Attrs[tasButton].Has := True;
  Doc.Attrs[tasButton].Value := [ccaBold, ccaUnderline];
  Doc.Attrs[tasHot].Has := True;
  Doc.Attrs[tasHot].Value := [];
  Doc.Glyphs[tgCheckOn].Has := True;
  Doc.Glyphs[tgCheckOn].Value := '[X] ';
  Doc.Glyphs[tgScrollBlock].Has := True;
  Doc.Glyphs[tgScrollBlock].Value := #$2593;
  Doc.Frames[tfsWindow].Has := True;
  Doc.Frames[tfsWindow].Value := 'mine';
  FS.Name := 'mine';
  FS.Glyphs.TL := 'a';
  FS.Glyphs.TR := 'b';
  FS.Glyphs.BL := 'c';
  FS.Glyphs.BR := 'd';
  FS.Glyphs.H := 'e';
  FS.Glyphs.V := 'f';
  Doc.FrameSets := [FS];
  Doc.DoubleActivePanel := ttsTrue;
  SetLength(Groups, 1);
  Groups[0].Name := 'Docs';
  Groups[0].Masks := ['*.txt'];
  Groups[0].Enabled := True;
  Groups[0].Colors[ccsNormal].Fg := TAlphaColor($FF112233);
  Doc.HasFileColoring := True;
  Doc.FileColoring := Groups;

  Json := ThemeDocToJson(Doc);
  Assert.IsTrue(TryParseThemeDoc(Json, Back, Err), Err);
  Assert.AreEqual('Round trip', Back.Name);
  Assert.AreEqual('NDN', ThemeExtendsText(Back.Extends));
  Assert.IsTrue(Back.Colors[trWindowBg].Has);
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF0A0B0C), Back.Colors[trWindowBg].Value);
  Assert.AreEqual<TAlphaColor>(TAlphaColor($80010203), Back.Colors[trEditorMatchBg].Value, 'alpha kept');
  Assert.IsFalse(Back.Colors[trWindowFg].Has, 'only what was set is written');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF445566), Back.MdFg[mskH1].Value);
  Assert.IsFalse(Back.MdBg[mskH1].Has);
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF778899), Back.MdBg[mskCodeBlock].Value);
  Assert.IsTrue(Back.MdAttrs[mskQuote].Has and (Back.MdAttrs[mskQuote].Value = [ccaBold, ccaItalic]));
  Assert.IsTrue(Back.MdAttrs[mskH2].Has and (Back.MdAttrs[mskH2].Value = []), 'explicit plain survives');
  Assert.IsTrue(Back.Attrs[tasButton].Value = [ccaBold, ccaUnderline]);
  Assert.IsTrue(Back.Attrs[tasHot].Has and (Back.Attrs[tasHot].Value = []), 'explicit empty set survives');
  Assert.AreEqual('[X] ', Back.Glyphs[tgCheckOn].Value);
  Assert.AreEqual(string(#$2593), Back.Glyphs[tgScrollBlock].Value);
  Assert.AreEqual('mine', Back.Frames[tfsWindow].Value);
  Assert.AreEqual(1, Integer(Length(Back.FrameSets)));
  Assert.AreEqual('c', string(Back.FrameSets[0].Glyphs.BL));
  Assert.IsTrue(Back.DoubleActivePanel = ttsTrue);
  Assert.IsTrue(Back.HasFileColoring);
  Assert.AreEqual(1, Integer(Length(Back.FileColoring)));
  Assert.AreEqual('Docs', Back.FileColoring[0].Name);
end;

procedure TTestThemeSpec.TestPaletteNames;
var
  Doc: TThemeDoc;
  Spec: TThemeSpec;
  Err: string;
begin
  Assert.IsTrue(TryParseThemeDoc(
    '{"palette":{"ink":"#102030","Paper":"#FFFFFF"},' +
    '"colors":{"window":{"fg":"ink","bg":"paper","borderFocus":"nosuch","borderNormal":"#445566"}},' +
    '"markdown":{"h1":{"fg":"INK"}}}', Doc, Err));
  Spec := ResolveThemeSpec([Doc]);
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF102030), Spec.Colors[trWindowFg], 'palette name');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FFFFFFFF), Spec.Colors[trWindowBg], 'names are case-insensitive');
  Assert.AreEqual<TAlphaColor>(TAlphaColor(0), Spec.Colors[trBorderFocus], 'an unknown name leaves the role unset');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF445566), Spec.Colors[trBorderNormal], 'literal');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF102030), Spec.MdFg[mskH1], 'palette in Markdown');
end;

procedure TTestThemeSpec.TestColorReferences;
var
  Doc: TThemeDoc;
  Spec: TThemeSpec;
  Err: string;
  Slot: TThemeColorSlot;
begin
  Assert.IsTrue(TryParseThemeDoc(
    '{"colors":{"cursor":{"bg":"#AA0000","fg":"@window.bg"},"window":{"bg":"#000011"},' +
    '"status":{"bg":"@cursor.bg"},"scroll":{"fg":"@scroll.thumb","thumb":"@scroll.fg"},' +
    '"tab":{"activeFg":"@nosuch.role"}},' +
    '"markdown":{"link":{"fg":"@cursor.bg"}},' +
    '"fileColoring":[{"name":"G","mask":"*.g","normal":{"fg":"@cursor.bg"}}]}', Doc, Err), Err);
  Spec := ResolveThemeSpec([Doc]);
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF000011), Spec.Colors[trCursorFg], 'a reference follows another role');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FFAA0000), Spec.Colors[trStatusBg]);
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FFAA0000), Spec.Colors[trEditorSelBg], 'and its fallbacks follow it too');
  Assert.AreEqual<TAlphaColor>(TAlphaColor(0), Spec.Colors[trScrollFg], 'a loop resolves to nothing');
  Assert.AreEqual<TAlphaColor>(TAlphaColor(0), Spec.Colors[trTabActiveFg], 'an unknown role resolves to nothing');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FFAA0000), Spec.MdFg[mskLink], 'Markdown follows a role');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FFAA0000), Spec.FileColoring[0].Colors[ccsNormal].Fg,
    'file coloring follows a role');

  // A reference survives the file round trip; an edit that follows it is text.
  Assert.IsTrue(TryParseThemeDoc(ThemeDocToJson(Doc), Doc, Err), Err);
  Assert.AreEqual('@cursor.bg', Doc.Colors[trStatusBg].Ref);
  Assert.IsTrue(ThemeSlotFromText('@cursor.bg', Slot));
  Assert.IsFalse(ThemeSlotFromText('@no.such', Slot));
  Assert.IsTrue(ThemeSlotFromText('#112233', Slot) and (Slot.Ref = ''));
  Assert.IsTrue(ThemeSlotFromText('accent', Slot) and (Slot.Ref = 'accent'));
  Assert.IsFalse(ThemeSlotFromText('not a color', Slot));
end;

procedure TTestThemeSpec.TestPaletteBoundWhereWritten;
var
  Base, Child: TThemeDoc;
  Spec: TThemeSpec;
  Err: string;
begin
  Assert.IsTrue(TryParseThemeDoc('{"palette":{"hot":"#111111"},"colors":{"window":{"fg":"hot"}}}', Base, Err), Err);
  Assert.IsTrue(TryParseThemeDoc('{"extends":"b","palette":{"hot":"#222222","own":"#333333"},' +
    '"colors":{"window":{"bg":"hot"},"cursor":{"bg":"own"}}}', Child, Err), Err);
  Spec := ResolveThemeSpec([Base, Child]);
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF111111), Spec.Colors[trWindowFg],
    'a name a base uses keeps the base''s value');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF222222), Spec.Colors[trWindowBg], 'the descendant''s own use');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF333333), Spec.Colors[trCursorBg]);

  // A descendant can use a name only its base defines.
  Assert.IsTrue(TryParseThemeDoc('{"colors":{"window":{"bg":"hot"}}}', Child, Err), Err);
  Spec := ResolveThemeSpec([Base, Child]);
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF111111), Spec.Colors[trWindowBg], 'palette names are inherited');
end;

procedure TTestThemeSpec.TestMarkdownFollowsText;
var
  Doc: TThemeDoc;
  Spec: TThemeSpec;
  Err: string;
begin
  Assert.IsTrue(TryParseThemeDoc(
    '{"colors":{"window":{"fg":"#010101","bg":"#020202"}},' +
    '"markdown":{"text":{"fg":"#030303","bg":"#040404"},"link":{"attrs":["underline"]},' +
    '"inlineCode":{"bg":"#050505"}}}', Doc, Err), Err);
  Spec := ResolveThemeSpec([Doc]);
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF040404), Spec.MdBg[mskBold], 'an element takes the document background');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF030303), Spec.MdFg[mskBold], 'and the document text color');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF050505), Spec.MdBg[mskInlineCode], 'unless it has its own');
  Assert.IsTrue(Spec.MdAttrs[mskLink] = [ccaUnderline]);
  Assert.IsTrue(Spec.MdAttrs[mskBold] = [], 'no attributes unless the theme gives them');
  Doc.MdBg[mskText] := Default(TThemeColorSlot);
  Doc.MdFg[mskText] := Default(TThemeColorSlot);
  Spec := ResolveThemeSpec([Doc]);
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF020202), Spec.MdBg[mskBold], 'the window colors when the text sets none');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF010101), Spec.MdFg[mskBold]);
end;

procedure TTestThemeSpec.TestMultipleBases;
var
  Cfg: TTempConfig;
  A, B, C: TThemeDoc;
  Err, Warning: string;
  Spec: TThemeSpec;
  Chain: TArray<TThemeDoc>;
begin
  Cfg := TTempConfig.Create;
  try
    A := DocWith('NDN');
    A.Name := 'Piece A';
    SetColor(A, trCursorBg, TAlphaColor($FF0000AA));
    SetColor(A, trWindowBg, TAlphaColor($FF00AA00));
    Assert.IsTrue(SaveUserTheme(A, Err), Err);
    B := DocWith('NDN');
    B.Name := 'Piece B';
    SetColor(B, trCursorBg, TAlphaColor($FFAA0000));
    Assert.IsTrue(SaveUserTheme(B, Err), Err);

    C := DocWith('');
    C.Name := 'Both';
    C.Extends := ['Piece A', 'Piece B'];
    SetColor(C, trScrollFg, TAlphaColor($FF123456));
    Chain := LoadBaseChain(C, Warning);
    Assert.AreEqual('', Warning);
    // NDN is a base of both pieces but counts once, where it came last.
    Assert.AreEqual(3, Integer(Length(Chain)));
    Assert.AreEqual('NDN', Chain[0].Id);
    Assert.AreEqual('Piece A', Chain[1].Id);
    Assert.AreEqual('Piece B', Chain[2].Id);
    Assert.IsTrue(SaveUserTheme(C, Err), Err);
    Assert.IsTrue(TryLoadThemeSpec('Both', Spec));
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FFAA0000), Spec.Colors[trCursorBg], 'the later base wins');
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF00AA00), Spec.Colors[trWindowBg], 'what only the earlier one sets');
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF123456), Spec.Colors[trScrollFg], 'the theme itself wins over all');
    Assert.AreEqual('Piece A; Piece B', ThemeExtendsText(C.Extends));

    // A list in the file, and one written back.
    Assert.IsTrue(TryParseThemeDoc(ThemeDocToJson(C), A, Err), Err);
    Assert.AreEqual(2, Integer(Length(A.Extends)));
    Assert.AreEqual('Piece B', A.Extends[1]);
    Assert.AreEqual('x;y', ThemeExtendsText(ThemeParseExtends('x, y')).Replace(' ', ''));
  finally
    Cfg.Free;
  end;
end;

procedure TTestThemeSpec.TestColoringDiffAndOrder;
var
  Base, Edited, Changes, Merged: TArray<TColorCodingGroup>;
  Order: TArray<string>;
  G: TColorCodingGroup;
  Doc: TThemeDoc;
  Spec: TThemeSpec;

  function Group(const AName, AMask: string; AFg: TAlphaColor): TColorCodingGroup;
  begin
    Result := Default(TColorCodingGroup);
    Result.Name := AName;
    Result.Masks := [AMask];
    Result.Enabled := True;
    Result.Colors[ccsNormal].Fg := AFg;
  end;

begin
  Base := [Group('A', '*.a', $FF111111), Group('B', '*.b', $FF222222), Group('C', '*.c', $FF333333)];

  // Nothing changed: nothing is stored.
  ColorCodingDiff(Base, Base, Changes, Order);
  Assert.AreEqual(0, Integer(Length(Changes)));
  Assert.AreEqual(0, Integer(Length(Order)));

  // One changed, one new, one dropped, and the order changed.
  Edited := [Group('N', '*.n', $FF444444), Group('C', '*.c', $FF333333), Group('B', '*.b', $FF999999)];
  ColorCodingDiff(Base, Edited, Changes, Order);
  Assert.AreEqual(3, Integer(Length(Changes)), 'B changed, N new, A switched off');
  Assert.AreEqual(3, Integer(Length(Order)));
  Merged := MergeColorCodingGroups(Base, Changes);
  ColorCodingApplyOrder(Merged, Order);
  Assert.AreEqual('N', Merged[0].Name);
  Assert.AreEqual('C', Merged[1].Name);
  Assert.AreEqual('B', Merged[2].Name);
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF999999), Merged[2].Colors[ccsNormal].Fg, 'the changed group');
  Assert.AreEqual('A', Merged[3].Name, 'a dropped group stays, switched off');
  Assert.IsFalse(Merged[3].Enabled);

  // The same through a theme file: only the difference is written.
  Doc := DocWith('');
  Doc.HasFileColoring := True;
  Doc.FileColoring := Changes;
  Doc.FileColoringOrder := Order;
  Assert.IsTrue(TryParseThemeDoc(ThemeDocToJson(Doc), Doc, Order[0]), Order[0]);
  Assert.AreEqual(3, Integer(Length(Doc.FileColoringOrder)));
  G := Group('Z', '*.z', 0);
  G.Colors[ccsNormal].FgRef := '@cursor.bg';
  Assert.AreEqual('@cursor.bg', ColorCodingColorText(0, G.Colors[ccsNormal].FgRef));
  Assert.AreEqual('#112233', ColorCodingColorText($FF112233, ''));
  Assert.IsFalse(ColorCodingGroupSame(Base[0], Base[1]));
  Assert.IsTrue(ColorCodingGroupSame(Base[0], Base[0]));
  Spec := ResolveThemeSpec([]);
  Assert.AreEqual(0, Integer(Length(Spec.FileColoring)));
end;

procedure TTestThemeSpec.TestNewerSchemaIsRefused;
var
  Doc: TThemeDoc;
  Err: string;
begin
  Assert.IsFalse(TryParseThemeDoc('{"schema": 99}', Doc, Err));
  Assert.IsTrue(Err <> '');
  Assert.IsFalse(TryParseThemeDoc('[1,2]', Doc, Err));
  Assert.IsFalse(TryParseThemeDoc('not json', Doc, Err));
  Assert.IsTrue(TryParseThemeDoc('{}', Doc, Err), 'an empty theme is valid');
end;

procedure TTestThemeSpec.TestFrameSets;
var
  Doc: TThemeDoc;
  Spec: TThemeSpec;
  Err: string;
begin
  Assert.IsTrue(TryParseThemeDoc(
    '{"frames":{"window":"mine","dialog":"double","panelActive":"nosuch","panelIdle":"ascii"},' +
    '"frameSets":{"mine":{"tl":"1","tr":"2","bl":"3","br":"4","h":"5","v":"6"}}}', Doc, Err));
  Spec := ResolveThemeSpec([Doc]);
  Assert.AreEqual('1', string(Spec.Frames[tfsWindow].TL));
  Assert.AreEqual('6', string(Spec.Frames[tfsWindow].V));
  Assert.AreEqual(string(#$2554), string(Spec.Frames[tfsDialog].TL));
  Assert.AreEqual('single', Spec.FrameNames[tfsPanelActive], 'an unknown set becomes single');
  Assert.AreEqual('+', string(Spec.Frames[tfsPanelIdle].TL));
  Assert.IsTrue(Spec.DoubleActivePanel, 'active and idle panel frames differ');

  Doc.Frames[tfsPanelActive].Value := 'ascii';
  Spec := ResolveThemeSpec([Doc]);
  Assert.IsFalse(Spec.DoubleActivePanel, 'same set for both');
  Doc.DoubleActivePanel := ttsTrue;
  Spec := ResolveThemeSpec([Doc]);
  Assert.IsTrue(Spec.DoubleActivePanel, 'explicit option wins');
end;

procedure TTestThemeSpec.TestFileColoringMerges;
var
  Base, Child: TThemeDoc;
  Spec: TThemeSpec;
  G: TColorCodingGroup;
begin
  Base := DocWith('');
  G.Name := 'A';
  G.Masks := ['*.a'];
  G.Enabled := True;
  G.ApplyTo := ccaFilesAndDirs;
  G.Colors[ccsNormal].Fg := TAlphaColor($FF111111);
  G.Colors[ccsSelected].Fg := 0;
  G.Colors[ccsCurrent].Fg := 0;
  Base.HasFileColoring := True;
  Base.FileColoring := [G];
  Child := DocWith('p');
  Child.HasFileColoring := True;
  G.Colors[ccsNormal].Fg := TAlphaColor($FF222222);
  Child.FileColoring := [G];
  G.Name := 'B';
  G.Masks := ['*.b'];
  Child.FileColoring := Child.FileColoring + [G];
  Spec := ResolveThemeSpec([Base, Child]);
  Assert.AreEqual(2, Integer(Length(Spec.FileColoring)), 'same name replaced, new name added');
  Assert.AreEqual<TAlphaColor>(TAlphaColor($FF222222), Spec.FileColoring[1].Colors[ccsNormal].Fg);
end;

procedure TTestThemeSpec.TestBuiltInsLoad;
var
  Infos: TArray<TThemeInfo>;
  Info: TThemeInfo;
  Spec: TThemeSpec;
  Builtin: Integer;
begin
  Infos := GetAvailableThemes;
  Builtin := 0;
  for Info in Infos do
    if Info.BuiltIn then
    begin
      Inc(Builtin);
      Assert.IsTrue(TryLoadThemeSpec(Info.Id, Spec), Info.Id);
      Assert.IsTrue(Info.DisplayName <> '', Info.Id + ' has a name');
      Assert.IsTrue(Spec.BuiltIn, Info.Id);
      Assert.IsTrue(Length(Spec.FileColoring) > 0, Info.Id + ' inherits the file coloring');
    end;
  Assert.AreEqual(8, Builtin);
  Assert.AreEqual('NDN', Infos[0].Id, 'the classic theme comes first');
  Assert.AreEqual('NDN', DefaultThemeId);
end;

procedure TTestThemeSpec.TestBuiltInLooks;
type
  TLook = record
    Id: string;
    Desktop: TAlphaColor;
    WindowTL: Char;
    DoubleActive: Boolean;
  end;
const
  cLooks: array[0..7] of TLook = (
    (Id: 'NDN'; Desktop: $FF000000; WindowTL: #$2554; DoubleActive: True),
    (Id: 'ModernUnicode'; Desktop: $FF11111B; WindowTL: #$250C; DoubleActive: False),
    (Id: 'ASCII'; Desktop: $FF000000; WindowTL: '+'; DoubleActive: False),
    (Id: 'TotalCommander'; Desktop: $FF404040; WindowTL: #$2554; DoubleActive: True),
    (Id: 'SolarizedDark'; Desktop: $FF002B36; WindowTL: #$250C; DoubleActive: False),
    (Id: 'Dracula'; Desktop: $FF282A36; WindowTL: #$250C; DoubleActive: False),
    (Id: 'Nord'; Desktop: $FF2E3440; WindowTL: #$250C; DoubleActive: False),
    (Id: 'HighContrast'; Desktop: $FF000000; WindowTL: #$2554; DoubleActive: True));
var
  I: Integer;
  Spec: TThemeSpec;
  Theme: IThemeRenderer;
begin
  for I := 0 to High(cLooks) do
  begin
    Assert.IsTrue(TryLoadThemeSpec(cLooks[I].Id, Spec), cLooks[I].Id);
    Assert.AreEqual<TAlphaColor>(cLooks[I].Desktop, Spec.Colors[trDesktopBg], cLooks[I].Id + ' desktop');
    Assert.AreEqual(string(cLooks[I].WindowTL), string(Spec.Frames[tfsWindow].TL), cLooks[I].Id + ' window frame');
    Theme := CreateThemeByName(cLooks[I].Id);
    Assert.AreEqual(cLooks[I].DoubleActive, Theme.UsesDoubleLineForActivePanel, cLooks[I].Id + ' panel frame');
    Assert.AreEqual<TAlphaColor>(cLooks[I].Desktop, Theme.DesktopColor, cLooks[I].Id);
  end;
end;

procedure TTestThemeSpec.TestUnknownThemeFallsBack;
var
  Spec: TThemeSpec;
  Theme, Classic: IThemeRenderer;
begin
  Assert.IsFalse(TryLoadThemeSpec('no such theme', Spec));
  Assert.IsFalse(ThemeExists(''));
  Theme := CreateThemeByName('no such theme');
  Classic := CreateThemeByName('NDN');
  Assert.AreEqual<TAlphaColor>(Classic.DesktopColor, Theme.DesktopColor, 'the classic Far theme stands in');
  Theme := CreateThemeByName('');
  Assert.AreEqual<TAlphaColor>(Classic.DesktopColor, Theme.DesktopColor);
end;

procedure TTestThemeSpec.TestThemeIdFromName;
begin
  Assert.AreEqual('My theme', ThemeIdFromName('  My theme '));
  Assert.AreEqual('a_b_c', ThemeIdFromName('a/b:c'));
  Assert.AreEqual('x', ThemeIdFromName('x..'));
  Assert.AreEqual('', ThemeIdFromName('   '));
  Assert.AreEqual('', ThemeIdFromName('CON'));
  Assert.AreEqual('', ThemeIdFromName('con'));
  Assert.AreEqual(64, Integer(Length(ThemeIdFromName(StringOfChar('q', 100)))));
  Assert.AreEqual('Тема', ThemeIdFromName('Тема'));
end;

procedure TTestThemeSpec.TestUserThemeRoundTrip;
var
  Cfg: TTempConfig;
  Doc, Loaded: TThemeDoc;
  Err: string;
  Infos: TArray<TThemeInfo>;
  Info: TThemeInfo;
  Found: Boolean;
  Spec: TThemeSpec;
begin
  Cfg := TTempConfig.Create;
  try
    Doc := DocWith('Nord');
    Doc.Name := 'Mine: one';
    SetColor(Doc, trWindowBg, TAlphaColor($FF102030));
    Assert.IsTrue(SaveUserTheme(Doc, Err), Err);
    Assert.AreEqual('Mine_ one', Doc.Id, 'the id is the file name');
    Assert.IsTrue(TFile.Exists(TPath.Combine(TPath.Combine(Cfg.Dir, 'themes'), 'Mine_ one.theme.json')));

    Found := False;
    Infos := GetAvailableThemes;
    for Info in Infos do
      if Info.Id = Doc.Id then
      begin
        Found := True;
        Assert.IsFalse(Info.BuiltIn);
        Assert.AreEqual('Mine: one', Info.DisplayName);
        Assert.AreEqual('Nord', Info.Extends);
      end;
    Assert.IsTrue(Found, 'listed');
    Assert.IsTrue(Infos[High(Infos)].Id = Doc.Id, 'user themes come after the built-in ones');

    Assert.IsTrue(TryLoadThemeDoc(Doc.Id, Loaded));
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF102030), Loaded.Colors[trWindowBg].Value);
    Assert.IsTrue(TryLoadThemeSpec(Doc.Id, Spec));
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF102030), Spec.Colors[trWindowBg], 'own value');
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF2E3440), Spec.Colors[trDesktopBg], 'from Nord');
    Assert.IsFalse(Spec.BuiltIn);

    Assert.IsTrue(DeleteUserTheme(Doc.Id));
    Assert.IsFalse(ThemeExists(Doc.Id));
  finally
    Cfg.Free;
  end;
end;

procedure TTestThemeSpec.TestBuiltInCannotBeOverwritten;
var
  Cfg: TTempConfig;
  Doc: TThemeDoc;
  Err: string;
begin
  Cfg := TTempConfig.Create;
  try
    Doc := DocWith('');
    Doc.Name := 'Hijack';
    Doc.Id := 'Nord';
    Assert.IsFalse(SaveUserTheme(Doc, Err));
    Assert.AreEqual('builtin', Err);
    Doc.Id := '';
    Doc.Name := 'nord';
    Assert.IsFalse(SaveUserTheme(Doc, Err), 'the id is compared without case');
    Doc.Name := '  ';
    Assert.IsFalse(SaveUserTheme(Doc, Err));
    Assert.AreEqual('name', Err);
    Assert.IsFalse(DeleteUserTheme('Nord'), 'a built-in theme is not deleted');
    Assert.IsTrue(ThemeExists('Nord'));
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(Cfg.Dir, 'themes')));
  finally
    Cfg.Free;
  end;
end;

procedure TTestThemeSpec.TestMissingAndCircularBases;
var
  Cfg: TTempConfig;
  A, B, C: TThemeDoc;
  Err, Warning: string;
  Spec: TThemeSpec;
  Chain: TArray<TThemeDoc>;
begin
  Cfg := TTempConfig.Create;
  try
    A := DocWith('gone');
    A.Name := 'Orphan';
    SetColor(A, trCursorBg, TAlphaColor($FF0000FF));
    Assert.IsTrue(SaveUserTheme(A, Err), Err);
    Chain := LoadBaseChain(A, Warning);
    Assert.AreEqual('gone', Warning, 'the missing base is reported');
    Assert.AreEqual(1, Integer(Length(Chain)));
    Assert.AreEqual('NDN', Chain[0].Id, 'the default theme stands in');
    Assert.IsTrue(TryLoadThemeSpec('Orphan', Spec), 'the theme still loads');
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF0000FF), Spec.Colors[trCursorBg]);
    Assert.AreNotEqual<TAlphaColor>(0, Spec.Colors[trWindowBg]);

    B := DocWith('Loop B');
    B.Name := 'Loop A';
    Assert.IsTrue(SaveUserTheme(B, Err), Err);
    C := DocWith('Loop A');
    C.Name := 'Loop B';
    Assert.IsTrue(SaveUserTheme(C, Err), Err);
    Assert.IsTrue(TryLoadThemeSpec('Loop A', Spec), 'a cycle does not hang or fail');
    Assert.AreNotEqual<TAlphaColor>(0, Spec.Colors[trWindowBg]);
  finally
    Cfg.Free;
  end;
end;

procedure TTestThemeSpec.TestRoleTitles;
var
  Role: TThemeColorRole;
  Other: TThemeColorRole;
  Attr: TThemeAttrSlot;
  Glyph: TThemeGlyph;
  Frame: TThemeFrameSlot;
  Kind: TMdSpanKind;
  EnRole: array[TThemeColorRole] of string;
  EnAttr: array[TThemeAttrSlot] of string;
  EnGlyph: array[TThemeGlyph] of string;
  EnFrame: array[TThemeFrameSlot] of string;
begin
  for Role := Low(TThemeColorRole) to High(TThemeColorRole) do
  begin
    EnRole[Role] := ThemeColorRoleTitle(Role);
    Assert.AreNotEqual('', ThemeColorRoleTitle(Role), ThemeColorRoleKey(Role));
    for Other := Succ(Role) to High(TThemeColorRole) do
      if ThemeColorRoleSection(Role) = ThemeColorRoleSection(Other) then
        Assert.AreNotEqual(ThemeColorRoleTitle(Role), ThemeColorRoleTitle(Other),
        'titles of ' + ThemeColorRoleKey(Role) + ' and ' + ThemeColorRoleKey(Other));
  end;
  for Attr := Low(TThemeAttrSlot) to High(TThemeAttrSlot) do
  begin
    EnAttr[Attr] := ThemeAttrSlotTitle(Attr);
    Assert.AreNotEqual('', EnAttr[Attr]);
  end;
  for Glyph := Low(TThemeGlyph) to High(TThemeGlyph) do
  begin
    EnGlyph[Glyph] := ThemeGlyphTitle(Glyph);
    Assert.AreNotEqual('', EnGlyph[Glyph]);
  end;
  for Frame := Low(TThemeFrameSlot) to High(TThemeFrameSlot) do
  begin
    EnFrame[Frame] := ThemeFrameSlotTitle(Frame);
    Assert.AreNotEqual('', EnFrame[Frame]);
  end;
  for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
    Assert.AreNotEqual('', ThemeMdKindTitle(Kind));

  // Every title has a Russian translation in the embedded strings.
  SetLocale('ru');
  try
    for Role := Low(TThemeColorRole) to High(TThemeColorRole) do
      Assert.AreNotEqual(EnRole[Role], ThemeColorRoleTitle(Role), ThemeColorRoleKey(Role));
    for Attr := Low(TThemeAttrSlot) to High(TThemeAttrSlot) do
      Assert.AreNotEqual(EnAttr[Attr], ThemeAttrSlotTitle(Attr), ThemeAttrSlotKey(Attr));
    for Glyph := Low(TThemeGlyph) to High(TThemeGlyph) do
      Assert.AreNotEqual(EnGlyph[Glyph], ThemeGlyphTitle(Glyph), ThemeGlyphKey(Glyph));
    for Frame := Low(TThemeFrameSlot) to High(TThemeFrameSlot) do
      Assert.AreNotEqual(EnFrame[Frame], ThemeFrameSlotTitle(Frame), ThemeFrameSlotKey(Frame));
  finally
    SetLocale('');
  end;
end;

procedure TTestThemeSpec.TestLegacyColoringImport;
var
  Cfg: TTempConfig;
  NewId: string;
  Doc: TThemeDoc;
  Legacy, LegacyMd: string;
  Spec: TThemeSpec;
begin
  Cfg := TTempConfig.Create;
  try
    Assert.IsFalse(ImportLegacyFiles('Nord', '', NewId), 'nothing to import');
    Legacy := TPath.Combine(Cfg.Dir, 'NDNtheme.json');
    LegacyMd := TPath.Combine(Cfg.Dir, 'markdown-colors.json');
    TFile.WriteAllText(Legacy,
      '{"fileColoring":[{"name":"Mine","mask":"*.zzz","normal":{"fg":"#FF0000"}}]}', TEncoding.UTF8);
    TFile.WriteAllText(LegacyMd,
      '{"styles":{"h1":{"fg":"#00FF00","style":["bold","underline"]}}}', TEncoding.UTF8);
    Assert.IsTrue(ImportLegacyFiles('Nord', '', NewId));
    Assert.IsTrue(ThemeExists(NewId));
    Assert.IsTrue(TryLoadThemeDoc(NewId, Doc));
    Assert.AreEqual('Nord', ThemeExtendsText(Doc.Extends));
    Assert.AreEqual(1, Integer(Length(Doc.FileColoring)));
    Assert.AreEqual('Mine', Doc.FileColoring[0].Name);
    Assert.IsTrue(Doc.MdFg[mskH1].Has, 'the Markdown colors come along');
    Assert.IsTrue(TryLoadThemeSpec(NewId, Spec));
    Assert.AreEqual<TAlphaColor>(TAlphaColor($FF00FF00), Spec.MdFg[mskH1]);
    Assert.IsTrue(Spec.MdAttrs[mskH1] = [ccaBold, ccaUnderline]);
    Assert.IsFalse(TFile.Exists(Legacy), 'the old files are set aside');
    Assert.IsFalse(TFile.Exists(LegacyMd));
    Assert.IsTrue(TFile.Exists(Legacy + '.migrated'));
    Assert.IsTrue(TFile.Exists(LegacyMd + '.migrated'));
    Assert.IsFalse(ImportLegacyFiles('Nord', '', NewId), 'only once');
  finally
    Cfg.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestThemeSpec);

end.
