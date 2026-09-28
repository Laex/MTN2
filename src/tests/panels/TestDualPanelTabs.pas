unit TestDualPanelTabs;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelTabs = class
  public
    [Test] procedure TestTabManager;
    [Test] procedure TestClonePanelAndWorkspaceTitle;
    [Test] procedure TestWorkspaceLifecycle;
    [Test] procedure TestEmbeddedWorkspace;
    [Test] procedure TestSessionExportFilter;
    [Test] procedure TestResolvePanelDriveUri;
  end;

implementation

uses
  System.SysUtils,
  uDualPanelTypes,
  uDualPanelTabs;

type
  TCloseSpy = class
  public
    Last: string;
    procedure CloseDocument(AIndex: Integer);
    procedure CloseTerminal(AIndex: Integer);
    procedure RemoveWorkspace(AIndex: Integer);
  end;

procedure TestTabManager;
var
  LTabs: TArray<TTab>;
  LNextId: Cardinal;
  LActiveIndex: Integer;
  LNewIndex: Integer;
begin
  LNextId := 0;
  SetLength(LTabs, 0);

  // Add tab
  LNewIndex := TDualPanelTabManager.AddTab(LTabs, LNextId, 'Home', 'file:///C:/');
  Assert.IsTrue(Length(LTabs) = 1, 'Tabs length should be 1');
  Assert.IsTrue(LTabs[0].Title = 'Home', 'Tab title should be Home');

  // Add second tab
  LNewIndex := TDualPanelTabManager.AddTab(LTabs, LNextId, 'Docs', 'file:///C:/Docs');
  Assert.IsTrue(Length(LTabs) = 2, 'Tabs length should be 2');

  // Test Navigation & History
  TDualPanelTabManager.NavigateTab(LTabs[1], 'file:///C:/Docs/Sub');
  Assert.IsTrue(TDualPanelTabManager.CanGoBack(LTabs[1]), 'Should be able to go back');
  TDualPanelTabManager.GoBack(LTabs[1]);
  Assert.IsTrue(LTabs[1].CurrentURI = 'file:///C:/Docs', 'Should return to previous URI');

  // Close tab
  LActiveIndex := 1;
  Assert.IsTrue(TDualPanelTabManager.CloseTab(LTabs, LActiveIndex, 1), 'Should close second tab');
  Assert.IsTrue(Length(LTabs) = 1, 'Tabs length should be 1 after closing');
  Assert.IsTrue(not TDualPanelTabManager.CloseTab(LTabs, LActiveIndex, 0), 'Should not close the last tab');

  Writeln('OK: TestTabManager passed');
end;

procedure TestClonePanelAndWorkspaceTitle;
var
  Src, Dst: TPanelState;
  NextId: Cardinal;
  State: TDualPanelState;
