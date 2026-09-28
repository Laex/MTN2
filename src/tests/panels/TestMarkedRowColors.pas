unit TestMarkedRowColors;

{ Marked panel rows in every built-in theme: the mark reads on its
  background (WCAG contrast >= 4.5), a marked row under the cursor differs
  from the plain cursor, and the "Row background" style (mrsBand) only
  changes marked rows away from the cursor. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMarkedRowColors = class
  public
    [Test] procedure TestContrast;
    [Test] procedure TestStatesDiffer;
    [Test] procedure TestBandStyle;
  end;

implementation

uses
  System.SysUtils, System.UITypes, System.Math,
  uThemeTypes, uThemeRegistry, uThemeDrawing, uDisplaySettings;

const
  cMinContrast = 4.5;

function Channel(AValue: Byte): Double;
begin
  Result := AValue / 255;
  if Result <= 0.03928 then
    Result := Result / 12.92
  else
    Result := Power((Result + 0.055) / 1.055, 2.4);
end;

function Luminance(AColor: TAlphaColor): Double;
var
  C: TAlphaColorRec;
begin
  C := TAlphaColorRec(AColor);
  Result := 0.2126 * Channel(C.R) + 0.7152 * Channel(C.G) + 0.0722 * Channel(C.B);
end;

function Contrast(AFg, ABg: TAlphaColor): Double;
var
  L1, L2: Double;
begin
  L1 := Luminance(AFg);
  L2 := Luminance(ABg);
  Result := (Max(L1, L2) + 0.05) / (Min(L1, L2) + 0.05);
end;

type
  TRowColors = record
    Fg, Bg: TAlphaColor;
  end;

function Row(const ATheme: IThemeRenderer; ASelected, ACursor, ASideActive: Boolean;
  AStyle: TMarkedRowStyle = mrsText): TRowColors;
begin
  ResolvePanelRowColors(ATheme, False, False, False, '', ASelected, ACursor,
    ASideActive, AStyle, Result.Fg, Result.Bg);
end;

function Same(const A, B: TRowColors): Boolean;
begin
  Result := (A.Fg = B.Fg) and (A.Bg = B.Bg);
end;

procedure CheckContrast(const AName, AState: string; const AColors: TRowColors);
var
  Ratio: Double;
begin
  Ratio := Contrast(AColors.Fg, AColors.Bg);
  Assert.IsTrue(Ratio >= cMinContrast,
    Format('%s, %s: contrast %.2f < %.1f', [AName, AState, Ratio, cMinContrast]));
end;

procedure TTestMarkedRowColors.TestContrast;
var
  Info: TThemeInfo;
  Theme: IThemeRenderer;
begin
  for Info in GetAvailableThemes do
  begin
    Theme := CreateThemeByName(Info.Id);
    CheckContrast(Info.Id, 'marked', Row(Theme, True, False, True));
    CheckContrast(Info.Id, 'marked + cursor', Row(Theme, True, True, True));
    CheckContrast(Info.Id, 'marked + idle cursor', Row(Theme, True, True, False));
    CheckContrast(Info.Id, 'marked band', Row(Theme, True, False, True, mrsBand));
  end;
end;

procedure TTestMarkedRowColors.TestStatesDiffer;
var
  Info: TThemeInfo;
  Theme: IThemeRenderer;
  Plain, Marked, Cursor, MarkedCursor, Band: TRowColors;
begin
  for Info in GetAvailableThemes do
  begin
    Theme := CreateThemeByName(Info.Id);
    Plain := Row(Theme, False, False, True);
    Marked := Row(Theme, True, False, True);
    Cursor := Row(Theme, False, True, True);
    MarkedCursor := Row(Theme, True, True, True);
    Band := Row(Theme, True, False, True, mrsBand);
    Assert.IsFalse(Same(Marked, Plain), Info.Id + ': marked looks plain');
    Assert.IsFalse(Same(MarkedCursor, Cursor), Info.Id + ': marked + cursor looks like the cursor');
    Assert.IsFalse(Same(MarkedCursor, Marked), Info.Id + ': marked + cursor looks like marked');
    Assert.IsTrue(Band.Bg <> Plain.Bg, Info.Id + ': band on the panel background');
    Assert.IsTrue(Band.Bg <> Cursor.Bg, Info.Id + ': band on the cursor background');
    Assert.IsFalse(Same(Band, MarkedCursor), Info.Id + ': band looks like marked + cursor');
  end;
end;

procedure TTestMarkedRowColors.TestBandStyle;
var
  Theme: IThemeRenderer;
  BandFg, BandBg, Fg, Bg: TAlphaColor;
begin
  Theme := CreateThemeByName('NDN');
  Theme.ResolveMarkedRowBand(BandFg, BandBg);
  Theme.ResolveFileRowColors(False, False, False, '', True, False, True, Fg, Bg);
  Assert.IsTrue((Row(Theme, True, False, True, mrsText).Fg = Fg) and
    (Row(Theme, True, False, True, mrsText).Bg = Bg), 'text style: theme colours');
  Assert.IsTrue(Row(Theme, True, False, True, mrsBand).Bg = BandBg, 'band style: marked row');
  Assert.IsTrue(Row(Theme, True, False, False, mrsBand).Bg = BandBg, 'band style: inactive panel too');
  Assert.IsTrue(Same(Row(Theme, True, True, True, mrsBand), Row(Theme, True, True, True)),
    'band style: cursor row unchanged');
  Assert.IsTrue(Same(Row(Theme, False, False, True, mrsBand), Row(Theme, False, False, True)),
    'band style: unmarked row unchanged');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMarkedRowColors);

end.
