unit uScreenSaver;

{ Screensaver of the text window: the idle timer, the wake-up rules and the
  registry of the pictures it can show.

  A picture (ISaverEffect) is registered by id: the built-in sharks, or one a
  plugin hands over (uPluginSaver). The window owns one TScreenSaver; it starts
  after the configured idle time (GSaverMinutes, 0 = never) or when the
  right-most cell of the menu bar is clicked, covers the window with the
  chosen picture (GSaverId) and stops with the next key press or mouse action,
  which it uses up. With no picture registered the saver never starts.

  A picture draws into the character grid, so it works the same in every host.
  A picture may also have a pixel mode (ISaverPixelEffect): a host that can
  show a bitmap over the grid (GSaverPixelHost) then gets a BGRA frame of the
  window from it (TScreenSaver.PixelFrame) instead of the characters; the text
  terminal never does, so a picture with only the pixel mode is not offered
  there.
  Main thread only. }

interface

uses
  System.SysUtils, System.Generics.Collections, uTerminalTypes;

const
  cSaverIdleCheckMs = 1000;
  cSaverMoveGraceMs = 1500;
  cSaverMinuteChoices: array[0..6] of Integer = (0, 1, 2, 5, 10, 15, 30);
  /// <summary>The picture used when the chosen one is not registered.</summary>
  cDefaultSaverId = 'sharks';
  /// <summary>Bits of TSaverInfo.Modes.</summary>
  cSaverText = 1;
  cSaverPixels = 2;
  /// <summary>Pixels a frame has per window cell, before the size cap.</summary>
  cSaverPixelCellW = 8;
  cSaverPixelCellH = 16;
  cSaverPixelMaxW = 1280;
  cSaverPixelMaxH = 800;

type
  /// <summary>One picture of the saver. The controller creates it when the saver
  /// starts and drops it when the saver stops.</summary>
  ISaverEffect = interface
    ['{6B1C7A52-3E0D-4E9B-9C55-0B7C2A41D8F3}']
    /// <summary>Milliseconds between Advance calls while the saver runs.</summary>
    function TickMs: Integer;
    /// <summary>The saver starts; the window size is not known yet.</summary>
    procedure Prepare;
    procedure Advance(ASeconds: Double);
    /// <summary>Paints a frame onto AGrid (ACols x ARows cells).</summary>
    procedure Draw(const AGrid: TTerminalGrid; ACols, ARows: Integer);
    /// <summary>The saver stops; the picture is dropped right after.</summary>
    procedure Finish;
  end;

  /// <summary>The pixel mode of a picture; an ISaverEffect that also has it
  /// implements this too.</summary>
  ISaverPixelEffect = interface
    ['{2D8E4F61-9A37-4C1B-8E52-6F0A3B7D9C14}']
    /// <summary>Fills AWidth x AHeight BGRA pixels; APixels points to a buffer
    /// the picture owns, valid until the next call. False when it has no pixel
    /// frame now (the characters are drawn instead).</summary>
    function DrawPixels(AWidth, AHeight: Integer; out APixels: PByte): Boolean;
  end;

  TSaverEffectFactory = reference to function: ISaverEffect;

  TSaverInfo = record
    Id: string;
    Caption: string;
    /// <summary>cSaverText / cSaverPixels bits.</summary>
    Modes: Integer;
    /// <summary>The plugin that registered it; '' for a built-in picture.</summary>
    OwnerId: string;
  end;

var
  /// <summary>Idle minutes before the saver starts; 0 = not by itself.
  /// Options > User interface; persisted in session.json (saverMinutes).</summary>
  GSaverMinutes: Integer = 5;
  /// <summary>Id of the chosen picture; persisted in session.json (saverId).</summary>
  GSaverId: string = cDefaultSaverId;
  /// <summary>True: every start shows a randomly chosen picture of the usable
  /// ones instead of GSaverId; persisted in session.json (saverRandom).</summary>
  GSaverRandom: Boolean = False;
  /// <summary>True in a host that shows a bitmap over the grid (set by its
  /// overlay renderer); pictures with only the pixel mode are listed and used
  /// only then.</summary>
  GSaverPixelHost: Boolean = False;

