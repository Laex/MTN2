unit uSharkWorld;

{$I sharks.inc}

{ Artificial-life simulation: tiny fish schools and the sharks that hunt them.

  Fish are boids (separation, alignment, cohesion) in zones, with a blind spot
  behind each fish. Alarm spreads from fish to fish through a school, so the
  whole school bolts even when only its edge sees the shark. Fleeing fish break
  sideways around the shark's path, the fountain seen in real bait balls.

  Sharks steer by wandering, pursuit and separation along a follow-the-leader
  spine. Hunger builds with time and drops when they eat; they prefer fish in
  sparse spots, since dense schools confuse predators. Eaten fish come back
  later as new schools swimming in from the edges, which keeps the number of
  fish steady.

  Lengths and speeds are in pixels of a virtual screen whose cells are
  CellWidth x CellHeight pixels. }

interface

{$IFDEF MTN_ASCII_SHARKS}

uses
  System.Generics.Collections, uSharkMath, uSharkShapes;

const
  cSharkNodes = 20;

type
  /// <summary>Which sharks to put in the water; Size is relative to the biggest.</summary>
  TSharkSpec = record
    Kind: TSharkKind;
    Size: Double;
  end;

  TFish = record
    X, Y, Vx, Vy: Double;
    Species: Integer;
    /// <summary>0 calm .. 1 panicking. Spreads to neighbours.</summary>
    Alarm: Double;
    Alive: Boolean;
    RespawnAt: Double;
    /// <summary>Tail-beat phase.</summary>
    Phase: Double;
    /// <summary>Smoothed angular velocity (rad/s); hard turns glint.</summary>
    Turn: Double;
    /// <summary>0.55 far .. 1 near.</summary>
    Depth: Double;
    /// <summary>Rotation sense shared by a school when it mills into a bait ball.</summary>
    MillDir: Integer;
  end;

  TSharkBody = record
    Id: Integer;
    Kind: TSharkKind;
    Length: Double;
    /// <summary>Spine positions, snout first: x0, y0, x1, y1, ...</summary>
    Nodes: array[0..cSharkNodes * 2 - 1] of Double;
    Heading, Speed: Double;
    /// <summary>Tail-beat phase; drives the body wave in the renderer.</summary>
    Phase: Double;
    /// <summary>Smoothed angular velocity (rad/s); the shark banks its fins into turns.</summary>
    Turn: Double;
    Hunger, Wander: Double;
    OrbitDir: Integer;
    OrbitRadius: Double;
    /// <summary>Index of the fish being hunted; -1 when none.</summary>
    Target: Integer;
    RetargetAt: Double;
    /// <summary>0 far and dim .. 1 near and bright.</summary>
    Depth: Double;
  end;

  TWorldEventKind = (wekEat, wekSplash);

  TWorldEvent = record
    Kind: TWorldEventKind;
    X, Y: Double;
  end;

  TSharkWorld = class
  private
    FRandom: TSharkRandom;
    FSharkSpecs: TArray<TSharkSpec>;
    FFishCount: Integer;
    FWidth, FHeight, FTime: Double;
    FFish: TArray<TFish>;
    FSharks: TArray<TSharkBody>;
    FEvents: TList<TWorldEvent>;
    FPerception: Double;
    FSepX, FSepY: array[0..4] of Double;
    FForeignSep: Double;
    FBucketCols, FBucketRows: Integer;
    FBucketHead, FBucketCount, FBucketNext: TArray<Integer>;
    FLastSpawn: Double;
    procedure Seed;
    procedure RebuildHash;
    function BucketOf(X, Y: Double): Integer;
    procedure StepFish(DT: Double);
    procedure StepSharks(DT: Double);
    function FindPrey(const AShark: TSharkBody): Integer;
    procedure RespawnFish;
  public
    /// <summary>AFishCount 0 = by the area of the screen.</summary>
    constructor Create(const ASpecs: TArray<TSharkSpec>; ASeed: Cardinal;
      AFishCount: Integer = 0);
    destructor Destroy; override;
    procedure Resize(AWidth, AHeight, ACellW, ACellH: Double);
    procedure Step(DT: Double);
    property Width: Double read FWidth;
    property Height: Double read FHeight;
    property Time: Double read FTime;
    property Fish: TArray<TFish> read FFish;
    property Sharks: TArray<TSharkBody> read FSharks;
    /// <summary>Things that happened since the renderer last cleared the list.</summary>
    property Events: TList<TWorldEvent> read FEvents;
  end;

