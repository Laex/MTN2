unit uOverlayRenderer;

{ Picture preview laid over the character grid (POSIX build). A text terminal
  has no pixels to put a picture on, so the picture is turned into colored
  block characters by chafa (--format=symbols works in every TrueColor
  terminal) and written into the cells of the preview area. The conversion
  runs on a worker thread and is cached per file and area size; until it is
  ready the area stays empty. Without chafa the area shows a hint. A picture in
  an archive or on a server is first copied to a temporary file (uPictureStage).
  The Windows build lives in Platform\Windows; each
  project puts exactly one of the two directories on its unit search path. }

interface

uses
  System.Classes, System.Types, uThemeTypes, uTerminalTypes;

const
  cOverlayMaxBytes = 32 * 1024 * 1024;

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
function SetOverlayCellMetrics(ACellWidth, ACellHeight: Single;
  APixelScale: Single = 1): Boolean;
/// <summary>Cell height / cell width; 2.0.</summary>
function OverlayCellAspect: Single;
/// <summary>False: the cell size in pixels is not known.</summary>
function OverlayNativeCellSize(AImageW, AImageH: Integer; out ACols, ARows: Integer): Boolean;

/// <summary>Writes the preview into the cells of AGrid. Painting what was not
/// requested again since the previous call is skipped, so a preview whose
/// window went away disappears with the next frame. Cells come from the
/// picture of the current request; a converter still at work leaves them as
/// they are.</summary>
procedure PaintOverlayCells(var AGrid: TTerminalGrid);

implementation

uses
  System.SysUtils, System.SyncObjs, System.IOUtils, System.UITypes, System.Math,
  uPlatformProcess, uAnsiPicture, uPictureStage, uStrings;

const
  cConvertTimeoutMs = 8000;
  cHintFg = TAlphaColor($FF9A9A9A);

type
  TPictureState = (psNone, psReady, psMissingTool, psFailed);

var
  GLock: TCriticalSection;
  GUri: string;
  GBounds, GClip: TRectI;
  GTouched: Boolean;
  GRepaint: TThreadProcedure;
  // The finished conversion and the request it answers.
  GReadyKey: string;
  GReadyState: TPictureState;
  GReadyPicture: TTerminalGrid;
  // Key of the conversion in progress; '' when none.
  GPendingKey: string;

function BoundsKey(const AUri: string; ACols, ARows: Integer): string;
begin
  Result := AUri + '|' + IntToStr(ACols) + 'x' + IntToStr(ARows);
end;

procedure StoreResult(const AKey: string; AState: TPictureState;
  const APicture: TTerminalGrid);
var
  Handler: TThreadProcedure;
begin
  GLock.Enter;
  try
    GReadyKey := AKey;
    GReadyState := AState;
    GReadyPicture := APicture;
    GPendingKey := '';
    // The frame that follows may not request the preview again; the finished
    // picture of the current request must still be painted once.
    if (GUri <> '') and (AKey = BoundsKey(GUri, GBounds.Right - GBounds.Left + 1,
         GBounds.Bottom - GBounds.Top + 1)) then
      GTouched := True;
    Handler := GRepaint;
  finally
    GLock.Leave;
  end;
  if Assigned(Handler) then
    TThread.Queue(nil, Handler);
end;

procedure ConvertPicture(const AKey, APath: string; ACols, ARows: Integer);
var
  Tool, Output: string;
  Code: Cardinal;
  Picture: TTerminalGrid;
begin
  Picture := nil;
  Tool := FileSearch('chafa', GetEnvironmentVariable('PATH'));
  if Tool = '' then
  begin
    StoreResult(AKey, psMissingTool, nil);
    Exit;
  end;
  if (PlatformRunCaptured(Tool, ['--format=symbols', '--colors=full', '--animate=off',
       '--size=' + IntToStr(ACols) + 'x' + IntToStr(ARows), APath], '',
       cConvertTimeoutMs, nil, Output, Code) <> srOk) or (Code <> 0) then
  begin
    StoreResult(AKey, psFailed, nil);
    Exit;
  end;
  Picture := ParseAnsiPicture(Output, TAlphaColors.Silver, TAlphaColors.Black);
  if Length(Picture) = 0 then
    StoreResult(AKey, psFailed, nil)
  else
    StoreResult(AKey, psReady, Picture);
end;

procedure StartConversion(const AKey, APath: string; ACols, ARows: Integer;
  ATemp: Boolean);
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        try
          ConvertPicture(AKey, APath, ACols, ARows);
        except
          StoreResult(AKey, psFailed, nil);
        end;
      finally
        if ATemp then
          TFile.Delete(APath);
      end;
    end).Start;
end;

procedure RequestOverlayPreview(const AURI: string; const ABounds: TRectI);
begin
  RequestOverlayPreview(AURI, ABounds, ABounds, 0);
