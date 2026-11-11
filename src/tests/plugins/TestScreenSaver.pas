unit TestScreenSaver;

interface

uses
  System.JSON, DUnitX.TestFramework;

type
  [TestFixture]
  TTestScreenSaverRegistry = class
  private
    FSavedId: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure RegisteredPictureIsListedAndReplacedById;
    [Test] procedure UnregisterRemovesOnlyThePicturesOfThatOwner;
    [Test] procedure UnknownIdFallsBackToARegisteredPicture;
    [Test] procedure StartShowsTheChosenPictureAndStopFinishesIt;
    [Test] procedure InputStopsTheSaverAndIsUsedUp;
    [Test] procedure RemovingTheOwnerStopsARunningSaver;
  end;

  [TestFixture]
  TTestPluginSaver = class
  private
    FSavedId: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure CellsFilledByThePluginReachTheGrid;
    [Test] procedure RegistrationNeedsTheTextModeAndAllCallbacks;
    [Test] procedure FailedDrawLeavesABlackScreen;
    [Test] procedure StopTellsThePluginTheSaverEnded;
  end;

  [TestFixture]
  TTestPixelSaver = class
  private
    FSavedId: string;
    FSavedPixelHost: Boolean;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure PixelOnlyPictureIsHiddenWhereThereAreNoPixels;
    [Test] procedure PixelHostGetsABgraFrameAndBlackCharacters;
    [Test] procedure TextHostStillGetsTheCharactersOfAMixedPicture;
    [Test] procedure FrameSizeFollowsTheWindowAndIsCapped;
    [Test] procedure FailedPixelDrawLeavesABlackScreen;
    [Test] procedure RegistrationNeedsTheCallbackOfEachMode;
  end;

  [TestFixture]
  TTestSaverSettings = class
  private
    FSavedId: string;
    FSavedMinutes: Integer;
    FSavedRandom: Boolean;
    function ReadJson: TJSONObject;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ChoiceListsThePicturesAndTheCurrentValues;
    [Test] procedure SmallBufferIsReported;
    [Test] procedure ValidChoiceIsApplied;
    [Test] procedure UnknownPictureChangesNothing;
    [Test] procedure UnknownMinutesChangesNothing;
    [Test] procedure EmptyIdAndNegativeMinutesKeepTheCurrentValues;
    [Test] procedure RandomFlagIsReadAndSetAndKeptWithMinusOne;
    [Test] procedure RandomStartPicksAUsablePicture;
  end;

  [TestFixture]
  TTestSaverModules = class
  public
    [Test] procedure InfoGivesIdNameAndTick;
    [Test] procedure InfoWithoutIdIsRefused;
    [Test] procedure TickIsKeptWithinLimits;
    [Test] procedure ModesDefaultToText;
    [Test] procedure PixelsModeIsKnown;
    [Test] procedure UnknownModesAreRefused;
  end;

implementation

uses
  System.SysUtils, System.UITypes, uTerminalTypes, uScreenSaver, uPluginHostAbi, uPluginSaver,
  uSaverModules;

const
  cOwner = 'test.owner';
  cOtherOwner = 'test.other';

type
  TFakeEffect = class(TInterfacedObject, ISaverEffect)
  public
    Prepared, Finished: Integer;
    function TickMs: Integer;
    procedure Prepare;
    procedure Advance(ASeconds: Double);
    procedure Draw(const AGrid: TTerminalGrid; ACols, ARows: Integer);
    procedure Finish;
  end;

var
  GLastFake: TFakeEffect;

function TFakeEffect.TickMs: Integer;
begin
  Result := 50;
end;

procedure TFakeEffect.Prepare;
begin
  Inc(Prepared);
end;

procedure TFakeEffect.Advance(ASeconds: Double);
begin
end;

procedure TFakeEffect.Draw(const AGrid: TTerminalGrid; ACols, ARows: Integer);
begin
end;

procedure TFakeEffect.Finish;
begin
  Inc(Finished);
end;

procedure RegisterFake(const AId, AOwner: string);
begin
  RegisterSaver(AId, AId, AOwner,
    function: ISaverEffect
    begin
      GLastFake := TFakeEffect.Create;
      Result := GLastFake;
    end);