/// <summary>Registers (or replaces) the picture AId. False for an empty id, a
/// missing factory or no mode.</summary>
function RegisterSaver(const AId, ACaption, AOwnerId: string;
  const AFactory: TSaverEffectFactory; AModes: Integer = cSaverText): Boolean;
/// <summary>Removes the pictures of AOwnerId; a running saver showing one of
/// them stops first.</summary>
procedure UnregisterSavers(const AOwnerId: string);
/// <summary>The registered pictures this host can show, in registration order.</summary>
function RegisteredSavers: TArray<TSaverInfo>;
function FindSaver(const AId: string; out AInfo: TSaverInfo): Boolean;
/// <summary>A new picture for AId, or for the default id, or for the first
/// registered one when AId is unknown; nil when nothing is registered.</summary>
function CreateSaverEffect(const AId: string; out AOwnerId: string): ISaverEffect;

/// <summary>The id of a randomly chosen picture that this host can show; ''
/// when there is none.</summary>
function RandomUsableSaverId: string;

/// <summary>True when the idle time has run out: the saver is on
/// (AMinutes > 0) and AIdleMs reached AMinutes.</summary>
function SaverIdleDue(AMinutes: Integer; AIdleMs: UInt64): Boolean;

type
  TScreenSaver = class
  private
    FEffect: ISaverEffect;
    FOwnerId: string;
    FActive: Boolean;
    FOnChanged: TProc;
    FTimer: TObject;
    FLastInputMs, FStartedMs: UInt64;
    FFrameValid: Boolean;
    FFrameW, FFrameH: Integer;
    FFramePixels: PByte;
    FFrameGen: Cardinal;
    procedure TimerTick(Sender: TObject);
    procedure SaversRemoved(const AOwnerId: string);
    procedure SetTimerInterval(AMs: Integer);
  public
    /// <summary>AOnChanged: repaint request (start, stop, every frame).</summary>
    constructor Create(const AOnChanged: TProc);
    destructor Destroy; override;
    /// <summary>User input of any kind: the idle time starts again.</summary>
    procedure Poke;
    /// <summary>User input while the saver runs: it stops. True when it was
    /// running, so the input is used up.</summary>
    function Wake: Boolean;
    /// <summary>Mouse movement: stops the saver too, but not in the first
    /// moments after it started, when the pointer that clicked to start it
    /// still settles.</summary>
    function WakeByMove: Boolean;
    procedure Start;
    procedure Stop;
    procedure Toggle;
    /// <summary>Paints a frame onto AGrid (AWidth x AHeight cells); nothing
    /// while stopped.</summary>
    procedure Draw(const AGrid: TTerminalGrid; AWidth, AHeight: Integer);
    /// <summary>True when the last Draw made a pixel frame instead of
    /// characters: AGen changes with every new frame; the host shows the
    /// bitmap over the whole window.</summary>
    function PixelFrame(out AWidth, AHeight: Integer; out APixels: PByte;
      out AGen: Cardinal): Boolean;
    property Active: Boolean read FActive;
  end;

implementation

uses
  System.Math, System.UITypes, uCoreTimer, uPlatformInfo;

type
  TSaverEntry = record
    Info: TSaverInfo;
    Factory: TSaverEffectFactory;
  end;

var
  GEntries: TList<TSaverEntry>;
  GSavers: TList<TScreenSaver>;

