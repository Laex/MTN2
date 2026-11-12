unit uSharkRender;

{$I sharks.inc}

{ Draws the shark world onto a grid of text cells:

    1. a black screen
    2. a wake field that spreads where things swim and lights cells cyan
    3. fish as minimal dashes, one per cell, glinting on hard turns
    4. sharks rasterised cell by cell with supersampled edges: grey blocks
       shaded by the light, dense letters, and shimmering accent colours

  The world is simulated in pixels of a virtual screen whose cells are
  CellWidth x CellHeight pixels, the proportions of a terminal cell. }

interface

{$IFDEF MTN_ASCII_SHARKS}

uses
  uTerminalTypes, uSharkShapes, uSharkWorld;

const
  cSharkCellWidth = 8;
  cSharkCellHeight = 16;

type
  TSharkRenderer = class
  private
    FCols, FRows: Integer;
    FEnergy, FEnergyTmp, FHeat: TArray<Single>;
    FSharkFlag: TArray<Byte>;
    FSharkShade: TArray<Single>;
    FSharkKey: TArray<Cardinal>;
    FSharkDepth: TArray<Single>;
    FSharkKind: TArray<Byte>;
    /// <summary>Brightness bucket of the fish in a cell, -1 for none.</summary>
    FFishBucket: TArray<ShortInt>;
    FSpine: array[0..cSharkNodes * 2 - 1] of Double;
    FArc: array[0..cSharkNodes - 1] of Double;
    FArcTotal: Double;
    FShape: TSharkShape;
    FKind: TSharkKind;
    FSharkId: Integer;
    FFinTipLeft, FFinTipRight: Double;
    FHitFlag: Integer;
    FHitShade, FHitS, FHitV, FHitDist: Double;
    function CellIndex(X, Y: Double): Integer;
    procedure Stamp(var AField: TArray<Single>; X, Y: Double; ARadius: Integer; AAmount: Double);
    procedure ConsumeEvents(AWorld: TSharkWorld);
    procedure DepositWake(AWorld: TSharkWorld);
    procedure Diffuse(DT: Double);
    function SampleShark(PX, PY, L: Double): Boolean;
    function Marked(S, V, L, Across: Double): Boolean;
    procedure RasterizeSharks(AWorld: TSharkWorld; T: Double);
    procedure MarkFish(AWorld: TSharkWorld);
    procedure PaintShark(const AGrid: TTerminalGrid; AX, AY, AIndex: Integer; T: Double);
  public
    procedure Resize(ACols, ARows: Integer);
    /// <summary>Turns the state of the world into the fields the next Paint draws.</summary>
    procedure Render(AWorld: TSharkWorld; DT: Double);
    /// <summary>Writes all cells of the grid that the renderer covers.</summary>
    procedure Paint(const AGrid: TTerminalGrid; T: Double);
    property Cols: Integer read FCols;
    property Rows: Integer read FRows;
  end;

{$ENDIF}

implementation

{$IFDEF MTN_ASCII_SHARKS}

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

uses
  System.SysUtils, System.Math, System.UITypes, uSharkMath;

const
  cFlagBody = 1;
  cFlagEdge = 2;
  cFlagFin = 3;
  cFlagRidge = 4;
  cFlagEye = 5;
  cFlagMark = 6;

  cSkinRamp = ':;t%SX8#@';
  cFinGlyphs = '%;tS:';
  cRidgeGlyphs = '@8%';
  cEdgeHeavy = ':;';
  cEdgeLight = '.'',`';
  cMarkGlyphs = '#%@';

  cFishAlphas: array[0..4] of Double = (0.28, 0.42, 0.58, 0.74, 0.9);
  cAccents: array[0..6] of Cardinal = ($E0892C, $E03A32, $B44AE0, $33C8CC, $3CB54A,
    $3150E8, $D9C14A);
  // Sub-cell sample offsets for anti-aliased silhouettes.
  cSubSamples: array[0..7] of Double = (0.25, 0.3, 0.75, 0.3, 0.25, 0.72, 0.75, 0.72);