end;

function NewGrid(ACols, ARows: Integer): TTerminalGrid;
var
  Y, X: Integer;
begin
  SetLength(Result, ARows);
  for Y := 0 to ARows - 1 do
  begin
    SetLength(Result[Y], ACols);
    for X := 0 to ACols - 1 do
      Result[Y][X] := TCharCell.Make('?', TAlphaColors.Red, TAlphaColors.Blue);
  end;
end;

function IndexOfId(const AId: string): Integer;
var
  Infos: TArray<TSaverInfo>;
  I: Integer;
begin
  Infos := RegisteredSavers;
  for I := 0 to High(Infos) do
    if SameText(Infos[I].Id, AId) then
      Exit(I);
  Result := -1;
end;

{ TTestScreenSaverRegistry }

procedure TTestScreenSaverRegistry.Setup;
begin
  FSavedId := GSaverId;
  GLastFake := nil;
end;

procedure TTestScreenSaverRegistry.TearDown;
begin
  UnregisterSavers(cOwner);
  UnregisterSavers(cOtherOwner);
  GSaverId := FSavedId;
end;

procedure TTestScreenSaverRegistry.RegisteredPictureIsListedAndReplacedById;
var
  Info: TSaverInfo;
  Count: Integer;
begin
  RegisterFake('test.one', cOwner);
  Assert.IsTrue(IndexOfId('test.one') >= 0, 'listed');
  Count := Length(RegisteredSavers);
  RegisterSaver('test.one', 'Renamed', cOwner,
    function: ISaverEffect
    begin
      Result := TFakeEffect.Create;
    end);
  Assert.AreEqual<Integer>(Count, Length(RegisteredSavers),'the same id does not add a second entry');
  Assert.IsTrue(FindSaver('TEST.ONE', Info), 'ids compare without case');
  Assert.AreEqual('Renamed', Info.Caption);
  Assert.IsFalse(RegisterSaver('', 'x', cOwner, nil), 'no id, no factory');
end;

procedure TTestScreenSaverRegistry.UnregisterRemovesOnlyThePicturesOfThatOwner;
begin
  RegisterFake('test.one', cOwner);
  RegisterFake('test.two', cOtherOwner);
  UnregisterSavers(cOwner);
  Assert.AreEqual(-1, IndexOfId('test.one'));
  Assert.IsTrue(IndexOfId('test.two') >= 0);
end;

procedure TTestScreenSaverRegistry.UnknownIdFallsBackToARegisteredPicture;
var
  Owner: string;
  Effect: ISaverEffect;
begin
  RegisterFake('test.one', cOwner);
  Effect := CreateSaverEffect('no.such.picture', Owner);
  Assert.IsTrue(Assigned(Effect), 'an unknown id still gives a picture while one is registered');
  Effect := CreateSaverEffect('test.one', Owner);
  Assert.IsTrue(Assigned(Effect));
  Assert.AreEqual(cOwner, Owner);
end;

procedure TTestScreenSaverRegistry.StartShowsTheChosenPictureAndStopFinishesIt;
var
  Saver: TScreenSaver;
  Fake: TFakeEffect;
  Hold: ISaverEffect;
begin
  RegisterFake('test.one', cOwner);
  GSaverId := 'test.one';
  Saver := TScreenSaver.Create(nil);
  try
    Saver.Start;
    Assert.IsTrue(Saver.Active);
    Fake := GLastFake;
    Hold := Fake;
    Assert.AreEqual(1, Fake.Prepared);
    Saver.Stop;
    Assert.IsFalse(Saver.Active);
    Assert.AreEqual(1, Fake.Finished);
  finally
    Saver.Free;
  end;
end;

procedure TTestScreenSaverRegistry.InputStopsTheSaverAndIsUsedUp;
var
  Saver: TScreenSaver;
begin
  RegisterFake('test.one', cOwner);
  GSaverId := 'test.one';
  Saver := TScreenSaver.Create(nil);
  try
    Assert.IsFalse(Saver.Wake, 'nothing to stop');
    Saver.Start;
    Assert.IsTrue(Saver.Wake, 'the key that stops it is used up');
    Assert.IsFalse(Saver.Active);
    Assert.IsFalse(Saver.Wake, 'the next one is not');
  finally
    Saver.Free;
  end;
