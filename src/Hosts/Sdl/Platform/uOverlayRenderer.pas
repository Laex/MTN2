unit uOverlayRenderer;

{ Picture preview of the SDL host. The picture is kept as pixels and handed to
  the host window (OverlayFrame), which scales it over the cells of the preview
  area (uOverlayModel holds the state). Local picture files are decoded by SDL
  (uSdlImage); a window that already holds the pixels passes them with
  SetOverlayPixels. Until the picture is ready the area stays as the window
  drew it; when it cannot be decoded the area shows a hint in its cells. The
  text-terminal build lives in Platform\Posix and the FireMonkey build in
  Platform\Windows; a project names exactly one of the three units. }

interface

uses
  System.Classes, System.Types, uThemeTypes, uTerminalTypes, uOverlayModel;

const
  cOverlayMaxBytes = uOverlayModel.cOverlayMaxBytes;

procedure RequestOverlayPreview(const AURI: string; const ABounds: TRectI); overload;
procedure RequestOverlayPreview(const AURI: string; const ABounds, AClip: TRectI;
  AImageScale: Single = 0); overload;
procedure UpdateOverlayBounds(const ABounds: TRectI); overload;
procedure UpdateOverlayBounds(const ABounds, AClip: TRectI; AImageScale: Single = 0); overload;
procedure SetOverlayPixelArea(const ARect: TRectF);
procedure ClearOverlayPixelArea;
procedure SetOverlayPixels(const AURI: string; AWidth, AHeight: Integer; APixels: PByte;
  const ABounds, AClip: TRectI);
procedure ClearOverlayPreview;
function OverlayActive: Boolean;
/// <summary>URI of the current preview request; '' if none.</summary>
function OverlayCurrentURI: string;
procedure SetOverlayRepaintHandler(AHandler: TThreadProcedure);
/// <summary>The host reports the size of a cell in pixels; True when it changed.</summary>
function SetOverlayCellMetrics(ACellWidth, ACellHeight: Single;
  APixelScale: Single = 1): Boolean;
/// <summary>Cell height / cell width; 2.0 until the host reports.</summary>
function OverlayCellAspect: Single;
/// <summary>False until the host reports the cell size.</summary>
function OverlayNativeCellSize(AImageW, AImageH: Integer; out ACols, ARows: Integer): Boolean;
/// <summary>Starts what the preview needs and writes hints into AGrid; the
/// picture stays in OverlayFrame until ClearOverlayPreview.</summary>
procedure PaintOverlayCells(var AGrid: TTerminalGrid);
/// <summary>The picture of the grid composed by the last PaintOverlayCells.</summary>
function OverlayFrame: TOverlayFrame;

implementation

uses
  System.SysUtils, uSdlImage, uScreenSaver;

var
  GModel: TOverlayModel;

function DecodeWithSdl(const APath: string; out AWidth, AHeight: Integer;
  out APixels: TBytes): TPictureState;
begin
  case DecodePictureFile(APath, AWidth, AHeight, APixels) of
    pdOk: Result := psReady;
    pdNoDecoder: Result := psNoDecoder;
  else
    Result := psFailed;
  end;
end;

procedure RequestOverlayPreview(const AURI: string; const ABounds: TRectI);
begin
  GModel.Request(AURI, ABounds, ABounds, 0);
end;

procedure RequestOverlayPreview(const AURI: string; const ABounds, AClip: TRectI;
  AImageScale: Single);
begin
  GModel.Request(AURI, ABounds, AClip, AImageScale);
end;

procedure UpdateOverlayBounds(const ABounds: TRectI);
begin
  GModel.UpdateBounds(ABounds, ABounds, 0);
end;

procedure UpdateOverlayBounds(const ABounds, AClip: TRectI; AImageScale: Single);
begin
  GModel.UpdateBounds(ABounds, AClip, AImageScale);
end;

procedure SetOverlayPixelArea(const ARect: TRectF);
begin
end;

procedure ClearOverlayPixelArea;
begin
end;

procedure SetOverlayPixels(const AURI: string; AWidth, AHeight: Integer; APixels: PByte;
  const ABounds, AClip: TRectI);
begin
  GModel.SetPixels(AURI, AWidth, AHeight, APixels, ABounds, AClip);
end;

procedure ClearOverlayPreview;
begin
  GModel.Clear;
end;

function OverlayActive: Boolean;
begin
  Result := GModel.Active;
end;

function OverlayCurrentURI: string;
begin
  Result := GModel.CurrentUri;
end;

procedure SetOverlayRepaintHandler(AHandler: TThreadProcedure);
begin
  GModel.SetRepaintHandler(AHandler);
end;

function SetOverlayCellMetrics(ACellWidth, ACellHeight: Single;
  APixelScale: Single): Boolean;
begin
  Result := GModel.SetCellMetrics(ACellWidth, ACellHeight, APixelScale);
end;

function OverlayCellAspect: Single;
begin
  Result := GModel.CellAspect;
end;

function OverlayNativeCellSize(AImageW, AImageH: Integer; out ACols, ARows: Integer): Boolean;
begin
  Result := GModel.NativeCellSize(AImageW, AImageH, ACols, ARows);
end;

procedure PaintOverlayCells(var AGrid: TTerminalGrid);
begin
  GModel.PaintCells(AGrid);
end;

function OverlayFrame: TOverlayFrame;
begin
  Result := GModel.Frame;
end;

initialization
  GModel := TOverlayModel.Create(DecodeWithSdl);
  GSaverPixelHost := True;

finalization
  GModel.Free;

end.
