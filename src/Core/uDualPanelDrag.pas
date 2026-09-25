unit uDualPanelDrag;

{ Tab-drag / file-drag / drop hit-testing extracted from TDualPanelWindow.
  Geometry reuses uDualPanelClick; StepTabDrag talks to the host via
  TDualPanelDragHost, bound once in Create. Commit still reloads VFS. }

interface

uses
  System.SysUtils,
  uThemeTypes, uDualPanelTypes, uVfsTypes, uPanelColumns, uDualPanelInput,
  uDualPanelClick;

const
  cTabDragNone       = 0;
  cTabDragWorkspace  = 1;
  cTabDragPanelLeft  = 2;
  cTabDragPanelRight = 3;

type
  TTabDragCommitKind = (tdcCancel, tdcWorkspace, tdcPanel);
  TMouseDownTarget = (mdtNone, mdtTopMenu, mdtWorkspaceTab, mdtEmbedded);

  TDragHitWorkspaceFn = function(ACol: Integer; out AIndex: Integer;
    out AIsClose: Boolean): Boolean of object;
  TDragHitPanelTabFn = function(ASide: TPanelSide; const ABounds: TRectI;
    ACol: Integer; out AIndex: Integer; out AIsClose: Boolean): Boolean of object;

  TDualPanelDragHost = record
    HitWorkspaceTab: TDragHitWorkspaceFn;
    HitPanelTab: TDragHitPanelTabFn;
    NotifyChanged: TKeymapProc;
    CancelFileDrag: TKeymapProc;
  end;

function CanArmTabDrag(AKind, AFrom, AWorkspaceCount: Integer): Boolean;
function ResetTabDrag(var AKind, AFrom, AHover: Integer;
  var AArmed, AActive: Boolean): Boolean;
function TabDragPastThreshold(ACol, ARow, AStartCol, AStartRow: Integer): Boolean;
function TabDragBusy(AArmed, AActive: Boolean): Boolean;
function TabDragPanelSide(AKind: Integer; out ASide: TPanelSide): Boolean;
function ClassifyTabDragCommit(AActive: Boolean; AKind: Integer): TTabDragCommitKind;
function StepTabDrag(const AHost: TDualPanelDragHost;
  var AArmed, AActive: Boolean; AKind: Integer; var AHover: Integer;
  AStartCol, AStartRow, ACol, ARow: Integer;
  const ALeftBounds, ARightBounds: TRectI): Boolean;

function CanArmFileDragSources(APanelsWorkspace, ADialogVisible,
  AJobBusy: Boolean): Boolean;
function FileDragPastThreshold(ACol, ARow, AStartCol, AStartRow: Integer): Boolean;
function ShouldStartFileDrag(ATabDragBusy, AArmed: Boolean;
  ACol, ARow, AStartCol, AStartRow: Integer): Boolean;

function CanHitTestPanelDrag(AKind: TWorkspaceKind; ADialogVisible,
  AJobBusy: Boolean): Boolean;
function CanHitTestListItem(AKind: TWorkspaceKind; ADialogVisible, AJobBusy,
  AMenuOverlay, ADrivePopup, ASearchActive: Boolean): Boolean;
function ResolvePanelHitBounds(ALeftVisible: Boolean; const ALeftBounds: TRectI;
  ALeftKind: TPanelViewKind; ARightVisible: Boolean; const ARightBounds: TRectI;
  ARightKind: TPanelViewKind; ACol, ARow: Integer;
  out ASide: TPanelSide; out ABounds: TRectI): Boolean;
function IsBlockedDropDestURI(const AURI: string): Boolean;
function DropFolderRowURI(const ARow: TPanelRow; out AURI: string): Boolean;
function ResolveDropDest(const ATabURI: string; const ABounds: TRectI;
  AMode: TPanelColumnMode; AScrollOffset, ACol, ARow: Integer;
  const ARows: TPanelRows; out ADestURI: string;
  out AHighlightRow: Integer): Boolean;
function ListItemSourceUri(const ARow: TPanelRow): string;
function ListItemLocalPath(const ARow: TPanelRow): string;

function ClassifyMouseDown(ARow: Integer; AKind: TWorkspaceKind): TMouseDownTarget;

