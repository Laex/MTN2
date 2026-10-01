unit uThemeSpec;

{ Data model of a theme file (*.theme.json) and its resolution.

  A theme file (TThemeDoc) lists only what it sets: colors by role, Markdown
  span styles, text attributes, glyph strings, frame glyph sets and the file
  coloring groups. Everything it leaves out comes from the themes it "extends";
  a chain of documents, bases first, is flattened by ResolveThemeSpec into a
  TThemeSpec that has a value for every role. A role nobody sets takes the
  value of its fallback role (TThemeColorRole table below), so a file can
  stay small: a theme that only changes the cursor colors still gets matching
  checkbox focus and editor selection colors.

  A color in a file is a "#RRGGBB" / "#AARRGGBB" literal, a name from the
  "palette" (merged along the whole extends chain, so a base theme's names are
  usable in its descendants), or "@role.key" - a reference to another role of
  the same theme, so a color can follow the theme instead of repeating a
  literal. A reference that cannot be resolved counts as not set. A resolved
  spec has plain colors.

  "extends" is one theme id or a list of ids; later bases override earlier
  ones, and the file overrides all of them, so a theme can be assembled from
  pieces (a palette theme plus a file-coloring theme plus a glyph theme).

  Top-level keys of a file: "schema" (2), "name", "extends", "palette"
  (name -> color), "colors" (group -> key -> color: the role "window.bg" is
  colors.window.bg), "markdown" (span kind -> fg / bg / attrs), "attrs"
  (slot -> list of attribute names), "glyphs" (key -> string), "frames"
  (slot -> frame set name), "frameSets" (name -> tl, tr, bl, br, h, v),
  "options" (doubleActivePanel), "fileColoring" (the color coding groups of
  uColorCoding that this theme adds or changes, merged over its bases by
  name) and "fileColoringOrder" (group names that go first, in that order). }

interface

uses
  System.SysUtils, System.UITypes,
  uTerminalTypes, uThemeTypes, uColorCoding, uMarkdownColors;

type
  /// <summary>Every color a theme decides. The dotted key of a role (the
  /// role table below) names its JSON path.</summary>
  TThemeColorRole = (
    trDesktopBg,
    trWindowFg, trWindowBg, trBorderFocus, trBorderNormal,
    trTitleFgFocus, trTitleBgFocus, trTitleFgNormal, trTitleBgNormal,
    trCloseAccent,
    trDialogFg, trDialogBg, trDialogBorder, trDialogHotFg,
    trDialogTitleFg, trDialogTitleBg,
    trDialogRowFg, trDialogRowBg, trDialogRowCursorFg, trDialogRowCursorBg,
    trButtonFg, trButtonBg, trButtonFocusFg, trButtonFocusBg,
    trButtonHotFg, trButtonHotFocusFg,
    trCheckFg, trCheckBg, trCheckHotFg,
    trCheckFocusFg, trCheckFocusBg, trCheckFocusHotFg,
    trCursorFg, trCursorBg, trCursorIdleBg, trCursorHotFg,
    trCursorMarkedFg, trCursorMarkedBg,
    trMarkFg, trMarkBg, trMarkBandFg, trMarkBandBg,
    trFileDir, trFileArchive, trFileExecutable, trFileMedia, trFilePlain,
    trFileHidden, trFileHiddenDir, trFileHiddenArchive, trFileHiddenExecutable,
    trFileHiddenMedia, trFileHiddenPlain,
    trStatusFg, trStatusBg, trStatusSeparator,
    trToolFg, trToolBg, trToolKeyFg,
    trMenuFg, trMenuBg, trMenuHotFg, trClockFg,
    trTabActiveFg, trTabActiveBg, trTabNormalFg, trTabNormalBg,
    trPanelTabBarBg, trPanelTabActiveFg, trPanelTabActiveBg, trPanelTabNormalFg,
    trPanelHeaderFg, trPanelHeaderBg, trPanelHotMark, trPanelCloseMark,
    trScrollFg, trScrollThumb,
    trEditorBodyFg, trEditorBodyBg, trEditorCursorFg, trEditorCursorBg,
    trEditorSelFg, trEditorSelBg, trEditorHintFg,
    trEditorStatusFg, trEditorStatusBg, trEditorFrameFocus, trEditorFrameIdle,
    trEditorScrollFg, trEditorScrollThumb, trEditorMatchFg, trEditorMatchBg);

  /// <summary>Text attributes a theme applies to a kind of chrome text.</summary>
  TThemeAttrSlot = (
    tasWindowTitle, tasDialogTitle, tasButton, tasCheck, tasTab,
    tasToolbar, tasToolbarKey, tasStatus, tasMenu, tasMenuHot, tasClock,
    tasHot, tasHotFocus);

  /// <summary>Strings a theme draws with: marks, caption templates and the
  /// single glyphs of the close button, scrollbar and desktop.</summary>
  TThemeGlyph = (
    tgCheckOn, tgCheckOff, tgRadioOn, tgRadioOff,
    tgButtonNormal, tgButtonDefault, tgTabWorkspace, tgTabPanel,
    tgStatusSeparator, tgCloseLeft, tgCloseMark, tgCloseRight, tgDesktopFill,
    tgScrollUp, tgScrollDown, tgScrollLeft, tgScrollRight,
    tgScrollShade, tgScrollBlock);

  /// <summary>Where a frame glyph set is used.</summary>
  TThemeFrameSlot = (tfsWindow, tfsDialog, tfsPanelActive, tfsPanelIdle);

  TThemeTriState = (ttsUnset, ttsFalse, ttsTrue);

  /// <summary>Corner and edge glyphs of a box frame.</summary>
  TThemeFrameSet = record
    TL, TR, BL, BR, H, V: Char;
  end;

  /// <summary>A color a file sets: a literal (Ref = '') or a reference
  /// ("@role.key", a palette name) that is resolved with the whole theme.</summary>
  TThemeColorSlot = record
    Has: Boolean;
    Value: TAlphaColor;
    Ref: string;
  end;

  TThemeStringSlot = record
    Has: Boolean;
    Value: string;
  end;

  TThemeAttrValue = record
    Has: Boolean;
    Value: TCharCellAttributes;
  end;

  TThemePaletteEntry = record
    Name: string;
    Color: TAlphaColor;
  end;

  TThemeNamedFrameSet = record
    Name: string;
    Glyphs: TThemeFrameSet;
  end;

  /// <summary>One theme file as written: only what the file sets.</summary>
  TThemeDoc = record
    /// <summary>Stable id: the built-in id, or the file name without
    /// ".theme.json". Not stored in the file.</summary>
    Id: string;
    Name: string;
    /// <summary>Ids of the themes this one builds on, later ones overriding
    /// earlier; none = the default theme.</summary>
    Extends: TArray<string>;
    Palette: TArray<TThemePaletteEntry>;
    Colors: array[TThemeColorRole] of TThemeColorSlot;
    MdFg, MdBg: array[TMdSpanKind] of TThemeColorSlot;
    MdAttrs: array[TMdSpanKind] of TThemeAttrValue;
    Attrs: array[TThemeAttrSlot] of TThemeAttrValue;
    Glyphs: array[TThemeGlyph] of TThemeStringSlot;
    Frames: array[TThemeFrameSlot] of TThemeStringSlot;
    FrameSets: TArray<TThemeNamedFrameSet>;
    DoubleActivePanel: TThemeTriState;
    HasFileColoring: Boolean;
    /// <summary>The groups this theme adds or changes (a merge over its bases).</summary>
    FileColoring: TArray<TColorCodingGroup>;
    /// <summary>Names of groups that go first, in this order (after the merge).</summary>
    FileColoringOrder: TArray<string>;
  end;

  /// <summary>A theme with a value for everything.</summary>
  TThemeSpec = record
    Id: string;
    Name: string;
    BuiltIn: Boolean;
    /// <summary>The palette merged along the chain.</summary>
    Palette: TArray<TThemePaletteEntry>;
    Colors: array[TThemeColorRole] of TAlphaColor;
    MdFg, MdBg: array[TMdSpanKind] of TAlphaColor;
    MdAttrs: array[TMdSpanKind] of TCharCellAttributes;
    Attrs: array[TThemeAttrSlot] of TCharCellAttributes;
    Glyphs: array[TThemeGlyph] of string;
    Frames: array[TThemeFrameSlot] of TThemeFrameSet;
    FrameNames: array[TThemeFrameSlot] of string;
    /// <summary>The named sets the theme defines itself (the built-in
    /// names need no entry).</summary>
    FrameSets: TArray<TThemeNamedFrameSet>;
    DoubleActivePanel: Boolean;
    FileColoring: TArray<TColorCodingGroup>;
  end;

