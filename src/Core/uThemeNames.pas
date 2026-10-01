unit uThemeNames;

{ Human-readable names of everything a theme file sets. The dotted keys of
  uThemeSpec ("editor.bodyFg") are for files; the editor shows these names
  instead. Each table is indexed by its enumeration, so a new role cannot be
  added without a name. The text here is the English one; a translation is
  looked up under "ui.themeRole.<key>", "ui.themeAttr.<key>", "ui.themeGlyph.<key>",
  "ui.themeFrame.<key>", "ui.themeMd.<key>" and "ui.themeMdPart.<key>". }

interface

uses
  uThemeTypes, uThemeSpec;

/// <summary>Name of a color role ("Text under the cursor").</summary>
function ThemeColorRoleTitle(ARole: TThemeColorRole): string;
function ThemeAttrSlotTitle(ASlot: TThemeAttrSlot): string;
function ThemeGlyphTitle(AGlyph: TThemeGlyph): string;
function ThemeFrameSlotTitle(ASlot: TThemeFrameSlot): string;
/// <summary>Name of the "double frame for the active panel" option.</summary>
function ThemeDoubleActiveTitle: string;
/// <summary>Name of the "bases" (extends) setting.</summary>
function ThemeExtendsTitle: string;
/// <summary>Display name of a frame set ("double"); a custom set is shown as is.</summary>
function ThemeFrameSetTitle(const AName: string): string;
function ThemeMdKindTitle(AKind: TMdSpanKind): string;
/// <summary>Part of a Markdown style: 'fg', 'bg' or 'attrs'.</summary>
function ThemeMdPartTitle(const APart: string): string;

implementation

uses
  System.SysUtils, uStrings, uMarkdownColors;

const
  cRoleNames: array[TThemeColorRole] of string = (
    'Desktop background',
    'Window text',
    'Window background',
    'Border of the active window',
    'Border of an inactive window',
    'Active title text',
    'Active title background',
    'Inactive title text',
    'Inactive title background',
    'Close button mark',
    'Dialog text',
    'Dialog background',
    'Dialog border',
    'Dialog hotkey letter',
    'Dialog title text',
    'Dialog title background',
    'List row text',
    'List row background',
    'Selected list row text',
    'Selected list row background',
    'Button text',
    'Button background',
    'Focused button text',
    'Focused button background',
    'Button hotkey letter',
    'Focused button hotkey letter',
    'Checkbox text',
    'Checkbox background',
    'Checkbox hotkey letter',
    'Focused checkbox text',
    'Focused checkbox background',
    'Focused checkbox hotkey letter',
    'Cursor text',
    'Cursor background',
    'Cursor background, inactive panel',
    'Hotkey letter under the cursor',
    'Marked file text under the cursor',
    'Marked file background under the cursor',
    'Marked file text',
    'Marked file background',
    'Marked row text (band)',
    'Marked row background (band)',
    'Folder',
    'Archive',
    'Executable',
    'Media file',
    'Other file',
    'Hidden file',
    'Hidden folder',
    'Hidden archive',
    'Hidden executable',
    'Hidden media file',
    'Hidden other file',
    'Status line text',
    'Status line background',
    'Status line separator',
    'Key bar text',
    'Key bar background',
    'Key bar number',
    'Menu text',
    'Menu background',
    'Menu hot letter',
    'Clock',
    'Active tab text',
    'Active tab background',
    'Tab text',
    'Tab background',
    'Panel tab bar background',
    'Active panel tab text',
    'Active panel tab background',
    'Panel tab text',
    'Column header text',
    'Column header background',
    'Panel mark',
    'Tab close mark',
    'Scroll bar',
    'Scroll bar thumb',
    'Text',
    'Background',
    'Cursor text',
    'Cursor background',
    'Selection text',
    'Selection background',
    'Hint text',
    'Status line text',
    'Status line background',
    'Frame of the active window',
    'Frame',
    'Scroll bar',
    'Scroll bar thumb',
    'Search match text',
    'Search match background');

  cAttrNames: array[TThemeAttrSlot] of string = (
    'Window title',
    'Dialog title',
    'Button',
    'Checkbox',
    'Tab',
    'Key bar text',
    'Key bar number',
    'Status line',
    'Menu',
    'Menu hot letter',
    'Clock',
    'Hotkey letter',
    'Hotkey letter in focus');

  cGlyphNames: array[TThemeGlyph] of string = (
    'Checked mark',
    'Unchecked mark',
    'Radio button selected',
    'Radio button not selected',
    'Button caption',
    'Default button caption',
    'Workspace tab caption',
    'Panel tab caption',
    'Status line separator',
    'Close button, left',
    'Close button, mark',
    'Close button, right',
    'Desktop fill',
    'Scroll arrow up',
    'Scroll arrow down',
    'Scroll arrow left',
    'Scroll arrow right',
    'Scroll bar track',
    'Scroll bar thumb');

  cFrameNames: array[TThemeFrameSlot] of string = (
    'Window frame',
    'Dialog frame',
    'Active panel frame',
    'Inactive panel frame');

  cMdNames: array[TMdSpanKind] of string = (
    'Text and document',
    'Heading 1',
    'Heading 2',
    'Headings 3-6',
    'Bold',
    'Italic',
    'Bold italic',
    'Strikethrough',
    'Inline code',
    'Code block',
    'Quote',
    'List marker',
    'Horizontal rule',
    'Link',
    'Image marker',
    'Table border',
    'Table header');

  cDoubleActiveName = 'Double frame for the active panel';
  cExtendsName = 'Bases';
  cMdPartNames: array[0..2] of string = ('text color', 'background', 'style');

function ThemeColorRoleTitle(ARole: TThemeColorRole): string;
begin
  Result := T('ui.themeRole.' + ThemeColorRoleKey(ARole), cRoleNames[ARole]);
end;

function ThemeAttrSlotTitle(ASlot: TThemeAttrSlot): string;
begin
  Result := T('ui.themeAttr.' + ThemeAttrSlotKey(ASlot), cAttrNames[ASlot]);
end;

function ThemeGlyphTitle(AGlyph: TThemeGlyph): string;
begin
  Result := T('ui.themeGlyph.' + ThemeGlyphKey(AGlyph), cGlyphNames[AGlyph]);
end;

function ThemeFrameSlotTitle(ASlot: TThemeFrameSlot): string;
begin
  Result := T('ui.themeFrame.' + ThemeFrameSlotKey(ASlot), cFrameNames[ASlot]);
end;

function ThemeDoubleActiveTitle: string;
begin
  Result := T('ui.themeFrame.doubleActivePanel', cDoubleActiveName);
end;

function ThemeFrameSetTitle(const AName: string): string;
begin
  Result := T('ui.themeFrameSet.' + LowerCase(AName), AName);
end;

function ThemeExtendsTitle: string;
begin
  Result := T('ui.themeFrame.extends', cExtendsName);
end;

function ThemeMdKindTitle(AKind: TMdSpanKind): string;
begin
  Result := T('ui.themeMd.' + MdSpanKindKey(AKind), cMdNames[AKind]);
end;

function ThemeMdPartTitle(const APart: string): string;
var
  I: Integer;
begin
  I := 2;
  if APart = 'fg' then
    I := 0
  else if APart = 'bg' then
    I := 1;
  Result := T('ui.themeMdPart.' + APart, cMdPartNames[I]);
end;

end.
