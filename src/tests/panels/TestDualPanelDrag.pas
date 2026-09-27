unit TestDualPanelDrag;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelDrag = class
  public
    [Test] procedure TestTabDragPredicates;
    [Test] procedure TestStepTabDrag;
    [Test] procedure TestFileDragAndHits;
    [Test] procedure TestMouseDownClassify;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uThemeTypes,
  uDualPanelTypes,
  uVfsTypes,
  uPanelColumns,
  uKeymap,
  uDualPanelUiTypes,
  uDualPanelInput,
  uDualPanelClick,
  uDualPanelDrag;

type
  TDragSpy = class
  public
    Last: string;
    WsHit: Boolean;
    WsIdx: Integer;
    PanelHit: Boolean;
    PanelIdx: Integer;
    function HitWorkspace(ACol: Integer; out AIndex: Integer;
      out AIsClose: Boolean): Boolean;
    function HitPanel(ASide: TPanelSide; const ABounds: TRectI;
      ACol: Integer; out AIndex: Integer; out AIsClose: Boolean): Boolean;
    procedure NotifyChanged;
    procedure CancelFileDrag;
  end;

function TDragSpy.HitWorkspace(ACol: Integer; out AIndex: Integer;
  out AIsClose: Boolean): Boolean;
begin
  Last := Last + 'ws,';
  AIsClose := False;
  AIndex := WsIdx;
  Result := WsHit;
end;

function TDragSpy.HitPanel(ASide: TPanelSide; const ABounds: TRectI;
  ACol: Integer; out AIndex: Integer; out AIsClose: Boolean): Boolean;
begin
  Last := Last + 'panel,';
  AIsClose := False;
  AIndex := PanelIdx;
  Result := PanelHit;
end;

procedure TDragSpy.NotifyChanged;
begin
  Last := Last + 'notify,';
end;

procedure TDragSpy.CancelFileDrag;
begin
  Last := Last + 'cancelfile,';
end;

procedure TestTabDragPredicates;
var
  Kind, FromIdx, Hover: Integer;
  Armed, Active: Boolean;
  Side: TPanelSide;
begin
  Assert.IsTrue(not CanArmTabDrag(cTabDragNone, 0, 2), 'none kind');
  Assert.IsTrue(not CanArmTabDrag(cTabDragWorkspace, -1, 2), 'negative from');
  Assert.IsTrue(not CanArmTabDrag(cTabDragWorkspace, 0, 1), 'single workspace');
  Assert.IsTrue(CanArmTabDrag(cTabDragWorkspace, 0, 2), 'two workspaces');
  Assert.IsTrue(CanArmTabDrag(cTabDragPanelLeft, 0, 1), 'panel ignores workspace count');

  Assert.IsTrue(not TabDragPastThreshold(5, 3, 5, 3), 'no move');
  Assert.IsTrue(not TabDragPastThreshold(6, 3, 5, 3), 'one col stays armed');
  Assert.IsTrue(TabDragPastThreshold(7, 3, 5, 3), 'two cols starts drag');
  Assert.IsTrue(TabDragPastThreshold(5, 4, 5, 3), 'one row starts drag');

  Kind := cTabDragWorkspace;
  FromIdx := 2;
  Hover := 3;
  Armed := True;
  Active := False;
  Assert.IsTrue(ResetTabDrag(Kind, FromIdx, Hover, Armed, Active), 'reset was busy');
  Assert.IsTrue((Kind = cTabDragNone) and (FromIdx = -1) and (Hover = -1) and
    (not Armed) and (not Active), 'reset clears fields');
  Assert.IsTrue(not ResetTabDrag(Kind, FromIdx, Hover, Armed, Active), 'idle reset');

  Assert.IsTrue(TabDragBusy(True, False) and TabDragBusy(False, True), 'busy flags');
  Assert.IsTrue(TabDragPanelSide(cTabDragPanelLeft, Side) and (Side = psLeft), 'left kind');
  Assert.IsTrue(TabDragPanelSide(cTabDragPanelRight, Side) and (Side = psRight), 'right kind');
  Assert.IsTrue(not TabDragPanelSide(cTabDragWorkspace, Side), 'workspace has no panel side');

  Assert.IsTrue(ClassifyTabDragCommit(False, cTabDragWorkspace) = tdcCancel, 'armed-only cancels');
  Assert.IsTrue(ClassifyTabDragCommit(True, cTabDragWorkspace) = tdcWorkspace, 'workspace commit');
  Assert.IsTrue(ClassifyTabDragCommit(True, cTabDragPanelRight) = tdcPanel, 'panel commit');
end;

