unit uWindowChrome;

{ Layout of the window chrome that lives in the character grid: the [+] button
  after the last workspace tab, the window title, the background-job chips and
  the window buttons. With the native title bar hidden the window buttons sit
  at the right end of the menu bar row (or of the tab bar row when the menu bar
  is hidden), and the free part of each of those rows drags the window.
  Pure layout and hit-testing; the window paints and acts on it. }

interface

uses
  System.SysUtils, System.Types, System.Math, uDualPanelUiTypes, uDualPanelJobChips;

type
  TWindowButton = (wbMinimize, wbMaximize, wbClose);

  /// <summary>The pieces of the window title, richest first to drop last;
  /// empty ones are left out.</summary>
  TWindowTitleParts = record
    FullName: string;
    ShortName: string;
    Version: string;
    SizeText: string;
    ZoomText: string;
    TabText: string;
    FpsText: string;
    /// <summary>"Administrator" or "Admin helper"; '' for an ordinary user.</summary>
    RightsText: string;
  end;

  TTabBarChrome = record
    /// <summary>Column of the [+] button, -1 when there is no room for it.</summary>
    PlusLeft: Integer;
    Strip: TJobStrip;
    /// <summary>Free columns [FreeLeft, FreeRight): the window title goes here
    /// and, with the native title bar hidden, the window is dragged by them.</summary>
    FreeLeft: Integer;
    FreeRight: Integer;
  end;

const
  /// <summary>Edges of a WM_SIZING drag, as WMSZ_LEFT .. WMSZ_BOTTOMRIGHT.</summary>
  cSizingLeft = 1;
  cSizingRight = 2;
  cSizingTop = 3;
  cSizingTopLeft = 4;
  cSizingTopRight = 5;
  cSizingBottom = 6;
  cSizingBottomLeft = 7;
  cSizingBottomRight = 8;
  /// <summary>The window is not made smaller than this many cells.</summary>
  cMinGridCols = 40;
  cMinGridRows = 12;
  cPlusCaption = '[+]';
  cWindowButtonsWidth = 9;
  /// <summary>Narrower than this the window buttons are not laid out.</summary>
  cMinWidthForButtons = 30;
  cMinTitleWidth = 4;

function WindowButtonCaption(AButton: TWindowButton; AMaximized: Boolean): string;
/// <summary>First column of the three window buttons, -1 when the row is too
/// narrow for them.</summary>
function WindowButtonsLeft(AWidth: Integer): Integer;
function HitWindowButton(AWidth, ACol: Integer; out AButton: TWindowButton): Boolean;
/// <summary>AText cut to AMaxLen columns, the last one an ellipsis when cut.</summary>
function FitTitle(const AText: string; AMaxLen: Integer): string;
/// <summary>The richest title that fits ARoom columns. As room shrinks the
/// parts go in this order: the full program name, the tab name, the zoom, the
/// window size in cells, the version, the frame rate; the short program name
/// stays and is cut with an ellipsis only when even it does not fit.</summary>
function ComposeTitle(const AParts: TWindowTitleParts; ARoom: Integer): string;
/// <summary>Right to left: window buttons (when AButtonsInRow), job chips and
/// list button, title; left to right: tabs, [+]. ATabsEnd is the first column
/// after the last tab and the gap that follows it.</summary>
/// <summary>Client width or height in pixels that holds a whole number of
/// cells (at least AMinCells): the nearest such size when ANearest, else the
/// largest one that fits. Rounded up to a pixel so the grid keeps every cell.</summary>
function GridClientExtent(AClient: Integer; ACell: Double; AMinCells: Integer;
  ANearest: Boolean): Integer;
/// <summary>Bends the rectangle of a window being resized from AEdge so its
/// client area (the rectangle less ANcW x ANcH of frame) is a whole number of
/// cells; the edge the user is not dragging stays put.</summary>
procedure SnapSizingRect(AEdge: Integer; var ARect: TRect; ANcW, ANcH: Integer;
  ACellW, ACellH: Double);
function LayoutTabBarChrome(ATabsEnd, AWidth: Integer; AButtonsInRow: Boolean;
  const AJobs: TArray<TPanelJobState>): TTabBarChrome;
function HitPlusButton(const AChrome: TTabBarChrome; ACol: Integer): Boolean;
/// <summary>True for a column of the free part of the tab bar row.</summary>
function InTabBarFreeZone(const AChrome: TTabBarChrome; ACol: Integer): Boolean;
/// <summary>True for a column of the menu bar row right of the menu titles
/// (AMenuEnd) and left of the window buttons.</summary>
function InMenuBarFreeZone(AMenuEnd, AWidth, ACol: Integer): Boolean;

implementation

const
  cGlyphMinimize = '_';
  cGlyphMaximize = #$25A1;
  cGlyphRestore = #$25A0;
  cGlyphClose = 'x';
  cEllipsis = #$2026;

function WindowButtonCaption(AButton: TWindowButton; AMaximized: Boolean): string;
begin
  case AButton of
    wbMinimize: Result := '[' + cGlyphMinimize + ']';
    wbMaximize:
      if AMaximized then
        Result := '[' + cGlyphRestore + ']'
      else
        Result := '[' + cGlyphMaximize + ']';
  else
    Result := '[' + cGlyphClose + ']';
  end;
end;

function WindowButtonsLeft(AWidth: Integer): Integer;
begin
  if AWidth < cMinWidthForButtons then
    Result := -1
  else
    Result := AWidth - cWindowButtonsWidth;
end;

function HitWindowButton(AWidth, ACol: Integer; out AButton: TWindowButton): Boolean;
var
  Left: Integer;
begin
  AButton := wbMinimize;
  Left := WindowButtonsLeft(AWidth);
  Result := (Left >= 0) and (ACol >= Left) and (ACol < AWidth);
  if Result then
    AButton := TWindowButton((ACol - Left) div 3);
