unit uSdlApi;

{ The part of SDL2 the graphical host uses, bound at run time: the library is
  looked up when the program starts, so it can report a missing libSDL2 in
  plain words and the units that only map events or draw into memory do not
  depend on it. Events are kept as raw bytes and read through accessors, so
  the layout of the C union is written down in one place. }

interface

const
  SDL_INIT_VIDEO = $00000020;
  SDL_INIT_EVENTS = $00004000;

  SDL_WINDOWPOS_UNDEFINED = $1FFF0000;
  SDL_WINDOW_SHOWN = $00000004;
  SDL_WINDOW_RESIZABLE = $00000020;
  SDL_WINDOW_ALLOW_HIGHDPI = $00002000;

  SDL_RENDERER_ACCELERATED = $00000002;
  SDL_RENDERER_SOFTWARE = $00000001;
  SDL_RENDERER_PRESENTVSYNC = $00000004;

  // SDL_PIXELFORMAT_ARGB8888: bytes B, G, R, A in memory on little-endian CPUs.
  SDL_PIXELFORMAT_ARGB8888 = $16362004;
  SDL_TEXTUREACCESS_STREAMING = 1;

  SDL_QUITEVENT = $100;
  SDL_WINDOWEVENT = $200;
  SDL_KEYDOWN = $300;
  SDL_KEYUP = $301;
  SDL_TEXTINPUT = $303;
  SDL_MOUSEMOTION = $400;
  SDL_MOUSEBUTTONDOWN = $401;
  SDL_MOUSEBUTTONUP = $402;
  SDL_MOUSEWHEEL = $403;
  SDL_DROPFILE = $1000;

  SDL_WINDOWEVENT_EXPOSED = 3;
  SDL_WINDOWEVENT_RESIZED = 5;
  SDL_WINDOWEVENT_SIZE_CHANGED = 6;
  SDL_WINDOWEVENT_FOCUS_GAINED = 12;
  SDL_WINDOWEVENT_FOCUS_LOST = 13;
  SDL_WINDOWEVENT_CLOSE = 14;

  SDL_BUTTON_LEFT = 1;
  SDL_BUTTON_MIDDLE = 2;
  SDL_BUTTON_RIGHT = 3;

  KMOD_LSHIFT = $0001;
  KMOD_RSHIFT = $0002;
  KMOD_LCTRL = $0040;
  KMOD_RCTRL = $0080;
  KMOD_LALT = $0100;
  KMOD_RALT = $0200;
  KMOD_NUM = $1000;
  KMOD_MODE = $4000;

  SDL_MOUSEWHEEL_FLIPPED = 1;

type
  PSDLWindow = Pointer;
  PSDLRenderer = Pointer;
  PSDLTexture = Pointer;
  PSDLSurface = ^TSDLSurface;

  TSDLSurface = record
    Flags: Cardinal;
    Format: Pointer;
    W, H: Integer;
    Pitch: Integer;
    Pixels: Pointer;
  end;

  /// <summary>An SDL_Event: 56 bytes read through the accessors below.</summary>
  TSDLEvent = record
    Raw: array[0..55] of Byte;
  end;

  TSDLRect = record
    X, Y, W, H: Integer;
  end;

function SdlEventType(const E: TSDLEvent): Cardinal;
function SdlEventU32(const E: TSDLEvent; AOffset: Integer): Cardinal;
function SdlEventI32(const E: TSDLEvent; AOffset: Integer): Integer;
function SdlEventU8(const E: TSDLEvent; AOffset: Integer): Byte;
/// <summary>The text of an SDL_TEXTINPUT event.</summary>
function SdlEventText(const E: TSDLEvent): string;
/// <summary>The path of an SDL_DROPFILE event; the buffer is freed here (with
/// SDL_free, or with SdlDropFree when that is set).</summary>
function SdlEventDropFile(const E: TSDLEvent): string;
/// <summary>Writes the little-endian value into an event, for tests and
/// synthetic input.</summary>
procedure SdlEventSetU32(var E: TSDLEvent; AOffset: Integer; AValue: Cardinal);
procedure SdlEventSetU8(var E: TSDLEvent; AOffset: Integer; AValue: Byte);
procedure SdlEventSetText(var E: TSDLEvent; const AText: string);