{$ENDIF}

implementation

{$IFDEF MTN_ASCII_SHARKS}

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

uses
  System.SysUtils, System.Math, uSharkSpecies;

const
  cFishSeparationK = 420;
  cFishAlignK = 1.4;
  cFishCohesionK = 1;
  cFishFleeK = 1100;
  // About 127 degrees either side of the heading is visible.
  cBlindCos = -0.6;

function JsRound(AValue: Double): Integer;
begin
  Result := Floor(AValue + 0.5);
end;

{ TSharkWorld }

constructor TSharkWorld.Create(const ASpecs: TArray<TSharkSpec>; ASeed: Cardinal;
  AFishCount: Integer);
begin
  inherited Create;
  FRandom := TSharkRandom.Create(ASeed);
  FSharkSpecs := ASpecs;
  FFishCount := AFishCount;
  FEvents := TList<TWorldEvent>.Create;
end;

destructor TSharkWorld.Destroy;
begin
  FEvents.Free;
  FRandom.Free;
  inherited Destroy;
end;

procedure TSharkWorld.Resize(AWidth, AHeight, ACellW, ACellH: Double);
var
  First: Boolean;
  I: Integer;
begin
  First := FWidth = 0;
  FWidth := AWidth;
  FHeight := AHeight;
  // Spacing is set in grid cells so every fish lands in its own cell.
  for I := 0 to cSpeciesCount - 1 do
  begin
    FSepX[I] := FishSpecies(I).SpacingX * ACellW;
    FSepY[I] := FishSpecies(I).SpacingY * ACellH;
  end;
  FPerception := Max(ACellH * 3, ACellW * 5.5);
  FForeignSep := ACellW * 3;
  if First or (Length(FFish) = 0) then
  begin
    Seed;
    Exit;
  end;
  for I := 0 to High(FFish) do
  begin
    FFish[I].X := SharkClamp(FFish[I].X, 0, AWidth);
    FFish[I].Y := SharkClamp(FFish[I].Y, 0, AHeight);
  end;
end;

procedure TSharkWorld.Seed;
var
  W, H, MinSide, BaseLen, Len, OrbitRadius, A, X, Y, Heading, Seg, Dir: Double;
  I, N, Total, Species, Size, K, OrbitDir, MillDir, J, Idx: Integer;
  Sp: TFishSpecies;
  Cx, Cy: Double;
  Body: TSharkBody;