implementation

function CanArmTabDrag(AKind, AFrom, AWorkspaceCount: Integer): Boolean;
begin
  Result := (AKind <> cTabDragNone) and (AFrom >= 0);
  if Result and (AKind = cTabDragWorkspace) then
    Result := AWorkspaceCount > 1;
end;

function ResetTabDrag(var AKind, AFrom, AHover: Integer;
  var AArmed, AActive: Boolean): Boolean;
begin
  Result := AArmed or AActive;
  AArmed := False;
  AActive := False;
  AKind := cTabDragNone;
  AFrom := -1;
  AHover := -1;
end;

function TabDragPastThreshold(ACol, ARow, AStartCol, AStartRow: Integer): Boolean;
begin
  Result := not ((Abs(ACol - AStartCol) < 2) and (Abs(ARow - AStartRow) < 1));
end;

function TabDragBusy(AArmed, AActive: Boolean): Boolean;
begin
  Result := AArmed or AActive;
end;

function TabDragPanelSide(AKind: Integer; out ASide: TPanelSide): Boolean;
begin
  Result := True;
  case AKind of
    cTabDragPanelLeft:
      ASide := psLeft;
    cTabDragPanelRight:
      ASide := psRight;
  else
    Result := False;
    ASide := psLeft;
  end;
end;

function ClassifyTabDragCommit(AActive: Boolean; AKind: Integer): TTabDragCommitKind;
begin
  if not AActive then
    Exit(tdcCancel);
  if AKind = cTabDragWorkspace then
    Result := tdcWorkspace
  else if (AKind = cTabDragPanelLeft) or (AKind = cTabDragPanelRight) then
    Result := tdcPanel
  else
    Result := tdcCancel;
end;

procedure ApplyTabDragHover(const AHost: TDualPanelDragHost; AKind, ACol, ARow: Integer;
  const ALeftBounds, ARightBounds: TRectI; var AHover: Integer);
var
  Idx: Integer;
  IsClose: Boolean;
  Bounds: TRectI;
  Side: TPanelSide;
begin
  case AKind of
    cTabDragWorkspace:
      if ARow = 1 then
        if AHost.HitWorkspaceTab(ACol, Idx, IsClose) then
          AHover := Idx;
    cTabDragPanelLeft, cTabDragPanelRight:
      begin
        if AKind = cTabDragPanelLeft then
          Bounds := ALeftBounds
        else
          Bounds := ARightBounds;
        if ARow = Bounds.Top then
        begin
          if TabDragPanelSide(AKind, Side) and
             AHost.HitPanelTab(Side, Bounds, ACol, Idx, IsClose) then
            AHover := Idx;
        end;
      end;
  end;
end;

function StepTabDrag(const AHost: TDualPanelDragHost;
  var AArmed, AActive: Boolean; AKind: Integer; var AHover: Integer;
  AStartCol, AStartRow, ACol, ARow: Integer;
  const ALeftBounds, ARightBounds: TRectI): Boolean;
var
  Prev: Integer;
begin
  Result := False;
  if not TabDragBusy(AArmed, AActive) then
    Exit;
  if not AActive then
  begin
    if not TabDragPastThreshold(ACol, ARow, AStartCol, AStartRow) then
      Exit(True);
    AActive := True;
    AArmed := False;
    AHost.CancelFileDrag();
  end;
  Prev := AHover;
  ApplyTabDragHover(AHost, AKind, ACol, ARow, ALeftBounds, ARightBounds, AHover);
  Result := True;
  if AHover <> Prev then
    AHost.NotifyChanged();
end;

function CanArmFileDragSources(APanelsWorkspace, ADialogVisible,
  AJobBusy: Boolean): Boolean;
begin
  Result := APanelsWorkspace and (not ADialogVisible) and (not AJobBusy);
end;

function FileDragPastThreshold(ACol, ARow, AStartCol, AStartRow: Integer): Boolean;
begin
  Result := not ((Abs(ACol - AStartCol) < 1) and (Abs(ARow - AStartRow) < 1));
end;

function ShouldStartFileDrag(ATabDragBusy, AArmed: Boolean;
  ACol, ARow, AStartCol, AStartRow: Integer): Boolean;
