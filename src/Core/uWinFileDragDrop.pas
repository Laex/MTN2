unit uWinFileDragDrop;

{ OLE CF_HDROP drag-out for FMX (Explorer and other shell targets).
  Drag-in uses FMX TWinDropTarget; this unit only starts DoDragDrop with real
  HDROP data — stock FMX BeginDragDrop does not export CF_HDROP.

  CROSS-PLATFORM (Этап 23): Windows OLE drag & drop, no portable concept to
  fall back to. Caller (uDualPanelWindow.pas) should treat this as an
  optional enhancement -- no-op / feature-detect on other platforms rather
  than something to reimplement per-OS. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Winapi.Windows, Winapi.ActiveX, Winapi.ShellAPI;

/// <summary>True while OleDragLocalFiles is inside DoDragDrop (self-drop detect).</summary>
function OleFileDragActive: Boolean;

/// <summary>Blocking OLE drag of local filesystem paths. Returns DROPEFFECT_*.</summary>
function OleDragLocalFiles(const APaths: TArray<string>;
  AAllowedEffects: LongInt = DROPEFFECT_COPY or DROPEFFECT_MOVE): LongInt;

/// <summary>file:// URIs → absolute local paths (skips archives / non-file).</summary>
function FileUrisToLocalPaths(const AUris: TArray<string>): TArray<string>;

/// <summary>Local paths → file:// URIs.</summary>
function LocalPathsToFileUris(const APaths: TArray<string>): TArray<string>;

/// <summary>Serialize panel URIs for the MTN2 clipboard format.</summary>
function EncodeMtnFileClip(const AUris: TArray<string>; ACut: Boolean): string;
/// <summary>Parse EncodeMtnFileClip text. False if the payload is empty/unknown.</summary>
function DecodeMtnFileClip(const AText: string; out AUris: TArray<string>;
  out ACut: Boolean): Boolean;

/// <summary>Put panel items on the OLE clipboard: CF_HDROP (Explorer) plus
/// MTN2 URIs so zip/VFS copy still pastes inside the host.</summary>
function ClipboardSetPanelItems(const ALocalPaths, AUris: TArray<string>;
  ACut: Boolean): Boolean;
/// <summary>Read panel items. Prefers the MTN2 URI list, then CF_HDROP.</summary>
function ClipboardGetPanelItems(out ALocalPaths, AUris: TArray<string>;
  out ACut: Boolean): Boolean;
function ClipboardHasPanelItems: Boolean;
procedure ClipboardClearPanelItems;

implementation

uses
  System.Win.ComObj,
  uVfsTypes;

var
  GOleFileDragDepth: Integer = 0;

function OleFileDragActive: Boolean;
begin
  Result := GOleFileDragDepth > 0;
end;

function FileUrisToLocalPaths(const AUris: TArray<string>): TArray<string>;
var
  U, Path: string;
  N: Integer;
begin
  SetLength(Result, 0);
  for U in AUris do
  begin
    if U = '' then
      Continue;
    if HasArchiveChain(U) or IsFindUri(U) or IsSystemFoldersUri(U) then
      Continue;
    Path := FileUriToPath(U);
    if Path = '' then
      Continue;
    if not (LocalPathIsFile(Path) or LocalPathIsDirectory(Path)) then
      Continue;
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N] := Path;
  end;
end;

function LocalPathsToFileUris(const APaths: TArray<string>): TArray<string>;
var
  P: string;
  N: Integer;
begin
  SetLength(Result, 0);
  for P in APaths do
  begin
    if Trim(P) = '' then
      Continue;
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N] := PathToFileUri(P);
  end;
end;

type
  TDropFilesRec = record
    pFiles: UINT;
    pt: TPoint;
    fNC: BOOL;
    fWide: BOOL;
  end;
  PDropFilesRec = ^TDropFilesRec;

function BuildHDrop(const APaths: TArray<string>): HGLOBAL;
var
  I, Bytes, Offset: Integer;
  Drop: PDropFilesRec;
  Dest: PWideChar;
  Path: string;