end;

procedure RequestOverlayPreview(const AURI: string; const ABounds, AClip: TRectI;
  AImageScale: Single);
begin
  GLock.Enter;
  try
    GUri := AURI;
    GBounds := ABounds;
    GClip := AClip;
    GTouched := True;
  finally
    GLock.Leave;
  end;
end;

procedure UpdateOverlayBounds(const ABounds: TRectI);
begin
  UpdateOverlayBounds(ABounds, ABounds, 0);
end;

procedure UpdateOverlayBounds(const ABounds, AClip: TRectI; AImageScale: Single);
begin
  GLock.Enter;
  try
    GBounds := ABounds;
    GClip := AClip;
    GTouched := True;
  finally
    GLock.Leave;
  end;
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
end;

procedure ClearOverlayPreview;
begin
  GLock.Enter;
  try
    GUri := '';
    GTouched := False;
  finally
    GLock.Leave;
  end;
end;

function OverlayActive: Boolean;
begin
  GLock.Enter;
  try
    Result := (GUri <> '') and GTouched;
  finally
    GLock.Leave;
  end;
end;

function OverlayCurrentURI: string;
begin
  GLock.Enter;
  try
    Result := GUri;
  finally
    GLock.Leave;
  end;
end;

procedure SetOverlayRepaintHandler(AHandler: TThreadProcedure);
begin
  GLock.Enter;
  try
    GRepaint := AHandler;
  finally
    GLock.Leave;
  end;
end;

function SetOverlayCellMetrics(ACellWidth, ACellHeight: Single;
  APixelScale: Single): Boolean;
begin
  Result := False;
end;

function OverlayCellAspect: Single;
begin
  Result := 2.0;
end;

function OverlayNativeCellSize(AImageW, AImageH: Integer; out ACols, ARows: Integer): Boolean;
begin
  ACols := 0;
  ARows := 0;
  Result := False;
end;

procedure PutHint(var AGrid: TTerminalGrid; const ABounds: TRectI; const AText: string);
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

procedure PaintOverlayCells(var AGrid: TTerminalGrid);
var
  Uri, Key: string;
  Bounds, Clip: TRectI;
  State: TPictureState;
  Picture: TTerminalGrid;
  Cols, Rows, OffX, OffY, X, Y, GX, GY: Integer;
  Start: Boolean;
begin
  GLock.Enter;
  try
    if (GUri = '') or not GTouched then
      Exit;
    GTouched := False;
    Uri := GUri;
    Bounds := GBounds;
    Clip := GClip;
  finally
    GLock.Leave;
  end;
  Cols := Bounds.Right - Bounds.Left + 1;
  Rows := Bounds.Bottom - Bounds.Top + 1;
  if (Cols <= 0) or (Rows <= 0) or (Length(AGrid) = 0) then
    Exit;
  Key := BoundsKey(Uri, Cols, Rows);

  Start := False;
  GLock.Enter;
  try
    if GReadyKey = Key then
    begin
      State := GReadyState;
      Picture := GReadyPicture;
    end
    else
    begin
      State := psNone;
      Picture := nil;
      if GPendingKey <> Key then
      begin
        GPendingKey := Key;
        Start := True;
      end;
    end;
  finally
    GLock.Leave;
  end;

  if Start then
    StagePictureFile(Uri,
      procedure(const APath: string; ATemp: Boolean)
      begin
        if APath = '' then
          StoreResult(Key, psFailed, nil)
        else
          StartConversion(Key, APath, Cols, Rows, ATemp);
      end);

  case State of
    psMissingTool:
      PutHint(AGrid, Bounds, T('ui.picture.needChafa', '(install chafa to see pictures)'));
    psFailed:
      PutHint(AGrid, Bounds, T('ui.picture.noPreview', '(no preview)'));
    psReady:
      begin
        OffX := Max(0, (Cols - AnsiPictureWidth(Picture)) div 2);
        OffY := Max(0, (Rows - Length(Picture)) div 2);
        for Y := 0 to Min(High(Picture), Rows - 1) do
          for X := 0 to Min(Length(Picture[Y]) - 1, Cols - 1) do
          begin
            GX := Bounds.Left + OffX + X;
            GY := Bounds.Top + OffY + Y;
            if (GX < Clip.Left) or (GX > Clip.Right) or (GY < Clip.Top) or (GY > Clip.Bottom) then
              Continue;
            if (GY < 0) or (GY > High(AGrid)) or (GX < 0) or (GX > High(AGrid[GY])) then
              Continue;
            AGrid[GY][GX] := Picture[Y][X];
          end;
      end;
  end;
end;

initialization
  GLock := TCriticalSection.Create;

finalization
  GLock.Free;

end.
