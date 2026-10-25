unit uSharkSaver;

{$I sharks.inc}

{ Screensaver: sharks swimming across a black screen. It starts after the
  configured idle time (GSaverMinutes, 0 = never) or when the right-most cell
  of the menu bar is clicked, covers the window with black, and stops with the
  next key press or mouse action, which it uses up.

  This is the only unit of the subsystem (folder ascii-sharks) the rest of the
  program uses. Without MTN_ASCII_SHARKS (see sharks.inc) the same names are
  here as an inert stand-in: the saver never starts and draws nothing, so no
  other unit needs to know whether the subsystem is built. }

interface

uses
  System.SysUtils, uTerminalTypes;

const
  /// <summary>The screensaver is part of this build.</summary>
{$IFDEF MTN_ASCII_SHARKS}
  SharksBuiltIn = True;
{$ELSE}
  SharksBuiltIn = False;
{$ENDIF}
  cSharkTickMs = 90;
  cSharkIdleCheckMs = 1000;
  cSharkMoveGraceMs = 1500;
  cSaverMinuteChoices: array[0..6] of Integer = (0, 1, 2, 5, 10, 15, 30);

type
  TSharkSaver = class
  private
    FImpl: TObject;
    FActive: Boolean;
    FOnChanged: TProc;
  public
    /// <summary>AOnChanged: repaint request (start, stop, every frame).</summary>
    constructor Create(const AOnChanged: TProc);
    destructor Destroy; override;
    /// <summary>User input of any kind: the idle time starts again.</summary>
    procedure Poke;
    /// <summary>User input while the sharks swim: they stop. True when they
    /// were swimming, so the input is used up.</summary>
    function Wake: Boolean;
    /// <summary>Mouse movement: stops the sharks too, but not in the first
    /// moments after they started, when the pointer that clicked to start
    /// them still settles.</summary>
    function WakeByMove: Boolean;
    procedure Start;
    procedure Stop;
    procedure Toggle;
    /// <summary>Paints a frame onto AGrid (AWidth x AHeight cells); nothing
    /// while stopped.</summary>
    procedure Draw(const AGrid: TTerminalGrid; AWidth, AHeight: Integer);
    property Active: Boolean read FActive;
  end;

var
  /// <summary>Idle minutes before the sharks start; 0 = not by itself.
  /// Options > User interface; persisted in session.json (saverMinutes).</summary>
  GSaverMinutes: Integer = 5;

/// <summary>True when the idle time has run out: the saver is on
/// (AMinutes > 0) and AIdleMs reached AMinutes.</summary>
function SaverIdleDue(AMinutes: Integer; AIdleMs: UInt64): Boolean;

implementation

{$IFDEF MTN_ASCII_SHARKS}

uses
  System.Math, uCoreTimer, uPlatformInfo, uSharkShapes, uSharkWorld, uSharkRender;

const
  cSimStep = 1 / 60;
  cMaxSteps = 8;

type
  /// <summary>The world, its renderer and the clocks of one running saver.</summary>
  TSharkEngine = class
  private
    FWorld: TSharkWorld;
    FRenderer: TSharkRenderer;
    FSeed: Cardinal;
    FAccumulator: Double;
    FCols, FRows: Integer;
    FTimer: TCoreTimer;
    FOnChanged: TProc;
    FOwner: TSharkSaver;
    FLastInputMs, FStartedMs: UInt64;
    procedure Layout(ACols, ARows: Integer);
    procedure TimerTick(Sender: TObject);
  public
    constructor Create(AOwner: TSharkSaver; const AOnChanged: TProc);
    destructor Destroy; override;
    procedure Prepare;
    procedure Finish;
    procedure Advance(ASeconds: Double);
    procedure Draw(const AGrid: TTerminalGrid; ACols, ARows: Integer);
    property LastInputMs: UInt64 read FLastInputMs write FLastInputMs;
    property StartedMs: UInt64 read FStartedMs;
  end;

function SharkSpecsFor(ACols: Integer; ARandom: Cardinal): TArray<TSharkSpec>;
const
  cSizes: array[0..3] of Double = (1, 0.7, 0.84, 0.77);
var
  Count, I, K: Integer;
  Kinds: array[0..cSharkKindCount - 1] of Integer;
  State: Cardinal;
begin
  Count := EnsureRange(ACols div 30, 2, 4);
  for I := 0 to High(Kinds) do
    Kinds[I] := I;
  // A different set of kinds every time, drawn without repeats.
  State := ARandom;
  SetLength(Result, Count);
  for I := 0 to Count - 1 do
  begin
    State := State * 1664525 + 1013904223;
    K := I + Integer((State shr 8) mod Cardinal(Length(Kinds) - I));
    Result[I].Kind := TSharkKind(Kinds[K]);
    Kinds[K] := Kinds[I];
    Result[I].Size := cSizes[I mod Length(cSizes)];
  end;
end;

{ TSharkEngine }

constructor TSharkEngine.Create(AOwner: TSharkSaver; const AOnChanged: TProc);
begin
  inherited Create;
  FOwner := AOwner;
  FOnChanged := AOnChanged;
  FRenderer := TSharkRenderer.Create;
  FSeed := Cardinal(PlatformTickCount64);
  FLastInputMs := PlatformTickCount64;
  FTimer := TCoreTimer.Create(nil);
  FTimer.Interval := cSharkIdleCheckMs;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

destructor TSharkEngine.Destroy;
begin
  FreeAndNil(FTimer);
  FreeAndNil(FWorld);
  FreeAndNil(FRenderer);
  inherited Destroy;
end;