end;

procedure TTestScreenSaverRegistry.RemovingTheOwnerStopsARunningSaver;
var
  Saver: TScreenSaver;
  Fake: TFakeEffect;
  Hold: ISaverEffect;
begin
  RegisterFake('test.one', cOwner);
  GSaverId := 'test.one';
  Saver := TScreenSaver.Create(nil);
  try
    Saver.Start;
    Fake := GLastFake;
    Hold := Fake;
    UnregisterSavers(cOwner);
    Assert.IsFalse(Saver.Active, 'the picture is gone, so is the saver');
    Assert.AreEqual(1, Fake.Finished, 'the picture was finished before its owner went');
  finally
    Saver.Free;
  end;
end;

{ Plugin side fakes }

type
  TPluginProbe = record
    Prepares, Finishes, Draws, PixelDraws: Integer;
    DrawResult, PixelResult, PixelW, PixelH: Int64;
    FirstPixel: Cardinal;
  end;

var
  GProbe: TPluginProbe;

function ProbeTickMs(AUserData: Pointer): Int64; cdecl;
begin
  Result := 40;
end;

function ProbePrepare(AUserData: Pointer): Int64; cdecl;
begin
  Inc(GProbe.Prepares);
  Result := 0;
end;

procedure ProbeAdvance(AUserData: Pointer; ADeltaMs: Int64); cdecl;
begin
end;

function ProbeDraw(AUserData: Pointer; ACols, ARows: Int64; ACells: PSaverCell): Int64; cdecl;
begin
  Inc(GProbe.Draws);
  ACells^.CodePoint := Ord('A');
  ACells^.Fg := $FF00FF00;
  ACells^.Attributes := cSaverAttrBold;
  Inc(ACells, ACols + 1);
  ACells^.CodePoint := Ord('B');
  ACells^.Bg := $FF0000FF;
  Result := GProbe.DrawResult;
end;

procedure ProbeFinish(AUserData: Pointer); cdecl;
begin
  Inc(GProbe.Finishes);
end;

function ProbeDrawPixels(AUserData: Pointer; AWidth, AHeight: Int64; APixels: PByte): Int64; cdecl;
begin
  Inc(GProbe.PixelDraws);
  GProbe.PixelW := AWidth;
  GProbe.PixelH := AHeight;
  // The host hands over opaque black: B, G, R, A.
  GProbe.FirstPixel := PCardinal(APixels)^;
  PCardinal(APixels)^ := $FF112233;
  Result := GProbe.PixelResult;
end;

function ProbeCallbacks: TSaverCallbacks;
begin
  Result := Default(TSaverCallbacks);
  Result.TickMs := ProbeTickMs;
  Result.Prepare := ProbePrepare;
  Result.Advance := ProbeAdvance;
  Result.Draw := ProbeDraw;
  Result.Finish := ProbeFinish;
end;

{ TTestPluginSaver }

procedure TTestPluginSaver.Setup;
begin
  FSavedId := GSaverId;
  GProbe := Default(TPluginProbe);
end;

procedure TTestPluginSaver.TearDown;
begin
  UnregisterSavers(cOwner);
  GSaverId := FSavedId;
end;

procedure TTestPluginSaver.CellsFilledByThePluginReachTheGrid;
var
  Callbacks: TSaverCallbacks;
  Saver: TScreenSaver;
  Grid: TTerminalGrid;
