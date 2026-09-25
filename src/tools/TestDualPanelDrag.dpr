program TestDualPanelDrag;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes,
  uThemeTypes in '..\Core\uThemeTypes.pas',
  uDualPanelTypes in '..\Core\uDualPanelTypes.pas',
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uPanelColumns in '..\Core\uPanelColumns.pas',
  uKeymap in '..\Core\uKeymap.pas',
  uDualPanelUiTypes in '..\Core\uDualPanelUiTypes.pas',
  uDualPanelInput in '..\Core\uDualPanelInput.pas',
  uDualPanelClick in '..\Core\uDualPanelClick.pas',
  uDualPanelDrag in '..\Core\uDualPanelDrag.pas';

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

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
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
  Writeln('Tab drag predicates');
  Expect(not CanArmTabDrag(cTabDragNone, 0, 2), 'none kind');
  Expect(not CanArmTabDrag(cTabDragWorkspace, -1, 2), 'negative from');
  Expect(not CanArmTabDrag(cTabDragWorkspace, 0, 1), 'single workspace');
  Expect(CanArmTabDrag(cTabDragWorkspace, 0, 2), 'two workspaces');
  Expect(CanArmTabDrag(cTabDragPanelLeft, 0, 1), 'panel ignores workspace count');

  Expect(not TabDragPastThreshold(5, 3, 5, 3), 'no move');
  Expect(not TabDragPastThreshold(6, 3, 5, 3), 'one col stays armed');
  Expect(TabDragPastThreshold(7, 3, 5, 3), 'two cols starts drag');
  Expect(TabDragPastThreshold(5, 4, 5, 3), 'one row starts drag');

  Kind := cTabDragWorkspace;
  FromIdx := 2;
  Hover := 3;
  Armed := True;
  Active := False;
  Expect(ResetTabDrag(Kind, FromIdx, Hover, Armed, Active), 'reset was busy');
  Expect((Kind = cTabDragNone) and (FromIdx = -1) and (Hover = -1) and
    (not Armed) and (not Active), 'reset clears fields');
  Expect(not ResetTabDrag(Kind, FromIdx, Hover, Armed, Active), 'idle reset');

  Expect(TabDragBusy(True, False) and TabDragBusy(False, True), 'busy flags');
  Expect(TabDragPanelSide(cTabDragPanelLeft, Side) and (Side = psLeft), 'left kind');
  Expect(TabDragPanelSide(cTabDragPanelRight, Side) and (Side = psRight), 'right kind');
  Expect(not TabDragPanelSide(cTabDragWorkspace, Side), 'workspace has no panel side');

  Expect(ClassifyTabDragCommit(False, cTabDragWorkspace) = tdcCancel, 'armed-only cancels');
  Expect(ClassifyTabDragCommit(True, cTabDragWorkspace) = tdcWorkspace, 'workspace commit');
  Expect(ClassifyTabDragCommit(True, cTabDragPanelRight) = tdcPanel, 'panel commit');
end;

procedure TestStepTabDrag;
var
  Spy: TDragSpy;
  Host: TDualPanelDragHost;
  Armed, Active: Boolean;
  Hover: Integer;
  LeftB, RightB: TRectI;