const
  cThemeSchemaVersion = 2;
  cThemeFileExt = '.theme.json';
  cFrameSingle = 'single';
  cFrameDouble = 'double';
  cFrameAscii = 'ascii';
  cFrameRounded = 'rounded';
  cFrameHeavy = 'heavy';

/// <summary>Dotted key of a role ("window.bg").</summary>
function ThemeColorRoleKey(ARole: TThemeColorRole): string;
/// <summary>Section of a role: the part of the key before the dot.</summary>
function ThemeColorRoleSection(ARole: TThemeColorRole): string;
/// <summary>The role ARole takes its value from when no file sets it; False
/// for a role the base theme must set itself.</summary>
function ThemeColorRoleFallback(ARole: TThemeColorRole; out AFallback: TThemeColorRole): Boolean;
/// <summary>The role with the dotted key AKey ("window.bg").</summary>
function ThemeColorRoleByKey(const AKey: string; out ARole: TThemeColorRole): Boolean;
function ThemeAttrSlotKey(ASlot: TThemeAttrSlot): string;
function ThemeGlyphKey(AGlyph: TThemeGlyph): string;
function ThemeFrameSlotKey(ASlot: TThemeFrameSlot): string;
/// <summary>Sections of the color roles in table order, each once.</summary>
function ThemeColorSections: TArray<string>;

/// <summary>Names of the built-in frame glyph sets.</summary>
function BuiltInFrameSetNames: TArray<string>;
function BuiltInFrameSet(const AName: string; out ASet: TThemeFrameSet): Boolean;

/// <summary>"#RRGGBB", or "#AARRGGBB" when the color is not opaque.</summary>
function ThemeColorToText(AColor: TAlphaColor): string;
/// <summary>"#RRGGBB" (opaque) or "#AARRGGBB".</summary>
function TryParseThemeColor(const AText: string; out AColor: TAlphaColor): Boolean;

/// <summary>What a slot shows: its reference, or its color as text; '' when unset.</summary>
function ThemeSlotText(const ASlot: TThemeColorSlot): string;
procedure ThemeSlotSetColor(var ASlot: TThemeColorSlot; AColor: TAlphaColor);
procedure ThemeSlotSetRef(var ASlot: TThemeColorSlot; const ARef: string);
/// <summary>Text typed for a color: a literal ("#RRGGBB", "RRGGBB",
/// "#AARRGGBB") or a reference ("@role.key" with a known role, or a palette
/// name). False for anything else.</summary>
function ThemeSlotFromText(const AText: string; out ASlot: TThemeColorSlot): Boolean;
function ThemeExtendsText(const AExtends: TArray<string>): string;
/// <summary>Ids separated by ',' or ';'.</summary>
function ThemeParseExtends(const AText: string): TArray<string>;

function ThemeAttrsToNames(AAttrs: TCharCellAttributes): TArray<string>;
function ThemeAttrsFromNames(const ANames: TArray<string>): TCharCellAttributes;

/// <summary>Parses the text of a theme file. False (with AError) when it is
/// not a JSON object or its schema is newer than this program understands;
/// single values that do not parse are left unset.</summary>
function TryParseThemeDoc(const AJson: string; out ADoc: TThemeDoc;
  out AError: string): Boolean;
/// <summary>The file text of ADoc: only the slots it sets.</summary>
function ThemeDocToJson(const ADoc: TThemeDoc): string;

/// <summary>Flattens a chain of documents (bases first, the theme itself
/// last) into a spec.</summary>
function ResolveThemeSpec(const AChain: TArray<TThemeDoc>): TThemeSpec;
/// <summary>A document that sets every slot to ASpec's value and extends
/// nothing - a standalone copy of the spec.</summary>
function ThemeDocFromSpec(const ASpec: TThemeSpec): TThemeDoc;

/// <summary>The Markdown styles ADoc sets, as the color set the Markdown
/// colors dialog edits; the colors are the resolved ones of ASpec.</summary>
function ThemeDocMdSet(const ADoc: TThemeDoc; const ASpec: TThemeSpec): TMdColorSet;
/// <summary>Writes into ADoc what the dialog changed: a channel whose value
/// is the same as in AInitial is left as it is (a reference stays one).</summary>
procedure ThemeDocApplyMdSet(var ADoc: TThemeDoc; const AInitial, AEdited: TMdColorSet);

/// <summary>A caption template must contain the "{0}" placeholder.</summary>
function ThemeTemplateValid(const ATemplate: string): Boolean;
/// <summary>The template with the placeholder replaced by AText.</summary>
function ThemeApplyTemplate(const ATemplate, AText: string): string;

implementation

uses
  System.Classes, System.JSON, System.Generics.Collections, System.Math;

type
  TRoleDef = record
    Key: string;
    /// <summary>Ord of the fallback role, -1 = none.</summary>
    Fallback: Integer;
  end;

