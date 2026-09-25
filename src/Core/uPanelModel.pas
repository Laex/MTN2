unit uPanelModel;

{ In-process file panel model (PANEL_PLUGIN Pull). Host owns layout/cursor;
  model owns URI list state and async VFS list.
  Seams for stage 29: WindowId + OnInvalidate + GetRowJson (PANEL_PLUGIN ABI). }

interface

uses
  System.SysUtils, System.Classes,
  uDualPanelTypes, uVfsTypes;

const
  cPanelWindowIdNone  = 0;
  cPanelWindowIdLeft  = 1;
  cPanelWindowIdRight = 2;
  /// <summary>Open's watchdog: how long a navigation stays on "Reading..."
  /// before switching to a "still trying" status line -- see Open.</summary>
  cSlowNavigationHintMs = 8000;

type
  /// <summary>Plugin → Host: model changed (mtn_host_invalidate).</summary>
  TPanelInvalidateEvent = reference to procedure(AWindowId: Integer);

  IPanelModel = interface
    ['{C3E8A1F2-5B7D-4E9A-8C1F-2D4A6B8E0F12}']
    procedure Open(const AURI: string);
    procedure Close;
    function GetURI: string;
    function GetPluginId: string;
    function GetWindowId: Integer;
    procedure SetWindowId(AId: Integer);
    function ItemCount: Integer;
    function GetRow(AIndex: Integer): TPanelRow;
    /// <summary>PANEL_PLUGIN get_row_json — logical metadata only.</summary>
    function GetRowJson(AIndex: Integer): string;
    function IsLoading: Boolean;
    procedure Refresh;
    /// <summary>Update Size/SizeText for a row by URI (folder-size calc).</summary>
    function SetRowSize(const AURI: string; ASize: Int64;
      const ASizeText: string): Boolean;
    /// <summary>Sort key applied on list results and immediately to current rows.</summary>
    procedure SetSort(AColumn: TPanelSortColumn; ADescending: Boolean);
    procedure GetSort(out AColumn: TPanelSortColumn; out ADescending: Boolean);
    procedure SetOnInvalidate(AHandler: TPanelInvalidateEvent);
    /// <summary>Legacy alias: maps to OnInvalidate(WindowId).</summary>
    procedure SetOnChanged(AHandler: TNotifyEvent);
    /// <summary>Live filter (Ctrl+F): '' clears it. Narrows the rows exposed
    /// via ItemCount/GetRow to those matching the mask (SplitMasks/
    /// NameMatchesAnyMask semantics) — the '..' parent row always survives.</summary>
    procedure SetFilterMask(const AMask: string);
    function FilterActive: Boolean;
    function FilterMask: string;
    /// <summary>Ctrl+H toggle: when False, rows with IsHidden or IsSystem set
    /// are excluded from ItemCount/GetRow (the '..' parent row always survives).</summary>
    procedure SetShowHidden(AValue: Boolean);
    function ShowHidden: Boolean;
    function GetLastError: TVfsError;
    /// <summary>When listing the current URI, '..' goes here instead of the
    /// disk parent. Empty = normal parent. Only the tab that entered a
    /// workspace dir-link should set this; the other panel at the same path
    /// stays on disk.</summary>
    procedure SetWorkspaceReturnUri(const AURI: string);
    property URI: string read GetURI;
    property PluginId: string read GetPluginId;
    property WindowId: Integer read GetWindowId write SetWindowId;
  end;

function PanelRowToJson(const ARow: TPanelRow): string;

