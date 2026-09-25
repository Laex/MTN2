unit uShellIcons;

{ Windows shell icons by file kind / extension for the panel icon column.
  Cached as FMX bitmaps; cells store IconId (see TCharCell.IconId).

  Paint (ShellIconIdForRow) peeks the cache and enqueues a miss. SHGetFileInfo
  runs on a dedicated worker so the file list can draw immediately; the
  fallback glyph stays until the bitmap arrives, then the panel invalidates.

  CROSS-PLATFORM (Этап 23): backed by Windows Shell (SHGetFileInfo-class
  APIs); a POSIX port needs a different icon source entirely (freedesktop
  icon theme lookup on Linux, NSWorkspace on macOS) -- not a portable
  substitute for this unit's internals, a parallel implementation behind
  the same IconId-cache contract. }

interface

uses
  FMX.Graphics,
  uDualPanelTypes;

const
  /// <summary>How many grid cells a shell icon occupies horizontally.</summary>
  cShellIconCells = 2;

type
  /// <summary>Fired on the main thread after one or more icons land in the cache.</summary>
  TShellIconsReadyProc = reference to procedure;

/// <summary>Peek the cache and enqueue a miss (0 = none / still loading).</summary>
function ShellIconIdForRow(const ARow: TPanelRow): Integer;
/// <summary>Resolve on the caller thread. For smoke tests without a message loop.</summary>
function ShellIconIdForRowWait(const ARow: TPanelRow): Integer;
/// <summary>Cached bitmap for id; nil if missing.</summary>
function ShellIconBitmap(AIconId: Integer): FMX.Graphics.TBitmap;
/// <summary>Called after background extracts update the cache (typically Invalidate).</summary>
procedure ShellIconsSetOnReady(const AProc: TShellIconsReadyProc);

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Types,
  System.UITypes, System.IOUtils, System.SyncObjs,
  FMX.Types, FMX.Surfaces,
  uShellAssoc, uVfsTypes
{$IFDEF MSWINDOWS}
  , Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, Winapi.ActiveX
{$ENDIF}
  ;

type
  TFmxBitmap = class(FMX.Graphics.TBitmap);

{$IFDEF MSWINDOWS}
type
  TShellIconJobKind = (sijParent, sijAttr, sijFile);

  TShellIconJob = record
    Kind: TShellIconJobKind;
    Key: string;
    Probe: string;
    Attrs: DWORD;
    FallbackKey: string;
    FallbackProbe: string;
  end;

  TShellIconWorker = class;

  TShellIconCache = class
  private
    FKeyToId: TDictionary<string, Integer>;
    FBitmaps: TObjectList<TFmxBitmap>;
    FPending: TDictionary<string, Boolean>;
    FQueue: TQueue<TShellIconJob>;
    FLock: TCriticalSection;
    FWake: TEvent;
    FWorker: TShellIconWorker;
    FOnReady: TShellIconsReadyProc;
    FNotifyPosted: Boolean;
    FWorkerStartPosted: Boolean;
    FStopping: Boolean;
    function HIconToBitmap(AIcon: HICON; ASize: Integer): TFmxBitmap;
    function ExtractIconByAttr(const AProbe: string; AAttrs: DWORD): HICON;
    function ExtractIconFromFile(const APath: string): HICON;
    function AddBitmap(const AKey: string; ABmp: TFmxBitmap): Integer;
    function StoreIcon(const AKey: string; AIcon: HICON): Integer;
    function LoadKey(const AKey, AProbe: string; AAttrs: DWORD): Integer;
    function LoadFromFile(const AKey, APath: string): Integer;
    function LoadParentUpIcon: Integer;
    function IsEmbeddedIconExt(const AExt: string): Boolean;
    function RowLocalPath(const ARow: TPanelRow): string;
    function DescribeRow(const ARow: TPanelRow; out AJob: TShellIconJob): Boolean;
    procedure Enqueue(const AJob: TShellIconJob);
    procedure EnqueueAttr(const AKey, AProbe: string; AAttrs: DWORD);
    procedure EnsureWorkerPosted;
    procedure PostDeliver(const AKey: string; AIcon: HICON;
      const AFallbackKey, AFallbackProbe: string);
    procedure ApplyDelivered(const AKey: string; AIcon: HICON;
      const AFallbackKey, AFallbackProbe: string);
    procedure RequestNotify;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Shutdown;
    procedure SetOnReady(const AProc: TShellIconsReadyProc);
    function Resolve(const ARow: TPanelRow): Integer;
    function ResolveSync(const ARow: TPanelRow): Integer;
    function BitmapById(AId: Integer): TFmxBitmap;
  end;

  TShellIconWorker = class(TThread)
  private
    FCache: TShellIconCache;
  protected
    procedure Execute; override;
  public
    constructor Create(ACache: TShellIconCache);
  end;