var
  /// <summary>Frees the file name buffer of a drop event instead of SDL_free;
  /// for events that did not come from SDL.</summary>
  SdlDropFree: procedure(AMemory: Pointer);
  SDL_Init: function(AFlags: Cardinal): Integer; cdecl;
  SDL_Quit: procedure; cdecl;
  SDL_GetError: function: PAnsiChar; cdecl;
  SDL_SetHint: function(AName, AValue: PAnsiChar): Integer; cdecl;
  SDL_CreateWindow: function(ATitle: PAnsiChar; X, Y, W, H: Integer;
    AFlags: Cardinal): PSDLWindow; cdecl;
  SDL_DestroyWindow: procedure(AWindow: PSDLWindow); cdecl;
  SDL_SetWindowTitle: procedure(AWindow: PSDLWindow; ATitle: PAnsiChar); cdecl;
  SDL_RestoreWindow: procedure(AWindow: PSDLWindow); cdecl;
  SDL_RaiseWindow: procedure(AWindow: PSDLWindow); cdecl;
  SDL_SetWindowMinimumSize: procedure(AWindow: PSDLWindow; W, H: Integer); cdecl;
  SDL_GetWindowSize: procedure(AWindow: PSDLWindow; out W, H: Integer); cdecl;
  SDL_CreateRenderer: function(AWindow: PSDLWindow; AIndex: Integer;
    AFlags: Cardinal): PSDLRenderer; cdecl;
  SDL_DestroyRenderer: procedure(ARenderer: PSDLRenderer); cdecl;
  SDL_GetRendererOutputSize: function(ARenderer: PSDLRenderer;
    out W, H: Integer): Integer; cdecl;
  SDL_SetRenderDrawColor: function(ARenderer: PSDLRenderer;
    R, G, B, A: Byte): Integer; cdecl;
  SDL_RenderClear: function(ARenderer: PSDLRenderer): Integer; cdecl;
  SDL_RenderCopy: function(ARenderer: PSDLRenderer; ATexture: PSDLTexture;
    ASrc, ADst: Pointer): Integer; cdecl;
  SDL_RenderPresent: procedure(ARenderer: PSDLRenderer); cdecl;
  SDL_CreateTexture: function(ARenderer: PSDLRenderer; AFormat: Cardinal;
    AAccess, W, H: Integer): PSDLTexture; cdecl;
  SDL_UpdateTexture: function(ATexture: PSDLTexture; ARect: Pointer;
    APixels: Pointer; APitch: Integer): Integer; cdecl;
  SDL_DestroyTexture: procedure(ATexture: PSDLTexture); cdecl;
  SDL_PollEvent: function(var AEvent: TSDLEvent): Integer; cdecl;
  SDL_WaitEventTimeout: function(var AEvent: TSDLEvent; ATimeoutMs: Integer): Integer; cdecl;
  SDL_StartTextInput: procedure; cdecl;
  SDL_StopTextInput: procedure; cdecl;
  SDL_SetTextInputRect: procedure(var ARect: TSDLRect); cdecl;
  SDL_GetWindowID: function(AWindow: PSDLWindow): Cardinal; cdecl;
  SDL_GetModState: function: Integer; cdecl;
  SDL_GetClipboardText: function: PAnsiChar; cdecl;
  SDL_SetClipboardText: function(AText: PAnsiChar): Integer; cdecl;
  SDL_free: procedure(AMemory: Pointer); cdecl;
  SDL_GetTicks: function: Cardinal; cdecl;
  SDL_GetDisplayDPI: function(ADisplay: Integer; out ADdpi, AHdpi,
    AVdpi: Single): Integer; cdecl;
  SDL_LoadBMP_RW: function(ASource: Pointer; AFreeSource: Integer): PSDLSurface; cdecl;
  SDL_RWFromFile: function(AFile, AMode: PAnsiChar): Pointer; cdecl;
  SDL_ConvertSurfaceFormat: function(ASurface: PSDLSurface; AFormat: Cardinal;
    AFlags: Cardinal): PSDLSurface; cdecl;
  SDL_FreeSurface: procedure(ASurface: PSDLSurface); cdecl;
  SDL_PushEvent: function(var AEvent: TSDLEvent): Integer; cdecl;

  // SDL2_image, optional: nil when the library is not installed.
  IMG_Load: function(AFile: PAnsiChar): PSDLSurface; cdecl;

