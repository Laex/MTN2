unit uDisplaySettings;

{ Stage 55: font / zoom / cursor-blink / panel-icon settings used by the
  Display dialog, TTerminalRenderer.SetFont, and session.json. }

interface

uses
  System.SysUtils;

const
  cDisplayMinFontSize = 8;
  cDisplayMaxFontSize = 32;
  cDisplayDefaultFontSize = 14;
  cDisplayDefaultBlinkMs = 530;
  cDisplayMinZoom = 0.5;
  cDisplayMaxZoom = 3.0;

type
  TDisplaySettings = record
    FontName: string;
    FontSize: Single;
    Zoom: Single;
    CursorBlink: Boolean;
    CursorBlinkMs: Integer;
    ShowPanelIcons: Boolean;
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
function DisplayFontSizeItems: TArray<string>;
function DisplayZoomItems: TArray<string>;
function DisplayBlinkMsItems: TArray<string>;
function IndexOfDisplayFontSize(ASize: Single): Integer;
function IndexOfDisplayZoom(AZoom: Single): Integer;
function IndexOfDisplayBlinkMs(AMs: Integer): Integer;
function DisplayFontSizeAt(AIndex: Integer): Single;
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

implementation

uses
  System.Math, System.Classes, System.IOUtils, System.Generics.Collections,
  Winapi.Windows, uStrings;

const
  cFontSizes: array[0..12] of Integer =
    (8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 28, 32);
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

function DefaultDisplaySettings: TDisplaySettings;
begin
  Result.FontName := '';
  Result.FontSize := cDisplayDefaultFontSize;
  Result.Zoom := 1.0;
  Result.CursorBlink := True;
  Result.CursorBlinkMs := cDisplayDefaultBlinkMs;
  Result.ShowPanelIcons := True;
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

function DisplayFontSizeItems: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Length(cFontSizes));
  for I := 0 to High(cFontSizes) do
    Result[I] := Format('%d pt', [cFontSizes[I]]);
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
begin
  Result := NearestIndex(ClampDisplayFontSize(ASize), cFontSizes);
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
  if AIndex > High(cFontSizes) then
    AIndex := High(cFontSizes);
  Result := cFontSizes[AIndex];
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
