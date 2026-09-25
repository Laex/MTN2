program TestDualPanelClick;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.UITypes,
  uThemeTypes in '..\..\Core\uThemeTypes.pas',
  uDualPanelTypes in '..\..\Core\uDualPanelTypes.pas',
  uDualPanelUiTypes in '..\..\Core\uDualPanelUiTypes.pas',
  uKeymap in '..\..\Core\uKeymap.pas',
  uDualPanelInput in '..\..\Core\uDualPanelInput.pas',
  uDualPanelClick in '..\..\Core\uDualPanelClick.pas';

type
  TClickSpy = class
  public
    Last: string;
    Side: TPanelSide;
    Focused: Boolean;
    MenuHit: Boolean;
    TabHit: Boolean;
    JobBounds: TRectI;
    SearchBounds: TRectI;
    procedure Invalidate;
    procedure NotifyChanged;
    function HandleTopMenu(ACol, ARow: Integer): Boolean;
    function SelectWorkspace(ACol: Integer): Boolean;
    function HandleDocument(ACol, ARow: Integer; AShift: TShiftState): Boolean;
    function HandleTerminal(ACol, ARow: Integer; AShift: TShiftState): Boolean;
    function HandleFunctionBar(ACol: Integer; AShift: TShiftState): Boolean;
    function HandleDialog(ACol, ARow: Integer; AShift: TShiftState): Boolean;
    procedure SyncHex;
    procedure LayoutSearch(AWidth, AHeight: Integer);
    function GetSearchBounds: TRectI;
    procedure CloseSearch;
    procedure CloseStub;
    function HandleUserMenu(ACol, ARow: Integer): Boolean;
    function HandleSortMenu(ACol, ARow: Integer): Boolean;
    function HandleColumnMode(ACol, ARow: Integer): Boolean;
    function HandleDrivePopup(ACol, ARow: Integer): Boolean;
    procedure LayoutJob(AWidth, AHeight: Integer);
    function GetJobBounds: TRectI;
    procedure RequestCancel;
    procedure BackgroundJob;
    procedure CloseJob;
    procedure CancelOverwrite;
    procedure CancelDelete;
    procedure ReloadRows;
    procedure SetCmdFocused(AValue: Boolean);
    procedure NewWorkspace;
    procedure ActivateSide(ASide: TPanelSide);
    function SelectPanelTab(ASide: TPanelSide; const ABounds: TRectI;
      ACol: Integer): Boolean;
    procedure NewPanelTab(ASide: TPanelSide);
    procedure NavigateDrive(ASide: TPanelSide; ALetter: Char);
    procedure ApplyHeaderSort(ASide: TPanelSide; ACol: TPanelSortColumn);
  end;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

procedure TClickSpy.Invalidate;
begin
  Last := Last + '+inv';
end;

procedure TClickSpy.NotifyChanged;
begin
  Last := Last + '+notify';
end;

function TClickSpy.HandleTopMenu(ACol, ARow: Integer): Boolean;
begin
  Last := 'topmenu';
  Result := MenuHit;
end;

function TClickSpy.SelectWorkspace(ACol: Integer): Boolean;
begin
  Last := 'wstab';
  Result := TabHit;
end;

function TClickSpy.HandleDocument(ACol, ARow: Integer; AShift: TShiftState): Boolean;
begin
  Last := Format('doc:%d:%d', [ACol, ARow]);
  Result := True;
end;

function TClickSpy.HandleTerminal(ACol, ARow: Integer; AShift: TShiftState): Boolean;
begin
  Last := Format('term:%d:%d', [ACol, ARow]);
  Result := True;
end;

function TClickSpy.HandleFunctionBar(ACol: Integer; AShift: TShiftState): Boolean;
begin
  Last := 'fbar';
  Result := True;
end;

function TClickSpy.HandleDialog(ACol, ARow: Integer; AShift: TShiftState): Boolean;
begin
  Last := 'dialog';
  Result := True;
end;

procedure TClickSpy.SyncHex;
begin
  Last := Last + '+hex';
end;

procedure TClickSpy.LayoutSearch(AWidth, AHeight: Integer);
begin
  Last := Last + '+slayout';