begin
  Result := 0;
  if Length(APaths) = 0 then
    Exit;
  Bytes := SizeOf(TDropFilesRec);
  for I := 0 to High(APaths) do
    Inc(Bytes, (Length(APaths[I]) + 1) * SizeOf(WideChar));
  Inc(Bytes, SizeOf(WideChar)); // final #0
  Result := GlobalAlloc(GHND, Bytes);
  if Result = 0 then
    Exit;
  Drop := GlobalLock(Result);
  try
    FillChar(Drop^, Bytes, 0);
    Drop.pFiles := SizeOf(TDropFilesRec);
    Drop.fWide := True;
    Dest := PWideChar(PByte(Drop) + Drop.pFiles);
    Offset := 0;
    for I := 0 to High(APaths) do
    begin
      Path := APaths[I];
      if Path = '' then
        Continue;
      Move(PWideChar(Path)^, Dest[Offset], Length(Path) * SizeOf(WideChar));
      Inc(Offset, Length(Path));
      Dest[Offset] := #0;
      Inc(Offset);
    end;
    Dest[Offset] := #0;
  finally
    GlobalUnlock(Result);
  end;
end;

type
  TEnumFormatEtc = class(TInterfacedObject, IEnumFormatEtc)
  private
    FIndex: Integer;
    FFmt: TFormatEtc;
  public
    constructor Create(const AFmt: TFormatEtc; AIndex: Integer = 0);
    function Next(celt: LongInt; out elt; pceltFetched: PLongInt): HRESULT; stdcall;
    function Skip(celt: LongInt): HRESULT; stdcall;
    function Reset: HRESULT; stdcall;
    function Clone(out Enum: IEnumFormatEtc): HRESULT; stdcall;
  end;

  TFileDataObject = class(TInterfacedObject, IDataObject, IDropSource)
  private
    FFmt: TFormatEtc;
    FMedium: TStgMedium;
    FHasData: Boolean;
  public
    constructor Create(AHdrop: HGLOBAL);
    destructor Destroy; override;
    { IDropSource }
    function QueryContinueDrag(fEscapePressed: BOOL; grfKeyState: LongInt): HRESULT; stdcall;
    function GiveFeedback(dwEffect: LongInt): HRESULT; stdcall;
    { IDataObject }
    function GetData(const FormatEtcIn: TFormatEtc; out Medium: TStgMedium): HRESULT; stdcall;
    function GetDataHere(const FormatEtc: TFormatEtc; out Medium: TStgMedium): HRESULT; stdcall;
    function QueryGetData(const FormatEtc: TFormatEtc): HRESULT; stdcall;
    function GetCanonicalFormatEtc(const FormatEtc: TFormatEtc;
      out FormatEtcOut: TFormatEtc): HRESULT; stdcall;
    function SetData(const FormatEtc: TFormatEtc; var Medium: TStgMedium;
      fRelease: BOOL): HRESULT; stdcall;
    function EnumFormatEtc(dwDirection: LongInt;
      out EnumFormatEtc: IEnumFormatEtc): HRESULT; stdcall;
    function DAdvise(const FormatEtc: TFormatEtc; advf: LongInt;
      const AdvSink: IAdviseSink; out dwConnection: LongInt): HRESULT; stdcall;
    function DUnadvise(dwConnection: LongInt): HRESULT; stdcall;
    function EnumDAdvise(out EnumAdvise: IEnumStatData): HRESULT; stdcall;
  end;

  TEnumFormatList = class(TInterfacedObject, IEnumFormatEtc)
  private
    FItems: TArray<TFormatEtc>;
    FIndex: Integer;
  public
    constructor Create(const AItems: TArray<TFormatEtc>; AIndex: Integer = 0);
    function Next(celt: LongInt; out elt; pceltFetched: PLongInt): HRESULT; stdcall;
    function Skip(celt: LongInt): HRESULT; stdcall;
    function Reset: HRESULT; stdcall;
    function Clone(out Enum: IEnumFormatEtc): HRESULT; stdcall;
  end;

  TPanelClipDataObject = class(TInterfacedObject, IDataObject)
  private
    FHdrop: HGLOBAL;
    FEffect: HGLOBAL;
    FUris: HGLOBAL;
    function MatchHandle(AFormat: TClipFormat): HGLOBAL;
  public
    constructor Create(AHdrop, AEffect, AUris: HGLOBAL);
    destructor Destroy; override;
    function GetData(const FormatEtcIn: TFormatEtc; out Medium: TStgMedium): HRESULT; stdcall;
    function GetDataHere(const FormatEtc: TFormatEtc; out Medium: TStgMedium): HRESULT; stdcall;
    function QueryGetData(const FormatEtc: TFormatEtc): HRESULT; stdcall;
    function GetCanonicalFormatEtc(const FormatEtc: TFormatEtc;
      out FormatEtcOut: TFormatEtc): HRESULT; stdcall;
    function SetData(const FormatEtc: TFormatEtc; var Medium: TStgMedium;
      fRelease: BOOL): HRESULT; stdcall;
    function EnumFormatEtc(dwDirection: LongInt;
      out EnumFormatEtc: IEnumFormatEtc): HRESULT; stdcall;
    function DAdvise(const FormatEtc: TFormatEtc; advf: LongInt;
      const AdvSink: IAdviseSink; out dwConnection: LongInt): HRESULT; stdcall;
    function DUnadvise(dwConnection: LongInt): HRESULT; stdcall;
    function EnumDAdvise(out EnumAdvise: IEnumStatData): HRESULT; stdcall;
  end;

