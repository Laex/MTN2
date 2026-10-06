unit uDisplaySettings;

{ Font / zoom / cursor-blink / panel-icon settings used by the
  Display dialog, TTerminalRenderer.SetFont, and session.json. }

interface

uses
  System.SysUtils;

const
  // Font sizes are FMX pixels at 100% scaling (TTerminalRenderer, session.json
  // fontSize); the Display dialog shows them as typographic points
  // (1 pt = 96/72 px), the unit Windows Terminal and the console use.
  cDisplayMinFontSize = 8;
  cDisplayMaxFontSize = 32;
  cDisplayDefaultFontSize = 14;
  cDisplayPxPerPt = 96 / 72;
  cDisplayDefaultBlinkMs = 530;
  cDisplayMinZoom = 0.5;
  /// <summary>Text contrast levels: 0 = off, 1..3 = a stronger second pass
  /// over each glyph (uTerminalRenderer.TGlyphCache.Contrast).</summary>
  cDisplayMaxTextContrast = 3;
  /// <summary>Extra cell width / height in device pixels (Display dialog
  /// "Cell width" / "Cell height"): 0..cDisplayMaxCellExtra.</summary>
  cDisplayMaxCellExtra = 4;
  cDisplayMaxZoom = 3.0;

type
  /// <summary>Dialog, button and toast drop shadows and the modal backdrop
  /// (uThemeDrawing.GShadowStyle): classic FAR/NDN strength, a lighter one,
  /// or none.</summary>
  TShadowStyle = (ssClassic, ssSoft, ssNone);
  /// <summary>How marked panel rows away from the cursor stand out
  /// (uThemeDrawing.GMarkedRowStyle): the theme's mark text colour only, or
  /// also a background band (IThemeRenderer.ResolveMarkedRowBand).</summary>
  TMarkedRowStyle = (mrsText, mrsBand);

  TDisplaySettings = record
    FontName: string;
    FontSize: Single;
    Zoom: Single;
    CursorBlink: Boolean;
    CursorBlinkMs: Integer;
    ShowPanelIcons: Boolean;
    /// <summary>Transient notices (uToast.GShowToasts), e.g. "path copied".</summary>
    ShowNotifications: Boolean;
    /// <summary>Chrome (uChromeRows): the native title bar, the menu bar, the
    /// F-key bar and the status line. A hidden row goes to the content; a
    /// hidden title bar moves the window buttons into the menu or tab bar.</summary>
    ShowTitleBar: Boolean;
    ShowMenuBar: Boolean;
    ShowKeyBar: Boolean;
    ShowStatusLine: Boolean;
    /// <summary>Files can be dragged out of the panels with the mouse.</summary>
    FileDrag: Boolean;
    ShadowStyle: TShadowStyle;
    MarkedRowStyle: TMarkedRowStyle;
    /// <summary>Taller rows (TTerminalRenderer.SetLineSpacing), like a
    /// terminal window. Off by default: more rows fit.</summary>
    LineSpacing: Boolean;
    /// <summary>The glyph size is rounded to whole device pixels
    /// (TTerminalRenderer.SetSnapFontSize): evener strokes on scaled displays.</summary>
    SnapFontSize: Boolean;
    /// <summary>0..cDisplayMaxTextContrast: heavier glyph edges for thin text
    /// (TTerminalRenderer.SetTextContrast).</summary>
    TextContrast: Integer;
    /// <summary>Device pixels added to every cell's width / height
    /// (TTerminalRenderer.SetCellExtra): looser letters or rows for a font
    /// that is cramped. 0 = the font's own cell.</summary>
    CellWidthExtra: Integer;
    CellHeightExtra: Integer;
    /// <summary>Select all / Deselect all and select by extension also take
    /// folders (uDualPanelSelection.SelectFolders). Off by default, like Far.</summary>
    SelectFolders: Boolean;
    /// <summary>uStrings.pas locale code ('en', 'ru', ...). '' = English
    /// (uStrings' own zero-cost default) -- see DisplayLanguageItems /
    /// DisplayLanguageName for the Display dialog's picker.</summary>
    Language: string;
  end;