begin
  NextId := 10;
  Src.ActiveTabIndex := 0;
  Src.ColumnMode := pcmBrief;
  Src.SortColumn := pscSize;
  Src.SortDescending := True;
  Src.ViewKind := pvkInfo;
  ClearPanelDriveDirs(Src.DriveDirs);
  Src.DriveDirs['C'] := 'C:\Work';
  SetLength(Src.Tabs, 1);
  Src.Tabs[0] := MakeTab(1, 'Work', 'file:///C:/Work');
  SetLength(Src.Tabs[0].SelectedURIs, 1);
  Src.Tabs[0].SelectedURIs[0] := 'file:///C:/Work/a.txt';

  Dst := ClonePanelState(Src, NextId);
  Assert.IsTrue(Dst.ColumnMode = pcmBrief, 'ColumnMode must be cloned');
  Assert.IsTrue(Dst.SortColumn = pscSize, 'SortColumn must be cloned');
  Assert.IsTrue(Dst.SortDescending, 'SortDescending must be cloned');
  Assert.IsTrue(Dst.ViewKind = pvkInfo, 'ViewKind must be cloned');
  Assert.IsTrue(Dst.DriveDirs['C'] = 'C:\Work', 'DriveDirs must be cloned');
  Assert.IsTrue(Length(Dst.Tabs) = 1, 'Tabs length must be cloned');
  Assert.IsTrue(Dst.Tabs[0].Id = 10, 'Cloned tab must get fresh Id');
  Assert.IsTrue(NextId = 11, 'NextId must advance');
  Assert.IsTrue(Dst.Tabs[0].CurrentURI = 'file:///C:/Work', 'URI must be cloned');
  Assert.IsTrue(Length(Dst.Tabs[0].SelectedURIs) = 1, 'Selection must be cloned');
  // Independent SelectedURIs copy: mutate source must not affect clone.
  Src.Tabs[0].SelectedURIs[0] := 'file:///C:/Work/b.txt';
  Assert.IsTrue(Dst.Tabs[0].SelectedURIs[0] = 'file:///C:/Work/a.txt',
    'SelectedURIs must be deep-copied');

  State.LeftPanel := Src;
  State.RightPanel := Default(TPanelState);
  State.RightPanel.ActiveTabIndex := 0;
  State.RightPanel.ColumnMode := pcmFull;
  State.RightPanel.SortColumn := pscNone;
  State.RightPanel.SortDescending := False;
  State.RightPanel.ViewKind := pvkFiles;
  ClearPanelDriveDirs(State.RightPanel.DriveDirs);
  SetLength(State.RightPanel.Tabs, 1);
  State.RightPanel.Tabs[0] := MakeTab(2, 'Docs', 'file:///C:/Docs');
  State.ActiveSide := psLeft;
  State.LeftVisible := True;
  State.RightVisible := True;
  Assert.IsTrue(MakePanelsWorkspaceTitle(State) = 'Work | Docs',
    'Workspace title from both panels');

  State.LeftVisible := False;
  Assert.IsTrue(MakePanelsWorkspaceTitle(State) = 'Docs',
    'Hidden left → right caption only');

  Writeln('OK: TestClonePanelAndWorkspaceTitle passed');
end;

function MakeWs(AId: Cardinal; AKind: TWorkspaceKind; AOrigin: Cardinal = 0): TDualPanelWorkspaceTab;
begin
  Result := Default(TDualPanelWorkspaceTab);
  Result.Id := AId;
  Result.Kind := AKind;
  Result.Title := IntToStr(AId);
  Result.OriginWorkspaceId := AOrigin;
end;

procedure TestWorkspaceLifecycle;
var
  Tabs: TArray<TDualPanelWorkspaceTab>;
  Src, Dst: TDualPanelWorkspaceTab;
  NextId: Cardinal;
