unit uOverlayRenderer;

{ Stage 24: Media Overlay (Quick View, Ctrl+Q). Host-only MVP path per
  OVERLAY_PLUGIN.md §4 ("Host сам по file_type/uri панели делает
  overlay_request") — no plugin cdecl API yet, that's Post-MVP (stage 29+).

  Threading: the VFS byte read is async/worker (uFileVfs.pas already
  marshals its callback onto the UI thread via TThread.Queue — see
  QueueBytes). Decode (TBitmap.LoadFromStream) and every frame's blit-scale
  in Draw both run on the UI thread; FMX TBitmap/TCanvas aren't safe to
  touch off it. No pre-downscale at decode time either — Draw blit-scales
  the full decoded bitmap into the current pixel bounds every frame (GPU
  DrawBitmap, same pattern TTerminalRenderer.Draw already uses for the
  whole grid frame), which also means a bounds_changed resize just needs a
  repaint, no re-decode. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, FMX.Graphics,
  uThemeTypes;

const
  cOverlayMaxBytes = 32 * 1024 * 1024; // 32 MB cap — generous for one photo

/// <summary>Whitelist for Quick View — matches what FMX's default bitmap
/// codecs (WIC on Windows) reliably decode via LoadFromStream.</summary>
function IsOverlayImageExtension(const AExt: string): Boolean;

/// <summary>Request (or replace) the active preview. ABounds is in grid
/// cells (inclusive Left/Top/Right/Bottom, TRectI convention).</summary>
procedure RequestOverlayPreview(const AURI: string; const ABounds: TRectI); overload;
/// <summary>As above, but the image is fitted into ABounds and only the
/// part inside AClip (grid cells, inclusive) is painted — a block that runs
/// past the viewport edge is cut off instead of shrunk.</summary>
procedure RequestOverlayPreview(const AURI: string; const ABounds, AClip: TRectI); overload;
/// <summary>Cheap, no decode/network — just moves where Draw paints the
/// already-loaded (or loading) preview. Call every redraw from the panel
/// that owns the Quick View bounds so a resize/reflow doesn't leave the
/// image positioned against stale geometry between URI changes.</summary>
procedure UpdateOverlayBounds(const ABounds: TRectI); overload;
procedure UpdateOverlayBounds(const ABounds, AClip: TRectI); overload;
procedure ClearOverlayPreview;
function OverlayActive: Boolean;
/// <summary>URI of the current/last preview request; '' if none.</summary>
function OverlayCurrentURI: string;
/// <summary>Draw the current preview (if ready) onto ACanvas, converting
/// the stored cell bounds to pixels via ACellWidth/ACellHeight.</summary>
procedure DrawOverlayPreview(ACanvas: TCanvas; ACellWidth, ACellHeight: Single);
/// <summary>Host subscribes once (e.g. FormCreate) to repaint when a decode
/// completes or fails — the request itself doesn't force a paint.</summary>
procedure SetOverlayRepaintHandler(AHandler: TThreadProcedure);
/// <summary>Host reports the grid's cell size in pixels (every paint). Lets
/// layout code size an image block in cells without knowing the font.
/// Returns True when the metrics changed.</summary>
function SetOverlayCellMetrics(ACellWidth, ACellHeight: Single): Boolean;
/// <summary>Cell height / cell width in pixels; 2.0 until the host reports.</summary>
function OverlayCellAspect: Single;
/// <summary>Pixel size from the file header only (PNG, JPEG, GIF, BMP,
/// WebP) — no decode, reads at most 64 KB. False for other formats or a
/// broken header.</summary>
function ReadImagePixelSize(const APath: string; out AWidth, AHeight: Integer): Boolean;

implementation

uses
  System.Math, System.Types,
  uVfsTypes, uVfsRegistry;

type
  TOverlayState = (osIdle, osLoading, osReady, osError);

  TOverlayHost = class
  private
    FVfs: IVirtualFileSystem;
    FGen: Cardinal;
    FCancel: IJobCancelToken;
    FState: TOverlayState;
    FURI: string;
    FBounds: TRectI;
    FClip: TRectI; // painted part of FBounds (= FBounds when not clipped)
    FBitmap: TBitmap;
    FRepaint: TThreadProcedure;
    procedure DecodeAndStore(const ABytes: TBytes; AGen: Cardinal);
    procedure NotifyRepaint;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Request(const AURI: string; const ABounds, AClip: TRectI);
    procedure UpdateBounds(const ABounds, AClip: TRectI);
    procedure Clear;
    function Active: Boolean;
    procedure Draw(ACanvas: TCanvas; ACellWidth, ACellHeight: Single);
    property URI: string read FURI;
    property RepaintHandler: TThreadProcedure read FRepaint write FRepaint;
  end;

var
  GHost: TOverlayHost;

function Host: TOverlayHost;
begin
  if not Assigned(GHost) then
    GHost := TOverlayHost.Create;
  Result := GHost;
end;

function IsOverlayImageExtension(const AExt: string): Boolean;
var
  E: string;
begin
  E := LowerCase(AExt);
  Result := (E = '.png') or (E = '.jpg') or (E = '.jpeg') or (E = '.jfif') or
    (E = '.bmp') or (E = '.gif') or (E = '.ico') or (E = '.tif') or
    (E = '.tiff') or (E = '.webp');
end;

{ TOverlayHost }

constructor TOverlayHost.Create;
begin
  inherited Create;
  FVfs := CreateDefaultVfs;
  FState := osIdle;
end;

destructor TOverlayHost.Destroy;
begin
  if Assigned(FCancel) then
    FCancel.Cancel;
  FCancel := nil;
  FreeAndNil(FBitmap);
  inherited Destroy;
end;

procedure TOverlayHost.NotifyRepaint;
begin
  if Assigned(FRepaint) then
    FRepaint;
end;

procedure TOverlayHost.Request(const AURI: string; const ABounds, AClip: TRectI);
var
  Gen: Cardinal;
  Vfs: IVirtualFileSystem;
begin
  if Assigned(FCancel) then
    FCancel.Cancel;
  Inc(FGen);
  Gen := FGen;
  FCancel := TJobCancelToken.Create;
  FURI := AURI;
  FBounds := ABounds;
  FClip := AClip;
  FState := osLoading;
  FreeAndNil(FBitmap);
  Vfs := FVfs;

  Vfs.ReadBytesAsync(AURI, cOverlayMaxBytes, FCancel,
    procedure(const ABytes: TBytes; const AError: TVfsError)
    begin
      if Gen <> FGen then
        Exit; // superseded by a newer Request/Clear
      FCancel := nil;
      if AError.Code <> vecOk then
      begin
        FState := osError;
        NotifyRepaint;
        Exit;
      end;
      DecodeAndStore(ABytes, Gen);
    end);
end;

procedure TOverlayHost.UpdateBounds(const ABounds, AClip: TRectI);
begin
  FBounds := ABounds;
  FClip := AClip;
end;

procedure TOverlayHost.DecodeAndStore(const ABytes: TBytes; AGen: Cardinal);
var
  Stream: TBytesStream;
begin
  if AGen <> FGen then
    Exit;
  FreeAndNil(FBitmap);
  FBitmap := TBitmap.Create;
  Stream := TBytesStream.Create(ABytes);
  try
    try
      FBitmap.LoadFromStream(Stream);
      if (FBitmap.Width > 0) and (FBitmap.Height > 0) then
        FState := osReady
      else
      begin
        FreeAndNil(FBitmap);
        FState := osError;
      end;
    except
      FreeAndNil(FBitmap);
      FState := osError;
    end;
  finally
    Stream.Free;
  end;
  NotifyRepaint;
end;

procedure TOverlayHost.Clear;
begin
  // Idempotent by design: DrawQuickViewContent calls this on every redraw
  // while the cursor sits on a non-previewable row. Without this guard,
  // NotifyRepaint -> Invalidate -> FormPaint -> DrawQuickViewContent ->
  // Clear would busy-loop repainting forever instead of settling.
  if FState = osIdle then
    Exit;
  if Assigned(FCancel) then
    FCancel.Cancel;
  FCancel := nil;
  Inc(FGen); // orphan any in-flight callback
  FState := osIdle;
  FURI := '';
  FreeAndNil(FBitmap);
  NotifyRepaint;
end;

function TOverlayHost.Active: Boolean;
begin
  Result := FState <> osIdle;
end;

procedure TOverlayHost.Draw(ACanvas: TCanvas; ACellWidth, ACellHeight: Single);
var
  BoundsPx, ClipPx, Fitted: TRectF;
  SrcW, SrcH, BW, BH, Scale, CX, CY: Single;
  Saved: TCanvasSaveState;
begin
  if (FState <> osReady) or not Assigned(FBitmap) then
    Exit;
  if (ACellWidth <= 0) or (ACellHeight <= 0) then
    Exit;

  BoundsPx := RectF(FBounds.Left * ACellWidth, FBounds.Top * ACellHeight,
    (FBounds.Right + 1) * ACellWidth, (FBounds.Bottom + 1) * ACellHeight);
  BW := BoundsPx.Right - BoundsPx.Left;
  BH := BoundsPx.Bottom - BoundsPx.Top;
  if (BW <= 0) or (BH <= 0) then
    Exit;

  SrcW := FBitmap.Width;
  SrcH := FBitmap.Height;
  if (SrcW <= 0) or (SrcH <= 0) then
    Exit;

  // fit: contain — scale to fit inside bounds, preserve aspect, center.
  Scale := Min(BW / SrcW, BH / SrcH);
  CX := BoundsPx.Left + (BW - SrcW * Scale) / 2;
  CY := BoundsPx.Top + (BH - SrcH * Scale) / 2;
  Fitted := RectF(CX, CY, CX + SrcW * Scale, CY + SrcH * Scale);

  ClipPx := RectF(FClip.Left * ACellWidth, FClip.Top * ACellHeight,
    (FClip.Right + 1) * ACellWidth, (FClip.Bottom + 1) * ACellHeight);
  if (ClipPx.Width <= 0) or (ClipPx.Height <= 0) then
    Exit;
  if ClipPx.Contains(Fitted) then
  begin
    ACanvas.DrawBitmap(FBitmap, RectF(0, 0, SrcW, SrcH), Fitted, 1, True);
    Exit;
  end;
  Saved := ACanvas.SaveState;
  try
    ACanvas.IntersectClipRect(ClipPx);
    ACanvas.DrawBitmap(FBitmap, RectF(0, 0, SrcW, SrcH), Fitted, 1, True);
  finally
    ACanvas.RestoreState(Saved);
  end;
end;

{ Free functions }

procedure RequestOverlayPreview(const AURI: string; const ABounds: TRectI);
begin
  Host.Request(AURI, ABounds, ABounds);
end;

procedure RequestOverlayPreview(const AURI: string; const ABounds, AClip: TRectI);
begin
  Host.Request(AURI, ABounds, AClip);
end;

procedure UpdateOverlayBounds(const ABounds: TRectI);
begin
  if Assigned(GHost) then
    GHost.UpdateBounds(ABounds, ABounds);
end;

procedure UpdateOverlayBounds(const ABounds, AClip: TRectI);
begin
  if Assigned(GHost) then
    GHost.UpdateBounds(ABounds, AClip);
end;

procedure ClearOverlayPreview;
begin
  if Assigned(GHost) then
    GHost.Clear;
end;

function OverlayActive: Boolean;
begin
  Result := Assigned(GHost) and GHost.Active;
end;

function OverlayCurrentURI: string;
begin
  if Assigned(GHost) then
    Result := GHost.URI
  else
    Result := '';
end;

procedure DrawOverlayPreview(ACanvas: TCanvas; ACellWidth, ACellHeight: Single);
begin
  if Assigned(GHost) then
    GHost.Draw(ACanvas, ACellWidth, ACellHeight);
end;

procedure SetOverlayRepaintHandler(AHandler: TThreadProcedure);
begin
  Host.RepaintHandler := AHandler;
end;

var
  GCellW: Single = 0;
  GCellH: Single = 0;

function SetOverlayCellMetrics(ACellWidth, ACellHeight: Single): Boolean;
begin
  Result := (ACellWidth > 0) and (ACellHeight > 0) and
    (not SameValue(ACellWidth, GCellW) or not SameValue(ACellHeight, GCellH));
  if Result then
  begin
    GCellW := ACellWidth;
    GCellH := ACellHeight;
  end;
end;

function OverlayCellAspect: Single;
begin
  if (GCellW > 0) and (GCellH > 0) then
    Result := GCellH / GCellW
  else
    Result := 2.0;
end;

function ReadImagePixelSize(const APath: string; out AWidth, AHeight: Integer): Boolean;
const
  cMaxHeader = 64 * 1024;
var
  FS: TFileStream;
  B: TBytes;
  N, P, SegLen: Integer;
  M: Byte;

  function BE16(I: Integer): Integer;
  begin
    Result := (B[I] shl 8) or B[I + 1];
  end;

  function LE16(I: Integer): Integer;
  begin
    Result := B[I] or (B[I + 1] shl 8);
  end;

  function LE24(I: Integer): Integer;
  begin
    Result := B[I] or (B[I + 1] shl 8) or (B[I + 2] shl 16);
  end;

  function BE32(I: Integer): Int64;
  begin
    Result := (Int64(B[I]) shl 24) or (B[I + 1] shl 16) or (B[I + 2] shl 8) or B[I + 3];
  end;

  function LE32(I: Integer): Integer;
  begin
    Result := Integer(Cardinal(B[I]) or (Cardinal(B[I + 1]) shl 8) or
      (Cardinal(B[I + 2]) shl 16) or (Cardinal(B[I + 3]) shl 24));
  end;

  function Tag(I: Integer; const S: AnsiString): Boolean;
  var
    K: Integer;
  begin
    Result := I + Length(S) <= N;
    if Result then
      for K := 1 to Length(S) do
        if B[I + K - 1] <> Ord(S[K]) then
          Exit(False);
  end;

begin
  Result := False;
  AWidth := 0;
  AHeight := 0;
  try
    FS := TFileStream.Create(WinApiPath(APath), fmOpenRead or fmShareDenyNone);
    try
      N := Integer(Min(FS.Size, cMaxHeader));
      SetLength(B, N);
      if N > 0 then
        FS.ReadBuffer(B[0], N);
    finally
      FS.Free;
    end;
  except
    Exit;
  end;

  if Tag(0, #$89'PNG'#13#10#26#10) and Tag(12, 'IHDR') and (N >= 24) then
  begin
    AWidth := BE32(16);
    AHeight := BE32(20);
  end
  else if (Tag(0, 'GIF87a') or Tag(0, 'GIF89a')) and (N >= 10) then
  begin
    AWidth := LE16(6);
    AHeight := LE16(8);
  end
  else if Tag(0, 'BM') and (N >= 26) then
  begin
    AWidth := LE32(18);
    AHeight := Abs(LE32(22)); // negative = top-down rows
  end
  else if Tag(0, 'RIFF') and Tag(8, 'WEBP') and (N >= 30) then
  begin
    if Tag(12, 'VP8 ') then
    begin
      AWidth := LE16(26) and $3FFF;
      AHeight := LE16(28) and $3FFF;
    end
    else if Tag(12, 'VP8L') and (N >= 25) then
    begin
      AWidth := (LE16(21) and $3FFF) + 1;
      AHeight := ((LE32(21) shr 14) and $3FFF) + 1;
    end
    else if Tag(12, 'VP8X') then
    begin
      AWidth := LE24(24) + 1;
      AHeight := LE24(27) + 1;
    end;
  end
  else if (N >= 4) and (B[0] = $FF) and (B[1] = $D8) then
  begin
    // JPEG: walk segments to the first SOFn (not DHT C4 / JPG C8 / DAC CC).
    P := 2;
    while P + 9 < N do
    begin
      if B[P] <> $FF then
        Break;
      M := B[P + 1];
      if M = $FF then
      begin
        Inc(P); // fill byte
        Continue;
      end;
      if (M = $D8) or ((M >= $D0) and (M <= $D7)) or (M = $01) then
      begin
        Inc(P, 2); // standalone markers
        Continue;
      end;
      SegLen := BE16(P + 2);
      if (M >= $C0) and (M <= $CF) and (M <> $C4) and (M <> $C8) and (M <> $CC) then
      begin
        AHeight := BE16(P + 5);
        AWidth := BE16(P + 7);
        Break;
      end;
      if SegLen < 2 then
        Break;
      Inc(P, 2 + SegLen);
    end;
  end;
  Result := (AWidth > 0) and (AHeight > 0);
end;

initialization

finalization
  FreeAndNil(GHost);

end.
