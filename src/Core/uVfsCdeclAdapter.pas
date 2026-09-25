unit uVfsCdeclAdapter;

{ Bridges a plugin's C-ABI VFS callback table (TVfsCallbacksCdecl,
  uPluginHostAbi.pas) into the host's native IVirtualFileSystem interface
  (uVfsTypes.pas), so a DLL plugin can register a VFS backend into the same
  IVfsRegistry used by built-in backends (uVfsRegistry.pas). This is the
  missing link identified during the plugin-readiness audit: the cdecl ABI
  and the Pascal-interface registry existed but nothing connected them.

  Each Async method runs the (synchronous) cdecl callback on a background
  thread and delivers the result via TThread.Queue, matching the pattern
  used throughout uFileVfs.pas. Buffer-fill calls (ListDirectory/ReadText/
  ReadBytes) use a single fixed-size buffer — if the plugin reports the
  result doesn't fit (verNeedsBiggerBuffer), the call fails with vecIOError;
  there is no retry-with-bigger-buffer loop in this first version. }

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections, System.Math,
  uVfsTypes, uTextEncoding, uPluginHostAbi;

const
  /// <summary>Single-shot buffer size for ListDirectory/ReadText/ReadBytes.
  /// A plugin whose result doesn't fit should keep it under this, or the
  /// call fails (see unit comment) — generous for typical directory
  /// listings and small text files.</summary>
  cCdeclVfsBufferSize = 4 * 1024 * 1024;

type
  /// <summary>Wraps a plugin-supplied TVfsCallbacksCdecl + opaque AUserData
  /// pointer as a host-native IVirtualFileSystem backend.</summary>
  TCdeclVfsBackend = class(TInterfacedObject, IVirtualFileSystem)
  private
    FCallbacks: TVfsCallbacksCdecl;
    FUserData: Pointer;
    function ErrorFromResult(ACode: Int64; const AURI: string): TVfsError;
  public
    constructor Create(const ACallbacks: TVfsCallbacksCdecl; AUserData: Pointer);
    procedure ListDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsListCallback);
    procedure DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
      ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
      AOnDone: TVfsBoolCallback);
    procedure CreateDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsBoolCallback);
    procedure CopyAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure MoveAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure ReadTextAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
    procedure ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
    procedure WriteTextAsync(const AURI, AText: string; AEncoding: TTextFileEncoding;
      ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
    procedure ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsExistsCallback);
    procedure GetFreeSpaceAsync(const ARootURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsFreeSpaceCallback);
  end;

/// <summary>Decodes the UTF-8 JSON array a plugin's ListDirectory callback
/// wrote into its buffer. Per-entry fields: name, ext, size (Int64),
/// isDir/isHidden/isReadOnly/isSystem/isArchive/isCompressed/isEncrypted/
/// isTemporary/isOffline/isLink (bool), created/modified/accessed (Int64
/// Unix seconds, 0 = unknown), targetUri (string, '' = none). Unknown
/// fields are ignored; missing fields default to False/0/''.</summary>
function EntriesFromJson(const AJson: string): TArray<TVfsEntry>;

implementation

uses
  System.DateUtils;

function EntriesFromJson(const AJson: string): TArray<TVfsEntry>;
var
  Val: TJSONValue;
  Arr: TJSONArray;
  Obj: TJSONObject;
  List: TList<TVfsEntry>;
  I: Integer;
  E: TVfsEntry;

  function GetBool(const AName: string): Boolean;
  var
    V: TJSONValue;
  begin
    V := Obj.Values[AName];
    Result := (V is TJSONBool) and TJSONBool(V).AsBoolean;
  end;

  function GetInt64(const AName: string): Int64;
  var
    V: TJSONValue;
  begin
    V := Obj.Values[AName];
    if V is TJSONNumber then
      Result := TJSONNumber(V).AsInt64
    else
      Result := 0;
  end;

  function GetStr(const AName: string): string;
  var
    V: TJSONValue;
  begin
    V := Obj.Values[AName];
    if V is TJSONString then
      Result := TJSONString(V).Value
    else
      Result := '';
  end;

  function UnixToDateTime(ASeconds: Int64): TDateTime;
  begin
    if ASeconds <= 0 then
      Result := 0
    else
      Result := System.DateUtils.UnixToDateTime(ASeconds, False);
  end;

