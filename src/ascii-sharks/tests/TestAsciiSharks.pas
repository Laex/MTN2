unit TestAsciiSharks;

{$I ..\sharks.inc}

{ The screensaver subsystem: the numbers, the world of fish and sharks, its
  drawing in text cells, and the idle / wake rules of the saver. Empty when the
  subsystem is left out of the build (NO_ASCII_SHARKS). }

interface

uses
  DUnitX.TestFramework;

type
{$IFDEF MTN_ASCII_SHARKS}
  [TestFixture]
  TTestSharkMath = class
  public
    [Test] procedure RandomRepeatsForTheSameSeed;
    [Test] procedure RandomStaysInRange;
    [Test] procedure HashIsStableAndSpreads;
    [Test] procedure AngleDifferenceIsTheShortWay;
    [Test] procedure CurrentIsFinite;
  end;

  [TestFixture]
  TTestSharkWorld = class
  public
    [Test] procedure WorldHoldsFishAndSharks;
    [Test] procedure SameSeedSameSea;
    [Test] procedure FishStayNearTheScreen;
    [Test] procedure SpineKeepsItsLength;
    [Test] procedure SharksStayInTheFrameForGood;
    [Test] procedure SharksEatAndTheSchoolsComeBack;
    [Test] procedure SmallScreenStillWorks;
    [Test] procedure ResizeKeepsTheSameFishAndSharks;
  end;

  [TestFixture]
  TTestSharkRender = class
  public
    [Test] procedure SharksAndFishAreDrawnOnBlack;
    [Test] procedure EveryKindOfSharkIsDrawn;
    [Test] procedure SharkCellsAreGreyBlocksWithLetters;
    [Test] procedure ShortGridIsNotOverrun;
  end;

  [TestFixture]
  TTestSharkSaver = class
  public
    [Test] procedure IdleTimeRunsOutOnlyWhenTheSaverIsOn;
    [Test] procedure InputStopsTheSharksAndIsUsedUp;
    [Test] procedure MovementRightAfterTheStartDoesNotStopThem;
    [Test] procedure ToggleStartsAndStopsAndDrawsBlack;
    [Test] procedure ResizeWhileSwimmingKeepsDrawing;
    [Test] procedure ChoicesStartWithOff;
  end;
{$ELSE}
  [TestFixture]
  TTestSharkSaverLeftOut = class
  public
    [Test] procedure SaverIsInertWithoutTheSubsystem;
  end;
{$ENDIF}

implementation

{$IFDEF MTN_ASCII_SHARKS}

uses
  System.SysUtils, System.Math, System.UITypes, uTerminalTypes, uSharkMath, uSharkSpecies,
  uSharkShapes, uSharkWorld, uSharkRender, uSharkSaver;

const
  cBlack = TAlphaColor($FF000000);

function NewGrid(AWidth, AHeight: Integer): TTerminalGrid;
begin
  AllocTerminalGrid(Result, AWidth, AHeight);
  ClearTerminalGrid(Result, TAlphaColor($FFFFFFFF), TAlphaColor($FF123456));
end;

function Specs(const AKinds: array of TSharkKind): TArray<TSharkSpec>;
var
  I: Integer;
begin
  SetLength(Result, Length(AKinds));
  for I := 0 to High(AKinds) do
  begin
    Result[I].Kind := AKinds[I];
    Result[I].Size := 1;
  end;
end;

function NewWorld(ASeed: Cardinal; ACols, ARows: Integer; const ASpecs: TArray<TSharkSpec>): TSharkWorld;
begin
  Result := TSharkWorld.Create(ASpecs, ASeed);
  Result.Resize(ACols * cSharkCellWidth, ARows * cSharkCellHeight, cSharkCellWidth,
    cSharkCellHeight);
end;

function AliveFish(AWorld: TSharkWorld): Integer;
var
  F: TFish;
begin
  Result := 0;
  for F in AWorld.Fish do
    if F.Alive then
      Inc(Result);
end;

{ TTestSharkMath }