var
  GCache: TShellIconCache;
  GOnReady: TShellIconsReadyProc;

function Cache: TShellIconCache;
begin
  if GCache = nil then
  begin
    GCache := TShellIconCache.Create;
    GCache.SetOnReady(GOnReady);
  end;
  Result := GCache;
end;

constructor TShellIconWorker.Create(ACache: TShellIconCache);
begin
  FCache := ACache;
  inherited Create(False);
  FreeOnTerminate := False;
end;

procedure TShellIconWorker.Execute;
var
  Job: TShellIconJob;
  Icon: HICON;
  HaveJob: Boolean;
  Msg: TMsg;
  WakeHandle: THandle;
  WaitResult: DWORD;
begin
  CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  // Apartment-threaded COM shell extensions (icon overlay / cloud-sync
  // providers such as OneDrive, some AV shell integrations) are marshaled
  // to this thread via a hidden window and window messages. Without an
  // active message queue being pumped, SHGetFileInfo/ExtractIconEx calls
  // that touch one of those extensions can block forever -- this
  // PeekMessage forces the queue to exist, and the loop below keeps it
  // drained instead of only ever waiting on FWake.
  PeekMessage(Msg, 0, WM_USER, WM_USER, PM_NOREMOVE);
  try
    while not Terminated do
    begin
      WakeHandle := FCache.FWake.Handle;
      WaitResult := MsgWaitForMultipleObjects(1, WakeHandle, False, INFINITE,
        QS_ALLINPUT);
      if Terminated then
        Break;
      if WaitResult = WAIT_OBJECT_0 + 1 then
      begin
        while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
          DispatchMessage(Msg);
        Continue;
      end;
      repeat
        HaveJob := False;
        FCache.FLock.Enter;
        try
          if FCache.FQueue.Count > 0 then
          begin
            Job := FCache.FQueue.Dequeue;
            HaveJob := True;
          end;
        finally
          FCache.FLock.Leave;
        end;
        if not HaveJob then
          Break;
        if Terminated then
          Break;
        try
          case Job.Kind of
            sijAttr:
              Icon := FCache.ExtractIconByAttr(Job.Probe, Job.Attrs);
            sijFile:
              Icon := FCache.ExtractIconFromFile(Job.Probe);
          else
            Icon := 0;
          end;
        except
          Icon := 0;
        end;
        FCache.PostDeliver(Job.Key, Icon, Job.FallbackKey, Job.FallbackProbe);
        // Drain messages that queued up while extraction was in flight.
        while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
          DispatchMessage(Msg);
      until False;
    end;
  finally
    CoUninitialize;
  end;
end;

constructor TShellIconCache.Create;
begin
  inherited Create;
  FKeyToId := TDictionary<string, Integer>.Create;
  // Index 0 unused so IconId 0 means "no icon".
  FBitmaps := TObjectList<TFmxBitmap>.Create(True);
  FBitmaps.Add(nil);
  FPending := TDictionary<string, Boolean>.Create;
  FQueue := TQueue<TShellIconJob>.Create;
  FLock := TCriticalSection.Create;
  FWake := TEvent.Create(nil, False, False, '');
  // Do not start the worker or call SHGetFileInfo here: the cache is often
  // created during TDualPanelWindow.Create, before the message loop. Shell
  // icon extractors SendMessage back to the UI thread and would deadlock
  // so the main window never appears.