begin
  SetLength(Tabs, 3);
  Tabs[0] := MakeWs(1, wkPanels);
  Tabs[1] := MakeWs(2, wkDocument, 1);
  Tabs[2] := MakeWs(3, wkTerminal, 1);

  Assert.IsTrue(TDualPanelTabManager.PanelsWorkspaceCount(Tabs) = 1,
    'one panels workspace');
  Assert.IsTrue(not TDualPanelTabManager.CanClosePanelsWorkspace(Tabs),
    'cannot close last panels workspace');
  Assert.IsTrue(TDualPanelTabManager.FindFirstPanelsWorkspaceIndex(Tabs) = 0,
    'first panels is 0');
  Assert.IsTrue(TDualPanelTabManager.FindWorkspaceIndexById(Tabs, 3) = 2,
    'find by id');
  Assert.IsTrue(TDualPanelTabManager.NextWorkspaceIndex(2, 3) = 0, 'next wraps');
  Assert.IsTrue(TDualPanelTabManager.PrevWorkspaceIndex(0, 3) = 2, 'prev wraps');
  Assert.IsTrue(TDualPanelTabManager.NextWorkspaceIndex(0, 1) = 0, 'single next is noop');

  Assert.IsTrue(TDualPanelTabManager.ActiveIndexAfterRemove(2, 2, 2, -1) = 1,
    'removing last clamps to new high');
  Assert.IsTrue(TDualPanelTabManager.ActiveIndexAfterRemove(2, 1, 2, 0) = 0,
    'return-to-origin wins');
  Assert.IsTrue(TDualPanelTabManager.ActiveIndexAfterRemove(2, 0, 2, -1) = 1,
    'active after removed index decrements');

  SetLength(Tabs, 2);
  Tabs[0] := MakeWs(1, wkPanels);
  Tabs[1] := MakeWs(4, wkPanels);
  Assert.IsTrue(TDualPanelTabManager.CanClosePanelsWorkspace(Tabs),
    'two panels sessions can close');
  Assert.IsTrue(TDualPanelTabManager.RemoveWorkspaceAt(Tabs, 0), 'splice first');
  Assert.IsTrue((Length(Tabs) = 1) and (Tabs[0].Id = 4), 'remaining is second');
  Assert.IsTrue(not TDualPanelTabManager.RemoveWorkspaceAt(Tabs, 5), 'oob splice fails');

  NextId := 10;
  Src := Default(TDualPanelWorkspaceTab);
  Src.Kind := wkPanels;
  Src.State.ActiveSide := psRight;
  Src.State.LeftVisible := True;
  Src.State.RightVisible := False;
  Src.State.LeftPanel.ActiveTabIndex := 0;
  Src.State.LeftPanel.ColumnMode := pcmFull;
  ClearPanelDriveDirs(Src.State.LeftPanel.DriveDirs);
  SetLength(Src.State.LeftPanel.Tabs, 1);
  Src.State.LeftPanel.Tabs[0] := MakeTab(1, 'Home', 'file:///C:/');
  Src.State.RightPanel.ActiveTabIndex := 0;
  Src.State.RightPanel.ColumnMode := pcmBrief;
  ClearPanelDriveDirs(Src.State.RightPanel.DriveDirs);
  SetLength(Src.State.RightPanel.Tabs, 1);
  Src.State.RightPanel.Tabs[0] := MakeTab(2, 'Docs', 'file:///C:/Docs');
  Dst := TDualPanelTabManager.ClonePanelsWorkspaceFrom(Src, NextId, 2);
  Assert.IsTrue(Dst.Id = 10, 'cloned workspace id');
  Assert.IsTrue(NextId > 10, 'next id advanced through panel tabs');
  Assert.IsTrue(Dst.Kind = wkPanels, 'clone is panels');
  Assert.IsTrue(Dst.State.ActiveSide = psRight, 'active side cloned');
  Assert.IsTrue(not Dst.State.RightVisible, 'visibility cloned');
  Assert.IsTrue(Dst.OriginWorkspaceId = 0, 'clone has no origin');
  Assert.IsTrue(Dst.Title <> '', 'clone has a title');

  Writeln('OK: TestWorkspaceLifecycle passed');
end;

procedure TCloseSpy.CloseDocument(AIndex: Integer);
begin
  Last := Last + Format('doc:%d,', [AIndex]);
end;

procedure TCloseSpy.CloseTerminal(AIndex: Integer);
begin
  Last := Last + Format('term:%d,', [AIndex]);
end;

procedure TCloseSpy.RemoveWorkspace(AIndex: Integer);
begin
  Last := Last + Format('rm:%d,', [AIndex]);
end;

procedure TestEmbeddedWorkspace;
var
  Tabs: TArray<TDualPanelWorkspaceTab>;
  Ws: TDualPanelWorkspaceTab;
  Active, Idx: Integer;
  Spy: TCloseSpy;
  Host: TDualPanelEmbeddedHost;
