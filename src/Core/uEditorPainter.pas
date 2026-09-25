unit uEditorPainter;

{ Editor Painter: TUI grid rendering for text and hex viewer/editor lines. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  uTerminalTypes;

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
  ColIdx, CharIdx: Integer;
begin
  ColIdx := AStartCol;
  CharIdx := AStartCharIndex;
  while (ColIdx < AStartCol + AWidth) and (ColIdx <= High(ARow)) do
  begin
    if (CharIdx >= 1) and (CharIdx <= Length(ALineText)) then
      ARow[ColIdx].CharValue := ALineText[CharIdx]
    else
      ARow[ColIdx].CharValue := ' ';
    ARow[ColIdx].FgColor := AFg;
    ARow[ColIdx].BgColor := ABg;
    Inc(ColIdx);
    Inc(CharIdx);
  end;
end;

class procedure TEditorPainter.DrawHexLine(var ARow: TTerminalRow; AWidth: Integer;
  const ALineText: string; AFg, ABg: TAlphaColor);
begin
  DrawTextLine(ARow, 1, AWidth, ALineText, 1, AFg, ABg);
end;

end.