/// <summary>Loads libSDL2; False and AError set when it is not there.</summary>
function LoadSdl(out AError: string): Boolean;
function SdlLoaded: Boolean;
/// <summary>The last SDL error as text.</summary>
function SdlErrorText: string;
/// <summary>True when SDL2_image was found.</summary>
function SdlImageLoaded: Boolean;

implementation

uses
  System.SysUtils, uPlatformInfo;

var
  GSdl: NativeUInt;
  GImg: NativeUInt;

function SdlEventType(const E: TSDLEvent): Cardinal;
begin
  Result := SdlEventU32(E, 0);
end;

function SdlEventU32(const E: TSDLEvent; AOffset: Integer): Cardinal;
begin
  Result := Cardinal(E.Raw[AOffset]) or (Cardinal(E.Raw[AOffset + 1]) shl 8) or
    (Cardinal(E.Raw[AOffset + 2]) shl 16) or (Cardinal(E.Raw[AOffset + 3]) shl 24);
end;

function SdlEventI32(const E: TSDLEvent; AOffset: Integer): Integer;
begin
  Result := Integer(SdlEventU32(E, AOffset));
end;

function SdlEventU8(const E: TSDLEvent; AOffset: Integer): Byte;
begin
  Result := E.Raw[AOffset];
end;

procedure SdlEventSetU32(var E: TSDLEvent; AOffset: Integer; AValue: Cardinal);
begin
  E.Raw[AOffset] := Byte(AValue);
  E.Raw[AOffset + 1] := Byte(AValue shr 8);
  E.Raw[AOffset + 2] := Byte(AValue shr 16);
  E.Raw[AOffset + 3] := Byte(AValue shr 24);
end;

procedure SdlEventSetU8(var E: TSDLEvent; AOffset: Integer; AValue: Byte);
begin
  E.Raw[AOffset] := AValue;
end;

procedure SdlEventSetText(var E: TSDLEvent; const AText: string);
var
  Bytes: TBytes;
  I, N: Integer;
begin
  Bytes := TEncoding.UTF8.GetBytes(AText);
  N := Length(Bytes);
  if N > 31 then
    N := 31;
  for I := 0 to 31 do
    E.Raw[12 + I] := 0;
  for I := 0 to N - 1 do
    E.Raw[12 + I] := Bytes[I];
end;

function SdlEventText(const E: TSDLEvent): string;
var
  Bytes: TBytes;
  N: Integer;
begin
  N := 0;
  while (N < 32) and (E.Raw[12 + N] <> 0) do
    Inc(N);
  SetLength(Bytes, N);
  if N > 0 then
    Move(E.Raw[12], Bytes[0], N);
  Result := TEncoding.UTF8.GetString(Bytes);
end;

function SdlEventDropFile(const E: TSDLEvent): string;
var
  P: PAnsiChar;
  Address: NativeUInt;
  I: Integer;
begin
  Address := 0;
  // The file name pointer follows the 8-byte header (type, timestamp).
  for I := 7 downto 0 do
    Address := (Address shl 8) or E.Raw[8 + I];
  P := PAnsiChar(Address);
  if P = nil then
    Exit('');
  Result := UTF8ToString(P);
  if Assigned(SdlDropFree) then
    SdlDropFree(P)
  else if Assigned(SDL_free) then
    SDL_free(P);
end;

function Bind(AHandle: NativeUInt; const AName: string; var AProc): Boolean;
begin
  Pointer(AProc) := PlatformGetProc(AHandle, AName);
  Result := Pointer(AProc) <> nil;
end;

function LoadSdl(out AError: string): Boolean;
const
  cNames: array[0..2] of string = ('libSDL2-2.0.so.0', 'libSDL2.so', 'SDL2.dll');
var
  I: Integer;
  Missing: string;