end;

procedure TShellIconCache.Shutdown;
begin
  FStopping := True;
  if FWorker <> nil then
  begin
    FWorker.Terminate;
    if FWake <> nil then
      FWake.SetEvent;
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  if FLock <> nil then
  begin
    FLock.Enter;
    try
      if FQueue <> nil then
        FQueue.Clear;
    finally
      FLock.Leave;
    end;
  end;
end;

destructor TShellIconCache.Destroy;
begin
  Shutdown;
  FreeAndNil(FWake);
  FreeAndNil(FLock);
  FreeAndNil(FQueue);
  FreeAndNil(FPending);
  FBitmaps.Free;
  FKeyToId.Free;
  inherited Destroy;
end;

procedure TShellIconCache.SetOnReady(const AProc: TShellIconsReadyProc);
begin
  FOnReady := AProc;
end;

function TShellIconCache.HIconToBitmap(AIcon: HICON; ASize: Integer): TFmxBitmap;
var
  DC, MemDC: HDC;
  Dib, OldBmp: HBITMAP;
  BI: TBitmapInfo;
  Bits: Pointer;
  Data: TBitmapData;
  P: PByte;
  I, N: Integer;
  B, G, R, A: Byte;
  OutC: TAlphaColorRec;
  Dest: PAlphaColor;
begin
  Result := nil;
  if (AIcon = 0) or (ASize < 8) then
    Exit;

  FillChar(BI, SizeOf(BI), 0);
  BI.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
  BI.bmiHeader.biWidth := ASize;
  BI.bmiHeader.biHeight := -ASize; // top-down
  BI.bmiHeader.biPlanes := 1;
  BI.bmiHeader.biBitCount := 32;
  BI.bmiHeader.biCompression := BI_RGB;

  DC := GetDC(0);
  if DC = 0 then
    Exit;
  MemDC := CreateCompatibleDC(DC);
  Bits := nil;
  Dib := CreateDIBSection(MemDC, BI, DIB_RGB_COLORS, Bits, 0, 0);
  if (Dib = 0) or (Bits = nil) then
  begin
    if MemDC <> 0 then
      DeleteDC(MemDC);
    ReleaseDC(0, DC);
    Exit;
  end;
  OldBmp := SelectObject(MemDC, Dib);
  try
    FillChar(Bits^, ASize * ASize * 4, 0);
    DrawIconEx(MemDC, 0, 0, AIcon, ASize, ASize, 0, 0, DI_NORMAL);

    Result := TFmxBitmap.Create;
    Result.SetSize(ASize, ASize);
    if not Result.Map(TMapAccess.Write, Data) then
    begin
      FreeAndNil(Result);
      Exit;
    end;
    try
      // DIB bytes are B,G,R,A; FMX wants premultiplied TAlphaColor.
      P := Bits;
      Dest := Data.Data;
      N := ASize * ASize;
      for I := 0 to N - 1 do
      begin
        B := P^; Inc(P);
        G := P^; Inc(P);
        R := P^; Inc(P);
        A := P^; Inc(P);
        if (A = 0) and ((R or G or B) <> 0) then
          A := 255;
        OutC.A := A;
        if A = 0 then
        begin
          OutC.R := 0;
          OutC.G := 0;
          OutC.B := 0;
        end
        else if A = 255 then
        begin
          OutC.R := R;
          OutC.G := G;
          OutC.B := B;
        end
        else
        begin
          OutC.R := Byte((Integer(R) * A) div 255);
          OutC.G := Byte((Integer(G) * A) div 255);
          OutC.B := Byte((Integer(B) * A) div 255);
        end;
        Dest^ := OutC.Color;
        Inc(Dest);
      end;
    finally
      Result.Unmap(Data);
    end;
  finally
    SelectObject(MemDC, OldBmp);
    DeleteObject(Dib);
    DeleteDC(MemDC);
    ReleaseDC(0, DC);
  end;
