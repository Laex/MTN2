unit uPdfium;

{ Thin binding to the PDFium C API (pdfium.dll or libpdfium.so next to the plugin): open a
  document, render a part of a page into a BGRA buffer, read the text of a
  page. The library is loaded on first use; PdfiumAvailable tells whether that
  worked, so the plugin can step aside when the library is missing. }

interface

uses
  System.SysUtils;

type
  EPdfium = class(Exception);

  TPdfDocument = class
  private
    FDoc: Pointer;
    FPageCount: Integer;
  public
    /// <summary>Opens APath; raises EPdfium when the file cannot be read, is
    /// damaged or needs a password.</summary>
    constructor Create(const APath: string);
    destructor Destroy; override;
    function PageSize(AIndex: Integer; out AWidth, AHeight: Double): Boolean;
    /// <summary>Draws page AIndex scaled to AScaledW x AScaledH pixels into a
    /// frame of AFrameW x AFrameH pixels. (AStartX, AStartY) is where the page's
    /// top-left corner lands in the frame: zero, or negative when the page is
    /// scrolled. Result is BGRA, rows top to bottom, no padding.</summary>
    function Render(AIndex, AFrameW, AFrameH, AStartX, AStartY,
      AScaledW, AScaledH: Integer): TBytes;
    function PageText(AIndex: Integer): string;
    property PageCount: Integer read FPageCount;
  end;

/// <summary>True when the PDFium library was found and initialised.</summary>
function PdfiumAvailable: Boolean;

/// <summary>Text of the first AMaxPages pages (at most AMaxChars characters),
/// pages separated by a rule line; '' when the document has no text.</summary>
function PdfDocumentText(ADoc: TPdfDocument; AMaxPages, AMaxChars: Integer): string;

procedure PdfiumShutdown;

implementation

uses
  System.Math
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ELSE}, Posix.Dlfcn{$ENDIF};

type
  TInitLibrary = procedure; cdecl;
  TLoadDocument = function(APath, APassword: PAnsiChar): Pointer; cdecl;
  TCloseDocument = procedure(ADoc: Pointer); cdecl;
  TGetPageCount = function(ADoc: Pointer): Integer; cdecl;
  TLoadPage = function(ADoc: Pointer; AIndex: Integer): Pointer; cdecl;
  TClosePage = procedure(APage: Pointer); cdecl;
  TGetPageDim = function(APage: Pointer): Double; cdecl;
  TBitmapCreate = function(AWidth, AHeight, AAlpha: Integer): Pointer; cdecl;
  TBitmapFill = procedure(ABitmap: Pointer; ALeft, ATop, AWidth, AHeight: Integer;
    AColor: Cardinal); cdecl;
  TBitmapGetBuffer = function(ABitmap: Pointer): Pointer; cdecl;
  TBitmapGetStride = function(ABitmap: Pointer): Integer; cdecl;
  TBitmapDestroy = procedure(ABitmap: Pointer); cdecl;
  TRenderPageBitmap = procedure(ABitmap, APage: Pointer; AStartX, AStartY, ASizeX, ASizeY,
    ARotate, AFlags: Integer); cdecl;
  TTextLoadPage = function(APage: Pointer): Pointer; cdecl;
  TTextClosePage = procedure(ATextPage: Pointer); cdecl;
  TTextCountChars = function(ATextPage: Pointer): Integer; cdecl;
  TTextGetText = function(ATextPage: Pointer; AStart, ACount: Integer;
    AResult: PWord): Integer; cdecl;

const
  cRenderAnnotations = 1;
  cRenderLcdText = 2;
  cMaxRenderSide = 16384;

var
  GLib: NativeUInt;
  GTried: Boolean;
  GReady: Boolean;
  GLoadDocument: TLoadDocument;
  GCloseDocument: TCloseDocument;
  GGetPageCount: TGetPageCount;
  GLoadPage: TLoadPage;
  GClosePage: TClosePage;
  GGetPageWidth, GGetPageHeight: TGetPageDim;
  GBitmapCreate: TBitmapCreate;
  GBitmapFill: TBitmapFill;
  GBitmapGetBuffer: TBitmapGetBuffer;
  GBitmapGetStride: TBitmapGetStride;
  GBitmapDestroy: TBitmapDestroy;
  GRenderPageBitmap: TRenderPageBitmap;
  GTextLoadPage: TTextLoadPage;
  GTextClosePage: TTextClosePage;
  GTextCountChars: TTextCountChars;
  GTextGetText: TTextGetText;

