unit uThemeRegistry;

{ Stage 27: catalog of built-in IThemeRenderer "looks" (chrome/skin), keyed
  by a stable Id persisted in session.json (TMtnSession.ThemeName) — distinct
  from uColorCoding's on-disk fileColoring theme *file*, which is a separate,
  independent axis (see uColorCoding.pas header comment). Single source of
  truth for both TMainForm.CreateTheme and the theme-picker dialog, so the
  two never drift out of sync. }

interface

uses
  uThemeTypes;

type
  TThemeInfo = record
    Id: string;
    DisplayName: string;
  end;

/// <summary>Built-in themes, display order = picker order.</summary>
function GetAvailableThemes: TArray<TThemeInfo>;
/// <summary>Theme named AId, or the default when AId is blank/unrecognized —
/// never fails.</summary>
function CreateThemeByName(const AId: string): IThemeRenderer;
function DefaultThemeId: string;

implementation

uses
  System.SysUtils,
  uNDNTheme, uModernUnicodeTheme, uASCIITheme,
  uTotalCommanderTheme, uSolarizedDarkTheme, uDraculaTheme, uNordTheme,
  uHighContrastTheme;

const
  cThemeNDN     = 'NDN';
  cThemeModern  = 'ModernUnicode';
  cThemeASCII   = 'ASCII';
  cThemeTC      = 'TotalCommander';
  cThemeSolar   = 'SolarizedDark';
  cThemeDracula = 'Dracula';
  cThemeNord    = 'Nord';
  cThemeHiCon   = 'HighContrast';

  cThemes: array[0..7] of TThemeInfo = (
    (Id: cThemeNDN;     DisplayName: 'Classic FAR (NDN)'),
    (Id: cThemeModern;  DisplayName: 'Modern Unicode'),
    (Id: cThemeASCII;   DisplayName: 'ASCII (no box-drawing glyphs)'),
    (Id: cThemeTC;      DisplayName: 'Total Commander (light)'),
    (Id: cThemeSolar;   DisplayName: 'Solarized Dark'),
    (Id: cThemeDracula; DisplayName: 'Dracula'),
    (Id: cThemeNord;    DisplayName: 'Nord'),
    (Id: cThemeHiCon;   DisplayName: 'High Contrast (accessibility)')
  );

function GetAvailableThemes: TArray<TThemeInfo>;
var
  I: Integer;
begin
  SetLength(Result, Length(cThemes));
  for I := 0 to High(cThemes) do
    Result[I] := cThemes[I];
end;

function CreateThemeByName(const AId: string): IThemeRenderer;
begin
  if SameText(AId, cThemeModern) then
    Result := TModernUnicodeTheme.Create
  else if SameText(AId, cThemeASCII) then
    Result := TASCIIOnlyTheme.Create
  else if SameText(AId, cThemeTC) then
    Result := TTotalCommanderTheme.Create
  else if SameText(AId, cThemeSolar) then
    Result := TSolarizedDarkTheme.Create
  else if SameText(AId, cThemeDracula) then
    Result := TDraculaTheme.Create
  else if SameText(AId, cThemeNord) then
    Result := TNordTheme.Create
  else if SameText(AId, cThemeHiCon) then
    Result := THighContrastTheme.Create
  else
    Result := TNDNTheme.Create; // default / cThemeNDN / unrecognized
end;

function DefaultThemeId: string;
begin
  Result := cThemeNDN;
end;

end.