end;

function TShellIconCache.ExtractIconByAttr(const AProbe: string; AAttrs: DWORD): HICON;
var
  Info: TSHFileInfo;
begin
  Result := 0;
  FillChar(Info, SizeOf(Info), 0);
  if SHGetFileInfo(PChar(AProbe), AAttrs, Info, SizeOf(Info),
    SHGFI_ICON or SHGFI_SMALLICON or SHGFI_USEFILEATTRIBUTES) <> 0 then
    Result := Info.hIcon;
end;

function TShellIconCache.ExtractIconFromFile(const APath: string): HICON;
var
  Info: TSHFileInfo;
  Large, Small: HICON;
  N: UINT;
begin
  Result := 0;
  if (APath = '') or not TFile.Exists(APath) then
    Exit;

  // Prefer shell: picks .exe/.dll embedded icon, .lnk overlay target, etc.
  FillChar(Info, SizeOf(Info), 0);
  if SHGetFileInfo(PChar(APath), 0, Info, SizeOf(Info),
    SHGFI_ICON or SHGFI_SMALLICON) <> 0 then
    Exit(Info.hIcon);

  // Fallback: first icon resource in the binary.
  Large := 0;
  Small := 0;
  N := ExtractIconEx(PChar(APath), 0, Large, Small, 1);
  if N = 0 then
    Exit;
  if Small <> 0 then
  begin
    Result := Small;
    if Large <> 0 then
      DestroyIcon(Large);
  end
  else
    Result := Large;
end;

function TShellIconCache.AddBitmap(const AKey: string; ABmp: TFmxBitmap): Integer;
begin
  if ABmp = nil then
    Exit(0);
  Result := FBitmaps.Add(ABmp);
  FKeyToId.AddOrSetValue(AKey, Result);
end;

function TShellIconCache.StoreIcon(const AKey: string; AIcon: HICON): Integer;
var
  Bmp: TFmxBitmap;
begin
  if FKeyToId.TryGetValue(AKey, Result) then
  begin
    if AIcon <> 0 then
      DestroyIcon(AIcon);
    Exit;
  end;
  if AIcon = 0 then
  begin
    FKeyToId.AddOrSetValue(AKey, 0);
    Exit(0);
  end;
  try
    Bmp := HIconToBitmap(AIcon, 16);
    Result := AddBitmap(AKey, Bmp);
    if Result = 0 then
      FKeyToId.AddOrSetValue(AKey, 0);
  finally
    DestroyIcon(AIcon);
  end;
end;

function TShellIconCache.LoadKey(const AKey, AProbe: string; AAttrs: DWORD): Integer;
begin
  if FKeyToId.TryGetValue(AKey, Result) then
    Exit;
  Result := StoreIcon(AKey, ExtractIconByAttr(AProbe, AAttrs));
end;

function TShellIconCache.LoadFromFile(const AKey, APath: string): Integer;
begin
  if FKeyToId.TryGetValue(AKey, Result) then
    Exit;
  Result := StoreIcon(AKey, ExtractIconFromFile(APath));
end;

function TShellIconCache.LoadParentUpIcon: Integer;
const
  cKey = 'special:parent';
  cResName = 'ICON_PARENT_UP';