type
  TFilePanelModel = class(TInterfacedObject, IPanelModel)
  private
    FVfs: IVirtualFileSystem;
    FURI: string;
    FWindowId: Integer;
    FRawRows: TPanelRows;
    FRows: TPanelRows;
    FLoading: Boolean;
    FAlive: Boolean;
    FGen: Cardinal;
    FCancel: IJobCancelToken;
    FSortColumn: TPanelSortColumn;
    FSortDescending: Boolean;
    FFilterMask: string;
    FShowHidden: Boolean;
    FOnInvalidate: TPanelInvalidateEvent;
    FOnChanged: TNotifyEvent;
    FLastError: TVfsError;
    FWorkspaceReturnUri: string;
    procedure NotifyChanged;
    procedure CancelPending;
    procedure ApplyRows(const ARows: TPanelRows; AGen: Cardinal);
    /// <summary>Updates the displayed rows to a "still waiting" hint without
    /// finishing the request (FLoading stays True, FGen is untouched) -- the
    /// real ListDirectoryAsync call keeps running and, if it eventually
    /// answers, ApplyRows still replaces this with the real result. See
    /// Open's watchdog thread.</summary>
    procedure ApplySlowHint(const ARows: TPanelRows; AGen: Cardinal);
    procedure RebuildSortedRows;
  public
    constructor Create(const AVfs: IVirtualFileSystem; AWindowId: Integer = cPanelWindowIdNone);
    destructor Destroy; override;
    procedure Open(const AURI: string);
    procedure Close;
    function GetURI: string;
    function GetPluginId: string;
    function GetWindowId: Integer;
    procedure SetWindowId(AId: Integer);
    function ItemCount: Integer;
    function GetRow(AIndex: Integer): TPanelRow;
    function GetRowJson(AIndex: Integer): string;
    function IsLoading: Boolean;
    procedure Refresh;
    function SetRowSize(const AURI: string; ASize: Int64;
      const ASizeText: string): Boolean;
    procedure SetSort(AColumn: TPanelSortColumn; ADescending: Boolean);
    procedure GetSort(out AColumn: TPanelSortColumn; out ADescending: Boolean);
    procedure SetOnInvalidate(AHandler: TPanelInvalidateEvent);
    procedure SetOnChanged(AHandler: TNotifyEvent);
    procedure SetFilterMask(const AMask: string);
    function FilterActive: Boolean;
    function FilterMask: string;
    procedure SetShowHidden(AValue: Boolean);
    function ShowHidden: Boolean;
    function GetLastError: TVfsError;
    procedure SetWorkspaceReturnUri(const AURI: string);
  end;

implementation

uses
  System.JSON, uPanelColumns, uMessageBus, uFileFind, uPanelPluginRegistry;

function PanelRowToJson(const ARow: TPanelRow): string;
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  try
    if ARow.Id <> '' then
      O.AddPair('id', ARow.Id);
    O.AddPair('text', ARow.Text);
    O.AddPair('size', TJSONNumber.Create(ARow.Size));
    if ARow.SizeText <> '' then
      O.AddPair('size_text', ARow.SizeText);
    if ARow.DateText <> '' then
      O.AddPair('date_text', ARow.DateText);
    O.AddPair('is_directory', TJSONBool.Create(ARow.IsDirectory));
    O.AddPair('is_parent', TJSONBool.Create(ARow.IsParent));
    O.AddPair('is_hidden', TJSONBool.Create(ARow.IsHidden));
    O.AddPair('is_readonly', TJSONBool.Create(ARow.IsReadOnly));
    O.AddPair('is_system', TJSONBool.Create(ARow.IsSystem));
    O.AddPair('is_archive', TJSONBool.Create(ARow.IsArchive));
    O.AddPair('is_compressed', TJSONBool.Create(ARow.IsCompressed));
    O.AddPair('is_encrypted', TJSONBool.Create(ARow.IsEncrypted));
    O.AddPair('is_temporary', TJSONBool.Create(ARow.IsTemporary));
    O.AddPair('is_offline', TJSONBool.Create(ARow.IsOffline));
    O.AddPair('is_symlink', TJSONBool.Create(ARow.IsLink));
    if ARow.Extension <> '' then
      O.AddPair('extension', ARow.Extension);
    if ARow.AttrText <> '' then
      O.AddPair('attributes', ARow.AttrText);
    if ARow.CreatedText <> '' then
      O.AddPair('created', ARow.CreatedText);
    if ARow.AccessedText <> '' then
      O.AddPair('accessed', ARow.AccessedText);
    if ARow.DateText <> '' then
      O.AddPair('modified', ARow.DateText);
    if ARow.FileType <> '' then
      O.AddPair('file_type', ARow.FileType);
    if ARow.TargetURI <> '' then
      O.AddPair('target_uri', ARow.TargetURI);
    if ARow.URI <> '' then
      O.AddPair('uri', ARow.URI);
    Result := O.ToJSON;
  finally
    O.Free;
  end;
end;

constructor TFilePanelModel.Create(const AVfs: IVirtualFileSystem; AWindowId: Integer);
begin
  inherited Create;
  FVfs := AVfs;
  FWindowId := AWindowId;
  FAlive := True;
  FLoading := False;
  FURI := '';
  FSortColumn := pscNone;
  FSortDescending := False;
  FShowHidden := True;
  FLastError := TVfsError.Ok;
  SetLength(FRawRows, 0);
  SetLength(FRows, 0);
end;

destructor TFilePanelModel.Destroy;
begin
  FAlive := False;
  CancelPending;
  FOnInvalidate := nil;
  FOnChanged := nil;
  FVfs := nil;
  inherited Destroy;
end;

procedure TFilePanelModel.NotifyChanged;
begin
  if Assigned(FOnInvalidate) then
    FOnInvalidate(FWindowId);
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TFilePanelModel.SetOnInvalidate(AHandler: TPanelInvalidateEvent);
begin
  FOnInvalidate := AHandler;
end;

