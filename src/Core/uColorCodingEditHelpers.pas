unit uColorCodingEditHelpers;

{ Pure helpers for the "Color coding" list/editor and its color-picker
  overlay (hdkColorCoding / hdkColorCodingEdit / hdkColorPicker), plus the
  Gray+/Gray-/Gray* key-recovery helper used by the same dialog family.
  Extracted from uDualPanelWindow.pas (health/refactor pass) — none of these
  touch TDualPanelWindow state, so they live here as free functions. }

interface

uses
  System.SysUtils, System.UITypes,
  uColorCoding;

/// <summary>In-progress (not yet committed to FColorCodingGroups) values
/// of hdkColorCodingEdit's fields — snapshotted before opening hdkColorPicker
/// on top of it (which needs to fully close/replace FDialog, per this
/// codebase's usual "reopen with a patched declaration" pattern — there's
/// no live in-place field mutation on an open TDialogHost) and restored
/// (with the picked field updated) when the picker returns.</summary>
type
  TColorCodingEditFields = record
    Name, Mask: string;
    ApplyToIdx: Integer;
    Enabled: Boolean;
    NormalFg, NormalBg, SelectedFg, SelectedBg, CurrentFg, CurrentBg: string;
  end;

{ FMX Win ExtractChar zeroes Key for printable chars (KeyChar kept). Recover
  Gray+/Gray−/Gray* via the physical VK still held during KeyDown. }
procedure RestoreGrayOpKey(var AKey: Word; const AKeyChar: Char);

function ColorCodingApplyToChar(AApplyTo: TColorCodingApplyTo): Char;
function ColorCodingStateMarker(const AColor: TColorCodingColor): Char;

// Row layout mirrors dialogs/colorcoding.json's "header" label:
//   "    T Name             Mask                     N S C"
// [x]/[ ] = Enabled; T = ApplyTo (B/F/D); N/S/C = Normal/Selected/Current,
// '#' when that state has a color set, '.' when it's left to the theme.
function ColorCodingDisplayLabel(const AGroup: TColorCodingGroup): string;

function ColorCodingNameExistsIn(const AGroups: TArray<TColorCodingGroup>;
  const AName: string): Boolean;
procedure ColorCodingArrayDelete(var AGroups: TArray<TColorCodingGroup>; AIndex: Integer);

/// <summary>Blank AText = unset (True, AColor left at 0). Non-blank must
/// parse via uColorCoding.HexToColor or this fails — a typo should be
/// rejected, not silently dropped to "unset".</summary>
function ColorCodingParseHexField(const AText: string; out AColor: TAlphaColor): Boolean;

/// <summary>True for a field id ending "_bg" (vs. "_fg") — used both to
/// route hdkColorPicker's live preview and to know which half of a pair to
/// write the picked color back into.</summary>
function ColorCodingFieldIsBg(const AFieldId: string): Boolean;
function ColorCodingFieldIdIsColorField(const AId: string): Boolean;

function ColorCodingFieldValue(const AFields: TColorCodingEditFields;
  const AFieldId: string): string;
procedure ColorCodingSetFieldValue(var AFields: TColorCodingEditFields;
  const AFieldId, AValue: string);

/// <summary>16 named ANSI presets (uANSIParser.TANSIParser.StandardAnsiColor
/// — the same 16 colors the terminal itself uses for SGR 30-37/90-97, so
/// the picker offers exactly the palette this app already renders with,
/// not an invented one) as pre-formatted "Name           #RRGGBB" labels
/// for the picker's list, plus the matching hex strings in the same order.</summary>
procedure ColorPickerPresets(out ALabels, AHexes: TArray<string>);

implementation

uses
  Winapi.Windows,
  uANSIParser, uPanelColumns;

procedure RestoreGrayOpKey(var AKey: Word; const AKeyChar: Char);
begin
  { FMX+Alt often delivers Gray+/− as AKey=0 + KeyChar, not vkAdd.
    vkInsert = 45 = Ord('-'): never treat Ins as Gray− (that opened the
    deselect-mask dialog). Recover Gray keys only from AKey=0 / vkAdd. }
  if (AKey = vkAdd) or (AKey = vkSubtract) or (AKey = vkMultiply) then
    Exit;
  if AKey = vkInsert then
    Exit;
  if (GetAsyncKeyState(VK_ADD) < 0) and (AKey = 0) then
    AKey := vkAdd
  else if (GetAsyncKeyState(VK_SUBTRACT) < 0) and (AKey = 0) then
    AKey := vkSubtract
  else if (GetAsyncKeyState(VK_MULTIPLY) < 0) and (AKey = 0) then
    AKey := vkMultiply
  else if AKey = 0 then
  begin
    if AKeyChar = '+' then
      AKey := vkAdd
    else if AKeyChar = '-' then
      AKey := vkSubtract
    else if AKeyChar = '*' then
      AKey := vkMultiply;
  end
  else if (AKey = Ord('+')) and (AKeyChar = '+') then
    AKey := vkAdd
  else if (AKey = Ord('*')) and (AKeyChar = '*') then
    AKey := vkMultiply;