var
  Stream: TStream;
  Bmp: TFmxBitmap;
  Surf: TBitmapSurface;
  Paths: TArray<string>;
  P: string;

  function FinishBitmap(ABmp: TFmxBitmap): Integer;
  begin
    Result := 0;
    if ABmp = nil then
      Exit;
    if (ABmp.Width < 1) or (ABmp.Height < 1) then
    begin
      ABmp.Free;
      Exit;
    end;
    Result := AddBitmap(cKey, ABmp);
  end;

  function TryLoadFromStream(AStream: TStream): Integer;
  begin
    Result := 0;
    if AStream = nil then
      Exit;
    AStream.Position := 0;
    Surf := TBitmapSurface.Create;
    try
      if TBitmapCodecManager.LoadFromStream(AStream, Surf) and
         (Surf.Width > 0) and (Surf.Height > 0) then
      begin
        Bmp := TFmxBitmap.Create;
        Bmp.Assign(Surf);
        Result := FinishBitmap(Bmp);
        if Result > 0 then
          Exit;
      end;
    finally
      FreeAndNil(Surf);
    end;
    AStream.Position := 0;
    Bmp := TFmxBitmap.Create;
    try
      Bmp.LoadFromStream(AStream);
      Result := FinishBitmap(Bmp);
      Bmp := nil; // owned by cache or freed in FinishBitmap
    except
      FreeAndNil(Bmp);
      Result := 0;
    end;
  end;

begin
  if FKeyToId.TryGetValue(cKey, Result) then
    Exit;

  Result := 0;
  if FindResource(HInstance, PChar(cResName), RT_RCDATA) <> 0 then
  begin
    try
      Stream := TResourceStream.Create(HInstance, cResName, RT_RCDATA);
      try
        Result := TryLoadFromStream(Stream);
      finally
        Stream.Free;
      end;
    except
      Result := 0;
    end;
  end;

  if Result = 0 then
  begin
    Paths := [
      TPath.Combine(ExtractFilePath(ParamStr(0)), 'Assets\parent_up.png'),
      TPath.Combine(ExtractFilePath(ParamStr(0)), 'parent_up.png'),
      TPath.Combine(ExtractFilePath(GetModuleName(HInstance)),
        'Assets\parent_up.png'),
      ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)),
        '..\src\Assets\parent_up.png')),
      ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)),
        'src\Assets\parent_up.png'))
    ];
    for P in Paths do
    begin
      if (P = '') or not TFile.Exists(P) then
        Continue;
      Stream := TFileStream.Create(P, fmOpenRead or fmShareDenyWrite);
      try
        Result := TryLoadFromStream(Stream);
      finally
        Stream.Free;
      end;
      if Result > 0 then
        Break;
    end;
  end;

  // Last resort: generic folder (should be rare).
  if Result = 0 then
    Result := LoadKey(cKey, 'folder', FILE_ATTRIBUTE_DIRECTORY);
end;

function TShellIconCache.IsEmbeddedIconExt(const AExt: string): Boolean;
begin
  Result := SameText(AExt, '.exe') or SameText(AExt, '.dll') or
    SameText(AExt, '.scr') or SameText(AExt, '.cpl') or
    SameText(AExt, '.ocx') or SameText(AExt, '.ico') or
    SameText(AExt, '.lnk') or SameText(AExt, '.msi');
end;

function TShellIconCache.RowLocalPath(const ARow: TPanelRow): string;
var
  Uri: string;
begin
  Result := '';
  Uri := ARow.TargetURI;
  if Uri = '' then
    Uri := ARow.URI;
  if Uri = '' then
    Exit;
  Result := FileUriToPath(Uri);
  // Only real local/UNC files — skip zip/plugin URIs that are not on disk.
  if Result = '' then
    Exit;
  if not (TPath.IsPathRooted(Result) or Result.StartsWith('\\')) then
    Result := '';
end;

function TShellIconCache.DescribeRow(const ARow: TPanelRow;
  out AJob: TShellIconJob): Boolean;
var
  Ext, Path: string;