procedure TestStepTabDrag;
var
  Spy: TDragSpy;
  Host: TDualPanelDragHost;
  Armed, Active: Boolean;
  Hover: Integer;
  LeftB, RightB: TRectI;
begin
  Spy := TDragSpy.Create;
  try
    Host := Default(TDualPanelDragHost);
    Host.HitWorkspaceTab := Spy.HitWorkspace;
    Host.HitPanelTab := Spy.HitPanel;
    Host.NotifyChanged := Spy.NotifyChanged;
    Host.CancelFileDrag := Spy.CancelFileDrag;
    LeftB := TRectI.Make(0, 2, 39, 20);
    RightB := TRectI.Make(40, 2, 79, 20);

    Armed := False;
    Active := False;
    Hover := 0;
    Assert.IsTrue(not StepTabDrag(Host, Armed, Active, cTabDragWorkspace, Hover,
      4, 1, 10, 1, LeftB, RightB), 'idle does nothing');

    Armed := True;
    Active := False;
    Hover := 0;
    Assert.IsTrue(StepTabDrag(Host, Armed, Active, cTabDragWorkspace, Hover,
      4, 1, 5, 1, LeftB, RightB) and Armed and (not Active),
      'within threshold stays armed');
    Assert.IsTrue(Spy.Last = '', 'no hover work under threshold');

    Assert.IsTrue(StepTabDrag(Host, Armed, Active, cTabDragWorkspace, Hover,
      4, 1, 8, 1, LeftB, RightB) and Active and (not Armed),
      'past threshold activates');
    Assert.IsTrue(Pos('cancelfile', Spy.Last) > 0, 'activate cancels file drag');

    Spy.Last := '';
    Spy.WsHit := True;
    Spy.WsIdx := 2;
    Hover := 0;
    Armed := False;
    Active := True;
    Assert.IsTrue(StepTabDrag(Host, Armed, Active, cTabDragWorkspace, Hover,
      4, 1, 10, 1, LeftB, RightB) and (Hover = 2), 'workspace hover');
    Assert.IsTrue(Pos('notify', Spy.Last) > 0, 'hover change notifies');

    Spy.Last := '';
    Spy.PanelHit := True;
    Spy.PanelIdx := 1;
    Hover := 0;
    Assert.IsTrue(StepTabDrag(Host, Armed, Active, cTabDragPanelLeft, Hover,
      4, 2, 8, 2, LeftB, RightB) and (Hover = 1) and
      (Pos('panel', Spy.Last) > 0), 'left panel tab row hover');
  finally
    Spy.Free;
  end;
end;

procedure TestFileDragAndHits;
var
  Side: TPanelSide;
  Bounds: TRectI;
  Dest: string;
  Highlight: Integer;
  Rows: TPanelRows;
  Row: TPanelRow;
  PanelBounds: TRectI;