function JsRound(AValue: Double): Integer;
begin
  Result := Floor(AValue + 0.5);
end;

function Rgb(R, G, B: Double): TAlphaColor;
begin
  Result := TAlphaColor($FF000000 or
    (Cardinal(EnsureRange(JsRound(R), 0, 255)) shl 16) or
    (Cardinal(EnsureRange(JsRound(G), 0, 255)) shl 8) or
    Cardinal(EnsureRange(JsRound(B), 0, 255)));
end;

function Accent(AKey: Cardinal): TAlphaColor;
begin
  Result := TAlphaColor($FF000000 or cAccents[AKey mod Cardinal(Length(cAccents))]);
end;

function InTriangle(PX, PY, AX, AY, BX, BY, CX, CY: Double): Boolean;
var
  D1, D2, D3: Double;
  Neg, Pos: Boolean;
begin
  D1 := (PX - BX) * (AY - BY) - (AX - BX) * (PY - BY);
  D2 := (PX - CX) * (BY - CY) - (BX - CX) * (PY - CY);
  D3 := (PX - AX) * (CY - AY) - (CX - AX) * (PY - AY);
  Neg := (D1 < 0) or (D2 < 0) or (D3 < 0);
  Pos := (D1 > 0) or (D2 > 0) or (D3 > 0);
  Result := not (Neg and Pos);
end;

{ TSharkRenderer }

procedure TSharkRenderer.Resize(ACols, ARows: Integer);
var
  N: Integer;
begin
  if (ACols = FCols) and (ARows = FRows) then
    Exit;
  FCols := ACols;
  FRows := ARows;
  N := ACols * ARows;
  SetLength(FEnergy, 0);
  SetLength(FEnergy, N);
  SetLength(FEnergyTmp, 0);
  SetLength(FEnergyTmp, N);
  SetLength(FHeat, 0);
  SetLength(FHeat, N);
  SetLength(FSharkFlag, 0);
  SetLength(FSharkFlag, N);
  SetLength(FSharkShade, 0);
  SetLength(FSharkShade, N);
  SetLength(FSharkKey, 0);
  SetLength(FSharkKey, N);
  SetLength(FSharkDepth, 0);
  SetLength(FSharkDepth, N);
  SetLength(FSharkKind, 0);
  SetLength(FSharkKind, N);
  SetLength(FFishBucket, 0);
  SetLength(FFishBucket, N);
end;

function TSharkRenderer.CellIndex(X, Y: Double): Integer;
var
  C, R: Integer;
begin
  C := Floor(X / cSharkCellWidth);
  R := Floor(Y / cSharkCellHeight);
  if (C < 0) or (R < 0) or (C >= FCols) or (R >= FRows) then
    Exit(-1);
  Result := R * FCols + C;
end;

procedure TSharkRenderer.Stamp(var AField: TArray<Single>; X, Y: Double;
  ARadius: Integer; AAmount: Double);
var
  C0, R0, R, C, I: Integer;
  D: Double;
begin
  C0 := Floor(X / cSharkCellWidth);
  R0 := Floor(Y / cSharkCellHeight);
  for R := R0 - ARadius to R0 + ARadius do
    for C := C0 - ARadius to C0 + ARadius do
    begin
      if (C < 0) or (R < 0) or (C >= FCols) or (R >= FRows) then
        Continue;
      D := Sqrt(Sqr(C - C0) + Sqr((R - R0) * 1.4));
      if D > ARadius + 0.5 then
        Continue;
      I := R * FCols + C;
      AField[I] := Min(1.6, AField[I] + AAmount * (1 - D / (ARadius + 1)));
    end;
end;

procedure TSharkRenderer.ConsumeEvents(AWorld: TSharkWorld);
var
  E: TWorldEvent;
begin
  for E in AWorld.Events do
    if E.Kind = wekEat then
    begin
      Stamp(FHeat, E.X, E.Y, 2, 1);
      Stamp(FEnergy, E.X, E.Y, 3, 0.9);
    end
    else
      Stamp(FEnergy, E.X, E.Y, 6, 1.4);
  AWorld.Events.Clear;
