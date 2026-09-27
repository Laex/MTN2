unit TestDualPanelTopMenu;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelTopMenu = class
  public
    [Test] procedure TestDispatch;
    [Test] procedure TestEnablement;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uKeymap,
  uDualPanelTypes,
  uDualPanelUiTypes,
  uDualPanelInput,
  uTopMenuBar,
  uDualPanelTopMenu;

type
  TMenuSpy = class
  public
    Last: string;
    Side: TPanelSide;
    Job: TPanelJobKind;
    Recycle: Boolean;
    Edit: Boolean;
    procedure ActivateSide(ASide: TPanelSide);
    procedure OpenSortMenu;
    procedure ToggleDrive(ASide: TPanelSide);
    procedure CloseTab(ASide: TPanelSide);
    procedure BeginJob(AKind: TPanelJobKind; ADeleteToRecycleBin: Boolean);
    procedure OpenViewOrEdit(AEdit: Boolean);
    procedure RequestQuit;
    procedure ToggleConsoleMode;
    procedure EditFindReplace;
    procedure EditCopy;
    procedure BeginSetAttributes;
    procedure OpenDisplayDialog;
    procedure OpenConsoleProfileDialog;
  end;

procedure TMenuSpy.ActivateSide(ASide: TPanelSide);
begin
  Last := 'activate';
  Side := ASide;
end;

procedure TMenuSpy.OpenSortMenu;
begin
  Last := Last + '+sort';
end;

procedure TMenuSpy.ToggleDrive(ASide: TPanelSide);
begin
  Last := 'drive';
  Side := ASide;
end;

procedure TMenuSpy.CloseTab(ASide: TPanelSide);
begin
  Last := 'closetab';
  Side := ASide;
end;

procedure TMenuSpy.BeginJob(AKind: TPanelJobKind; ADeleteToRecycleBin: Boolean);
begin
  Last := 'job';
  Job := AKind;
  Recycle := ADeleteToRecycleBin;
end;

procedure TMenuSpy.OpenViewOrEdit(AEdit: Boolean);
begin
  Last := 'viewedit';
  Edit := AEdit;
end;

procedure TMenuSpy.RequestQuit;
begin
  Last := 'quit';
end;

procedure TMenuSpy.ToggleConsoleMode;
begin
  Last := 'console';
end;

procedure TMenuSpy.EditFindReplace;
begin
  Last := 'replace';
end;

procedure TMenuSpy.EditCopy;
begin
  Last := 'editcopy';
end;

procedure TMenuSpy.BeginSetAttributes;
begin
  Last := 'setattr';
end;

procedure TMenuSpy.OpenDisplayDialog;
begin
  Last := 'display';
end;

procedure TMenuSpy.OpenConsoleProfileDialog;
begin
  Last := 'consoleprofile';
end;

procedure BindSpy(var AHost: TDualPanelKeymapHost; ASpy: TMenuSpy);
begin
  FillChar(AHost, SizeOf(AHost), 0);
  AHost.ActivateSide := ASpy.ActivateSide;
  AHost.OpenSortMenu := ASpy.OpenSortMenu;
  AHost.ToggleDrivePopup := ASpy.ToggleDrive;
  AHost.ClosePanelTabOnSide := ASpy.CloseTab;
  AHost.BeginJob := ASpy.BeginJob;
  AHost.OpenViewOrEdit := ASpy.OpenViewOrEdit;
  AHost.RequestQuit := ASpy.RequestQuit;
  AHost.ToggleConsole := ASpy.ToggleConsoleMode;
  AHost.EditFindReplace := ASpy.EditFindReplace;
  AHost.EditCopy := ASpy.EditCopy;
  AHost.BeginSetAttributes := ASpy.BeginSetAttributes;
  AHost.OpenDisplayDialog := ASpy.OpenDisplayDialog;
  AHost.OpenConsoleProfileDialog := ASpy.OpenConsoleProfileDialog;
end;

procedure TestDispatch;
var
  Spy: TMenuSpy;
  Host: TDualPanelKeymapHost;