end;

function FitTitle(const AText: string; AMaxLen: Integer): string;
begin
  if AMaxLen < 1 then
    Exit('');
  if Length(AText) <= AMaxLen then
    Exit(AText);
  Result := Copy(AText, 1, AMaxLen - 1) + cEllipsis;
end;

function GridClientExtent(AClient: Integer; ACell: Double; AMinCells: Integer;
  ANearest: Boolean): Integer;
var
  Cells: Integer;
begin
  if ACell <= 0 then
    Exit(AClient);
  if ANearest then
    Cells := Round(AClient / ACell)
  else
    Cells := Trunc(AClient / ACell + 0.0001);
  if Cells < AMinCells then
    Cells := AMinCells;
  Result := Ceil(Cells * ACell - 0.0001);
end;

procedure SnapSizingRect(AEdge: Integer; var ARect: TRect; ANcW, ANcH: Integer;
  ACellW, ACellH: Double);
var
  NewW, NewH: Integer;
begin
  if (ACellW <= 0) or (ACellH <= 0) then
    Exit;
  NewW := GridClientExtent(ARect.Right - ARect.Left - ANcW, ACellW, cMinGridCols, True) + ANcW;
  NewH := GridClientExtent(ARect.Bottom - ARect.Top - ANcH, ACellH, cMinGridRows, True) + ANcH;
  if AEdge in [cSizingLeft, cSizingTopLeft, cSizingBottomLeft] then
    ARect.Left := ARect.Right - NewW
  else if AEdge in [cSizingRight, cSizingTopRight, cSizingBottomRight] then
    ARect.Right := ARect.Left + NewW;
  if AEdge in [cSizingTop, cSizingTopLeft, cSizingTopRight] then
    ARect.Top := ARect.Bottom - NewH
  else if AEdge in [cSizingBottom, cSizingBottomLeft, cSizingBottomRight] then
    ARect.Bottom := ARect.Top + NewH;
end;

function BuildTitle(const AParts: TWindowTitleParts; ALevel: Integer): string;
var
  Inner: string;

  procedure AddInner(const AText: string);
  begin
    if AText = '' then
      Exit;
    if Inner <> '' then
      Inner := Inner + '  ';
    Inner := Inner + AText;
  end;

begin
  if (ALevel = 0) and (AParts.FullName <> '') then
    Result := AParts.FullName + ' - ' + AParts.ShortName
  else
    Result := AParts.ShortName;
  if (ALevel <= 4) and (AParts.Version <> '') then
    Result := Result + ' ' + AParts.Version;
  Inner := '';
  if ALevel <= 3 then
    AddInner(AParts.SizeText);
  if ALevel <= 2 then
    AddInner(AParts.ZoomText);
  if ALevel <= 1 then
    AddInner(AParts.TabText);
  if Inner <> '' then
    Result := Result + '  [' + Inner + ']';
  if (ALevel <= 5) and (AParts.RightsText <> '') then
    Result := Result + '  [' + AParts.RightsText + ']';
  if (ALevel <= 5) and (AParts.FpsText <> '') then
    Result := Result + '  [' + AParts.FpsText + ']';
end;

function ComposeTitle(const AParts: TWindowTitleParts; ARoom: Integer): string;
var
  Level: Integer;
begin
  for Level := 0 to 5 do
  begin
    Result := BuildTitle(AParts, Level);
    if Length(Result) <= ARoom then
      Exit;
  end;
  Result := FitTitle(AParts.ShortName, ARoom);
end;

function LayoutTabBarChrome(ATabsEnd, AWidth: Integer; AButtonsInRow: Boolean;
  const AJobs: TArray<TPanelJobState>): TTabBarChrome;
var
  RightEdge, StripLeft: Integer;
begin
  Result := Default(TTabBarChrome);
  RightEdge := AWidth;
  if AButtonsInRow and (WindowButtonsLeft(AWidth) >= 0) then
    RightEdge := WindowButtonsLeft(AWidth) - 1;

  Result.PlusLeft := -1;
  Result.FreeLeft := ATabsEnd;
  if ATabsEnd + Length(cPlusCaption) <= RightEdge then
  begin
    Result.PlusLeft := ATabsEnd;
    Result.FreeLeft := ATabsEnd + Length(cPlusCaption) + 1;
  end;

  Result.Strip := LayoutJobStrip(AJobs, Result.FreeLeft, RightEdge);
  Result.FreeRight := RightEdge;
  if Result.Strip.ListWidth > 0 then
  begin
    StripLeft := Result.Strip.ListLeft;
    if Length(Result.Strip.Chips) > 0 then
      StripLeft := Result.Strip.Chips[0].Left;
    Result.FreeRight := StripLeft - 1;
  end;
  if Result.FreeRight < Result.FreeLeft then
    Result.FreeRight := Result.FreeLeft;
end;

function HitPlusButton(const AChrome: TTabBarChrome; ACol: Integer): Boolean;
begin
  Result := (AChrome.PlusLeft >= 0) and (ACol >= AChrome.PlusLeft) and
    (ACol < AChrome.PlusLeft + Length(cPlusCaption));
end;

function InTabBarFreeZone(const AChrome: TTabBarChrome; ACol: Integer): Boolean;
begin
  Result := (ACol >= AChrome.FreeLeft) and (ACol < AChrome.FreeRight);
end;

function InMenuBarFreeZone(AMenuEnd, AWidth, ACol: Integer): Boolean;
var
  Right: Integer;
begin
  Right := WindowButtonsLeft(AWidth);
  if Right < 0 then
    Right := AWidth;
  Result := (ACol >= AMenuEnd) and (ACol < Right);
end;

end.