end;

procedure TSharkRenderer.DepositWake(AWorld: TSharkWorld);
var
  I, K, Idx: Integer;
begin
  for I := 0 to High(AWorld.Fish) do
  begin
    if not AWorld.Fish[I].Alive then
      Continue;
    K := CellIndex(AWorld.Fish[I].X, AWorld.Fish[I].Y);
    if K >= 0 then
      FEnergy[K] := Min(1.6, FEnergy[K] + 0.012 + AWorld.Fish[I].Alarm * 0.03);
  end;
  for I := 0 to High(AWorld.Sharks) do
    // The tail sweeps the most water.
    for K := cSharkNodes - 6 to cSharkNodes - 1 do
    begin
      Idx := CellIndex(AWorld.Sharks[I].Nodes[K * 2], AWorld.Sharks[I].Nodes[K * 2 + 1]);
      if Idx >= 0 then
        FEnergy[Idx] := Min(1.6, FEnergy[Idx] + 0.05 + AWorld.Sharks[I].Speed * 0.0012);
    end;
end;

// Blur and decay, so wakes spread out like ripples and fade.
procedure TSharkRenderer.Diffuse(DT: Double);
var
  R, C, I: Integer;
  Decay, HeatDecay, L, Rt, U, D: Double;
  Tmp: TArray<Single>;
begin
  Decay := Exp(-DT * 1.5);
  for R := 0 to FRows - 1 do
    for C := 0 to FCols - 1 do
    begin
      I := R * FCols + C;
      if C > 0 then L := FEnergy[I - 1] else L := FEnergy[I];
      if C < FCols - 1 then Rt := FEnergy[I + 1] else Rt := FEnergy[I];
      if R > 0 then U := FEnergy[I - FCols] else U := FEnergy[I];
      if R < FRows - 1 then D := FEnergy[I + FCols] else D := FEnergy[I];
      FEnergyTmp[I] := (FEnergy[I] * 4 + L + Rt + U + D) * 0.125 * Decay;
    end;
  Tmp := FEnergy;
  FEnergy := FEnergyTmp;
  FEnergyTmp := Tmp;
  HeatDecay := Exp(-DT * 2.2);
  for I := 0 to High(FHeat) do
    FHeat[I] := FHeat[I] * HeatDecay;
end;

// Classifies one point against the current shark (spine and arc already
// built). Body coordinates: s along the spine (0 snout .. 1 tail), v across it.
// Writes the Hit fields and returns whether the point is on the shark.
function TSharkRenderer.SampleShark(PX, PY, L: Double): Boolean;
var
  K: Integer;
  Best, BestS, BestSign, BestNx, BestNy, Ax, Ay, Sx, Sy, Len2, U, Qx, Qy, D2, Len: Double;
  A, S, W, Across, Facing, Shade, Tip, UU, Span, R, Front, Depth: Double;
  Flag: Integer;
  Head: Boolean;