begin
  Callbacks := ProbeCallbacks;
  Assert.IsTrue(PluginRegisterSaver(cOwner, 'test.cells', 'Cells', cSaverModeText, @Callbacks, nil));
  GSaverId := 'test.cells';
  Saver := TScreenSaver.Create(nil);
  try
    Saver.Start;
    Grid := NewGrid(4, 2);
    Saver.Draw(Grid, 4, 2);
    Assert.AreEqual('A', string(Grid[0][0].CharValue));
    Assert.AreEqual(Cardinal($FF00FF00), Cardinal(Grid[0][0].FgColor));
    Assert.IsTrue(ccaBold in Grid[0][0].Attributes);
    Assert.AreEqual('B', string(Grid[1][1].CharValue));
    Assert.AreEqual(Cardinal($FF0000FF), Cardinal(Grid[1][1].BgColor));
    Assert.AreEqual(' ', string(Grid[1][3].CharValue), 'a cell the plugin left alone is a blank');
    Assert.AreEqual(Cardinal($FF000000), Cardinal(Grid[1][3].BgColor), 'on black');
    Assert.AreEqual(1, GProbe.Prepares);
  finally
    Saver.Free;
  end;
end;

procedure TTestPluginSaver.RegistrationNeedsTheTextModeAndAllCallbacks;
var
  Callbacks: TSaverCallbacks;
begin
  Callbacks := ProbeCallbacks;
  Assert.IsFalse(PluginRegisterSaver(cOwner, 'test.px', 'Px', 2, @Callbacks, nil), 'pixels only');
  Assert.IsFalse(PluginRegisterSaver(cOwner, '', 'x', cSaverModeText, @Callbacks, nil), 'no id');
  Assert.IsFalse(PluginRegisterSaver(cOwner, 'test.nil', 'x', cSaverModeText, nil, nil), 'no table');
  Callbacks.Draw := nil;
  Assert.IsFalse(PluginRegisterSaver(cOwner, 'test.nodraw', 'x', cSaverModeText, @Callbacks, nil),
    'no draw callback');
  Assert.AreEqual(-1, IndexOfId('test.px'));
  Assert.AreEqual(-1, IndexOfId('test.nodraw'));
end;

procedure TTestPluginSaver.FailedDrawLeavesABlackScreen;
var
  Callbacks: TSaverCallbacks;
  Saver: TScreenSaver;
  Grid: TTerminalGrid;
begin
  Callbacks := ProbeCallbacks;
  GProbe.DrawResult := -1;
  Assert.IsTrue(PluginRegisterSaver(cOwner, 'test.fail', 'Fail', cSaverModeText, @Callbacks, nil));
  GSaverId := 'test.fail';
  Saver := TScreenSaver.Create(nil);
  try
    Saver.Start;
    Grid := NewGrid(3, 2);
    Saver.Draw(Grid, 3, 2);
    Assert.AreEqual(' ', string(Grid[0][0].CharValue), 'the half-filled frame is dropped');
    Assert.AreEqual(Cardinal($FF000000), Cardinal(Grid[0][0].BgColor));
    Saver.Draw(Grid, 3, 2);
    Assert.AreEqual(1, GProbe.Draws, 'a failed picture is not asked again');
    Assert.IsTrue(Saver.Active, 'the saver stays up until input');
  finally
    Saver.Free;
  end;
end;

procedure TTestPluginSaver.StopTellsThePluginTheSaverEnded;
var
  Callbacks: TSaverCallbacks;
  Saver: TScreenSaver;
begin
  Callbacks := ProbeCallbacks;
  Assert.IsTrue(PluginRegisterSaver(cOwner, 'test.stop', 'Stop', cSaverModeText, @Callbacks, nil));
  GSaverId := 'test.stop';
  Saver := TScreenSaver.Create(nil);
  try
    Saver.Start;
    Saver.Stop;
    Assert.AreEqual(1, GProbe.Finishes);
    Saver.Start;
    UnregisterSavers(cOwner);
    Assert.AreEqual(2, GProbe.Finishes, 'unloading the plugin ends a running picture first');
  finally
    Saver.Free;
  end;
end;

{ TTestPixelSaver }

procedure TTestPixelSaver.Setup;
begin
  FSavedId := GSaverId;
  FSavedPixelHost := GSaverPixelHost;
  GProbe := Default(TPluginProbe);
end;

procedure TTestPixelSaver.TearDown;
begin
  UnregisterSavers(cOwner);
  GSaverId := FSavedId;
  GSaverPixelHost := FSavedPixelHost;
end;