begin
  W := FWidth;
  H := FHeight;
  MinSide := Min(W, H);
  // A text cell is coarser than a pixel, so the sharks are drawn larger than
  // the screen proportions of a picture would suggest.
  BaseLen := SharkClamp(MinSide * 0.6, 170, 560);

  SetLength(FSharks, Length(FSharkSpecs));
  for I := 0 to High(FSharkSpecs) do
  begin
    Len := BaseLen * FSharkSpecs[I].Size;
    OrbitRadius := MinSide * FRandom.Range(0.28, 0.4);
    A := (I / Length(FSharkSpecs)) * cTau + FRandom.Range(-0.4, 0.4);
    if I mod 2 = 0 then
      OrbitDir := 1
    else
      OrbitDir := -1;
    X := W / 2 + Cos(A) * OrbitRadius * (W / MinSide) * 0.9;
    Y := H / 2 + Sin(A) * OrbitRadius;
    Heading := A + OrbitDir * Pi / 2;
    Seg := Len / (cSharkNodes - 1);
    Body := Default(TSharkBody);
    for N := 0 to cSharkNodes - 1 do
    begin
      Body.Nodes[N * 2] := X - Cos(Heading) * Seg * N;
      Body.Nodes[N * 2 + 1] := Y - Sin(Heading) * Seg * N;
    end;
    Body.Id := I + 1;
    Body.Kind := FSharkSpecs[I].Kind;
    Body.Length := Len;
    Body.Heading := Heading;
    Body.Speed := 30;
    Body.Phase := FRandom.Range(0, cTau);
    Body.Hunger := FRandom.Range(0.25, 0.75);
    Body.OrbitDir := OrbitDir;
    Body.OrbitRadius := OrbitRadius;
    Body.Target := -1;
    Body.Depth := FSharkSpecs[I].Size;
    FSharks[I] := Body;
  end;
  // Smaller (farther) sharks come first so the big one swims over them.
  for I := 1 to High(FSharks) do
  begin
    Body := FSharks[I];
    J := I - 1;
    while (J >= 0) and (FSharks[J].Length > Body.Length) do
    begin
      FSharks[J + 1] := FSharks[J];
      Dec(J);
    end;
    FSharks[J + 1] := Body;
  end;

  if FFishCount > 0 then
    Total := FFishCount
  else
    Total := Max(85, Min(340, JsRound(W * H / 4400)));
  SetLength(FFish, 0);
  while Length(FFish) < Total do
  begin
    Species := PickFishSpecies(FRandom);
    Sp := FishSpecies(Species);
    Size := Min(FRandom.IntRange(Sp.SchoolMin, Sp.SchoolMax), Total - Length(FFish));
    if FRandom.Next < 0.5 then
      MillDir := 1
    else
      MillDir := -1;
    Cx := FRandom.Range(W * 0.06, W * 0.94);
    Cy := FRandom.Range(H * 0.08, H * 0.92);
    // Mostly level headings: fish cruise sideways far more than up or down.
    if FRandom.Next < 0.5 then
      Dir := 0
    else
      Dir := Pi;
    Dir := Dir + FRandom.Range(-0.5, 0.5);
    for K := 0 to Size - 1 do
    begin
      SetLength(FFish, Length(FFish) + 1);
      Idx := High(FFish);
      FFish[Idx].X := Cx + FRandom.Range(-1, 1) * FSepX[Species] * Sqrt(Size);
      FFish[Idx].Y := Cy + FRandom.Range(-1, 1) * FSepY[Species] * Sqrt(Size) * 0.6;
      FFish[Idx].Vx := Cos(Dir) * Sp.Cruise;
      FFish[Idx].Vy := Sin(Dir) * Sp.Cruise;
      FFish[Idx].Species := Species;
      FFish[Idx].Alarm := 0;
      FFish[Idx].Alive := True;
      FFish[Idx].RespawnAt := 0;
      FFish[Idx].Phase := FRandom.Range(0, cTau);
      FFish[Idx].Turn := 0;
      FFish[Idx].Depth := FRandom.Range(0.55, 1);
      FFish[Idx].MillDir := MillDir;
    end;
  end;
  SetLength(FBucketNext, Length(FFish));
end;

procedure TSharkWorld.Step(DT: Double);
begin
  FTime := FTime + DT;
  RebuildHash;
  StepFish(DT);
  StepSharks(DT);
  RespawnFish;
end;

procedure TSharkWorld.RebuildHash;
const
  cPad = 2;
var
  Size: Double;
  N, I, B: Integer;
begin
  Size := FPerception;
  FBucketCols := Ceil(FWidth / Size) + cPad * 2;
  FBucketRows := Ceil(FHeight / Size) + cPad * 2;
  N := FBucketCols * FBucketRows;
  if Length(FBucketHead) <> N then
  begin
    SetLength(FBucketHead, N);
    SetLength(FBucketCount, N);
  end;
  for I := 0 to N - 1 do
  begin
    FBucketHead[I] := -1;
    FBucketCount[I] := 0;
  end;
  if Length(FBucketNext) <> Length(FFish) then
    SetLength(FBucketNext, Length(FFish));
  for I := 0 to High(FFish) do
  begin
    if not FFish[I].Alive then
      Continue;
    B := BucketOf(FFish[I].X, FFish[I].Y);
    FBucketNext[I] := FBucketHead[B];
    FBucketHead[B] := I;
    Inc(FBucketCount[B]);
  end;
end;

function TSharkWorld.BucketOf(X, Y: Double): Integer;
var
  C, R: Integer;
begin
  C := Round(SharkClamp(Floor(X / FPerception) + 2, 0, FBucketCols - 1));
  R := Round(SharkClamp(Floor(Y / FPerception) + 2, 0, FBucketRows - 1));
  Result := R * FBucketCols + C;