begin
  List := TList<TVfsEntry>.Create;
  try
    Val := TJSONObject.ParseJSONValue(AJson);
    if Assigned(Val) then
    try
      if Val is TJSONArray then
      begin
        Arr := TJSONArray(Val);
        for I := 0 to Arr.Count - 1 do
        begin
          if not (Arr.Items[I] is TJSONObject) then
            Continue;
          Obj := TJSONObject(Arr.Items[I]);
          E.Name := GetStr('name');
          E.Extension := GetStr('ext');
          E.Size := GetInt64('size');
          E.IsDirectory := GetBool('isDir');
          E.IsHidden := GetBool('isHidden');
          E.IsReadOnly := GetBool('isReadOnly');
          E.IsSystem := GetBool('isSystem');
          E.IsArchive := GetBool('isArchive');
          E.IsCompressed := GetBool('isCompressed');
          E.IsEncrypted := GetBool('isEncrypted');
          E.IsTemporary := GetBool('isTemporary');
          E.IsOffline := GetBool('isOffline');
          E.IsLink := GetBool('isLink');
          E.CreationTime := UnixToDateTime(GetInt64('created'));
          E.ModificationTime := UnixToDateTime(GetInt64('modified'));
          E.AccessTime := UnixToDateTime(GetInt64('accessed'));
          E.TargetURI := GetStr('targetUri');
          List.Add(E);
        end;
      end;
    finally
      Val.Free;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

constructor TCdeclVfsBackend.Create(const ACallbacks: TVfsCallbacksCdecl; AUserData: Pointer);
begin
  inherited Create;
  FCallbacks := ACallbacks;
  FUserData := AUserData;
end;

function TCdeclVfsBackend.ErrorFromResult(ACode: Int64; const AURI: string): TVfsError;
begin
  case TVfsCdeclResult(ACode) of
    verOk: Result := TVfsError.Ok;
    verNotFound: Result := TVfsError.Make(vecNotFound, 'Not found', AURI);
    verAccessDenied: Result := TVfsError.Make(vecAccessDenied, 'Access denied', AURI);
    verAlreadyExists: Result := TVfsError.Make(vecAlreadyExists, 'Already exists', AURI);
    verNotSupported: Result := TVfsError.Make(vecNotSupported, 'Not supported by plugin', AURI);
    verInvalidURI: Result := TVfsError.Make(vecInvalidURI, 'Invalid URI', AURI);
    verNeedsBiggerBuffer: Result := TVfsError.Make(vecIOError,
      'Plugin result exceeded the single-shot buffer size', AURI);
  else
    Result := TVfsError.Make(vecIOError, 'Plugin VFS error', AURI);
  end;
end;

procedure TCdeclVfsBackend.ListDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsListCallback);
var
  URI: string;
  OnDone: TVfsListCallback;
  Callbacks: TVfsCallbacksCdecl;
  UserData: Pointer;
begin
  URI := AURI;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  TThread.CreateAnonymousThread(
    procedure
    var
      Buf: TBytes;
      Negotiated, Code: Int64;
      Items: TArray<TVfsEntry>;
      Err: TVfsError;
      Json: string;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      SetLength(Items, 0);
      if not Assigned(Callbacks.ListDirectory) then
        Err := TVfsError.Make(vecNotSupported, 'Plugin has no ListDirectory callback', URI)
      else
      begin
        SetLength(Buf, cCdeclVfsBufferSize);
        Code := Callbacks.ListDirectory(PAnsiChar(UTF8String(URI)), UserData,
          PAnsiChar(Buf), Length(Buf), Negotiated);
        if Code = 0 then
        begin
          Json := TEncoding.UTF8.GetString(Buf, 0, EnsureRange(Negotiated, 0, Length(Buf)));
          try
            Items := EntriesFromJson(Json);
          except
            on E: Exception do
              Err := TVfsError.Make(vecIOError, 'Bad JSON from plugin: ' + E.Message, URI);
          end;
        end
        else
          Err := ErrorFromResult(Code, URI);
      end;

      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Items, Err);
        end);
    end).Start;
end;

procedure TCdeclVfsBackend.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
var
  URI: string;
  Mode: TVfsDeleteMode;
  OnDone: TVfsBoolCallback;
  Callbacks: TVfsCallbacksCdecl;
  UserData: Pointer;
