unit uVfsCdeclAdapterV2;

{ Bridges a plugin's version 2 VFS callback table (TVfsCallbacksCdeclV2,
  uPluginHostAbi.pas) into IVirtualFileSystem. Like uVfsCdeclAdapter.pas each
  call runs the synchronous cdecl callback on a background thread and delivers
  the result through TThread.Queue; in addition every call gets an operation
  context (TVfsOpContext) through which the plugin reports progress, polls
  for cancellation and attaches a message to a failure, listings arrive in
  pages, and a result that does not fit the buffer is retried once with the
  size the plugin asked for. }

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections,
  uVfsTypes, uTextEncoding, uPluginHostAbi;

const
  /// <summary>First buffer for a listing page or a read; a bigger one is used
  /// when the plugin asks for it (verNeedsBiggerBuffer).</summary>
  cCdeclV2FirstBufferSize = 4 * 1024 * 1024;
  cCdeclV2MaxBufferSize = 256 * 1024 * 1024;
  /// <summary>Progress reports of one call reach the UI at most this often.</summary>
  cCdeclV2ProgressIntervalMs = 80;

type
  TCdeclVfsBackendV2 = class(TInterfacedObject, IVirtualFileSystem)
  private
    FCallbacks: TVfsCallbacksCdeclV2;
    FUserData: Pointer;
  public
    constructor Create(const ACallbacks: TVfsCallbacksCdeclV2; AUserData: Pointer);
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

/// <summary>Maps a result code of the version 2 table to a VFS error; AText
/// (what the plugin gave through SetErrorText) replaces the stock message.</summary>
function V2ErrorFromCode(ACode: Int64; const AURI, AText: string): TVfsError;

implementation

uses
  uVfsCdeclAdapter;

type
  /// <summary>State of one call: the context the plugin sees, the cancel
  /// token and the progress sink. Lives on the worker thread that runs the
  /// plugin call.</summary>
  TOpState = class
  public
    Ctx: TVfsOpContext;
    Cancel: IJobCancelToken;
    OnProgress: TVfsProgressCallback;
    ErrorText: string;
    LastReportTick: UInt64;
    constructor Create(const ACancel: IJobCancelToken;
      const AOnProgress: TVfsProgressCallback);
    function CtxPtr: PVfsOpContext;
  end;

function OpReportProgress(ACtx: PVfsOpContext; ADone, ATotal, AItemDone,
  AItemTotal: Int64; AName: PAnsiChar): Int64; cdecl;
var
  St: TOpState;
  Name: string;
  Tick: UInt64;
  Sink: TVfsProgressCallback;
begin
  Result := 0;
  try
    St := TOpState(ACtx^.Cookie);
    if JobCancelRequested(St.Cancel) then
      Exit(1);
    if not Assigned(St.OnProgress) then
      Exit;
    Tick := TThread.GetTickCount64;
    if (Tick - St.LastReportTick < cCdeclV2ProgressIntervalMs) and
       ((ATotal <= 0) or (ADone < ATotal)) then
      Exit;
    St.LastReportTick := Tick;
    if AName <> nil then
      Name := UTF8ToString(AName)
    else
      Name := '';
    Sink := St.OnProgress;
    TThread.Queue(nil,
      procedure
      begin
        Sink(ADone, ATotal, Name, AItemDone, AItemTotal, '', '');
      end);
  except
    Result := 0;
  end;
end;

function OpIsCancelled(ACtx: PVfsOpContext): Int64; cdecl;
begin
  try
    Result := Ord(JobCancelRequested(TOpState(ACtx^.Cookie).Cancel));
  except
    Result := 0;
  end;
end;

procedure OpSetErrorText(ACtx: PVfsOpContext; AText: PAnsiChar); cdecl;
begin
  try
    if AText = nil then
      TOpState(ACtx^.Cookie).ErrorText := ''
    else
      TOpState(ACtx^.Cookie).ErrorText := UTF8ToString(AText);
  except
    // The text is a courtesy; the result code still carries the failure.
  end;
end;

constructor TOpState.Create(const ACancel: IJobCancelToken;
  const AOnProgress: TVfsProgressCallback);