begin
  Best := MaxDouble;
  BestS := 0;
  BestSign := 1;
  BestNx := 0;
  BestNy := 0;
  for K := 0 to cSharkNodes - 2 do
  begin
    Ax := FSpine[K * 2];
    Ay := FSpine[K * 2 + 1];
    Sx := FSpine[(K + 1) * 2] - Ax;
    Sy := FSpine[(K + 1) * 2 + 1] - Ay;
    Len2 := Sx * Sx + Sy * Sy;
    if Len2 = 0 then
      Len2 := 1;
    U := SharkClamp(((PX - Ax) * Sx + (PY - Ay) * Sy) / Len2, 0, 1);
    Qx := Ax + Sx * U;
    Qy := Ay + Sy * U;
    D2 := Sqr(PX - Qx) + Sqr(PY - Qy);
    if D2 < Best then
    begin
      Best := D2;
      Len := Sqrt(Len2);
      BestS := (FArc[K] + U * Len) / FArcTotal;
      if Sx * (PY - Ay) - Sy * (PX - Ax) >= 0 then
        BestSign := 1
      else
        BestSign := -1;
      BestNx := (-Sy / Len) * BestSign;
      BestNy := (Sx / Len) * BestSign;
    end;
  end;

  A := Sqrt(Best);
  S := BestS;
  UU := S * L;
  W := SharkHalfWidth(FKind, S) * L;
  FHitDist := A;
  FHitS := S;
  FHitV := A * BestSign;

  Head := FShape.HasHead and (UU < L * (FShape.HeadSweep + FShape.HeadDepth + FShape.HeadNotch));
  if Head then
  begin
    // Wide wing across the snout, its tips swept back toward the eyes, and
    // on a great hammerhead a shallow notch in the middle of the front edge.
    Span := L * FShape.HeadSpan;
    R := A / Span;
    Front := L * FShape.HeadSweep * R * R + L * FShape.HeadNotch * Max(0, 1 - R / 0.14);
    // Full depth almost to the tips, so the wing reads as a solid bar.
    Depth := L * FShape.HeadDepth * (1 - 0.2 * R * R * R * R);
    if (R <= 1) and (UU >= Front) and (UU <= Front + Depth) then
    begin
      if R > 0.84 then
      begin
        FHitFlag := cFlagEye;
        FHitShade := 0;
      end
      else
      begin
        FHitFlag := cFlagBody;
        FHitShade := 0.62 - 0.2 * R;
        if UU < Front + L * 0.012 then
          FHitShade := FHitShade + 0.1;
      end;
      Exit(True);
    end;
  end;

  if A <= W then
  begin
    if W = 0 then
      Across := A
    else
      Across := A / W;
    // Rounded back lit from the top-left; flanks fall off into shadow.
    Facing := (BestNx * -0.6 + BestNy * -0.8) * Across;
    Shade := 0.58 - Across * Across * 0.42 + Facing * 0.26;
    Flag := cFlagBody;
    if (S > FShape.Dorsal[0]) and (S < FShape.Dorsal[1]) and (Across < 0.3) then
    begin
      // First dorsal fin, catching the light.
      Flag := cFlagRidge;
      Shade := 1;
    end
    else if (S > FShape.SecondDorsal[0]) and (S < FShape.SecondDorsal[1]) and (Across < 0.4) then
      Shade := Max(Shade, 0.82)
    else if FShape.HasEye and (S > FShape.Eye[0]) and (S < FShape.Eye[1]) and (Across > 0.6) then
    begin
      Flag := cFlagEye;
      Shade := 0;
    end
    else if (S > FShape.Gills[0]) and (S < FShape.Gills[1]) and (Across > 0.58) then
    begin
      // Five gill slits.
      if Floor(((S - FShape.Gills[0]) / (FShape.Gills[1] - FShape.Gills[0])) * 5) mod 2 = 0 then
        Shade := Shade * 0.45;
    end
    else if S < 0.05 then
      // Pale snout tip.
      Shade := Max(Shade, 0.7)
    else if (FKind = skZebra) and (S > 0.08) and (S < 0.55) and
      ((Across < 0.1) or (Abs(Across - 0.6) < 0.08)) then
      // Zebra sharks carry pale ridges down the back.
      Shade := Max(Shade, 0.8)
    else if Marked(S, A * BestSign, L, Across) then
      Flag := cFlagMark;
    FHitFlag := Flag;
    FHitShade := Shade;
    Exit(True);
  end;

  if BestSign > 0 then
    Tip := FFinTipRight
  else
    Tip := FFinTipLeft;
  if InTriangle(UU, A, L * FShape.Pectoral[0], 0, L * FShape.Pectoral[1], 0,
       L * FShape.Pectoral[2], Tip) and
     // Falcate (sickle) fins get a concave trailing edge.
     not (FShape.Falcate and InTriangle(UU, A, L * FShape.Pectoral[1], 0,
       L * (FShape.Pectoral[1] + (FShape.Pectoral[2] - FShape.Pectoral[1]) * 0.33),
       Tip * 0.55, L * FShape.Pectoral[2], Tip)) then
  begin
    if Marked(S, A * BestSign, L, 0) then
      FHitFlag := cFlagMark
    else
      FHitFlag := cFlagFin;
    FHitShade := 0.38 + 0.22 * (1 - SharkClamp(A / Tip, 0, 1));
    Exit(True);
  end;
  if InTriangle(UU, A, L * FShape.Pelvic[0], 0, L * FShape.Pelvic[1], 0,
       L * FShape.Pelvic[2], L * FShape.Pelvic[3]) or
     // Forked caudal fin.
     ((FShape.Caudal > 0) and InTriangle(UU, A, L * 0.86, 0, L * 0.95, 0, L,
       L * FShape.Caudal)) then
  begin
    FHitFlag := cFlagFin;
    FHitShade := 0.36;
    Exit(True);
  end;
  Result := False;