procedure TTestPixelSaver.PixelOnlyPictureIsHiddenWhereThereAreNoPixels;
var
  Callbacks: TSaverCallbacks;
  Owner: string;
  Effect: ISaverEffect;
begin
  Callbacks := ProbeCallbacks;
  Callbacks.Draw := nil;
  Callbacks.DrawPixels := ProbeDrawPixels;
  Assert.IsTrue(PluginRegisterSaver(cOwner, 'test.px', 'Px', cSaverModePixels, @Callbacks, nil));
  GSaverPixelHost := False;
  Assert.AreEqual(-1, IndexOfId('test.px'), 'not listed in a text terminal');
  GSaverId := 'test.px';
  Effect := CreateSaverEffect('test.px', Owner);
  Assert.IsFalse(Owner = cOwner, 'and not used there');
  Effect := nil;
  GSaverPixelHost := True;
  Assert.IsTrue(IndexOfId('test.px') >= 0, 'listed where bitmaps can be shown');
end;

procedure TTestPixelSaver.PixelHostGetsABgraFrameAndBlackCharacters;
var
  Callbacks: TSaverCallbacks;
  Saver: TScreenSaver;
  Grid: TTerminalGrid;
  W, H: Integer;
  Pixels: PByte;
  Gen, Gen2: Cardinal;
begin
  Callbacks := ProbeCallbacks;
  Callbacks.Draw := nil;
  Callbacks.DrawPixels := ProbeDrawPixels;
  Assert.IsTrue(PluginRegisterSaver(cOwner, 'test.px', 'Px', cSaverModePixels, @Callbacks, nil));
  GSaverPixelHost := True;
  GSaverId := 'test.px';
  Saver := TScreenSaver.Create(nil);
  try
    Saver.Start;
    Grid := NewGrid(10, 4);
    Assert.IsFalse(Saver.PixelFrame(W, H, Pixels, Gen), 'nothing before the first Draw');
    Saver.Draw(Grid, 10, 4);
    Assert.IsTrue(Saver.PixelFrame(W, H, Pixels, Gen));
    Assert.AreEqual(10 * cSaverPixelCellW, W);
    Assert.AreEqual(4 * cSaverPixelCellH, H);
    Assert.AreEqual(Cardinal($FF000000), GProbe.FirstPixel, 'the plugin gets opaque black');
    Assert.AreEqual(Cardinal($FF112233), PCardinal(Pixels)^, 'and the frame it painted');
    Assert.AreEqual(' ', string(Grid[2][3].CharValue), 'the characters under the bitmap are blank');
    Assert.AreEqual(Cardinal($FF000000), Cardinal(Grid[2][3].BgColor));
    Saver.Draw(Grid, 10, 4);
    Assert.IsTrue(Saver.PixelFrame(W, H, Pixels, Gen2));
    Assert.AreNotEqual(Gen, Gen2, 'every frame is a new generation');
    Saver.Stop;
    Assert.IsFalse(Saver.PixelFrame(W, H, Pixels, Gen), 'no frame once stopped');
  finally
    Saver.Free;
  end;
end;

procedure TTestPixelSaver.TextHostStillGetsTheCharactersOfAMixedPicture;
var
  Callbacks: TSaverCallbacks;
  Saver: TScreenSaver;
  Grid: TTerminalGrid;
  W, H: Integer;
  Pixels: PByte;
  Gen: Cardinal;
begin
  Callbacks := ProbeCallbacks;
  Callbacks.DrawPixels := ProbeDrawPixels;
  Assert.IsTrue(PluginRegisterSaver(cOwner, 'test.mixed', 'Mixed',
    cSaverModeText or cSaverModePixels, @Callbacks, nil));
  GSaverPixelHost := False;
  GSaverId := 'test.mixed';
  Saver := TScreenSaver.Create(nil);
  try
    Saver.Start;
    Grid := NewGrid(4, 2);
    Saver.Draw(Grid, 4, 2);
    Assert.IsFalse(Saver.PixelFrame(W, H, Pixels, Gen));
    Assert.AreEqual('A', string(Grid[0][0].CharValue));
    Assert.AreEqual(0, GProbe.PixelDraws, 'the pixel callback is not used in a text host');
  finally
    Saver.Free;
  end;