var
  GCfPreferredDropEffect: TClipFormat = 0;
  GCfMtnFileUris: TClipFormat = 0;

constructor TEnumFormatEtc.Create(const AFmt: TFormatEtc; AIndex: Integer);
begin
  inherited Create;
  FFmt := AFmt;
  FIndex := AIndex;
end;

function TEnumFormatEtc.Next(celt: LongInt; out elt; pceltFetched: PLongInt): HRESULT;
var
  Dest: PFormatEtc;
  N: Integer;
begin
  N := 0;
  Dest := @elt;
  if (celt > 0) and (FIndex = 0) then
  begin
    Dest^ := FFmt;
    Inc(FIndex);
    N := 1;
  end;
  if pceltFetched <> nil then
    pceltFetched^ := N;
  if N = celt then
    Result := S_OK
  else
    Result := S_FALSE;
end;

function TEnumFormatEtc.Skip(celt: LongInt): HRESULT;
begin
  Inc(FIndex, celt);
  if FIndex > 1 then
    Result := S_FALSE
  else
    Result := S_OK;
end;

function TEnumFormatEtc.Reset: HRESULT;
begin
  FIndex := 0;
  Result := S_OK;
end;

function TEnumFormatEtc.Clone(out Enum: IEnumFormatEtc): HRESULT;
begin
  Enum := TEnumFormatEtc.Create(FFmt, FIndex);
  Result := S_OK;
end;

constructor TFileDataObject.Create(AHdrop: HGLOBAL);
begin
  inherited Create;
  FillChar(FFmt, SizeOf(FFmt), 0);
  FFmt.cfFormat := CF_HDROP;
  FFmt.dwAspect := DVASPECT_CONTENT;
  FFmt.lindex := -1;
  FFmt.tymed := TYMED_HGLOBAL;
  FillChar(FMedium, SizeOf(FMedium), 0);
  FMedium.tymed := TYMED_HGLOBAL;
  FMedium.hGlobal := AHdrop;
  FMedium.unkForRelease := nil;
  FHasData := AHdrop <> 0;
end;

destructor TFileDataObject.Destroy;
begin
  if FHasData and (FMedium.hGlobal <> 0) then
    ReleaseStgMedium(FMedium);
  inherited;
end;

function TFileDataObject.QueryContinueDrag(fEscapePressed: BOOL;
  grfKeyState: LongInt): HRESULT;
begin
  if fEscapePressed then
    Exit(DRAGDROP_S_CANCEL);
  if (grfKeyState and (MK_LBUTTON or MK_RBUTTON)) = 0 then
    Exit(DRAGDROP_S_DROP);
  Result := S_OK;
end;

function TFileDataObject.GiveFeedback(dwEffect: LongInt): HRESULT;
begin
  Result := DRAGDROP_S_USEDEFAULTCURSORS;
end;

function TFileDataObject.QueryGetData(const FormatEtc: TFormatEtc): HRESULT;
begin
  if not FHasData then
    Exit(E_FAIL);
  if (FormatEtc.cfFormat = CF_HDROP) and
     ((FormatEtc.tymed and TYMED_HGLOBAL) <> 0) then
    Result := S_OK
  else
    Result := DV_E_FORMATETC;
end;

function TFileDataObject.GetData(const FormatEtcIn: TFormatEtc;
  out Medium: TStgMedium): HRESULT;