begin
  inherited Create;
  Cancel := ACancel;
  OnProgress := AOnProgress;
  Ctx.Cookie := Self;
  Ctx.ReportProgress := OpReportProgress;
  Ctx.IsCancelled := OpIsCancelled;
  Ctx.SetErrorText := OpSetErrorText;
end;

function TOpState.CtxPtr: PVfsOpContext;
begin
  Result := @Ctx;
end;

function V2ErrorFromCode(ACode: Int64; const AURI, AText: string): TVfsError;

  function Pick(const ADefault: string): string;
  begin
    if AText <> '' then
      Result := AText
    else
      Result := ADefault;
  end;

begin
  case ACode of
    Ord(verOk): Result := TVfsError.Ok;
    Ord(verNotFound): Result := TVfsError.Make(vecNotFound, Pick('Not found'), AURI);
    Ord(verAccessDenied): Result := TVfsError.Make(vecAccessDenied, Pick('Access denied'), AURI);
    Ord(verAlreadyExists): Result := TVfsError.Make(vecAlreadyExists, Pick('Already exists'), AURI);
    Ord(verNotSupported): Result := TVfsError.Make(vecNotSupported, Pick('Not supported by plugin'), AURI);
    Ord(verInvalidURI): Result := TVfsError.Make(vecInvalidURI, Pick('Invalid URI'), AURI);
    Ord(verCancelled): Result := TVfsError.Make(vecCancelled, Pick('Cancelled'), AURI);
    Ord(verAuthFailed): Result := TVfsError.Make(vecAccessDenied, Pick('Authentication failed'), AURI);
    Ord(verTimeout): Result := TVfsError.Make(vecIOError, Pick('Timed out'), AURI);
    Ord(verNeedsBiggerBuffer): Result := TVfsError.Make(vecIOError,
      Pick('Plugin result exceeded the buffer size'), AURI);
  else
    Result := TVfsError.Make(vecIOError, Pick('Plugin VFS error'), AURI);
  end;
end;

procedure RunWorker(const AProc: TProc);
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        AProc();
      except
        // Every worker body converts its own failures into a VFS error; an
        // exception that gets here must not take the process down.
      end;
    end).Start;
end;

constructor TCdeclVfsBackendV2.Create(const ACallbacks: TVfsCallbacksCdeclV2;
  AUserData: Pointer);
begin
  inherited Create;
  FCallbacks := ACallbacks;
  FUserData := AUserData;
end;

procedure TCdeclVfsBackendV2.ListDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsListCallback);
var
  URI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsListCallback;
  Callbacks: TVfsCallbacksCdeclV2;
  UserData: Pointer;
begin
  URI := AURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  RunWorker(
    procedure
    var
      State: TOpState;
      All: TList<TVfsEntry>;
      Page: TArray<TVfsEntry>;
      Buf: TBytes;
      Negotiated, More, Code, Offset: Int64;
      Items: TArray<TVfsEntry>;
      Err: TVfsError;
      UriU: UTF8String;
      Retried, Stop: Boolean;
    begin
      State := TOpState.Create(Cancel, nil);
      All := TList<TVfsEntry>.Create;
      try
        Err := TVfsError.Ok;
        Err.URI := URI;
        if not Assigned(Callbacks.ListDirectory) then
          Err := TVfsError.Make(vecNotSupported, 'Plugin has no ListDirectory callback', URI)
        else
        begin
          UriU := UTF8String(URI);
          SetLength(Buf, cCdeclV2FirstBufferSize);
          Offset := 0;
          Retried := False;
          Stop := False;
          while not Stop do
          begin
            Negotiated := 0;
            More := 0;
            Code := Callbacks.ListDirectory(PAnsiChar(UriU), UserData, State.CtxPtr, Offset,
              PAnsiChar(Buf), Length(Buf), Negotiated, More);
            if (Code = Ord(verNeedsBiggerBuffer)) and not Retried and
               (Negotiated > Length(Buf)) and (Negotiated <= cCdeclV2MaxBufferSize) then
            begin
              Retried := True;
              SetLength(Buf, Negotiated);
              Continue;
            end;
            Retried := False;
            if Code <> 0 then
            begin
              Err := V2ErrorFromCode(Code, URI, State.ErrorText);
              Break;
            end;
            try
              Page := EntriesFromJson(TEncoding.UTF8.GetString(Buf, 0,
                EnsureRange(Negotiated, 0, Length(Buf))));
            except
              on E: Exception do
              begin
                Err := TVfsError.Make(vecIOError, 'Bad JSON from plugin: ' + E.Message, URI);
                Break;
              end;
            end;
            All.AddRange(Page);
            Inc(Offset, Length(Page));
            if More = 0 then
              Stop := True
            else if Length(Page) = 0 then
            begin
              Err := TVfsError.Make(vecIOError, 'Plugin listing did not advance', URI);
              Stop := True;
            end
            else if JobCancelRequested(Cancel) then
            begin
              Err := TVfsError.Make(vecCancelled, 'Cancelled', URI);
              Stop := True;
            end;
          end;
        end;
        if Err.Code = vecOk then
          Items := All.ToArray
        else
          SetLength(Items, 0);
      finally
        All.Free;
        State.Free;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Items, Err);
        end);
    end);