end;

procedure TSharkWorld.StepFish(DT: Double);
var
  I, J, K, R, C, Bc, Br, N, Sh: Integer;
  F, O: ^TFish;
  Sp: TFishSpecies;
  Spread, SepX, SepY, Speed, Hx, Hy, Ax, Ay, Sx, Sy, Avx, Avy, Cx, Cy: Double;
  NeighbourAlarm, Dx, Dy, D2, D, Qx, Qy, Q2, Q, Kk, AlignK, CohesionK, Cl: Double;
  Fear, FearR, Best, Bx, By, Nx, Ny, Wt, AwayX, AwayY, Shx, Shy, Side: Double;
  Alarm, Relayed, Preferred, Before, MaxSpeed, S, CurX, CurY, Margin: Double;
  CalmDecay, Contagion, R2, Size: Double;
  Cols, Rows: Integer;
begin
  R2 := FPerception * FPerception;
  Size := FPerception;
  Cols := FBucketCols;
  Rows := FBucketRows;
  CalmDecay := Exp(-DT * 0.7);
  Contagion := Min(1, DT * 6);

  for I := 0 to High(FFish) do
  begin
    F := @FFish[I];
    if not F^.Alive then
      Continue;
    Sp := FishSpecies(F^.Species);
    // Alarmed fish want more room: the school flashes apart around a shark and
    // closes back up once the threat fades.
    Spread := 1 + 1.8 * F^.Alarm;
    SepX := FSepX[F^.Species] * Spread;
    SepY := FSepY[F^.Species] * Spread;

    Speed := Sqrt(F^.Vx * F^.Vx + F^.Vy * F^.Vy);
    if Speed = 0 then
      Speed := 1;
    Hx := F^.Vx / Speed;
    Hy := F^.Vy / Speed;

    Ax := 0; Ay := 0; Sx := 0; Sy := 0; Avx := 0; Avy := 0; Cx := 0; Cy := 0;
    N := 0;
    NeighbourAlarm := 0;

    Bc := Round(SharkClamp(Floor(F^.X / Size) + 2, 0, Cols - 1));
    Br := Round(SharkClamp(Floor(F^.Y / Size) + 2, 0, Rows - 1));
    for R := Max(0, Br - 1) to Min(Rows - 1, Br + 1) do
      for C := Max(0, Bc - 1) to Min(Cols - 1, Bc + 1) do
      begin
        J := FBucketHead[R * Cols + C];
        while J <> -1 do
        begin
          if J <> I then
          begin
            O := @FFish[J];
            Dx := O^.X - F^.X;
            Dy := O^.Y - F^.Y;
            D2 := Dx * Dx + Dy * Dy;
            if (D2 < R2) and (D2 > 1E-6) then
            begin
              D := Sqrt(D2);
              // Blind zone directly behind the fish.
              if (Dx * Hx + Dy * Hy) / D > cBlindCos then
              begin
                // Elliptical personal space: wide along x, tight along y.
                Qx := Dx / SepX;
                Qy := Dy / SepY;
                Q2 := Qx * Qx + Qy * Qy;
                if Q2 < 1 then
                begin
                  Q := Sqrt(Q2);
                  if Q = 0 then
                    Q := 1E-3;
                  Kk := (1 - Q) / Q;
                  Sx := Sx - Qx * Kk;
                  Sy := Sy - Qy * Kk;
                end;
                if O^.Species = F^.Species then
                begin
                  Avx := Avx + O^.Vx;
                  Avy := Avy + O^.Vy;
                  Cx := Cx + Dx;
                  Cy := Cy + Dy;
                  Inc(N);
                end
                else if D < FForeignSep then
                begin
                  // Different species keep their own schools.
                  Kk := ((1 - D / FForeignSep) / D) * 0.6;
                  Sx := Sx - Dx * Kk;
                  Sy := Sy - Dy * Kk;
                end;
                if O^.Alarm > NeighbourAlarm then
                  NeighbourAlarm := O^.Alarm;
              end;
            end;
          end;
          J := FBucketNext[J];
        end;
      end;

    Ax := Ax + Sx * cFishSeparationK;
    Ay := Ay + Sy * cFishSeparationK;
    if N > 0 then
    begin
      AlignK := cFishAlignK * Sp.Align;
      CohesionK := cFishCohesionK * Sp.Cohesion * (1 - 0.8 * F^.Alarm);
      Ax := Ax + (Avx / N - F^.Vx) * AlignK + (Cx / N) * CohesionK;
      Ay := Ay + (Avy / N - F^.Vy) * AlignK + (Cy / N) * CohesionK;
      if Sp.Mill > 0 then
      begin
        // Circle the local centre: the school spins into a bait ball.
        Cl := Sqrt(Cx * Cx + Cy * Cy);
        if Cl = 0 then
          Cl := 1;
        Ax := Ax + (-Cy / Cl) * F^.MillDir * Sp.Mill * (1 - F^.Alarm);
        Ay := Ay + (Cx / Cl) * F^.MillDir * Sp.Mill * (1 - F^.Alarm);
      end;
    end;

    // Predators. Distance is measured to the nearest point along the front
    // half of the shark, so fish also give the flanks a wide berth.
    Fear := 0;
    for Sh := 0 to High(FSharks) do
    begin
      FearR := FSharks[Sh].Length * 0.6 + 60;
      Best := MaxDouble;
      Bx := 0;
      By := 0;
      K := 0;
      while K <= 12 do
      begin
        Nx := FSharks[Sh].Nodes[K * 2];
        Ny := FSharks[Sh].Nodes[K * 2 + 1];
        D2 := Sqr(F^.X - Nx) + Sqr(F^.Y - Ny);
        if D2 < Best then
        begin
          Best := D2;
          Bx := Nx;
          By := Ny;
        end;
        Inc(K, 3);
      end;
      D := Sqrt(Best);
      if (D >= FearR) or (D < 1E-3) then
        Continue;
      Wt := 1 - D / FearR;
      Wt := Wt * Wt;
      AwayX := (F^.X - Bx) / D;
      AwayY := (F^.Y - By) / D;
      // Fountain effect: break to whichever side of the shark's path you're on.
      Shx := Cos(FSharks[Sh].Heading);
      Shy := Sin(FSharks[Sh].Heading);
      if Shx * (F^.Y - FSharks[Sh].Nodes[1]) - Shy * (F^.X - FSharks[Sh].Nodes[0]) >= 0 then
        Side := 1
      else
        Side := -1;
      Ax := Ax + (AwayX * 0.7 - Shy * Side * 0.9) * cFishFleeK * Wt;
      Ay := Ay + (AwayY * 0.7 + Shx * Side * 0.9) * cFishFleeK * Wt;
      Fear := Max(Fear, Sqrt(Wt));
    end;

    // Alarm: a direct threat sets it, neighbours pass it along (slightly
    // weaker each hop), and it fades on its own.
    Alarm := Max(F^.Alarm * CalmDecay, Fear);
    Relayed := NeighbourAlarm * 0.86;
    if Relayed > Alarm then
      Alarm := Alarm + (Relayed - Alarm) * Contagion;
    F^.Alarm := Alarm;

    // Soft walls.
    Margin := 36;
    if F^.X < Margin then
      Ax := Ax + (Margin - F^.X) * 7
    else if F^.X > FWidth - Margin then
      Ax := Ax - (F^.X - (FWidth - Margin)) * 7;
    if F^.Y < Margin then
      Ay := Ay + (Margin - F^.Y) * 7
    else if F^.Y > FHeight - Margin then
      Ay := Ay - (F^.Y - (FHeight - Margin)) * 7;

    // Ambient current and a little individual restlessness.
    OceanCurrent(F^.X, F^.Y, FTime, CurX, CurY);
    Ax := Ax + CurX * 0.5 + (FRandom.Next - 0.5) * Sp.Jitter;
    Ay := Ay + CurY * 0.5 + (FRandom.Next - 0.5) * Sp.Jitter;
    // Swim level, except when bolting from danger.
    Ay := Ay - F^.Vy * Sp.VerticalDrag * (1 - 0.7 * F^.Alarm);

    // Relax toward a preferred speed that rises with panic.
    Preferred := Sp.Cruise * (1 + 1.3 * F^.Alarm);
    Ax := Ax + (Preferred - Speed) * Hx * 1.6;
    Ay := Ay + (Preferred - Speed) * Hy * 1.6;

    Before := ArcTan2(F^.Vy, F^.Vx);
    F^.Vx := F^.Vx + Ax * DT;
    F^.Vy := F^.Vy + Ay * DT;
    MaxSpeed := Sp.MaxSpeed * (1 + 1.8 * F^.Alarm);
    S := Sqrt(F^.Vx * F^.Vx + F^.Vy * F^.Vy);
    if S > MaxSpeed then
    begin
      F^.Vx := F^.Vx * MaxSpeed / S;
      F^.Vy := F^.Vy * MaxSpeed / S;
    end
    else if (S < Sp.MinSpeed) and (S > 1E-3) then
    begin
      F^.Vx := F^.Vx * Sp.MinSpeed / S;
      F^.Vy := F^.Vy * Sp.MinSpeed / S;
    end;
    F^.Turn := F^.Turn + (AngleDiff(Before, ArcTan2(F^.Vy, F^.Vx)) / DT - F^.Turn) * Min(1, DT * 8);
    F^.Phase := F^.Phase + DT * (7 + Sqrt(F^.Vx * F^.Vx + F^.Vy * F^.Vy) * 0.12);
    F^.X := SharkClamp(F^.X + F^.Vx * DT, -60, FWidth + 60);
    F^.Y := SharkClamp(F^.Y + F^.Vy * DT, -60, FHeight + 60);
  end;