var
  Size: SIZE_T;
  Src, Dst: Pointer;
begin
  Result := QueryGetData(FormatEtcIn);
  if Result <> S_OK then
    Exit;
  Size := GlobalSize(FMedium.hGlobal);
  Medium.tymed := TYMED_HGLOBAL;
  Medium.unkForRelease := nil;
  Medium.hGlobal := GlobalAlloc(GMEM_MOVEABLE, Size);
  if Medium.hGlobal = 0 then
    Exit(E_OUTOFMEMORY);
  Src := GlobalLock(FMedium.hGlobal);
  Dst := GlobalLock(Medium.hGlobal);
  try
    Move(Src^, Dst^, Size);
  finally
    GlobalUnlock(Medium.hGlobal);
    GlobalUnlock(FMedium.hGlobal);
  end;
  Result := S_OK;
end;

function TFileDataObject.GetDataHere(const FormatEtc: TFormatEtc;
  out Medium: TStgMedium): HRESULT;
begin
  Result := E_NOTIMPL;
end;

function TFileDataObject.GetCanonicalFormatEtc(const FormatEtc: TFormatEtc;
  out FormatEtcOut: TFormatEtc): HRESULT;
begin
  FormatEtcOut := FormatEtc;
  FormatEtcOut.ptd := nil;
  Result := DATA_S_SAMEFORMATETC;
end;

function TFileDataObject.SetData(const FormatEtc: TFormatEtc; var Medium: TStgMedium;
  fRelease: BOOL): HRESULT;
begin
  Result := E_NOTIMPL;
end;

function TFileDataObject.EnumFormatEtc(dwDirection: LongInt;
  out EnumFormatEtc: IEnumFormatEtc): HRESULT;
begin
  if dwDirection <> DATADIR_GET then
    Exit(E_NOTIMPL);
  EnumFormatEtc := TEnumFormatEtc.Create(FFmt);
  Result := S_OK;
end;

function TFileDataObject.DAdvise(const FormatEtc: TFormatEtc; advf: LongInt;
  const AdvSink: IAdviseSink; out dwConnection: LongInt): HRESULT;
begin
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function TFileDataObject.DUnadvise(dwConnection: LongInt): HRESULT;
begin
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function TFileDataObject.EnumDAdvise(out EnumAdvise: IEnumStatData): HRESULT;
begin
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function OleDragLocalFiles(const APaths: TArray<string>;
  AAllowedEffects: LongInt): LongInt;
var
  HDrop: HGLOBAL;
  DataObj: IDataObject;
  DropSrc: IDropSource;
  Obj: TFileDataObject;
  Effect: LongInt;
  Hr: HRESULT;
begin
  Result := DROPEFFECT_NONE;
  if Length(APaths) = 0 then
    Exit;
  HDrop := BuildHDrop(APaths);
  if HDrop = 0 then
    Exit;
  Obj := TFileDataObject.Create(HDrop);
  DataObj := Obj;
  DropSrc := Obj;
  Effect := DROPEFFECT_NONE;
  Inc(GOleFileDragDepth);
  try
    Hr := DoDragDrop(DataObj, DropSrc, AAllowedEffects, Effect);
    if Hr = DRAGDROP_S_DROP then
      Result := Effect
    else
      Result := DROPEFFECT_NONE;
  finally
    Dec(GOleFileDragDepth);
  end;
end;

function MakeHGlobalFmt(AFormat: TClipFormat): TFormatEtc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.cfFormat := AFormat;
  Result.dwAspect := DVASPECT_CONTENT;
  Result.lindex := -1;
  Result.tymed := TYMED_HGLOBAL;
end;

function CloneHGlobal(ASrc: HGLOBAL): HGLOBAL;
var
  Size: SIZE_T;
  Src, Dst: Pointer;
begin
  Result := 0;
  if ASrc = 0 then
    Exit;
  Size := GlobalSize(ASrc);
  if Size = 0 then
    Exit;
  Result := GlobalAlloc(GMEM_MOVEABLE, Size);
  if Result = 0 then
    Exit;
  Src := GlobalLock(ASrc);
  Dst := GlobalLock(Result);
  try
    if (Src <> nil) and (Dst <> nil) then
      Move(Src^, Dst^, Size);
  finally
    GlobalUnlock(Result);
    GlobalUnlock(ASrc);
  end;