{ The folder the plugin library was loaded from. }
function ModuleDir: string;
{$IFDEF MSWINDOWS}
var
  Buf: array[0..MAX_PATH] of Char;
begin
  GetModuleFileName(HInstance, Buf, Length(Buf));
  Result := ExtractFilePath(string(PChar(@Buf[0])));
end;
{$ELSE}
var
  Info: dl_info;
begin
  Result := '';
  if (dladdr(UInt64(NativeUInt(@ModuleDir)), Info) <> 0) and (Info.dli_fname <> nil) then
    Result := ExtractFilePath(UTF8ToString(Info.dli_fname));
end;
{$ENDIF}

function LoadPdfiumLibrary: Boolean;
begin
  {$IFDEF MSWINDOWS}
  GLib := LoadLibraryEx(PChar(ModuleDir + 'pdfium.dll'), 0, LOAD_WITH_ALTERED_SEARCH_PATH);
  {$ELSE}
  GLib := NativeUInt(dlopen(PAnsiChar(UTF8String(ModuleDir + 'libpdfium.so')), RTLD_NOW));
  if GLib = 0 then
    GLib := NativeUInt(dlopen('libpdfium.so', RTLD_NOW));
  {$ENDIF}
  Result := GLib <> 0;
end;

function Proc(const AName: AnsiString): Pointer;
begin
  {$IFDEF MSWINDOWS}
  Result := GetProcAddress(HMODULE(GLib), PAnsiChar(AName));
  {$ELSE}
  Result := dlsym(GLib, PAnsiChar(AName));
  {$ENDIF}
  if Result = nil then
    raise EPdfium.CreateFmt('the PDFium library has no %s', [string(AName)]);
end;

function PdfiumAvailable: Boolean;
var
  Init: TInitLibrary;
begin
  if GTried then
    Exit(GReady);
  GTried := True;
  try
    if not LoadPdfiumLibrary then
      Exit(False);
    GLoadDocument := Proc('FPDF_LoadDocument');
    GCloseDocument := Proc('FPDF_CloseDocument');
    GGetPageCount := Proc('FPDF_GetPageCount');
    GLoadPage := Proc('FPDF_LoadPage');
    GClosePage := Proc('FPDF_ClosePage');
    GGetPageWidth := Proc('FPDF_GetPageWidth');
    GGetPageHeight := Proc('FPDF_GetPageHeight');
    GBitmapCreate := Proc('FPDFBitmap_Create');
    GBitmapFill := Proc('FPDFBitmap_FillRect');
    GBitmapGetBuffer := Proc('FPDFBitmap_GetBuffer');
    GBitmapGetStride := Proc('FPDFBitmap_GetStride');
    GBitmapDestroy := Proc('FPDFBitmap_Destroy');
    GRenderPageBitmap := Proc('FPDF_RenderPageBitmap');
    GTextLoadPage := Proc('FPDFText_LoadPage');
    GTextClosePage := Proc('FPDFText_ClosePage');
    GTextCountChars := Proc('FPDFText_CountChars');
    GTextGetText := Proc('FPDFText_GetText');
    Init := Proc('FPDF_InitLibrary');
    Init;
    GReady := True;
  except
    GReady := False;
  end;
  Result := GReady;
end;

procedure PdfiumShutdown;
var
  Destroy_: TInitLibrary;
begin
  if GReady and (GLib <> 0) then
  begin
    try
      Destroy_ := Proc('FPDF_DestroyLibrary');
      Destroy_;
    except
      // The library is unloaded with the process anyway.
    end;
  end;
  GReady := False;
end;

constructor TPdfDocument.Create(const APath: string);
var
  PathU: UTF8String;
begin
  inherited Create;
  if not PdfiumAvailable then
    raise EPdfium.Create('the PDFium library is not available');
  PathU := UTF8String(APath);
  FDoc := GLoadDocument(PAnsiChar(PathU), nil);
  if FDoc = nil then
    raise EPdfium.Create('the document cannot be opened');
  FPageCount := GGetPageCount(FDoc);
  if FPageCount <= 0 then
  begin
    GCloseDocument(FDoc);
    FDoc := nil;
    raise EPdfium.Create('the document has no pages');
  end;
