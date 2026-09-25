program TestButtonTextClip;

{$APPTYPE CONSOLE}

{ Stage: button-caption clipping (PutGridTextClipped, used by every theme's
  DrawButton). Guards against the overflow bug found when translating dialog
  buttons to Russian: a fixed-width button box (sized from the dialog JSON's
  "width", never from caption length -- see uDialogJson.pas/uDialogHost.pas)
  whose translated caption is longer than the English one used to size it
  must clip at the box's own right edge instead of bleeding text into
  whatever sits to the right of the button (its own shadow column, or a
  neighboring control). }

uses
  System.SysUtils,
  System.UITypes,
  uTerminalTypes in '..\Core\uTerminalTypes.pas',
  uThemeTypes in '..\Core\uThemeTypes.pas',
  uNDNTheme in '..\Themes\uNDNTheme.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

function RowText(const AGrid: TTerminalGrid; AY, AFrom, ATo: Integer): string;
var
  X: Integer;
begin
  Result := '';
  for X := AFrom to ATo do
    Result := Result + AGrid[AY][X].CharValue;
end;

procedure TestPutGridTextClippedBasics;
var
  Grid: TTerminalGrid;
begin
  Writeln('PutGridTextClipped');

  // Fits comfortably: identical to plain PutGridText.
  AllocTerminalGrid(Grid, 20, 3);
  ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, '.');
  PutGridTextClipped(Grid, 2, 0, 19, 'OK', TAlphaColors.White, TAlphaColors.Black);
  Expect(RowText(Grid, 0, 0, 19) = '..OK................', 'short text is unaffected by a far-away clip edge');

  // Exactly fills the clip range: last char lands on AMaxX itself, nothing past it.
  AllocTerminalGrid(Grid, 20, 3);
  ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, '.');
  PutGridTextClipped(Grid, 0, 0, 4, 'ABCDE', TAlphaColors.White, TAlphaColors.Black);
  Expect(RowText(Grid, 0, 0, 5) = 'ABCDE.', 'text landing exactly on AMaxX draws in full, cell past it untouched');

  // Overflowing text is cut off at AMaxX -- nothing written past it.
  AllocTerminalGrid(Grid, 20, 3);
  ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, '.');
  PutGridTextClipped(Grid, 0, 0, 4, 'ABCDEFGH', TAlphaColors.White, TAlphaColors.Black);
  Expect(RowText(Grid, 0, 0, 7) = 'ABCDE...', 'overflowing text stops at AMaxX, no bleed into later cells');

  // AMaxX before AX: nothing at all should be written.
  AllocTerminalGrid(Grid, 20, 3);
  ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, '.');
  PutGridTextClipped(Grid, 5, 0, 2, 'ABCDEFGH', TAlphaColors.White, TAlphaColors.Black);
  Expect(RowText(Grid, 0, 0, 19) = '....................', 'AMaxX before AX writes nothing (not even at AX)');
end;

procedure TestThemeDrawButtonClipsToBounds;
var
  Grid: TTerminalGrid;
  Theme: IThemeRenderer;
  Bounds: TRectI;
  RightNeighbor, ShadowCol: Char;
begin
  Writeln('TNDNTheme.DrawButton respects a fixed-width box under a long translated caption');
  Theme := TNDNTheme.Create as IThemeRenderer;

  // Mirrors the real DIALOG_OVERWRITEASK 'append' button: box width 10,
  // English caption 'Append' fits ('[ Append ]' = 10 chars); the Russian
  // translation 'Добавить в конец' does not (would need 20 cells).
  AllocTerminalGrid(Grid, 40, 3);
  ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, '.');
  Bounds := TRectI.Make(5, 0, 14, 0); // width 10, cols 5..14
  Theme.DrawButton(Grid, Bounds, 'Добавить в конец', []);

  // Cell right after the box (col 15) is where DrawButtonShadow (Host-side,
  // drawn separately/after all faces) puts its shadow glyph -- DrawButton
  // itself must never write there, or a real dialog's shadow pass would be
  // drawing over live caption text instead of the panel background.
  ShadowCol := Grid[0][15].CharValue;
  Expect(ShadowCol = '.', 'button face never writes into its own shadow column (15)');

  // Further right -- where a neighboring control/button would sit in a real
  // dialog -- must be completely untouched.
  RightNeighbor := Grid[0][20].CharValue;
  Expect(RightNeighbor = '.', 'overflow does not bleed as far as a neighboring control (20)');

  // The box itself must still be fully painted (face + as much caption as fits).
  Expect(Grid[0][5].CharValue <> '.', 'the button face itself is still drawn (left edge)');
  Expect(Grid[0][14].CharValue <> '.', 'the button face fills its box right up to its own right edge (14)');
end;

begin
  try
    TestPutGridTextClippedBasics;
    TestThemeDrawButtonClipsToBounds;
    Writeln('All ButtonTextClip tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