end;

procedure TSharkWorld.StepSharks(DT: Double);
var
  Sh, K, I, Oth: Integer;
  S: ^TSharkBody;
  L, Hx, Hy, Dx, Dy, TX, TY, D, W, Closing, Radius, Rx, Ry, R, Radial: Double;
  Ox, Oy, Range, Over, ToX, ToY, Desired, Agility, MaxTurn, Turned: Double;
  CruiseSpeed, TargetSpeed, Seg, MaxBend, PrevAngle, Angle, Px, Py, MouthR, Mx, My: Double;
  MinSide, CxW, CyW: Double;
  Hunting: Boolean;
  T: ^TFish;
  Ev: TWorldEvent;
begin
  MinSide := Min(FWidth, FHeight);
  CxW := FWidth / 2;
  CyW := FHeight / 2;

  for Sh := 0 to High(FSharks) do
  begin
    S := @FSharks[Sh];
    L := S^.Length;
    Hx := S^.Nodes[0];
    Hy := S^.Nodes[1];

    S^.Hunger := Min(1, S^.Hunger + DT * 0.03);

    // Momentum.
    Dx := Cos(S^.Heading);
    Dy := Sin(S^.Heading);

    // Wander: a slowly drifting offset on a circle ahead of the snout.
    S^.Wander := SharkClamp(S^.Wander + (FRandom.Next - 0.5) * DT * 3.2, -1.1, 1.1);
    Dx := Dx + Cos(S^.Heading + S^.Wander) * 0.45;
    Dy := Dy + Sin(S^.Heading + S^.Wander) * 0.45;

    // Hunt.
    if FTime >= S^.RetargetAt then
    begin
      S^.Target := FindPrey(S^);
      S^.RetargetAt := FTime + 0.45;
    end;
    Hunting := False;
    Closing := 0;
    if (S^.Target >= 0) and FFish[S^.Target].Alive and (S^.Hunger > 0.3) then
    begin
      T := @FFish[S^.Target];
      // Pursuit: aim at where the fish is about to be.
      TX := T^.X + T^.Vx * 0.35 - Hx;
      TY := T^.Y + T^.Vy * 0.35 - Hy;
      D := Sqrt(TX * TX + TY * TY);
      if D = 0 then
        D := 1;
      W := 1.4 + 2.6 * S^.Hunger;
      Dx := Dx + (TX / D) * W;
      Dy := Dy + (TY / D) * W;
      Hunting := True;
      Closing := SharkClamp(1 - D / (L * 0.9), 0, 1);
    end
    else
    begin
      // Patrol: a lazy circuit around the middle of the screen.
      Rx := (Hx - CxW) / (FWidth / MinSide);
      Ry := Hy - CyW;
      R := Sqrt(Rx * Rx + Ry * Ry);
      if R = 0 then
        R := 1;
      Radius := S^.OrbitRadius * (1 + 0.15 * Sin(FTime * 0.05 + S^.Id));
      Radial := SharkClamp((Radius - R) / Radius, -1, 1);
      Dx := Dx + ((-Ry / R) * S^.OrbitDir + (Rx / R) * Radial * 0.9) * 0.55;
      Dy := Dy + ((Rx / R) * S^.OrbitDir + (Ry / R) * Radial * 0.9) * 0.55;
    end;

    // Give other sharks room.
    for Oth := 0 to High(FSharks) do
    begin
      if Oth = Sh then
        Continue;
      K := 0;
      while K < cSharkNodes do
      begin
        Ox := Hx - FSharks[Oth].Nodes[K * 2];
        Oy := Hy - FSharks[Oth].Nodes[K * 2 + 1];
        D := Sqrt(Ox * Ox + Oy * Oy);
        Range := (L + FSharks[Oth].Length) * 0.45;
        if (D < Range) and (D > 1E-3) then
        begin
          W := (1 - D / Range) * 3;
          Dx := Dx + (Ox / D) * W;
          Dy := Dy + (Oy / D) * W;
        end;
        Inc(K, 4);
      end;
    end;

    // Turn back once the snout leaves the frame, so bodies dip off-screen now
    // and then but the sharks never wander away for good.
    Over := Max(Max(-Hx, Hx - FWidth), Max(-Hy, Hy - FHeight));
    if Over > -L * 0.05 then
    begin
      W := SharkClamp((Over + L * 0.05) / (L * 0.35), 0, 1) * 3.5;
      ToX := CxW - Hx;
      ToY := CyW - Hy;
      D := Sqrt(ToX * ToX + ToY * ToY);
      if D = 0 then
        D := 1;
      Dx := Dx + (ToX / D) * W;
      Dy := Dy + (ToY / D) * W;
    end;

    Desired := ArcTan2(Dy, Dx);
    // Sharks can't pivot on the spot: the turning circle grows with speed.
    if Hunting then
      Agility := Min(1.7 + Closing, S^.Speed / (L * 0.22))
    else
      Agility := Min(0.8, S^.Speed / (L * 0.22));
    MaxTurn := Agility * DT;
    Turned := SharkClamp(AngleDiff(S^.Heading, Desired), -MaxTurn, MaxTurn);
    S^.Heading := S^.Heading + Turned;
    S^.Turn := S^.Turn + (Turned / DT - S^.Turn) * Min(1, DT * 3);

    CruiseSpeed := 30 + L * 0.04;
    if Hunting then
      TargetSpeed := CruiseSpeed * (1.45 + Closing * 1.5)
    else
      TargetSpeed := CruiseSpeed;
    S^.Speed := S^.Speed + (TargetSpeed - S^.Speed) * Min(1, DT * 1.1);
    S^.Phase := S^.Phase + DT * (2 + S^.Speed / 24);

    S^.Nodes[0] := S^.Nodes[0] + Cos(S^.Heading) * S^.Speed * DT;
    S^.Nodes[1] := S^.Nodes[1] + Sin(S^.Heading) * S^.Speed * DT;

    // Follow-the-leader spine, with a stiffness limit per joint so the body
    // bends into a C at most and never folds back on itself.
    Seg := L / (cSharkNodes - 1);
    MaxBend := 0.16;
    PrevAngle := S^.Heading + Pi;
    for K := 1 to cSharkNodes - 1 do
    begin
      Px := S^.Nodes[(K - 1) * 2];
      Py := S^.Nodes[(K - 1) * 2 + 1];
      Angle := ArcTan2(S^.Nodes[K * 2 + 1] - Py, S^.Nodes[K * 2] - Px);
      Angle := PrevAngle + SharkClamp(AngleDiff(PrevAngle, Angle), -MaxBend, MaxBend);
      S^.Nodes[K * 2] := Px + Cos(Angle) * Seg;
      S^.Nodes[K * 2 + 1] := Py + Sin(Angle) * Seg;
      PrevAngle := Angle;
    end;

    // Feed.
    if S^.Hunger > 0.15 then
    begin
      MouthR := L * 0.05 + 8;
      Mx := S^.Nodes[0];
      My := S^.Nodes[1];
      for I := 0 to High(FFish) do
      begin
        if not FFish[I].Alive then
          Continue;
        if Sqr(FFish[I].X - Mx) + Sqr(FFish[I].Y - My) < MouthR * MouthR then
        begin
          FFish[I].Alive := False;
          FFish[I].RespawnAt := FTime + FRandom.Range(3, 8);
          S^.Hunger := Max(0, S^.Hunger - 0.16);
          Ev.Kind := wekEat;
          Ev.X := FFish[I].X;
          Ev.Y := FFish[I].Y;
          FEvents.Add(Ev);
        end;
      end;
    end;
  end;
