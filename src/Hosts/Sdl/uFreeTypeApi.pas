unit uFreeTypeApi;

{ The part of FreeType 2 the glyph source uses, bound at run time. The
  structures FreeType hands out (face, size, glyph slot) are read at fixed
  offsets of the 64-bit Unix layout (C long is 8 bytes), written down here
  once; where long is 4 bytes (Windows) the library is not used. }

interface

const
  FT_LOAD_DEFAULT = 0;
  FT_LOAD_NO_BITMAP = 8;
  FT_LOAD_RENDER = 4;

  FT_PIXEL_MODE_MONO = 1;
  FT_PIXEL_MODE_GRAY = 2;

type
  TFtLibrary = Pointer;
  TFtFace = Pointer;

  /// <summary>The rendered glyph of the last FT_Load_Glyph call.</summary>
  TFtBitmapInfo = record
    Rows: Integer;
    Width: Integer;
    Pitch: Integer;
    Buffer: PByte;
    PixelMode: Byte;
    Left: Integer;
    Top: Integer;
    /// <summary>Horizontal advance in 1/64 pixel.</summary>
    Advance: Integer;
  end;

  /// <summary>Vertical metrics of a face at its current size, in whole pixels.</summary>
  TFtSizeInfo = record
    Ascender: Integer;
    Descender: Integer;
    Height: Integer;
  end;

var
  FT_Init_FreeType: function(out ALib: TFtLibrary): Integer; cdecl;
  FT_Done_FreeType: function(ALib: TFtLibrary): Integer; cdecl;
  FT_New_Face: function(ALib: TFtLibrary; APath: PAnsiChar; AIndex: NativeInt;
    out AFace: TFtFace): Integer; cdecl;
  FT_Done_Face: function(AFace: TFtFace): Integer; cdecl;
  FT_Set_Pixel_Sizes: function(AFace: TFtFace; AWidth, AHeight: Cardinal): Integer; cdecl;
  FT_Get_Char_Index: function(AFace: TFtFace; ACode: NativeUInt): Cardinal; cdecl;
  FT_Load_Glyph: function(AFace: TFtFace; AIndex: Cardinal; AFlags: Integer): Integer; cdecl;

/// <summary>Loads libfreetype; False and AError set when it is not there.</summary>
function LoadFreeType(out AError: string): Boolean;
function FreeTypeLoaded: Boolean;

/// <summary>Reads the glyph slot after FT_Load_Glyph with FT_LOAD_RENDER.</summary>
function FtGlyphBitmap(AFace: TFtFace): TFtBitmapInfo;
function FtSizeInfo(AFace: TFtFace): TFtSizeInfo;

implementation

uses
  System.SysUtils, uPlatformInfo;

const
  cFaceGlyphOffset = 152;
  cFaceSizeOffset = 160;
  // FT_SizeRec: face, generic (two pointers), then the FT_Size_Metrics whose
  // ascender, descender and height follow two ppem words and two scales.
  cSizeMetricsOffset = 24;
  cMetricsAscender = cSizeMetricsOffset + 24;
  cMetricsDescender = cSizeMetricsOffset + 32;
  cMetricsHeight = cSizeMetricsOffset + 40;
  // FT_GlyphSlotRec.
  cSlotAdvanceX = 128;
  cSlotBitmap = 152;
  cSlotBitmapLeft = 192;
  cSlotBitmapTop = 196;

var
  GFt: NativeUInt;

function LoadFreeType(out AError: string): Boolean;
const
  cNames: array[0..2] of string = ('libfreetype.so.6', 'libfreetype.so', 'freetype.dll');
var
  I: Integer;
  FirstError: string;

  function Bind(const AName: string; var AProc): Boolean;
  begin
    Pointer(AProc) := PlatformGetProc(GFt, AName);
    Result := Pointer(AProc) <> nil;
  end;

begin
  AError := '';
  if GFt <> 0 then
    Exit(True);
  if PlatformSharedLibExt <> '.so' then
  begin
    AError := 'FreeType is read through the 64-bit Unix structure layout';
    Exit(False);
  end;
  for I := Low(cNames) to High(cNames) do
  begin
    GFt := PlatformLoadLibrary(cNames[I]);
    if GFt <> 0 then
      Break;
    if I = Low(cNames) then
      FirstError := PlatformLibraryError;
  end;
  if GFt = 0 then
  begin
    AError := 'FreeType library not found (' + FirstError + ')';
    Exit(False);
  end;
  if not (Bind('FT_Init_FreeType', FT_Init_FreeType) and
          Bind('FT_Done_FreeType', FT_Done_FreeType) and
          Bind('FT_New_Face', FT_New_Face) and
          Bind('FT_Done_Face', FT_Done_Face) and
          Bind('FT_Set_Pixel_Sizes', FT_Set_Pixel_Sizes) and
          Bind('FT_Get_Char_Index', FT_Get_Char_Index) and
          Bind('FT_Load_Glyph', FT_Load_Glyph)) then
  begin
    AError := 'FreeType library is incomplete';
    PlatformFreeLibrary(GFt);
    GFt := 0;
    Exit(False);
  end;
  Result := True;
end;

function FreeTypeLoaded: Boolean;
begin
  Result := GFt <> 0;
end;

function ReadPtr(AAddress: Pointer; AOffset: Integer): Pointer;
begin
  Result := PPointer(PByte(AAddress) + AOffset)^;
end;

function ReadInt(AAddress: Pointer; AOffset: Integer): Integer;
begin
  Result := PInteger(PByte(AAddress) + AOffset)^;
end;

function ReadLong(AAddress: Pointer; AOffset: Integer): Int64;
begin
  Result := PInt64(PByte(AAddress) + AOffset)^;
end;

function FtGlyphBitmap(AFace: TFtFace): TFtBitmapInfo;
var
  Slot: Pointer;
begin
  Slot := ReadPtr(AFace, cFaceGlyphOffset);
  Result.Rows := ReadInt(Slot, cSlotBitmap);
  Result.Width := ReadInt(Slot, cSlotBitmap + 4);
  Result.Pitch := ReadInt(Slot, cSlotBitmap + 8);
  Result.Buffer := PByte(ReadPtr(Slot, cSlotBitmap + 16));
  Result.PixelMode := PByte(PByte(Slot) + cSlotBitmap + 26)^;
  Result.Left := ReadInt(Slot, cSlotBitmapLeft);
  Result.Top := ReadInt(Slot, cSlotBitmapTop);
  Result.Advance := Integer(ReadLong(Slot, cSlotAdvanceX));
end;

function FtSizeInfo(AFace: TFtFace): TFtSizeInfo;
var
  Size: Pointer;
begin
  Size := ReadPtr(AFace, cFaceSizeOffset);
  // The metrics are 26.6 fixed point; ascent and descent are rounded away
  // from the baseline so the whole glyph box fits the cell.
  Result.Ascender := Integer((ReadLong(Size, cMetricsAscender) + 63) div 64);
  Result.Descender := -Integer((-ReadLong(Size, cMetricsDescender) + 63) div 64);
  Result.Height := Integer((ReadLong(Size, cMetricsHeight) + 63) div 64);
end;

end.