end;

procedure TTestPixelSaver.FrameSizeFollowsTheWindowAndIsCapped;
var
  Callbacks: TSaverCallbacks;
  Saver: TScreenSaver;
  Grid: TTerminalGrid;
  W, H: Integer;
  Pixels: PByte;
  Gen: Cardinal;
begin
  Callbacks := ProbeCallbacks;
  Callbacks.Draw := nil;
  Callbacks.DrawPixels := ProbeDrawPixels;
  Assert.IsTrue(PluginRegisterSaver(cOwner, 'test.px', 'Px', cSaverModePixels, @Callbacks, nil));
  GSaverPixelHost := True;
  GSaverId := 'test.px';
  Saver := TScreenSaver.Create(nil);
  try
    Saver.Start;
    Grid := NewGrid(300, 100);
    Saver.Draw(Grid, 300, 100);
    Assert.IsTrue(Saver.PixelFrame(W, H, Pixels, Gen));
    Assert.IsTrue(W <= cSaverPixelMaxW, 'width capped');
    Assert.IsTrue(H <= cSaverPixelMaxH, 'height capped');
    Assert.AreEqual(Int64(W), GProbe.PixelW);
    Assert.AreEqual(Int64(H), GProbe.PixelH);
    Assert.IsTrue(Abs(W / H - (300 * cSaverPixelCellW) / (100 * cSaverPixelCellH)) < 0.02,
      'the cap keeps the proportions');
  finally
    Saver.Free;
  end;
end;

procedure TTestPixelSaver.FailedPixelDrawLeavesABlackScreen;
var
  Callbacks: TSaverCallbacks;
  Saver: TScreenSaver;
  Grid: TTerminalGrid;
  W, H: Integer;
  Pixels: PByte;
  Gen: Cardinal;
begin
  Callbacks := ProbeCallbacks;
  Callbacks.DrawPixels := ProbeDrawPixels;
  GProbe.PixelResult := -1;
  Assert.IsTrue(PluginRegisterSaver(cOwner, 'test.mixed', 'Mixed',
    cSaverModeText or cSaverModePixels, @Callbacks, nil));
  GSaverPixelHost := True;
  GSaverId := 'test.mixed';
  Saver := TScreenSaver.Create(nil);
  try
    Saver.Start;
    Grid := NewGrid(4, 2);
    Saver.Draw(Grid, 4, 2);
    Assert.IsFalse(Saver.PixelFrame(W, H, Pixels, Gen), 'no bitmap from a failed picture');
    Assert.AreEqual(' ', string(Grid[0][0].CharValue), 'a black screen, not half a picture');
    Saver.Draw(Grid, 4, 2);
    Assert.AreEqual(1, GProbe.PixelDraws, 'a failed picture is not asked again');
  finally
    Saver.Free;
  end;
end;

procedure TTestPixelSaver.RegistrationNeedsTheCallbackOfEachMode;
var
  Callbacks: TSaverCallbacks;
begin
  Callbacks := ProbeCallbacks;
  Assert.IsFalse(PluginRegisterSaver(cOwner, 'test.nopx', 'x', cSaverModePixels, @Callbacks, nil),
    'pixel mode without DrawPixels');
  Assert.IsFalse(PluginRegisterSaver(cOwner, 'test.nopx2', 'x',
    cSaverModeText or cSaverModePixels, @Callbacks, nil), 'text and pixels, but no DrawPixels');
  Callbacks.DrawPixels := ProbeDrawPixels;
  Callbacks.Draw := nil;
  Assert.IsFalse(PluginRegisterSaver(cOwner, 'test.notext', 'x', cSaverModeText, @Callbacks, nil),
    'text mode without Draw');
end;

{ TTestSaverModules }

procedure TTestSaverModules.InfoGivesIdNameAndTick;
var
  Info: TSaverModuleInfo;
begin
  Assert.IsTrue(ParseSaverInfo('{"id":"stars","name":"Starfield","tickMs":50,"modes":["text"]}', Info));
  Assert.AreEqual('stars', Info.Id);
  Assert.AreEqual('Starfield', Info.Name);
  Assert.AreEqual(50, Info.TickMs);
  Assert.AreEqual(Int64(cSaverModeText), Info.Modes);