end;

procedure TCdeclVfsBackendV2.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
var
  URI: string;
  Mode: TVfsDeleteMode;
  Cancel: IJobCancelToken;
  OnProgress: TVfsProgressCallback;
  OnDone: TVfsBoolCallback;
  Callbacks: TVfsCallbacksCdeclV2;
  UserData: Pointer;
begin
  URI := AURI;
  Mode := AMode;
  Cancel := ACancel;
  OnProgress := AOnProgress;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  RunWorker(
    procedure
    var
      State: TOpState;
      Err: TVfsError;
    begin
      State := TOpState.Create(Cancel, OnProgress);
      try
        if not Assigned(Callbacks.Delete) then
          Err := TVfsError.Make(vecNotSupported, 'Plugin has no Delete callback', URI)
        else
          Err := V2ErrorFromCode(Callbacks.Delete(PAnsiChar(UTF8String(URI)), Ord(Mode),
            UserData, State.CtxPtr), URI, State.ErrorText);
      finally
        State.Free;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Err.Code = vecOk, Err);
        end);
    end);
end;

procedure TCdeclVfsBackendV2.CreateDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
var
  URI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsBoolCallback;
  Callbacks: TVfsCallbacksCdeclV2;
  UserData: Pointer;
begin
  URI := AURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  RunWorker(
    procedure
    var
      State: TOpState;
      Err: TVfsError;
    begin
      State := TOpState.Create(Cancel, nil);
      try
        if not Assigned(Callbacks.CreateDirectory) then
          Err := TVfsError.Make(vecNotSupported, 'Plugin has no CreateDirectory callback', URI)
        else
          Err := V2ErrorFromCode(Callbacks.CreateDirectory(PAnsiChar(UTF8String(URI)),
            UserData, State.CtxPtr), URI, State.ErrorText);
      finally
        State.Free;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Err.Code = vecOk, Err);
        end);
    end);
end;

procedure TCdeclVfsBackendV2.CopyAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
var
  FromURI, ToURI: string;
  Flags: Int64;
  Cancel: IJobCancelToken;
  OnProgress: TVfsProgressCallback;
  OnDone: TVfsBoolCallback;
  Callbacks: TVfsCallbacksCdeclV2;
  UserData: Pointer;
begin
  FromURI := AFromURI;
  ToURI := AToURI;
  Flags := Ord(AOverwrite) or (Ord(APreserveTimestamps) shl 1);
  Cancel := ACancel;
  OnProgress := AOnProgress;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  RunWorker(
    procedure
    var
      State: TOpState;
      Err: TVfsError;
      FromU, ToU: UTF8String;
    begin
      State := TOpState.Create(Cancel, OnProgress);
      try
        if not Assigned(Callbacks.CopyItem) then
          Err := TVfsError.Make(vecNotSupported, 'Plugin has no CopyItem callback', FromURI)
        else
        begin
          FromU := UTF8String(FromURI);
          ToU := UTF8String(ToURI);
          Err := V2ErrorFromCode(Callbacks.CopyItem(PAnsiChar(FromU), PAnsiChar(ToU), Flags,
            UserData, State.CtxPtr), FromURI, State.ErrorText);
        end;
      finally
        State.Free;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Err.Code = vecOk, Err);
        end);
    end);
end;