end;

// Whether a body point (s along, v across) falls on a dark marking.
function TSharkRenderer.Marked(S, V, L, Across: Double): Boolean;
var
  Wobble, Bar, Gu, Gv, Jx, Jy: Double;
  Cu, Cv: Integer;
begin
  Result := False;
  if FKind = skTiger then
  begin
    // Wavy vertical bars over the back half, fading out toward the head.
    if (S < 0.2) or (S > 0.9) or (Across > 0.85) then
      Exit;
    Wobble := 0.35 * Sin((V / L) * 25 + S * 5);
    Bar := Sin(S * Pi * 2 * 9 + Wobble);
    Result := Bar > 0.65 - 0.5 * SmoothStep(0.2, 0.42, S) + 0.4 * SmoothStep(0.8, 0.9, S);
  end
  else if FKind = skZebra then
  begin
    // Leopard spots on a jittered grid, so they ride along with the skin.
    if S < 0.07 then
      Exit;
    Gu := (S * L) / (L * 0.06);
    Gv := V / (L * 0.045);
    Cu := Floor(Gu);
    Cv := Floor(Gv);
    Jx := Hash3(Cu, Cv, FSharkId) * 0.5 + 0.25;
    Jy := Hash3(Cu, Cv, FSharkId + 11) * 0.5 + 0.25;
    Result := Sqr(Gu - Cu - Jx) + Sqr(Gv - Cv - Jy) < 0.08;
  end;
end;

// Builds a smooth, undulating render spine from the simulated spine, then
// supersamples every cell in the shark's bounding box against the shape. Fully
// covered cells become solid skin, partial cells become edge glyphs.
procedure TSharkRenderer.RasterizeSharks(AWorld: TSharkWorld; T: Double);
var
  Sh, K, A, B, R, C, I, Hits, SubK, KindIndex, C0, C1, R0, R1: Integer;
  Body: ^TSharkBody;
  Sharks: TArray<TSharkBody>;
  L, Swim, Tx, Ty, Tl, Amp, Off, S, Bank, Flex, MinX, MinY, MaxX, MaxY, Reach: Double;
  X, Y, SkipBeyond, Coverage, Shade, V, Flicker: Double;
  CenterHit: Boolean;
  Flag: Integer;
  Key: Cardinal;
  SrcS, SrcV: Double;