function PreferMonoFontFamily: string;
function ResolveMonospaceFontFamily(const AName: string): string;
function EnumerateMonospaceFontFamilies: TArray<string>;
function FontFamilyInstalled(const AName: string): Boolean;
function DefaultDisplaySettings: TDisplaySettings;
function ClampDisplayFontSize(ASize: Single): Single;
function ClampDisplayZoom(AZoom: Single): Single;
function ClampDisplayBlinkMs(AMs: Integer): Integer;
function ClampTextContrast(ALevel: Integer): Integer;
function ClampCellExtra(APixels: Integer): Integer;
/// <summary>Display dialog "Cell width" / "Cell height" dropdown ("0 px" ... "4 px").</summary>
function DisplayCellExtraItems: TArray<string>;
/// <summary>Display dialog "Text contrast" dropdown, level order.</summary>
function DisplayTextContrastItems: TArray<string>;
/// <summary>Display dialog size list, in points ("10.5 pt"; the decimal
/// separator follows the Windows locale).</summary>
function DisplayFontSizeItems: TArray<string>;
function DisplayZoomItems: TArray<string>;
function DisplayBlinkMsItems: TArray<string>;
/// <summary>ASize in pixels -> the nearest point size in the list.</summary>
function IndexOfDisplayFontSize(ASize: Single): Integer;
function IndexOfDisplayZoom(AZoom: Single): Integer;
function IndexOfDisplayBlinkMs(AMs: Integer): Integer;
/// <summary>List index -> size in pixels (11 pt -> 14.67).</summary>
function DisplayFontSizeAt(AIndex: Integer): Single;
function FontPointsToPixels(APoints: Single): Single;
function FontPixelsToPoints(APixels: Single): Single;
function DisplayZoomAt(AIndex: Integer): Single;
function DisplayBlinkMsAt(AIndex: Integer): Integer;
function IndexOfFontName(const ANames: TArray<string>; const AName: string): Integer;
procedure EnsureFontInList(var ANames: TArray<string>; const AName: string);
/// <summary>Locale codes for the Display dialog's language picker --
/// uStrings.AvailableLocales(), 'en' always first.</summary>
function DisplayLanguageItems: TArray<string>;
/// <summary>Human-readable name for a locale code (e.g. 'ru' -> 'Русский'),
/// for populating the Display dialog's dropdown. Falls back to the
/// uppercased code itself for a locale with no curated name yet (e.g. a
/// community locale dropped into strings\ without an app update).</summary>
function DisplayLanguageName(const ALocale: string): string;
/// <summary>session.json id: 'classic' / 'soft' / 'none'.</summary>
function ShadowStyleId(AStyle: TShadowStyle): string;
/// <summary>Unknown or empty id -> ssClassic.</summary>
function ShadowStyleFromId(const AId: string): TShadowStyle;
/// <summary>Display dialog "Shadows" dropdown, in TShadowStyle order.</summary>
function DisplayShadowItems: TArray<string>;
/// <summary>session.json id: 'text' / 'band'.</summary>
function MarkedRowStyleId(AStyle: TMarkedRowStyle): string;
/// <summary>Unknown or empty id -> mrsText.</summary>
function MarkedRowStyleFromId(const AId: string): TMarkedRowStyle;
/// <summary>Display dialog "Marked files" dropdown, in TMarkedRowStyle order.</summary>
function DisplayMarkedRowItems: TArray<string>;

implementation

uses
  System.Math, System.Classes, System.IOUtils, System.Generics.Collections,
  Winapi.Windows, uStrings;

const
  // Points; half steps where terminals are usually set (8..12 pt). 6 and 24 pt
  // are cDisplayMinFontSize / cDisplayMaxFontSize px. 10.5 pt = 14 px (the
  // default), 11 pt = Windows Terminal's default.
  cFontPoints: array[0..20] of Single =
    (6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10, 10.5, 11, 11.5, 12, 13, 14, 15, 16,
     18, 20, 22, 24);
  cZoomPercents: array[0..8] of Integer =
    (50, 75, 100, 125, 150, 175, 200, 250, 300);
  cBlinkMs: array[0..2] of Integer = (300, 530, 1000);
  cCuratedMono: array[0..9] of string = (
    'Cascadia Mono', 'Cascadia Code', 'Consolas', 'Lucida Console',
    'Courier New', 'Source Code Pro', 'JetBrains Mono', 'Fira Code',
    'DejaVu Sans Mono', 'Inconsolata');

