unit uSevenZipApi;

{ Minimal stdcall COM wrapper around 7z.dll (CreateObject / IInArchive /
  IOutArchive). The DLL is loaded from a caller-supplied path so the host
  can keep a replaceable LGPL copy next to the plugin. }

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.DateUtils, System.IOUtils,
  Winapi.Windows, Winapi.ActiveX;

type
  T7zItem = record
    Index: UInt32;
    Path: string;
    Size: Int64;
    IsDir: Boolean;
    Encrypted: Boolean;
    MTime: TDateTime;
    Attrib: Cardinal;
  end;

function SevenZipLoadEngine(const ADllPath: string): Boolean;
procedure SevenZipUnloadEngine;
function SevenZipEngineLoaded: Boolean;
function SevenZipListArchive(const AArchivePath: string; out AItems: TArray<T7zItem>;
  out AError: string): Boolean;
function SevenZipExtractFile(const AArchivePath, AInnerPath: string; AMaxBytes: Int64;
  out ABytes: TBytes; out AError: string): Boolean;
function SevenZipCreateSimpleArchive(const AArchivePath, ASourceFile: string;
  out AError: string): Boolean;
function SevenZipAddLocalPath(const AArchivePath, ALocalPath, AInnerPath: string;
  AOverwrite: Boolean; out AError: string): Boolean;
function SevenZipNormInner(const APath: string): string;
procedure SevenZipSetPassword(const AArchivePath, APassword: string);
procedure SevenZipClearPassword(const AArchivePath: string);
procedure SevenZipClearAllPasswords;
function SevenZipTryGetPassword(const AArchivePath: string; out APassword: string): Boolean;

/// <summary>Extracts AEntryPath from AOuterArchivePath to a cached temp file
/// and returns its path, so the caller can re-open it as an archive in its
/// own right (archive-inside-archive chains, e.g. the .tar inside a .tar.gz).
/// Repeat calls for the same (outer archive, entry) pair reuse the cached
/// file as long as the outer archive's mtime hasn't changed.</summary>
function SevenZipResolveNestedArchive(const AOuterArchivePath, AEntryPath: string;
  out ATempFilePath: string; out AError: string): Boolean;

implementation

uses
  System.Generics.Collections;

const
  IID_IProgress: TGUID = '{23170F69-40C1-278A-0000-000000050000}';
  IID_ISequentialInStream: TGUID = '{23170F69-40C1-278A-0000-000300010000}';
  IID_ISequentialOutStream: TGUID = '{23170F69-40C1-278A-0000-000300020000}';
  IID_IInStream: TGUID = '{23170F69-40C1-278A-0000-000300030000}';
  IID_IOutStream: TGUID = '{23170F69-40C1-278A-0000-000300040000}';
  IID_IInArchive: TGUID = '{23170F69-40C1-278A-0000-000600600000}';
  IID_IOutArchive: TGUID = '{23170F69-40C1-278A-0000-000600A00000}';
  IID_IArchiveExtractCallback: TGUID = '{23170F69-40C1-278A-0000-000600200000}';
  IID_IArchiveUpdateCallback: TGUID = '{23170F69-40C1-278A-0000-000600800000}';
  CLSID_CFormat7z: TGUID = '{23170F69-40C1-278A-1000-000110070000}';
  CLSID_CFormatRar: TGUID = '{23170F69-40C1-278A-1000-000110030000}';
  CLSID_CFormatRar5: TGUID = '{23170F69-40C1-278A-1000-000110CC0000}';

  kHandlerClassID = 1;
  kHandlerExtension = 2;

  kpidPath = 3;
  kpidIsDir = 6;
  kpidSize = 7;
  kpidAttrib = 9;
  kpidMTime = 12;
  kpidEncrypted = 15;

  STREAM_SEEK_SET = 0;
  STREAM_SEEK_CUR = 1;
  STREAM_SEEK_END = 2;