begin
  SetLength(Tabs, 2);
  Tabs[0] := MakeWs(1, wkPanels);
  Tabs[1] := MakeWs(2, wkDocument);
  Tabs[1].DocURI := 'file:///C:/a.txt';
  Tabs[1].ViewOnly := True;
  Assert.IsTrue(TDualPanelTabManager.FindDocumentWorkspaceIndex(Tabs,
    'file:///C:/a.txt', True) = 1, 'find viewer tab');
  Assert.IsTrue(TDualPanelTabManager.FindDocumentWorkspaceIndex(Tabs,
    'file:///C:/a.txt', False) < 0, 'editor mode is a different tab');
  Assert.IsTrue(TDualPanelTabManager.FindWorkspaceIndexByKindAndId(Tabs,
    wkDocument, 2) = 1, 'find by kind+id');
  Assert.IsTrue(TDualPanelTabManager.FindWorkspaceIndexByKindAndId(Tabs,
    wkTerminal, 2) < 0, 'kind mismatch');

  Assert.IsTrue(TDualPanelTabManager.WorkspaceInsertIndex(0, 2) = 1, 'insert after 0');
  Assert.IsTrue(TDualPanelTabManager.WorkspaceInsertIndex(1, 2) = 2, 'insert after last');
  Assert.IsTrue(TDualPanelTabManager.WorkspaceInsertIndex(-1, 2) = 0, 'negative clamps');
  Assert.IsTrue(TDualPanelTabManager.WorkspaceInsertIndex(9, 2) = 2, 'past end clamps');

  Active := 0;
  Ws := TDualPanelTabManager.MakeEmbeddedWorkspaceTab(9, 'ed', wkDocument, 1);
  Assert.IsTrue(Ws.Kind = wkDocument, 'embedded kind');
  Assert.IsTrue(Ws.OriginWorkspaceId = 1, 'origin');
  Assert.IsTrue((Length(Ws.State.LeftPanel.Tabs) = 0) and
    (Length(Ws.State.RightPanel.Tabs) = 0), 'no panel tabs');
  Assert.IsTrue(Ws.State.LeftVisible and Ws.State.RightVisible, 'both sides visible');
  Idx := TDualPanelTabManager.InsertWorkspaceAfterActive(Tabs, Active, Ws);
  Assert.IsTrue((Idx = 1) and (Active = 1) and (Length(Tabs) = 3), 'inserted after active');
  Assert.IsTrue(Tabs[1].Id = 9, 'new tab sits after panels');
  Assert.IsTrue(Tabs[2].Id = 2, 'previous document shifted');

  Assert.IsTrue(TDualPanelTabManager.EmbeddedDocumentTitle('', 'Document') = 'Document',
    'empty editor caption falls back');
  Assert.IsTrue(TDualPanelTabManager.EmbeddedDocumentTitle('a.txt', 'Document') = 'a.txt',
    'editor caption wins');

  Assert.IsTrue(TDualPanelTabManager.ClassifyCloseWorkspace(-1, Tabs) = cwkNone, 'oob');
  Assert.IsTrue(TDualPanelTabManager.ClassifyCloseWorkspace(1, Tabs) = cwkDocument, 'doc');
  SetLength(Tabs, 2);
  Tabs[0] := MakeWs(1, wkPanels);
  Tabs[1] := MakeWs(3, wkTerminal);
  Assert.IsTrue(TDualPanelTabManager.ClassifyCloseWorkspace(1, Tabs) = cwkTerminal, 'term');
  Assert.IsTrue(TDualPanelTabManager.ClassifyCloseWorkspace(0, Tabs) = cwkNone,
    'last panels cannot close');
  SetLength(Tabs, 3);
  Tabs[0] := MakeWs(1, wkPanels);
  Tabs[1] := MakeWs(4, wkPanels);
  Tabs[2] := MakeWs(3, wkTerminal);
  Assert.IsTrue(TDualPanelTabManager.ClassifyCloseWorkspace(0, Tabs) = cwkPanels,
    'extra panels session can close');

  Spy := TCloseSpy.Create;
  try
    Host := Default(TDualPanelEmbeddedHost);
    Host.CloseDocument := Spy.CloseDocument;
    Host.CloseTerminal := Spy.CloseTerminal;
    Host.RemoveWorkspace := Spy.RemoveWorkspace;
    TDualPanelTabManager.DispatchCloseWorkspace(Host, cwkNone, 0);
    Assert.IsTrue(Spy.Last = '', 'none is a no-op');
    TDualPanelTabManager.DispatchCloseWorkspace(Host, cwkDocument, 2);
    TDualPanelTabManager.DispatchCloseWorkspace(Host, cwkTerminal, 3);
    TDualPanelTabManager.DispatchCloseWorkspace(Host, cwkPanels, 0);
    Assert.IsTrue(Spy.Last = 'doc:2,term:3,rm:0,', 'close dispatch order');
  finally
    Spy.Free;
  end;

  Writeln('OK: TestEmbeddedWorkspace passed');