function PreferMonoFontFamily: string;
{$IFDEF SKIA}
var
  WinDir, CascadiaPath: string;
{$ENDIF}
begin
  Result := 'Consolas';
  {$IFDEF SKIA}
  WinDir := GetEnvironmentVariable('WINDIR');
  if WinDir = '' then
    WinDir := 'C:\Windows';
  CascadiaPath := TPath.Combine(TPath.Combine(WinDir, 'Fonts'), 'CascadiaMono.ttf');
  if TFile.Exists(CascadiaPath) then
    Exit('Cascadia Mono');
  CascadiaPath := TPath.Combine(TPath.Combine(WinDir, 'Fonts'), 'cascadiamono.ttf');
  if TFile.Exists(CascadiaPath) then
    Exit('Cascadia Mono');
  {$ENDIF}
end;

function FamilyPresentProc(var LogFont: TLogFont; var TextMetric: TTextMetric;
  FontType: Integer; Data: LPARAM): Integer; stdcall;
begin
  PBoolean(Data)^ := True;
  Result := 0;
end;

function FontFamilyInstalled(const AName: string): Boolean;
var
  DC: HDC;
  LF: TLogFont;
  Found: Boolean;
  Face: string;
begin
  Result := False;
  Face := Trim(AName);
  if Face = '' then
    Exit;
  Found := False;
  FillChar(LF, SizeOf(LF), 0);
  LF.lfCharSet := DEFAULT_CHARSET;
  StrLCopy(@LF.lfFaceName[0], PChar(Face), LF_FACESIZE - 1);
  DC := GetDC(0);
  if DC = 0 then
    Exit;
  try
    EnumFontFamiliesEx(DC, LF, @FamilyPresentProc, LPARAM(@Found), 0);
  finally
    ReleaseDC(0, DC);
  end;
  Result := Found;
end;

function MonoEnumProc(var LogFont: TLogFont; var TextMetric: TTextMetric;
  FontType: Integer; Data: LPARAM): Integer; stdcall;
var
  Face: string;
  List: TStringList;
begin
  Result := 1;
  List := TStringList(Data);
  if (TextMetric.tmPitchAndFamily and TMPF_FIXED_PITCH) <> 0 then
    Exit;
  Face := Trim(string(LogFont.lfFaceName));
  if (Face = '') or Face.StartsWith('@') then
    Exit;
  if List.IndexOf(Face) < 0 then
    List.Add(Face);
end;

function EnumerateMonospaceFontFamilies: TArray<string>;
var
  DC: HDC;
  LF: TLogFont;
  List: TStringList;
  I: Integer;
begin
  List := TStringList.Create;
  try
    List.CaseSensitive := False;
    FillChar(LF, SizeOf(LF), 0);
    LF.lfCharSet := DEFAULT_CHARSET;
    LF.lfPitchAndFamily := FIXED_PITCH or FF_DONTCARE;
    DC := GetDC(0);
    if DC <> 0 then
    try
      EnumFontFamiliesEx(DC, LF, @MonoEnumProc, LPARAM(List), 0);
    finally
      ReleaseDC(0, DC);
    end;
    for I := Low(cCuratedMono) to High(cCuratedMono) do
      if FontFamilyInstalled(cCuratedMono[I]) and (List.IndexOf(cCuratedMono[I]) < 0) then
        List.Add(cCuratedMono[I]);
    if List.Count = 0 then
      List.Add(PreferMonoFontFamily);
    List.Sort;
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

function ResolveMonospaceFontFamily(const AName: string): string;
var
  Names: TArray<string>;
  I: Integer;
  Want: string;
begin
  Want := Trim(AName);
  if Want = '' then
    Exit(PreferMonoFontFamily);
  if FontFamilyInstalled(Want) then
    Exit(Want);
  Names := EnumerateMonospaceFontFamilies;
  for I := 0 to High(Names) do
    if SameText(Names[I], Want) then
      Exit(Names[I]);
  Result := PreferMonoFontFamily;
end;

const
  cShadowStyleIds: array[TShadowStyle] of string = ('classic', 'soft', 'none');

