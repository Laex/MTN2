unit uThumbsDecode;

{ Reads a picture file into 32-bit pixels (blue, green, red, alpha in memory
  order) with SDL2 and, when it is installed, SDL2_image (PNG, JPEG, GIF and
  more); without it only BMP is read. }

interface

uses
  System.SysUtils;

/// <summary>Starts the decoder; False when SDL2 is not available.</summary>
function ThumbsDecodeInit: Boolean;
procedure ThumbsDecodeDone;

/// <summary>Decodes the file; False when it is not a readable picture.
/// Safe to call from a worker thread after ThumbsDecodeInit.</summary>
function ThumbsDecodeFile(const APath: string; out AWidth, AHeight: Integer;
  out APixels: TBytes): Boolean;

implementation

uses
  uSdlApi, uSdlImage;

function ThumbsDecodeInit: Boolean;
var
  Err: string;
begin
  Result := SdlLoaded or LoadSdl(Err);
end;

procedure ThumbsDecodeDone;
begin
end;

function ThumbsDecodeFile(const APath: string; out AWidth, AHeight: Integer;
  out APixels: TBytes): Boolean;
begin
  Result := DecodePictureFile(APath, AWidth, AHeight, APixels) = pdOk;
end;

end.