end;

procedure TestSessionExportFilter;
var
  Src, OutS: TDualPanelWindowState;
  Ws: TDualPanelWorkspaceTab;
begin
  Src := Default(TDualPanelWindowState);
  SetLength(Src.WorkspaceTabs, 3);
  Src.WorkspaceTabs[0] := MakeWs(1, wkPanels);
  Src.WorkspaceTabs[1] := MakeWs(2, wkDocument);
  Src.WorkspaceTabs[1].DocURI := 'file:///C:/a.txt';
  Src.WorkspaceTabs[2] := MakeWs(3, wkPanels);
  Src.ActiveWorkspaceIndex := 2;
  OutS := TDualPanelTabManager.ExportPanelsSession(Src);
  Assert.IsTrue(Length(OutS.WorkspaceTabs) = 2, 'export keeps only panels');
  Assert.IsTrue((OutS.WorkspaceTabs[0].Id = 1) and (OutS.WorkspaceTabs[1].Id = 3),
    'export order');
  Assert.IsTrue(OutS.ActiveWorkspaceIndex = 1, 'active remapped onto panels');

  Src := Default(TDualPanelWindowState);
  SetLength(Src.WorkspaceTabs, 1);
  Src.WorkspaceTabs[0] := MakeWs(9, wkDocument);
  Src.ActiveWorkspaceIndex := 0;
  OutS := TDualPanelTabManager.ExportPanelsSession(Src);
  Assert.IsTrue((Length(OutS.WorkspaceTabs) = 1) and
    (OutS.WorkspaceTabs[0].Kind = wkDocument),
    'no panels → original state');

  Src := Default(TDualPanelWindowState);
  SetLength(Src.WorkspaceTabs, 3);
  Src.WorkspaceTabs[0] := MakeWs(1, wkDocument);
  Src.WorkspaceTabs[0].DocURI := 'x';
  Src.WorkspaceTabs[0].ViewOnly := True;
  Src.WorkspaceTabs[0].OriginWorkspaceId := 5;
  Src.WorkspaceTabs[1] := MakeWs(2, wkPanels);
  Src.WorkspaceTabs[2] := MakeWs(3, wkTerminal);
  Src.ActiveWorkspaceIndex := 1;
  OutS := TDualPanelTabManager.FilterImportedSession(Src);
  Assert.IsTrue(Length(OutS.WorkspaceTabs) = 1, 'import drops doc/term');
  Assert.IsTrue(OutS.WorkspaceTabs[0].Kind = wkPanels, 'forced panels');
  Assert.IsTrue(OutS.WorkspaceTabs[0].DocURI = '', 'cleared DocURI');
  Assert.IsTrue(not OutS.WorkspaceTabs[0].ViewOnly, 'cleared ViewOnly');
  Assert.IsTrue(OutS.WorkspaceTabs[0].OriginWorkspaceId = 0, 'cleared origin');
  Assert.IsTrue(OutS.ActiveWorkspaceIndex = 0, 'active remapped');

  Src := Default(TDualPanelWindowState);
  Assert.IsTrue(TDualPanelTabManager.NextIdAfterSession(Src) = 1, 'empty next id');
  SetLength(Src.WorkspaceTabs, 1);
  Src.WorkspaceTabs[0] := MakeWs(5, wkPanels);
  SetLength(Src.WorkspaceTabs[0].State.LeftPanel.Tabs, 1);
  Src.WorkspaceTabs[0].State.LeftPanel.Tabs[0].Id := 10;
  SetLength(Src.WorkspaceTabs[0].State.RightPanel.Tabs, 1);
  Src.WorkspaceTabs[0].State.RightPanel.Tabs[0].Id := 7;
  Assert.IsTrue(TDualPanelTabManager.NextIdAfterSession(Src) = 11, 'max of ws+tab ids');

  Ws := MakeWs(1, wkPanels);
  Ws.State.LeftVisible := False;
  Ws.State.RightVisible := False;
  TDualPanelTabManager.RestoreBothVisibleIfHidden(Ws);
  Assert.IsTrue(Ws.State.LeftVisible and Ws.State.RightVisible, 'both hidden → both shown');
  Ws.State.LeftVisible := False;
  Ws.State.RightVisible := True;
  TDualPanelTabManager.RestoreBothVisibleIfHidden(Ws);
  Assert.IsTrue((not Ws.State.LeftVisible) and Ws.State.RightVisible,
    'one hidden is left as-is');
  Writeln('OK: TestSessionExportFilter passed');