type
  PInt32 = ^Int32;
  TCreateObjectFn = function(clsid, iid: PGUID; outObj: Pointer): HRESULT; stdcall;
  TGetNumberOfFormatsFn = function(numFormats: PUInt32): HRESULT; stdcall;
  TGetHandlerProperty2Fn = function(formatIndex, propID: UInt32;
    out value: TPropVariant): HRESULT; stdcall;

  T7zFormatInfo = record
    ClassID: TGUID;
    Extensions: string;
  end;

  IProgress = interface(IUnknown)
    ['{23170F69-40C1-278A-0000-000000050000}']
    function SetTotal(total: UInt64): HRESULT; stdcall;
    function SetCompleted(completeValue: PUInt64): HRESULT; stdcall;
  end;

  ISequentialInStream = interface(IUnknown)
    ['{23170F69-40C1-278A-0000-000300010000}']
    function Read(data: Pointer; size: UInt32; processedSize: PUInt32): HRESULT; stdcall;
  end;

  ISequentialOutStream = interface(IUnknown)
    ['{23170F69-40C1-278A-0000-000300020000}']
    function Write(data: Pointer; size: UInt32; processedSize: PUInt32): HRESULT; stdcall;
  end;

  IInStream = interface(ISequentialInStream)
    ['{23170F69-40C1-278A-0000-000300030000}']
    function Seek(offset: Int64; seekOrigin: UInt32; newPosition: PUInt64): HRESULT; stdcall;
  end;

  IOutStream = interface(ISequentialOutStream)
    ['{23170F69-40C1-278A-0000-000300040000}']
    function Seek(offset: Int64; seekOrigin: UInt32; newPosition: PUInt64): HRESULT; stdcall;
    function SetSize(newSize: UInt64): HRESULT; stdcall;
  end;

  IArchiveOpenCallback = interface(IUnknown)
    ['{23170F69-40C1-278A-0000-000600100000}']
    function SetTotal(files, bytes: PUInt64): HRESULT; stdcall;
    function SetCompleted(files, bytes: PUInt64): HRESULT; stdcall;
  end;

  ICryptoGetTextPassword = interface(IUnknown)
    ['{23170F69-40C1-278A-0000-000500100000}']
    function CryptoGetTextPassword(out password: TBStr): HRESULT; stdcall;
  end;

  ICryptoGetTextPassword2 = interface(IUnknown)
    ['{23170F69-40C1-278A-0000-000500110000}']
    function CryptoGetTextPassword2(out passwordIsDefined: Int32;
      out password: TBStr): HRESULT; stdcall;
  end;

  IArchiveExtractCallback = interface(IProgress)
    ['{23170F69-40C1-278A-0000-000600200000}']
    function GetStream(index: UInt32; out outStream: ISequentialOutStream;
      askExtractMode: Int32): HRESULT; stdcall;
    function PrepareOperation(askExtractMode: Int32): HRESULT; stdcall;
    function SetOperationResult(opRes: Int32): HRESULT; stdcall;
  end;

  IArchiveUpdateCallback = interface(IProgress)
    ['{23170F69-40C1-278A-0000-000600800000}']
    function GetUpdateItemInfo(index: UInt32; newData, newProperties: PInt32;
      indexInArchive: PUInt32): HRESULT; stdcall;
    function GetProperty(index: UInt32; propID: UInt32; out value: TPropVariant): HRESULT; stdcall;
    function GetStream(index: UInt32; out inStream: ISequentialInStream): HRESULT; stdcall;
    function SetOperationResult(opRes: Int32): HRESULT; stdcall;
  end;

  IInArchive = interface(IUnknown)
    ['{23170F69-40C1-278A-0000-000600600000}']
    function Open(stream: IInStream; maxCheckStartPosition: PUInt64;
      openCallback: IArchiveOpenCallback): HRESULT; stdcall;
    function Close: HRESULT; stdcall;
    function GetNumberOfItems(out numItems: UInt32): HRESULT; stdcall;
    function GetProperty(index: UInt32; propID: UInt32; out value: TPropVariant): HRESULT; stdcall;
    function Extract(indices: PUInt32; numItems: UInt32; testMode: Int32;
      extractCallback: IArchiveExtractCallback): HRESULT; stdcall;
    function GetArchiveProperty(propID: UInt32; out value: TPropVariant): HRESULT; stdcall;
    function GetNumberOfProperties(out numProps: UInt32): HRESULT; stdcall;
    function GetPropertyInfo(index: UInt32; out name: TBStr; out propID: UInt32;
      out varType: TVarType): HRESULT; stdcall;
    function GetNumberOfArchiveProperties(out numProps: UInt32): HRESULT; stdcall;
    function GetArchivePropertyInfo(index: UInt32; out name: TBStr; out propID: UInt32;
      out varType: TVarType): HRESULT; stdcall;
  end;

  IOutArchive = interface(IUnknown)
    ['{23170F69-40C1-278A-0000-000600A00000}']
    function UpdateItems(outStream: ISequentialOutStream; numItems: UInt32;
      updateCallback: IArchiveUpdateCallback): HRESULT; stdcall;
    function GetFileTimeType(out fileTimeType: UInt32): HRESULT; stdcall;
  end;

  T7zFileStream = class(TInterfacedObject, ISequentialInStream, IInStream,
    ISequentialOutStream, IOutStream)
  private
    FStream: TFileStream;
  public
    constructor Create(const APath: string; AMode: Word);
    destructor Destroy; override;
    function Read(data: Pointer; size: UInt32; processedSize: PUInt32): HRESULT; stdcall;
    function Write(data: Pointer; size: UInt32; processedSize: PUInt32): HRESULT; stdcall;
    function Seek(offset: Int64; seekOrigin: UInt32; newPosition: PUInt64): HRESULT; stdcall;
    function SetSize(newSize: UInt64): HRESULT; stdcall;
  end;

  T7zMemOutStream = class(TInterfacedObject, ISequentialOutStream)
  private
    FData: TMemoryStream;
    FMaxBytes: Int64;
    FOverflow: Boolean;
  public
    constructor Create(AMaxBytes: Int64);
    destructor Destroy; override;
    function Write(data: Pointer; size: UInt32; processedSize: PUInt32): HRESULT; stdcall;
    function CopyBytes(out ABytes: TBytes): Boolean;
    property Overflow: Boolean read FOverflow;
  end;

  T7zOpenQuiet = class(TInterfacedObject, IArchiveOpenCallback)
  public
    function SetTotal(files, bytes: PUInt64): HRESULT; stdcall;
    function SetCompleted(files, bytes: PUInt64): HRESULT; stdcall;
  end;

  T7zOpenAuthed = class(TInterfacedObject, IArchiveOpenCallback,
    ICryptoGetTextPassword, ICryptoGetTextPassword2)
  private
    FPassword: string;
  public
    constructor Create(const APassword: string);
    function SetTotal(files, bytes: PUInt64): HRESULT; stdcall;
    function SetCompleted(files, bytes: PUInt64): HRESULT; stdcall;
    function CryptoGetTextPassword(out password: TBStr): HRESULT; stdcall;
    function CryptoGetTextPassword2(out passwordIsDefined: Int32;
      out password: TBStr): HRESULT; stdcall;
  end;

  T7zExtractCallback = class(TInterfacedObject, IProgress, IArchiveExtractCallback,
    ICryptoGetTextPassword, ICryptoGetTextPassword2)
  private
    FOut: T7zMemOutStream;
    FOpRes: Int32;
    FPassword: string;
  public
    constructor Create(AOut: T7zMemOutStream; const APassword: string);
    function SetTotal(total: UInt64): HRESULT; stdcall;
    function SetCompleted(completeValue: PUInt64): HRESULT; stdcall;
    function GetStream(index: UInt32; out outStream: ISequentialOutStream;
      askExtractMode: Int32): HRESULT; stdcall;
    function PrepareOperation(askExtractMode: Int32): HRESULT; stdcall;
    function SetOperationResult(opRes: Int32): HRESULT; stdcall;
    function CryptoGetTextPassword(out password: TBStr): HRESULT; stdcall;
    function CryptoGetTextPassword2(out passwordIsDefined: Int32;
      out password: TBStr): HRESULT; stdcall;
    property OpRes: Int32 read FOpRes;
  end;

  T7zUpdateCallback = class(TInterfacedObject, IProgress, IArchiveUpdateCallback)
  private
    FPath: string;
    FName: string;
    FSize: Int64;
    FTime: TFileTime;
  public
    constructor Create(const ASourceFile: string);
    function SetTotal(total: UInt64): HRESULT; stdcall;
    function SetCompleted(completeValue: PUInt64): HRESULT; stdcall;
    function GetUpdateItemInfo(index: UInt32; newData, newProperties: PInt32;
      indexInArchive: PUInt32): HRESULT; stdcall;
    function GetProperty(index: UInt32; propID: UInt32; out value: TPropVariant): HRESULT; stdcall;
    function GetStream(index: UInt32; out inStream: ISequentialInStream): HRESULT; stdcall;
    function SetOperationResult(opRes: Int32): HRESULT; stdcall;
  end;

  T7zPackItem = record
    LocalPath: string;
    InnerPath: string;
    IsDir: Boolean;
    Size: Int64;
    Time: TFileTime;
  end;

  T7zPackCallback = class(TInterfacedObject, IProgress, IArchiveUpdateCallback)
  private
    FKeep: TArray<UInt32>;
    FNew: TArray<T7zPackItem>;
    function NewIdx(AIndex: UInt32): Integer;
  public
    constructor Create(const AKeep: TArray<UInt32>; const ANew: TArray<T7zPackItem>);
    function SetTotal(total: UInt64): HRESULT; stdcall;
    function SetCompleted(completeValue: PUInt64): HRESULT; stdcall;
    function GetUpdateItemInfo(index: UInt32; newData, newProperties: PInt32;
      indexInArchive: PUInt32): HRESULT; stdcall;
    function GetProperty(index: UInt32; propID: UInt32; out value: TPropVariant): HRESULT; stdcall;
    function GetStream(index: UInt32; out inStream: ISequentialInStream): HRESULT; stdcall;
    function SetOperationResult(opRes: Int32): HRESULT; stdcall;
  end;