end;

function TClickSpy.GetSearchBounds: TRectI;
begin
  Result := SearchBounds;
end;

procedure TClickSpy.CloseSearch;
begin
  Last := Last + '+sclose';
end;

procedure TClickSpy.CloseStub;
begin
  Last := 'stub';
end;

function TClickSpy.HandleUserMenu(ACol, ARow: Integer): Boolean;
begin
  Last := 'usermenu';
  Result := True;
end;

function TClickSpy.HandleSortMenu(ACol, ARow: Integer): Boolean;
begin
  Last := 'sortmenu';
  Result := True;
end;

function TClickSpy.HandleColumnMode(ACol, ARow: Integer): Boolean;
begin
  Last := 'colmenu';
  Result := True;
end;

function TClickSpy.HandleDrivePopup(ACol, ARow: Integer): Boolean;
begin
  Last := 'drivepop';
  Result := False;
end;

procedure TClickSpy.LayoutJob(AWidth, AHeight: Integer);
begin
  Last := Last + '+jlayout';
end;

function TClickSpy.GetJobBounds: TRectI;
begin
  Result := JobBounds;
end;

procedure TClickSpy.RequestCancel;
begin
  Last := Last + '+cancel';
end;

procedure TClickSpy.BackgroundJob;
begin
  Last := Last + '+bg';
end;

procedure TClickSpy.CloseJob;
begin
  Last := Last + '+jclose';
end;

procedure TClickSpy.CancelOverwrite;
begin
  Last := Last + '+ow';
end;

procedure TClickSpy.CancelDelete;
begin
  Last := Last + '+del';
end;

procedure TClickSpy.ReloadRows;
begin
  Last := Last + '+reload';
end;

procedure TClickSpy.SetCmdFocused(AValue: Boolean);
begin
  Last := 'cmd';
  Focused := AValue;
end;

procedure TClickSpy.NewWorkspace;
begin
  Last := Last + '+newws';
end;

procedure TClickSpy.ActivateSide(ASide: TPanelSide);
begin
  Last := 'activate';
  Side := ASide;
end;

function TClickSpy.SelectPanelTab(ASide: TPanelSide; const ABounds: TRectI;
  ACol: Integer): Boolean;
begin
  Last := 'ptab';
  Side := ASide;
  Result := TabHit;
end;

procedure TClickSpy.NewPanelTab(ASide: TPanelSide);
begin
  Last := 'newptab';
  Side := ASide;
end;

procedure TClickSpy.NavigateDrive(ASide: TPanelSide; ALetter: Char);
begin
  Last := 'navdrive';
  Side := ASide;
end;

procedure TClickSpy.ApplyHeaderSort(ASide: TPanelSide; ACol: TPanelSortColumn);
begin
  Last := 'sort';
  Side := ASide;
end;

procedure BindSpy(var AHost: TDualPanelClickHost; ASpy: TClickSpy);
begin
  FillChar(AHost, SizeOf(AHost), 0);
  AHost.Invalidate := ASpy.Invalidate;
  AHost.NotifyChanged := ASpy.NotifyChanged;
  AHost.HandleTopMenuClick := ASpy.HandleTopMenu;
  AHost.SelectWorkspaceAtCol := ASpy.SelectWorkspace;
  AHost.HandleDocumentClick := ASpy.HandleDocument;
  AHost.HandleTerminalClick := ASpy.HandleTerminal;
  AHost.HandleFunctionBarClick := ASpy.HandleFunctionBar;
  AHost.HandleDialogClick := ASpy.HandleDialog;
  AHost.SyncColorPickerHex := ASpy.SyncHex;
  AHost.LayoutSearchUi := ASpy.LayoutSearch;
  AHost.SearchBounds := ASpy.GetSearchBounds;
  AHost.CloseSearchUi := ASpy.CloseSearch;
  AHost.CloseStub := ASpy.CloseStub;
  AHost.HandleUserMenuClick := ASpy.HandleUserMenu;
  AHost.HandleSortMenuClick := ASpy.HandleSortMenu;
  AHost.HandleColumnModeMenuClick := ASpy.HandleColumnMode;
  AHost.HandleDrivePopupClick := ASpy.HandleDrivePopup;
  AHost.LayoutJobPopup := ASpy.LayoutJob;
  AHost.JobBounds := ASpy.GetJobBounds;
  AHost.RequestJobCancel := ASpy.RequestCancel;
  AHost.BackgroundJob := ASpy.BackgroundJob;
  AHost.CloseJobUi := ASpy.CloseJob;
  AHost.CancelOverwriteAsk := ASpy.CancelOverwrite;
  AHost.CancelDeleteAsk := ASpy.CancelDelete;
  AHost.ReloadActiveRows := ASpy.ReloadRows;
  AHost.SetCmdFocused := ASpy.SetCmdFocused;
  AHost.NewWorkspace := ASpy.NewWorkspace;
  AHost.ActivateSide := ASpy.ActivateSide;
  AHost.SelectPanelTabAtCol := ASpy.SelectPanelTab;
  AHost.NewPanelTabOnSide := ASpy.NewPanelTab;
  AHost.NavigatePanelToDrive := ASpy.NavigateDrive;
  AHost.ApplyHeaderSort := ASpy.ApplyHeaderSort;