end;

function TSharkWorld.FindPrey(const AShark: TSharkBody): Integer;
var
  Range, Hx, Hy, Fx, Fy, Dx, Dy, D, Cs, Score, BestScore, CurrentScore: Double;
  I, Crowd: Integer;
begin
  Range := AShark.Length * 0.9 + 160;
  Hx := AShark.Nodes[0];
  Hy := AShark.Nodes[1];
  Fx := Cos(AShark.Heading);
  Fy := Sin(AShark.Heading);
  Result := -1;
  BestScore := MaxDouble;
  CurrentScore := MaxDouble;
  for I := 0 to High(FFish) do
  begin
    if not FFish[I].Alive then
      Continue;
    Dx := FFish[I].X - Hx;
    Dy := FFish[I].Y - Hy;
    D := Sqrt(Dx * Dx + Dy * Dy);
    if (D > Range) or (D < 1E-3) then
      Continue;
    Cs := (Dx * Fx + Dy * Fy) / D;
    if Cs < 0.2 then
      Continue;
    Crowd := FBucketCount[BucketOf(FFish[I].X, FFish[I].Y)];
    Score := D * (1 + (1 - Cs) * 0.8) * (1 + Crowd * 0.07);
    if Score < BestScore then
    begin
      BestScore := Score;
      Result := I;
    end;
    if I = AShark.Target then
      CurrentScore := Score;
  end;
  // Stick with the current target unless something is clearly better.
  if (AShark.Target >= 0) and (CurrentScore < BestScore * 1.3) then
    Result := AShark.Target;
