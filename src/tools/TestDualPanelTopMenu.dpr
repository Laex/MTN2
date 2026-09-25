program TestDualPanelTopMenu;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.UITypes,
  uKeymap in '..\Core\uKeymap.pas',
  uDualPanelTypes in '..\Core\uDualPanelTypes.pas',
  uDualPanelUiTypes in '..\Core\uDualPanelUiTypes.pas',
  uDualPanelInput in '..\Core\uDualPanelInput.pas',
  uTopMenuBar in '..\Core\uTopMenuBar.pas',
  uDualPanelTopMenu in '..\Core\uDualPanelTopMenu.pas';

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

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
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

    Expect(not DispatchTopMenuAction(Host, tmaNone), 'tmaNone is unhandled');

    Expect(DispatchTopMenuAction(Host, tmaLeftSort), 'left sort handled');
    Expect(Spy.Side = psLeft, 'left sort activates left');
    Expect(Spy.Last = 'activate+sort', 'left sort then opens sort menu');

    Expect(DispatchTopMenuAction(Host, tmaRightDrive), 'right drive handled');
    Expect(Spy.Last = 'drive', 'right drive toggles popup');
    Expect(Spy.Side = psRight, 'right drive uses right side');

    Expect(DispatchTopMenuAction(Host, tmaLeftCloseTab), 'left close tab');
    Expect(Spy.Last = 'closetab', 'close tab does not save-activate');
    Expect(Spy.Side = psLeft, 'close tab left');

    Expect(DispatchTopMenuAction(Host, tmaFileCopy), 'copy handled');
    Expect(Spy.Job = pjkCopy, 'copy job kind');
    Expect(Spy.Recycle, 'copy recycle default true');

    Expect(DispatchTopMenuAction(Host, tmaFileWipe), 'wipe handled');
    Expect(Spy.Job = pjkDelete, 'wipe is delete job');
    Expect(not Spy.Recycle, 'wipe is not recycle');

    Expect(DispatchTopMenuAction(Host, tmaFileEdit), 'edit handled');
    Expect(Spy.Edit, 'edit opens editor');

    Expect(DispatchTopMenuAction(Host, tmaCmdConsoleToggle), 'console toggle');
    Expect(Spy.Last = 'console', 'console toggle uses Ctrl+O host ToggleConsole');

    Expect(DispatchTopMenuAction(Host, tmaCmdConsoleProfile), 'console profile handled');
    Expect(Spy.Last = 'consoleprofile', 'console profile opens Background console dialog');

    Expect(DispatchTopMenuAction(Host, tmaEditFindReplace), 'find replace handled');
    Expect(Spy.Last = 'replace', 'find replace calls EditFindReplace');

    Expect(DispatchTopMenuAction(Host, tmaEditCopy), 'edit copy handled');
    Expect(Spy.Last = 'editcopy', 'edit copy calls EditCopy');

    Expect(DispatchTopMenuAction(Host, tmaFileSetAttributes), 'set attributes handled');
    Expect(Spy.Last = 'setattr', 'set attributes calls BeginSetAttributes');

    Expect(DispatchTopMenuAction(Host, tmaOptDisplay), 'display handled');
    Expect(Spy.Last = 'display', 'display opens Font / Display dialog');

    Expect(DispatchTopMenuAction(Host, tmaQuit), 'quit handled');
    Expect(Spy.Last = 'quit', 'quit uses RequestQuit');

    Spy.Last := 'keep';
    Expect(DispatchTopMenuAction(Host, tmaOptZoomIn), 'zoom is handled no-op');
    Expect(Spy.Last = 'keep', 'zoom does not call host');
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
  Writeln('Top menu enablement');
  Panels := Ctx(wkPanels, False, False, False, False, False);
  Viewer := Ctx(wkDocument, True, False, False, False, False);
  Editor := Ctx(wkDocument, True, True, False, True, True);
  Term := Ctx(wkTerminal, False, False, False, False, False);
  HexBin := Ctx(wkDocument, True, False, True, False, False);
  Cmd := Ctx(wkTerminal, False, False, False, False, False, True);

  Expect(TopMenuActionEnabled(tmaFileCopy, Panels), 'panels: copy on');
  Expect(not TopMenuActionEnabled(tmaEditGotoLine, Panels), 'panels: goto off');
  Expect(TopMenuActionEnabled(tmaEditCopy, Panels), 'panels: edit copy on');
  Expect(TopMenuActionEnabled(tmaEditCut, Panels), 'panels: edit cut on');
  Expect(TopMenuActionEnabled(tmaEditPaste, Panels), 'panels: edit paste on');
  Expect(TopMenuActionEnabled(tmaQuit, Panels), 'panels: quit on');
  Expect(TopMenuActionEnabled(tmaCmdNextTab, Panels), 'panels: next tab on');
  Expect(TopMenuActionEnabled(tmaOptTheme, Panels), 'panels: theme on');
  Expect(TopMenuActionEnabled(tmaOptDisplay, Panels), 'panels: display on');

  Expect(not TopMenuActionEnabled(tmaFileCopy, Viewer), 'viewer: copy off');
  Expect(not TopMenuActionEnabled(tmaLeftDrive, Viewer), 'viewer: left drive off');
  Expect(TopMenuActionEnabled(tmaEditCopy, Viewer), 'viewer: edit copy on');
  Expect(not TopMenuActionEnabled(tmaEditCut, Viewer), 'viewer: edit cut off');
  Expect(not TopMenuActionEnabled(tmaEditPaste, Viewer), 'viewer: edit paste off');
  Expect(TopMenuActionEnabled(tmaEditGotoLine, Viewer), 'viewer: goto on');
  Expect(TopMenuActionEnabled(tmaEditFind, Viewer), 'viewer: find on');
  Expect(not TopMenuActionEnabled(tmaEditFindReplace, Viewer), 'viewer: replace off');
  Expect(not TopMenuActionEnabled(tmaEditUndo, Viewer), 'viewer: undo off');
  Expect(TopMenuActionEnabled(tmaEditHexToggle, Viewer), 'viewer: hex on');
  Expect(TopMenuActionEnabled(tmaOptTheme, Viewer), 'viewer: theme on');
  Expect(TopMenuActionEnabled(tmaOptDisplay, Viewer), 'viewer: display on');
  Expect(TopMenuActionEnabled(tmaCmdNewTerminal, Viewer), 'viewer: new terminal on');
  Expect(TopMenuActionEnabled(tmaCmdConsoleProfile, Viewer), 'viewer: console profile on');
  Expect(TopMenuActionEnabled(tmaCmdConsoleProfile, Term), 'terminal: console profile on');

  Expect(TopMenuActionEnabled(tmaEditFindReplace, Editor), 'editor: replace on');
  Expect(TopMenuActionEnabled(tmaEditUndo, Editor), 'editor: undo on');
  Expect(TopMenuActionEnabled(tmaEditRedo, Editor), 'editor: redo on');
  Expect(TopMenuActionEnabled(tmaEditCopy, Editor), 'editor: edit copy on');
  Expect(TopMenuActionEnabled(tmaEditCut, Editor), 'editor: edit cut on');
  Expect(TopMenuActionEnabled(tmaEditPaste, Editor), 'editor: edit paste on');
  Expect(not TopMenuActionEnabled(tmaFileEdit, Editor), 'editor: Files Edit off');

  Expect(not TopMenuActionEnabled(tmaEditGotoLine, Term), 'terminal: goto off');
  Expect(not TopMenuActionEnabled(tmaLeftDrive, Term), 'terminal: left drive off');
  Expect(not TopMenuActionEnabled(tmaEditCopy, Term), 'terminal: edit copy off');
  Expect(TopMenuActionEnabled(tmaCmdConsoleToggle, Term), 'terminal: console on');

  Expect(TopMenuActionEnabled(tmaEditCopy, Cmd), 'cmdline: copy on');
  Expect(TopMenuActionEnabled(tmaEditCut, Cmd), 'cmdline: cut on');
  Expect(TopMenuActionEnabled(tmaEditPaste, Cmd), 'cmdline: paste on');

  Expect(TopMenuActionEnabled(tmaEditHexToggle, HexBin), 'binary hex: F4 Text on');
  Expect(TopMenuActionEnabled(tmaEditFind, HexBin), 'binary hex: find on');
  Expect(not TopMenuActionEnabled(tmaEditFindReplace, HexBin), 'binary hex: replace off');
end;

begin
  try
    TestDispatch;
    TestEnablement;
    Writeln('All DualPanelTopMenu tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.Message);
      Halt(1);
    end;
  end;
end.