begin
  Writeln('StepTabDrag');
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
    Expect(not StepTabDrag(Host, Armed, Active, cTabDragWorkspace, Hover,
      4, 1, 10, 1, LeftB, RightB), 'idle does nothing');

    Armed := True;
    Active := False;
    Hover := 0;
    Expect(StepTabDrag(Host, Armed, Active, cTabDragWorkspace, Hover,
      4, 1, 5, 1, LeftB, RightB) and Armed and (not Active),
      'within threshold stays armed');
    Expect(Spy.Last = '', 'no hover work under threshold');

    Expect(StepTabDrag(Host, Armed, Active, cTabDragWorkspace, Hover,
      4, 1, 8, 1, LeftB, RightB) and Active and (not Armed),
      'past threshold activates');
    Expect(Pos('cancelfile', Spy.Last) > 0, 'activate cancels file drag');

    Spy.Last := '';
    Spy.WsHit := True;
    Spy.WsIdx := 2;
    Hover := 0;
    Armed := False;
    Active := True;
    Expect(StepTabDrag(Host, Armed, Active, cTabDragWorkspace, Hover,
      4, 1, 10, 1, LeftB, RightB) and (Hover = 2), 'workspace hover');
    Expect(Pos('notify', Spy.Last) > 0, 'hover change notifies');

    Spy.Last := '';
    Spy.PanelHit := True;
    Spy.PanelIdx := 1;
    Hover := 0;
    Expect(StepTabDrag(Host, Armed, Active, cTabDragPanelLeft, Hover,
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
  Writeln('File drag / drop hits');
  Expect(not CanArmFileDragSources(False, False, False), 'not panels');
  Expect(not CanArmFileDragSources(True, True, False), 'dialog blocks');
  Expect(not CanArmFileDragSources(True, False, True), 'job blocks');
  Expect(CanArmFileDragSources(True, False, False), 'panels idle');

  Expect(not FileDragPastThreshold(3, 3, 3, 3), 'file no move');
  Expect(FileDragPastThreshold(4, 3, 3, 3), 'file one cell');
  Expect(not ShouldStartFileDrag(True, True, 10, 10, 0, 0), 'tab drag wins');
  Expect(not ShouldStartFileDrag(False, False, 10, 10, 0, 0), 'not armed');
  Expect(ShouldStartFileDrag(False, True, 10, 10, 0, 0), 'armed and moved');

  Expect(not CanHitTestPanelDrag(wkDocument, False, False), 'document no drop');
  Expect(CanHitTestPanelDrag(wkPanels, False, False), 'panels drop');
  Expect(not CanHitTestListItem(wkPanels, False, False, True, False, False),
    'menu overlay blocks list path');
  Expect(CanHitTestListItem(wkPanels, False, False, False, False, False),
    'idle list path');

  Bounds := TRectI.Make(0, 2, 39, 20);
  Expect(ResolvePanelHitBounds(True, Bounds, pvkFiles, True,
    TRectI.Make(40, 2, 79, 20), pvkFiles, 10, 8, Side, Bounds) and
    (Side = psLeft), 'files panel hit');
  Expect(not ResolvePanelHitBounds(True, TRectI.Make(0, 2, 39, 20), pvkInfo,
    True, TRectI.Make(40, 2, 79, 20), pvkFiles, 10, 8, Side, Bounds),
    'info panel is not a drop target');

  Expect(IsBlockedDropDestURI('file:///C:/zip!/inner'), 'archive dest blocked');
  Expect(IsBlockedDropDestURI('find://q'), 'find dest blocked');
  Expect(IsBlockedDropDestURI('sys://folders'), 'sys dest blocked');
  Expect(not IsBlockedDropDestURI('file:///C:/docs'), 'plain dest ok');

  Row := Default(TPanelRow);
  Row.IsDirectory := True;
  Row.URI := 'file:///C:/docs';
  Expect(DropFolderRowURI(Row, Dest) and (Dest = Row.URI), 'dir row');
  Row.IsParent := True;
  Expect(not DropFolderRowURI(Row, Dest), 'parent is not a drop folder');
  Row := Default(TPanelRow);
  Row.IsDirectory := True;
  Row.URI := 'file:///C:/a.zip!/x';
  Expect(not DropFolderRowURI(Row, Dest), 'archive folder row skipped');

  SetLength(Rows, 3);
  Rows[0] := Default(TPanelRow);
  Rows[0].Text := 'a.txt';
  Rows[0].URI := 'file:///C:/a.txt';
  Rows[1] := Default(TPanelRow);
  Rows[1].IsDirectory := True;
  Rows[1].URI := 'file:///C:/docs';
  Rows[2] := Default(TPanelRow);
  PanelBounds := TRectI.Make(0, 2, 40, 20);
    Expect(ResolveDropDest('file:///C:/root', PanelBounds, pcmFull, 0, 5, 3,
    Rows, Dest, Highlight) and (Dest = 'file:///C:/root') and (Highlight = -1),
    'header miss keeps tab URI');
  Expect(ResolveDropDest('file:///C:/root', PanelBounds, pcmFull, 0, 5, 4,
    Rows, Dest, Highlight) and (Dest = 'file:///C:/root') and (Highlight = -1),
    'file row keeps tab URI');
  Expect(ResolveDropDest('file:///C:/root', PanelBounds, pcmFull, 0, 5, 5,
    Rows, Dest, Highlight) and (Dest = 'file:///C:/docs') and (Highlight = 1),
    'folder row overrides dest');
  Expect(not ResolveDropDest('find://q', PanelBounds, pcmFull, 0, 5, 5,
    Rows, Dest, Highlight), 'blocked tab URI rejects drop');

  Row := Default(TPanelRow);
  Row.URI := 'file:///C:/a.txt';
  Row.TargetURI := 'file:///C:/b.txt';
  Expect(ListItemSourceUri(Row) = 'file:///C:/b.txt', 'target URI wins');
  Row.URI := 'file:///C:/a.zip!/x';
  Row.TargetURI := '';
  Expect(ListItemLocalPath(Row) = '', 'archive has no local path');
end;

procedure TestMouseDownClassify;
begin
  Writeln('MouseDown classify');
  Expect(ClassifyMouseDown(0, wkPanels) = mdtTopMenu, 'row 0 is top menu');
  Expect(ClassifyMouseDown(1, wkTerminal) = mdtWorkspaceTab, 'terminal tabs');
  Expect(ClassifyMouseDown(5, wkTerminal) = mdtEmbedded, 'terminal body');
  Expect(ClassifyMouseDown(1, wkDocument) = mdtWorkspaceTab, 'document tabs');
  Expect(ClassifyMouseDown(5, wkDocument) = mdtEmbedded, 'document body');
  Expect(ClassifyMouseDown(5, wkPanels) = mdtNone, 'panels fall through');
end;

begin
  try
    TestTabDragPredicates;
    TestStepTabDrag;
    TestFileDragAndHits;
    TestMouseDownClassify;
    Writeln('All DualPanelDrag tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