procedure TCdeclVfsBackendV2.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
var
  FromURI, ToURI: string;
  Flags: Int64;
  Cancel: IJobCancelToken;
  OnProgress: TVfsProgressCallback;
  OnDone: TVfsBoolCallback;
  Callbacks: TVfsCallbacksCdeclV2;
  UserData: Pointer;
begin
  FromURI := AFromURI;
  ToURI := AToURI;
  Flags := Ord(AOverwrite) or (Ord(APreserveTimestamps) shl 1);
  Cancel := ACancel;
  OnProgress := AOnProgress;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  RunWorker(
    procedure
    var
      State: TOpState;
      Err: TVfsError;
      FromU, ToU: UTF8String;
    begin
      State := TOpState.Create(Cancel, OnProgress);
      try
        if not Assigned(Callbacks.MoveItem) then
          Err := TVfsError.Make(vecNotSupported, 'Plugin has no MoveItem callback', FromURI)
        else
        begin
          FromU := UTF8String(FromURI);
          ToU := UTF8String(ToURI);
          Err := V2ErrorFromCode(Callbacks.MoveItem(PAnsiChar(FromU), PAnsiChar(ToU), Flags,
            UserData, State.CtxPtr), FromURI, State.ErrorText);
        end;
      finally
        State.Free;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Err.Code = vecOk, Err);
        end);
    end);
end;

procedure TCdeclVfsBackendV2.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
var
  URI: string;
  MaxBytes: Int64;
  Cancel: IJobCancelToken;
  OnDone: TVfsTextCallback;
  Callbacks: TVfsCallbacksCdeclV2;
  UserData: Pointer;
begin
  URI := AURI;
  MaxBytes := AMaxBytes;
  Cancel := ACancel;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  RunWorker(
    procedure
    var
      State: TOpState;
      Buf: TBytes;
      Negotiated, Code: Int64;
      Text: string;
      Err: TVfsError;
      UriU: UTF8String;
      Attempt: Integer;
    begin
      State := TOpState.Create(Cancel, nil);
      try
        Text := '';
        Err := TVfsError.Ok;
        Err.URI := URI;
        if not Assigned(Callbacks.ReadText) then
          Err := TVfsError.Make(vecNotSupported, 'Plugin has no ReadText callback', URI)
        else
        begin
          UriU := UTF8String(URI);
          SetLength(Buf, cCdeclV2FirstBufferSize);
          Negotiated := 0;
          for Attempt := 0 to 1 do
          begin
            Negotiated := 0;
            Code := Callbacks.ReadText(PAnsiChar(UriU), MaxBytes, UserData, State.CtxPtr,
              PAnsiChar(Buf), Length(Buf), Negotiated);
            if (Code = Ord(verNeedsBiggerBuffer)) and (Attempt = 0) and
               (Negotiated > Length(Buf)) and (Negotiated <= cCdeclV2MaxBufferSize) then
            begin
              SetLength(Buf, Negotiated);
              Continue;
            end;
            Break;
          end;
          if Code = 0 then
            Text := TEncoding.UTF8.GetString(Buf, 0, EnsureRange(Negotiated, 0, Length(Buf)))
          else
            Err := V2ErrorFromCode(Code, URI, State.ErrorText);
        end;
      finally
        State.Free;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Text, tfeUtf8, Err);
        end);
    end);
end;

procedure TCdeclVfsBackendV2.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
var
  URI: string;
  MaxBytes: Int64;
  Cancel: IJobCancelToken;
  OnDone: TVfsBytesCallback;
  Callbacks: TVfsCallbacksCdeclV2;
  UserData: Pointer;
