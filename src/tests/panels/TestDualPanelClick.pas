unit TestDualPanelClick;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelClick = class
  public
    [Test] procedure TestGeometry;
    [Test] procedure TestOverlays;
    [Test] procedure TestChromeClick;
    [Test] procedure TestJobStripClick;
    [Test] procedure TestListClickPair;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uThemeTypes,
  uDualPanelTypes,
  uDualPanelUiTypes,
  uKeymap,
  uDualPanelInput,
  uDualPanelClick;

type
  TClickSpy = class
  public
    Last: string;
    Side: TPanelSide;
    Focused: Boolean;
    MenuHit: Boolean;
    TabHit: Boolean;
    StripHit: Boolean;
    StripCol: Integer;
    JobBounds: TRectI;
    SearchBounds: TRectI;
    procedure Invalidate;
    procedure NotifyChanged;
    function HandleTopMenu(ACol, ARow: Integer): Boolean;
    function SelectWorkspace(ACol: Integer): Boolean;
    function JobStrip(ACol: Integer): Boolean;
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

function TClickSpy.JobStrip(ACol: Integer): Boolean;
begin
  Last := 'jobstrip';
  StripCol := ACol;
  Result := StripHit;
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
  AHost.JobStripClick := ASpy.JobStrip;
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
  Mode: TPanelColumnMode;
  I, Col, Row: Integer;
begin
  Outer := TRectI.Make(0, 2, 58, 17);
  ListB := PanelListBounds(Outer);
  Assert.IsTrue((ListB.Left = 1) and (ListB.Top = 4) and (ListB.Right = 56) and
    (ListB.Bottom = 14), 'list inset');

  LeftB := TRectI.Make(0, 2, 39, 20);
  RightB := TRectI.Make(40, 2, 79, 20);
  Assert.IsTrue(HitPanelSide(True, LeftB, True, RightB, 10, 5, Side) and (Side = psLeft),
    'left panel hit');
  Assert.IsTrue(HitPanelSide(True, LeftB, True, RightB, 50, 5, Side) and (Side = psRight),
    'right panel hit');
  Assert.IsTrue(not HitPanelSide(False, LeftB, True, RightB, 10, 5, Side),
    'hidden left misses');
  Assert.IsTrue(not HitPanelSide(True, LeftB, True, RightB, 10, 0, Side),
    'above panels misses');

  Assert.IsTrue(ClassifyPanelClickZone(2, Outer, pvkFiles) = pczTabs, 'top row tabs');
  Assert.IsTrue(ClassifyPanelClickZone(17, Outer, pvkFiles) = pczDrives, 'bottom drives');
  Assert.IsTrue(ClassifyPanelClickZone(5, Outer, pvkInfo) = pczInfo, 'info swallows body');
  Assert.IsTrue(ClassifyPanelClickZone(3, Outer, pvkFiles) = pczHeaders, 'header row');
  Assert.IsTrue(ClassifyPanelClickZone(8, Outer, pvkFiles) = pczBody, 'list body');

  ListB := TRectI.Make(1, 4, 20, 13);
  Assert.IsTrue(HitPanelListIndex(ListB, pcmFull, 0, 5, 6, 10, Idx) and (Idx = 2),
    'full list row');
  Assert.IsTrue(not HitPanelListIndex(ListB, pcmFull, 0, 0, 6, 10, Idx),
    'left frame is not a row');
  Assert.IsTrue(not HitPanelListIndex(ListB, pcmFull, 0, 5, 6, 0, Idx),
    'empty list misses');

  // PanelListIndexCell (anchor of the Shift+F10 context menu) is the inverse
  // of HitPanelListIndex, in single-column and Brief layouts alike.
  for Mode in [pcmFull, pcmBrief] do
    for I := 0 to 40 do
      if PanelListIndexCell(ListB, Mode, 3, I, Col, Row) then
        Assert.IsTrue(HitPanelListIndex(ListB, Mode, 3, Col, Row, 100, Idx) and (Idx = I),
          Format('mode %d item %d: cell (%d,%d) hits %d', [Ord(Mode), I, Col, Row, Idx]));
  Assert.IsTrue(PanelListIndexCell(ListB, pcmFull, 3, 5, Col, Row) and
    (Col = ListB.Left) and (Row = ListB.Top + 2), 'full: row below the scroll offset');
  Assert.IsTrue(not PanelListIndexCell(ListB, pcmFull, 3, 2, Col, Row), 'scrolled off above');
  Assert.IsTrue(not PanelListIndexCell(ListB, pcmFull, 3, 3 + ListB.Height, Col, Row),
    'scrolled off below');
end;

procedure TestOverlays;
var
  Spy: TClickSpy;
  Host: TDualPanelClickHost;
  Snap: TClickOverlaySnapshot;
  Owned, Handled: Boolean;
