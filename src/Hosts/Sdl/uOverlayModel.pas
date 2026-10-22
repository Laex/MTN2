unit uOverlayModel;

{ State of the picture preview of the SDL host: which picture the windows ask
  for, where, the decoded pixels, and the frame the host window lays over the
  grid. The windows reach it through the functions of the unit uOverlayRenderer
  of this host; the class is separate so it can be driven without them.
  A worker thread decodes a requested picture (the decoder is replaceable);
  a window that already holds the pixels passes them in directly. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.SyncObjs,
  uThemeTypes, uTerminalTypes;

const
  cOverlayMaxBytes = 32 * 1024 * 1024;

type
  /// <summary>The picture to lay over the grid of the frame just composed.</summary>
  TOverlayFrame = record
    Visible: Boolean;
    Width: Integer;
    Height: Integer;
    /// <summary>Bytes of the picture, 4 per pixel (blue, green, red, alpha); shared and never changed.</summary>
    Pixels: TBytes;
    /// <summary>Cell area the picture is fitted into, and the part of it that shows.</summary>
    Bounds: TRectI;
    Clip: TRectI;
    /// <summary>Device pixels per picture pixel from the top left; 0 fits and centers.</summary>
    ImageScale: Single;
    /// <summary>Changes whenever the pixels are replaced.</summary>
    Serial: Cardinal;
  end;

  TPictureState = (psNone, psLoading, psReady, psNoDecoder, psFailed);

  /// <summary>Reads a picture file: the state it ends in and, for psReady, its pixels.</summary>
  TPictureDecoder = reference to function(const APath: string; out AWidth, AHeight: Integer;
    out APixels: TBytes): TPictureState;

  TOverlayModel = class
  strict private
    FLock: TCriticalSection;
    FDecoder: TPictureDecoder;
    FAsync: Boolean;
    FUri: string;
    FBounds, FClip: TRectI;
    FScale: Single;
    FRepaint: TThreadProcedure;
    FPicUri: string;
    FPicState: TPictureState;
    FPicW, FPicH: Integer;
    FPicPixels: TBytes;
    FPicSerial: Cardinal;
    FFrame: TOverlayFrame;
    FCellW, FCellH: Single;
    procedure Store(const AUri: string; AState: TPictureState; AWidth, AHeight: Integer;
      const APixels: TBytes);
    procedure Decode(const AUri, APath: string);
    procedure DecodeStaged(const AUri, APath: string; ATemp: Boolean);
    procedure NotifyRepaint;
    procedure PutHint(var AGrid: TTerminalGrid; const ABounds: TRectI; const AText: string);
  public
    constructor Create(const ADecoder: TPictureDecoder; AAsync: Boolean = True);
    destructor Destroy; override;
    procedure Request(const AUri: string; const ABounds, AClip: TRectI; AScale: Single);
    procedure UpdateBounds(const ABounds, AClip: TRectI; AScale: Single);
    procedure SetPixels(const AUri: string; AWidth, AHeight: Integer; APixels: PByte;
      const ABounds, AClip: TRectI);
    procedure Clear;
    function Active: Boolean;
    function CurrentUri: string;
    procedure SetRepaintHandler(AHandler: TThreadProcedure);
    function SetCellMetrics(ACellWidth, ACellHeight, APixelScale: Single): Boolean;
    function CellAspect: Single;
    function NativeCellSize(AImageW, AImageH: Integer; out ACols, ARows: Integer): Boolean;
    /// <summary>Starts decoding what was asked for and writes hints into AGrid.
    /// The picture stays in the frame until a window clears the preview.</summary>
    procedure PaintCells(var AGrid: TTerminalGrid);
    /// <summary>The picture of the grid composed by the last PaintCells.</summary>
    function Frame: TOverlayFrame;
  end;

/// <summary>Where the picture of a frame lands in a bitmap of AW x AH pixels
/// whose cells are ACellW x ACellH: the fitted picture and the part of it that
/// shows. False when the frame has no picture.</summary>
function OverlayFrameRects(const AFrame: TOverlayFrame; ACellW, ACellH, AW, AH: Integer;
  out AFitted, AClip: TRect): Boolean;

/// <summary>Draws the picture of the frame into the bitmap, only inside ADirty.</summary>
procedure BlitOverlayFrame(const AFrame: TOverlayFrame; ACellW, ACellH: Integer;
  APixels: PByte; AStride, AW, AH: Integer; const ADirty: TRect);

implementation

uses
  System.IOUtils, System.UITypes, System.Math, uStrings, uPictureStage, uPixelBlit;

const
  cHintFg = TAlphaColor($FF9A9A9A);

constructor TOverlayModel.Create(const ADecoder: TPictureDecoder; AAsync: Boolean);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FDecoder := ADecoder;
  FAsync := AAsync;
end;

destructor TOverlayModel.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TOverlayModel.NotifyRepaint;
var
  Handler: TThreadProcedure;
begin
  FLock.Enter;
  try
    Handler := FRepaint;
  finally
    FLock.Leave;
  end;
  if Assigned(Handler) then
    if FAsync then
      TThread.Queue(nil, Handler)
    else
      Handler();
end;

procedure TOverlayModel.Store(const AUri: string; AState: TPictureState; AWidth,
  AHeight: Integer; const APixels: TBytes);
begin
  FLock.Enter;
  try
    // A result for a request that another one has replaced is dropped.
    if AUri <> FUri then
      Exit;
    FPicUri := AUri;
    FPicState := AState;
    FPicW := AWidth;
    FPicH := AHeight;
    FPicPixels := APixels;
    Inc(FPicSerial);
  finally
    FLock.Leave;
  end;
  NotifyRepaint;
end;

procedure TOverlayModel.Decode(const AUri, APath: string);
var
  W, H: Integer;
  Pixels: TBytes;
  State: TPictureState;
begin
  try
    State := FDecoder(APath, W, H, Pixels);
  except
    State := psFailed;
  end;
  if State = psReady then
    Store(AUri, psReady, W, H, Pixels)
  else
    Store(AUri, State, 0, 0, nil);
end;

procedure TOverlayModel.DecodeStaged(const AUri, APath: string; ATemp: Boolean);
begin
  try
    Decode(AUri, APath);
  finally
    if ATemp then
      TFile.Delete(APath);
  end;
end;

procedure TOverlayModel.Request(const AUri: string; const ABounds, AClip: TRectI;
  AScale: Single);
begin
  FLock.Enter;
  try
    FUri := AUri;
    FBounds := ABounds;
    FClip := AClip;
    FScale := AScale;
  finally
    FLock.Leave;
  end;
end;

procedure TOverlayModel.UpdateBounds(const ABounds, AClip: TRectI; AScale: Single);
begin
  FLock.Enter;
  try
    FBounds := ABounds;
    FClip := AClip;
    FScale := AScale;
  finally
    FLock.Leave;
  end;
end;

procedure TOverlayModel.SetPixels(const AUri: string; AWidth, AHeight: Integer;
  APixels: PByte; const ABounds, AClip: TRectI);
var
  Buf: TBytes;
begin
  if (AWidth <= 0) or (AHeight <= 0) or (APixels = nil) or
     (Int64(AWidth) * AHeight * 4 > cOverlayMaxBytes) then
    Exit;
  SetLength(Buf, AWidth * AHeight * 4);
  Move(APixels^, Buf[0], Length(Buf));
  FLock.Enter;
  try
    FUri := AUri;
    FBounds := ABounds;
    FClip := AClip;
    FScale := 0;
    FPicUri := AUri;
    FPicState := psReady;
    FPicW := AWidth;
    FPicH := AHeight;
    FPicPixels := Buf;
    Inc(FPicSerial);
  finally
    FLock.Leave;
  end;
end;

procedure TOverlayModel.Clear;
begin
  FLock.Enter;
  try
    FUri := '';
  finally
    FLock.Leave;
  end;
end;

function TOverlayModel.Active: Boolean;
begin
  FLock.Enter;
  try
    Result := FUri <> '';
  finally
    FLock.Leave;
  end;
end;

function TOverlayModel.CurrentUri: string;
begin
  FLock.Enter;
  try
    Result := FUri;
  finally
    FLock.Leave;
  end;
end;

procedure TOverlayModel.SetRepaintHandler(AHandler: TThreadProcedure);
begin
  FLock.Enter;
  try
    FRepaint := AHandler;
  finally
    FLock.Leave;
  end;
end;

function TOverlayModel.SetCellMetrics(ACellWidth, ACellHeight, APixelScale: Single): Boolean;
var
  W, H: Single;
begin
  W := ACellWidth * APixelScale;
  H := ACellHeight * APixelScale;
  FLock.Enter;
  try
    Result := (W <> FCellW) or (H <> FCellH);
    FCellW := W;
    FCellH := H;
  finally
    FLock.Leave;
  end;
end;

function TOverlayModel.CellAspect: Single;
begin
  FLock.Enter;
  try
    if (FCellW > 0) and (FCellH > 0) then
      Result := FCellH / FCellW
    else
      Result := 2.0;
  finally
    FLock.Leave;
  end;
end;

function TOverlayModel.NativeCellSize(AImageW, AImageH: Integer; out ACols,
  ARows: Integer): Boolean;
begin
  FLock.Enter;
  try
    Result := (FCellW > 0) and (FCellH > 0);
    if Result then
    begin
      ACols := Ceil(AImageW / FCellW);
      ARows := Ceil(AImageH / FCellH);
    end
    else
    begin
      ACols := 0;
      ARows := 0;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TOverlayModel.PutHint(var AGrid: TTerminalGrid; const ABounds: TRectI;
  const AText: string);
var
  X, Y, Cols: Integer;
begin
  Cols := ABounds.Right - ABounds.Left + 1;
  Y := (ABounds.Top + ABounds.Bottom) div 2;
  X := ABounds.Left + Max(0, (Cols - Length(AText)) div 2);
  if (Y < 0) or (Y > High(AGrid)) or (X < 0) or (X > High(AGrid[Y])) then
    Exit;
  PutTerminalText(AGrid, X, Y, Copy(AText, 1, Max(0, Min(Cols, High(AGrid[Y]) + 1 - X))),
    cHintFg, AGrid[Y][X].BgColor);
end;

procedure TOverlayModel.PaintCells(var AGrid: TTerminalGrid);
var
  Uri: string;
  Bounds, Clip: TRectI;
  Scale: Single;
  State: TPictureState;
  Start: Boolean;
begin
  FFrame := Default(TOverlayFrame);
  FLock.Enter;
  try
    if FUri = '' then
      Exit;
    Uri := FUri;
    Bounds := FBounds;
    Clip := FClip;
    Scale := FScale;
    Start := False;
    if FPicUri = Uri then
      State := FPicState
    else
    begin
      State := psLoading;
      FPicUri := Uri;
      FPicState := psLoading;
      FPicPixels := nil;
      Start := True;
    end;
    if State = psReady then
    begin
      FFrame.Visible := True;
      FFrame.Width := FPicW;
      FFrame.Height := FPicH;
      FFrame.Pixels := FPicPixels;
      FFrame.Bounds := Bounds;
      FFrame.Clip := Clip;
      FFrame.ImageScale := Scale;
      FFrame.Serial := FPicSerial;
    end;
  finally
    FLock.Leave;
  end;
  if Start then
    StagePictureFile(Uri,
      procedure(const APath: string; ATemp: Boolean)
      begin
        if APath = '' then
          Store(Uri, psFailed, 0, 0, nil)
        else if FAsync then
          TThread.CreateAnonymousThread(
            procedure
            begin
              DecodeStaged(Uri, APath, ATemp);
            end).Start
        else
          DecodeStaged(Uri, APath, ATemp);
      end);
  case State of
    psNoDecoder:
      PutHint(AGrid, Bounds, T('ui.picture.needImageLib', '(install SDL2_image to see pictures)'));
    psFailed:
      PutHint(AGrid, Bounds, T('ui.picture.noPreview', '(no preview)'));
  end;
end;

function TOverlayModel.Frame: TOverlayFrame;
begin
  Result := FFrame;
end;

function OverlayFrameRects(const AFrame: TOverlayFrame; ACellW, ACellH, AW, AH: Integer;
  out AFitted, AClip: TRect): Boolean;
var
  Target: TRect;
begin
  Result := AFrame.Visible and (Length(AFrame.Pixels) > 0);
  if not Result then
    Exit;
  Target := TRect.Create(AFrame.Bounds.Left * ACellW, AFrame.Bounds.Top * ACellH,
    (AFrame.Bounds.Right + 1) * ACellW, (AFrame.Bounds.Bottom + 1) * ACellH);
  AFitted := FitPicture(AFrame.Width, AFrame.Height, Target, AFrame.ImageScale);
  AClip := TRect.Create(AFrame.Clip.Left * ACellW, AFrame.Clip.Top * ACellH,
    (AFrame.Clip.Right + 1) * ACellW, (AFrame.Clip.Bottom + 1) * ACellH);
  AClip := TRect.Intersect(AClip, TRect.Create(0, 0, AW, AH));
end;

procedure BlitOverlayFrame(const AFrame: TOverlayFrame; ACellW, ACellH: Integer;
  APixels: PByte; AStride, AW, AH: Integer; const ADirty: TRect);
var
  Fitted, Clip: TRect;
begin
  if not OverlayFrameRects(AFrame, ACellW, ACellH, AW, AH, Fitted, Clip) then
    Exit;
  BlitScaled(AFrame.Pixels, AFrame.Width, AFrame.Height, APixels, AStride, AW, AH,
    Fitted, TRect.Intersect(Clip, ADirty));
end;

end.