begin
  URI := AURI;
  MaxBytes := AMaxBytes;
  Cancel := ACancel;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  RunWorker(
    procedure
    var
      State: TOpState;
      Buf, Data: TBytes;
      Negotiated, Code: Int64;
      Err: TVfsError;
      UriU: UTF8String;
      Attempt: Integer;
    begin
      State := TOpState.Create(Cancel, nil);
      try
        SetLength(Data, 0);
        Err := TVfsError.Ok;
        Err.URI := URI;
        if not Assigned(Callbacks.ReadBytes) then
          Err := TVfsError.Make(vecNotSupported, 'Plugin has no ReadBytes callback', URI)
        else
        begin
          UriU := UTF8String(URI);
          SetLength(Buf, cCdeclV2FirstBufferSize);
          Negotiated := 0;
          for Attempt := 0 to 1 do
          begin
            Negotiated := 0;
            Code := Callbacks.ReadBytes(PAnsiChar(UriU), MaxBytes, UserData, State.CtxPtr,
              PByte(Buf), Length(Buf), Negotiated);
            if (Code = Ord(verNeedsBiggerBuffer)) and (Attempt = 0) and
               (Negotiated > Length(Buf)) and (Negotiated <= cCdeclV2MaxBufferSize) then
            begin
              SetLength(Buf, Negotiated);
              Continue;
            end;
            Break;
          end;
          if Code = 0 then
          begin
            if (Negotiated < 0) or (Negotiated > Length(Buf)) then
              Err := TVfsError.Make(vecIOError, 'Result exceeded buffer', URI)
            else
              Data := Copy(Buf, 0, Negotiated);
          end
          else
            Err := V2ErrorFromCode(Code, URI, State.ErrorText);
        end;
      finally
        State.Free;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Data, Err);
        end);
    end);
end;

procedure TCdeclVfsBackendV2.WriteTextAsync(const AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
var
  URI, Text: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsBoolCallback;
  Callbacks: TVfsCallbacksCdeclV2;
  UserData: Pointer;
begin
  URI := AURI;
  Text := AText;
  Cancel := ACancel;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  RunWorker(
    procedure
    var
      State: TOpState;
      Err: TVfsError;
      TextU: UTF8String;
    begin
      State := TOpState.Create(Cancel, nil);
      try
        if not Assigned(Callbacks.WriteText) then
          Err := TVfsError.Make(vecNotSupported, 'Plugin has no WriteText callback', URI)
        else
        begin
          TextU := UTF8String(Text);
          Err := V2ErrorFromCode(Callbacks.WriteText(PAnsiChar(UTF8String(URI)),
            PAnsiChar(TextU), UserData, State.CtxPtr), URI, State.ErrorText);
        end;
      finally
        State.Free;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Err.Code = vecOk, Err);
        end);
    end);
end;

procedure TCdeclVfsBackendV2.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
var
  URI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsExistsCallback;
  Callbacks: TVfsCallbacksCdeclV2;
  UserData: Pointer;
begin
  URI := AURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  RunWorker(
    procedure
    var
      State: TOpState;
      Code, IsDir: Int64;
      Err: TVfsError;
      Exists: Boolean;
    begin
      State := TOpState.Create(Cancel, nil);
      try
        IsDir := 0;
        Exists := False;
        if not Assigned(Callbacks.Exists) then
          Err := TVfsError.Make(vecNotSupported, 'Plugin has no Exists callback', URI)
        else
        begin
          Code := Callbacks.Exists(PAnsiChar(UTF8String(URI)), UserData, State.CtxPtr, IsDir);
          Exists := Code = 0;
          if Code = Ord(verNotFound) then
            Err := TVfsError.Ok // "not found" is a normal ExistsAsync=False result
          else
            Err := V2ErrorFromCode(Code, URI, State.ErrorText);
        end;
      finally
        State.Free;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Exists, IsDir <> 0, Err);
        end);
    end);
end;

procedure TCdeclVfsBackendV2.GetFreeSpaceAsync(const ARootURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsFreeSpaceCallback);
var
  URI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsFreeSpaceCallback;
  Callbacks: TVfsCallbacksCdeclV2;
  UserData: Pointer;
begin
  URI := ARootURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  Callbacks := FCallbacks;
  UserData := FUserData;
  RunWorker(
    procedure
    var
      State: TOpState;
      LFree, LTotal: Int64;
      Err: TVfsError;
    begin
      State := TOpState.Create(Cancel, nil);
      try
        LFree := -1;
        LTotal := -1;
        if not Assigned(Callbacks.GetFreeSpace) then
          Err := TVfsError.Make(vecNotSupported, 'Plugin has no GetFreeSpace callback', URI)
        else
          Err := V2ErrorFromCode(Callbacks.GetFreeSpace(PAnsiChar(UTF8String(URI)), UserData,
            State.CtxPtr, LFree, LTotal), URI, State.ErrorText);
      finally
        State.Free;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(LFree, LTotal, Err);
        end);
    end);
end;

end.