var
  GLock: TCriticalSection;
  GModule: HMODULE;
  GCreateObject: TCreateObjectFn;
  GGetNumberOfFormats: TGetNumberOfFormatsFn;
  GGetHandlerProperty2: TGetHandlerProperty2Fn;
  GFormats: TArray<T7zFormatInfo>;
  GPasswords: TDictionary<string, string>;
  // outer-archive|entry|outer-mtime -> extracted temp file, so repeat
  // listing/read calls while browsing a nested archive don't re-extract it.
  GNestedCache: TDictionary<string, string>;
  GNestedSeq: Integer;

procedure SevenZipClearNestedCache; forward;

function SevenZipNormInner(const APath: string): string;
begin
  Result := StringReplace(Trim(APath), '\', '/', [rfReplaceAll]);
  while (Length(Result) > 0) and (Result[1] = '/') do
    Delete(Result, 1, 1);
  while (Length(Result) > 0) and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

function HResOk(AHr: HRESULT): Boolean;
begin
  Result := AHr = S_OK;
end;

function PropStr(const P: TPropVariant): string;
begin
  if P.vt = VT_BSTR then
    Result := P.bstrVal
  else
    Result := '';
end;

function PropBool(const P: TPropVariant): Boolean;
begin
  case P.vt of
    VT_BOOL: Result := Boolean(P.boolVal);
    VT_UI1, VT_I1, VT_UI2, VT_I2, VT_UI4, VT_I4: Result := P.lVal <> 0;
  else
    Result := False;
  end;
end;

function PropUInt64(const P: TPropVariant): UInt64;
begin
  case P.vt of
    VT_UI8: Result := P.uhVal.QuadPart;
    VT_I8: Result := UInt64(P.hVal.QuadPart);
    VT_UI4, VT_I4: Result := Cardinal(P.lVal);
    VT_UI2, VT_I2: Result := Word(P.iVal);
  else
    Result := 0;
  end;
end;

function PropFileTime(const P: TPropVariant): TDateTime;
var
  Sys: TSystemTime;
  Local: TFileTime;
begin
  Result := 0;
  if P.vt <> VT_FILETIME then
    Exit;
  if (P.filetime.dwLowDateTime = 0) and (P.filetime.dwHighDateTime = 0) then
    Exit;
  if FileTimeToLocalFileTime(P.filetime, Local) and FileTimeToSystemTime(Local, Sys) then
    Result := SystemTimeToDateTime(Sys);
end;

constructor T7zFileStream.Create(const APath: string; AMode: Word);
begin
  inherited Create;
  FStream := TFileStream.Create(APath, AMode);
end;

destructor T7zFileStream.Destroy;
begin
  FStream.Free;
  inherited;
end;

function T7zFileStream.Read(data: Pointer; size: UInt32; processedSize: PUInt32): HRESULT;
var
  N: Longint;
begin
  N := FStream.Read(data^, size);
  if Assigned(processedSize) then
    processedSize^ := UInt32(N);
  Result := S_OK;
end;

function T7zFileStream.Write(data: Pointer; size: UInt32; processedSize: PUInt32): HRESULT;
var
  N: Longint;
begin
  N := FStream.Write(data^, size);
  if Assigned(processedSize) then
    processedSize^ := UInt32(N);
  if UInt32(N) <> size then
    Result := E_FAIL
  else
    Result := S_OK;
end;

function T7zFileStream.Seek(offset: Int64; seekOrigin: UInt32; newPosition: PUInt64): HRESULT;
var
  Origin: TSeekOrigin;
  Pos: Int64;
begin
  case seekOrigin of
    STREAM_SEEK_CUR: Origin := soCurrent;
    STREAM_SEEK_END: Origin := soEnd;
  else
    Origin := soBeginning;
  end;
  Pos := FStream.Seek(offset, Origin);
  if Assigned(newPosition) then
    newPosition^ := UInt64(Pos);
  Result := S_OK;
end;

function T7zFileStream.SetSize(newSize: UInt64): HRESULT;
begin
  FStream.Size := Int64(newSize);
  Result := S_OK;
end;

constructor T7zMemOutStream.Create(AMaxBytes: Int64);
begin
  inherited Create;
  FMaxBytes := AMaxBytes;
  FData := TMemoryStream.Create;
  FOverflow := False;
end;

destructor T7zMemOutStream.Destroy;
begin
  FData.Free;
  inherited;
end;

function T7zMemOutStream.Write(data: Pointer; size: UInt32; processedSize: PUInt32): HRESULT;
begin
  if FOverflow or ((FMaxBytes >= 0) and (FData.Size + size > FMaxBytes)) then
  begin
    FOverflow := True;
    if Assigned(processedSize) then
      processedSize^ := 0;
    Exit(E_FAIL);
  end;
  FData.WriteBuffer(data^, size);
  if Assigned(processedSize) then
    processedSize^ := size;
  Result := S_OK;
end;

function T7zMemOutStream.CopyBytes(out ABytes: TBytes): Boolean;
begin
  Result := not FOverflow;
  SetLength(ABytes, FData.Size);
  if FData.Size > 0 then
  begin
    FData.Position := 0;
    FData.ReadBuffer(ABytes[0], FData.Size);
  end;
end;

function PasswordKey(const APath: string): string;
begin
  Result := LowerCase(ExcludeTrailingPathDelimiter(
    StringReplace(Trim(APath), '/', PathDelim, [rfReplaceAll])));
end;

procedure SevenZipSetPassword(const AArchivePath, APassword: string);
begin
  GLock.Acquire;
  try
    GPasswords.AddOrSetValue(PasswordKey(AArchivePath), APassword);
  finally
    GLock.Release;
  end;
end;

procedure SevenZipClearPassword(const AArchivePath: string);
begin
  GLock.Acquire;
  try
    GPasswords.Remove(PasswordKey(AArchivePath));
  finally
    GLock.Release;
  end;
end;

procedure SevenZipClearAllPasswords;
begin
  GLock.Acquire;
  try
    GPasswords.Clear;
  finally
    GLock.Release;
  end;
end;

function SevenZipTryGetPassword(const AArchivePath: string; out APassword: string): Boolean;
begin
  GLock.Acquire;
  try
    Result := GPasswords.TryGetValue(PasswordKey(AArchivePath), APassword);
  finally
    GLock.Release;
  end;
end;

function AllocPassword(const APassword: string; out password: TBStr): HRESULT;
begin
  password := SysAllocString(PWideChar(APassword));
  Result := S_OK;
end;

function T7zOpenQuiet.SetTotal(files, bytes: PUInt64): HRESULT;
begin
  Result := S_OK;
end;

function T7zOpenQuiet.SetCompleted(files, bytes: PUInt64): HRESULT;
begin
  Result := S_OK;
end;

constructor T7zOpenAuthed.Create(const APassword: string);
begin
  inherited Create;
  FPassword := APassword;
end;

function T7zOpenAuthed.SetTotal(files, bytes: PUInt64): HRESULT;
begin
  Result := S_OK;
end;

function T7zOpenAuthed.SetCompleted(files, bytes: PUInt64): HRESULT;
begin
  Result := S_OK;
end;

function T7zOpenAuthed.CryptoGetTextPassword(out password: TBStr): HRESULT;
begin
  Result := AllocPassword(FPassword, password);
end;

function T7zOpenAuthed.CryptoGetTextPassword2(out passwordIsDefined: Int32;
  out password: TBStr): HRESULT;
begin
  passwordIsDefined := 1;
  Result := AllocPassword(FPassword, password);
end;

constructor T7zExtractCallback.Create(AOut: T7zMemOutStream; const APassword: string);
begin
  inherited Create;
  FOut := AOut;
  FOpRes := 0;
  FPassword := APassword;
end;

function T7zExtractCallback.SetTotal(total: UInt64): HRESULT;
begin
  Result := S_OK;
end;

function T7zExtractCallback.SetCompleted(completeValue: PUInt64): HRESULT;
begin
  Result := S_OK;
end;

function T7zExtractCallback.GetStream(index: UInt32; out outStream: ISequentialOutStream;
  askExtractMode: Int32): HRESULT;
begin
  if askExtractMode <> 0 then
  begin
    outStream := nil;
    Exit(S_OK);
  end;
  outStream := FOut;
  Result := S_OK;
end;

function T7zExtractCallback.PrepareOperation(askExtractMode: Int32): HRESULT;
begin
  Result := S_OK;
end;

function T7zExtractCallback.SetOperationResult(opRes: Int32): HRESULT;
begin
  FOpRes := opRes;
  Result := S_OK;
end;

function T7zExtractCallback.CryptoGetTextPassword(out password: TBStr): HRESULT;
begin
  Result := AllocPassword(FPassword, password);
end;

function T7zExtractCallback.CryptoGetTextPassword2(out passwordIsDefined: Int32;
  out password: TBStr): HRESULT;
begin
  passwordIsDefined := 1;
  Result := AllocPassword(FPassword, password);
end;

constructor T7zUpdateCallback.Create(const ASourceFile: string);
var
  FH: THandle;
  CT, AT, WT: TFileTime;
begin
  inherited Create;
  FPath := ASourceFile;
  FName := ExtractFileName(ASourceFile);
  FSize := 0;
  FillChar(FTime, SizeOf(FTime), 0);
  if FileExists(ASourceFile) then
  begin
    FSize := TFile.GetSize(ASourceFile);
    FH := CreateFile(PChar(ASourceFile), GENERIC_READ, FILE_SHARE_READ, nil,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    if FH <> INVALID_HANDLE_VALUE then
    try
      if GetFileTime(FH, @CT, @AT, @WT) then
        FTime := WT;
    finally
      CloseHandle(FH);
    end;
  end;
end;

function T7zUpdateCallback.SetTotal(total: UInt64): HRESULT;
begin
  Result := S_OK;
end;

function T7zUpdateCallback.SetCompleted(completeValue: PUInt64): HRESULT;
begin
  Result := S_OK;
end;

function T7zUpdateCallback.GetUpdateItemInfo(index: UInt32; newData, newProperties: PInt32;
  indexInArchive: PUInt32): HRESULT;
begin
  if Assigned(newData) then
    newData^ := 1;
  if Assigned(newProperties) then
    newProperties^ := 1;
  if Assigned(indexInArchive) then
    indexInArchive^ := $FFFFFFFF;
  Result := S_OK;
end;

function T7zUpdateCallback.GetProperty(index: UInt32; propID: UInt32;
  out value: TPropVariant): HRESULT;
var
  W: WideString;
begin
  FillChar(value, SizeOf(value), 0);
  case propID of
    kpidPath:
      begin
        W := FName;
        value.vt := VT_BSTR;
        value.bstrVal := SysAllocString(PWideChar(W));
      end;
    kpidIsDir:
      begin
        value.vt := VT_BOOL;
        value.boolVal := False;
      end;
    kpidSize:
      begin
        value.vt := VT_UI8;
        value.uhVal.QuadPart := UInt64(FSize);
      end;
    kpidMTime:
      begin
        value.vt := VT_FILETIME;
        value.filetime := FTime;
      end;
  else
    value.vt := VT_EMPTY;
  end;
  Result := S_OK;
end;

function T7zUpdateCallback.GetStream(index: UInt32; out inStream: ISequentialInStream): HRESULT;
begin
  inStream := T7zFileStream.Create(FPath, fmOpenRead or fmShareDenyWrite);
  Result := S_OK;
end;

function T7zUpdateCallback.SetOperationResult(opRes: Int32): HRESULT;
begin
  Result := S_OK;
end;

constructor T7zPackCallback.Create(const AKeep: TArray<UInt32>;
  const ANew: TArray<T7zPackItem>);
begin
  inherited Create;
  FKeep := Copy(AKeep);
  FNew := Copy(ANew);
end;

function T7zPackCallback.NewIdx(AIndex: UInt32): Integer;
begin
  Result := Integer(AIndex) - Length(FKeep);
end;

function T7zPackCallback.SetTotal(total: UInt64): HRESULT;
begin
  Result := S_OK;
end;

function T7zPackCallback.SetCompleted(completeValue: PUInt64): HRESULT;
begin
  Result := S_OK;
end;

function T7zPackCallback.GetUpdateItemInfo(index: UInt32; newData, newProperties: PInt32;
  indexInArchive: PUInt32): HRESULT;
begin
  if Integer(index) < Length(FKeep) then
  begin
    if Assigned(newData) then
      newData^ := 0;
    if Assigned(newProperties) then
      newProperties^ := 0;
    if Assigned(indexInArchive) then
      indexInArchive^ := FKeep[index];
  end
  else
  begin
    if Assigned(newData) then
      newData^ := 1;
    if Assigned(newProperties) then
      newProperties^ := 1;
    if Assigned(indexInArchive) then
      indexInArchive^ := $FFFFFFFF;
  end;
  Result := S_OK;
end;

function T7zPackCallback.GetProperty(index: UInt32; propID: UInt32;
  out value: TPropVariant): HRESULT;
var
  I: Integer;
  W: WideString;
  Item: T7zPackItem;
begin
  FillChar(value, SizeOf(value), 0);
  I := NewIdx(index);
  if (I < 0) or (I > High(FNew)) then
    Exit(S_OK);
  Item := FNew[I];
  case propID of
    kpidPath:
      begin
        W := StringReplace(Item.InnerPath, '/', '\', [rfReplaceAll]);
        value.vt := VT_BSTR;
        value.bstrVal := SysAllocString(PWideChar(W));
      end;
    kpidIsDir:
      begin
        value.vt := VT_BOOL;
        value.boolVal := Item.IsDir;
      end;
    kpidSize:
      begin
        value.vt := VT_UI8;
        value.uhVal.QuadPart := UInt64(Item.Size);
      end;
    kpidMTime:
      begin
        value.vt := VT_FILETIME;
        value.filetime := Item.Time;
      end;
  else
    value.vt := VT_EMPTY;
  end;
  Result := S_OK;
end;

function T7zPackCallback.GetStream(index: UInt32; out inStream: ISequentialInStream): HRESULT;
var
  I: Integer;
begin
  inStream := nil;
  I := NewIdx(index);
  if (I < 0) or (I > High(FNew)) then
    Exit(E_INVALIDARG);
  if FNew[I].IsDir then
    Exit(S_FALSE);
  try
    inStream := T7zFileStream.Create(FNew[I].LocalPath, fmOpenRead or fmShareDenyWrite);
    Result := S_OK;
  except
    Result := E_FAIL;
  end;
end;

function T7zPackCallback.SetOperationResult(opRes: Int32): HRESULT;
begin
  Result := S_OK;
end;

function GuidIsEmpty(const AId: TGUID): Boolean;
begin
  Result := (AId.D1 = 0) and (AId.D2 = 0) and (AId.D3 = 0) and
    (AId.D4[0] = 0) and (AId.D4[1] = 0) and (AId.D4[2] = 0) and (AId.D4[3] = 0) and
    (AId.D4[4] = 0) and (AId.D4[5] = 0) and (AId.D4[6] = 0) and (AId.D4[7] = 0);
end;

function BstrByteLen(B: TBStr): Cardinal;
begin
  if B = nil then
    Exit(0);
  Result := PCardinal(PByte(B) - 4)^;
end;

function PropGuid(const P: TPropVariant): TGUID;
begin
  FillChar(Result, SizeOf(Result), 0);
  if (P.vt = VT_BSTR) and Assigned(P.bstrVal) and
     (BstrByteLen(P.bstrVal) >= SizeOf(TGUID)) then
    Move(P.bstrVal^, Result, SizeOf(TGUID));
end;

procedure AddGuid(var AList: TArray<TGUID>; const AId: TGUID);
var
  I: Integer;
begin
  if GuidIsEmpty(AId) then
    Exit;
  for I := 0 to High(AList) do
    if CompareMem(@AList[I], @AId, SizeOf(TGUID)) then
      Exit;
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := AId;
end;

procedure LoadFormatTable;
var
  N, I: UInt32;
  P: TPropVariant;
  Info: T7zFormatInfo;
begin
  SetLength(GFormats, 0);
  if not Assigned(GGetNumberOfFormats) or not Assigned(GGetHandlerProperty2) then
    Exit;
  N := 0;
  if GGetNumberOfFormats(@N) <> S_OK then
    Exit;
  for I := 0 to N - 1 do
  begin
    FillChar(P, SizeOf(P), 0);
    if GGetHandlerProperty2(I, kHandlerClassID, P) <> S_OK then
      Continue;
    Info.ClassID := PropGuid(P);
    PropVariantClear(P);
    if GuidIsEmpty(Info.ClassID) then
      Continue;
    FillChar(P, SizeOf(P), 0);
    if GGetHandlerProperty2(I, kHandlerExtension, P) = S_OK then
    begin
      Info.Extensions := LowerCase(Trim(PropStr(P)));
      PropVariantClear(P);
    end
    else
      Info.Extensions := '';
    SetLength(GFormats, Length(GFormats) + 1);
    GFormats[High(GFormats)] := Info;
  end;
end;

function ArchiveExt(const APath: string): string;
begin
  Result := LowerCase(TPath.GetExtension(APath));
  if (Result <> '') and (Result[1] = '.') then
    Delete(Result, 1, 1);
end;

function FormatMatchesExt(const AFmt: T7zFormatInfo; const AExt: string): Boolean;
var
  Parts: TArray<string>;
  Part: string;
begin
  Result := False;
  if AExt = '' then
    Exit;
  Parts := AFmt.Extensions.Split([' '], TStringSplitOptions.ExcludeEmpty);
  for Part in Parts do
    if SameText(Part, AExt) then
      Exit(True);
end;

function CollectClassIds(const AArchivePath: string): TArray<TGUID>;
var
  Ext: string;
  Fmt: T7zFormatInfo;
begin
  SetLength(Result, 0);
  Ext := ArchiveExt(AArchivePath);
  for Fmt in GFormats do
    if FormatMatchesExt(Fmt, Ext) then
      AddGuid(Result, Fmt.ClassID);
  if Length(Result) > 0 then
    Exit;
  if Ext = 'rar' then
  begin
    AddGuid(Result, CLSID_CFormatRar5);
    AddGuid(Result, CLSID_CFormatRar);
  end;
  AddGuid(Result, CLSID_CFormat7z);
  if Ext <> 'rar' then
  begin
    AddGuid(Result, CLSID_CFormatRar5);
    AddGuid(Result, CLSID_CFormatRar);
  end;
end;

function Create7zObject(const IID: TGUID; outObj: Pointer): HRESULT;
begin
  if not Assigned(GCreateObject) then
    Exit(E_FAIL);
  Result := GCreateObject(@CLSID_CFormat7z, @IID, outObj);
end;

function OpenArchive(const AArchivePath: string; out AArc: IInArchive;
  out AError: string): Boolean;
var
  St: IInStream;
  Ids: TArray<TGUID>;
  I: Integer;
  Hr: HRESULT;
  Dummy, MaxCheck: UInt64;
  OpenCb: IArchiveOpenCallback;
  SawEncrypted, HasPassword: Boolean;
  Password: string;
begin
  Result := False;
  AArc := nil;
  AError := '';
  if not Assigned(GCreateObject) then
  begin
    AError := '7z.dll is not loaded';
    Exit;
  end;
  if not FileExists(AArchivePath) then
  begin
    AError := 'Archive not found';
    Exit;
  end;
  St := T7zFileStream.Create(AArchivePath, fmOpenRead or fmShareDenyWrite);
  Ids := CollectClassIds(AArchivePath);
  MaxCheck := 1 shl 22;
  HasPassword := SevenZipTryGetPassword(AArchivePath, Password);
  { Quiet (no ICryptoGetTextPassword) makes encrypted-header Open return
    E_NOTIMPL. Authed QIs crypto, so a missing/wrong password is S_FALSE. }
  if HasPassword then
    OpenCb := T7zOpenAuthed.Create(Password)
  else
    OpenCb := T7zOpenQuiet.Create;
  SawEncrypted := False;
  for I := 0 to High(Ids) do
  begin
    AArc := nil;
    Hr := GCreateObject(@Ids[I], @IID_IInArchive, @AArc);
    if (Hr <> S_OK) or not Assigned(AArc) then
    begin
      AArc := nil;
      Continue;
    end;
    Dummy := 0;
    St.Seek(0, STREAM_SEEK_SET, @Dummy);
    Hr := AArc.Open(St, @MaxCheck, OpenCb);
    if Hr = S_OK then
      Exit(True);
    if Hr = E_NOTIMPL then
      SawEncrypted := True
    else if HasPassword and (Hr = S_FALSE) then
      SawEncrypted := True;
    AArc.Close;
    AArc := nil;
  end;
  if SawEncrypted then
    AError := 'Encrypted'
  else
    AError := 'Not a supported archive';
end;

function ReadItem(const AArc: IInArchive; AIndex: UInt32; out AItem: T7zItem): Boolean;
var
  P: TPropVariant;
begin
  FillChar(AItem, SizeOf(AItem), 0);
  AItem.Index := AIndex;
  FillChar(P, SizeOf(P), 0);
  if HResOk(AArc.GetProperty(AIndex, kpidPath, P)) then
  begin
    AItem.Path := SevenZipNormInner(PropStr(P));
    PropVariantClear(P);
  end;
  FillChar(P, SizeOf(P), 0);
  if HResOk(AArc.GetProperty(AIndex, kpidIsDir, P)) then
  begin
    AItem.IsDir := PropBool(P);
    PropVariantClear(P);
  end;
  FillChar(P, SizeOf(P), 0);
  if HResOk(AArc.GetProperty(AIndex, kpidSize, P)) then
  begin
    AItem.Size := Int64(PropUInt64(P));
    PropVariantClear(P);
  end;
  FillChar(P, SizeOf(P), 0);
  if HResOk(AArc.GetProperty(AIndex, kpidEncrypted, P)) then
  begin
    AItem.Encrypted := PropBool(P);
    PropVariantClear(P);
  end;
  FillChar(P, SizeOf(P), 0);
  if HResOk(AArc.GetProperty(AIndex, kpidMTime, P)) then
  begin
    AItem.MTime := PropFileTime(P);
    PropVariantClear(P);
  end;
  FillChar(P, SizeOf(P), 0);
  if HResOk(AArc.GetProperty(AIndex, kpidAttrib, P)) then
  begin
    AItem.Attrib := Cardinal(PropUInt64(P));
    PropVariantClear(P);
  end;
  Result := AItem.Path <> '';
end;

function SevenZipLoadEngine(const ADllPath: string): Boolean;
begin
  GLock.Acquire;
  try
    if (GModule <> 0) and Assigned(GCreateObject) then
      Exit(True);
    GModule := LoadLibrary(PChar(ADllPath));
    Result := GModule <> 0;
    if not Result then
      Exit;
    GCreateObject := TCreateObjectFn(GetProcAddress(GModule, 'CreateObject'));
    if not Assigned(GCreateObject) then
    begin
      FreeLibrary(GModule);
      GModule := 0;
      Result := False;
      Exit;
    end;
    GGetNumberOfFormats := TGetNumberOfFormatsFn(
      GetProcAddress(GModule, 'GetNumberOfFormats'));
    GGetHandlerProperty2 := TGetHandlerProperty2Fn(
      GetProcAddress(GModule, 'GetHandlerProperty2'));
    LoadFormatTable;
  finally
    GLock.Release;
  end;
end;

procedure SevenZipUnloadEngine;
begin
  GLock.Acquire;
  try
    GCreateObject := nil;
    GGetNumberOfFormats := nil;
    GGetHandlerProperty2 := nil;
    SetLength(GFormats, 0);
    if Assigned(GPasswords) then
      GPasswords.Clear;
    if GModule <> 0 then
    begin
      FreeLibrary(GModule);
      GModule := 0;
    end;
  finally
    GLock.Release;
  end;
  SevenZipClearNestedCache;
end;

function SevenZipEngineLoaded: Boolean;
begin
  Result := Assigned(GCreateObject);
end;

function SevenZipListArchive(const AArchivePath: string; out AItems: TArray<T7zItem>;
  out AError: string): Boolean;
var
  Arc: IInArchive;
  N, I: UInt32;
  Item: T7zItem;
begin
  SetLength(AItems, 0);
  GLock.Acquire;
  try
    Result := OpenArchive(AArchivePath, Arc, AError);
    if not Result then
      Exit;
    if not HResOk(Arc.GetNumberOfItems(N)) then
    begin
      AError := 'GetNumberOfItems failed';
      Result := False;
      Exit;
    end;
    SetLength(AItems, N);
    for I := 0 to N - 1 do
    begin
      ReadItem(Arc, I, Item);
      if (Item.Path = '') and (N = 1) then
        // Single-stream compressors (gzip/bzip2/xz/lzma) don't always embed
        // the original name in their header -- e.g. `tar czf` output has no
        // FNAME flag, so 7z.dll's kpidPath comes back blank. Real 7-Zip
        // falls back to the archive's own file name with its outer
        // extension stripped (foo.tar.gz -> foo.tar); do the same instead
        // of exposing an unnamed entry that SevenZipListToJson then drops.
        Item.Path := TPath.GetFileNameWithoutExtension(AArchivePath);
      AItems[I] := Item;
    end;
    Arc.Close;
  finally
    GLock.Release;
  end;
end;

function SevenZipExtractFile(const AArchivePath, AInnerPath: string; AMaxBytes: Int64;
  out ABytes: TBytes; out AError: string): Boolean;
var
  Arc: IInArchive;
  Items: TArray<T7zItem>;
  Dummy: string;
  I: Integer;
  Idx: UInt32;
  Want: string;
    Mem: T7zMemOutStream;
    Hold: ISequentialOutStream;
    Cb: T7zExtractCallback;
    HoldCb: IArchiveExtractCallback;
    Hr: HRESULT;
    Password: string;
begin
  Result := False;
  SetLength(ABytes, 0);
  AError := '';
  Want := SevenZipNormInner(AInnerPath);
  if Want = '' then
  begin
    AError := 'Empty inner path';
    Exit;
  end;
  if not SevenZipListArchive(AArchivePath, Items, Dummy) then
  begin
    AError := Dummy;
    Exit;
  end;
  Idx := $FFFFFFFF;
    for I := 0 to High(Items) do
    if (not Items[I].IsDir) and SameText(Items[I].Path, Want) then
    begin
      Idx := Items[I].Index;
      Break;
    end;
  if Idx = $FFFFFFFF then
  begin
    AError := 'Not found';
    Exit;
  end;

  GLock.Acquire;
  try
    if not OpenArchive(AArchivePath, Arc, AError) then
      Exit;
    Mem := T7zMemOutStream.Create(AMaxBytes);
    Hold := Mem;
    if not SevenZipTryGetPassword(AArchivePath, Password) then
      Password := '';
    Cb := T7zExtractCallback.Create(Mem, Password);
    HoldCb := Cb;
    Hr := Arc.Extract(@Idx, 1, 0, HoldCb);
    if Mem.Overflow then
    begin
      AError := 'Too large';
      Arc.Close;
      Exit;
    end;
    if (not HResOk(Hr)) or (Cb.OpRes <> 0) then
    begin
      if Cb.OpRes = 9 then
        AError := 'Encrypted'
      else
        AError := 'Extract failed';
      Arc.Close;
      Exit;
    end;
    Result := Mem.CopyBytes(ABytes);
    Arc.Close;
  finally
    GLock.Release;
  end;
end;

function SevenZipCreateSimpleArchive(const AArchivePath, ASourceFile: string;
  out AError: string): Boolean;
begin
  Result := SevenZipAddLocalPath(AArchivePath, ASourceFile,
    ExtractFileName(ASourceFile), True, AError);
end;

function NestedCacheDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-7z-nested');
end;

function SevenZipResolveNestedArchive(const AOuterArchivePath, AEntryPath: string;
  out ATempFilePath: string; out AError: string): Boolean;
var
  Want, Key, Dir, FileName, Cached: string;
  OuterStamp: TDateTime;
  Items: TArray<T7zItem>;
  Dummy: string;
  I: Integer;
  Size: Int64;
  Data: TBytes;
begin
  Result := False;
  AError := '';
  ATempFilePath := '';
  Want := SevenZipNormInner(AEntryPath);
  if Want = '' then
  begin
    AError := 'Empty inner path';
    Exit;
  end;

  OuterStamp := 0;
  if TFile.Exists(AOuterArchivePath) then
    OuterStamp := TFile.GetLastWriteTime(AOuterArchivePath);
  Key := LowerCase(AOuterArchivePath) + '|' + LowerCase(Want) + '|' +
    FormatDateTime('yyyymmddhhnnsszzz', OuterStamp);

  GLock.Acquire;
  try
    if Assigned(GNestedCache) and GNestedCache.TryGetValue(Key, Cached) and
       TFile.Exists(Cached) then
    begin
      ATempFilePath := Cached;
      Exit(True);
    end;
  finally
    GLock.Release;
  end;

  if not SevenZipListArchive(AOuterArchivePath, Items, Dummy) then
  begin
    AError := Dummy;
    Exit;
  end;
  Size := -1;
  for I := 0 to High(Items) do
    if (not Items[I].IsDir) and SameText(Items[I].Path, Want) then
    begin
      Size := Items[I].Size;
      Break;
    end;
  if Size < 0 then
  begin
    AError := 'Not found';
    Exit;
  end;

  if not SevenZipExtractFile(AOuterArchivePath, Want, Size + 4096, Data, AError) then
    Exit;

  GLock.Acquire;
  try
    Dir := NestedCacheDir;
    TDirectory.CreateDirectory(Dir);
    Inc(GNestedSeq);
    FileName := Format('n%.6d_%s', [GNestedSeq, ExtractFileName(Want)]);
    if ExtractFileName(Want) = '' then
      FileName := Format('n%.6d.bin', [GNestedSeq]);
    Cached := TPath.Combine(Dir, FileName);
    TFile.WriteAllBytes(Cached, Data);
    if not Assigned(GNestedCache) then
      GNestedCache := TDictionary<string, string>.Create;
    GNestedCache.AddOrSetValue(Key, Cached);
  finally
    GLock.Release;
  end;
  ATempFilePath := Cached;
  Result := True;
end;

procedure SevenZipClearNestedCache;
var
  Dir: string;
begin
  GLock.Acquire;
  try
    if Assigned(GNestedCache) then
      GNestedCache.Clear;
  finally
    GLock.Release;
  end;
  Dir := NestedCacheDir;
  if TDirectory.Exists(Dir) then
    try
      TDirectory.Delete(Dir, True);
    except
      // Best effort -- a file still open (e.g. mid-read) just stays behind
      // in the OS temp dir; not worth failing shutdown over.
    end;
end;

procedure AppendPackItem(var AItems: TArray<T7zPackItem>; const AItem: T7zPackItem);
var
  N: Integer;
begin
  N := Length(AItems);
  SetLength(AItems, N + 1);
  AItems[N] := AItem;
end;

procedure FillPackTimes(const APath: string; var AItem: T7zPackItem);
var
  FH: THandle;
  CT, AT, WT: TFileTime;
begin
  FillChar(AItem.Time, SizeOf(AItem.Time), 0);
  FH := CreateFile(PChar(APath), GENERIC_READ, FILE_SHARE_READ, nil,
    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL or FILE_FLAG_BACKUP_SEMANTICS, 0);
  if FH = INVALID_HANDLE_VALUE then
    Exit;
  try
    if GetFileTime(FH, @CT, @AT, @WT) then
      AItem.Time := WT;
  finally
    CloseHandle(FH);
  end;
end;

procedure CollectPackTree(const ALocalPath, AInnerPath: string;
  var AItems: TArray<T7zPackItem>);
var
  Item: T7zPackItem;
  Files: TArray<string>;
  One, Rel, Inner: string;
  Root: string;
begin
  Root := ExcludeTrailingPathDelimiter(ALocalPath);
  Inner := SevenZipNormInner(AInnerPath);
  if TFile.Exists(Root) and not TDirectory.Exists(Root) then
  begin
    FillChar(Item, SizeOf(Item), 0);
    Item.LocalPath := Root;
    if Inner = '' then
      Item.InnerPath := ExtractFileName(Root)
    else
      Item.InnerPath := Inner;
    Item.IsDir := False;
    Item.Size := TFile.GetSize(Root);
    FillPackTimes(Root, Item);
    AppendPackItem(AItems, Item);
    Exit;
  end;
  if not TDirectory.Exists(Root) then
    Exit;
  Files := TDirectory.GetFiles(Root, '*', TSearchOption.soAllDirectories);
  if Length(Files) = 0 then
  begin
    FillChar(Item, SizeOf(Item), 0);
    Item.LocalPath := Root;
    Item.InnerPath := Inner;
    Item.IsDir := True;
    FillPackTimes(Root, Item);
    if Item.InnerPath <> '' then
      AppendPackItem(AItems, Item);
    Exit;
  end;
  for One in Files do
  begin
    Rel := Copy(One, Length(Root) + 2, MaxInt);
    Rel := StringReplace(Rel, '\', '/', [rfReplaceAll]);
    FillChar(Item, SizeOf(Item), 0);
    Item.LocalPath := One;
    if Inner = '' then
      Item.InnerPath := Rel
    else
      Item.InnerPath := Inner + '/' + Rel;
    Item.IsDir := False;
    try
      Item.Size := TFile.GetSize(One);
    except
      Item.Size := 0;
    end;
    FillPackTimes(One, Item);
    AppendPackItem(AItems, Item);
  end;
end;

function SevenZipAddLocalPath(const AArchivePath, ALocalPath, AInnerPath: string;
  AOverwrite: Boolean; out AError: string): Boolean;
var
  NewItems: TArray<T7zPackItem>;
  Keep: TArray<UInt32>;
  ArcIn: IInArchive;
  ArcOut: IOutArchive;
  OutSt: IOutStream;
  Cb: IArchiveUpdateCallback;
  Hr: HRESULT;
  N, I: UInt32;
  Old: T7zItem;
  Skip: Boolean;
  J, K: Integer;
  TmpPath, Want: string;
  ExistsArc: Boolean;
begin
  Result := False;
  AError := '';
  SetLength(NewItems, 0);
  CollectPackTree(ALocalPath, AInnerPath, NewItems);
  if Length(NewItems) = 0 then
  begin
    AError := 'Nothing to pack';
    Exit;
  end;
    ExistsArc := FileExists(AArchivePath);
  TmpPath := AArchivePath + '.mtn2-pack.tmp';
  GLock.Acquire;
  try
    if not Assigned(GCreateObject) then
    begin
      AError := '7z.dll is not loaded';
      Exit;
    end;
    SetLength(Keep, 0);
    ArcIn := nil;
    ArcOut := nil;
    if ExistsArc then
    begin
      if not OpenArchive(AArchivePath, ArcIn, AError) then
        Exit;
      if not HResOk(ArcIn.GetNumberOfItems(N)) then
      begin
        AError := 'GetNumberOfItems failed';
        Exit;
      end;
      for I := 0 to N - 1 do
      begin
        ReadItem(ArcIn, I, Old);
        Skip := False;
        for J := 0 to High(NewItems) do
        begin
          Want := SevenZipNormInner(NewItems[J].InnerPath);
          if SameText(Old.Path, Want) then
          begin
            if not AOverwrite then
            begin
              AError := 'Already exists';
              Exit;
            end;
            Skip := True;
            Break;
          end;
        end;
        if not Skip then
        begin
          K := Length(Keep);
          SetLength(Keep, K + 1);
          Keep[K] := I;
        end;
      end;
      // Same handler object implements IInArchive + IOutArchive for .7z.
      if not Supports(ArcIn, IOutArchive, ArcOut) then
      begin
        AError := 'This archive format cannot be updated';
        Exit;
      end;
    end
    else
    begin
      Hr := Create7zObject(IID_IOutArchive, @ArcOut);
      if not HResOk(Hr) or not Assigned(ArcOut) then
      begin
        AError := Format('CreateObject(IOutArchive) failed: 0x%x', [Hr]);
        Exit;
      end;
    end;
    if FileExists(TmpPath) then
      TFile.Delete(TmpPath);
    OutSt := T7zFileStream.Create(TmpPath, fmCreate);
    Cb := T7zPackCallback.Create(Keep, NewItems);
    Hr := ArcOut.UpdateItems(OutSt, UInt32(Length(Keep) + Length(NewItems)), Cb);
    OutSt := nil;
    Cb := nil;
    ArcOut := nil;
    if Assigned(ArcIn) then
    begin
      ArcIn.Close;
      ArcIn := nil;
    end;
    if not HResOk(Hr) then
    begin
      if FileExists(TmpPath) then
        TFile.Delete(TmpPath);
      AError := Format('UpdateItems failed: 0x%x', [Hr]);
      Exit;
    end;
    if ExistsArc then
    begin
      if not System.SysUtils.DeleteFile(AArchivePath) then
      begin
        if FileExists(TmpPath) then
          TFile.Delete(TmpPath);
        AError := 'Cannot replace archive';
        Exit;
      end;
    end;
    try
      TFile.Move(TmpPath, AArchivePath);
    except
      on E: Exception do
      begin
        AError := 'Cannot write archive: ' + E.Message;
        Exit;
      end;
    end;
    Result := True;
  finally
    GLock.Release;
  end;
end;

initialization
  GLock := TCriticalSection.Create;
  GPasswords := TDictionary<string, string>.Create;
  GNestedCache := TDictionary<string, string>.Create;
  GNestedSeq := 0;
  GModule := 0;
  GCreateObject := nil;
  GGetNumberOfFormats := nil;
  GGetHandlerProperty2 := nil;

finalization
  SevenZipUnloadEngine;
  FreeAndNil(GPasswords);
  FreeAndNil(GNestedCache);
  FreeAndNil(GLock);

end.