end;

function WideToHGlobal(const AText: string): HGLOBAL;
var
  Bytes: SIZE_T;
  Dest: PWideChar;
begin
  Bytes := (Length(AText) + 1) * SizeOf(WideChar);
  Result := GlobalAlloc(GHND, Bytes);
  if Result = 0 then
    Exit;
  Dest := GlobalLock(Result);
  try
    if Length(AText) > 0 then
      Move(PWideChar(AText)^, Dest^, Length(AText) * SizeOf(WideChar));
    Dest[Length(AText)] := #0;
  finally
    GlobalUnlock(Result);
  end;
end;

function DwordToHGlobal(AValue: DWORD): HGLOBAL;
var
  P: PDWORD;
begin
  Result := GlobalAlloc(GHND, SizeOf(DWORD));
  if Result = 0 then
    Exit;
  P := GlobalLock(Result);
  try
    P^ := AValue;
  finally
    GlobalUnlock(Result);
  end;
end;

function HGlobalToWide(AHandle: HGLOBAL): string;
var
  P: PWideChar;
begin
  Result := '';
  if AHandle = 0 then
    Exit;
  P := GlobalLock(AHandle);
  if P = nil then
    Exit;
  try
    Result := P;
  finally
    GlobalUnlock(AHandle);
  end;
end;

constructor TEnumFormatList.Create(const AItems: TArray<TFormatEtc>; AIndex: Integer);
begin
  inherited Create;
  FItems := Copy(AItems);
  FIndex := AIndex;
end;

function TEnumFormatList.Next(celt: LongInt; out elt; pceltFetched: PLongInt): HRESULT;
var
  Dest: PFormatEtc;
  N: Integer;
begin
  N := 0;
  Dest := @elt;
  while (N < celt) and (FIndex <= High(FItems)) do
  begin
    Dest^ := FItems[FIndex];
    Inc(Dest);
    Inc(FIndex);
    Inc(N);
  end;
  if pceltFetched <> nil then
    pceltFetched^ := N;
  if N = celt then
    Result := S_OK
  else
    Result := S_FALSE;
end;

function TEnumFormatList.Skip(celt: LongInt): HRESULT;
begin
  Inc(FIndex, celt);
  if FIndex > Length(FItems) then
    Result := S_FALSE
  else
    Result := S_OK;
end;

function TEnumFormatList.Reset: HRESULT;
begin
  FIndex := 0;
  Result := S_OK;
end;

function TEnumFormatList.Clone(out Enum: IEnumFormatEtc): HRESULT;
begin
  Enum := TEnumFormatList.Create(FItems, FIndex);
  Result := S_OK;
end;

constructor TPanelClipDataObject.Create(AHdrop, AEffect, AUris: HGLOBAL);
begin
  inherited Create;
  FHdrop := AHdrop;
  FEffect := AEffect;
  FUris := AUris;
end;

destructor TPanelClipDataObject.Destroy;
begin
  if FHdrop <> 0 then
    GlobalFree(FHdrop);
  if FEffect <> 0 then
    GlobalFree(FEffect);
  if FUris <> 0 then
    GlobalFree(FUris);
  inherited;
end;

function TPanelClipDataObject.MatchHandle(AFormat: TClipFormat): HGLOBAL;
begin
  Result := 0;
  if (AFormat = CF_HDROP) and (FHdrop <> 0) then
    Exit(FHdrop);
  if (GCfPreferredDropEffect <> 0) and (AFormat = GCfPreferredDropEffect) and
     (FEffect <> 0) then
    Exit(FEffect);
  if (GCfMtnFileUris <> 0) and (AFormat = GCfMtnFileUris) and (FUris <> 0) then
    Exit(FUris);
end;

function TPanelClipDataObject.QueryGetData(const FormatEtc: TFormatEtc): HRESULT;
begin
  if (FormatEtc.tymed and TYMED_HGLOBAL) = 0 then
    Exit(DV_E_TYMED);
  if MatchHandle(FormatEtc.cfFormat) <> 0 then
    Result := S_OK
  else
    Result := DV_E_FORMATETC;
end;

function TPanelClipDataObject.GetData(const FormatEtcIn: TFormatEtc;
  out Medium: TStgMedium): HRESULT;