begin
  AError := '';
  if GSdl <> 0 then
    Exit(True);
  for I := Low(cNames) to High(cNames) do
  begin
    GSdl := PlatformLoadLibrary(cNames[I]);
    if GSdl <> 0 then
      Break;
  end;
  if GSdl = 0 then
  begin
    AError := 'SDL2 library not found (' + PlatformLibraryError + ')';
    Exit(False);
  end;
  Missing := '';
  if not Bind(GSdl, 'SDL_Init', SDL_Init) then Missing := 'SDL_Init';
  Bind(GSdl, 'SDL_Quit', SDL_Quit);
  Bind(GSdl, 'SDL_GetError', SDL_GetError);
  Bind(GSdl, 'SDL_SetHint', SDL_SetHint);
  Bind(GSdl, 'SDL_CreateWindow', SDL_CreateWindow);
  Bind(GSdl, 'SDL_DestroyWindow', SDL_DestroyWindow);
  Bind(GSdl, 'SDL_SetWindowTitle', SDL_SetWindowTitle);
  Bind(GSdl, 'SDL_RestoreWindow', SDL_RestoreWindow);
  Bind(GSdl, 'SDL_RaiseWindow', SDL_RaiseWindow);
  Bind(GSdl, 'SDL_SetWindowMinimumSize', SDL_SetWindowMinimumSize);
  Bind(GSdl, 'SDL_GetWindowSize', SDL_GetWindowSize);
  Bind(GSdl, 'SDL_CreateRenderer', SDL_CreateRenderer);
  Bind(GSdl, 'SDL_DestroyRenderer', SDL_DestroyRenderer);
  Bind(GSdl, 'SDL_GetRendererOutputSize', SDL_GetRendererOutputSize);
  Bind(GSdl, 'SDL_SetRenderDrawColor', SDL_SetRenderDrawColor);
  Bind(GSdl, 'SDL_RenderClear', SDL_RenderClear);
  Bind(GSdl, 'SDL_RenderCopy', SDL_RenderCopy);
  Bind(GSdl, 'SDL_RenderPresent', SDL_RenderPresent);
  Bind(GSdl, 'SDL_CreateTexture', SDL_CreateTexture);
  Bind(GSdl, 'SDL_UpdateTexture', SDL_UpdateTexture);
  Bind(GSdl, 'SDL_DestroyTexture', SDL_DestroyTexture);
  Bind(GSdl, 'SDL_PollEvent', SDL_PollEvent);
  Bind(GSdl, 'SDL_WaitEventTimeout', SDL_WaitEventTimeout);
  Bind(GSdl, 'SDL_StartTextInput', SDL_StartTextInput);
  Bind(GSdl, 'SDL_StopTextInput', SDL_StopTextInput);
  Bind(GSdl, 'SDL_SetTextInputRect', SDL_SetTextInputRect);
  Bind(GSdl, 'SDL_GetWindowID', SDL_GetWindowID);
  Bind(GSdl, 'SDL_GetModState', SDL_GetModState);
  Bind(GSdl, 'SDL_GetClipboardText', SDL_GetClipboardText);
  Bind(GSdl, 'SDL_SetClipboardText', SDL_SetClipboardText);
  Bind(GSdl, 'SDL_free', SDL_free);
  Bind(GSdl, 'SDL_GetTicks', SDL_GetTicks);
  Bind(GSdl, 'SDL_GetDisplayDPI', SDL_GetDisplayDPI);
  Bind(GSdl, 'SDL_LoadBMP_RW', SDL_LoadBMP_RW);
  Bind(GSdl, 'SDL_RWFromFile', SDL_RWFromFile);
  Bind(GSdl, 'SDL_ConvertSurfaceFormat', SDL_ConvertSurfaceFormat);
  Bind(GSdl, 'SDL_FreeSurface', SDL_FreeSurface);
  Bind(GSdl, 'SDL_PushEvent', SDL_PushEvent);
  if (Missing = '') and (not Assigned(SDL_CreateWindow) or not Assigned(SDL_CreateRenderer) or
     not Assigned(SDL_CreateTexture) or not Assigned(SDL_UpdateTexture) or
     not Assigned(SDL_WaitEventTimeout) or not Assigned(SDL_RenderCopy)) then
    Missing := 'window or renderer functions';
  if Missing <> '' then
  begin
    AError := 'SDL2 library is incomplete (' + Missing + ' missing)';
    PlatformFreeLibrary(GSdl);
    GSdl := 0;
    Exit(False);
  end;
  GImg := PlatformLoadLibrary('libSDL2_image-2.0.so.0');
  if (GImg <> 0) and not Bind(GImg, 'IMG_Load', IMG_Load) then
  begin
    PlatformFreeLibrary(GImg);
    GImg := 0;
  end;
  Result := True;
end;

function SdlLoaded: Boolean;
begin
  Result := GSdl <> 0;
end;

function SdlImageLoaded: Boolean;
begin
  Result := (GImg <> 0) and Assigned(IMG_Load);
end;

function SdlErrorText: string;
begin
  if Assigned(SDL_GetError) then
    Result := UTF8ToString(SDL_GetError)
  else
    Result := '';
end;

end.
