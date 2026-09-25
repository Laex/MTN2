unit uEditorHexView;

{ Helper engine for rendering hex dumps in TEditorWindow.
  Extracted from uEditorWindow.pas as part of Step 2 refactoring. }

interface

uses
  System.SysUtils, System.Math;

type
  TGetByteFunc = reference to function(AIndex: Integer): Byte;

  TEditorHexFormatter = class
  public
    class function BytesPerRow(ATextWidth: Integer): Integer;
    class function HexRowCount(AByteCount, ATextWidth: Integer): Integer;
    /// <summary>0-based column of the first hex digit ("00000000  " = 10).</summary>
    class function HexColStart: Integer;
    /// <summary>0-based column of the ASCII dump's first glyph.</summary>
    class function AsciiColStart(ABytesPerRow: Integer): Integer;
    /// <summary>0-based column of the first hex glyph for AByteIdx in the row.</summary>
    class function HexGlyphCol(AByteIdx: Integer): Integer;
    /// <summary>Cursor at the last byte for SelectAll in hex mode.</summary>
    class procedure SelectAllEnd(AByteCount, ATextWidth: Integer;
      out ARow, ACol: Integer);
    class function FormatHexLine(ARow, ATextWidth, AByteCount: Integer;
      const AGetByte: TGetByteFunc): string;
    class function HexDigitValue(ACh: Char): Integer;
    class function ApplyNibble(AValue: Byte; ADigit: Integer;
      AHigh: Boolean): Byte;
    class function AbsoluteByteIndex(ARow, ACol, ABytesPerRow: Integer): Integer;
  end;

implementation

class function TEditorHexFormatter.BytesPerRow(ATextWidth: Integer): Integer;
begin
  // offset(8) + gap(2) + 3*N hex + gap(2) + N ascii  =>  10 + 4*N
  Result := Max((ATextWidth - 10) div 4, 8);
  if Result >= 16 then
    Result := 16
  else
    Result := 8;
end;

class function TEditorHexFormatter.HexRowCount(AByteCount, ATextWidth: Integer): Integer;
var
  Per: Integer;
begin
  Per := BytesPerRow(ATextWidth);
  if Per < 1 then
    Per := 16;
  if AByteCount <= 0 then
    Exit(1);
  Result := (AByteCount + Per - 1) div Per;
end;

class function TEditorHexFormatter.HexColStart: Integer;
begin
  Result := 10;
end;

class function TEditorHexFormatter.AsciiColStart(ABytesPerRow: Integer): Integer;
begin
  Result := HexColStart + (ABytesPerRow * 3 - 1) + 2;
end;

class function TEditorHexFormatter.HexGlyphCol(AByteIdx: Integer): Integer;
begin
  Result := HexColStart + AByteIdx * 3;
end;

class procedure TEditorHexFormatter.SelectAllEnd(AByteCount, ATextWidth: Integer;
  out ARow, ACol: Integer);
var
  Per: Integer;
begin
  Per := BytesPerRow(ATextWidth);
  if Per < 1 then
    Per := 16;
  if AByteCount <= 0 then
  begin
    ARow := 0;
    ACol := 0;
    Exit;
  end;
  ARow := (AByteCount - 1) div Per;
  ACol := (AByteCount - 1) mod Per;
end;

class function TEditorHexFormatter.FormatHexLine(ARow, ATextWidth, AByteCount: Integer;
  const AGetByte: TGetByteFunc): string;
var
  Per, Off, I, N: Integer;
  HexPart, AscPart: string;
  B: Byte;
  Ch: Char;
begin
  Per := BytesPerRow(ATextWidth);
  Off := ARow * Per;
  N := AByteCount - Off;
  if N < 0 then
    N := 0;
  if N > Per then
    N := Per;
  HexPart := '';
  AscPart := '';
  for I := 0 to Per - 1 do
  begin
    if I < N then
    begin
      B := 0;
      if Assigned(AGetByte) then
        B := AGetByte(Off + I);
      HexPart := HexPart + IntToHex(B, 2);
      if (B >= 32) and (B < 127) then
        Ch := Char(B)
      else
        Ch := '.';
      AscPart := AscPart + Ch;
    end
    else
    begin
      HexPart := HexPart + '  ';
      AscPart := AscPart + ' ';
    end;
    if I < Per - 1 then
    begin
      if (Per = 16) and (I = 7) then
        HexPart := HexPart + '-'
      else
        HexPart := HexPart + ' ';
    end;
  end;
  Result := Format('%.8x  %s  %s', [Off, HexPart, AscPart]);
end;

class function TEditorHexFormatter.HexDigitValue(ACh: Char): Integer;
begin
  case ACh of
    '0'..'9': Result := Ord(ACh) - Ord('0');
    'a'..'f': Result := 10 + Ord(ACh) - Ord('a');
    'A'..'F': Result := 10 + Ord(ACh) - Ord('A');
  else
    Result := -1;
  end;
end;

class function TEditorHexFormatter.ApplyNibble(AValue: Byte; ADigit: Integer;
  AHigh: Boolean): Byte;
begin
  ADigit := ADigit and $F;
  if AHigh then
    Result := Byte((AValue and $0F) or (ADigit shl 4))
  else
    Result := Byte((AValue and $F0) or ADigit);
end;

class function TEditorHexFormatter.AbsoluteByteIndex(ARow, ACol,
  ABytesPerRow: Integer): Integer;
begin
  if (ABytesPerRow < 1) or (ARow < 0) or (ACol < 0) then
    Exit(-1);
  Result := ARow * ABytesPerRow + ACol;
end;

end.