end;

procedure TestGeometry;
var
  LeftB, RightB, ListB, Outer: TRectI;
  Side: TPanelSide;
  Idx: Integer;
begin
  Writeln('Geometry');
  Outer := TRectI.Make(0, 2, 58, 17);
  ListB := PanelListBounds(Outer);
  Expect((ListB.Left = 1) and (ListB.Top = 4) and (ListB.Right = 56) and
    (ListB.Bottom = 14), 'list inset');

  LeftB := TRectI.Make(0, 2, 39, 20);
  RightB := TRectI.Make(40, 2, 79, 20);
  Expect(HitPanelSide(True, LeftB, True, RightB, 10, 5, Side) and (Side = psLeft),
    'left panel hit');
  Expect(HitPanelSide(True, LeftB, True, RightB, 50, 5, Side) and (Side = psRight),
    'right panel hit');
  Expect(not HitPanelSide(False, LeftB, True, RightB, 10, 5, Side),
    'hidden left misses');
  Expect(not HitPanelSide(True, LeftB, True, RightB, 10, 0, Side),
    'above panels misses');

  Expect(ClassifyPanelClickZone(2, Outer, pvkFiles) = pczTabs, 'top row tabs');
  Expect(ClassifyPanelClickZone(17, Outer, pvkFiles) = pczDrives, 'bottom drives');
  Expect(ClassifyPanelClickZone(5, Outer, pvkInfo) = pczInfo, 'info swallows body');
  Expect(ClassifyPanelClickZone(3, Outer, pvkFiles) = pczHeaders, 'header row');
  Expect(ClassifyPanelClickZone(8, Outer, pvkFiles) = pczBody, 'list body');

  ListB := TRectI.Make(1, 4, 20, 13);
  Expect(HitPanelListIndex(ListB, pcmFull, 0, 5, 6, 10, Idx) and (Idx = 2),
    'full list row');
  Expect(not HitPanelListIndex(ListB, pcmFull, 0, 0, 6, 10, Idx),
    'left frame is not a row');
  Expect(not HitPanelListIndex(ListB, pcmFull, 0, 5, 6, 0, Idx),
    'empty list misses');
end;

procedure TestOverlays;
var
  Spy: TClickSpy;
  Host: TDualPanelClickHost;
  Snap: TClickOverlaySnapshot;
  Owned, Handled: Boolean;