begin
  Spy := TMenuSpy.Create;
  try
    BindSpy(Host, Spy);
    Writeln('Top menu dispatch');

    Assert.IsTrue(not DispatchTopMenuAction(Host, tmaNone), 'tmaNone is unhandled');

    Assert.IsTrue(DispatchTopMenuAction(Host, tmaLeftSort), 'left sort handled');
    Assert.IsTrue(Spy.Side = psLeft, 'left sort activates left');
    Assert.IsTrue(Spy.Last = 'activate+sort', 'left sort then opens sort menu');

    Assert.IsTrue(DispatchTopMenuAction(Host, tmaRightDrive), 'right drive handled');
    Assert.IsTrue(Spy.Last = 'drive', 'right drive toggles popup');
    Assert.IsTrue(Spy.Side = psRight, 'right drive uses right side');

    Assert.IsTrue(DispatchTopMenuAction(Host, tmaLeftCloseTab), 'left close tab');
    Assert.IsTrue(Spy.Last = 'closetab', 'close tab does not save-activate');
    Assert.IsTrue(Spy.Side = psLeft, 'close tab left');

    Assert.IsTrue(DispatchTopMenuAction(Host, tmaFileCopy), 'copy handled');
    Assert.IsTrue(Spy.Job = pjkCopy, 'copy job kind');
    Assert.IsTrue(Spy.Recycle, 'copy recycle default true');

    Assert.IsTrue(DispatchTopMenuAction(Host, tmaFileWipe), 'wipe handled');
    Assert.IsTrue(Spy.Job = pjkDelete, 'wipe is delete job');
    Assert.IsTrue(not Spy.Recycle, 'wipe is not recycle');

    Assert.IsTrue(DispatchTopMenuAction(Host, tmaFileEdit), 'edit handled');
    Assert.IsTrue(Spy.Edit, 'edit opens editor');

    Assert.IsTrue(DispatchTopMenuAction(Host, tmaCmdConsoleToggle), 'console toggle');
    Assert.IsTrue(Spy.Last = 'console', 'console toggle uses Ctrl+O host ToggleConsole');

    Assert.IsTrue(DispatchTopMenuAction(Host, tmaCmdConsoleProfile), 'console profile handled');
    Assert.IsTrue(Spy.Last = 'consoleprofile', 'console profile opens Background console dialog');

    Assert.IsTrue(DispatchTopMenuAction(Host, tmaEditFindReplace), 'find replace handled');
    Assert.IsTrue(Spy.Last = 'replace', 'find replace calls EditFindReplace');

    Assert.IsTrue(DispatchTopMenuAction(Host, tmaEditCopy), 'edit copy handled');
    Assert.IsTrue(Spy.Last = 'editcopy', 'edit copy calls EditCopy');

    Assert.IsTrue(DispatchTopMenuAction(Host, tmaFileSetAttributes), 'set attributes handled');
    Assert.IsTrue(Spy.Last = 'setattr', 'set attributes calls BeginSetAttributes');

    Assert.IsTrue(DispatchTopMenuAction(Host, tmaOptDisplay), 'display handled');
    Assert.IsTrue(Spy.Last = 'display', 'display opens Font / Display dialog');

    Assert.IsTrue(DispatchTopMenuAction(Host, tmaQuit), 'quit handled');
    Assert.IsTrue(Spy.Last = 'quit', 'quit uses RequestQuit');

    Spy.Last := 'keep';
    Assert.IsTrue(DispatchTopMenuAction(Host, tmaOptZoomIn), 'zoom is handled no-op');
    Assert.IsTrue(Spy.Last = 'keep', 'zoom does not call host');
  finally
    Spy.Free;
  end;
end;

function Ctx(AKind: TWorkspaceKind; AReady, ACanEdit, AHexLock, AUndo,
  ARedo: Boolean; ACmdFocused: Boolean = False): TTopMenuEnableContext;
begin
  Result.Kind := AKind;
  Result.DocReady := AReady;
  Result.CanEdit := ACanEdit;
  Result.HexBinaryLocked := AHexLock;
  Result.CanUndo := AUndo;
  Result.CanRedo := ARedo;
  Result.CmdFocused := ACmdFocused;
end;

procedure TestEnablement;
var
  Panels, Viewer, Editor, Term, HexBin, Cmd: TTopMenuEnableContext;