begin
  URI := AURI;
  Mode := AMode;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  TThread.CreateAnonymousThread(
    procedure
    var
      Code: Int64;
      Err: TVfsError;
      Ok: Boolean;
    begin
      if not Assigned(Callbacks.Delete) then
      begin
        Err := TVfsError.Make(vecNotSupported, 'Plugin has no Delete callback', URI);
        Ok := False;
      end
      else
      begin
        Code := Callbacks.Delete(PAnsiChar(UTF8String(URI)), Ord(Mode), UserData);
        Ok := Code = 0;
        Err := ErrorFromResult(Code, URI);
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Ok, Err);
        end);
    end).Start;
end;

procedure TCdeclVfsBackend.CreateDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
var
  URI: string;
  OnDone: TVfsBoolCallback;
  Callbacks: TVfsCallbacksCdecl;
  UserData: Pointer;
begin
  URI := AURI;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  TThread.CreateAnonymousThread(
    procedure
    var
      Code: Int64;
      Err: TVfsError;
      Ok: Boolean;
    begin
      if not Assigned(Callbacks.CreateDirectory) then
      begin
        Err := TVfsError.Make(vecNotSupported, 'Plugin has no CreateDirectory callback', URI);
        Ok := False;
      end
      else
      begin
        Code := Callbacks.CreateDirectory(PAnsiChar(UTF8String(URI)), UserData);
        Ok := Code = 0;
        Err := ErrorFromResult(Code, URI);
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Ok, Err);
        end);
    end).Start;
end;

procedure TCdeclVfsBackend.CopyAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
var
  FromURI, ToURI: string;
  Overwrite: Boolean;
  OnDone: TVfsBoolCallback;
  Callbacks: TVfsCallbacksCdecl;
  UserData: Pointer;
begin
  FromURI := AFromURI;
  ToURI := AToURI;
  Overwrite := AOverwrite;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  TThread.CreateAnonymousThread(
    procedure
    var
      Code: Int64;
      Err: TVfsError;
      Ok: Boolean;
      FromU, ToU: UTF8String;
    begin
      if not Assigned(Callbacks.CopyItem) then
      begin
        Err := TVfsError.Make(vecNotSupported, 'Plugin has no CopyItem callback', FromURI);
        Ok := False;
      end
      else
      begin
        FromU := UTF8String(FromURI);
        ToU := UTF8String(ToURI);
        Code := Callbacks.CopyItem(PAnsiChar(FromU), PAnsiChar(ToU),
          Ord(Overwrite), UserData);
        Ok := Code = 0;
        Err := ErrorFromResult(Code, FromURI);
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Ok, Err);
        end);
    end).Start;
end;

procedure TCdeclVfsBackend.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
var
  FromURI, ToURI: string;
  Overwrite: Boolean;
  OnDone: TVfsBoolCallback;
  Callbacks: TVfsCallbacksCdecl;
  UserData: Pointer;
begin
  FromURI := AFromURI;
  ToURI := AToURI;
  Overwrite := AOverwrite;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  TThread.CreateAnonymousThread(
    procedure
    var
      Code: Int64;
      Err: TVfsError;
      Ok: Boolean;
      FromU, ToU: UTF8String;
    begin
      if not Assigned(Callbacks.MoveItem) then
      begin
        Err := TVfsError.Make(vecNotSupported, 'Plugin has no MoveItem callback', FromURI);
        Ok := False;
      end
      else
      begin
        FromU := UTF8String(FromURI);
        ToU := UTF8String(ToURI);
        Code := Callbacks.MoveItem(PAnsiChar(FromU), PAnsiChar(ToU),
          Ord(Overwrite), UserData);
        Ok := Code = 0;
        Err := ErrorFromResult(Code, FromURI);
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Ok, Err);
        end);
    end).Start;
end;

procedure TCdeclVfsBackend.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
var
  URI: string;
  MaxBytes: Int64;
  OnDone: TVfsTextCallback;
  Callbacks: TVfsCallbacksCdecl;
  UserData: Pointer;
begin
  URI := AURI;
  MaxBytes := AMaxBytes;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  TThread.CreateAnonymousThread(
    procedure
    var
      Buf: TBytes;
      Negotiated, Code: Int64;
      Text: string;
      Err: TVfsError;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      Text := '';
      if not Assigned(Callbacks.ReadText) then
        Err := TVfsError.Make(vecNotSupported, 'Plugin has no ReadText callback', URI)
      else
      begin
        SetLength(Buf, cCdeclVfsBufferSize);
        Code := Callbacks.ReadText(PAnsiChar(UTF8String(URI)), MaxBytes, UserData,
          PAnsiChar(Buf), Length(Buf), Negotiated);
        if Code = 0 then
          Text := TEncoding.UTF8.GetString(Buf, 0, EnsureRange(Negotiated, 0, Length(Buf)))
        else
          Err := ErrorFromResult(Code, URI);
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Text, tfeUtf8, Err);
        end);
    end).Start;