function IndexOfSaver(const AId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to GEntries.Count - 1 do
    if SameText(GEntries[I].Info.Id, AId) then
      Exit(I);
  Result := -1;
end;

function ModesUsable(AModes: Integer): Boolean;
begin
  Result := (AModes and cSaverText <> 0) or (GSaverPixelHost and (AModes and cSaverPixels <> 0));
end;

function IndexOfUsableSaver(const AId: string): Integer;
begin
  Result := IndexOfSaver(AId);
  if (Result >= 0) and not ModesUsable(GEntries[Result].Info.Modes) then
    Result := -1;
end;

function RegisterSaver(const AId, ACaption, AOwnerId: string;
  const AFactory: TSaverEffectFactory; AModes: Integer): Boolean;
var
  Entry: TSaverEntry;
  Idx: Integer;
begin
  Result := (Trim(AId) <> '') and Assigned(AFactory) and (AModes and (cSaverText or cSaverPixels) <> 0);
  if not Result then
    Exit;
  Entry.Info.Modes := AModes and (cSaverText or cSaverPixels);
  Entry.Info.Id := Trim(AId);
  Entry.Info.Caption := ACaption;
  Entry.Info.OwnerId := AOwnerId;
  Entry.Factory := AFactory;
  Idx := IndexOfSaver(Entry.Info.Id);
  if Idx >= 0 then
    GEntries[Idx] := Entry
  else
    GEntries.Add(Entry);
end;

procedure UnregisterSavers(const AOwnerId: string);
var
  I: Integer;
  Saver: TScreenSaver;
begin
  if AOwnerId = '' then
    Exit;
  // A running saver lets go of its picture before the owner's code goes away.
  for Saver in GSavers.ToArray do
    Saver.SaversRemoved(AOwnerId);
  for I := GEntries.Count - 1 downto 0 do
    if SameText(GEntries[I].Info.OwnerId, AOwnerId) then
      GEntries.Delete(I);
end;

function RegisteredSavers: TArray<TSaverInfo>;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to GEntries.Count - 1 do
    if ModesUsable(GEntries[I].Info.Modes) then
      Result := Result + [GEntries[I].Info];
end;

function FindSaver(const AId: string; out AInfo: TSaverInfo): Boolean;
var
  Idx: Integer;
begin
  Idx := IndexOfSaver(AId);
  Result := Idx >= 0;
  if Result then
    AInfo := GEntries[Idx].Info;
end;

function CreateSaverEffect(const AId: string; out AOwnerId: string): ISaverEffect;
var
  Idx: Integer;
begin
  AOwnerId := '';
  Idx := IndexOfUsableSaver(AId);
  if Idx < 0 then
    Idx := IndexOfUsableSaver(cDefaultSaverId);
  if Idx < 0 then
  begin
    Idx := 0;
    while (Idx < GEntries.Count) and not ModesUsable(GEntries[Idx].Info.Modes) do
      Inc(Idx);
    if Idx >= GEntries.Count then
      Idx := -1;
  end;
  if Idx < 0 then
    Exit(nil);
  AOwnerId := GEntries[Idx].Info.OwnerId;
  Result := GEntries[Idx].Factory();
end;

function RandomUsableSaverId: string;
var
  Infos: TArray<TSaverInfo>;
begin
  Infos := RegisteredSavers;
  if Length(Infos) = 0 then
    Exit('');
  Result := Infos[Random(Length(Infos))].Id;
end;

function SaverIdleDue(AMinutes: Integer; AIdleMs: UInt64): Boolean;
begin
  Result := (AMinutes > 0) and (AIdleMs >= UInt64(AMinutes) * 60000);
end;

{ TScreenSaver }

constructor TScreenSaver.Create(const AOnChanged: TProc);
begin
  inherited Create;
  FOnChanged := AOnChanged;
  FLastInputMs := PlatformTickCount64;
  FTimer := TCoreTimer.Create(nil);
  TCoreTimer(FTimer).Interval := cSaverIdleCheckMs;
  TCoreTimer(FTimer).OnTimer := TimerTick;
  TCoreTimer(FTimer).Enabled := True;
  GSavers.Add(Self);
end;

destructor TScreenSaver.Destroy;
begin
  GSavers.Remove(Self);
  FreeAndNil(FTimer);
  if FActive then
  begin
    FActive := False;
    FEffect.Finish;
  end;
  FEffect := nil;
  inherited Destroy;
end;

procedure TScreenSaver.SetTimerInterval(AMs: Integer);
begin
  TCoreTimer(FTimer).Interval := AMs;
end;

procedure TScreenSaver.TimerTick(Sender: TObject);
begin
  if FActive then
  begin
    FEffect.Advance(FEffect.TickMs / 1000);
    if Assigned(FOnChanged) then
      FOnChanged();
  end
  else if SaverIdleDue(GSaverMinutes, PlatformTickCount64 - FLastInputMs) then
    Start;
end;

procedure TScreenSaver.SaversRemoved(const AOwnerId: string);
begin
  if FActive and SameText(FOwnerId, AOwnerId) then
    Stop;
end;

procedure TScreenSaver.Poke;
begin
  FLastInputMs := PlatformTickCount64;
end;

function TScreenSaver.Wake: Boolean;
begin
  Poke;
  Result := FActive;
  if Result then
    Stop;
end;

function TScreenSaver.WakeByMove: Boolean;
begin
  if FActive and (PlatformTickCount64 - FStartedMs < cSaverMoveGraceMs) then
  begin
    Poke;
    Exit(True);
  end;
  Result := Wake;
end;

procedure TScreenSaver.Start;
var
  Effect: ISaverEffect;
begin
  if FActive then
    Exit;
  if GSaverRandom then
    Effect := CreateSaverEffect(RandomUsableSaverId, FOwnerId)
  else
    Effect := CreateSaverEffect(GSaverId, FOwnerId);
  if Effect = nil then
  begin
    // Nothing to show: wait a full idle time before trying again.
    Poke;
    Exit;
  end;
  FEffect := Effect;
  FActive := True;
  FStartedMs := PlatformTickCount64;
  FEffect.Prepare;
  SetTimerInterval(FEffect.TickMs);
  if Assigned(FOnChanged) then
    FOnChanged();
end;

procedure TScreenSaver.Stop;
var
  Effect: ISaverEffect;
begin
  if not FActive then
    Exit;
  FActive := False;
  Effect := FEffect;
  FEffect := nil;
  Effect.Finish;
  Poke;
  SetTimerInterval(cSaverIdleCheckMs);
  if Assigned(FOnChanged) then
    FOnChanged();
end;

procedure TScreenSaver.Toggle;
begin
  if FActive then
    Stop
  else
    Start;
end;

procedure TScreenSaver.Draw(const AGrid: TTerminalGrid; AWidth, AHeight: Integer);
var
  PixelEffect: ISaverPixelEffect;
  PW, PH, X, Y: Integer;
  Pixels: PByte;
begin
  FFrameValid := False;
  if not (FActive and (AWidth > 0) and (AHeight > 0)) then
    Exit;
  if GSaverPixelHost and Supports(FEffect, ISaverPixelEffect, PixelEffect) then
  begin
    PW := AWidth * cSaverPixelCellW;
    PH := AHeight * cSaverPixelCellH;
    while (PW > cSaverPixelMaxW) or (PH > cSaverPixelMaxH) do
    begin
      PW := PW div 2;
      PH := PH div 2;
    end;
    if (PW > 0) and (PH > 0) and PixelEffect.DrawPixels(PW, PH, Pixels) then
    begin
      FFrameValid := True;
      FFrameW := PW;
      FFrameH := PH;
      FFramePixels := Pixels;
      Inc(FFrameGen);
      // The bitmap covers the window; the characters under it are black.
      for Y := 0 to Min(AHeight, Length(AGrid)) - 1 do
        for X := 0 to Min(AWidth, Length(AGrid[Y])) - 1 do
          AGrid[Y][X] := TCharCell.Make(' ', TAlphaColor($FFFFFFFF), TAlphaColor($FF000000));
      Exit;
    end;
  end;
  FEffect.Draw(AGrid, AWidth, AHeight);
end;

function TScreenSaver.PixelFrame(out AWidth, AHeight: Integer; out APixels: PByte;
  out AGen: Cardinal): Boolean;
begin
  Result := FActive and FFrameValid;
  if Result then
  begin
    AWidth := FFrameW;
    AHeight := FFrameH;
    APixels := FFramePixels;
    AGen := FFrameGen;
  end;
end;

initialization
  GEntries := TList<TSaverEntry>.Create;
  GSavers := TList<TScreenSaver>.Create;

finalization
  FreeAndNil(GSavers);
  FreeAndNil(GEntries);

end.