begin
  FillChar(FSharkFlag[0], Length(FSharkFlag), 0);
  Sharks := AWorld.Sharks;
  for Sh := 0 to High(Sharks) do
  begin
    Body := @Sharks[Sh];
    L := Body^.Length;
    Swim := SharkClamp(Body^.Speed / 60, 0.4, 1.4);
    FKind := Body^.Kind;
    FShape := SharkShapeOf(FKind);
    FSharkId := Body^.Id;
    KindIndex := Ord(FKind);

    // Travelling body wave, growing toward the tail.
    for K := 0 to cSharkNodes - 1 do
    begin
      S := K / (cSharkNodes - 1);
      A := Max(0, K - 1);
      B := Min(cSharkNodes - 1, K + 1);
      Tx := Body^.Nodes[A * 2] - Body^.Nodes[B * 2];
      Ty := Body^.Nodes[A * 2 + 1] - Body^.Nodes[B * 2 + 1];
      Tl := Sqrt(Tx * Tx + Ty * Ty);
      if Tl = 0 then
        Tl := 1;
      Tx := Tx / Tl;
      Ty := Ty / Tl;
      Amp := L * 0.05 * (0.1 + 0.9 * Power(S, 1.8)) * Swim;
      Off := Amp * Sin(Body^.Phase - S * 5.2);
      FSpine[K * 2] := Body^.Nodes[K * 2] - Ty * Off;
      FSpine[K * 2 + 1] := Body^.Nodes[K * 2 + 1] + Tx * Off;
    end;
    FArc[0] := 0;
    for K := 1 to cSharkNodes - 1 do
      FArc[K] := FArc[K - 1] + Sqrt(Sqr(FSpine[K * 2] - FSpine[(K - 1) * 2]) +
        Sqr(FSpine[K * 2 + 1] - FSpine[(K - 1) * 2 + 1]));
    FArcTotal := FArc[cSharkNodes - 1];
    if FArcTotal = 0 then
      FArcTotal := 1;

    // Bank into turns: the inside fin foreshortens, the outside one spreads.
    Bank := SharkClamp(Body^.Turn * 0.45, -0.35, 0.35);
    Flex := 1 + 0.06 * Sin(Body^.Phase * 0.5);
    FFinTipRight := L * FShape.Pectoral[3] * Flex * (1 - Bank);
    FFinTipLeft := L * FShape.Pectoral[3] * Flex * (1 + Bank);

    MinX := MaxDouble;
    MinY := MaxDouble;
    MaxX := -MaxDouble;
    MaxY := -MaxDouble;
    for K := 0 to cSharkNodes - 1 do
    begin
      MinX := Min(MinX, FSpine[K * 2]);
      MaxX := Max(MaxX, FSpine[K * 2]);
      MinY := Min(MinY, FSpine[K * 2 + 1]);
      MaxY := Max(MaxY, FSpine[K * 2 + 1]);
    end;
    Reach := L * 0.36;
    C0 := Max(0, Floor((MinX - Reach) / cSharkCellWidth));
    C1 := Min(FCols - 1, Floor((MaxX + Reach) / cSharkCellWidth));
    R0 := Max(0, Floor((MinY - Reach) / cSharkCellHeight));
    R1 := Min(FRows - 1, Floor((MaxY + Reach) / cSharkCellHeight));
    if (C0 > C1) or (R0 > R1) then
      Continue;

    SkipBeyond := Reach + Sqrt(Sqr(cSharkCellWidth) + Sqr(cSharkCellHeight));

    for R := R0 to R1 do
      for C := C0 to C1 do
      begin
        X := C * cSharkCellWidth;
        Y := R * cSharkCellHeight;
        CenterHit := SampleShark(X + cSharkCellWidth / 2, Y + cSharkCellHeight / 2, L);
        if (not CenterHit) and (FHitDist > SkipBeyond) then
          Continue;
        Flag := FHitFlag;
        Shade := FHitShade;
        SrcS := FHitS;
        SrcV := FHitV;

        Hits := 0;
        if CenterHit then
          Hits := 1;
        SubK := 0;
        while SubK < Length(cSubSamples) do
        begin
          if SampleShark(X + cSubSamples[SubK] * cSharkCellWidth,
               Y + cSubSamples[SubK + 1] * cSharkCellHeight, L) then
            Inc(Hits);
          Inc(SubK, 2);
        end;
        if Hits = 0 then
          Continue;
        Coverage := Hits / 5;

        I := R * FCols + C;
        // Body-anchored key so each glyph rides along with the skin.
        Key := Cardinal(Trunc(Hash3(JsRound(SrcS * 52),
          JsRound(SrcV / (cSharkCellWidth * 0.9)), Body^.Id) * 4294967295.0));
        FSharkKey[I] := Key;
        FSharkDepth[I] := Body^.Depth;
        FSharkKind[I] := KindIndex;

        if CenterHit and (Coverage >= 0.6) then
        begin
          FSharkFlag[I] := Flag;
          Flicker := (Hash3(C, R, Floor(T * 6)) - 0.5) * 0.06;
          FSharkShade[I] := SharkClamp(Shade + Flicker, 0, 1);
        end
        else
        begin
          FSharkFlag[I] := cFlagEdge;
          FSharkShade[I] := Coverage;
        end;
      end;
  end;
