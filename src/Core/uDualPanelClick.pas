unit uDualPanelClick;

{ Click hit-testing and overlay dispatch extracted from TDualPanelWindow.HandleClick.
  Geometry helpers are pure; overlay/chrome tables talk to the host via
  TDualPanelClickHost, bound once in Create. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uThemeTypes, uDualPanelTypes, uDualPanelUiTypes, uDualPanelInput, uPanelColumns;

type
  TPanelClickZone = (pczTabs, pczDrives, pczInfo, pczHeaders, pczBody);

  TClickColRowFn = function(ACol, ARow: Integer): Boolean of object;
  TClickColShiftFn = function(ACol: Integer; AShift: TShiftState): Boolean of object;
  TClickDocFn = function(ACol, ARow: Integer; AShift: TShiftState): Boolean of object;
  TClickIntFn = function(ACol: Integer): Boolean of object;
  TClickLayoutProc = procedure(AWidth, AHeight: Integer) of object;
  TClickBoundsFn = function: TRectI of object;
  TClickTabColFn = function(ASide: TPanelSide; const ABounds: TRectI;
    ACol: Integer): Boolean of object;
  TClickDriveProc = procedure(ASide: TPanelSide; ALetter: Char) of object;

  TClickOverlaySnapshot = record
    WorkspaceKind: TWorkspaceKind;
    DialogVisible: Boolean;
    DialogKind: THostDialogKind;
    AreaWidth: Integer;
    AreaHeight: Integer;
    ConsoleMode: Boolean;
    CmdFocused: Boolean;
    TopMenuAssigned: Boolean;
    TopMenuActive: Boolean;
    SearchPhase: TSearchPhase;
    StubVisible: Boolean;
    UserMenuVisible: Boolean;
    SortMenuVisible: Boolean;
    ColumnModeMenuVisible: Boolean;
    DrivePopupVisible: Boolean;
    JobsPhase: TPanelJobPhase;
    JobsKind: TPanelJobKind;
    JobsShowsOverlay: Boolean;
  end;

  TDualPanelClickHost = record
    Invalidate: TKeymapProc;
    NotifyChanged: TKeymapProc;
    HandleTopMenuClick: TClickColRowFn;
    SelectWorkspaceAtCol: TClickIntFn;
    /// <summary>Double-click on a workspace tab caption (not the close mark).
    /// Returns True when a tab was hit and the rename dialog opened.</summary>
    BeginRenameWorkspaceAtCol: TClickIntFn;
    HandleDocumentClick: TClickDocFn;
    HandleTerminalClick: TClickDocFn;
    HandleFunctionBarClick: TClickColShiftFn;
    HandleDialogClick: TClickDocFn;
    SyncColorPickerHex: TKeymapProc;
    LayoutSearchUi: TClickLayoutProc;
    SearchBounds: TClickBoundsFn;
    CloseSearchUi: TKeymapProc;
    CloseStub: TKeymapProc;
    HandleUserMenuClick: TClickColRowFn;
    HandleSortMenuClick: TClickColRowFn;
    HandleColumnModeMenuClick: TClickColRowFn;
    HandleDrivePopupClick: TClickColRowFn;
    LayoutJobPopup: TClickLayoutProc;
    JobBounds: TClickBoundsFn;
    RequestJobCancel: TKeymapProc;
    BackgroundJob: TKeymapProc;
    CloseJobUi: TKeymapProc;
    CancelOverwriteAsk: TKeymapProc;
    CancelDeleteAsk: TKeymapProc;
    CancelIOErrorAsk: TKeymapProc;
    ReloadActiveRows: TKeymapProc;
    OpenJobList: TKeymapProc;
    SetCmdFocused: TKeymapBoolProc;
    /// <summary>Optional: click on the command-line row (caret / word / line).</summary>
    ClickCmdLine: TClickDocFn;
    NewWorkspace: TKeymapProc;
    ActivateSide: TKeymapSideProc;
    SelectPanelTabAtCol: TClickTabColFn;
    NewPanelTabOnSide: TKeymapSideProc;
    NavigatePanelToDrive: TClickDriveProc;
    ApplyHeaderSort: TKeymapSortProc;
  end;

function PanelListBounds(const ABounds: TRectI): TRectI;
function HitPanelSide(ALeftVisible: Boolean; const ALeftBounds: TRectI;
  ARightVisible: Boolean; const ARightBounds: TRectI; ACol, ARow: Integer;
  out ASide: TPanelSide): Boolean;
function ClassifyPanelClickZone(ALocalRow: Integer; const ABounds: TRectI;
  AViewKind: TPanelViewKind): TPanelClickZone;
function HitPanelListIndex(const AListBounds: TRectI; AMode: TPanelColumnMode;
  AScrollOffset, ALocalCol, ALocalRow, ARowCount: Integer;
  out AIndex: Integer): Boolean;
function UpdateListClickPair(AHitList, AAllowOpenOnDouble: Boolean;
  var ADoubleClick: Boolean; ACol, ARow: Integer;
  var ALastCol, ALastRow: Integer; var ALastTick: Cardinal;
  ANow, ADoubleMs: Cardinal): Boolean;

function DispatchClickOverlays(const AHost: TDualPanelClickHost;
  const ASnap: TClickOverlaySnapshot; ALocalCol, ALocalRow: Integer;
  AShift: TShiftState; ADoubleClick: Boolean; out AHandled: Boolean): Boolean;
function DispatchPanelChromeClick(const AHost: TDualPanelClickHost;
  ASide: TPanelSide; const ABounds: TRectI; AViewKind: TPanelViewKind;
  AColumnMode: TPanelColumnMode; ACol, ARow: Integer;
  ADoubleClick: Boolean): Boolean;

implementation

uses
  uThemeDrawing, uDualPanelDrawUtils, uJobPopupRenderer;

function PanelListBounds(const ABounds: TRectI): TRectI;
begin
  Result := TRectI.Make(ABounds.Left + 1, ABounds.Top + 2,
    ABounds.Right - 2, ABounds.Bottom - 3);
end;

function HitPanelSide(ALeftVisible: Boolean; const ALeftBounds: TRectI;
  ARightVisible: Boolean; const ARightBounds: TRectI; ACol, ARow: Integer;
  out ASide: TPanelSide): Boolean;
begin
  Result := True;
  if ALeftVisible and ALeftBounds.Contains(ACol, ARow) then
    ASide := psLeft
  else if ARightVisible and ARightBounds.Contains(ACol, ARow) then
    ASide := psRight
  else
    Result := False;
end;

function ClassifyPanelClickZone(ALocalRow: Integer; const ABounds: TRectI;
  AViewKind: TPanelViewKind): TPanelClickZone;
begin
  if ALocalRow = ABounds.Top then
    Exit(pczTabs);
  if ALocalRow = ABounds.Bottom then
    Exit(pczDrives);
  if AViewKind = pvkInfo then
    Exit(pczInfo);
  if ALocalRow = ABounds.Top + 1 then
    Exit(pczHeaders);
  Result := pczBody;
end;

function HitPanelListIndex(const AListBounds: TRectI; AMode: TPanelColumnMode;
  AScrollOffset, ALocalCol, ALocalRow, ARowCount: Integer;
  out AIndex: Integer): Boolean;
var
  ViewH, Cols, CellW: Integer;
begin
  Result := False;
  AIndex := -1;
  if (ALocalRow < AListBounds.Top) or (ALocalRow > AListBounds.Bottom) or
     (ALocalCol < AListBounds.Left) or (ALocalCol > AListBounds.Right) then
    Exit;
  ViewH := AListBounds.Height;
  Cols := PanelListColumnCount(AMode, AListBounds.Width);
  if (AMode = pcmBrief) and (Cols > 1) then
  begin
    CellW := BriefCellWidth(AListBounds.Width, Cols);
    AIndex := BriefHitIndex(AScrollOffset,
      ALocalCol - AListBounds.Left, ALocalRow - AListBounds.Top,
      ViewH, CellW, Cols, ARowCount);
  end
  else
    AIndex := AScrollOffset + (ALocalRow - AListBounds.Top);
  Result := (AIndex >= 0) and (AIndex < ARowCount);
  if not Result then
    AIndex := -1;
end;

function UpdateListClickPair(AHitList, AAllowOpenOnDouble: Boolean;
  var ADoubleClick: Boolean; ACol, ARow: Integer;
  var ALastCol, ALastRow: Integer; var ALastTick: Cardinal;
  ANow, ADoubleMs: Cardinal): Boolean;
begin
  Result := False;
  if (not AHitList) or (not AAllowOpenOnDouble) then
  begin
    ALastCol := -1;
    ALastRow := -1;
    ALastTick := 0;
    Exit;
  end;
  if not ADoubleClick and (ALastCol = ACol) and (ALastRow = ARow) and
     (ANow - ALastTick <= ADoubleMs) then
    ADoubleClick := True;
  ALastCol := ACol;
  ALastRow := ARow;
  ALastTick := ANow;
  if ADoubleClick then
  begin
    ALastTick := 0;
    Result := True;
  end;
end;

procedure ConsumeMenuClick(const AClick: TClickColRowFn;
  const AHost: TDualPanelClickHost; ACol, ARow: Integer);
begin
  if AClick(ACol, ARow) then
    AHost.NotifyChanged();
end;

function DispatchWorkspaceTabRow(const AHost: TDualPanelClickHost;
  ALocalCol: Integer; ADoubleClick: Boolean; var AHandled: Boolean): Boolean;
begin
  Result := True;
  if ADoubleClick and Assigned(AHost.BeginRenameWorkspaceAtCol) and
     AHost.BeginRenameWorkspaceAtCol(ALocalCol) then
  begin
    AHandled := True;
    Exit;
  end;
  AHandled := AHost.SelectWorkspaceAtCol(ALocalCol);
  if (not AHandled) and ADoubleClick and Assigned(AHost.NewWorkspace) then
  begin
    AHost.NewWorkspace();
    AHandled := True;
  end;
end;

function DispatchWorkspaceBody(const AHost: TDualPanelClickHost;
  AKind: TWorkspaceKind; ALocalCol, ALocalRow: Integer; AShift: TShiftState;
  ADoubleClick: Boolean; var AHandled: Boolean): Boolean;
begin
  Result := True;
  if ALocalRow = 1 then
    DispatchWorkspaceTabRow(AHost, ALocalCol, ADoubleClick, AHandled)
  else if ALocalRow >= 2 then
  begin
    if AKind = wkDocument then
      AHandled := AHost.HandleDocumentClick(ALocalCol, ALocalRow - 2, AShift)
    else
      AHandled := AHost.HandleTerminalClick(ALocalCol, ALocalRow - 2, AShift);
  end;
end;

function TryDispatchJobOverlay(const AHost: TDualPanelClickHost;
  const ASnap: TClickOverlaySnapshot; ALocalCol, ALocalRow: Integer): Boolean;
var
  Bounds: TRectI;
begin
  Result := False;
  if not (ASnap.JobsShowsOverlay or
     (ASnap.JobsPhase in [pjpConfirm, pjpOverwriteAsk, pjpDeleteAsk, pjpIOErrorAsk])) then
    Exit;
  Result := True;
  AHost.LayoutJobPopup(ASnap.AreaWidth, ASnap.AreaHeight);
  Bounds := AHost.JobBounds();
  if ASnap.JobsPhase = pjpRunning then
  begin
    if WindowFrameCloseHit(Bounds, ALocalCol, ALocalRow) then
      AHost.RequestJobCancel()
    else if JobPopupBackgroundHit(Bounds, ASnap.JobsKind, ALocalCol, ALocalRow) then
    begin
      if Assigned(AHost.BackgroundJob) then
        AHost.BackgroundJob();
    end;
    Exit;
  end;
  if WindowFrameCloseHit(Bounds, ALocalCol, ALocalRow) then
  begin
    AHost.CloseJobUi();
    AHost.NotifyChanged();
    Exit;
  end;
  if Bounds.Contains(ALocalCol, ALocalRow) then
    Exit;
  // Confirm UI is the host dialog; do not cancel the pending job on
  // background clicks while the dialog is still open.
  if (ASnap.JobsPhase in [pjpConfirm, pjpOverwriteAsk, pjpDeleteAsk, pjpIOErrorAsk]) and
     ASnap.DialogVisible then
    Exit;
  if ASnap.JobsPhase in [pjpConfirm, pjpOverwriteAsk, pjpDeleteAsk, pjpIOErrorAsk] then
  begin
    case ASnap.JobsPhase of
      pjpOverwriteAsk: AHost.CancelOverwriteAsk();
      pjpDeleteAsk: AHost.CancelDeleteAsk();
      pjpIOErrorAsk: AHost.CancelIOErrorAsk();
    else
      AHost.CloseJobUi();
    end;
    AHost.NotifyChanged();
    Exit;
  end;
  if ASnap.JobsPhase = pjpError then
  begin
    AHost.CloseJobUi();
    AHost.ReloadActiveRows();
    AHost.NotifyChanged();
  end;
end;

function DispatchClickOverlays(const AHost: TDualPanelClickHost;
  const ASnap: TClickOverlaySnapshot; ALocalCol, ALocalRow: Integer;
  AShift: TShiftState; ADoubleClick: Boolean; out AHandled: Boolean): Boolean;
var
  Bounds: TRectI;
begin
  Result := True;
  AHandled := True;

  // Row 0 is the Dual Panel menu bar for every workspace kind (panels,
  // Viewer/Editor, Terminal). Skip only while a modal dialog is open —
  // otherwise the click would drive the menu behind the dialog. Document
  // tabs used to exclude this branch, which swallowed row 0 (the document
  // arm below only handles row 1 / >= 2).
  if ASnap.TopMenuAssigned and (not ASnap.DialogVisible) and
     (ASnap.TopMenuActive or (ALocalRow = 0)) then
  begin
    if AHost.HandleTopMenuClick(ALocalCol, ALocalRow) then
    begin
      AHost.Invalidate();
      Exit;
    end;
  end;

  if (ASnap.WorkspaceKind in [wkDocument, wkTerminal]) and (not ASnap.DialogVisible) then
  begin
    DispatchWorkspaceBody(AHost, ASnap.WorkspaceKind, ALocalCol, ALocalRow,
      AShift, ADoubleClick, AHandled);
    Exit;
  end;

  if (ALocalRow = ASnap.AreaHeight - 2) and (not ASnap.DialogVisible) and
     (not ASnap.StubVisible) then
  begin
    AHandled := AHost.HandleFunctionBarClick(ALocalCol, AShift);
    Exit;
  end;

  if ASnap.StubVisible then
  begin
    AHost.CloseStub();
    AHost.NotifyChanged();
    Exit;
  end;

  if ASnap.DialogVisible then
  begin
    AHandled := AHost.HandleDialogClick(ALocalCol, ALocalRow, AShift);
    if ASnap.DialogKind = hdkColorPicker then
      AHost.SyncColorPickerHex();
    Exit;
  end;

  if ASnap.SearchPhase <> spNone then
  begin
    if ASnap.SearchPhase <> spDialog then
    begin
      AHost.LayoutSearchUi(ASnap.AreaWidth, ASnap.AreaHeight);
      Bounds := AHost.SearchBounds();
      if WindowFrameCloseHit(Bounds, ALocalCol, ALocalRow) or
         (not Bounds.Contains(ALocalCol, ALocalRow)) then
      begin
        AHost.CloseSearchUi();
        AHost.NotifyChanged();
      end;
    end;
    Exit;
  end;

  if ASnap.UserMenuVisible then
  begin
    ConsumeMenuClick(AHost.HandleUserMenuClick, AHost, ALocalCol, ALocalRow);
    Exit;
  end;
  if ASnap.SortMenuVisible then
  begin
    ConsumeMenuClick(AHost.HandleSortMenuClick, AHost, ALocalCol, ALocalRow);
    Exit;
  end;
  if ASnap.ColumnModeMenuVisible then
  begin
    ConsumeMenuClick(AHost.HandleColumnModeMenuClick, AHost, ALocalCol, ALocalRow);
    Exit;
  end;

  if ASnap.DrivePopupVisible then
  begin
    AHandled := AHost.HandleDrivePopupClick(ALocalCol, ALocalRow);
    Exit;
  end;

  if (ALocalRow = ASnap.AreaHeight - 1) and (not ASnap.DialogVisible) and
     (not ASnap.StubVisible) and (ASnap.JobsPhase <> pjpNone) then
  begin
    if Assigned(AHost.OpenJobList) then
      AHost.OpenJobList();
    Exit;
  end;

  if TryDispatchJobOverlay(AHost, ASnap, ALocalCol, ALocalRow) then
    Exit;

  if (not ASnap.ConsoleMode) and (ALocalRow = ASnap.AreaHeight - 3) then
  begin
    AHost.SetCmdFocused(True);
    if Assigned(AHost.ClickCmdLine) then
      AHost.ClickCmdLine(ALocalCol, ALocalRow, AShift);
    Exit;
  end;

  if ASnap.CmdFocused then
    AHost.SetCmdFocused(False);

  if ALocalRow = 1 then
  begin
    DispatchWorkspaceTabRow(AHost, ALocalCol, ADoubleClick, AHandled);
    Exit;
  end;

  Result := False;
end;

function DispatchPanelChromeClick(const AHost: TDualPanelClickHost;
  ASide: TPanelSide; const ABounds: TRectI; AViewKind: TPanelViewKind;
  AColumnMode: TPanelColumnMode; ACol, ARow: Integer;
  ADoubleClick: Boolean): Boolean;
var
  DriveLetter: Char;
  SortCol: TPanelSortColumn;
begin
  Result := True;
  case ClassifyPanelClickZone(ARow, ABounds, AViewKind) of
    pczTabs:
      begin
        if AHost.SelectPanelTabAtCol(ASide, ABounds, ACol) then
          Exit;
        if ADoubleClick then
        begin
          AHost.NewPanelTabOnSide(ASide);
          Exit;
        end;
        AHost.ActivateSide(ASide);
        AHost.Invalidate();
      end;
    pczDrives:
      begin
        AHost.ActivateSide(ASide);
        if HitPanelDriveLetterAtCol(ABounds, ACol, DriveLetter) then
          AHost.NavigatePanelToDrive(ASide, DriveLetter)
        else
          AHost.Invalidate();
      end;
    pczInfo:
      begin
        AHost.ActivateSide(ASide);
        AHost.Invalidate();
      end;
    pczHeaders:
      begin
        AHost.ActivateSide(ASide);
        if HitPanelSortColumn(AColumnMode, ABounds.Right - ABounds.Left - 2,
          ACol - (ABounds.Left + 1), SortCol) then
          AHost.ApplyHeaderSort(ASide, SortCol)
        else
          AHost.Invalidate();
      end;
  else
    Result := False;
  end;
end;

end.