procedure TSharkEngine.Prepare;
begin
  FStartedMs := PlatformTickCount64;
  // The window size is not known yet: the first frame lays the world out.
  FreeAndNil(FWorld);
  FCols := 0;
  FRows := 0;
  FAccumulator := 0;
  FTimer.Interval := cSharkTickMs;
end;

procedure TSharkEngine.Finish;
begin
  FreeAndNil(FWorld);
  FLastInputMs := PlatformTickCount64;
  FTimer.Interval := cSharkIdleCheckMs;
end;

procedure TSharkEngine.Layout(ACols, ARows: Integer);
begin
  FCols := ACols;
  FRows := ARows;
  FreeAndNil(FWorld);
  FSeed := FSeed * 1664525 + 1013904223;
  FWorld := TSharkWorld.Create(SharkSpecsFor(ACols, FSeed), FSeed);
  FWorld.Resize(ACols * cSharkCellWidth, ARows * cSharkCellHeight, cSharkCellWidth,
    cSharkCellHeight);
  FRenderer.Resize(ACols, ARows);
  FAccumulator := 0;
end;

procedure TSharkEngine.Advance(ASeconds: Double);
var
  Steps: Integer;
begin
  if FWorld = nil then
    Exit;
  FAccumulator := FAccumulator + Min(0.25, ASeconds);
  Steps := 0;
  while (FAccumulator >= cSimStep) and (Steps < cMaxSteps) do
  begin
    FWorld.Step(cSimStep);
    FAccumulator := FAccumulator - cSimStep;
    Inc(Steps);
  end;
  if Steps = cMaxSteps then
    FAccumulator := 0;
  FRenderer.Render(FWorld, ASeconds);
end;

procedure TSharkEngine.TimerTick(Sender: TObject);
begin
  if FOwner.Active then
  begin
    Advance(cSharkTickMs / 1000);
    if Assigned(FOnChanged) then
      FOnChanged();
  end
  else if SaverIdleDue(GSaverMinutes, PlatformTickCount64 - FLastInputMs) then
    FOwner.Start;
end;

procedure TSharkEngine.Draw(const AGrid: TTerminalGrid; ACols, ARows: Integer);
var
  I: Integer;
begin
  if (ACols < 1) or (ARows < 1) then
    Exit;
  if FWorld = nil then
  begin
    Layout(ACols, ARows);
    // Two seconds of swimming first, so the first frame is not the staging.
    for I := 1 to 120 do
      FWorld.Step(cSimStep);
    FRenderer.Render(FWorld, cSharkTickMs / 1000);
  end
  else if (ACols <> FCols) or (ARows <> FRows) then
  begin
    // The window was resized: the same fish and sharks swim on, the fish are
    // kept inside the new edges and the sharks turn back by themselves.
    FCols := ACols;
    FRows := ARows;
    FWorld.Resize(ACols * cSharkCellWidth, ARows * cSharkCellHeight, cSharkCellWidth,
      cSharkCellHeight);
    FRenderer.Resize(ACols, ARows);
    FRenderer.Render(FWorld, cSharkTickMs / 1000);
  end;
  FRenderer.Paint(AGrid, FWorld.Time);
end;

{$ENDIF}

function SaverIdleDue(AMinutes: Integer; AIdleMs: UInt64): Boolean;
begin
  Result := (AMinutes > 0) and (AIdleMs >= UInt64(AMinutes) * 60000);
end;

{ TSharkSaver }

{$IFDEF MTN_ASCII_SHARKS}

constructor TSharkSaver.Create(const AOnChanged: TProc);
begin
  inherited Create;
  FOnChanged := AOnChanged;
  FImpl := TSharkEngine.Create(Self, AOnChanged);
end;

destructor TSharkSaver.Destroy;
begin
  FreeAndNil(FImpl);
  inherited Destroy;
end;

procedure TSharkSaver.Poke;
begin
  TSharkEngine(FImpl).LastInputMs := PlatformTickCount64;
end;

function TSharkSaver.Wake: Boolean;
begin
  Poke;
  Result := FActive;
  if Result then
    Stop;
end;

function TSharkSaver.WakeByMove: Boolean;
begin
  if FActive and (PlatformTickCount64 - TSharkEngine(FImpl).StartedMs < cSharkMoveGraceMs) then
  begin
    Poke;
    Exit(True);
  end;
  Result := Wake;
end;

procedure TSharkSaver.Start;
begin
  if FActive then
    Exit;
  FActive := True;
  TSharkEngine(FImpl).Prepare;
  if Assigned(FOnChanged) then
    FOnChanged();
end;

procedure TSharkSaver.Stop;
begin
  if not FActive then
    Exit;
  FActive := False;
  TSharkEngine(FImpl).Finish;
  if Assigned(FOnChanged) then
    FOnChanged();
end;

procedure TSharkSaver.Toggle;
begin
  if FActive then
    Stop
  else
    Start;
end;

procedure TSharkSaver.Draw(const AGrid: TTerminalGrid; AWidth, AHeight: Integer);
begin
  if FActive then
    TSharkEngine(FImpl).Draw(AGrid, AWidth, AHeight);
end;

{$ELSE}

constructor TSharkSaver.Create(const AOnChanged: TProc);
begin
  inherited Create;
end;

destructor TSharkSaver.Destroy;
begin
  inherited Destroy;
end;

procedure TSharkSaver.Poke;
begin
end;

function TSharkSaver.Wake: Boolean;
begin
  Result := False;
end;

function TSharkSaver.WakeByMove: Boolean;
begin
  Result := False;
end;

procedure TSharkSaver.Start;
begin
end;

procedure TSharkSaver.Stop;
begin
end;

procedure TSharkSaver.Toggle;
begin
end;

procedure TSharkSaver.Draw(const AGrid: TTerminalGrid; AWidth, AHeight: Integer);
begin
end;

{$ENDIF}

end.