begin
  Writeln('Overlay dispatch');
  Spy := TClickSpy.Create;
  try
    BindSpy(Host, Spy);
    Snap := Default(TClickOverlaySnapshot);
    Snap.WorkspaceKind := wkPanels;
    Snap.AreaHeight := 24;
    Snap.AreaWidth := 80;

    Spy.MenuHit := True;
    Snap.TopMenuAssigned := True;
    Owned := DispatchClickOverlays(Host, Snap, 3, 0, [], False, Handled);
    Expect(Owned and Handled and (Spy.Last = 'topmenu+inv'), 'top menu consumes row 0');

    Spy.Last := '';
    Spy.MenuHit := True;
    Snap.WorkspaceKind := wkDocument;
    Owned := DispatchClickOverlays(Host, Snap, 3, 0, [], False, Handled);
    Expect(Owned and Handled and (Spy.Last = 'topmenu+inv'),
      'document row 0 is top menu');

    Spy.Last := '';
    Snap.WorkspaceKind := wkTerminal;
    Owned := DispatchClickOverlays(Host, Snap, 3, 0, [], False, Handled);
    Expect(Owned and Handled and (Spy.Last = 'topmenu+inv'),
      'terminal row 0 is top menu');

    Spy.Last := '';
    Spy.MenuHit := True;
    Snap.TopMenuAssigned := True;
    Snap.TopMenuActive := True;
    Snap.WorkspaceKind := wkDocument;
    Owned := DispatchClickOverlays(Host, Snap, 4, 5, [], False, Handled);
    Expect(Owned and Handled and (Spy.Last = 'topmenu+inv'),
      'open submenu wins over document body');

    Spy.Last := '';
    Snap.WorkspaceKind := wkTerminal;
    Owned := DispatchClickOverlays(Host, Snap, 4, 5, [], False, Handled);
    Expect(Owned and Handled and (Spy.Last = 'topmenu+inv'),
      'open submenu wins over terminal body');
    Snap.TopMenuActive := False;

    Spy.Last := '';
    Spy.MenuHit := False;
    Snap.WorkspaceKind := wkPanels;
    Owned := DispatchClickOverlays(Host, Snap, 3, 0, [], False, Handled);
    Expect(not Owned, 'top menu miss falls through');

    Snap.TopMenuAssigned := False;
    Snap.WorkspaceKind := wkDocument;
    Owned := DispatchClickOverlays(Host, Snap, 4, 5, [], False, Handled);
    Expect(Owned and (Spy.Last = 'doc:4:3'), 'document body is row-2');

    Snap.WorkspaceKind := wkTerminal;
    Owned := DispatchClickOverlays(Host, Snap, 1, 1, [], False, Handled);
    Expect(Owned and (Spy.Last = 'wstab'), 'terminal row 1 is workspace tabs');

    Snap.WorkspaceKind := wkPanels;
    Owned := DispatchClickOverlays(Host, Snap, 2, 22, [], False, Handled);
    Expect(Owned and (Spy.Last = 'fbar'), 'F-bar is height-2');

    Snap.DialogVisible := True;
    Snap.DialogKind := hdkColorPicker;
    Owned := DispatchClickOverlays(Host, Snap, 2, 10, [], False, Handled);
    Expect(Owned and (Spy.Last = 'dialog+hex'), 'color picker syncs hex');

    Snap.DialogVisible := False;
    Snap.SearchPhase := spRunning;
    Spy.SearchBounds := TRectI.Make(10, 10, 40, 20);
    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 0, 0, [], False, Handled);
    Expect(Owned and (Pos('+sclose', Spy.Last) > 0), 'outside search closes it');

    Snap.SearchPhase := spDialog;
    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 0, 0, [], False, Handled);
    Expect(Owned and (Spy.Last = ''), 'search dialog click is swallowed');

    Snap.SearchPhase := spNone;
    Snap.JobsPhase := pjpRunning;
    Snap.JobsKind := pjkCopy;
    Snap.JobsShowsOverlay := True;
    Spy.JobBounds := TRectI.Make(10, 10, 40, 22);
    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 38, 10, [], False, Handled);
    Expect(Owned and (Pos('+cancel', Spy.Last) > 0), 'running job close cancels');

    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 12, 21, [], False, Handled);
    Expect(Owned and (Pos('+bg', Spy.Last) > 0), 'running job Background button');

    Snap.JobsShowsOverlay := False;
    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 2, 12, [], False, Handled);
    Expect((not Owned) or (Pos('+cancel', Spy.Last) = 0),
      'background running does not eat panel clicks');

    Snap.JobsPhase := pjpOverwriteAsk;
    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 0, 0, [], False, Handled);
    Expect(Owned and (Pos('+ow', Spy.Last) > 0), 'overwrite outside cancels ask');

    Snap.JobsPhase := pjpConfirm;
    Snap.DialogVisible := True;
    Snap.DialogKind := hdkJobConfirm;
    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 0, 0, [], False, Handled);
    Expect(Owned and (Spy.Last = 'dialog'),
      'open dialog wins over job confirm');

    Snap.StubVisible := True;
    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 0, 0, [], False, Handled);
    Expect(Owned and (Pos('stub', Spy.Last) > 0),
      'stub sits above dialog');
    Snap.StubVisible := False;

    Snap.DialogVisible := False;
    Snap.JobsPhase := pjpNone;
    Owned := DispatchClickOverlays(Host, Snap, 2, 21, [], False, Handled);
    Expect(Owned and Spy.Focused, 'cmdline row focuses');

    Spy.TabHit := False;
    Owned := DispatchClickOverlays(Host, Snap, 70, 1, [], True, Handled);
    Expect(Owned and Handled and (Pos('+newws', Spy.Last) > 0),
      'empty workspace row double-click clones');
  finally
    Spy.Free;
  end;
