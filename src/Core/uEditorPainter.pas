unit uEditorPainter;

{ Editor Painter: TUI grid rendering for text and hex viewer/editor lines. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  uTerminalTypes, uCharWidth;

type
  TEditorPainter = class
  public
    class procedure DrawTextLine(var ARow: TTerminalRow; AStartCol, AWidth: Integer;
      const ALineText: string; AStartCharIndex: Integer; AFg, ABg: TAlphaColor);
    class procedure DrawHexLine(var ARow: TTerminalRow; AWidth: Integer;
      const ALineText: string; AFg, ABg: TAlphaColor);
  end;

implementation

class procedure TEditorPainter.DrawTextLine(var ARow: TTerminalRow; AStartCol, AWidth: Integer;
  const ALineText: string; AStartCharIndex: Integer; AFg, ABg: TAlphaColor);
var
  ColIdx, CharIdx, EndCol: Integer;
  Ch: Char;
  Wide: Boolean;
begin
  ColIdx := AStartCol;
  CharIdx := AStartCharIndex;
  EndCol := Min(AStartCol + AWidth, High(ARow) + 1);
  while ColIdx < EndCol do
  begin
    if (CharIdx >= 1) and (CharIdx <= Length(ALineText)) then
      Ch := ALineText[CharIdx]
    else
      Ch := ' ';
    // A wide character takes two cells; at the right edge, where its second
    // half would be clipped, it is left blank.
    Wide := CharDisplayWidth(Ch) = 2;
    if Wide and (ColIdx + 1 >= EndCol) then
    begin
      Ch := ' ';
      Wide := False;
    end;
    ARow[ColIdx].CharValue := Ch;
    ARow[ColIdx].FgColor := AFg;
    ARow[ColIdx].BgColor := ABg;
    ARow[ColIdx].Attributes := ARow[ColIdx].Attributes - [ccaWide, ccaWideTail];
    Inc(ColIdx);
    Inc(CharIdx);
    if Wide then
    begin
      Include(ARow[ColIdx - 1].Attributes, ccaWide);
      ARow[ColIdx].CharValue := ' ';
      ARow[ColIdx].FgColor := AFg;
      ARow[ColIdx].BgColor := ABg;
      ARow[ColIdx].Attributes := ARow[ColIdx].Attributes - [ccaWide] + [ccaWideTail];
      Inc(ColIdx);
    end;
  end;
end;

class procedure TEditorPainter.DrawHexLine(var ARow: TTerminalRow; AWidth: Integer;
  const ALineText: string; AFg, ABg: TAlphaColor);
begin
  DrawTextLine(ARow, 1, AWidth, ALineText, 1, AFg, ABg);
end;

end.
