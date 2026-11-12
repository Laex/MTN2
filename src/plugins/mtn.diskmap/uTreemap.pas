unit uTreemap;

{ Squarified treemap layout: splits a rectangle into tiles whose areas are
  proportional to the sizes, keeping the tiles as close to squares as possible.
  Pure arithmetic, no drawing. }

interface

type
  /// <summary>A tile: X1, Y1 inclusive, X2, Y2 exclusive. An empty tile
  /// (X2 <= X1 or Y2 <= Y1) belongs to a size that got no room.</summary>
  TTileRect = record
    X1, Y1, X2, Y2: Integer;
    function Width: Integer;
    function Height: Integer;
    function IsEmpty: Boolean;
    function Contains(AX, AY: Integer): Boolean;
  end;

/// <summary>One tile per size, in the same order. ASizes must be sorted in
/// descending order (the squarified rule needs it); a size of zero or less gets
/// an empty tile. Neighbouring tiles share their edge, so the tiles cover the
/// rectangle without gaps or overlaps.</summary>
function SquarifyLayout(const ASizes: TArray<Int64>; AX, AY, AW, AH: Integer): TArray<TTileRect>;

implementation

uses
  System.Math;

function TTileRect.Width: Integer;
begin
  Result := X2 - X1;
end;

function TTileRect.Height: Integer;
begin
  Result := Y2 - Y1;
end;

function TTileRect.IsEmpty: Boolean;
begin
  Result := (X2 <= X1) or (Y2 <= Y1);
end;

function TTileRect.Contains(AX, AY: Integer): Boolean;
begin
  Result := (AX >= X1) and (AX < X2) and (AY >= Y1) and (AY < Y2);
end;

function MakeTile(AX1, AY1, AX2, AY2: Double): TTileRect;
begin
  Result.X1 := Round(AX1);
  Result.Y1 := Round(AY1);
  Result.X2 := Round(AX2);
  Result.Y2 := Round(AY2);
end;

function SquarifyLayout(const ASizes: TArray<Int64>; AX, AY, AW, AH: Integer): TArray<TTileRect>;
var
  N, I, J, K: Integer;
  Total, RX, RY, RW, RH, Side, RowSum, NewSum, Worst, NewWorst, Pos, Thick, Len: Double;
  Areas: TArray<Double>;
begin
  N := Length(ASizes);
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := MakeTile(0, 0, 0, 0);
  if (N = 0) or (AW <= 0) or (AH <= 0) then
    Exit;
  Total := 0;
  for I := 0 to N - 1 do
    if ASizes[I] > 0 then
      Total := Total + ASizes[I];
  if Total <= 0 then
    Exit;
  SetLength(Areas, N);
  for I := 0 to N - 1 do
    if ASizes[I] > 0 then
      Areas[I] := ASizes[I] / Total * AW * AH
    else
      Areas[I] := 0;

  RX := AX;
  RY := AY;
  RW := AW;
  RH := AH;
  I := 0;
  while I < N do
  begin
    if Areas[I] <= 0 then
      Break;
    Side := Min(RW, RH);
    if Side <= 0 then
      Break;
    // Grow the row while the worst aspect ratio in it keeps improving.
    RowSum := 0;
    Worst := MaxDouble;
    J := I;
    while (J < N) and (Areas[J] > 0) do
    begin
      NewSum := RowSum + Areas[J];
      NewWorst := Max(Side * Side * Areas[I] / (NewSum * NewSum),
        NewSum * NewSum / (Side * Side * Areas[J]));
      if (J > I) and (NewWorst > Worst) then
        Break;
      Worst := NewWorst;
      RowSum := NewSum;
      Inc(J);
    end;
    if RW >= RH then
    begin
      // A column on the left edge, its tiles stacked from the top.
      Thick := RowSum / RH;
      Pos := RY;
      for K := I to J - 1 do
      begin
        Len := Areas[K] / Thick;
        Result[K] := MakeTile(RX, Pos, RX + Thick, Pos + Len);
        Pos := Pos + Len;
      end;
      RX := RX + Thick;
      RW := RW - Thick;
    end
    else
    begin
      // A row on the top edge, its tiles side by side.
      Thick := RowSum / RW;
      Pos := RX;
      for K := I to J - 1 do
      begin
        Len := Areas[K] / Thick;
        Result[K] := MakeTile(Pos, RY, Pos + Len, RY + Thick);
        Pos := Pos + Len;
      end;
      RY := RY + Thick;
      RH := RH - Thick;
    end;
    I := J;
  end;
end;

end.