end;

const
  cCCNameW = 16;
  cCCMaskW = 24;

function ColorCodingApplyToChar(AApplyTo: TColorCodingApplyTo): Char;
begin
  case AApplyTo of
    ccaFilesOnly: Result := 'F';
    ccaDirsOnly: Result := 'D';
  else
    Result := 'B';
  end;
end;

function ColorCodingStateMarker(const AColor: TColorCodingColor): Char;
begin
  if (AColor.Fg <> 0) or (AColor.Bg <> 0) then
    Result := '#'
  else
    Result := '.';
end;

function ColorCodingDisplayLabel(const AGroup: TColorCodingGroup): string;
var
  Chk, MaskText: string;
begin
  if AGroup.Enabled then
    Chk := '[x]'
  else
    Chk := '[ ]';
  MaskText := string.Join(';', AGroup.Masks);
  Result := Chk + ' ' + ColorCodingApplyToChar(AGroup.ApplyTo) + ' ' +
    PadRight(AGroup.Name, cCCNameW) + ' ' +
    PadRight(MaskText, cCCMaskW) + ' N' +
    ColorCodingStateMarker(AGroup.Colors[ccsNormal]) + ' S' +
    ColorCodingStateMarker(AGroup.Colors[ccsSelected]) + ' C' +
    ColorCodingStateMarker(AGroup.Colors[ccsCurrent]);
end;

function ColorCodingNameExistsIn(const AGroups: TArray<TColorCodingGroup>;
  const AName: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(AGroups) do
    if SameText(AGroups[I].Name, AName) then
      Exit(True);
  Result := False;
end;

procedure ColorCodingArrayDelete(var AGroups: TArray<TColorCodingGroup>; AIndex: Integer);
var
  J: Integer;
begin
  for J := AIndex to High(AGroups) - 1 do
    AGroups[J] := AGroups[J + 1];
  SetLength(AGroups, Length(AGroups) - 1);
end;

function ColorCodingParseHexField(const AText: string; out AColor: TAlphaColor): Boolean;
begin
  AColor := 0;
  if Trim(AText) = '' then
    Exit(True);
  Result := HexToColor(AText, AColor);
end;

function ColorCodingFieldIsBg(const AFieldId: string): Boolean;
begin
  Result := (Length(AFieldId) >= 3) and
    (Copy(AFieldId, Length(AFieldId) - 2, 3) = '_bg');
end;

function ColorCodingFieldIdIsColorField(const AId: string): Boolean;
begin
  Result := SameText(AId, 'cc_normal_fg') or SameText(AId, 'cc_normal_bg') or
    SameText(AId, 'cc_selected_fg') or SameText(AId, 'cc_selected_bg') or
    SameText(AId, 'cc_current_fg') or SameText(AId, 'cc_current_bg');
end;

function ColorCodingFieldValue(const AFields: TColorCodingEditFields;
  const AFieldId: string): string;
begin
  if SameText(AFieldId, 'cc_normal_fg') then Result := AFields.NormalFg
  else if SameText(AFieldId, 'cc_normal_bg') then Result := AFields.NormalBg
  else if SameText(AFieldId, 'cc_selected_fg') then Result := AFields.SelectedFg
  else if SameText(AFieldId, 'cc_selected_bg') then Result := AFields.SelectedBg
  else if SameText(AFieldId, 'cc_current_fg') then Result := AFields.CurrentFg
  else if SameText(AFieldId, 'cc_current_bg') then Result := AFields.CurrentBg
  else Result := '';
end;

procedure ColorCodingSetFieldValue(var AFields: TColorCodingEditFields;
  const AFieldId, AValue: string);
begin
  if SameText(AFieldId, 'cc_normal_fg') then AFields.NormalFg := AValue
  else if SameText(AFieldId, 'cc_normal_bg') then AFields.NormalBg := AValue
  else if SameText(AFieldId, 'cc_selected_fg') then AFields.SelectedFg := AValue
  else if SameText(AFieldId, 'cc_selected_bg') then AFields.SelectedBg := AValue
  else if SameText(AFieldId, 'cc_current_fg') then AFields.CurrentFg := AValue
  else if SameText(AFieldId, 'cc_current_bg') then AFields.CurrentBg := AValue;
end;

procedure ColorPickerPresets(out ALabels, AHexes: TArray<string>);
const
  cNames: array[0..7] of string = ('Black', 'Red', 'Green', 'Yellow',
    'Blue', 'Magenta', 'Cyan', 'White');
var
  I: Integer;
begin
  SetLength(ALabels, 16);
  SetLength(AHexes, 16);
  for I := 0 to 7 do
  begin
    AHexes[I] := ColorToHex(TANSIParser.StandardAnsiColor(I, False));
    ALabels[I] := PadRight(cNames[I], 14) + ' ' + AHexes[I];
    AHexes[I + 8] := ColorToHex(TANSIParser.StandardAnsiColor(I, True));
    ALabels[I + 8] := PadRight('Bright ' + cNames[I], 14) + ' ' + AHexes[I + 8];
  end;
end;

end.