procedure TTestSharkMath.RandomRepeatsForTheSameSeed;
var
  A, B: TSharkRandom;
  I: Integer;
begin
  A := TSharkRandom.Create(42);
  B := TSharkRandom.Create(42);
  try
    for I := 1 to 50 do
      Assert.AreEqual(A.Next, B.Next);
  finally
    B.Free;
    A.Free;
  end;
end;

procedure TTestSharkMath.RandomStaysInRange;
var
  R: TSharkRandom;
  I, V: Integer;
  D: Double;
begin
  R := TSharkRandom.Create(7);
  try
    for I := 1 to 2000 do
    begin
      D := R.Next;
      Assert.IsTrue((D >= 0) and (D < 1));
      D := R.Range(-2, 3);
      Assert.IsTrue((D >= -2) and (D <= 3));
      V := R.IntRange(2, 5);
      Assert.IsTrue((V >= 2) and (V <= 5));
    end;
  finally
    R.Free;
  end;
end;

procedure TTestSharkMath.HashIsStableAndSpreads;
var
  Seen: array[0..9] of Boolean;
  I, Slot, Count: Integer;
begin
  Assert.AreEqual(HashBits(3, 4, 5), HashBits(3, 4, 5));
  Assert.AreNotEqual(HashBits(3, 4, 5), HashBits(4, 3, 5));
  Assert.IsTrue(Hash3(-7, 100000, 3) < 1);
  Assert.IsTrue(Hash3(-7, 100000, 3) >= 0);
  FillChar(Seen, SizeOf(Seen), 0);
  for I := 0 to 999 do
  begin
    Slot := Trunc(Hash3(I, I * 3, 11) * 10);
    Seen[Slot] := True;
  end;
  Count := 0;
  for I := 0 to 9 do
    if Seen[I] then
      Inc(Count);
  Assert.AreEqual(10, Count, 'a thousand inputs reach every tenth');
end;

procedure TTestSharkMath.AngleDifferenceIsTheShortWay;
begin
  Assert.AreEqual(0.2, AngleDiff(0.1, 0.3), 1E-9);
  Assert.AreEqual(-0.2, AngleDiff(0.3, 0.1), 1E-9);
  Assert.AreEqual(0.2, AngleDiff(Pi - 0.1, -Pi + 0.1), 1E-9, 'across the half turn');
  Assert.IsTrue(Abs(AngleDiff(0, 7 * Pi)) <= Pi + 1E-9);
end;

procedure TTestSharkMath.CurrentIsFinite;
var
  I, J: Integer;
  Ux, Uy: Double;
begin
  for I := 0 to 5 do
    for J := 0 to 5 do
    begin
      OceanCurrent(I * 190, J * 120, 33.3, Ux, Uy);
      Assert.IsFalse(IsNan(Ux) or IsNan(Uy));
      Assert.IsTrue((Abs(Ux) < 20) and (Abs(Uy) < 20), 'a gentle drift');
    end;
end;

{ TTestSharkWorld }

procedure TTestSharkWorld.WorldHoldsFishAndSharks;
var
  W: TSharkWorld;
begin
  W := NewWorld(1, 120, 40, Specs([skClassic, skMako]));
  try
    Assert.AreEqual(2, Integer(Length(W.Sharks)));
    Assert.IsTrue(Length(W.Fish) >= 85, 'a school or more');
    Assert.AreEqual(Integer(Length(W.Fish)), AliveFish(W), 'all fish are alive at the start');
    Assert.IsTrue(W.Sharks[0].Length <= W.Sharks[1].Length, 'smaller sharks come first');
  finally
    W.Free;
  end;
end;

procedure TTestSharkWorld.SameSeedSameSea;
var
  A, B: TSharkWorld;
  I: Integer;