end;

procedure TCdeclVfsBackend.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
var
  URI: string;
  MaxBytes: Int64;
  OnDone: TVfsBytesCallback;
  Callbacks: TVfsCallbacksCdecl;
  UserData: Pointer;
begin
  URI := AURI;
  MaxBytes := AMaxBytes;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  TThread.CreateAnonymousThread(
    procedure
    var
      Buf: TBytes;
      Negotiated, Code: Int64;
      Result: TBytes;
      Err: TVfsError;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      SetLength(Result, 0);
      if not Assigned(Callbacks.ReadBytes) then
        Err := TVfsError.Make(vecNotSupported, 'Plugin has no ReadBytes callback', URI)
      else
      begin
        SetLength(Buf, cCdeclVfsBufferSize);
        Code := Callbacks.ReadBytes(PAnsiChar(UTF8String(URI)), MaxBytes, UserData,
          PByte(Buf), Length(Buf), Negotiated);
        if Code = 0 then
        begin
          if (Negotiated < 0) or (Negotiated > Length(Buf)) then
            Err := TVfsError.Make(vecIOError, 'Result exceeded buffer', URI)
          else
            Result := Copy(Buf, 0, Negotiated);
        end
        else
          Err := ErrorFromResult(Code, URI);
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Result, Err);
        end);
    end).Start;
end;

procedure TCdeclVfsBackend.WriteTextAsync(const AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
var
  URI, Text: string;
  OnDone: TVfsBoolCallback;
  Callbacks: TVfsCallbacksCdecl;
  UserData: Pointer;
begin
  URI := AURI;
  Text := AText;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  TThread.CreateAnonymousThread(
    procedure
    var
      Code: Int64;
      Err: TVfsError;
      Ok: Boolean;
    begin
      if not Assigned(Callbacks.WriteText) then
      begin
        Err := TVfsError.Make(vecNotSupported, 'Plugin has no WriteText callback', URI);
        Ok := False;
      end
      else
      begin
        Code := Callbacks.WriteText(PAnsiChar(UTF8String(URI)),
          PAnsiChar(UTF8String(Text)), UserData);
        Ok := Code = 0;
        Err := ErrorFromResult(Code, URI);
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Ok, Err);
        end);
    end).Start;
end;

procedure TCdeclVfsBackend.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
var
  URI: string;
  OnDone: TVfsExistsCallback;
  Callbacks: TVfsCallbacksCdecl;
  UserData: Pointer;
begin
  URI := AURI;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  TThread.CreateAnonymousThread(
    procedure
    var
      Code: Int64;
      IsDir: Int64;
      Err: TVfsError;
      Exists: Boolean;
    begin
      IsDir := 0;
      if not Assigned(Callbacks.Exists) then
      begin
        Err := TVfsError.Make(vecNotSupported, 'Plugin has no Exists callback', URI);
        Exists := False;
      end
      else
      begin
        Code := Callbacks.Exists(PAnsiChar(UTF8String(URI)), UserData, IsDir);
        Exists := Code = 0;
        Err := ErrorFromResult(Code, URI);
        if Code = Int64(verNotFound) then
          Err := TVfsError.Ok; // "not found" is a normal ExistsAsync=False result, not an error
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Exists, IsDir <> 0, Err);
        end);
    end).Start;
end;

procedure TCdeclVfsBackend.GetFreeSpaceAsync(const ARootURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsFreeSpaceCallback);
var
  URI: string;
  OnDone: TVfsFreeSpaceCallback;
  Callbacks: TVfsCallbacksCdecl;
  UserData: Pointer;
begin
  URI := ARootURI;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  TThread.CreateAnonymousThread(
    procedure
    var
      Code, LFree, LTotal: Int64;
      Err: TVfsError;
    begin
      LFree := -1;
      LTotal := -1;
      if not Assigned(Callbacks.GetFreeSpace) then
        Err := TVfsError.Make(vecNotSupported, 'Plugin has no GetFreeSpace callback', URI)
      else
      begin
        Code := Callbacks.GetFreeSpace(PAnsiChar(UTF8String(URI)), UserData, LFree, LTotal);
        Err := ErrorFromResult(Code, URI);
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(LFree, LTotal, Err);
        end);
    end).Start;
end;

end.