end;

destructor TPdfDocument.Destroy;
begin
  if FDoc <> nil then
    GCloseDocument(FDoc);
  inherited;
end;

function TPdfDocument.PageSize(AIndex: Integer; out AWidth, AHeight: Double): Boolean;
var
  Page: Pointer;
begin
  Result := False;
  AWidth := 0;
  AHeight := 0;
  if (AIndex < 0) or (AIndex >= FPageCount) then
    Exit;
  Page := GLoadPage(FDoc, AIndex);
  if Page = nil then
    Exit;
  try
    AWidth := GGetPageWidth(Page);
    AHeight := GGetPageHeight(Page);
    Result := (AWidth > 0) and (AHeight > 0);
  finally
    GClosePage(Page);
  end;
end;

function TPdfDocument.Render(AIndex, AFrameW, AFrameH, AStartX, AStartY,
  AScaledW, AScaledH: Integer): TBytes;
var
  Page, Bmp, Buf: Pointer;
  Stride, Y: Integer;
begin
  SetLength(Result, 0);
  if (AIndex < 0) or (AIndex >= FPageCount) or (AFrameW <= 0) or (AFrameH <= 0) or
     (AScaledW <= 0) or (AScaledH <= 0) or (AScaledW > cMaxRenderSide) or
     (AScaledH > cMaxRenderSide) then
    Exit;
  Page := GLoadPage(FDoc, AIndex);
  if Page = nil then
    Exit;
  try
    Bmp := GBitmapCreate(AFrameW, AFrameH, 0);
    if Bmp = nil then
      Exit;
    try
      GBitmapFill(Bmp, 0, 0, AFrameW, AFrameH, $FFFFFFFF);
      GRenderPageBitmap(Bmp, Page, AStartX, AStartY, AScaledW, AScaledH, 0,
        cRenderAnnotations or cRenderLcdText);
      Buf := GBitmapGetBuffer(Bmp);
      Stride := GBitmapGetStride(Bmp);
      SetLength(Result, AFrameW * AFrameH * 4);
      for Y := 0 to AFrameH - 1 do
        Move(PByte(Buf)[Y * Stride], Result[Y * AFrameW * 4], AFrameW * 4);
      // The bitmap has no alpha channel; the host expects an opaque picture.
      for Y := 0 to AFrameW * AFrameH - 1 do
        Result[Y * 4 + 3] := $FF;
    finally
      GBitmapDestroy(Bmp);
    end;
  finally
    GClosePage(Page);
  end;
end;

function TPdfDocument.PageText(AIndex: Integer): string;
var
  Page, Text: Pointer;
  Count, Got: Integer;
  Buf: TArray<Word>;
begin
  Result := '';
  if (AIndex < 0) or (AIndex >= FPageCount) then
    Exit;
  Page := GLoadPage(FDoc, AIndex);
  if Page = nil then
    Exit;
  try
    Text := GTextLoadPage(Page);
    if Text = nil then
      Exit;
    try
      Count := GTextCountChars(Text);
      if Count <= 0 then
        Exit;
      SetLength(Buf, Count + 1);
      Got := GTextGetText(Text, 0, Count, @Buf[0]);
      if Got > 1 then
        SetString(Result, PWideChar(@Buf[0]), Got - 1);
    finally
      GTextClosePage(Text);
    end;
  finally
    GClosePage(Page);
  end;
end;

function PdfDocumentText(ADoc: TPdfDocument; AMaxPages, AMaxChars: Integer): string;
var
  I: Integer;
  SB: TStringBuilder;
  T: string;
begin
  Result := '';
  SB := TStringBuilder.Create;
  try
    for I := 0 to Min(ADoc.PageCount, AMaxPages) - 1 do
    begin
      T := Trim(ADoc.PageText(I));
      if T = '' then
        Continue;
      if SB.Length > 0 then
        SB.Append(#13#10).Append(StringOfChar('-', 20)).Append(Format(' %d ', [I + 1]))
          .Append(StringOfChar('-', 20)).Append(#13#10);
      SB.Append(T);
      if SB.Length >= AMaxChars then
        Break;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