begin
  A := NewWorld(5, 100, 30, Specs([skClassic, skNurse]));
  B := NewWorld(5, 100, 30, Specs([skClassic, skNurse]));
  try
    for I := 1 to 600 do
    begin
      A.Step(1 / 60);
      B.Step(1 / 60);
    end;
    Assert.AreEqual(A.Sharks[0].Nodes[0], B.Sharks[0].Nodes[0], 1E-9);
    Assert.AreEqual(A.Fish[3].X, B.Fish[3].X, 1E-9);
  finally
    B.Free;
    A.Free;
  end;
end;

procedure TTestSharkWorld.FishStayNearTheScreen;
var
  W: TSharkWorld;
  I: Integer;
  F: TFish;
begin
  W := NewWorld(2, 120, 40, Specs([skClassic, skTiger, skMako]));
  try
    for I := 1 to 1800 do
      W.Step(1 / 60);
    for F in W.Fish do
    begin
      Assert.IsTrue((F.X >= -60) and (F.X <= W.Width + 60));
      Assert.IsTrue((F.Y >= -60) and (F.Y <= W.Height + 60));
      Assert.IsFalse(IsNan(F.X) or IsNan(F.Y) or IsNan(F.Vx));
      Assert.IsTrue((F.Alarm >= 0) and (F.Alarm <= 1.5), 'alarm is a fraction');
    end;
  finally
    W.Free;
  end;
end;

procedure TTestSharkWorld.SpineKeepsItsLength;
var
  W: TSharkWorld;
  I, K: Integer;
  Seg, D: Double;
begin
  W := NewWorld(3, 120, 40, Specs([skThresher]));
  try
    for I := 1 to 900 do
      W.Step(1 / 60);
    Seg := W.Sharks[0].Length / (cSharkNodes - 1);
    for K := 1 to cSharkNodes - 1 do
    begin
      D := Sqrt(Sqr(W.Sharks[0].Nodes[K * 2] - W.Sharks[0].Nodes[(K - 1) * 2]) +
        Sqr(W.Sharks[0].Nodes[K * 2 + 1] - W.Sharks[0].Nodes[(K - 1) * 2 + 1]));
      Assert.AreEqual(Seg, D, 0.01, 'the body is not stretched');
    end;
  finally
    W.Free;
  end;
end;

procedure TTestSharkWorld.SharksStayInTheFrameForGood;
var
  W: TSharkWorld;
  I, S: Integer;
begin
  W := NewWorld(4, 120, 40, Specs([skClassic, skZebra, skGreatHammer]));
  try
    for I := 1 to 3600 do
    begin
      W.Step(1 / 60);
      for S := 0 to High(W.Sharks) do
      begin
        Assert.IsTrue((W.Sharks[S].Nodes[0] > -W.Width) and (W.Sharks[S].Nodes[0] < 2 * W.Width),
          'the snout does not wander away');
        Assert.IsTrue((W.Sharks[S].Nodes[1] > -W.Height) and (W.Sharks[S].Nodes[1] < 2 * W.Height));
      end;
    end;
  finally
    W.Free;
  end;
end;

procedure TTestSharkWorld.SharksEatAndTheSchoolsComeBack;
var
  W: TSharkWorld;
  I, Eaten, Lowest: Integer;
  E: TWorldEvent;
begin
  W := NewWorld(9, 120, 40, Specs([skClassic, skMako, skNurse, skTiger]));
  try
    Eaten := 0;
    Lowest := Length(W.Fish);
    for I := 1 to 60 * 240 do
    begin
      W.Step(1 / 60);
      for E in W.Events do
        if E.Kind = wekEat then
          Inc(Eaten);
      W.Events.Clear;
      Lowest := Min(Lowest, AliveFish(W));
    end;
    Assert.IsTrue(Eaten > 0, 'four hungry sharks eat something in four minutes');
    Assert.IsTrue(Lowest < Length(W.Fish), 'the population dipped');
    Assert.IsTrue(AliveFish(W) > Length(W.Fish) div 2, 'new schools swim in');
  finally
    W.Free;
  end;
end;

procedure TTestSharkWorld.SmallScreenStillWorks;
var
  W: TSharkWorld;
  I: Integer;