end;

// Snaps each fish to a cell and buckets it by brightness: far fish are dim,
// near fish brighter, and turning or panicking fish glint. Nearer fish claim a
// cell first when two land in the same one.
procedure TSharkRenderer.MarkFish(AWorld: TSharkWorld);
var
  Pass, I, K, B: Integer;
  Glint, V: Double;
begin
  for I := 0 to High(FFishBucket) do
    FFishBucket[I] := -1;
  for Pass := 0 to 1 do
    for I := 0 to High(AWorld.Fish) do
    begin
      if not AWorld.Fish[I].Alive then
        Continue;
      if (Ord(AWorld.Fish[I].Depth <= 0.78)) <> Pass then
        Continue;
      K := CellIndex(AWorld.Fish[I].X, AWorld.Fish[I].Y);
      if (K < 0) or (FFishBucket[K] >= 0) or (FSharkFlag[K] <> 0) then
        Continue;
      Glint := SharkClamp(Abs(AWorld.Fish[I].Turn) / 3.5, 0, 1);
      V := 0.3 + (0.4 * (AWorld.Fish[I].Depth - 0.55)) / 0.45 + 0.3 * Max(Glint, AWorld.Fish[I].Alarm);
      B := Floor(V * Length(cFishAlphas));
      FFishBucket[K] := EnsureRange(B, 0, Length(cFishAlphas) - 1);
    end;
end;

procedure TSharkRenderer.Render(AWorld: TSharkWorld; DT: Double);
begin
  if FCols = 0 then
    Exit;
  ConsumeEvents(AWorld);
  RasterizeSharks(AWorld, AWorld.Time);
  DepositWake(AWorld);
  Diffuse(DT);
  MarkFish(AWorld);
end;

procedure TSharkRenderer.PaintShark(const AGrid: TTerminalGrid; AX, AY, AIndex: Integer;
  T: Double);
var
  Flag, Tick, Idx: Integer;
  Key: Cardinal;
  Shade, Dim, Level, G, Roll: Double;
  Shape: TSharkShape;
  Glyph: Char;
  Fg, Bg: TAlphaColor;
