unit TestScreenSaver;

interface

uses
  DUnitX.TestFramework;

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
  TTestSaverModules = class
  public
    [Test] procedure InfoGivesIdNameAndTick;
    [Test] procedure InfoWithoutIdIsRefused;
    [Test] procedure TickIsKeptWithinLimits;
    [Test] procedure ModesDefaultToText;
    [Test] procedure ModesWithoutTextAreRefused;
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
    Prepares, Finishes, Draws: Integer;
    DrawResult: Int64;
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

function ProbeCallbacks: TSaverCallbacks;
begin
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

procedure TTestSaverModules.ModesWithoutTextAreRefused;
var
  Info: TSaverModuleInfo;
begin
  Assert.IsFalse(ParseSaverInfo('{"id":"a","modes":["pixels"]}', Info));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestScreenSaverRegistry);
  TDUnitX.RegisterTestFixture(TTestPluginSaver);
  TDUnitX.RegisterTestFixture(TTestSaverModules);

end.