begin
  W := NewWorld(6, 40, 10, Specs([skMako]));
  try
    for I := 1 to 600 do
      W.Step(1 / 60);
    Assert.IsFalse(IsNan(W.Sharks[0].Nodes[0]));
  finally
    W.Free;
  end;
end;

procedure TTestSharkWorld.ResizeKeepsTheSameFishAndSharks;
var
  W: TSharkWorld;
  I, FishBefore: Integer;
  Id: Integer;
  Snout: Double;
begin
  W := NewWorld(14, 120, 40, Specs([skClassic, skMako]));
  try
    for I := 1 to 300 do
      W.Step(1 / 60);
    FishBefore := Length(W.Fish);
    Id := W.Sharks[1].Id;
    Snout := W.Sharks[1].Nodes[0];
    W.Resize(80 * cSharkCellWidth, 24 * cSharkCellHeight, cSharkCellWidth, cSharkCellHeight);
    Assert.AreEqual(FishBefore, Integer(Length(W.Fish)), 'the same fish');
    Assert.AreEqual(2, Integer(Length(W.Sharks)), 'the same sharks');
    Assert.AreEqual(Id, W.Sharks[1].Id);
    Assert.AreEqual(Snout, W.Sharks[1].Nodes[0], 1E-9, 'a shark is not moved');
    for I := 0 to High(W.Fish) do
    begin
      Assert.IsTrue((W.Fish[I].X >= 0) and (W.Fish[I].X <= W.Width), 'fish are inside the new edges');
      Assert.IsTrue((W.Fish[I].Y >= 0) and (W.Fish[I].Y <= W.Height));
    end;
    for I := 1 to 600 do
      W.Step(1 / 60);
    Assert.IsFalse(IsNan(W.Sharks[0].Nodes[0]));
  finally
    W.Free;
  end;
end;

{ TTestSharkRender }

procedure TTestSharkRender.SharksAndFishAreDrawnOnBlack;
var
  W: TSharkWorld;
  R: TSharkRenderer;
  Grid: TTerminalGrid;
  X, Y, Fish, Grey, Black: Integer;
  I: Integer;
begin
  W := NewWorld(8, 120, 40, Specs([skClassic, skHammerhead]));
  R := TSharkRenderer.Create;
  try
    R.Resize(120, 40);
    for I := 1 to 600 do
      W.Step(1 / 60);
    R.Render(W, 0.1);
    Grid := NewGrid(120, 40);
    R.Paint(Grid, W.Time);
    Fish := 0;
    Grey := 0;
    Black := 0;
    for Y := 0 to 39 do
      for X := 0 to 119 do
      begin
        if Grid[Y][X].CharValue = '-' then
          Inc(Fish);
        if Grid[Y][X].BgColor = cBlack then
          Inc(Black)
        else
          Inc(Grey);
      end;
    Assert.IsTrue(Fish > 20, 'fish are dashes');
    Assert.IsTrue(Grey > 40, 'sharks are blocks');
    Assert.IsTrue(Black > Grey * 4, 'the screen is mostly black');
    Assert.AreEqual(Cardinal(cBlack), Cardinal(Grid[0][0].BgColor) or 0, 'the old background is overwritten'
      + ' (the corner is empty water)');
  finally
    R.Free;
    W.Free;
  end;
end;

procedure TTestSharkRender.EveryKindOfSharkIsDrawn;
var
  Kind: TSharkKind;
  W: TSharkWorld;
  R: TSharkRenderer;
  Grid: TTerminalGrid;
  X, Y, Painted, I: Integer;
begin
  for Kind := Low(TSharkKind) to High(TSharkKind) do
  begin
    W := NewWorld(100 + Ord(Kind), 120, 40, Specs([Kind]));
    R := TSharkRenderer.Create;
    try
      R.Resize(120, 40);
      for I := 1 to 120 do
        W.Step(1 / 60);
      R.Render(W, 0.1);
      Grid := NewGrid(120, 40);
      R.Paint(Grid, W.Time);
      Painted := 0;
      for Y := 0 to 39 do
        for X := 0 to 119 do
          if (Grid[Y][X].BgColor <> cBlack) and (Grid[Y][X].BgColor <> TAlphaColor($FF123456)) then
            Inc(Painted);
      Assert.IsTrue(Painted > 40, 'a ' + IntToStr(Ord(Kind)) + 'th kind is on screen');
    finally
      R.Free;
      W.Free;
    end;
  end;