begin
  Flag := FSharkFlag[AIndex];
  Key := FSharkKey[AIndex];
  Shade := FSharkShade[AIndex];
  Dim := 0.7 + 0.3 * FSharkDepth[AIndex];
  Shape := SharkShapeOf(TSharkKind(FSharkKind[AIndex]));

  // Colours re-roll on a staggered clock so the hide shimmers.
  Tick := Floor(T * 2.4 + (Key mod 997) / 97);
  Roll := Hash3(Key, Tick, 7);

  if Flag = cFlagEdge then
  begin
    // Soft, anti-aliased silhouette: no block, just a light glyph.
    if Shade >= 0.5 then
      Glyph := cEdgeHeavy[1 + (Key shr 8) mod Cardinal(Length(cEdgeHeavy))]
    else
      Glyph := cEdgeLight[1 + (Key shr 8) mod Cardinal(Length(cEdgeLight))];
    G := (70 + Shade * 80) * Dim;
    if Roll < 0.07 then
      Fg := Accent(Key)
    else
      Fg := Rgb(G * Shape.Tint[0], G * Shape.Tint[1], Min(255, G * Shape.Tint[2] + 6));
    DrawGridChar(AGrid, AX, AY, Glyph, Fg, TAlphaColor($FF000000));
    Exit;
  end;

  case Flag of
    cFlagRidge:
      begin
        Level := 226;
        Glyph := cRidgeGlyphs[1 + (Key shr 8) mod Cardinal(Length(cRidgeGlyphs))];
      end;
    cFlagEye:
      begin
        Level := 12;
        Glyph := 'o';
      end;
    cFlagMark:
      begin
        Level := 24 + Shade * 22;
        Glyph := cMarkGlyphs[1 + (Key shr 8) mod Cardinal(Length(cMarkGlyphs))];
      end;
    cFlagFin:
      begin
        Level := 40 + Shade * 120;
        Glyph := cFinGlyphs[1 + (Key shr 8) mod Cardinal(Length(cFinGlyphs))];
      end;
  else
    begin
      Level := 46 + Shade * 160;
      Idx := Floor((1 - Shade) * 8.99) + Integer((Key shr 4) mod 3) - 1;
      Glyph := cSkinRamp[1 + EnsureRange(Idx, 0, Length(cSkinRamp) - 1)];
    end;
  end;
  Level := Level * Dim;
  // Tinted per species; the classic tint is a cool blue-grey, like a back seen
  // through deep water.
  Bg := Rgb(Level * Shape.Tint[0], Level * Shape.Tint[1], Level * Shape.Tint[2] + 4);

  if Flag = cFlagEye then
    Fg := Rgb($9A, $A0, $AD)
  else if Flag = cFlagMark then
    Fg := Rgb(70 * Shape.Tint[0], 70 * Shape.Tint[1], 70 * Shape.Tint[2])
  else if Roll < 0.09 then
    Fg := Accent(Key)
  else if Roll < 0.13 then
    Fg := Rgb(255, 255, 255)
  else if Shade > 0.55 then
    Fg := Rgb($0E, $0F, $13)
  else
    Fg := Rgb($1B, $1D, $24);
  DrawGridChar(AGrid, AX, AY, Glyph, Fg, Bg);
end;

procedure TSharkRenderer.Paint(const AGrid: TTerminalGrid; T: Double);
var
  C, R, I, Level: Integer;
  E, H, A: Double;
  Black: TAlphaColor;
  Glyph: Char;
begin
  Black := TAlphaColor($FF000000);
  for R := 0 to Min(FRows, Length(AGrid)) - 1 do
    for C := 0 to Min(FCols, Length(AGrid[R])) - 1 do
    begin
      I := R * FCols + C;
      if FSharkFlag[I] <> 0 then
      begin
        PaintShark(AGrid, C, R, I, T);
        Continue;
      end;
      if FFishBucket[I] >= 0 then
      begin
        A := cFishAlphas[FFishBucket[I]];
        DrawGridChar(AGrid, C, R, '-', Rgb(230 * A, 238 * A, 255 * A), Black);
        Continue;
      end;
      H := FHeat[I];
      if H >= 0.08 then
      begin
        if H > 0.5 then
        begin
          if H > 0.6 then
            Glyph := '*'
          else
            Glyph := '.';
          DrawGridChar(AGrid, C, R, Glyph,
            Rgb(255 * Min(1, H), 120 * Min(1, H), 60 * Min(1, H)), Black);
        end
        else
          DrawGridChar(AGrid, C, R, '.', Rgb(220 * Min(1, H * 1.6), 40 * Min(1, H * 1.6),
            40 * Min(1, H * 1.6)), Black);
        Continue;
      end;
      E := FEnergy[I];
      if E > 0.45 then
      begin
        // The wake lights the cell cyan, brighter where it is stronger.
        Level := EnsureRange(Floor((E - 0.45) * 5), 0, 5);
        A := (Level + 1) / 6;
        if Level < 3 then
          Glyph := '.'
        else
          Glyph := ':';
        DrawGridChar(AGrid, C, R, Glyph, Rgb(110 * A, 230 * A, 255 * A), Black);
        Continue;
      end;
      DrawGridChar(AGrid, C, R, ' ', Black, Black);
    end;
end;

{$ENDIF}

end.