procedure TFilePanelModel.SetOnChanged(AHandler: TNotifyEvent);
begin
  FOnChanged := AHandler;
end;

procedure TFilePanelModel.CancelPending;
begin
  if Assigned(FCancel) then
    FCancel.Cancel;
  FCancel := nil;
end;

procedure TFilePanelModel.ApplyRows(const ARows: TPanelRows; AGen: Cardinal);
begin
  if not FAlive or (AGen <> FGen) then
    Exit;
  FRawRows := ARows;
  RebuildSortedRows;
  FLoading := False;
  NotifyChanged;
  MessageBus.Publish(cTopicPanelNavigated);
end;

procedure TFilePanelModel.ApplySlowHint(const ARows: TPanelRows; AGen: Cardinal);
begin
  // Still loading (not FLoading) -- a superseded/finished request must not
  // stomp over whatever ApplyRows already showed for a newer navigation.
  if not FAlive or (AGen <> FGen) or not FLoading then
    Exit;
  FRawRows := ARows;
  RebuildSortedRows;
  NotifyChanged;
end;

procedure TFilePanelModel.RebuildSortedRows;
var
  Masks: TArray<string>;
  Kept: TPanelRows;
  I, N: Integer;
  Name: string;
begin
  FRows := Copy(FRawRows);
  if not FShowHidden then
  begin
    SetLength(Kept, Length(FRows));
    N := 0;
    for I := 0 to High(FRows) do
      if FRows[I].IsParent or not (FRows[I].IsHidden or FRows[I].IsSystem) then
      begin
        Kept[N] := FRows[I];
        Inc(N);
      end;
    SetLength(Kept, N);
    FRows := Kept;
  end;
  if FSortColumn <> pscNone then
    SortPanelRows(FRows, FSortColumn, FSortDescending);
  if FFilterMask <> '' then
  begin
    Masks := SplitMasks(FFilterMask);
    SetLength(Kept, Length(FRows));
    N := 0;
    for I := 0 to High(FRows) do
    begin
      if FRows[I].IsParent then
      begin
        Kept[N] := FRows[I];
        Inc(N);
        Continue;
      end;
      Name := FRows[I].Text;
      if (Length(Name) > 0) and (Name[Length(Name)] = '/') then
        Name := Copy(Name, 1, Length(Name) - 1);
      if NameMatchesAnyMask(Name, Masks) then
      begin
        Kept[N] := FRows[I];
        Inc(N);
      end;
    end;
    SetLength(Kept, N);
    FRows := Kept;
  end;
end;

procedure TFilePanelModel.SetShowHidden(AValue: Boolean);
begin
  if FShowHidden = AValue then
    Exit;
  FShowHidden := AValue;
  RebuildSortedRows;
  NotifyChanged;
end;

function TFilePanelModel.ShowHidden: Boolean;
begin
  Result := FShowHidden;
end;

function TFilePanelModel.GetLastError: TVfsError;
begin
  Result := FLastError;
end;

procedure TFilePanelModel.SetWorkspaceReturnUri(const AURI: string);
begin
  FWorkspaceReturnUri := AURI;
end;

procedure TFilePanelModel.SetFilterMask(const AMask: string);
begin
  if FFilterMask = AMask then
    Exit;
  FFilterMask := AMask;
  RebuildSortedRows;
  NotifyChanged;
end;

function TFilePanelModel.FilterActive: Boolean;
begin
  Result := FFilterMask <> '';
end;

function TFilePanelModel.FilterMask: string;
begin
  Result := FFilterMask;
end;

procedure TFilePanelModel.SetSort(AColumn: TPanelSortColumn; ADescending: Boolean);
begin
  if (FSortColumn = AColumn) and (FSortDescending = ADescending) then
    Exit;
  FSortColumn := AColumn;
  FSortDescending := ADescending;
  if Length(FRawRows) > 0 then
  begin
    RebuildSortedRows;
    NotifyChanged;
  end;
end;

procedure TFilePanelModel.GetSort(out AColumn: TPanelSortColumn;
  out ADescending: Boolean);
begin
  AColumn := FSortColumn;
  ADescending := FSortDescending;
end;

function TFilePanelModel.GetURI: string;
begin
  Result := FURI;
end;

function TFilePanelModel.GetPluginId: string;
begin
  Result := PanelPluginRegistry.ResolvePlugin(FURI);
end;

function TFilePanelModel.GetWindowId: Integer;
begin
  Result := FWindowId;
end;

procedure TFilePanelModel.SetWindowId(AId: Integer);
begin
  FWindowId := AId;
end;

function TFilePanelModel.ItemCount: Integer;
begin
  Result := Length(FRows);
end;