function ShadowStyleId(AStyle: TShadowStyle): string;
begin
  Result := cShadowStyleIds[AStyle];
end;

function ShadowStyleFromId(const AId: string): TShadowStyle;
var
  S: TShadowStyle;
begin
  for S := Low(TShadowStyle) to High(TShadowStyle) do
    if SameText(AId, cShadowStyleIds[S]) then
      Exit(S);
  Result := ssClassic;
end;

function DisplayTextContrastItems: TArray<string>;
begin
  Result := [T('ui.display.contrastOff', 'Off'),
    T('ui.display.contrastLow', 'Low'),
    T('ui.display.contrastMedium', 'Medium'),
    T('ui.display.contrastHigh', 'High')];
end;

function ClampTextContrast(ALevel: Integer): Integer;
begin
  Result := EnsureRange(ALevel, 0, cDisplayMaxTextContrast);
end;

function ClampCellExtra(APixels: Integer): Integer;
begin
  Result := EnsureRange(APixels, 0, cDisplayMaxCellExtra);
end;

function DisplayCellExtraItems: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, cDisplayMaxCellExtra + 1);
  for I := 0 to cDisplayMaxCellExtra do
    Result[I] := Format('%d %s', [I, T('ui.display.px', 'px')]);
end;

function DisplayShadowItems: TArray<string>;
begin
  Result := [T('ui.display.shadowClassic', 'Classic'),
    T('ui.display.shadowSoft', 'Soft'),
    T('ui.display.shadowNone', 'None')];
end;

const
  cMarkedRowStyleIds: array[TMarkedRowStyle] of string = ('text', 'band');

function MarkedRowStyleId(AStyle: TMarkedRowStyle): string;
begin
  Result := cMarkedRowStyleIds[AStyle];
end;

function MarkedRowStyleFromId(const AId: string): TMarkedRowStyle;
var
  S: TMarkedRowStyle;
begin
  for S := Low(TMarkedRowStyle) to High(TMarkedRowStyle) do
    if SameText(AId, cMarkedRowStyleIds[S]) then
      Exit(S);
  Result := mrsText;
end;

function DisplayMarkedRowItems: TArray<string>;
begin
  Result := [T('ui.display.markedText', 'Text color'),
    T('ui.display.markedBand', 'Row background')];
end;

function DefaultDisplaySettings: TDisplaySettings;
begin
  Result.FontName := '';
  Result.FontSize := cDisplayDefaultFontSize;
  Result.Zoom := 1.0;
  Result.CursorBlink := True;
  Result.CursorBlinkMs := cDisplayDefaultBlinkMs;
  Result.ShowPanelIcons := True;
  Result.ShowNotifications := True;
  Result.ShowTitleBar := True;
  Result.ShowMenuBar := True;
  Result.ShowKeyBar := True;
  Result.ShowStatusLine := True;
  Result.FileDrag := True;
  Result.ShadowStyle := ssClassic;
  Result.MarkedRowStyle := mrsText;
  Result.LineSpacing := False;
  Result.SnapFontSize := False;
  Result.TextContrast := 0;
  Result.CellWidthExtra := 0;
  Result.CellHeightExtra := 0;
  Result.SelectFolders := False;
  Result.Language := '';
end;

function ClampDisplayFontSize(ASize: Single): Single;
begin
  Result := EnsureRange(ASize, cDisplayMinFontSize, cDisplayMaxFontSize);
end;

function ClampDisplayZoom(AZoom: Single): Single;
begin
  Result := EnsureRange(AZoom, cDisplayMinZoom, cDisplayMaxZoom);
end;

function ClampDisplayBlinkMs(AMs: Integer): Integer;
var
  I, Best, Dist, D: Integer;
begin
  Best := cBlinkMs[0];
  Dist := Abs(AMs - Best);
  for I := 1 to High(cBlinkMs) do
  begin
    D := Abs(AMs - cBlinkMs[I]);
    if D < Dist then
    begin
      Dist := D;
      Best := cBlinkMs[I];
    end;
  end;
  Result := Best;
end;

function FontPointsToPixels(APoints: Single): Single;
begin
  Result := APoints * cDisplayPxPerPt;
end;