var
  Handle: HGLOBAL;
begin
  Result := QueryGetData(FormatEtcIn);
  if Result <> S_OK then
    Exit;
  Handle := MatchHandle(FormatEtcIn.cfFormat);
  FillChar(Medium, SizeOf(Medium), 0);
  Medium.tymed := TYMED_HGLOBAL;
  Medium.hGlobal := CloneHGlobal(Handle);
  if Medium.hGlobal = 0 then
    Exit(E_OUTOFMEMORY);
  Result := S_OK;
end;

function TPanelClipDataObject.GetDataHere(const FormatEtc: TFormatEtc;
  out Medium: TStgMedium): HRESULT;
begin
  Result := E_NOTIMPL;
end;

function TPanelClipDataObject.GetCanonicalFormatEtc(const FormatEtc: TFormatEtc;
  out FormatEtcOut: TFormatEtc): HRESULT;
begin
  FormatEtcOut := FormatEtc;
  FormatEtcOut.ptd := nil;
  Result := DATA_S_SAMEFORMATETC;
end;

function TPanelClipDataObject.SetData(const FormatEtc: TFormatEtc; var Medium: TStgMedium;
  fRelease: BOOL): HRESULT;
begin
  Result := E_NOTIMPL;
end;

function TPanelClipDataObject.EnumFormatEtc(dwDirection: LongInt;
  out EnumFormatEtc: IEnumFormatEtc): HRESULT;
var
  Items: TArray<TFormatEtc>;
  N: Integer;
begin
  if dwDirection <> DATADIR_GET then
    Exit(E_NOTIMPL);
  SetLength(Items, 3);
  N := 0;
  if FHdrop <> 0 then
  begin
    Items[N] := MakeHGlobalFmt(CF_HDROP);
    Inc(N);
  end;
  if (FEffect <> 0) and (GCfPreferredDropEffect <> 0) then
  begin
    Items[N] := MakeHGlobalFmt(GCfPreferredDropEffect);
    Inc(N);
  end;
  if (FUris <> 0) and (GCfMtnFileUris <> 0) then
  begin
    Items[N] := MakeHGlobalFmt(GCfMtnFileUris);
    Inc(N);
  end;
  SetLength(Items, N);
  EnumFormatEtc := TEnumFormatList.Create(Items);
  Result := S_OK;
end;

function TPanelClipDataObject.DAdvise(const FormatEtc: TFormatEtc; advf: LongInt;
  const AdvSink: IAdviseSink; out dwConnection: LongInt): HRESULT;
begin
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function TPanelClipDataObject.DUnadvise(dwConnection: LongInt): HRESULT;
begin
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function TPanelClipDataObject.EnumDAdvise(out EnumAdvise: IEnumStatData): HRESULT;
begin
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function EncodeMtnFileClip(const AUris: TArray<string>; ACut: Boolean): string;
var
  I: Integer;
begin
  if ACut then
    Result := 'CUT'
  else
    Result := 'COPY';
  for I := 0 to High(AUris) do
    if Trim(AUris[I]) <> '' then
      Result := Result + #10 + AUris[I];
end;

function DecodeMtnFileClip(const AText: string; out AUris: TArray<string>;
  out ACut: Boolean): Boolean;
var
  Lines: TArray<string>;
  Head: string;
  I, N: Integer;