function TFilePanelModel.GetRow(AIndex: Integer): TPanelRow;
begin
  if (AIndex < 0) or (AIndex > High(FRows)) then
  begin
    Result := MakePanelRow('', False);
    Exit;
  end;
  Result := FRows[AIndex];
end;

function TFilePanelModel.GetRowJson(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(FRows)) then
    Exit('');
  Result := PanelRowToJson(FRows[AIndex]);
end;

function TFilePanelModel.IsLoading: Boolean;
begin
  Result := FLoading;
end;

procedure TFilePanelModel.Close;
begin
  CancelPending;
  Inc(FGen);
  FURI := '';
  FLastError := TVfsError.Ok;
  SetLength(FRawRows, 0);
  SetLength(FRows, 0);
  FLoading := False;
  NotifyChanged;
end;

procedure TFilePanelModel.Open(const AURI: string);
var
  URI, ReturnUri: string;
  Gen: Cardinal;
  Token: IJobCancelToken;
  KeepVisual: Boolean;
begin
  URI := AURI;
  if URI = '' then
    Exit;
  if not Assigned(FVfs) then
    Exit;

  CancelPending;
  Inc(FGen);
  Gen := FGen;
  ReturnUri := FWorkspaceReturnUri;
  // Soft refresh / dir-watch: keep the previous list on screen until the new
  // list arrives — LoadingRows flash is the main panel blink on redraw.
  KeepVisual := SameVfsUri(FURI, URI) and (Length(FRows) > 0);
  FURI := URI;
  FLastError := TVfsError.Ok;
  FLoading := True;
  if not KeepVisual then
  begin
    FRows := LoadingRows;
    NotifyChanged;
  end;

  Token := TJobCancelToken.Create;
  FCancel := Token;

  FVfs.ListDirectoryAsync(URI, Token,
    procedure(const AItems: TArray<TVfsEntry>; const AError: TVfsError)
    var
      Rows: TPanelRows;
      Msg: string;
    begin
      if not FAlive or (Gen <> FGen) then
        Exit;
      if AError.Code = vecCancelled then
      begin
        FLastError := AError;
        FLoading := False;
        NotifyChanged;
        Exit;
      end;
      FLastError := AError;
      if AError.Code = vecOk then
        Rows := RowsFromVfsItems(URI, AItems, ReturnUri)
      else
      begin
        case AError.Code of
          vecAccessDenied: Msg := 'Access denied';
          vecNotFound: Msg := 'Path not found';
          vecInvalidURI: Msg := 'Invalid path';
          vecNotSupported: Msg := 'Not a directory';
          vecIOError: Msg := AError.Message;
        else
          Msg := AError.Message;
        end;
        if Msg = '' then
          Msg := 'Error';
        Rows := ErrorRows(URI, Msg, ReturnUri);
      end;
      ApplyRows(Rows, Gen);
    end);

  // ListDirectoryAsync already runs off the UI thread, but a truly
  // unresponsive location (an unreachable network drive/share) can leave
  // that background thread blocked for a very long time -- Win32's
  // FindFirstFile-family calls cannot be cancelled mid-flight, so the token
  // above only stops a *not-yet-started* scan, and a query already in
  // progress is simply abandoned (harmless: ApplyRows' Gen check ignores it
  // if it ever does return after the user has moved on). Meanwhile the panel
  // would otherwise sit on a static "Reading..." forever with no sign
  // anything is wrong. This one-shot watchdog swaps in a "still trying"
  // status line instead -- FLoading/FGen are untouched, so if the real
  // listing does eventually answer (for this same navigation), ApplyRows
  // still replaces it with the genuine result or error as normal.
  TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(cSlowNavigationHintMs);
      TThread.Queue(nil,
        procedure
        begin
          ApplySlowHint(ErrorRows(URI,
            'Not responding yet -- still trying (this can take a while on a slow/unreachable drive)...',
            ReturnUri), Gen);
        end);
    end).Start;
end;

procedure TFilePanelModel.Refresh;
begin
  if FURI <> '' then
    Open(FURI);
end;

function TFilePanelModel.SetRowSize(const AURI: string; ASize: Int64;
  const ASizeText: string): Boolean;
var
  I: Integer;
  Changed: Boolean;
begin
  Result := False;
  if AURI = '' then
    Exit;
  Changed := False;
  for I := 0 to High(FRawRows) do
    if SameVfsUri(FRawRows[I].URI, AURI) then
    begin
      FRawRows[I].Size := ASize;
      FRawRows[I].SizeText := ASizeText;
      Changed := True;
      Break;
    end;
  if not Changed then
    Exit;
  for I := 0 to High(FRows) do
    if SameVfsUri(FRows[I].URI, AURI) then
    begin
      FRows[I].Size := ASize;
      FRows[I].SizeText := ASizeText;
      Break;
    end;
  NotifyChanged;
  Result := True;
end;

end.