begin
  Result := True;
  AJob := Default(TShellIconJob);
  if ARow.IsParent or (ARow.Text = '..') then
  begin
    AJob.Kind := sijParent;
    AJob.Key := 'special:parent';
    Exit;
  end;
  if ARow.IsDirectory then
  begin
    AJob.Kind := sijAttr;
    if ARow.IsLink then
      AJob.Key := 'special:dirlink'
    else
      AJob.Key := 'special:dir';
    AJob.Probe := 'folder';
    AJob.Attrs := FILE_ATTRIBUTE_DIRECTORY;
    Exit;
  end;

  Ext := NormalizeFileExtension(ARow.Extension);
  if Ext = '' then
    Ext := NormalizeFileExtension(ARow.Text);

  if IsEmbeddedIconExt(Ext) then
  begin
    Path := RowLocalPath(ARow);
    if Path <> '' then
    begin
      AJob.Kind := sijFile;
      AJob.Key := 'path:' + LowerCase(Path);
      AJob.Probe := Path;
      if Ext <> '' then
      begin
        AJob.FallbackKey := 'ext:' + Ext;
        AJob.FallbackProbe := '*' + Ext;
      end
      else
      begin
        AJob.FallbackKey := 'special:file';
        AJob.FallbackProbe := 'file';
      end;
      Exit;
    end;
  end;

  if Ext = '' then
  begin
    AJob.Kind := sijAttr;
    AJob.Key := 'special:file';
    AJob.Probe := 'file';
    AJob.Attrs := FILE_ATTRIBUTE_NORMAL;
    Exit;
  end;

  AJob.Kind := sijAttr;
  AJob.Key := 'ext:' + Ext;
  AJob.Probe := '*' + Ext;
  AJob.Attrs := FILE_ATTRIBUTE_NORMAL;
end;

procedure TShellIconCache.Enqueue(const AJob: TShellIconJob);
begin
  if FStopping then
    Exit;
  if FKeyToId.ContainsKey(AJob.Key) then
    Exit;
  if FPending.ContainsKey(AJob.Key) then
    Exit;
  FPending.Add(AJob.Key, True);
  FLock.Enter;
  try
    FQueue.Enqueue(AJob);
  finally
    FLock.Leave;
  end;
  EnsureWorkerPosted;
end;

procedure TShellIconCache.EnsureWorkerPosted;
begin
  if FStopping then
    Exit;
  if FWorker <> nil then
  begin
    FWake.SetEvent;
    Exit;
  end;
  if FWorkerStartPosted then
    Exit;
  FWorkerStartPosted := True;
  TThread.ForceQueue(nil,
    procedure
    begin
      if (GCache = nil) or GCache.FStopping then
        Exit;
      if GCache.FWorker = nil then
        GCache.FWorker := TShellIconWorker.Create(GCache);
      GCache.EnqueueAttr('special:dir', 'folder', FILE_ATTRIBUTE_DIRECTORY);
      GCache.EnqueueAttr('special:dirlink', 'folder', FILE_ATTRIBUTE_DIRECTORY);
      GCache.EnqueueAttr('special:file', 'file', FILE_ATTRIBUTE_NORMAL);
      GCache.FWake.SetEvent;
    end);
end;

procedure TShellIconCache.EnqueueAttr(const AKey, AProbe: string; AAttrs: DWORD);
var
  Job: TShellIconJob;
begin
  Job := Default(TShellIconJob);
  Job.Kind := sijAttr;
  Job.Key := AKey;
  Job.Probe := AProbe;
  Job.Attrs := AAttrs;
  Enqueue(Job);
end;

procedure TShellIconCache.PostDeliver(const AKey: string; AIcon: HICON;
  const AFallbackKey, AFallbackProbe: string);
var
  Key, FbKey, FbProbe: string;
  Icon: HICON;
begin
  Key := AKey;
  Icon := AIcon;
  FbKey := AFallbackKey;
  FbProbe := AFallbackProbe;
  TThread.Queue(nil,
    procedure
    begin
      if GCache = nil then
      begin
        if Icon <> 0 then
          DestroyIcon(Icon);
        Exit;
      end;
      GCache.ApplyDelivered(Key, Icon, FbKey, FbProbe);
    end);