begin
  Assert.IsTrue(not CanArmFileDragSources(False, False, False), 'not panels');
  Assert.IsTrue(not CanArmFileDragSources(True, True, False), 'dialog blocks');
  Assert.IsTrue(not CanArmFileDragSources(True, False, True), 'job blocks');
  Assert.IsTrue(CanArmFileDragSources(True, False, False), 'panels idle');

  Assert.IsTrue(not FileDragPastThreshold(3, 3, 3, 3), 'file no move');
  Assert.IsTrue(FileDragPastThreshold(4, 3, 3, 3), 'file one cell');
  Assert.IsTrue(not ShouldStartFileDrag(True, True, 10, 10, 0, 0), 'tab drag wins');
  Assert.IsTrue(not ShouldStartFileDrag(False, False, 10, 10, 0, 0), 'not armed');
  Assert.IsTrue(ShouldStartFileDrag(False, True, 10, 10, 0, 0), 'armed and moved');

  Assert.IsTrue(not CanHitTestPanelDrag(wkDocument, False, False), 'document no drop');
  Assert.IsTrue(CanHitTestPanelDrag(wkPanels, False, False), 'panels drop');
  Assert.IsTrue(not CanHitTestListItem(wkPanels, False, False, True, False, False),
    'menu overlay blocks list path');
  Assert.IsTrue(CanHitTestListItem(wkPanels, False, False, False, False, False),
    'idle list path');

  Bounds := TRectI.Make(0, 2, 39, 20);
  Assert.IsTrue(ResolvePanelHitBounds(True, Bounds, pvkFiles, True,
    TRectI.Make(40, 2, 79, 20), pvkFiles, 10, 8, Side, Bounds) and
    (Side = psLeft), 'files panel hit');
  Assert.IsTrue(not ResolvePanelHitBounds(True, TRectI.Make(0, 2, 39, 20), pvkInfo,
    True, TRectI.Make(40, 2, 79, 20), pvkFiles, 10, 8, Side, Bounds),
    'info panel is not a drop target');

  Assert.IsTrue(IsBlockedDropDestURI('file:///C:/zip!/inner'), 'archive dest blocked');
  Assert.IsTrue(IsBlockedDropDestURI('find://q'), 'find dest blocked');
  Assert.IsTrue(IsBlockedDropDestURI('sys://folders'), 'sys dest blocked');
  Assert.IsTrue(not IsBlockedDropDestURI('file:///C:/docs'), 'plain dest ok');

  Row := Default(TPanelRow);
  Row.IsDirectory := True;
  Row.URI := 'file:///C:/docs';
  Assert.IsTrue(DropFolderRowURI(Row, Dest) and (Dest = Row.URI), 'dir row');
  Row.IsParent := True;
  Assert.IsTrue(not DropFolderRowURI(Row, Dest), 'parent is not a drop folder');
  Row := Default(TPanelRow);
  Row.IsDirectory := True;
  Row.URI := 'file:///C:/a.zip!/x';
  Assert.IsTrue(not DropFolderRowURI(Row, Dest), 'archive folder row skipped');

  SetLength(Rows, 3);
  Rows[0] := Default(TPanelRow);
  Rows[0].Text := 'a.txt';
  Rows[0].URI := 'file:///C:/a.txt';
  Rows[1] := Default(TPanelRow);
  Rows[1].IsDirectory := True;
  Rows[1].URI := 'file:///C:/docs';
  Rows[2] := Default(TPanelRow);
  PanelBounds := TRectI.Make(0, 2, 40, 20);
    Assert.IsTrue(ResolveDropDest('file:///C:/root', PanelBounds, pcmFull, 0, 5, 3,
    Rows, Dest, Highlight) and (Dest = 'file:///C:/root') and (Highlight = -1),
    'header miss keeps tab URI');
  Assert.IsTrue(ResolveDropDest('file:///C:/root', PanelBounds, pcmFull, 0, 5, 4,
    Rows, Dest, Highlight) and (Dest = 'file:///C:/root') and (Highlight = -1),
    'file row keeps tab URI');
  Assert.IsTrue(ResolveDropDest('file:///C:/root', PanelBounds, pcmFull, 0, 5, 5,
    Rows, Dest, Highlight) and (Dest = 'file:///C:/docs') and (Highlight = 1),
    'folder row overrides dest');
  Assert.IsTrue(not ResolveDropDest('find://q', PanelBounds, pcmFull, 0, 5, 5,
    Rows, Dest, Highlight), 'blocked tab URI rejects drop');

  Row := Default(TPanelRow);
  Row.URI := 'file:///C:/a.txt';
  Row.TargetURI := 'file:///C:/b.txt';
  Assert.IsTrue(ListItemSourceUri(Row) = 'file:///C:/b.txt', 'target URI wins');
  Row.URI := 'file:///C:/a.zip!/x';
  Row.TargetURI := '';
  Assert.IsTrue(ListItemLocalPath(Row) = '', 'archive has no local path');
end;

procedure TestMouseDownClassify;
begin
  Assert.IsTrue(ClassifyMouseDown(0, wkPanels) = mdtTopMenu, 'row 0 is top menu');
  Assert.IsTrue(ClassifyMouseDown(1, wkTerminal) = mdtWorkspaceTab, 'terminal tabs');
  Assert.IsTrue(ClassifyMouseDown(5, wkTerminal) = mdtEmbedded, 'terminal body');
  Assert.IsTrue(ClassifyMouseDown(1, wkDocument) = mdtWorkspaceTab, 'document tabs');
  Assert.IsTrue(ClassifyMouseDown(5, wkDocument) = mdtEmbedded, 'document body');
  Assert.IsTrue(ClassifyMouseDown(5, wkPanels) = mdtNone, 'panels fall through');
end;

{ TTestDualPanelDrag }

procedure TTestDualPanelDrag.TestTabDragPredicates;
begin
  TestDualPanelDrag.TestTabDragPredicates;
end;

procedure TTestDualPanelDrag.TestStepTabDrag;
begin
  TestDualPanelDrag.TestStepTabDrag;
end;

procedure TTestDualPanelDrag.TestFileDragAndHits;
begin
  TestDualPanelDrag.TestFileDragAndHits;
end;

procedure TTestDualPanelDrag.TestMouseDownClassify;
begin
  TestDualPanelDrag.TestMouseDownClassify;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelDrag);

end.