const
  cRoleDefs: array[TThemeColorRole] of TRoleDef = (
    (Key: 'desktop.bg'; Fallback: -1),
    (Key: 'window.fg'; Fallback: -1),
    (Key: 'window.bg'; Fallback: -1),
    (Key: 'window.borderFocus'; Fallback: -1),
    (Key: 'window.borderNormal'; Fallback: -1),
    (Key: 'window.titleFgFocus'; Fallback: -1),
    (Key: 'window.titleBgFocus'; Fallback: -1),
    (Key: 'window.titleFgNormal'; Fallback: -1),
    (Key: 'window.titleBgNormal'; Fallback: -1),
    (Key: 'window.closeAccent'; Fallback: -1),
    (Key: 'dialog.fg'; Fallback: -1),
    (Key: 'dialog.bg'; Fallback: -1),
    (Key: 'dialog.border'; Fallback: -1),
    (Key: 'dialog.hotFg'; Fallback: -1),
    (Key: 'dialog.titleFg'; Fallback: Ord(trTitleFgFocus)),
    (Key: 'dialog.titleBg'; Fallback: Ord(trTitleBgFocus)),
    (Key: 'dialog.rowFg'; Fallback: Ord(trDialogFg)),
    (Key: 'dialog.rowBg'; Fallback: Ord(trDialogBg)),
    (Key: 'dialog.rowCursorFg'; Fallback: Ord(trCursorFg)),
    (Key: 'dialog.rowCursorBg'; Fallback: Ord(trCursorBg)),
    (Key: 'button.fg'; Fallback: -1),
    (Key: 'button.bg'; Fallback: -1),
    (Key: 'button.focusFg'; Fallback: -1),
    (Key: 'button.focusBg'; Fallback: -1),
    (Key: 'button.hotFg'; Fallback: Ord(trDialogHotFg)),
    (Key: 'button.hotFocusFg'; Fallback: Ord(trButtonFocusFg)),
    (Key: 'check.fg'; Fallback: Ord(trDialogFg)),
    (Key: 'check.bg'; Fallback: Ord(trDialogBg)),
    (Key: 'check.hotFg'; Fallback: Ord(trDialogHotFg)),
    (Key: 'check.focusFg'; Fallback: Ord(trCursorFg)),
    (Key: 'check.focusBg'; Fallback: Ord(trCursorBg)),
    (Key: 'check.focusHotFg'; Fallback: Ord(trCursorHotFg)),
    (Key: 'cursor.fg'; Fallback: -1),
    (Key: 'cursor.bg'; Fallback: -1),
    (Key: 'cursor.idleBg'; Fallback: -1),
    (Key: 'cursor.hotFg'; Fallback: Ord(trCursorFg)),
    (Key: 'cursor.markedFg'; Fallback: Ord(trCursorFg)),
    (Key: 'cursor.markedBg'; Fallback: Ord(trCursorBg)),
    (Key: 'mark.fg'; Fallback: -1),
    (Key: 'mark.bg'; Fallback: Ord(trWindowBg)),
    (Key: 'mark.bandFg'; Fallback: Ord(trMarkFg)),
    (Key: 'mark.bandBg'; Fallback: -1),
    (Key: 'file.dir'; Fallback: -1),
    (Key: 'file.archive'; Fallback: -1),
    (Key: 'file.executable'; Fallback: -1),
    (Key: 'file.media'; Fallback: -1),
    (Key: 'file.plain'; Fallback: Ord(trWindowFg)),
    (Key: 'file.hidden'; Fallback: -1),
    (Key: 'file.hiddenDir'; Fallback: Ord(trFileHidden)),
    (Key: 'file.hiddenArchive'; Fallback: Ord(trFileHidden)),
    (Key: 'file.hiddenExecutable'; Fallback: Ord(trFileHidden)),
    (Key: 'file.hiddenMedia'; Fallback: Ord(trFileHidden)),
    (Key: 'file.hiddenPlain'; Fallback: Ord(trFileHidden)),
    (Key: 'status.fg'; Fallback: -1),
    (Key: 'status.bg'; Fallback: -1),
    (Key: 'status.separator'; Fallback: Ord(trStatusFg)),
    (Key: 'toolbar.fg'; Fallback: -1),
    (Key: 'toolbar.bg'; Fallback: -1),
    (Key: 'toolbar.keyFg'; Fallback: -1),
    (Key: 'menu.fg'; Fallback: Ord(trStatusFg)),
    (Key: 'menu.bg'; Fallback: Ord(trStatusBg)),
    (Key: 'menu.hotFg'; Fallback: Ord(trToolKeyFg)),
    (Key: 'menu.clockFg'; Fallback: Ord(trMenuFg)),
    (Key: 'tab.activeFg'; Fallback: -1),
    (Key: 'tab.activeBg'; Fallback: -1),
    (Key: 'tab.normalFg'; Fallback: -1),
    (Key: 'tab.normalBg'; Fallback: -1),
    (Key: 'panel.tabBarBg'; Fallback: Ord(trWindowBg)),
    (Key: 'panel.tabActiveFg'; Fallback: -1),
    (Key: 'panel.tabActiveBg'; Fallback: -1),
    (Key: 'panel.tabNormalFg'; Fallback: -1),
    (Key: 'panel.headerFg'; Fallback: -1),
    (Key: 'panel.headerBg'; Fallback: Ord(trWindowBg)),
    (Key: 'panel.hotMark'; Fallback: Ord(trToolKeyFg)),
    (Key: 'panel.closeMark'; Fallback: Ord(trCloseAccent)),
    (Key: 'scroll.fg'; Fallback: -1),
    (Key: 'scroll.thumb'; Fallback: -1),
    (Key: 'editor.bodyFg'; Fallback: Ord(trWindowFg)),
    (Key: 'editor.bodyBg'; Fallback: Ord(trWindowBg)),
    (Key: 'editor.cursorFg'; Fallback: Ord(trCursorFg)),
    (Key: 'editor.cursorBg'; Fallback: Ord(trCursorBg)),
    (Key: 'editor.selFg'; Fallback: Ord(trCursorFg)),
    (Key: 'editor.selBg'; Fallback: Ord(trCursorBg)),
    (Key: 'editor.hintFg'; Fallback: Ord(trToolKeyFg)),
    (Key: 'editor.statusFg'; Fallback: Ord(trStatusFg)),
    (Key: 'editor.statusBg'; Fallback: Ord(trStatusBg)),
    (Key: 'editor.frameFocus'; Fallback: Ord(trBorderFocus)),
    (Key: 'editor.frameIdle'; Fallback: Ord(trBorderNormal)),
    (Key: 'editor.scrollFg'; Fallback: Ord(trScrollFg)),
    (Key: 'editor.scrollThumb'; Fallback: Ord(trScrollThumb)),
    (Key: 'editor.matchFg'; Fallback: Ord(trCursorFg)),
    (Key: 'editor.matchBg'; Fallback: Ord(trCursorBg)));

  cAttrKeys: array[TThemeAttrSlot] of string = (
    'windowTitle', 'dialogTitle', 'button', 'check', 'tab',
    'toolbar', 'toolbarKey', 'status', 'menu', 'menuHot', 'clock',
    'hot', 'hotFocus');

  cGlyphKeys: array[TThemeGlyph] of string = (
    'checkOn', 'checkOff', 'radioOn', 'radioOff',
    'buttonNormal', 'buttonDefault', 'tabWorkspace', 'tabPanel',
    'statusSeparator', 'closeLeft', 'closeMark', 'closeRight', 'desktopFill',
    'scrollUp', 'scrollDown', 'scrollLeft', 'scrollRight',
    'scrollShade', 'scrollBlock');

  cGlyphDefaults: array[TThemeGlyph] of string = (
    '[x] ', '[ ] ', '(*) ', '( ) ',
    '[ {0} ]', '< {0} >', '[{0}]', ' {0} ',
    #$2502, '[', 'x', ']', ' ',
    #$25B2, #$25BC, #$25C4, #$25BA,
    #$2591, #$2588);

  cFrameKeys: array[TThemeFrameSlot] of string = (
    'window', 'dialog', 'panelActive', 'panelIdle');

  cPlaceholder = '{0}';

function ThemeColorRoleKey(ARole: TThemeColorRole): string;
begin
  Result := cRoleDefs[ARole].Key;
end;

function ThemeColorRoleSection(ARole: TThemeColorRole): string;
var
  Key: string;
  P: Integer;
begin
  Key := cRoleDefs[ARole].Key;
  P := Pos('.', Key);
  Result := Copy(Key, 1, P - 1);
end;

function ThemeColorRoleFallback(ARole: TThemeColorRole; out AFallback: TThemeColorRole): Boolean;
begin
  Result := cRoleDefs[ARole].Fallback >= 0;
  if Result then
    AFallback := TThemeColorRole(cRoleDefs[ARole].Fallback)
  else
    AFallback := ARole;
end;

function ThemeColorRoleByKey(const AKey: string; out ARole: TThemeColorRole): Boolean;
var
  R: TThemeColorRole;
begin
  for R := Low(TThemeColorRole) to High(TThemeColorRole) do
    if SameText(cRoleDefs[R].Key, AKey) then
    begin
      ARole := R;
      Exit(True);
    end;
  ARole := Low(TThemeColorRole);
  Result := False;
end;

function ThemeAttrSlotKey(ASlot: TThemeAttrSlot): string;
begin
  Result := cAttrKeys[ASlot];
end;

function ThemeGlyphKey(AGlyph: TThemeGlyph): string;
begin
  Result := cGlyphKeys[AGlyph];
end;

function ThemeFrameSlotKey(ASlot: TThemeFrameSlot): string;
begin
  Result := cFrameKeys[ASlot];
end;

function ThemeColorSections: TArray<string>;
var
  Role: TThemeColorRole;
  Sect: string;
begin
  SetLength(Result, 0);
  for Role := Low(TThemeColorRole) to High(TThemeColorRole) do
  begin
    Sect := ThemeColorRoleSection(Role);
    if (Length(Result) = 0) or (Result[High(Result)] <> Sect) then
      Result := Result + [Sect];
  end;
end;

function MakeFrameSet(ATL, ATR, ABL, ABR, AH, AV: Char): TThemeFrameSet;
begin
  Result.TL := ATL;
  Result.TR := ATR;
  Result.BL := ABL;
  Result.BR := ABR;
  Result.H := AH;
  Result.V := AV;
end;

function BuiltInFrameSetNames: TArray<string>;
begin
  Result := [cFrameSingle, cFrameDouble, cFrameAscii, cFrameRounded, cFrameHeavy];
end;

function BuiltInFrameSet(const AName: string; out ASet: TThemeFrameSet): Boolean;
begin
  Result := True;
  if SameText(AName, cFrameSingle) then
    ASet := MakeFrameSet(chBoxTL, chBoxTR, chBoxBL, chBoxBR, chBoxH, chBoxV)
  else if SameText(AName, cFrameDouble) then
    ASet := MakeFrameSet(chDblTL, chDblTR, chDblBL, chDblBR, chDblH, chDblV)
  else if SameText(AName, cFrameAscii) then
    ASet := MakeFrameSet('+', '+', '+', '+', '-', '|')
  else if SameText(AName, cFrameRounded) then
    ASet := MakeFrameSet(#$256D, #$256E, #$2570, #$256F, chBoxH, chBoxV)
  else if SameText(AName, cFrameHeavy) then
    ASet := MakeFrameSet(#$250F, #$2513, #$2517, #$251B, #$2501, #$2503)
  else
  begin
    Result := False;
    ASet := MakeFrameSet(chBoxTL, chBoxTR, chBoxBL, chBoxBR, chBoxH, chBoxV);
  end;
end;

function ThemeColorToText(AColor: TAlphaColor): string;
var
  Rec: TAlphaColorRec;
begin
  Rec := TAlphaColorRec(AColor);
  if Rec.A = $FF then
    Result := Format('#%.2X%.2X%.2X', [Rec.R, Rec.G, Rec.B])
  else
    Result := Format('#%.2X%.2X%.2X%.2X', [Rec.A, Rec.R, Rec.G, Rec.B]);
end;

function TryParseThemeColor(const AText: string; out AColor: TAlphaColor): Boolean;
var
  S: string;
  V: Cardinal;
  I: Integer;
begin
  Result := False;
  AColor := 0;
  S := Trim(AText);
  if (Length(S) > 0) and (S[1] = '#') then
    Delete(S, 1, 1);
  if (Length(S) <> 6) and (Length(S) <> 8) then
    Exit;
  V := 0;
  for I := 1 to Length(S) do
  begin
    if not CharInSet(S[I], ['0'..'9', 'a'..'f', 'A'..'F']) then
      Exit;
    V := (V shl 4) or Cardinal(StrToInt('$' + S[I]));
  end;
  if Length(S) = 6 then
    V := V or $FF000000;
  AColor := TAlphaColor(V);
  Result := True;
end;

function ThemeAttrsToNames(AAttrs: TCharCellAttributes): TArray<string>;
begin
  SetLength(Result, 0);
  if ccaBold in AAttrs then
    Result := Result + ['bold'];
  if ccaItalic in AAttrs then
    Result := Result + ['italic'];
  if ccaUnderline in AAttrs then
    Result := Result + ['underline'];
  if ccaStrike in AAttrs then
    Result := Result + ['strike'];
  if ccaBlink in AAttrs then
    Result := Result + ['blink'];
  if ccaReverse in AAttrs then
    Result := Result + ['reverse'];
end;

function ThemeAttrsFromNames(const ANames: TArray<string>): TCharCellAttributes;
var
  Name: string;
begin
  Result := [];
  for Name in ANames do
    if SameText(Name, 'bold') then
      Include(Result, ccaBold)
    else if SameText(Name, 'italic') then
      Include(Result, ccaItalic)
    else if SameText(Name, 'underline') then
      Include(Result, ccaUnderline)
    else if SameText(Name, 'strike') then
      Include(Result, ccaStrike)
    else if SameText(Name, 'blink') then
      Include(Result, ccaBlink)
    else if SameText(Name, 'reverse') then
      Include(Result, ccaReverse);
end;

function ThemeTemplateValid(const ATemplate: string): Boolean;
begin
  Result := Pos(cPlaceholder, ATemplate) > 0;
end;

function ThemeApplyTemplate(const ATemplate, AText: string): string;
begin
  Result := StringReplace(ATemplate, cPlaceholder, AText, []);
end;

// ------------------------------------------------------------------ slots

function ThemeSlotText(const ASlot: TThemeColorSlot): string;
begin
  if not ASlot.Has then
    Result := ''
  else if ASlot.Ref <> '' then
    Result := ASlot.Ref
  else
    Result := ThemeColorToText(ASlot.Value);
end;

procedure ThemeSlotSetColor(var ASlot: TThemeColorSlot; AColor: TAlphaColor);
begin
  ASlot.Has := True;
  ASlot.Value := AColor;
  ASlot.Ref := '';
end;

procedure ThemeSlotSetRef(var ASlot: TThemeColorSlot; const ARef: string);
begin
  ASlot.Has := True;
  ASlot.Value := 0;
  ASlot.Ref := ARef;
end;

function IsRefName(const AText: string): Boolean;
var
  I: Integer;
begin
  Result := AText <> '';
  for I := 1 to Length(AText) do
    if not (CharInSet(AText[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-']) or
            ((I = 1) and (AText[I] = '@'))) then
      Exit(False);
end;

function ThemeSlotFromText(const AText: string; out ASlot: TThemeColorSlot): Boolean;
var
  Text: string;
  Color: TAlphaColor;
  Role: TThemeColorRole;
begin
  ASlot := Default(TThemeColorSlot);
  Result := False;
  Text := Trim(AText);
  if TryParseThemeColor(Text, Color) then
  begin
    ThemeSlotSetColor(ASlot, Color);
    Exit(True);
  end;
  if (Text <> '') and (Text[1] = '@') then
  begin
    if ThemeColorRoleByKey(Copy(Text, 2, MaxInt), Role) then
    begin
      ThemeSlotSetRef(ASlot, Text);
      Result := True;
    end;
    Exit;
  end;
  if IsRefName(Text) then
  begin
    ThemeSlotSetRef(ASlot, Text);
    Result := True;
  end;
end;

function ThemeExtendsText(const AExtends: TArray<string>): string;
var
  Id: string;
begin
  Result := '';
  for Id in AExtends do
  begin
    if Result <> '' then
      Result := Result + '; ';
    Result := Result + Id;
  end;
end;

function ThemeParseExtends(const AText: string): TArray<string>;
var
  Part, Id: string;
begin
  SetLength(Result, 0);
  for Part in AText.Replace(',', ';').Split([';']) do
  begin
    Id := Trim(Part);
    if Id <> '' then
      Result := Result + [Id];
  end;
end;

function PaletteLookup(const APalette: TArray<TThemePaletteEntry>;
  const AName: string; out AColor: TAlphaColor): Boolean;
var
  I: Integer;
begin
  for I := High(APalette) downto 0 do
    if SameText(APalette[I].Name, AName) then
    begin
      AColor := APalette[I].Color;
      Exit(True);
    end;
  Result := False;
  AColor := 0;
end;

// ---------------------------------------------------------------- parsing

function ParseColorValue(AValue: TJSONValue; out ASlot: TThemeColorSlot): Boolean;
var
  Text: string;
  Color: TAlphaColor;
begin
  ASlot := Default(TThemeColorSlot);
  Result := False;
  if not (AValue is TJSONString) then
    Exit;
  Text := Trim(TJSONString(AValue).Value);
  if (Text <> '') and (Text[1] = '#') then
  begin
    Result := TryParseThemeColor(Text, Color);
    if Result then
      ThemeSlotSetColor(ASlot, Color);
  end
  else if IsRefName(Text) then
  begin
    ThemeSlotSetRef(ASlot, Text);
    Result := True;
  end;
end;

function JsonObj(AObj: TJSONObject; const AKey: string): TJSONObject;
var
  V: TJSONValue;
begin
  Result := nil;
  if AObj = nil then
    Exit;
  V := AObj.GetValue(AKey);
  if V is TJSONObject then
    Result := TJSONObject(V);
end;

function JsonText(AObj: TJSONObject; const AKey: string; out AText: string): Boolean;
var
  V: TJSONValue;
begin
  Result := False;
  AText := '';
  if AObj = nil then
    Exit;
  V := AObj.GetValue(AKey);
  if V is TJSONString then
  begin
    AText := TJSONString(V).Value;
    Result := True;
  end;
end;

procedure ParsePalette(AObj: TJSONObject; var ADoc: TThemeDoc);
var
  Pair: TJSONPair;
  Entry: TThemePaletteEntry;
  Color: TAlphaColor;
begin
  if AObj = nil then
    Exit;
  for Pair in AObj do
    if (Pair.JsonValue is TJSONString) and
       TryParseThemeColor(TJSONString(Pair.JsonValue).Value, Color) then
    begin
      Entry.Name := Pair.JsonString.Value;
      Entry.Color := Color;
      ADoc.Palette := ADoc.Palette + [Entry];
    end;
end;

procedure ParseColors(AObj: TJSONObject; var ADoc: TThemeDoc);
var
  Role: TThemeColorRole;
  Key, Group, Leaf: string;
  P: Integer;
  GroupObj: TJSONObject;
  Slot: TThemeColorSlot;
begin
  if AObj = nil then
    Exit;
  for Role := Low(TThemeColorRole) to High(TThemeColorRole) do
  begin
    Key := cRoleDefs[Role].Key;
    P := Pos('.', Key);
    Group := Copy(Key, 1, P - 1);
    Leaf := Copy(Key, P + 1, MaxInt);
    GroupObj := JsonObj(AObj, Group);
    if (GroupObj <> nil) and ParseColorValue(GroupObj.GetValue(Leaf), Slot) then
      ADoc.Colors[Role] := Slot;
  end;
end;

procedure ParseAttrArray(AValue: TJSONValue; out AAttr: TThemeAttrValue);
var
  Arr: TJSONArray;
  Names: TArray<string>;
  I: Integer;
begin
  AAttr := Default(TThemeAttrValue);
  if not (AValue is TJSONArray) then
    Exit;
  Arr := TJSONArray(AValue);
  SetLength(Names, 0);
  for I := 0 to Arr.Count - 1 do
    if Arr.Items[I] is TJSONString then
      Names := Names + [TJSONString(Arr.Items[I]).Value];
  AAttr.Has := True;
  AAttr.Value := ThemeAttrsFromNames(Names);
end;

procedure ParseMarkdown(AObj: TJSONObject; var ADoc: TThemeDoc);
var
  Kind: TMdSpanKind;
  KindObj: TJSONObject;
  Slot: TThemeColorSlot;
begin
  if AObj = nil then
    Exit;
  for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
  begin
    KindObj := JsonObj(AObj, MdSpanKindKey(Kind));
    if KindObj = nil then
      Continue;
    if ParseColorValue(KindObj.GetValue('fg'), Slot) then
      ADoc.MdFg[Kind] := Slot;
    if ParseColorValue(KindObj.GetValue('bg'), Slot) then
      ADoc.MdBg[Kind] := Slot;
    ParseAttrArray(KindObj.GetValue('attrs'), ADoc.MdAttrs[Kind]);
  end;
end;

procedure ParseAttrs(AObj: TJSONObject; var ADoc: TThemeDoc);
var
  Slot: TThemeAttrSlot;
begin
  if AObj = nil then
    Exit;
  for Slot := Low(TThemeAttrSlot) to High(TThemeAttrSlot) do
    ParseAttrArray(AObj.GetValue(cAttrKeys[Slot]), ADoc.Attrs[Slot]);
end;

procedure ParseGlyphs(AObj: TJSONObject; var ADoc: TThemeDoc);
var
  Glyph: TThemeGlyph;
  Text: string;
begin
  if AObj = nil then
    Exit;
  for Glyph := Low(TThemeGlyph) to High(TThemeGlyph) do
    if JsonText(AObj, cGlyphKeys[Glyph], Text) then
    begin
      ADoc.Glyphs[Glyph].Has := True;
      ADoc.Glyphs[Glyph].Value := Text;
    end;
end;

procedure ParseFrames(AFrames, ASets: TJSONObject; var ADoc: TThemeDoc);
var
  Slot: TThemeFrameSlot;
  Text: string;
  Pair: TJSONPair;
  Named: TThemeNamedFrameSet;
  SetObj: TJSONObject;

  function Glyph(const AKey: string; ADefault: Char): Char;
  var
    S: string;
  begin
    Result := ADefault;
    if JsonText(SetObj, AKey, S) and (S <> '') then
      Result := S[1];
  end;

begin
  if AFrames <> nil then
    for Slot := Low(TThemeFrameSlot) to High(TThemeFrameSlot) do
      if JsonText(AFrames, cFrameKeys[Slot], Text) and (Trim(Text) <> '') then
      begin
        ADoc.Frames[Slot].Has := True;
        ADoc.Frames[Slot].Value := Trim(Text);
      end;
  if ASets <> nil then
    for Pair in ASets do
      if Pair.JsonValue is TJSONObject then
      begin
        SetObj := TJSONObject(Pair.JsonValue);
        Named.Name := Pair.JsonString.Value;
        Named.Glyphs := MakeFrameSet(Glyph('tl', chBoxTL), Glyph('tr', chBoxTR),
          Glyph('bl', chBoxBL), Glyph('br', chBoxBR), Glyph('h', chBoxH),
          Glyph('v', chBoxV));
        ADoc.FrameSets := ADoc.FrameSets + [Named];
      end;
end;

function TryParseThemeDoc(const AJson: string; out ADoc: TThemeDoc;
  out AError: string): Boolean;
var
  Root: TJSONValue;
  Obj, Options: TJSONObject;
  Schema, I: Integer;
  Text: string;
  V: TJSONValue;
  Arr: TJSONArray;
begin
  ADoc := Default(TThemeDoc);
  AError := '';
  Result := False;
  try
    Root := TJSONObject.ParseJSONValue(AJson);
  except
    Root := nil;
  end;
  try
    if not (Root is TJSONObject) then
    begin
      AError := 'not a JSON object';
      Exit;
    end;
    Obj := TJSONObject(Root);
    V := Obj.GetValue('schema');
    Schema := cThemeSchemaVersion;
    if V is TJSONNumber then
      Schema := TJSONNumber(V).AsInt;
    if Schema > cThemeSchemaVersion then
    begin
      AError := 'unsupported schema ' + IntToStr(Schema);
      Exit;
    end;
    if JsonText(Obj, 'name', Text) then
      ADoc.Name := Trim(Text);
    V := Obj.GetValue('extends');
    if V is TJSONString then
      ADoc.Extends := ThemeParseExtends(TJSONString(V).Value)
    else if V is TJSONArray then
      for I := 0 to TJSONArray(V).Count - 1 do
        if TJSONArray(V).Items[I] is TJSONString then
          ADoc.Extends := ADoc.Extends +
            ThemeParseExtends(TJSONString(TJSONArray(V).Items[I]).Value);
    ParsePalette(JsonObj(Obj, 'palette'), ADoc);
    ParseColors(JsonObj(Obj, 'colors'), ADoc);
    ParseMarkdown(JsonObj(Obj, 'markdown'), ADoc);
    ParseAttrs(JsonObj(Obj, 'attrs'), ADoc);
    ParseGlyphs(JsonObj(Obj, 'glyphs'), ADoc);
    ParseFrames(JsonObj(Obj, 'frames'), JsonObj(Obj, 'frameSets'), ADoc);
    Options := JsonObj(Obj, 'options');
    if Options <> nil then
    begin
      V := Options.GetValue('doubleActivePanel');
      if V is TJSONTrue then
        ADoc.DoubleActivePanel := ttsTrue
      else if V is TJSONFalse then
        ADoc.DoubleActivePanel := ttsFalse;
    end;
    if Obj.GetValue('fileColoring') is TJSONArray then
      ADoc.HasFileColoring := ParseColorCodingJson(AJson, ADoc.FileColoring, 'fileColoring');
    V := Obj.GetValue('fileColoringOrder');
    if V is TJSONArray then
    begin
      Arr := TJSONArray(V);
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONString then
          ADoc.FileColoringOrder := ADoc.FileColoringOrder + [TJSONString(Arr.Items[I]).Value];
      if Length(ADoc.FileColoringOrder) > 0 then
        ADoc.HasFileColoring := True;
    end;
    Result := True;
  finally
    Root.Free;
  end;
end;

// ---------------------------------------------------------- serialization

function FrameSetToJson(const ASet: TThemeFrameSet): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('tl', ASet.TL);
  Result.AddPair('tr', ASet.TR);
  Result.AddPair('bl', ASet.BL);
  Result.AddPair('br', ASet.BR);
  Result.AddPair('h', ASet.H);
  Result.AddPair('v', ASet.V);
end;

function AttrArray(AAttrs: TCharCellAttributes): TJSONArray;
var
  Name: string;
begin
  Result := TJSONArray.Create;
  for Name in ThemeAttrsToNames(AAttrs) do
    Result.Add(Name);
end;

function ThemeDocToJson(const ADoc: TThemeDoc): string;
var
  Root, Palette, Colors, Group, MdAll, MdKind, AttrObj, GlyphObj, FrameObj,
    SetsObj, Options: TJSONObject;
  Role: TThemeColorRole;
  Kind: TMdSpanKind;
  Slot: TThemeAttrSlot;
  Glyph: TThemeGlyph;
  FSlot: TThemeFrameSlot;
  Key, GroupKey, Leaf: string;
  P, I: Integer;
  Arr: TJSONArray;
  Parsed: TJSONValue;
  FilePair: TJSONPair;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('schema', TJSONNumber.Create(cThemeSchemaVersion));
    if ADoc.Name <> '' then
      Root.AddPair('name', ADoc.Name);
    if Length(ADoc.Extends) = 1 then
      Root.AddPair('extends', ADoc.Extends[0])
    else if Length(ADoc.Extends) > 1 then
    begin
      Arr := TJSONArray.Create;
      for I := 0 to High(ADoc.Extends) do
        Arr.Add(ADoc.Extends[I]);
      Root.AddPair('extends', Arr);
    end;

    if Length(ADoc.Palette) > 0 then
    begin
      Palette := TJSONObject.Create;
      for I := 0 to High(ADoc.Palette) do
        Palette.AddPair(ADoc.Palette[I].Name, ThemeColorToText(ADoc.Palette[I].Color));
      Root.AddPair('palette', Palette);
    end;

    Colors := TJSONObject.Create;
    Group := nil;
    GroupKey := '';
    for Role := Low(TThemeColorRole) to High(TThemeColorRole) do
    begin
      if not ADoc.Colors[Role].Has then
        Continue;
      Key := cRoleDefs[Role].Key;
      P := Pos('.', Key);
      if Copy(Key, 1, P - 1) <> GroupKey then
      begin
        GroupKey := Copy(Key, 1, P - 1);
        Group := TJSONObject.Create;
        Colors.AddPair(GroupKey, Group);
      end;
      Leaf := Copy(Key, P + 1, MaxInt);
      Group.AddPair(Leaf, ThemeSlotText(ADoc.Colors[Role]));
    end;
    if Colors.Count > 0 then
      Root.AddPair('colors', Colors)
    else
      Colors.Free;

    MdAll := TJSONObject.Create;
    for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
    begin
      if not (ADoc.MdFg[Kind].Has or ADoc.MdBg[Kind].Has or ADoc.MdAttrs[Kind].Has) then
        Continue;
      MdKind := TJSONObject.Create;
      if ADoc.MdFg[Kind].Has then
        MdKind.AddPair('fg', ThemeSlotText(ADoc.MdFg[Kind]));
      if ADoc.MdBg[Kind].Has then
        MdKind.AddPair('bg', ThemeSlotText(ADoc.MdBg[Kind]));
      if ADoc.MdAttrs[Kind].Has then
        MdKind.AddPair('attrs', AttrArray(ADoc.MdAttrs[Kind].Value));
      MdAll.AddPair(MdSpanKindKey(Kind), MdKind);
    end;
    if MdAll.Count > 0 then
      Root.AddPair('markdown', MdAll)
    else
      MdAll.Free;

    AttrObj := TJSONObject.Create;
    for Slot := Low(TThemeAttrSlot) to High(TThemeAttrSlot) do
      if ADoc.Attrs[Slot].Has then
        AttrObj.AddPair(cAttrKeys[Slot], AttrArray(ADoc.Attrs[Slot].Value));
    if AttrObj.Count > 0 then
      Root.AddPair('attrs', AttrObj)
    else
      AttrObj.Free;

    GlyphObj := TJSONObject.Create;
    for Glyph := Low(TThemeGlyph) to High(TThemeGlyph) do
      if ADoc.Glyphs[Glyph].Has then
        GlyphObj.AddPair(cGlyphKeys[Glyph], ADoc.Glyphs[Glyph].Value);
    if GlyphObj.Count > 0 then
      Root.AddPair('glyphs', GlyphObj)
    else
      GlyphObj.Free;

    FrameObj := TJSONObject.Create;
    for FSlot := Low(TThemeFrameSlot) to High(TThemeFrameSlot) do
      if ADoc.Frames[FSlot].Has then
        FrameObj.AddPair(cFrameKeys[FSlot], ADoc.Frames[FSlot].Value);
    if FrameObj.Count > 0 then
      Root.AddPair('frames', FrameObj)
    else
      FrameObj.Free;

    if Length(ADoc.FrameSets) > 0 then
    begin
      SetsObj := TJSONObject.Create;
      for I := 0 to High(ADoc.FrameSets) do
        SetsObj.AddPair(ADoc.FrameSets[I].Name, FrameSetToJson(ADoc.FrameSets[I].Glyphs));
      Root.AddPair('frameSets', SetsObj);
    end;

    if ADoc.DoubleActivePanel <> ttsUnset then
    begin
      Options := TJSONObject.Create;
      Options.AddPair('doubleActivePanel', TJSONBool.Create(ADoc.DoubleActivePanel = ttsTrue));
      Root.AddPair('options', Options);
    end;

    if ADoc.HasFileColoring then
    begin
      Parsed := TJSONObject.ParseJSONValue(ColorCodingGroupsToJson(ADoc.FileColoring));
      try
        if Parsed is TJSONObject then
        begin
          FilePair := TJSONObject(Parsed).RemovePair('fileColoring');
          if FilePair <> nil then
            Root.AddPair(FilePair);
        end;
      finally
        Parsed.Free;
      end;
      if Length(ADoc.FileColoringOrder) > 0 then
      begin
        Arr := TJSONArray.Create;
        for I := 0 to High(ADoc.FileColoringOrder) do
          Arr.Add(ADoc.FileColoringOrder[I]);
        Root.AddPair('fileColoringOrder', Arr);
      end;
    end;

    Result := Root.Format(2);
  finally
    Root.Free;
  end;
end;

// -------------------------------------------------------------- resolving

function FindNamedFrameSet(const ASets: TArray<TThemeNamedFrameSet>;
  const AName: string; out ASet: TThemeFrameSet): Boolean;
var
  I: Integer;
begin
  for I := High(ASets) downto 0 do
    if SameText(ASets[I].Name, AName) then
    begin
      ASet := ASets[I].Glyphs;
      Exit(True);
    end;
  Result := False;
end;

function ResolveThemeSpec(const AChain: TArray<TThemeDoc>): TThemeSpec;
var
  Doc: TThemeDoc;
  Colors: array[TThemeColorRole] of TThemeColorSlot;
  MdFg, MdBg: array[TMdSpanKind] of TThemeColorSlot;
  MdAttrs: array[TMdSpanKind] of TThemeAttrValue;
  Attrs: array[TThemeAttrSlot] of TThemeAttrValue;
  Sets: TArray<TThemeNamedFrameSet>;
  Role: TThemeColorRole;
  Kind: TMdSpanKind;
  Slot: TThemeAttrSlot;
  Glyph: TThemeGlyph;
  FSlot: TThemeFrameSlot;
  FrameName: string;
  DoubleMode: TThemeTriState;
  I, J, K: Integer;
  Entry: TThemePaletteEntry;
  Found, Resolved: Boolean;
  S: TColorCodingState;
  Pal: TArray<TThemePaletteEntry>;
  Groups: TArray<TColorCodingGroup>;

  // A palette name is bound where it is written: a color a base theme names
  // keeps that theme's value even when a descendant defines the same name
  // differently. Only "@role" references are resolved against the final theme.
  procedure BindSlot(var ASlot: TThemeColorSlot);
  var
    Color: TAlphaColor;
  begin
    if ASlot.Has and (ASlot.Ref <> '') and (ASlot.Ref[1] <> '@') and
       PaletteLookup(Pal, ASlot.Ref, Color) then
      ThemeSlotSetColor(ASlot, Color);
  end;

  procedure BindRef(var AColor: TAlphaColor; var ARef: string);
  var
    Color: TAlphaColor;
  begin
    if (ARef <> '') and (ARef[1] <> '@') and PaletteLookup(Pal, ARef, Color) then
    begin
      AColor := Color;
      ARef := '';
    end;
  end;

  function EvalRef(const ARef: string; ADepth: Integer; out AColor: TAlphaColor): Boolean; forward;

  function RoleValue(ARole: TThemeColorRole; ADepth: Integer): TAlphaColor;
  var
    Fallback: TThemeColorRole;
    Color: TAlphaColor;
  begin
    if Colors[ARole].Has then
    begin
      if Colors[ARole].Ref = '' then
        Exit(Colors[ARole].Value);
      if EvalRef(Colors[ARole].Ref, ADepth + 1, Color) then
        Exit(Color);
    end;
    if (ADepth < 16) and ThemeColorRoleFallback(ARole, Fallback) then
      Exit(RoleValue(Fallback, ADepth + 1));
    Result := 0;
  end;

  // A reference: "@role.key" follows another role, anything else is a palette
  // name. False when it cannot be resolved (the slot then counts as not set).
  function EvalRef(const ARef: string; ADepth: Integer; out AColor: TAlphaColor): Boolean;
  var
    Target: TThemeColorRole;
  begin
    AColor := 0;
    Result := False;
    if ADepth > 16 then
      Exit;
    if (ARef <> '') and (ARef[1] = '@') then
    begin
      if not ThemeColorRoleByKey(Copy(ARef, 2, MaxInt), Target) then
        Exit;
      AColor := RoleValue(Target, ADepth);
      Result := True;
    end
    else
      Result := PaletteLookup(Pal, ARef, AColor);
  end;

begin
  Result := Default(TThemeSpec);
  // The managed Ref strings start empty; the other fields are not initialized.
  FillChar(Colors, SizeOf(Colors), 0);
  FillChar(MdFg, SizeOf(MdFg), 0);
  FillChar(MdBg, SizeOf(MdBg), 0);
  FillChar(MdAttrs, SizeOf(MdAttrs), 0);
  FillChar(Attrs, SizeOf(Attrs), 0);
  DoubleMode := ttsUnset;
  for Glyph := Low(TThemeGlyph) to High(TThemeGlyph) do
    Result.Glyphs[Glyph] := cGlyphDefaults[Glyph];
  for FSlot := Low(TThemeFrameSlot) to High(TThemeFrameSlot) do
    Result.FrameNames[FSlot] := cFrameSingle;

  for I := 0 to High(AChain) do
  begin
    Doc := AChain[I];
    Result.Id := Doc.Id;
    if Doc.Name <> '' then
      Result.Name := Doc.Name;
    for J := 0 to High(Doc.Palette) do
    begin
      Entry := Doc.Palette[J];
      Found := False;
      for K := 0 to High(Result.Palette) do
        if SameText(Result.Palette[K].Name, Entry.Name) then
        begin
          Result.Palette[K] := Entry;
          Found := True;
          Break;
        end;
      if not Found then
        Result.Palette := Result.Palette + [Entry];
    end;
    Pal := Result.Palette;
    for Role := Low(TThemeColorRole) to High(TThemeColorRole) do
      if Doc.Colors[Role].Has then
      begin
        Colors[Role] := Doc.Colors[Role];
        BindSlot(Colors[Role]);
      end;
    for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
    begin
      if Doc.MdFg[Kind].Has then
      begin
        MdFg[Kind] := Doc.MdFg[Kind];
        BindSlot(MdFg[Kind]);
      end;
      if Doc.MdBg[Kind].Has then
      begin
        MdBg[Kind] := Doc.MdBg[Kind];
        BindSlot(MdBg[Kind]);
      end;
      if Doc.MdAttrs[Kind].Has then
        MdAttrs[Kind] := Doc.MdAttrs[Kind];
    end;
    for Slot := Low(TThemeAttrSlot) to High(TThemeAttrSlot) do
      if Doc.Attrs[Slot].Has then
        Attrs[Slot] := Doc.Attrs[Slot];
    for Glyph := Low(TThemeGlyph) to High(TThemeGlyph) do
      if Doc.Glyphs[Glyph].Has then
        Result.Glyphs[Glyph] := Doc.Glyphs[Glyph].Value;
    for FSlot := Low(TThemeFrameSlot) to High(TThemeFrameSlot) do
      if Doc.Frames[FSlot].Has then
        Result.FrameNames[FSlot] := Doc.Frames[FSlot].Value;
    Sets := Sets + Doc.FrameSets;
    if Doc.DoubleActivePanel <> ttsUnset then
      DoubleMode := Doc.DoubleActivePanel;
    if Doc.HasFileColoring then
    begin
      Groups := Copy(Doc.FileColoring);
      for J := 0 to High(Groups) do
        for S := Low(TColorCodingState) to High(TColorCodingState) do
        begin
          BindRef(Groups[J].Colors[S].Fg, Groups[J].Colors[S].FgRef);
          BindRef(Groups[J].Colors[S].Bg, Groups[J].Colors[S].BgRef);
        end;
      Result.FileColoring := MergeColorCodingGroups(Result.FileColoring, Groups);
      ColorCodingApplyOrder(Result.FileColoring, Doc.FileColoringOrder);
    end;
  end;

  Pal := Result.Palette;
  for Role := Low(TThemeColorRole) to High(TThemeColorRole) do
    Result.Colors[Role] := RoleValue(Role, 0);
  // Markdown: text first; every other element follows the text colors unless
  // it has its own.
  for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
  begin
    Resolved := False;
    if MdFg[Kind].Has then
    begin
      if MdFg[Kind].Ref = '' then
      begin
        Result.MdFg[Kind] := MdFg[Kind].Value;
        Resolved := True;
      end
      else
        Resolved := EvalRef(MdFg[Kind].Ref, 0, Result.MdFg[Kind]);
    end;
    if not Resolved then
      if Kind = mskText then
        Result.MdFg[Kind] := Result.Colors[trWindowFg]
      else
        Result.MdFg[Kind] := Result.MdFg[mskText];
    Resolved := False;
    if MdBg[Kind].Has then
    begin
      if MdBg[Kind].Ref = '' then
      begin
        Result.MdBg[Kind] := MdBg[Kind].Value;
        Resolved := True;
      end
      else
        Resolved := EvalRef(MdBg[Kind].Ref, 0, Result.MdBg[Kind]);
    end;
    if not Resolved then
      if Kind = mskText then
        Result.MdBg[Kind] := Result.Colors[trWindowBg]
      else
        Result.MdBg[Kind] := Result.MdBg[mskText];
    if MdAttrs[Kind].Has then
      Result.MdAttrs[Kind] := MdAttrs[Kind].Value
    else
      Result.MdAttrs[Kind] := [];
  end;
  for Slot := Low(TThemeAttrSlot) to High(TThemeAttrSlot) do
    if Attrs[Slot].Has then
      Result.Attrs[Slot] := Attrs[Slot].Value
    else if Slot = tasClock then
      Result.Attrs[Slot] := Result.Attrs[tasMenu]
    else
      Result.Attrs[Slot] := [];
  // File coloring colors written as references.
  for I := 0 to High(Result.FileColoring) do
    for S := Low(TColorCodingState) to High(TColorCodingState) do
    begin
      if Result.FileColoring[I].Colors[S].FgRef <> '' then
        EvalRef(Result.FileColoring[I].Colors[S].FgRef, 0, Result.FileColoring[I].Colors[S].Fg);
      if Result.FileColoring[I].Colors[S].BgRef <> '' then
        EvalRef(Result.FileColoring[I].Colors[S].BgRef, 0, Result.FileColoring[I].Colors[S].Bg);
    end;

  Result.FrameSets := Sets;
  for FSlot := Low(TThemeFrameSlot) to High(TThemeFrameSlot) do
  begin
    FrameName := Result.FrameNames[FSlot];
    if not FindNamedFrameSet(Sets, FrameName, Result.Frames[FSlot]) and
       not BuiltInFrameSet(FrameName, Result.Frames[FSlot]) then
    begin
      Result.FrameNames[FSlot] := cFrameSingle;
      BuiltInFrameSet(cFrameSingle, Result.Frames[FSlot]);
    end;
  end;
  case DoubleMode of
    ttsTrue: Result.DoubleActivePanel := True;
    ttsFalse: Result.DoubleActivePanel := False;
  else
    Result.DoubleActivePanel :=
      not SameText(Result.FrameNames[tfsPanelActive], Result.FrameNames[tfsPanelIdle]);
  end;
end;

function ThemeDocFromSpec(const ASpec: TThemeSpec): TThemeDoc;
var
  Role: TThemeColorRole;
  Kind: TMdSpanKind;
  Slot: TThemeAttrSlot;
  Glyph: TThemeGlyph;
  FSlot: TThemeFrameSlot;
begin
  Result := Default(TThemeDoc);
  Result.Name := ASpec.Name;
  for Role := Low(TThemeColorRole) to High(TThemeColorRole) do
    ThemeSlotSetColor(Result.Colors[Role], ASpec.Colors[Role]);
  for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
  begin
    ThemeSlotSetColor(Result.MdFg[Kind], ASpec.MdFg[Kind]);
    ThemeSlotSetColor(Result.MdBg[Kind], ASpec.MdBg[Kind]);
    Result.MdAttrs[Kind].Has := True;
    Result.MdAttrs[Kind].Value := ASpec.MdAttrs[Kind];
  end;
  for Slot := Low(TThemeAttrSlot) to High(TThemeAttrSlot) do
  begin
    Result.Attrs[Slot].Has := True;
    Result.Attrs[Slot].Value := ASpec.Attrs[Slot];
  end;
  for Glyph := Low(TThemeGlyph) to High(TThemeGlyph) do
  begin
    Result.Glyphs[Glyph].Has := True;
    Result.Glyphs[Glyph].Value := ASpec.Glyphs[Glyph];
  end;
  for FSlot := Low(TThemeFrameSlot) to High(TThemeFrameSlot) do
  begin
    Result.Frames[FSlot].Has := True;
    Result.Frames[FSlot].Value := ASpec.FrameNames[FSlot];
  end;
  Result.FrameSets := Copy(ASpec.FrameSets);
  Result.DoubleActivePanel := ttsFalse;
  if ASpec.DoubleActivePanel then
    Result.DoubleActivePanel := ttsTrue;
  Result.HasFileColoring := Length(ASpec.FileColoring) > 0;
  Result.FileColoring := Copy(ASpec.FileColoring);
  Result.FileColoringOrder := ColorCodingNames(ASpec.FileColoring);
end;

function ThemeDocMdSet(const ADoc: TThemeDoc; const ASpec: TThemeSpec): TMdColorSet;
var
  Kind: TMdSpanKind;
begin
  MdColorSetClear(Result);
  for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
  begin
    Result[Kind].HasFg := ADoc.MdFg[Kind].Has;
    if Result[Kind].HasFg then
      Result[Kind].Fg := ASpec.MdFg[Kind];
    Result[Kind].HasBg := ADoc.MdBg[Kind].Has;
    if Result[Kind].HasBg then
      Result[Kind].Bg := ASpec.MdBg[Kind];
    Result[Kind].HasStyle := ADoc.MdAttrs[Kind].Has;
    if Result[Kind].HasStyle then
      Result[Kind].Style := ADoc.MdAttrs[Kind].Value;
  end;
end;

procedure ThemeDocApplyMdSet(var ADoc: TThemeDoc; const AInitial, AEdited: TMdColorSet);
var
  Kind: TMdSpanKind;
begin
  for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
  begin
    if (AEdited[Kind].HasFg <> AInitial[Kind].HasFg) or
       (AEdited[Kind].HasFg and (AEdited[Kind].Fg <> AInitial[Kind].Fg)) then
    begin
      if AEdited[Kind].HasFg then
        ThemeSlotSetColor(ADoc.MdFg[Kind], AEdited[Kind].Fg)
      else
        ADoc.MdFg[Kind] := Default(TThemeColorSlot);
    end;
    if (AEdited[Kind].HasBg <> AInitial[Kind].HasBg) or
       (AEdited[Kind].HasBg and (AEdited[Kind].Bg <> AInitial[Kind].Bg)) then
    begin
      if AEdited[Kind].HasBg then
        ThemeSlotSetColor(ADoc.MdBg[Kind], AEdited[Kind].Bg)
      else
        ADoc.MdBg[Kind] := Default(TThemeColorSlot);
    end;
    if (AEdited[Kind].HasStyle <> AInitial[Kind].HasStyle) or
       (AEdited[Kind].HasStyle and (AEdited[Kind].Style <> AInitial[Kind].Style)) then
    begin
      ADoc.MdAttrs[Kind].Has := AEdited[Kind].HasStyle;
      ADoc.MdAttrs[Kind].Value := AEdited[Kind].Style;
    end;
  end;
end;

end.
