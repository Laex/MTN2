unit uDualPanelOverlays;

{ Shared Host overlay chrome for Dual Panel specialized UIs (drive / job /
  search / stub / user menu). Layout and input stay in TDualPanelWindow. }

interface

uses
  System.SysUtils, System.UITypes,
  uTerminalTypes, uThemeTypes, uThemeDrawing;

const
  /// <summary>Menu hotkey letters in every menu (F9 bar and dropdowns, F2
  /// user menu) -- dark red on whatever background the row has, fixed
  /// rather than theme-driven at the user's request (how FAR/NDN menus
  /// always looked), and one colour so all menus read the same.</summary>
  cMenuHotKeyFg = TAlphaColor($FFC00000);

/// <summary>Resolves a menu item's hotkey after translation (every menu: F9,
/// Sort, Column modes). A translation marks its own letter with '&'
/// ("&Файлы", "Ра&змер"; '&&' is a literal '&'): the marker is stripped from
/// ACaption and its letter wins. Without a marker AHot is kept only when it
/// occurs in the caption the user sees -- an English letter invisible in a
/// Russian caption would be a hidden hotkey -- else AHot becomes #0. APos is
/// the 1-based position to highlight, 0 for none.</summary>
procedure MenuResolveMnemonic(var ACaption: string; var AHot: Char; out APos: Integer);
/// <summary>First case-insensitive occurrence of AHot in ACaption, 0 if none.</summary>
function MenuFindHotPos(const ACaption: string; AHot: Char): Integer;
/// <summary>Does the typed char fire hotkey AHot? AOtherLayout = False:
/// same letter (any case, any alphabet); True: the same physical key on the
/// other keyboard layout (QWERTY <-> JCUKEN). Callers try all items with
/// False first, then with True.</summary>
function MenuHotKeyMatches(AHot, ATyped: Char; AOtherLayout: Boolean): Boolean;

procedure DrawHostOverlayFrame(const AGrid: TTerminalGrid;
  const ATheme: IThemeRenderer; const ABounds: TRectI; const ATitle: string;
  AFallbackFg, AFallbackBg, AFallbackFrame, AFallbackTitleFg: TAlphaColor);

/// <summary>
/// Body/list colors for Host dialog overlays. Base fg/bg comes from the
/// active theme's ResolveDialogRowColors (white bg / black text, black on
/// cyan cursor, for the FAR/NDN default); falls back to that same white/black
/// pair when no theme is assigned. ASelected: dark-red accent (errors).
/// AIsDirectory: dark-cyan hot tips (callers reuse this flag for hints).
/// Fallbacks (AFallbackFg/AFallbackBg) unused when Theme is assigned.
/// </summary>
procedure ResolveOverlayTextColors(const ATheme: IThemeRenderer;
  AIsDirectory, ASelected, ACursor: Boolean;
  AFallbackFg, AFallbackBg: TAlphaColor; out AFg, ABg: TAlphaColor);

procedure PutOverlayText(const AGrid: TTerminalGrid;
  const ATheme: IThemeRenderer; AX, AY: Integer; const AText: string;
  AIsDirectory, ASelected, ACursor: Boolean;
  AFallbackFg, AFallbackBg: TAlphaColor);

implementation

uses
  System.Character, uInputLine;

function MenuHotUpper(AChar: Char): Char;
begin
  Result := AChar.ToUpper; // System.UpCase only folds a..z
end;

function MenuExtractMnemonic(var ACaption: string; out AHot: Char;
  out APos: Integer): Boolean;
var
  I: Integer;
  S: string;
begin
  Result := False;
  AHot := #0;
  APos := 0;
  if Pos('&', ACaption) = 0 then
    Exit;
  S := '';
  I := 1;
  while I <= Length(ACaption) do
  begin
    if (ACaption[I] = '&') and (I < Length(ACaption)) then
    begin
      Inc(I);
      if (ACaption[I] <> '&') and not Result then
      begin
        Result := True;
        AHot := MenuHotUpper(ACaption[I]);
        APos := Length(S) + 1;
      end;
    end;
    S := S + ACaption[I];
    Inc(I);
  end;
  ACaption := S;
end;

function MenuFindHotPos(const ACaption: string; AHot: Char): Integer;
var
  I: Integer;
