unit uThumbsDecode;

{ Reads a picture file into 32-bit pixels (blue, green, red, alpha in memory
  order) with GDI+, which brings PNG, JPEG, GIF, BMP, TIFF and ICO. }

interface

uses
  System.SysUtils;

/// <summary>Starts the decoder; False when it is not available.</summary>
function ThumbsDecodeInit: Boolean;
procedure ThumbsDecodeDone;

/// <summary>Decodes the file; False when it is not a readable picture.
/// Safe to call from a worker thread after ThumbsDecodeInit.</summary>
function ThumbsDecodeFile(const APath: string; out AWidth, AHeight: Integer;
  out APixels: TBytes): Boolean;

implementation

uses
  Winapi.Windows, Winapi.GDIPAPI;

const
  cMaxPixels = 120 * 1000 * 1000;

var
  GToken: ULONG_PTR;
  GStarted: Boolean;

function ThumbsDecodeInit: Boolean;
var
  Input: TGdiplusStartupInput;
begin
  if not GStarted then
  begin
    FillChar(Input, SizeOf(Input), 0);
    Input.GdiplusVersion := 1;
    GStarted := GdiplusStartup(GToken, @Input, nil) = Ok;
  end;
  Result := GStarted;
end;

procedure ThumbsDecodeDone;
begin
  if GStarted then
  begin
    GdiplusShutdown(GToken);
    GStarted := False;
  end;
end;

function ThumbsDecodeFile(const APath: string; out AWidth, AHeight: Integer;
  out APixels: TBytes): Boolean;
var
  Bmp: GpBitmap;
  W, H: UINT;
  Rect: TGPRect;
  Data: TBitmapData;
  Y: Integer;
  Locked: Boolean;
begin
  Result := False;
  AWidth := 0;
  AHeight := 0;
  APixels := nil;
  if not GStarted then
    Exit;
  Bmp := nil;
  if GdipCreateBitmapFromFile(PWideChar(APath), Bmp) <> Ok then
    Exit;
  Locked := False;
  try
    if (GdipGetImageWidth(Bmp, W) <> Ok) or (GdipGetImageHeight(Bmp, H) <> Ok) or
       (W = 0) or (H = 0) or (Int64(W) * Int64(H) > cMaxPixels) then
      Exit;
    Rect.X := 0;
    Rect.Y := 0;
    Rect.Width := Integer(W);
    Rect.Height := Integer(H);
    FillChar(Data, SizeOf(Data), 0);
    if GdipBitmapLockBits(Bmp, @Rect, ImageLockModeRead, PixelFormat32bppARGB, @Data) <> Ok then
      Exit;
    Locked := True;
    if (Data.Scan0 = nil) or (Data.Stride <= 0) then
      Exit;
    SetLength(APixels, Integer(W) * Integer(H) * 4);
    for Y := 0 to Integer(H) - 1 do
      Move(PByte(Data.Scan0)[Y * Data.Stride], APixels[Y * Integer(W) * 4], Integer(W) * 4);
    AWidth := Integer(W);
    AHeight := Integer(H);
    Result := True;
  finally
    if Locked then
      GdipBitmapUnlockBits(Bmp, @Data);
    GdipDisposeImage(Bmp);
  end;
end;

end.
