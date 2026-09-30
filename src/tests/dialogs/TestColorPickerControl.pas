unit TestColorPickerControl;

{ uColorPickerControl: HSL conversion, the swatch grid, slider and hex input,
  mouse clicks, and what the drawn grid shows. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestColorPickerControl = class
  public
    [Test] procedure TestHslRoundTrip;
    [Test] procedure TestGridColors;
    [Test] procedure TestInitAndHex;
    [Test] procedure TestGridKeys;
    [Test] procedure TestSliderKeys;
    [Test] procedure TestHexTyping;
    [Test] procedure TestClicks;
    [Test] procedure TestDraw;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uTerminalTypes, uInputLine, uColorPickerControl;

function Rgb(R, G, B: Cardinal): TAlphaColor;
begin
  Result := TAlphaColor($FF000000 or (R shl 16) or (G shl 8) or B);
end;

procedure PressKey(var S: TColorPickerState; AKey: Word; AShift: TShiftState = []);
var
  K: Word;
  Ch: Char;
begin
  K := AKey;
  Ch := #0;
  ColorPickerHandleKey(S, K, AShift, Ch);
end;

procedure TTestColorPickerControl.TestHslRoundTrip;
var
  H, S, L: Integer;
begin
  ColorToHsl(Rgb($FF, 0, 0), H, S, L);
  Assert.IsTrue((H = 0) and (S = 100) and (L = 50), 'red is 0/100/50');
  ColorToHsl(Rgb(0, $FF, 0), H, S, L);
  Assert.IsTrue((H = 120) and (S = 100) and (L = 50), 'green is 120/100/50');
  ColorToHsl(Rgb(0, 0, $FF), H, S, L);
  Assert.IsTrue((H = 240) and (S = 100) and (L = 50), 'blue is 240/100/50');
  ColorToHsl(Rgb($80, $80, $80), H, S, L);
  Assert.IsTrue((S = 0) and (L = 50), 'gray has no saturation');
  Assert.AreEqual(Rgb($FF, 0, 0), HslToColor(0, 100, 50), 'red back');
  Assert.AreEqual(Rgb(0, $FF, $FF), HslToColor(180, 100, 50), 'cyan');
  Assert.AreEqual(Rgb(0, 0, 0), HslToColor(77, 40, 0), 'black at any hue');
  Assert.AreEqual(Rgb($FF, $FF, $FF), HslToColor(77, 40, 100), 'white at any hue');
  Assert.AreEqual(HslToColor(10, 50, 50), HslToColor(370, 50, 50), 'hue wraps');
end;

procedure TTestColorPickerControl.TestGridColors;
begin
  Assert.AreEqual(HslToColor(0, 100, 90), ColorPickerGridColor(0, 0, 100), 'top left is the lightest red');
  Assert.AreEqual(HslToColor(120, 100, 50), ColorPickerGridColor(8, 4, 100), 'hue column 8, middle row');
  Assert.AreEqual(Rgb(0, 0, 0), ColorPickerGridColor(0, cPickerGrayLine, 100), 'gray ramp starts black');
  Assert.AreEqual(Rgb($FF, $FF, $FF), ColorPickerGridColor(cPickerHues - 1, cPickerGrayLine, 100),
    'gray ramp ends white');
  Assert.AreNotEqual(ColorPickerGridColor(3, 4, 100), ColorPickerGridColor(3, 4, 40), 'saturation changes the grid');
end;

procedure TTestColorPickerControl.TestInitAndHex;
var
  S: TColorPickerState;
begin
  ColorPickerInit(S, Rgb($33, $66, $99), Rgb(1, 2, 3));
  Assert.AreEqual('#336699', ColorPickerHex(S), 'hex of the start color');
  Assert.AreEqual('#336699', S.HexEdit.Text, 'the hex field shows it');
  Assert.AreEqual(Rgb(1, 2, 3), S.Orig, 'the original is kept apart');
  ColorPickerSetColor(S, Rgb(0, $FF, 0));
  Assert.AreEqual('#00FF00', ColorPickerHex(S), 'SetColor');
  Assert.AreEqual(120, S.H, 'SetColor updates the hue');
end;

procedure TTestColorPickerControl.TestGridKeys;
var
  S: TColorPickerState;
begin
  ColorPickerInit(S, Rgb($FF, 0, 0), Rgb($FF, 0, 0)); // pure red: row 4 is L 50
  S.Line := 4;
  S.GridCol := 0;
  PressKey(S, vkRight);
  Assert.AreEqual(1, S.GridCol, 'Right moves the cursor');
  Assert.AreEqual(ColorPickerGridColor(1, 4, S.GridSat), S.Color, 'and picks that cell');
  PressKey(S, vkEnd);
  Assert.AreEqual(cPickerHues - 1, S.GridCol, 'End goes to the last hue');
  PressKey(S, vkRight);
  Assert.AreEqual(cPickerHues - 1, S.GridCol, 'Right stops at the last hue');
  PressKey(S, vkHome);
  Assert.AreEqual(0, S.GridCol, 'Home goes to the first hue');
  PressKey(S, vkDown);
  Assert.AreEqual(5, S.Line, 'Down moves to the next lightness row');
  Assert.AreEqual(ColorPickerGridColor(0, 5, S.GridSat), S.Color, 'and picks the cell there');
  S.Line := 0;
  PressKey(S, vkUp);
  Assert.AreEqual(0, S.Line, 'Up stops at the top');
end;

procedure TTestColorPickerControl.TestSliderKeys;
var
  S: TColorPickerState;
begin
  ColorPickerInit(S, Rgb(100, 50, 25), Rgb(0, 0, 0));
  S.Line := cPickerLineR;
  PressKey(S, vkRight);
  Assert.AreEqual(Rgb(101, 50, 25), S.Color, 'Right adds 1 to red');
  PressKey(S, vkRight, [ssShift]);
  Assert.AreEqual(Rgb(111, 50, 25), S.Color, 'Shift+Right adds 10');
  PressKey(S, vkHome);
  Assert.AreEqual(Rgb(0, 50, 25), S.Color, 'Home sets red to 0');
  PressKey(S, vkEnd);
  Assert.AreEqual(Rgb(255, 50, 25), S.Color, 'End sets red to 255');
  PressKey(S, vkRight);
  Assert.AreEqual(Rgb(255, 50, 25), S.Color, 'red stays at 255');
  Assert.AreEqual('#FF3219', S.HexEdit.Text, 'the hex field follows');

  ColorPickerSetColor(S, Rgb($FF, 0, 0));
  S.Line := cPickerLineL;
  PressKey(S, vkHome);
  Assert.AreEqual(Rgb(0, 0, 0), S.Color, 'L = 0 is black');
  Assert.AreEqual(0, S.H, 'the hue is kept at black');
  PressKey(S, vkRight, [ssShift]);
  Assert.AreEqual(HslToColor(0, 100, 10), S.Color, 'and comes back when lightness rises');

  S.Line := cPickerLineS;
  PressKey(S, vkHome);
  Assert.AreEqual(HslToColor(0, 0, 10), S.Color, 'S = 0 is gray');
  S.Line := cPickerLineH;
  PressKey(S, vkEnd);
  Assert.AreEqual(359, S.H, 'hue goes to 359');
end;

procedure TTestColorPickerControl.TestHexTyping;
var
  S: TColorPickerState;
  K: Word;
  Ch: Char;
begin
  ColorPickerInit(S, Rgb(0, 0, 0), Rgb(0, 0, 0));
  S.Line := cPickerLineHex;
  InputLineSetText(S.HexEdit, '#12345');
  K := 0;
  Ch := '6';
  Assert.IsTrue(ColorPickerHandleKey(S, K, [], Ch), 'a typed character is used');
  Assert.AreEqual('#123456', S.HexEdit.Text, 'the character lands in the field');
  Assert.AreEqual(Rgb($12, $34, $56), S.Color, 'a complete hex becomes the color');
  K := vkBack;
  Ch := #0;
  ColorPickerHandleKey(S, K, [], Ch);
  Assert.AreEqual(Rgb($12, $34, $56), S.Color, 'an incomplete hex leaves the color alone');
end;

procedure TTestColorPickerControl.TestClicks;
var
  S: TColorPickerState;
begin
  ColorPickerInit(S, Rgb(10, 20, 30), Rgb(9, 9, 9));
  ColorPickerClick(S, 10, 2, 1);
  Assert.AreEqual(ColorPickerGridColor(5, 2, S.GridSat), S.Color, 'a grid click picks the cell under it');
  Assert.AreEqual(5, S.GridCol);
  Assert.AreEqual(2, S.Line);
  ColorPickerClick(S, 2 + 31, cPickerLineR, 1);
  Assert.AreEqual(255, Integer(TAlphaColorRec(S.Color).R), 'a click at the right end of the bar is the maximum');
  ColorPickerClick(S, 2, cPickerLineR, 1);
  Assert.AreEqual(0, Integer(TAlphaColorRec(S.Color).R), 'a click at the left end is zero');
  ColorPickerClick(S, 19, cPickerLineHex, 1);
  Assert.AreEqual(Rgb(9, 9, 9), S.Color, 'a click on the "was" swatch restores the original');
  Assert.AreEqual(cPickerLineHex, S.Line, 'and focuses the hex line');
end;

procedure TTestColorPickerControl.TestDraw;
var
  Grid: TTerminalGrid;
  S: TColorPickerState;
  X, Y: Integer;
begin
  SetLength(Grid, 20);
  for Y := 0 to High(Grid) do
  begin
    SetLength(Grid[Y], 60);
    for X := 0 to 59 do
      Grid[Y][X] := TCharCell.Make(' ', $FF000000, $FF000000);
  end;
  ColorPickerInit(S, Rgb(10, 20, 30), Rgb(9, 9, 9));
  S.Line := 4;
  S.GridCol := 3;
  ColorPickerDraw(Grid, 1, 1, S, True, True, $FF000000, $FFFFFFFF);
  Assert.AreEqual(ColorPickerGridColor(0, 0, S.GridSat), Grid[1][1].BgColor, 'the grid starts at the control origin');
  Assert.AreEqual('[', string(Grid[1 + 4][1 + 3 * 2].CharValue), 'the cursor cell is bracketed');
  Assert.AreEqual(ColorPickerGridColor(3, 4, S.GridSat), Grid[1 + 4][1 + 3 * 2].BgColor, 'on its own color');
  Assert.AreEqual(Rgb(9, 9, 9), Grid[1 + cPickerLineHex][1 + 18].BgColor, 'the "was" swatch shows the original');
  Assert.AreEqual(Rgb(10, 20, 30), Grid[1 + cPickerLineHex][1 + 28].BgColor, 'the "now" swatch shows the color');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestColorPickerControl);

end.