end;

procedure TSharkWorld.RespawnFish;
var
  I, Side, Species, MillDir, Taken, Count: Integer;
  Due: TArray<Integer>;
  Along, X, Y, Inward: Double;
  Sp: TFishSpecies;
begin
  SetLength(Due, 0);
  for I := 0 to High(FFish) do
    if (not FFish[I].Alive) and (FFish[I].RespawnAt <= FTime) then
      Due := Due + [I];
  if Length(Due) = 0 then
    Exit;
  if (Length(Due) < 6) and (FTime - FLastSpawn < 9) then
    Exit;
  FLastSpawn := FTime;

  // A new school swims in from a random edge.
  Side := FRandom.IntRange(0, 3);
  Along := FRandom.Range(0.15, 0.85);
  if Side = 0 then
    X := -20
  else if Side = 1 then
    X := FWidth + 20
  else
    X := Along * FWidth;
  if Side = 2 then
    Y := -20
  else if Side = 3 then
    Y := FHeight + 20
  else
    Y := Along * FHeight;
  Inward := ArcTan2(FHeight / 2 - Y, FWidth / 2 - X) + FRandom.Range(-0.5, 0.5);
  Species := PickFishSpecies(FRandom);
  Sp := FishSpecies(Species);
  if FRandom.Next < 0.5 then
    MillDir := 1
  else
    MillDir := -1;
  Count := Min(Length(Due), Sp.SchoolMax);
  for Taken := 0 to Count - 1 do
  begin
    I := Due[Taken];
    FFish[I].Alive := True;
    FFish[I].Species := Species;
    FFish[I].Alarm := 0;
    FFish[I].Turn := 0;
    FFish[I].MillDir := MillDir;
    FFish[I].X := X + FRandom.Range(-1, 1) * FPerception;
    FFish[I].Y := Y + FRandom.Range(-1, 1) * FPerception;
    FFish[I].Vx := Cos(Inward) * Sp.Cruise * 1.4;
    FFish[I].Vy := Sin(Inward) * Sp.Cruise * 1.4;
  end;
end;

{$ENDIF}

end.