begin
  Result := False;
  ACut := False;
  SetLength(AUris, 0);
  Lines := AText.Split([#10, #13], TStringSplitOptions.ExcludeEmpty);
  if Length(Lines) = 0 then
    Exit;
  Head := UpperCase(Trim(Lines[0]));
  if Head = 'CUT' then
    ACut := True
  else if Head = 'COPY' then
    ACut := False
  else
    Exit;
  SetLength(AUris, Length(Lines) - 1);
  N := 0;
  for I := 1 to High(Lines) do
  begin
    AUris[N] := Trim(Lines[I]);
    if AUris[N] <> '' then
      Inc(N);
  end;
  SetLength(AUris, N);
  Result := N > 0;
end;

function ClipboardSetPanelItems(const ALocalPaths, AUris: TArray<string>;
  ACut: Boolean): Boolean;
var
  HDrop, Effect, UrisHandle: HGLOBAL;
  Data: IDataObject;
  EffectVal: DWORD;
  Payload: string;
  EncodedUris: TArray<string>;
begin
  Result := False;
  EncodedUris := AUris;
  if Length(EncodedUris) = 0 then
    EncodedUris := LocalPathsToFileUris(ALocalPaths);
  if (Length(ALocalPaths) = 0) and (Length(EncodedUris) = 0) then
    Exit;

  HDrop := 0;
  UrisHandle := 0;
  if Length(ALocalPaths) > 0 then
    HDrop := BuildHDrop(ALocalPaths);
  if ACut then
    EffectVal := DROPEFFECT_MOVE
  else
    EffectVal := DROPEFFECT_COPY;
  Effect := DwordToHGlobal(EffectVal);
  Payload := EncodeMtnFileClip(EncodedUris, ACut);
  if Payload <> '' then
    UrisHandle := WideToHGlobal(Payload);

  if (HDrop = 0) and (UrisHandle = 0) then
  begin
    if Effect <> 0 then
      GlobalFree(Effect);
    Exit;
  end;

  Data := TPanelClipDataObject.Create(HDrop, Effect, UrisHandle);
  Result := Succeeded(OleSetClipboard(Data));
end;

function HDropToPaths(AHdrop: HDROP): TArray<string>;
var
  Count, I, Len: UINT;
  Buf: string;
begin
  SetLength(Result, 0);
  if AHdrop = 0 then
    Exit;
  Count := DragQueryFileW(AHdrop, $FFFFFFFF, nil, 0);
  SetLength(Result, Count);
  for I := 0 to Count - 1 do
  begin
    Len := DragQueryFileW(AHdrop, I, nil, 0);
    SetLength(Buf, Len);
    if Len > 0 then
      DragQueryFileW(AHdrop, I, PWideChar(Buf), Len + 1);
    Result[I] := Buf;
  end;
end;

function ClipboardGetPanelItems(out ALocalPaths, AUris: TArray<string>;
  out ACut: Boolean): Boolean;
var
  Data: IDataObject;
  Fmt: TFormatEtc;
  Med: TStgMedium;
  Text: string;
  Effect: DWORD;
  P: PDWORD;
begin
  Result := False;
  ACut := False;
  SetLength(ALocalPaths, 0);
  SetLength(AUris, 0);
  if Failed(OleGetClipboard(Data)) or (Data = nil) then
    Exit;

  if (GCfMtnFileUris <> 0) then
  begin
    Fmt := MakeHGlobalFmt(GCfMtnFileUris);
    if Data.GetData(Fmt, Med) = S_OK then
    try
      Text := HGlobalToWide(Med.hGlobal);
      if DecodeMtnFileClip(Text, AUris, ACut) then
        Result := True;
    finally
      ReleaseStgMedium(Med);
    end;
  end;

  if (GCfPreferredDropEffect <> 0) then
  begin
    Fmt := MakeHGlobalFmt(GCfPreferredDropEffect);
    if Data.GetData(Fmt, Med) = S_OK then
    try
      P := GlobalLock(Med.hGlobal);
      if P <> nil then
      try
        Effect := P^;
        if (Effect and DROPEFFECT_MOVE) <> 0 then
          ACut := True;
      finally
        GlobalUnlock(Med.hGlobal);
      end;
    finally
      ReleaseStgMedium(Med);
    end;
  end;

  Fmt := MakeHGlobalFmt(CF_HDROP);
  if Data.GetData(Fmt, Med) = S_OK then
  try
    ALocalPaths := HDropToPaths(Med.hGlobal);
    if Length(ALocalPaths) > 0 then
      Result := True;
  finally
    ReleaseStgMedium(Med);
  end;

  if Result and (Length(AUris) = 0) and (Length(ALocalPaths) > 0) then
    AUris := LocalPathsToFileUris(ALocalPaths);
end;

function ClipboardHasPanelItems: Boolean;
var
  Paths, Uris: TArray<string>;
  Cut: Boolean;
begin
  Result := ClipboardGetPanelItems(Paths, Uris, Cut);
end;

procedure ClipboardClearPanelItems;
begin
  OleSetClipboard(nil);
end;

initialization
  GCfPreferredDropEffect := RegisterClipboardFormat('Preferred DropEffect');
  GCfMtnFileUris := RegisterClipboardFormat('MTN2 File URIs');

end.