end;

procedure TTestSharkRender.SharkCellsAreGreyBlocksWithLetters;
var
  W: TSharkWorld;
  R: TSharkRenderer;
  Grid: TTerminalGrid;
  X, Y, I, Letters, Blocks: Integer;
  Cell: TCharCell;
begin
  W := NewWorld(12, 120, 40, Specs([skClassic]));
  R := TSharkRenderer.Create;
  try
    R.Resize(120, 40);
    for I := 1 to 120 do
      W.Step(1 / 60);
    R.Render(W, 0.1);
    Grid := NewGrid(120, 40);
    R.Paint(Grid, W.Time);
    Letters := 0;
    Blocks := 0;
    for Y := 0 to 39 do
      for X := 0 to 119 do
      begin
        Cell := Grid[Y][X];
        if Cell.BgColor = cBlack then
          Continue;
        Inc(Blocks);
        if not CharInSet(Cell.CharValue, [' ', '-', '.', ':', '*']) then
          Inc(Letters);
        Assert.IsTrue(((Cell.BgColor shr 16) and $FF) < 250, 'a block is grey, not white');
      end;
    Assert.IsTrue(Blocks > 40);
    Assert.IsTrue(Letters > Blocks div 3, 'blocks carry dense letters');
  finally
    R.Free;
    W.Free;
  end;
end;

procedure TTestSharkRender.ShortGridIsNotOverrun;
var
  W: TSharkWorld;
  R: TSharkRenderer;
  Grid: TTerminalGrid;
begin
  W := NewWorld(13, 120, 40, Specs([skNurse]));
  R := TSharkRenderer.Create;
  try
    R.Resize(120, 40);
    R.Render(W, 0.1);
    Grid := NewGrid(30, 8);
    R.Paint(Grid, W.Time);
    Assert.AreEqual(8, Integer(Length(Grid)));
  finally
    R.Free;
    W.Free;
  end;
end;

{ TTestSharkSaver }

procedure TTestSharkSaver.IdleTimeRunsOutOnlyWhenTheSaverIsOn;
begin
  Assert.IsFalse(SaverIdleDue(0, 99999999), 'off never starts');
  Assert.IsFalse(SaverIdleDue(5, 5 * 60000 - 1));
  Assert.IsTrue(SaverIdleDue(5, 5 * 60000));
  Assert.IsTrue(SaverIdleDue(1, 3600000));
end;

procedure TTestSharkSaver.InputStopsTheSharksAndIsUsedUp;
var
  Saver: TSharkSaver;
  Changes: Integer;
begin
  Changes := 0;
  Saver := TSharkSaver.Create(procedure begin Inc(Changes); end);
  try
    Assert.IsFalse(Saver.Wake, 'nothing to stop: the input is not used up');
    Saver.Start;
    Assert.IsTrue(Saver.Active);
    Assert.IsTrue(Saver.Wake, 'the key that stops them is used up');
    Assert.IsFalse(Saver.Active);
    Assert.IsFalse(Saver.Wake, 'the next key is a normal one');
    Assert.IsTrue(Changes >= 2, 'start and stop ask for a repaint');
  finally
    Saver.Free;
  end;
end;

procedure TTestSharkSaver.MovementRightAfterTheStartDoesNotStopThem;
var
  Saver: TSharkSaver;
begin
  Saver := TSharkSaver.Create(nil);
  try
    Saver.Start;
    Assert.IsTrue(Saver.WakeByMove, 'the pointer that clicked is still settling');
    Assert.IsTrue(Saver.Active);
    Assert.IsTrue(Saver.Wake, 'a key stops them at once');
    Assert.IsFalse(Saver.Active);
    Assert.IsFalse(Saver.WakeByMove, 'movement while they are not swimming is no input to use up');
  finally
    Saver.Free;
  end;