end;

procedure TTestSaverModules.InfoWithoutIdIsRefused;
var
  Info: TSaverModuleInfo;
begin
  Assert.IsFalse(ParseSaverInfo('{"name":"x"}', Info));
  Assert.IsFalse(ParseSaverInfo('{"id":"  "}', Info));
  Assert.IsFalse(ParseSaverInfo('not json', Info));
  Assert.IsFalse(ParseSaverInfo('[1]', Info));
end;

procedure TTestSaverModules.TickIsKeptWithinLimits;
var
  Info: TSaverModuleInfo;
begin
  Assert.IsTrue(ParseSaverInfo('{"id":"a","tickMs":1}', Info));
  Assert.AreEqual(10, Info.TickMs);
  Assert.IsTrue(ParseSaverInfo('{"id":"a","tickMs":99999}', Info));
  Assert.AreEqual(1000, Info.TickMs);
  Assert.IsTrue(ParseSaverInfo('{"id":"a"}', Info));
  Assert.AreEqual(90, Info.TickMs, 'no value: the default');
end;

procedure TTestSaverModules.ModesDefaultToText;
var
  Info: TSaverModuleInfo;
begin
  Assert.IsTrue(ParseSaverInfo('{"id":"a"}', Info));
  Assert.AreEqual(Int64(cSaverModeText), Info.Modes);
end;

procedure TTestSaverModules.PixelsModeIsKnown;
var
  Info: TSaverModuleInfo;
begin
  Assert.IsTrue(ParseSaverInfo('{"id":"a","modes":["pixels"]}', Info));
  Assert.AreEqual(Int64(cSaverModePixels), Info.Modes);
  Assert.IsTrue(ParseSaverInfo('{"id":"a","modes":["text","pixels"]}', Info));
  Assert.AreEqual(Int64(cSaverModeText or cSaverModePixels), Info.Modes);
end;

procedure TTestSaverModules.UnknownModesAreRefused;
var
  Info: TSaverModuleInfo;
begin
  Assert.IsFalse(ParseSaverInfo('{"id":"a","modes":["hologram"]}', Info));
  Assert.IsFalse(ParseSaverInfo('{"id":"a","modes":[]}', Info));
end;

{ TTestSaverSettings }

procedure TTestSaverSettings.Setup;
begin
  FSavedId := GSaverId;
  FSavedMinutes := GSaverMinutes;
  FSavedRandom := GSaverRandom;
  RegisterFake('test.set.a', cOwner);
  RegisterFake('test.set.b', cOwner);
end;

procedure TTestSaverSettings.TearDown;
begin
  UnregisterSavers(cOwner);
  GSaverId := FSavedId;
  GSaverMinutes := FSavedMinutes;
  GSaverRandom := FSavedRandom;
end;

function TTestSaverSettings.ReadJson: TJSONObject;
var
  Buf: array[0..8191] of AnsiChar;
  Len: Int64;
begin
  Len := PluginSaverSettingsJson(@Buf[0], SizeOf(Buf));
  Assert.IsTrue(Len > 0, 'JSON written');
  Result := TJSONObject.ParseJSONValue(UTF8ToString(UTF8String(PAnsiChar(@Buf[0])))) as TJSONObject;
  Assert.IsNotNull(Result);
end;

procedure TTestSaverSettings.ChoiceListsThePicturesAndTheCurrentValues;
var
  Root: TJSONObject;
  List: TJSONArray;
  I: Integer;
  Found: Boolean;
begin
  GSaverId := 'test.set.b';
  GSaverMinutes := cSaverMinuteChoices[1];
  Root := ReadJson;
  try
    Assert.AreEqual('test.set.b', Root.GetValue('saverId').Value);
    Assert.AreEqual(IntToStr(cSaverMinuteChoices[1]), Root.GetValue('minutes').Value);
    Assert.AreEqual<Integer>(Length(cSaverMinuteChoices),
      (Root.GetValue('minuteChoices') as TJSONArray).Count);
    List := Root.GetValue('savers') as TJSONArray;
    Found := False;
    for I := 0 to List.Count - 1 do
      if (List.Items[I] as TJSONObject).GetValue('id').Value = 'test.set.a' then
        Found := True;
    Assert.IsTrue(Found, 'registered picture listed');
  finally
    Root.Free;
  end;