end;

procedure TestResolvePanelDriveUri;
var
  Dirs: TPanelDriveDirs;
  Uri: string;
begin
  ClearPanelDriveDirs(Dirs);

  Uri := ResolvePanelDriveUri(Dirs, 'D', 'D:\');
  Assert.IsTrue(Uri = 'file:///D:/', 'no remembered folder -> drive root');

  // Remembered folder is used as-is, WITHOUT a synchronous existence check
  // (GetFileAttributes/LocalPathIsDirectory on the UI thread could block for
  // a long time on an unresponsive network drive -- see the comment on
  // ResolvePanelDriveUri). A path that no
  // longer exists is deliberately not special-cased: navigating to it and
  // letting the async listing report "Path not found" is safer than
  // blocking here to pre-verify it.
  Dirs['D'] := 'D:\DoesNotExist\Nowhere';
  Uri := ResolvePanelDriveUri(Dirs, 'D', 'D:\');
  Assert.IsTrue(Uri = 'file:///D:/DoesNotExist/Nowhere',
    'remembered folder used as-is, no blocking existence check');

  // Bare "D:" gets a trailing path delimiter.
  Dirs['D'] := 'D:';
  Uri := ResolvePanelDriveUri(Dirs, 'D', 'D:\');
  Assert.IsTrue(Uri = 'file:///D:/', 'bare drive letter gets a trailing delimiter');

  // Non A-Z glyph (a Change-Drive special item) always falls back to the
  // given root, ignoring any remembered folder.
  Uri := ResolvePanelDriveUri(Dirs, #1, 'D:\');
  Assert.IsTrue(Uri = 'file:///D:/', 'non A-Z letter falls back to the given root');

  Writeln('OK: TestResolvePanelDriveUri passed');
end;

{ TTestDualPanelTabs }

procedure TTestDualPanelTabs.TestTabManager;
begin
  TestDualPanelTabs.TestTabManager;
end;

procedure TTestDualPanelTabs.TestClonePanelAndWorkspaceTitle;
begin
  TestDualPanelTabs.TestClonePanelAndWorkspaceTitle;
end;

procedure TTestDualPanelTabs.TestWorkspaceLifecycle;
begin
  TestDualPanelTabs.TestWorkspaceLifecycle;
end;

procedure TTestDualPanelTabs.TestEmbeddedWorkspace;
begin
  TestDualPanelTabs.TestEmbeddedWorkspace;
end;

procedure TTestDualPanelTabs.TestSessionExportFilter;
begin
  TestDualPanelTabs.TestSessionExportFilter;
end;

procedure TTestDualPanelTabs.TestResolvePanelDriveUri;
begin
  TestDualPanelTabs.TestResolvePanelDriveUri;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelTabs);

end.
