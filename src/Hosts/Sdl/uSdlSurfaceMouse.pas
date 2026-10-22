unit uSdlSurfaceMouse;

{ Mouse input of the picture tabs a plugin opens (uPluginSurface) in the SDL
  window: a button, the wheel or a drag over the area of a tab goes to the
  plugin instead of the panels, in pixels from the top left corner of the area,
  and the plugin learns the size of its area so it can draw a picture to fit.
  Where the area is and which tabs are on screen comes from the host, so the
  class knows nothing about the shell. A press the plugin does not use goes on
  to the panels; once a plugin has taken a press it also gets the moves and
  the release. }

interface

uses
  System.Types, System.SysUtils, uSdlApi;

type
  /// <summary>The tabs of plugin pictures that are on screen.</summary>
  TSurfaceHandles = reference to function: TArray<Integer>;

  /// <summary>The area of a tab in pixels of the drawn bitmap; False when it is not shown.</summary>
  TSurfaceArea = reference to function(AHandle: Integer; out AArea: TRect): Boolean;

  TSdlSurfaceMouse = class
  strict private
    FHandles: TSurfaceHandles;
    FArea: TSurfaceArea;
    FScale: Single;
    FHeld: Integer;
    FX, FY: Integer;
    function Hit(AX, AY: Integer; out AHandle: Integer; out AArea: TRect): Boolean;
    function Deliver(AHandle: Integer; const AArea: TRect; AKind, AButton, AExtra,
      AShift: Integer): Boolean;
  public
    constructor Create(const AHandles: TSurfaceHandles; const AArea: TSurfaceArea);
    /// <summary>Window units are multiplied by this to get bitmap pixels.</summary>
    property Scale: Single read FScale write FScale;
    /// <summary>True when the plugin took the event; the panels then do not see it.</summary>
    function Handle(const E: TSDLEvent; AMods: Integer): Boolean;
    /// <summary>Tells every plugin on screen how big its area is (a plugin hears of a
    /// change only). Called after each composed frame; the plugin answers with a new picture.</summary>
    procedure ReportSizes;
  end;

/// <summary>SDL button (1 left, 2 middle, 3 right) as the plugin ABI names it (1 left, 2 right, 3 middle).</summary>
function SdlButtonToSurface(AButton: Integer): Integer;

/// <summary>Shift, Ctrl and Alt of an SDL modifier mask as the plugin ABI bit set (1, 2, 4).</summary>
function SdlModsToSurfaceBits(AMods: Integer): Integer;

implementation

uses
  System.Classes, System.Math, uPluginSurface;

const
  cKindDown = 0;
  cKindUp = 1;
  cKindMove = 2;
  cKindWheel = 3;
  cKindDouble = 4;

function SdlButtonToSurface(AButton: Integer): Integer;
begin
  case AButton of
    SDL_BUTTON_RIGHT: Result := 2;
    SDL_BUTTON_MIDDLE: Result := 3;
  else
    Result := 1;
  end;
end;

function SdlModsToSurfaceBits(AMods: Integer): Integer;
begin
  Result := 0;
  if (AMods and (KMOD_LSHIFT or KMOD_RSHIFT)) <> 0 then
    Result := Result or 1;
  if (AMods and (KMOD_LCTRL or KMOD_RCTRL)) <> 0 then
    Result := Result or 2;
  if (AMods and (KMOD_LALT or KMOD_RALT)) <> 0 then
    Result := Result or 4;
end;

constructor TSdlSurfaceMouse.Create(const AHandles: TSurfaceHandles; const AArea: TSurfaceArea);
begin
  inherited Create;
  FHandles := AHandles;
  FArea := AArea;
  FScale := 1;
end;

function TSdlSurfaceMouse.Hit(AX, AY: Integer; out AHandle: Integer; out AArea: TRect): Boolean;
var
  H: Integer;
  R: TRect;
begin
  Result := False;
  for H in FHandles() do
    if FArea(H, R) and R.Contains(Point(AX, AY)) then
    begin
      AHandle := H;
      AArea := R;
      Exit(True);
    end;
end;

function TSdlSurfaceMouse.Deliver(AHandle: Integer; const AArea: TRect; AKind, AButton, AExtra,
  AShift: Integer): Boolean;
begin
  Result := SurfaceDeliverMouse(AHandle, AKind, FX - AArea.Left, FY - AArea.Top, AArea.Width,
    AArea.Height, AButton, AExtra, AShift);
end;

function TSdlSurfaceMouse.Handle(const E: TSDLEvent; AMods: Integer): Boolean;
var
  H: Integer;
  Area: TRect;
  Kind: Cardinal;
  Shift, Button: Integer;
begin
  Result := False;
  Kind := SdlEventType(E);
  if (Kind <> SDL_MOUSEBUTTONDOWN) and (Kind <> SDL_MOUSEBUTTONUP) and
     (Kind <> SDL_MOUSEMOTION) and (Kind <> SDL_MOUSEWHEEL) then
    Exit;
  Shift := SdlModsToSurfaceBits(AMods);
  if Kind <> SDL_MOUSEWHEEL then
  begin
    FX := Round(SdlEventI32(E, 20) * FScale);
    FY := Round(SdlEventI32(E, 24) * FScale);
  end;
  case Kind of
    SDL_MOUSEBUTTONDOWN:
      begin
        if not Hit(FX, FY, H, Area) then
          Exit;
        Button := SdlButtonToSurface(SdlEventU8(E, 16));
        Result := Deliver(H, Area, IfThen(SdlEventU8(E, 18) >= 2, cKindDouble, cKindDown), Button,
          0, Shift);
        if Result then
          FHeld := H;
      end;
    SDL_MOUSEMOTION:
      begin
        if (FHeld = 0) or not FArea(FHeld, Area) then
        begin
          FHeld := 0;
          Exit;
        end;
        Deliver(FHeld, Area, cKindMove, 1, 0, Shift);
        Result := True;
      end;
    SDL_MOUSEBUTTONUP:
      begin
        if (FHeld = 0) or not FArea(FHeld, Area) then
        begin
          FHeld := 0;
          Exit;
        end;
        Button := SdlButtonToSurface(SdlEventU8(E, 16));
        Deliver(FHeld, Area, cKindUp, Button, 0, Shift);
        FHeld := 0;
        Result := True;
      end;
    SDL_MOUSEWHEEL:
      begin
        // The wheel event has no position: the last one seen is used.
        if (SdlEventI32(E, 20) = 0) or not Hit(FX, FY, H, Area) then
          Exit;
        Result := Deliver(H, Area, cKindWheel, 1, Sign(SdlEventI32(E, 20)), Shift);
      end;
  end;
end;

procedure TSdlSurfaceMouse.ReportSizes;
var
  H: Integer;
  Area: TRect;
begin
  // SurfaceReportSize passes on a size only when it changed.
  for H in FHandles() do
    if FArea(H, Area) and (Area.Width >= 1) and (Area.Height >= 1) then
      SurfaceReportSize(H, Area.Width, Area.Height);
end;

end.