function FontPixelsToPoints(APixels: Single): Single;
begin
  Result := APixels / cDisplayPxPerPt;
end;

function DisplayFontSizeItems: TArray<string>;
var
  I: Integer;
  Pt: string;
begin
  Pt := T('ui.display.pt', 'pt');
  SetLength(Result, Length(cFontPoints));
  for I := 0 to High(cFontPoints) do
    Result[I] := FormatFloat('0.#', cFontPoints[I]) + ' ' + Pt;
end;

function DisplayZoomItems: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Length(cZoomPercents));
  for I := 0 to High(cZoomPercents) do
    Result[I] := Format('%d%%', [cZoomPercents[I]]);
end;

function DisplayBlinkMsItems: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Length(cBlinkMs));
  for I := 0 to High(cBlinkMs) do
    Result[I] := Format('%d ms', [cBlinkMs[I]]);
end;

function NearestIndex(AValue: Single; const AOpts: array of Integer): Integer;
var
  I: Integer;
  Dist, Best: Single;
begin
  Result := 0;
  Best := Abs(AValue - AOpts[0]);
  for I := 1 to High(AOpts) do
  begin
    Dist := Abs(AValue - AOpts[I]);
    if Dist < Best then
    begin
      Best := Dist;
      Result := I;
    end;
  end;
end;

function IndexOfDisplayFontSize(ASize: Single): Integer;
var
  I: Integer;
  Pt, Dist, Best: Single;
begin
  Pt := FontPixelsToPoints(ClampDisplayFontSize(ASize));
  Result := 0;
  Best := Abs(Pt - cFontPoints[0]);
  for I := 1 to High(cFontPoints) do
  begin
    Dist := Abs(Pt - cFontPoints[I]);
    if Dist < Best - 0.001 then
    begin
      Best := Dist;
      Result := I;
    end;
  end;
end;

function IndexOfDisplayZoom(AZoom: Single): Integer;
begin
  Result := NearestIndex(ClampDisplayZoom(AZoom) * 100.0, cZoomPercents);
end;

function IndexOfDisplayBlinkMs(AMs: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(cBlinkMs) do
    if cBlinkMs[I] = ClampDisplayBlinkMs(AMs) then
      Exit(I);
end;

function DisplayFontSizeAt(AIndex: Integer): Single;
begin
  if AIndex < 0 then
    AIndex := 0;
  if AIndex > High(cFontPoints) then
    AIndex := High(cFontPoints);
  Result := FontPointsToPixels(cFontPoints[AIndex]);
end;

function DisplayZoomAt(AIndex: Integer): Single;
begin
  if AIndex < 0 then
    AIndex := 0;
  if AIndex > High(cZoomPercents) then
    AIndex := High(cZoomPercents);
  Result := cZoomPercents[AIndex] / 100.0;
end;

function DisplayBlinkMsAt(AIndex: Integer): Integer;
begin
  if AIndex < 0 then
    AIndex := 0;
  if AIndex > High(cBlinkMs) then
    AIndex := High(cBlinkMs);
  Result := cBlinkMs[AIndex];
end;

function IndexOfFontName(const ANames: TArray<string>; const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ANames) do
    if SameText(ANames[I], AName) then
      Exit(I);
  Result := 0;
end;

function DisplayLanguageItems: TArray<string>;
begin
  Result := AvailableLocales;
end;

function DisplayLanguageName(const ALocale: string): string;
begin
  if SameText(ALocale, 'en') then
    Result := 'English'
  else if SameText(ALocale, 'ru') then
    Result := #$0420 + #$0443 + #$0441 + #$0441 + #$043A + #$0438 + #$0439 // Русский
  else if Trim(ALocale) = '' then
    Result := 'English'
  else
    Result := UpperCase(ALocale);
end;

procedure EnsureFontInList(var ANames: TArray<string>; const AName: string);
var
  I: Integer;
  Face: string;
begin
  Face := Trim(AName);
  if Face = '' then
    Exit;
  for I := 0 to High(ANames) do
    if SameText(ANames[I], Face) then
      Exit;
  SetLength(ANames, Length(ANames) + 1);
  for I := High(ANames) downto 1 do
    ANames[I] := ANames[I - 1];
  ANames[0] := Face;
end;

end.