end;

procedure TestChromeClick;
var
  Spy: TClickSpy;
  Host: TDualPanelClickHost;
  Bounds: TRectI;
begin
  Writeln('Panel chrome click');
  Spy := TClickSpy.Create;
  try
    BindSpy(Host, Spy);
    Bounds := TRectI.Make(0, 2, 40, 20);

    Spy.TabHit := True;
    Expect(DispatchPanelChromeClick(Host, psLeft, Bounds, pvkFiles, pcmFull,
      5, 2, False) and (Spy.Last = 'ptab'), 'tab hit');

    Spy.TabHit := False;
    Expect(DispatchPanelChromeClick(Host, psRight, Bounds, pvkFiles, pcmFull,
      5, 2, True) and (Spy.Last = 'newptab') and (Spy.Side = psRight),
      'empty tab row double-click');

    Expect(DispatchPanelChromeClick(Host, psLeft, Bounds, pvkInfo, pcmFull,
      8, 8, False) and (Spy.Last = 'activate+inv'), 'info activates only');

    Expect(not DispatchPanelChromeClick(Host, psLeft, Bounds, pvkFiles, pcmFull,
      8, 8, False), 'body is not chrome');
  finally
    Spy.Free;
  end;
end;

procedure TestListClickPair;
var
  LastCol, LastRow: Integer;
  LastTick: Cardinal;
  Dbl: Boolean;
begin
  LastCol := -1;
  LastRow := -1;
  LastTick := 0;
  Dbl := False;
  Expect(not UpdateListClickPair(False, True, Dbl, 3, 4, LastCol, LastRow,
    LastTick, 100, 50), 'miss does not activate');
  Expect(LastCol = -1, 'miss resets last col');

  Dbl := False;
  Expect(not UpdateListClickPair(True, False, Dbl, 3, 4, LastCol, LastRow,
    LastTick, 100, 50), 'right-click does not activate');
  Expect(LastCol = -1, 'right-click resets pair');

  Dbl := False;
  Expect(not UpdateListClickPair(True, True, Dbl, 3, 4, LastCol, LastRow,
    LastTick, 100, 50), 'first left click arms');
  Expect((LastCol = 3) and (LastRow = 4) and (LastTick = 100), 'first click stored');

  Dbl := False;
  Expect(UpdateListClickPair(True, True, Dbl, 3, 4, LastCol, LastRow,
    LastTick, 120, 50), 'second click in time activates');
  Expect(Dbl, 'paired click becomes double');
  Expect(LastTick = 0, 'activate clears tick');

  Dbl := True;
  LastTick := 200;
  Expect(UpdateListClickPair(True, True, Dbl, 5, 6, LastCol, LastRow,
    LastTick, 200, 50), 'ssDouble activates immediately');
end;

begin
  try
    TestGeometry;
    TestOverlays;
    TestChromeClick;
    TestListClickPair;
    Writeln('All DualPanelClick tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