begin
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
    Assert.IsTrue(Owned and Handled and (Spy.Last = 'topmenu+inv'), 'top menu consumes row 0');

    Spy.Last := '';
    Spy.MenuHit := True;
    Snap.WorkspaceKind := wkDocument;
    Owned := DispatchClickOverlays(Host, Snap, 3, 0, [], False, Handled);
    Assert.IsTrue(Owned and Handled and (Spy.Last = 'topmenu+inv'),
      'document row 0 is top menu');

    Spy.Last := '';
    Snap.WorkspaceKind := wkTerminal;
    Owned := DispatchClickOverlays(Host, Snap, 3, 0, [], False, Handled);
    Assert.IsTrue(Owned and Handled and (Spy.Last = 'topmenu+inv'),
      'terminal row 0 is top menu');

    Spy.Last := '';
    Spy.MenuHit := True;
    Snap.TopMenuAssigned := True;
    Snap.TopMenuActive := True;
    Snap.WorkspaceKind := wkDocument;
    Owned := DispatchClickOverlays(Host, Snap, 4, 5, [], False, Handled);
    Assert.IsTrue(Owned and Handled and (Spy.Last = 'topmenu+inv'),
      'open submenu wins over document body');

    Spy.Last := '';
    Snap.WorkspaceKind := wkTerminal;
    Owned := DispatchClickOverlays(Host, Snap, 4, 5, [], False, Handled);
    Assert.IsTrue(Owned and Handled and (Spy.Last = 'topmenu+inv'),
      'open submenu wins over terminal body');
    Snap.TopMenuActive := False;

    Spy.Last := '';
    Spy.MenuHit := False;
    Snap.WorkspaceKind := wkPanels;
    Owned := DispatchClickOverlays(Host, Snap, 3, 0, [], False, Handled);
    Assert.IsTrue(not Owned, 'top menu miss falls through');

    Snap.TopMenuAssigned := False;
    Snap.WorkspaceKind := wkDocument;
    Owned := DispatchClickOverlays(Host, Snap, 4, 5, [], False, Handled);
    Assert.IsTrue(Owned and (Spy.Last = 'doc:4:3'), 'document body is row-2');

    Snap.WorkspaceKind := wkTerminal;
    Owned := DispatchClickOverlays(Host, Snap, 1, 1, [], False, Handled);
    Assert.IsTrue(Owned and (Spy.Last = 'wstab'), 'terminal row 1 is workspace tabs');

    Snap.WorkspaceKind := wkPanels;
    Owned := DispatchClickOverlays(Host, Snap, 2, 22, [], False, Handled);
    Assert.IsTrue(Owned and (Spy.Last = 'fbar'), 'F-bar is height-2');

    Snap.DialogVisible := True;
    Snap.DialogKind := hdkColorPicker;
    Owned := DispatchClickOverlays(Host, Snap, 2, 10, [], False, Handled);
    Assert.IsTrue(Owned and (Spy.Last = 'dialog+hex'), 'color picker syncs hex');

    Snap.DialogVisible := False;
    Snap.SearchPhase := spRunning;
    Spy.SearchBounds := TRectI.Make(10, 10, 40, 20);
    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 0, 0, [], False, Handled);
    Assert.IsTrue(Owned and (Pos('+sclose', Spy.Last) > 0), 'outside search closes it');

    Snap.SearchPhase := spDialog;
    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 0, 0, [], False, Handled);
    Assert.IsTrue(Owned and (Spy.Last = ''), 'search dialog click is swallowed');

    Snap.SearchPhase := spNone;
    Snap.JobsPhase := pjpRunning;
    Snap.JobsKind := pjkCopy;
    Snap.JobsShowsOverlay := True;
    Spy.JobBounds := TRectI.Make(10, 10, 40, 22);
    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 38, 10, [], False, Handled);
    Assert.IsTrue(Owned and (Pos('+cancel', Spy.Last) > 0), 'running job close cancels');

    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 12, 21, [], False, Handled);
    Assert.IsTrue(Owned and (Pos('+bg', Spy.Last) > 0), 'running job Background button');

    Snap.JobsShowsOverlay := False;
    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 2, 12, [], False, Handled);
    Assert.IsTrue((not Owned) or (Pos('+cancel', Spy.Last) = 0),
      'background running does not eat panel clicks');

    Snap.JobsPhase := pjpOverwriteAsk;
    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 0, 0, [], False, Handled);
    Assert.IsTrue(Owned and (Pos('+ow', Spy.Last) > 0), 'overwrite outside cancels ask');

    Snap.JobsPhase := pjpConfirm;
    Snap.DialogVisible := True;
    Snap.DialogKind := hdkJobConfirm;
    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 0, 0, [], False, Handled);
    Assert.IsTrue(Owned and (Spy.Last = 'dialog'),
      'open dialog wins over job confirm');

    Snap.StubVisible := True;
    Spy.Last := '';
    Owned := DispatchClickOverlays(Host, Snap, 0, 0, [], False, Handled);
    Assert.IsTrue(Owned and (Pos('stub', Spy.Last) > 0),
      'stub sits above dialog');
    Snap.StubVisible := False;

    Snap.DialogVisible := False;
    Snap.JobsPhase := pjpNone;
    Owned := DispatchClickOverlays(Host, Snap, 2, 21, [], False, Handled);
    Assert.IsTrue(Owned and Spy.Focused, 'cmdline row focuses');

    Spy.TabHit := False;
    Owned := DispatchClickOverlays(Host, Snap, 70, 1, [], True, Handled);
    Assert.IsTrue(Owned and Handled and (Pos('+newws', Spy.Last) > 0),
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
  Spy := TClickSpy.Create;
  try
    BindSpy(Host, Spy);
    Bounds := TRectI.Make(0, 2, 40, 20);

    Spy.TabHit := True;
    Assert.IsTrue(DispatchPanelChromeClick(Host, psLeft, Bounds, pvkFiles, pcmFull,
      5, 2, False) and (Spy.Last = 'ptab'), 'tab hit');

    Spy.TabHit := False;
    Assert.IsTrue(DispatchPanelChromeClick(Host, psRight, Bounds, pvkFiles, pcmFull,
      5, 2, True) and (Spy.Last = 'newptab') and (Spy.Side = psRight),
      'empty tab row double-click');

    Assert.IsTrue(DispatchPanelChromeClick(Host, psLeft, Bounds, pvkInfo, pcmFull,
      8, 8, False) and (Spy.Last = 'activate+inv'), 'info activates only');

    Assert.IsTrue(not DispatchPanelChromeClick(Host, psLeft, Bounds, pvkFiles, pcmFull,
      8, 8, False), 'body is not chrome');
  finally
    Spy.Free;
  end;
end;

procedure TestJobStripClick;
var
  Spy: TClickSpy;
  Host: TDualPanelClickHost;
  Snap: TClickOverlaySnapshot;
  Handled: Boolean;
begin
  Spy := TClickSpy.Create;
  try
    BindSpy(Host, Spy);
    Snap := Default(TClickOverlaySnapshot);
    Snap.WorkspaceKind := wkPanels;
    Snap.AreaHeight := 24;
    Snap.AreaWidth := 80;

    Spy.StripHit := True;
    Spy.TabHit := True;
    Handled := False;
    Assert.IsTrue(DispatchClickOverlays(Host, Snap, 75, 1, [], False, Handled),
      'tab row click reaches the strip');
    Assert.IsTrue(Handled and (Spy.Last = 'jobstrip') and (Spy.StripCol = 75),
      'a hit on the strip does not select a tab');

    Spy.StripHit := False;
    Handled := False;
    DispatchClickOverlays(Host, Snap, 3, 1, [], False, Handled);
    Assert.IsTrue(Handled and (Spy.Last = 'wstab'),
      'a miss on the strip falls through to the tabs');

    Spy.Last := '';
    Handled := False;
    DispatchClickOverlays(Host, Snap, 75, 2, [], False, Handled);
    Assert.IsTrue(Spy.Last <> 'jobstrip', 'only the tab row is the strip');
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
  Assert.IsTrue(not UpdateListClickPair(False, True, Dbl, 3, 4, LastCol, LastRow,
    LastTick, 100, 50), 'miss does not activate');
  Assert.IsTrue(LastCol = -1, 'miss resets last col');

  Dbl := False;
  Assert.IsTrue(not UpdateListClickPair(True, False, Dbl, 3, 4, LastCol, LastRow,
    LastTick, 100, 50), 'right-click does not activate');
  Assert.IsTrue(LastCol = -1, 'right-click resets pair');

  Dbl := False;
  Assert.IsTrue(not UpdateListClickPair(True, True, Dbl, 3, 4, LastCol, LastRow,
    LastTick, 100, 50), 'first left click arms');
  Assert.IsTrue((LastCol = 3) and (LastRow = 4) and (LastTick = 100), 'first click stored');

  Dbl := False;
  Assert.IsTrue(UpdateListClickPair(True, True, Dbl, 3, 4, LastCol, LastRow,
    LastTick, 120, 50), 'second click in time activates');
  Assert.IsTrue(Dbl, 'paired click becomes double');
  Assert.IsTrue(LastTick = 0, 'activate clears tick');

  Dbl := True;
  LastTick := 200;
  Assert.IsTrue(UpdateListClickPair(True, True, Dbl, 5, 6, LastCol, LastRow,
    LastTick, 200, 50), 'ssDouble activates immediately');
end;

{ TTestDualPanelClick }

procedure TTestDualPanelClick.TestGeometry;
begin
  TestDualPanelClick.TestGeometry;
end;

procedure TTestDualPanelClick.TestOverlays;
begin
  TestDualPanelClick.TestOverlays;
end;

procedure TTestDualPanelClick.TestChromeClick;
begin
  TestDualPanelClick.TestChromeClick;
end;

procedure TTestDualPanelClick.TestJobStripClick;
begin
  TestDualPanelClick.TestJobStripClick;
end;

procedure TTestDualPanelClick.TestListClickPair;
begin
  TestDualPanelClick.TestListClickPair;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelClick);

end.