end;

procedure TShellIconCache.ApplyDelivered(const AKey: string; AIcon: HICON;
  const AFallbackKey, AFallbackProbe: string);
var
  Id: Integer;
begin
  if FStopping then
  begin
    if AIcon <> 0 then
      DestroyIcon(AIcon);
    Exit;
  end;
  Id := StoreIcon(AKey, AIcon);
  FPending.Remove(AKey);
  if (Id = 0) and (AFallbackKey <> '') then
    EnqueueAttr(AFallbackKey, AFallbackProbe, FILE_ATTRIBUTE_NORMAL);
  RequestNotify;
end;

procedure TShellIconCache.RequestNotify;
begin
  if FNotifyPosted then
    Exit;
  FNotifyPosted := True;
  TThread.ForceQueue(nil,
    procedure
    begin
      if GCache = nil then
        Exit;
      GCache.FNotifyPosted := False;
      if Assigned(GCache.FOnReady) then
        GCache.FOnReady();
    end);
end;

function TShellIconCache.Resolve(const ARow: TPanelRow): Integer;
var
  Job: TShellIconJob;
begin
  if not DescribeRow(ARow, Job) then
    Exit(0);
  if Job.Kind = sijParent then
  begin
    if FKeyToId.TryGetValue(Job.Key, Result) then
      Exit;
    Exit(LoadParentUpIcon);
  end;
  if FKeyToId.TryGetValue(Job.Key, Result) then
  begin
    if (Result > 0) or (Job.FallbackKey = '') then
      Exit;
    if FKeyToId.TryGetValue(Job.FallbackKey, Result) then
      Exit;
    EnqueueAttr(Job.FallbackKey, Job.FallbackProbe, FILE_ATTRIBUTE_NORMAL);
    Exit(0);
  end;
  Enqueue(Job);
  Result := 0;
end;

function TShellIconCache.ResolveSync(const ARow: TPanelRow): Integer;
var
  Job: TShellIconJob;
begin
  if not DescribeRow(ARow, Job) then
    Exit(0);
  if Job.Kind = sijParent then
    Exit(LoadParentUpIcon);
  if Job.Kind = sijFile then
  begin
    Result := LoadFromFile(Job.Key, Job.Probe);
    if Result > 0 then
      Exit;
    if Job.FallbackKey <> '' then
      Exit(LoadKey(Job.FallbackKey, Job.FallbackProbe, FILE_ATTRIBUTE_NORMAL));
    Exit;
  end;
  Result := LoadKey(Job.Key, Job.Probe, Job.Attrs);
end;

function TShellIconCache.BitmapById(AId: Integer): TFmxBitmap;
begin
  if (AId <= 0) or (AId >= FBitmaps.Count) then
    Exit(nil);
  Result := FBitmaps[AId];
end;
{$ENDIF}

function ShellIconIdForRow(const ARow: TPanelRow): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Cache.Resolve(ARow);
  {$ELSE}
  Result := 0;
  {$ENDIF}
end;

function ShellIconIdForRowWait(const ARow: TPanelRow): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Cache.ResolveSync(ARow);
  {$ELSE}
  Result := 0;
  {$ENDIF}
end;

function ShellIconBitmap(AIconId: Integer): FMX.Graphics.TBitmap;
begin
  {$IFDEF MSWINDOWS}
  Result := Cache.BitmapById(AIconId);
  {$ELSE}
  Result := nil;
  {$ENDIF}
end;

procedure ShellIconsSetOnReady(const AProc: TShellIconsReadyProc);
begin
  {$IFDEF MSWINDOWS}
  GOnReady := AProc;
  if GCache <> nil then
    GCache.SetOnReady(AProc);
  {$ENDIF}
end;

initialization
finalization
  {$IFDEF MSWINDOWS}
  if GCache <> nil then
    GCache.Shutdown;
  FreeAndNil(GCache);
  {$ENDIF}
end.