end;

procedure TTestSharkSaver.ToggleStartsAndStopsAndDrawsBlack;
var
  Saver: TSharkSaver;
  Grid: TTerminalGrid;
  X, Y, Changed, Black: Integer;
begin
  Saver := TSharkSaver.Create(nil);
  try
    Grid := NewGrid(100, 30);
    Saver.Draw(Grid, 100, 30);
    Changed := 0;
    for Y := 0 to 29 do
      for X := 0 to 99 do
        if Grid[Y][X].BgColor <> TAlphaColor($FF123456) then
          Inc(Changed);
    Assert.AreEqual(0, Changed, 'nothing is drawn while stopped');
    Saver.Toggle;
    Assert.IsTrue(Saver.Active);
    Saver.Draw(Grid, 100, 30);
    Black := 0;
    for Y := 0 to 29 do
      for X := 0 to 99 do
        if Grid[Y][X].BgColor = cBlack then
          Inc(Black);
    Assert.IsTrue(Black > 100 * 30 div 2, 'the screen goes black');
    Saver.Toggle;
    Assert.IsFalse(Saver.Active);
  finally
    Saver.Free;
  end;
end;

procedure TTestSharkSaver.ResizeWhileSwimmingKeepsDrawing;
var
  Saver: TSharkSaver;
  Grid: TTerminalGrid;
  X, Y, Black, Cols, Rows: Integer;
begin
  Saver := TSharkSaver.Create(nil);
  try
    Saver.Start;
    Grid := NewGrid(100, 30);
    Saver.Draw(Grid, 100, 30);
    for Cols := 3 to 4 do
    begin
      // Smaller, tiny, then larger than the first size.
      Rows := Cols * 3;
      Grid := NewGrid(Cols * 20, Rows);
      Saver.Draw(Grid, Cols * 20, Rows);
    end;
    Grid := NewGrid(140, 45);
    Saver.Draw(Grid, 140, 45);
    Black := 0;
    for Y := 0 to 44 do
      for X := 0 to 139 do
        if Grid[Y][X].BgColor = cBlack then
          Inc(Black);
    Assert.IsTrue(Black > 140 * 45 div 2, 'the screen is black at the new size');
    Grid := NewGrid(2, 1);
    Saver.Draw(Grid, 2, 1);
    Assert.IsTrue(Saver.Active, 'a tiny window does not end the saver');
  finally
    Saver.Free;
  end;
end;

procedure TTestSharkSaver.ChoicesStartWithOff;
var
  I: Integer;
begin
  Assert.AreEqual(0, cSaverMinuteChoices[0]);
  for I := 1 to High(cSaverMinuteChoices) do
    Assert.IsTrue(cSaverMinuteChoices[I] > cSaverMinuteChoices[I - 1], 'ascending');
end;

{$ELSE}

uses
  uSharkSaver;

procedure TTestSharkSaverLeftOut.SaverIsInertWithoutTheSubsystem;
var
  Saver: TSharkSaver;
begin
  Assert.IsFalse(SharksBuiltIn);
  Saver := TSharkSaver.Create(nil);
  try
    Saver.Start;
    Assert.IsFalse(Saver.Active, 'it never starts');
    Assert.IsFalse(Saver.Wake, 'and never uses up an input');
  finally
    Saver.Free;
  end;
end;

{$ENDIF}

initialization
{$IFDEF MTN_ASCII_SHARKS}
  TDUnitX.RegisterTestFixture(TTestSharkMath);
  TDUnitX.RegisterTestFixture(TTestSharkWorld);
  TDUnitX.RegisterTestFixture(TTestSharkRender);
  TDUnitX.RegisterTestFixture(TTestSharkSaver);
{$ELSE}
  TDUnitX.RegisterTestFixture(TTestSharkSaverLeftOut);
{$ENDIF}

end.