begin
  Result := (not ATabDragBusy) and AArmed and
    FileDragPastThreshold(ACol, ARow, AStartCol, AStartRow);
end;

function CanHitTestPanelDrag(AKind: TWorkspaceKind; ADialogVisible,
  AJobBusy: Boolean): Boolean;
begin
  Result := (AKind = wkPanels) and (not ADialogVisible) and (not AJobBusy);
end;

function CanHitTestListItem(AKind: TWorkspaceKind; ADialogVisible, AJobBusy,
  AMenuOverlay, ADrivePopup, ASearchActive: Boolean): Boolean;
begin
  Result := CanHitTestPanelDrag(AKind, ADialogVisible, AJobBusy) and
    (not AMenuOverlay) and (not ADrivePopup) and (not ASearchActive);
end;

function ResolvePanelHitBounds(ALeftVisible: Boolean; const ALeftBounds: TRectI;
  ALeftKind: TPanelViewKind; ARightVisible: Boolean; const ARightBounds: TRectI;
  ARightKind: TPanelViewKind; ACol, ARow: Integer;
  out ASide: TPanelSide; out ABounds: TRectI): Boolean;
var
  Kind: TPanelViewKind;
begin
  Result := HitPanelSide(ALeftVisible, ALeftBounds, ARightVisible, ARightBounds,
    ACol, ARow, ASide);
  if not Result then
    Exit;
  if ASide = psLeft then
    Kind := ALeftKind
  else
    Kind := ARightKind;
  if Kind = pvkInfo then
    Exit(False);
  if ASide = psLeft then
    ABounds := ALeftBounds
  else
    ABounds := ARightBounds;
end;

function IsBlockedDropDestURI(const AURI: string): Boolean;
begin
  Result := HasArchiveChain(AURI) or IsFindUri(AURI) or IsSystemFoldersUri(AURI);
end;

function DropFolderRowURI(const ARow: TPanelRow; out AURI: string): Boolean;
begin
  AURI := '';
  Result := ARow.IsDirectory and (not ARow.IsParent) and (ARow.URI <> '') and
    (not HasArchiveChain(ARow.URI));
  if Result then
    AURI := ARow.URI;
end;

function ResolveDropDest(const ATabURI: string; const ABounds: TRectI;
  AMode: TPanelColumnMode; AScrollOffset, ACol, ARow: Integer;
  const ARows: TPanelRows; out ADestURI: string;
  out AHighlightRow: Integer): Boolean;
var
  Idx: Integer;
  FolderURI: string;
begin
  AHighlightRow := -1;
  ADestURI := ATabURI;
  if IsBlockedDropDestURI(ADestURI) then
  begin
    ADestURI := '';
    Exit(False);
  end;
  if HitPanelListIndex(PanelListBounds(ABounds), AMode, AScrollOffset, ACol, ARow,
     Length(ARows), Idx) then
  begin
    if DropFolderRowURI(ARows[Idx], FolderURI) then
    begin
      ADestURI := FolderURI;
      AHighlightRow := Idx;
    end;
  end;
  Result := ADestURI <> '';
end;

function ListItemSourceUri(const ARow: TPanelRow): string;
begin
  Result := ARow.URI;
  if ARow.TargetURI <> '' then
    Result := ARow.TargetURI;
end;

function ListItemLocalPath(const ARow: TPanelRow): string;
var
  Uri: string;
begin
  Result := '';
  Uri := ListItemSourceUri(ARow);
  if (Uri = '') or HasArchiveChain(Uri) then
    Exit;
  Result := FileUriToPath(Uri);
  if Result = '' then
    Exit;
  if not (LocalPathIsFile(Result) or LocalPathIsDirectory(Result)) then
    Result := '';
end;

function ClassifyMouseDown(ARow: Integer; AKind: TWorkspaceKind): TMouseDownTarget;
begin
  if ARow = 0 then
    Exit(mdtTopMenu);
  if (AKind = wkTerminal) or (AKind = wkDocument) then
  begin
    if ARow = 1 then
      Exit(mdtWorkspaceTab);
    Exit(mdtEmbedded);
  end;
  Result := mdtNone;
end;

end.