begin
  Panels := Ctx(wkPanels, False, False, False, False, False);
  Viewer := Ctx(wkDocument, True, False, False, False, False);
  Editor := Ctx(wkDocument, True, True, False, True, True);
  Term := Ctx(wkTerminal, False, False, False, False, False);
  HexBin := Ctx(wkDocument, True, False, True, False, False);
  Cmd := Ctx(wkTerminal, False, False, False, False, False, True);

  Assert.IsTrue(TopMenuActionEnabled(tmaFileCopy, Panels), 'panels: copy on');
  Assert.IsTrue(not TopMenuActionEnabled(tmaEditGotoLine, Panels), 'panels: goto off');
  Assert.IsTrue(TopMenuActionEnabled(tmaEditCopy, Panels), 'panels: edit copy on');
  Assert.IsTrue(TopMenuActionEnabled(tmaEditCut, Panels), 'panels: edit cut on');
  Assert.IsTrue(TopMenuActionEnabled(tmaEditPaste, Panels), 'panels: edit paste on');
  Assert.IsTrue(TopMenuActionEnabled(tmaQuit, Panels), 'panels: quit on');
  Assert.IsTrue(TopMenuActionEnabled(tmaCmdNextTab, Panels), 'panels: next tab on');
  Assert.IsTrue(TopMenuActionEnabled(tmaOptTheme, Panels), 'panels: theme on');
  Assert.IsTrue(TopMenuActionEnabled(tmaOptDisplay, Panels), 'panels: display on');

  Assert.IsTrue(not TopMenuActionEnabled(tmaFileCopy, Viewer), 'viewer: copy off');
  Assert.IsTrue(not TopMenuActionEnabled(tmaLeftDrive, Viewer), 'viewer: left drive off');
  Assert.IsTrue(TopMenuActionEnabled(tmaEditCopy, Viewer), 'viewer: edit copy on');
  Assert.IsTrue(not TopMenuActionEnabled(tmaEditCut, Viewer), 'viewer: edit cut off');
  Assert.IsTrue(not TopMenuActionEnabled(tmaEditPaste, Viewer), 'viewer: edit paste off');
  Assert.IsTrue(TopMenuActionEnabled(tmaEditGotoLine, Viewer), 'viewer: goto on');
  Assert.IsTrue(TopMenuActionEnabled(tmaEditFind, Viewer), 'viewer: find on');
  Assert.IsTrue(not TopMenuActionEnabled(tmaEditFindReplace, Viewer), 'viewer: replace off');
  Assert.IsTrue(not TopMenuActionEnabled(tmaEditUndo, Viewer), 'viewer: undo off');
  Assert.IsTrue(TopMenuActionEnabled(tmaEditHexToggle, Viewer), 'viewer: hex on');
  Assert.IsTrue(TopMenuActionEnabled(tmaOptTheme, Viewer), 'viewer: theme on');
  Assert.IsTrue(TopMenuActionEnabled(tmaOptDisplay, Viewer), 'viewer: display on');
  Assert.IsTrue(TopMenuActionEnabled(tmaCmdNewTerminal, Viewer), 'viewer: new terminal on');
  Assert.IsTrue(TopMenuActionEnabled(tmaCmdConsoleProfile, Viewer), 'viewer: console profile on');
  Assert.IsTrue(TopMenuActionEnabled(tmaCmdConsoleProfile, Term), 'terminal: console profile on');

  Assert.IsTrue(TopMenuActionEnabled(tmaEditFindReplace, Editor), 'editor: replace on');
  Assert.IsTrue(TopMenuActionEnabled(tmaEditUndo, Editor), 'editor: undo on');
  Assert.IsTrue(TopMenuActionEnabled(tmaEditRedo, Editor), 'editor: redo on');
  Assert.IsTrue(TopMenuActionEnabled(tmaEditCopy, Editor), 'editor: edit copy on');
  Assert.IsTrue(TopMenuActionEnabled(tmaEditCut, Editor), 'editor: edit cut on');
  Assert.IsTrue(TopMenuActionEnabled(tmaEditPaste, Editor), 'editor: edit paste on');
  Assert.IsTrue(not TopMenuActionEnabled(tmaFileEdit, Editor), 'editor: Files Edit off');

  Assert.IsTrue(not TopMenuActionEnabled(tmaEditGotoLine, Term), 'terminal: goto off');
  Assert.IsTrue(not TopMenuActionEnabled(tmaLeftDrive, Term), 'terminal: left drive off');
  Assert.IsTrue(not TopMenuActionEnabled(tmaEditCopy, Term), 'terminal: edit copy off');
  Assert.IsTrue(TopMenuActionEnabled(tmaCmdConsoleToggle, Term), 'terminal: console on');

  Assert.IsTrue(TopMenuActionEnabled(tmaEditCopy, Cmd), 'cmdline: copy on');
  Assert.IsTrue(TopMenuActionEnabled(tmaEditCut, Cmd), 'cmdline: cut on');
  Assert.IsTrue(TopMenuActionEnabled(tmaEditPaste, Cmd), 'cmdline: paste on');

  Assert.IsTrue(TopMenuActionEnabled(tmaEditHexToggle, HexBin), 'binary hex: F4 Text on');
  Assert.IsTrue(TopMenuActionEnabled(tmaEditFind, HexBin), 'binary hex: find on');
  Assert.IsTrue(not TopMenuActionEnabled(tmaEditFindReplace, HexBin), 'binary hex: replace off');
end;

{ TTestDualPanelTopMenu }

procedure TTestDualPanelTopMenu.TestDispatch;
begin
  TestDualPanelTopMenu.TestDispatch;
end;

procedure TTestDualPanelTopMenu.TestEnablement;
begin
  TestDualPanelTopMenu.TestEnablement;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelTopMenu);

end.