end;

procedure TTestSaverSettings.SmallBufferIsReported;
var
  Buf: array[0..7] of AnsiChar;
begin
  Assert.AreEqual<Int64>(-2, PluginSaverSettingsJson(@Buf[0], SizeOf(Buf)));
  Assert.AreEqual<Int64>(-2, PluginSaverSettingsJson(nil, 0));
end;

procedure TTestSaverSettings.ValidChoiceIsApplied;
begin
  GSaverId := 'test.set.a';
  GSaverMinutes := 0;
  Assert.AreEqual<Int64>(0,
    PluginSaverApplySettings('TEST.SET.B', cSaverMinuteChoices[High(cSaverMinuteChoices)], -1));
  Assert.AreEqual('test.set.b', GSaverId, 'the registered spelling of the id');
  Assert.AreEqual(cSaverMinuteChoices[High(cSaverMinuteChoices)], GSaverMinutes);
end;

procedure TTestSaverSettings.UnknownPictureChangesNothing;
begin
  GSaverId := 'test.set.a';
  GSaverMinutes := 0;
  Assert.AreEqual<Int64>(-1, PluginSaverApplySettings('no.such', cSaverMinuteChoices[1], 1));
  Assert.AreEqual('test.set.a', GSaverId);
  Assert.AreEqual(0, GSaverMinutes, 'minutes untouched when the picture is refused');
end;

procedure TTestSaverSettings.UnknownMinutesChangesNothing;
begin
  GSaverId := 'test.set.a';
  GSaverMinutes := 0;
  Assert.AreEqual<Int64>(-1, PluginSaverApplySettings('test.set.b', 7777, 1));
  Assert.AreEqual('test.set.a', GSaverId, 'picture untouched when the minutes are refused');
  Assert.AreEqual(0, GSaverMinutes);
end;

procedure TTestSaverSettings.EmptyIdAndNegativeMinutesKeepTheCurrentValues;
begin
  GSaverId := 'test.set.a';
  GSaverMinutes := cSaverMinuteChoices[1];
  Assert.AreEqual<Int64>(0, PluginSaverApplySettings(nil, -1, -1));
  Assert.AreEqual<Int64>(0, PluginSaverApplySettings('', -1, -1));
  Assert.AreEqual('test.set.a', GSaverId);
  Assert.AreEqual(cSaverMinuteChoices[1], GSaverMinutes);
end;

procedure TTestSaverSettings.RandomFlagIsReadAndSetAndKeptWithMinusOne;
var
  Root: TJSONObject;
begin
  GSaverRandom := False;
  Assert.AreEqual<Int64>(0, PluginSaverApplySettings(nil, -1, 1));
  Assert.IsTrue(GSaverRandom);
  Root := ReadJson;
  try
    Assert.AreEqual('true', Root.GetValue('random').Value);
  finally
    Root.Free;
  end;
  Assert.AreEqual<Int64>(0, PluginSaverApplySettings(nil, -1, -1));
  Assert.IsTrue(GSaverRandom, 'kept');
  Assert.AreEqual<Int64>(0, PluginSaverApplySettings(nil, -1, 0));
  Assert.IsFalse(GSaverRandom);
end;

procedure TTestSaverSettings.RandomStartPicksAUsablePicture;
var
  I: Integer;
  Id: string;
  Info: TSaverInfo;
begin
  for I := 1 to 30 do
  begin
    Id := RandomUsableSaverId;
    Assert.IsTrue(FindSaver(Id, Info), 'a registered picture: ' + Id);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestScreenSaverRegistry);
  TDUnitX.RegisterTestFixture(TTestPluginSaver);
  TDUnitX.RegisterTestFixture(TTestPixelSaver);
  TDUnitX.RegisterTestFixture(TTestSaverModules);
  TDUnitX.RegisterTestFixture(TTestSaverSettings);

end.
