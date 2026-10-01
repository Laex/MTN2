unit TestDialogHotKeyDraw;

{ Hotkey letters in dialog captions, as every theme draws them: the '&'
  marker takes no cell, the caption stays contiguous and centred by its
  visible length, and the marked letter stands out from the rest of the
  caption (another colour or an underline) on normal and focused buttons,
  checkboxes and radio buttons. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogHotKeyDraw = class
  public
    [Test] procedure TestStripHotKeyMarker;
    [Test] procedure TestEveryThemeMarksTheLetter;
    [Test] procedure TestButtonCentredByVisibleText;
  end;

implementation

uses
  System.SysUtils, System.UITypes,
  uTerminalTypes, uThemeTypes,
  uThemeRegistry, uThemeSpec, uDataTheme;

const
  cW = 30;

function Themes: TArray<IThemeRenderer>;
var
  Info: TThemeInfo;
begin
  SetLength(Result, 0);
  for Info in GetAvailableThemes do
    if Info.BuiltIn then
      Result := Result + [CreateThemeByName(Info.Id)];
end;

function RowText(const AGrid: TTerminalGrid): string;
var
  X: Integer;
begin
  Result := '';
  for X := 0 to cW - 1 do
    Result := Result + AGrid[0][X].CharValue;
end;

function NewGrid: TTerminalGrid;
begin
  AllocTerminalGrid(Result, cW, 1);
  ClearTerminalGrid(Result, TAlphaColors.White, TAlphaColors.Black, '.');
end;

function Stands(const AHot, AOther: TCharCell): Boolean;
begin
  Result := (AHot.FgColor <> AOther.FgColor) or
    ((ccaUnderline in AHot.Attributes) and not (ccaUnderline in AOther.Attributes));
end;

procedure CheckCaption(const AGrid: TTerminalGrid; const AWhat: string);
var
  Row: string;
  P: Integer;
begin
  Row := RowText(AGrid);
  Assert.IsTrue(Pos('&', Row) = 0, AWhat + ': the marker is not drawn: ' + Row);
  P := Pos('Skip', Row);
  Assert.IsTrue(P > 0, AWhat + ': caption drawn in one piece: ' + Row);
  // 'S' is the hotkey, 'k' next to it is plain caption text.
  Assert.IsTrue(Stands(AGrid[0][P - 1], AGrid[0][P]),
    AWhat + ': the hotkey letter stands out');
  Assert.IsFalse(Stands(AGrid[0][P], AGrid[0][P + 1]),
    AWhat + ': the rest of the caption is plain');
end;

procedure TTestDialogHotKeyDraw.TestStripHotKeyMarker;
var
  P: Integer;
begin
  Assert.AreEqual('Skip', StripHotKeyMarker('&Skip', P));
  Assert.AreEqual(1, P, '&Skip: first letter');
  Assert.AreEqual('Rename', StripHotKeyMarker('Re&name', P));
  Assert.AreEqual(3, P, 'Re&name: n');
  Assert.AreEqual('A&B', StripHotKeyMarker('A&&B', P));
  Assert.AreEqual(0, P, '&& is a literal &, not a marker');
  Assert.AreEqual('x&y', StripHotKeyMarker('x&&&y', P));
  Assert.AreEqual(3, P, 'a marker after a literal &');
  Assert.AreEqual('End', StripHotKeyMarker('End&', P));
  Assert.AreEqual(0, P, 'a trailing & marks nothing');
  Assert.AreEqual('Plain', StripHotKeyMarker('Plain', P));
  Assert.AreEqual(0, P, 'no marker');
  Assert.AreEqual(#$0418, HotKeyCharOf('Пере&именовать'), 'hotkey letter in upper case');
  Assert.AreEqual(#0, HotKeyCharOf('Отмена'), 'no marker, no hotkey');
end;

procedure TTestDialogHotKeyDraw.TestEveryThemeMarksTheLetter;
var
  Theme: IThemeRenderer;
  Grid: TTerminalGrid;
  Box: TRectI;
  Name: string;
  State: TThemeWidgetState;
begin
  Box := TRectI.Make(2, 0, 16, 0);
  for Theme in Themes do
  begin
    Name := (Theme as TDataTheme).Spec.Id;
    for State in [[], [twFocused], [twSelected]] do
    begin
      Grid := NewGrid;
      Theme.DrawButton(Grid, Box, '&Skip', State);
      CheckCaption(Grid, Name + ' button');

      Grid := NewGrid;
      Theme.DrawCheckBox(Grid, Box, '&Skip', True, State);
      CheckCaption(Grid, Name + ' checkbox');

      Grid := NewGrid;
      Theme.DrawRadioBox(Grid, Box, '&Skip', False, State);
      CheckCaption(Grid, Name + ' radio');
    end;
  end;
end;

procedure TTestDialogHotKeyDraw.TestButtonCentredByVisibleText;
var
  Theme: IThemeRenderer;
  Marked, Plain: TTerminalGrid;
  Box: TRectI;
begin
  // '[ Skip ]' is 8 cells in a 12-cell box: two cells on each side, the
  // same as for the caption without a marker.
  Box := TRectI.Make(2, 0, 13, 0);
  for Theme in Themes do
  begin
    Marked := NewGrid;
    Theme.DrawButton(Marked, Box, '&Skip', []);
    Plain := NewGrid;
    Theme.DrawButton(Plain, Box, 'Skip', []);
    Assert.AreEqual(RowText(Plain), RowText(Marked),
      (Theme as TDataTheme).Spec.Id + ': same cells with and without the marker');
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogHotKeyDraw);

end.