begin
  Result := 0;
  if AHot = #0 then
    Exit;
  for I := 1 to Length(ACaption) do
    if MenuHotUpper(ACaption[I]) = MenuHotUpper(AHot) then
      Exit(I);
end;

procedure MenuResolveMnemonic(var ACaption: string; var AHot: Char; out APos: Integer);
var
  MarkHot: Char;
begin
  if MenuExtractMnemonic(ACaption, MarkHot, APos) then
  begin
    AHot := MarkHot;
    Exit;
  end;
  APos := MenuFindHotPos(ACaption, AHot);
  if APos = 0 then
    AHot := #0;
end;

function MenuHotKeyMatches(AHot, ATyped: Char; AOtherLayout: Boolean): Boolean;
begin
  if (AHot = #0) or (ATyped < ' ') then
    Exit(False);
  if AOtherLayout then
    Result := TextKeyLayoutAlternate(ATyped) = MenuHotUpper(AHot)
  else
    Result := MenuHotUpper(ATyped) = MenuHotUpper(AHot);
end;

const
  cDialogFg = TAlphaColor($FF000000);
  cDialogBg = TAlphaColor($FFFFFFFF);
  // Accents readable on white (panel yellow/cyan fall flat on dialog body).
  cAccentFg = TAlphaColor($FFAA0000); // selected / error
  cHotFg    = TAlphaColor($FF008888); // hot tips / status hints

procedure DrawHostOverlayFrame(const AGrid: TTerminalGrid;
  const ATheme: IThemeRenderer; const ABounds: TRectI; const ATitle: string;
  AFallbackFg, AFallbackBg, AFallbackFrame, AFallbackTitleFg: TAlphaColor);
var
  Cap: string;
begin
  if (ABounds.Width < 4) or (ABounds.Height < 3) then
    Exit;
  if Assigned(ATheme) then
  begin
    ATheme.DrawDialogFrame(AGrid, ABounds, ATitle, [twFocused]);
    DrawDialogShadow(AGrid, ABounds);
    Exit;
  end;
  DrawPanelFrameGlyphs(AGrid, ABounds, chDblTL, chDblTR, chDblBL, chDblBR, chDblH, chDblV,
    AFallbackFrame, cDialogFg, cDialogBg);
  Cap := ' ' + ATitle + ' ';
  PutGridText(AGrid, ABounds.Left + 2, ABounds.Top, Cap, AFallbackTitleFg, AFallbackFrame);
  DrawDialogShadow(AGrid, ABounds);
end;

procedure ResolveOverlayTextColors(const ATheme: IThemeRenderer;
  AIsDirectory, ASelected, ACursor: Boolean;
  AFallbackFg, AFallbackBg: TAlphaColor; out AFg, ABg: TAlphaColor);
begin
  // Dialog body: cursor = black on cyan; selected/error = dark red;
  // AIsDirectory reused by callers as "hot tip" → dark cyan. Fallbacks ignored
  // when Theme is set so panel-blue colours never paint over dialog chrome.
  if ACursor then
  begin
    if Assigned(ATheme) then
      ATheme.ResolveDialogRowColors(True, AFg, ABg)
    else
    begin
      AFg := TAlphaColor($FF000000);
      ABg := TAlphaColor($FF00AAAA);
    end;
    Exit;
  end;
  if Assigned(ATheme) then
    ATheme.ResolveDialogRowColors(False, AFg, ABg)
  else
  begin
    AFg := cDialogFg;
    ABg := cDialogBg;
  end;
  if ASelected then
    AFg := cAccentFg
  else if AIsDirectory then
    AFg := cHotFg;
end;

procedure PutOverlayText(const AGrid: TTerminalGrid;
  const ATheme: IThemeRenderer; AX, AY: Integer; const AText: string;
  AIsDirectory, ASelected, ACursor: Boolean;
  AFallbackFg, AFallbackBg: TAlphaColor);
var
  Fg, Bg: TAlphaColor;
begin
  ResolveOverlayTextColors(ATheme, AIsDirectory, ASelected, ACursor,
    AFallbackFg, AFallbackBg, Fg, Bg);
  PutGridText(AGrid, AX, AY, AText, Fg, Bg);
end;

end.
