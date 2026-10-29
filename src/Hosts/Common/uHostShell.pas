unit uHostShell;

{ The program behind the text-terminal host: the theme, the compositor with
  the dual panel window (documents and terminals live in its tabs) and the
  background console, the commands the windows ask of their host, and the
  routing of keys and mouse events. It knows nothing about the terminal
  itself: it takes decoded events (uTermInput) and returns the character grid
  to show. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  uTerminalTypes, uThemeTypes, uThemeController, uThemeSpec, uMdiCompositor,
  uDualPanelWindow, uDualPanelUiTypes, uConsoleWindow, uSession, uTermInput, uCoreTimer,
  uUpdateController, uDisplaySettings;

type
  THostShell = class
  private
    FThemes: TThemeController;
    FTheme: IThemeRenderer;
    FMdi: TMdiCompositor;
    FDualPanel: TDualPanelWindow;
    FConsole: TConsoleWindow;
    FSession: TMtnSession;
    FCols: Integer;
    FRows: Integer;
    FGrid: TTerminalGrid;
    FDirty: Boolean;
    FQuit: Boolean;
    FPeekTimer: TCoreTimer;
    FDriveTimer: TCoreTimer;
    FAltTimer: TCoreTimer;
    FHeldShift: TShiftState;
    FUpdater: TUpdateController;
    FUpdateTimer: TCoreTimer;
    FLastClickTick: UInt64;
    FLastClickCol: Integer;
    FLastClickRow: Integer;
    FButtonsDown: Integer;
    // The window flags the shell changes for its lifetime.
    FPrevTitleBar: Boolean;
    FPrevPanelIcons: Boolean;
    FPrevFileDrag: Boolean;
    procedure Recompose;
    procedure SwitchTheme(const AThemeId: string);
    procedure RestoreSession;
    procedure ApplyChromeRows(AMenuBar, AKeyBar, AStatusLine: Boolean);
    function GetDisplaySettings: TDisplaySettings;
    procedure ApplyDisplaySettings(const ASettings: TDisplaySettings);
    procedure CreateDualPanel;
    function EnsureConsole: TConsoleWindow;
    procedure SyncHiddenConsoleArea(ACols, ARows: Integer);
    procedure ShowConsoleMode;
    procedure ShowPanelMode;
    procedure ApplyConsoleLayout;
    function IsConsoleActiveInConsoleMode: Boolean;
    procedure SyncKeyModifiers(AShift: TShiftState);
    function DispatchTerminalKey(var AKey: Word; var AKeyChar: Char;
      AShift: TShiftState): Boolean;
    procedure HandleKey(const AEvent: TTermEvent);
    procedure HandleMouse(const AEvent: TTermEvent);
    procedure HandleMouseDown(const AEvent: TTermEvent);
    procedure HandleMouseMove(const AEvent: TTermEvent);
    procedure HandleMouseUp(const AEvent: TTermEvent);
    procedure HandleWheel(const AEvent: TTermEvent);
    procedure HandlePaste(const AText: string);
    // Commands of the dual panel window.
    procedure DualPanelContentChanged(Sender: TObject);
    procedure DualPanelQuitRequest(Sender: TObject);
    procedure DualPanelOpenUpdates(Sender: TObject);
    procedure UpdateTimerTick(Sender: TObject);
    procedure DualPanelOpenViewer(const AURI: string);
    procedure DualPanelOpenEditor(const AURI: string);
    procedure DualPanelRunCommand(const ACommand, AWorkingDir: string);
    procedure DualPanelRunInBackground(Sender: TObject);
    procedure DualPanelReturnWhenDone(Sender: TObject);
    procedure DualPanelShellCwdSync(const APath: string);
    function DualPanelShellReleaseDirs(const APaths: TArray<string>): Boolean;
    function DualPanelSaveConsoleOutput(const APath: string; out AError: string): Boolean;
    procedure DualPanelClearConsoleBuffer(Sender: TObject);
    procedure DualPanelToggleConsole(Sender: TObject);
    procedure DualPanelOpenTerminal(const AProfileId, ACwd: string);
    procedure DualPanelOpenTerminalWith(const AProfileId, ACwd, ACommand: string);
    procedure DualPanelRunInPanelTerminal(const AProfileId, ACwd, ACommand: string);
    function DualPanelLaunchConsoleFile(const APath: string;
      AWhere: TLaunchPlacement): Boolean;
    procedure ChangeConsoleProfile(const AProfileId: string);
    function GetConsoleProfile: string;
    function GetConsoleStartOnLaunch: Boolean;
    procedure SetConsoleStartOnLaunch(AValue: Boolean);
    function GetConsoleCwdToPanels: Boolean;
    procedure SetConsoleCwdToPanels(AValue: Boolean);
    procedure ThemeSelected(const AThemeId: string);
    procedure ThemePreview(const ASpec: TThemeSpec);
    function GetActiveThemeId: string;
    procedure PeekTimerTick(Sender: TObject);
    procedure DriveTimerTick(Sender: TObject);
    procedure AltTimerTick(Sender: TObject);
    // Commands of the console window.
    procedure ConsoleContentChanged(Sender: TObject);
    procedure ConsoleCloseRequest(Sender: TObject);
    procedure ConsoleBackToPanels(Sender: TObject);
    procedure ConsoleDismiss(Sender: TObject);
    procedure ConsoleFocusCommandLine(Sender: TObject);
    procedure ConsoleSyncDirToPanels(Sender: TObject);
    function ConsoleGetCmdHistory: TArray<string>;
    procedure ConsoleRemoveCmdHistory(const ACommand: string);
    procedure ConsoleClearCmdHistory;
    procedure ConsoleCommandExecuted(const ACommand: string);
  public
    /// <summary>ANewSessionLocale is the language of a first start (no saved
    /// session); '' follows the OS interface language.</summary>
    constructor Create(ACols, ARows: Integer; const ANewSessionLocale: string = '');
    destructor Destroy; override;
    procedure Resize(ACols, ARows: Integer);
    /// <summary>The composed screen; valid until the next call.</summary>
    function Compose: TTerminalGrid;
    procedure HandleEvent(const AEvent: TTermEvent);
    /// <summary>Saves the panels and settings; call before leaving.</summary>
    procedure PersistSession;
    /// <summary>Saves the panels and settings now; False when the file could not
    /// be written.</summary>
    function TryPersistSession: Boolean;
    function DualPanelSaveSettings(out AError: string): Boolean;
    /// <summary>The terminal window title: the program and the folder of the
    /// active panel.</summary>
    function Title: string;
    /// <summary>Starts the plugin host and lets plugins reach the panels and
    /// show dialogs; call once before the first frame.</summary>
    procedure AttachPlugins(const APluginsDir: string);
    /// <summary>Stops the plugin host.</summary>
    procedure DetachPlugins;
    /// <summary>Starts the self-updater: Help > Updates and the quiet check
    /// shortly after the start.</summary>
    procedure AttachUpdater;
    /// <summary>Installs a staged update that was left for the exit, then
    /// drops the updater.</summary>
    procedure DetachUpdater;
    /// <summary>True when the screen must be composed again.</summary>
    property Dirty: Boolean read FDirty write FDirty;
    property Quit: Boolean read FQuit;
    property DualPanel: TDualPanelWindow read FDualPanel;
    property Cols: Integer read FCols;
    property Rows: Integer read FRows;
  end;

var
  /// <summary>Set by a host that draws bitmap file icons before it creates the
  /// shell: the panel icon column and its setting then work; otherwise the
  /// column is off.</summary>
  GHostShowsIcons: Boolean;
  /// <summary>Set by a host that draws pictures over the cells (the overlay
  /// frame): plugins may then open picture tabs.</summary>
  GHostShowsSurfaces: Boolean;

implementation

uses
  System.IOUtils, uThemeRegistry, uColorCoding, uKeymap, uStrings, uChromeRows,
  uShellProfiles, uDualPanelTypes, uConsoleSettings,
  uEditorSearch, uEditorWindow, uBaseConsoleWindow, uPanelColumns, uListExport, uThemeDrawing,
  uDualPanelDrag, uKeyChord, uDialogHost, uPlatformInfo, uTerminalWindow,
  uToast, uSharkSaver, uWindowChrome, uConsoleLaunch, uPluginHost, uPluginSurface,
  uPluginPanelServices, uPluginServices, uPluginUi, uPluginChrome, uDialogTypes, uVfsTypes,
  uOverlayRenderer, uKeyRouting;

const
  cDefaultThemeFallback = 'NDN';
  // Pause after the last Ctrl+Left/Right that applies the chosen drive.
  cDriveCommitMs = 700;
  cAltReleaseMs = 1500;

constructor THostShell.Create(ACols, ARows: Integer; const ANewSessionLocale: string);
begin
  inherited Create;
  FCols := Max(ACols, 20);
  FRows := Max(ARows, 6);
  FLastClickCol := -1;
  FLastClickRow := -1;
  ReloadKeymap('');
  // The shell draws no window frame of its own and no drag-out, and has bitmap
  // file icons only when the host draws them; the flags go back when the shell
  // is freed.
  FPrevTitleBar := GShowTitleBar;
  FPrevPanelIcons := GShowPanelIcons;
  FPrevFileDrag := GFileDragEnabled;
  GShowTitleBar := True;
  GShowPanelIcons := GHostShowsIcons;
  GFileDragEnabled := False;
  SetOverlayRepaintHandler(
    procedure
    begin
      Recompose;
    end);

  FSession := Default(TMtnSession);
  FSession.ConsoleRestartOnExit := True;
  FSession.TerminalCloseOnExit := True;
  FSession.ConsoleCwdToPanels := True;
  FSession.RestoreWorkspaceOnStart := True;
  FSession.CursorBlink := True;
  FSession.ShowNotifications := True;
  FSession.ShowKeyHints := True;
  FSession.ShowTitleBar := True;
  FSession.ShowMenuBar := True;
  FSession.ShowKeyBar := True;
  FSession.ShowStatusLine := True;
  FSession.AltOpensMenu := True;
  FSession.EditorAutoIndent := True;
  FSession.ExactSelectionSize := False;
  FSession.SaverMinutes := 5;
  FSession.CaretUnderline := False;
  FSession.PassiveCursor := True;
  FSession.ShowPanelIcons := True;
  FSession.ShadowStyle := ShadowStyleId(ssClassic);
  FSession.MarkedRows := MarkedRowStyleId(mrsText);

  if TryLoadSession(DefaultSessionFilePath, FSession) then
    SetLocale(FSession.Language)
  else if ANewSessionLocale <> '' then
    SetLocale(ANewSessionLocale)
  else
    SetLocale(SystemDefaultLocale);
  FThemes := TThemeController.Create(FSession.ThemeName);
  FTheme := FThemes.Theme;
  FMdi := TMdiCompositor.Create(FTheme);
  CreateDualPanel;
  RestoreSession;
  FPeekTimer := TCoreTimer.Create(nil);
  FPeekTimer.Enabled := False;
  FPeekTimer.OnTimer := PeekTimerTick;
  FDriveTimer := TCoreTimer.Create(nil);
  FDriveTimer.Enabled := False;
  FDriveTimer.Interval := cDriveCommitMs;
  FDriveTimer.OnTimer := DriveTimerTick;
  FAltTimer := TCoreTimer.Create(nil);
  FAltTimer.Enabled := False;
  FAltTimer.Interval := cAltReleaseMs;
  FAltTimer.OnTimer := AltTimerTick;
  AllocTerminalGrid(FGrid, FCols, FRows);
  FDirty := True;
end;

destructor THostShell.Destroy;
begin
  GShowTitleBar := FPrevTitleBar;
  GShowPanelIcons := FPrevPanelIcons;
  GFileDragEnabled := FPrevFileDrag;
  SetOverlayRepaintHandler(nil);
  FreeAndNil(FUpdateTimer);
  FreeAndNil(FUpdater);
  FreeAndNil(FPeekTimer);
  FreeAndNil(FDriveTimer);
  FreeAndNil(FAltTimer);
  // The windows call back into the shell while they close.
  if Assigned(FDualPanel) then
  begin
    FDualPanel.OnContentChanged := nil;
    FDualPanel.OnQuitRequest := nil;
  end;
  if Assigned(FConsole) then
  begin
    FConsole.OnContentChanged := nil;
    FConsole.OnCloseRequest := nil;
    FConsole.OnBackToPanels := nil;
    FConsole.OnDismissConsole := nil;
    FConsole.OnFocusCommandLine := nil;
    FConsole.OnSyncDirToPanels := nil;
    FConsole.OnGetCmdHistory := nil;
    FConsole.OnRemoveCmdHistory := nil;
    FConsole.OnClearCmdHistory := nil;
    FConsole.OnCommandExecuted := nil;
  end;
  FreeAndNil(FMdi);
  FTheme := nil;
  FreeAndNil(FThemes);
  inherited Destroy;
end;

procedure THostShell.AttachPlugins(const APluginsDir: string);
begin
  // Picture tabs a plugin opens (uPluginSurface) need a host that can show
  // pixels; without one the plugin is told no surface is available. Registered before the
  // plugins load so a plugin may open one from its start-up code.
  if GHostShowsSurfaces then
    SetPluginSurfaceHost(
      function(AHandle: Integer): Boolean
      begin
        Result := Assigned(FDualPanel) and (FMdi.Active = FDualPanel) and
          FDualPanel.Visible and FDualPanel.OpenSurfaceTab(AHandle);
        if Result then
          Recompose;
      end);
  StartPluginHost(APluginsDir);
  // Dialogs a plugin asks for appear only over the panels, never inside an
  // editor, viewer or terminal.
  SetPluginDialogHost(
    function(const ADecl: TDialogDeclaration; const AOnCommand: TProc<string, string>): Boolean
    begin
      Result := Assigned(FDualPanel) and (FMdi.Active = FDualPanel) and
        FDualPanel.Visible and FDualPanel.ShowHostDialog(ADecl, AOnCommand, 'settings.md');
      if Result then
        Recompose;
    end);
  SetPluginHostServices(BuildPanelPluginServices(
    function: TDualPanelWindow
    begin
      Result := FDualPanel;
    end,
    function: Boolean
    begin
      Result := FMdi.Active = FDualPanel;
    end,
    procedure
    begin
      Recompose;
    end));
  SetPluginChromeChanged(
    procedure
    begin
      // The status line is drawn with the panels: they must rebuild.
      if Assigned(FDualPanel) then
        FDualPanel.Invalidate;
      Recompose;
    end);
end;

procedure THostShell.DetachPlugins;
begin
  SetPluginHostServices(Default(TPluginHostServices));
  SetPluginChromeChanged(nil);
  SetPluginDialogHost(nil);
  SetPluginSurfaceHost(nil);
  StopPluginHost;
end;

procedure THostShell.Recompose;
begin
  FDirty := True;
end;

{ ---- theme -------------------------------------------------------------- }

procedure THostShell.SwitchTheme(const AThemeId: string);
begin
  if FThemes.Switch(AThemeId) then
    Recompose;
end;

procedure THostShell.ThemeSelected(const AThemeId: string);
begin
  SwitchTheme(AThemeId);
end;

procedure THostShell.ThemePreview(const ASpec: TThemeSpec);
begin
  FThemes.Apply(ASpec);
  Recompose;
end;

function THostShell.GetActiveThemeId: string;
begin
  Result := FThemes.ThemeId;
end;

{ ---- session ------------------------------------------------------------ }

function THostShell.GetDisplaySettings: TDisplaySettings;
begin
  Result := DefaultDisplaySettings;
  Result.CursorBlink := FSession.CursorBlink;
  Result.ShowPanelIcons := GShowPanelIcons;
  Result.ShowNotifications := GShowToasts;
  Result.ShowKeyHints := not Assigned(FDualPanel) or FDualPanel.KeyHintsEnabled;
  Result.ShowTitleBar := GShowTitleBar;
  Result.ShowMenuBar := GShowMenuBar;
  Result.FileDrag := GFileDragEnabled;
  Result.AltOpensMenu := GAltOpensMenu;
  Result.EditorAutoIndent := GEditorAutoIndent;
  Result.ExactSelectionSize := GExactSelectionSize;
  Result.SaverMinutes := GSaverMinutes;
  Result.CaretUnderline := GCaretUnderline;
  Result.PassiveCursor := GShowPassiveCursor;
  Result.ShowKeyBar := GShowKeyBar;
  Result.ShowStatusLine := GShowStatusLine;
  Result.ShadowStyle := GShadowStyle;
  Result.MarkedRowStyle := GMarkedRowStyle;
  Result.SelectFolders := FDualPanel.SelectFolders;
  Result.PackInSamePanel := FDualPanel.PackInSamePanel;
  Result.BackspaceDriveMenu := FDualPanel.BackspaceDriveMenu;
  Result.DriveToOtherFolder := FDualPanel.DriveToOtherFolder;
  Result.SpaceSelects := FDualPanel.SpaceSelects;
  Result.Language := CurrentLocale;
end;

procedure THostShell.ApplyDisplaySettings(const ASettings: TDisplaySettings);
var
  LanguageChanged: Boolean;
begin
  // The terminal owns the font, the zoom and the window frame; the icons are
  // the host's setting only when the host draws them.
  if GHostShowsIcons then
  begin
    FSession.ShowPanelIcons := ASettings.ShowPanelIcons;
    GShowPanelIcons := ASettings.ShowPanelIcons;
  end;
  FSession.CursorBlink := ASettings.CursorBlink;
  FSession.ShowNotifications := ASettings.ShowNotifications;
  GShowToasts := ASettings.ShowNotifications;
  FSession.ShowKeyHints := ASettings.ShowKeyHints;
  if Assigned(FDualPanel) then
    FDualPanel.KeyHintsEnabled := ASettings.ShowKeyHints;
  FSession.PassiveCursor := ASettings.PassiveCursor;
  FSession.AltOpensMenu := ASettings.AltOpensMenu;
  GAltOpensMenu := ASettings.AltOpensMenu;
  FSession.EditorAutoIndent := ASettings.EditorAutoIndent;
  FSession.ExactSelectionSize := ASettings.ExactSelectionSize;
  FSession.SaverMinutes := ASettings.SaverMinutes;
  FSession.CaretUnderline := ASettings.CaretUnderline;
  GEditorAutoIndent := ASettings.EditorAutoIndent;
  GExactSelectionSize := ASettings.ExactSelectionSize;
  GSaverMinutes := ASettings.SaverMinutes;
  GCaretUnderline := ASettings.CaretUnderline;
  GShowPassiveCursor := ASettings.PassiveCursor;
  FSession.ShowMenuBar := ASettings.ShowMenuBar;
  FSession.ShowKeyBar := ASettings.ShowKeyBar;
  FSession.ShowStatusLine := ASettings.ShowStatusLine;
  ApplyChromeRows(ASettings.ShowMenuBar, ASettings.ShowKeyBar, ASettings.ShowStatusLine);
  FSession.ShadowStyle := ShadowStyleId(ASettings.ShadowStyle);
  GShadowStyle := ASettings.ShadowStyle;
  FSession.MarkedRows := MarkedRowStyleId(ASettings.MarkedRowStyle);
  GMarkedRowStyle := ASettings.MarkedRowStyle;
  FSession.SelectFolders := ASettings.SelectFolders;
  FDualPanel.SelectFolders := ASettings.SelectFolders;
  FSession.PackInSamePanel := ASettings.PackInSamePanel;
  FSession.BackspaceDriveMenu := ASettings.BackspaceDriveMenu;
  FSession.DriveToOtherFolder := ASettings.DriveToOtherFolder;
  FSession.SpaceSelects := ASettings.SpaceSelects;
  FDualPanel.PackInSamePanel := ASettings.PackInSamePanel;
  FDualPanel.BackspaceDriveMenu := ASettings.BackspaceDriveMenu;
  FDualPanel.DriveToOtherFolder := ASettings.DriveToOtherFolder;
  FDualPanel.SpaceSelects := ASettings.SpaceSelects;
  LanguageChanged := not SameText(CurrentLocale, ASettings.Language) and
    not (SameText(CurrentLocale, 'en') and (Trim(ASettings.Language) = ''));
  FSession.Language := ASettings.Language;
  if LanguageChanged then
  begin
    SetLocale(ASettings.Language);
    FDualPanel.ReloadMenuStructure;
    PluginAnnounceLanguage;
  end;
  Recompose;
end;

procedure THostShell.ApplyChromeRows(AMenuBar, AKeyBar, AStatusLine: Boolean);
begin
  GShowMenuBar := AMenuBar;
  GShowKeyBar := AKeyBar;
  GShowStatusLine := AStatusLine;
  if Assigned(FConsole) then
    FConsole.LayoutBottomMargin := ChromeBottomRows;
end;

procedure THostShell.RestoreSession;
var
  Sess: TMtnSession;
begin
  if not TryLoadSession(DefaultSessionFilePath, Sess) then
    Exit;
  FSession := Sess;
  FDualPanel.ApplySessionState(Sess.Panels);
  FDualPanel.TerminalCloseOnExit := Sess.TerminalCloseOnExit;
  FDualPanel.ProgramsInTerminal := Sess.ProgramsInTerminal;
  FDualPanel.AutoSyncConsoleCwd := Sess.AutoSyncConsoleCwd;
  FDualPanel.SelectFolders := Sess.SelectFolders;
  FDualPanel.PackInSamePanel := Sess.PackInSamePanel;
  FDualPanel.BackspaceDriveMenu := Sess.BackspaceDriveMenu;
  FDualPanel.DriveToOtherFolder := Sess.DriveToOtherFolder;
  FDualPanel.SpaceSelects := Sess.SpaceSelects;
  if Sess.RestoreWorkspaceOnStart then
    FDualPanel.RestoreWorkspaceLibrary(Sess.LastWorkspaceId);
  GCustomColumnsConfig := Sess.CustomColumns;
  GListExportConfig := Sess.ListExport;
  GShowToasts := Sess.ShowNotifications;
  FDualPanel.KeyHintsEnabled := Sess.ShowKeyHints;
  FDualPanel.KeyHintsSeen := Sess.KeyHintsSeen;
  GSaverMinutes := Sess.SaverMinutes;
  GShowPassiveCursor := Sess.PassiveCursor;
  if GHostShowsIcons then
    GShowPanelIcons := Sess.ShowPanelIcons;
  ApplyChromeRows(Sess.ShowMenuBar, Sess.ShowKeyBar, Sess.ShowStatusLine);
  GShadowStyle := ShadowStyleFromId(Sess.ShadowStyle);
  GMarkedRowStyle := MarkedRowStyleFromId(Sess.MarkedRows);
  GConsoleSettings.ScrollbackLines := ClampScrollbackLines(Sess.ConsoleScrollback);
  GConsoleSettings.ConfirmMultiLinePaste := Sess.ConsoleConfirmPaste;
  GConsoleSettings.TrimCopiedSpaces := Sess.ConsoleTrimCopy;
  GConsoleSettings.TrimPastedSpaces := Sess.ConsoleTrimPaste;
  GConsoleSettings.ReturnToPanels := Sess.ConsoleReturnToPanels;
  GConsoleSettings.BackgroundShowMs := ClampBackgroundShowMs(Sess.ConsoleBackgroundShowMs);
  GEditorSearchOptions.MatchCase := Sess.EditorSearchCase;
  GEditorSearchOptions.WholeWord := Sess.EditorSearchWords;
  GEditorSearchOptions.UseRegex := Sess.EditorSearchRegex;
end;

procedure THostShell.PersistSession;
begin
  TryPersistSession;
end;

function THostShell.DualPanelSaveSettings(out AError: string): Boolean;
begin
  AError := DefaultSessionFilePath;
  Result := TryPersistSession;
end;

function THostShell.TryPersistSession: Boolean;
var
  Sess: TMtnSession;
begin
  Result := False;
  if not Assigned(FDualPanel) then
    Exit;
  Sess := FSession;
  Sess.Version := cSessionVersion;
  Sess.Panels := FDualPanel.ExportSessionState;
  if Assigned(FConsole) then
  begin
    Sess.BackgroundConsoleProfile := FConsole.ProfileId;
    Sess.ConsoleRestartOnExit := FConsole.RestartOnExit;
  end;
  Sess.TerminalCloseOnExit := FDualPanel.TerminalCloseOnExit;
  Sess.ProgramsInTerminal := FDualPanel.ProgramsInTerminal;
  Sess.AutoSyncConsoleCwd := FDualPanel.AutoSyncConsoleCwd;
  Sess.ThemeName := FThemes.ThemeId;
  Sess.ThemeFile := '';
  Sess.ShowNotifications := GShowToasts;
  Sess.ShowKeyHints := FDualPanel.KeyHintsEnabled;
  Sess.KeyHintsSeen := FDualPanel.KeyHintsSeen;
  Sess.SaverMinutes := GSaverMinutes;
  Sess.ShowMenuBar := GShowMenuBar;
  Sess.ShowKeyBar := GShowKeyBar;
  Sess.ShowStatusLine := GShowStatusLine;
  Sess.PassiveCursor := GShowPassiveCursor;
  if GHostShowsIcons then
    Sess.ShowPanelIcons := GShowPanelIcons;
  Sess.ShadowStyle := ShadowStyleId(GShadowStyle);
  Sess.MarkedRows := MarkedRowStyleId(GMarkedRowStyle);
  Sess.ConsoleScrollback := GConsoleSettings.ScrollbackLines;
  Sess.ConsoleConfirmPaste := GConsoleSettings.ConfirmMultiLinePaste;
  Sess.ConsoleTrimCopy := GConsoleSettings.TrimCopiedSpaces;
  Sess.ConsoleTrimPaste := GConsoleSettings.TrimPastedSpaces;
  Sess.ConsoleReturnToPanels := GConsoleSettings.ReturnToPanels;
  Sess.ConsoleBackgroundShowMs := GConsoleSettings.BackgroundShowMs;
  Sess.EditorSearchCase := GEditorSearchOptions.MatchCase;
  Sess.EditorSearchWords := GEditorSearchOptions.WholeWord;
  Sess.EditorSearchRegex := GEditorSearchOptions.UseRegex;
  Sess.SelectFolders := FDualPanel.SelectFolders;
  Sess.PackInSamePanel := FDualPanel.PackInSamePanel;
  Sess.BackspaceDriveMenu := FDualPanel.BackspaceDriveMenu;
  Sess.DriveToOtherFolder := FDualPanel.DriveToOtherFolder;
  Sess.SpaceSelects := FDualPanel.SpaceSelects;
  Sess.Language := CurrentLocale;
  Sess.CustomColumns := GCustomColumnsConfig;
  Sess.ListExport := GListExportConfig;
  Sess.LastWorkspaceId := FDualPanel.WorkspaceLibraryId;
  FSession := Sess;
  Result := SaveSession(DefaultSessionFilePath, Sess);
end;

{ ---- windows ------------------------------------------------------------ }

procedure THostShell.CreateDualPanel;
begin
  FDualPanel := TDualPanelWindow.Create(FTheme, FMdi.AllocId);
  FDualPanel.OnContentChanged := DualPanelContentChanged;
  FDualPanel.OnOpenViewer := DualPanelOpenViewer;
  FDualPanel.OnOpenEditor := DualPanelOpenEditor;
  FDualPanel.OnQuitRequest := DualPanelQuitRequest;
  FDualPanel.OnRunCommand := DualPanelRunCommand;
  FDualPanel.OnReturnWhenDone := DualPanelReturnWhenDone;
  FDualPanel.OnRunInBackground := DualPanelRunInBackground;
  FDualPanel.OnShellCwdSync := DualPanelShellCwdSync;
  FDualPanel.OnShellReleaseDirs := DualPanelShellReleaseDirs;
  FDualPanel.OnSaveConsoleOutput := DualPanelSaveConsoleOutput;
  FDualPanel.OnClearConsoleBuffer := DualPanelClearConsoleBuffer;
  FDualPanel.OnSaveSettings := DualPanelSaveSettings;
  FDualPanel.OnGetDisplaySettings := GetDisplaySettings;
  FDualPanel.OnApplyDisplaySettings := ApplyDisplaySettings;
  FDualPanel.OnToggleConsole := DualPanelToggleConsole;
  FDualPanel.OnOpenTerminal := DualPanelOpenTerminal;
  FDualPanel.OnLaunchConsoleFile := DualPanelLaunchConsoleFile;
  FDualPanel.OnQueryConsoleKeyCapture :=
    function: Boolean
    begin
      Result := IsConsoleActiveInConsoleMode and Assigned(FConsole) and
        FConsole.KeysToProgram;
    end;
  FDualPanel.OnSetConsoleProfile := ChangeConsoleProfile;
  FDualPanel.OnGetConsoleProfile := GetConsoleProfile;
  FDualPanel.OnGetConsoleStartOnLaunch := GetConsoleStartOnLaunch;
  FDualPanel.OnSetConsoleStartOnLaunch := SetConsoleStartOnLaunch;
  FDualPanel.OnGetConsoleCwdToPanels := GetConsoleCwdToPanels;
  FDualPanel.OnSetConsoleCwdToPanels := SetConsoleCwdToPanels;
  FDualPanel.OnThemeSelect := ThemeSelected;
  FDualPanel.OnThemePreview := ThemePreview;
  FDualPanel.OnGetActiveThemeId := GetActiveThemeId;
  FMdi.AttachWindow(FDualPanel);
end;

function THostShell.EnsureConsole: TConsoleWindow;
var
  ProfileId: string;
begin
  if not Assigned(FConsole) then
  begin
    ProfileId := FSession.BackgroundConsoleProfile;
    FConsole := TConsoleWindow.Create(FTheme, FMdi.AllocId, ProfileId);
    FConsole.RestartOnExit := FSession.ConsoleRestartOnExit;
    FConsole.OnContentChanged := ConsoleContentChanged;
    FConsole.OnCloseRequest := ConsoleCloseRequest;
    FConsole.OnBackToPanels := ConsoleBackToPanels;
    FConsole.OnDismissConsole := ConsoleDismiss;
    FConsole.OnFocusCommandLine := ConsoleFocusCommandLine;
    FConsole.OnSyncDirToPanels := ConsoleSyncDirToPanels;
    FConsole.OnGetCmdHistory := ConsoleGetCmdHistory;
    FConsole.OnRemoveCmdHistory := ConsoleRemoveCmdHistory;
    FConsole.OnClearCmdHistory := ConsoleClearCmdHistory;
    FConsole.OnCommandExecuted := ConsoleCommandExecuted;
    FMdi.AttachWindow(FConsole);
    // Attaching activates the window; it stays hidden until it is asked for.
    FConsole.Visible := False;
    FMdi.Activate(FDualPanel);
    FConsole.LayoutBottomMargin := ChromeBottomRows;
    SyncHiddenConsoleArea(FCols, FRows);
  end;
  Result := FConsole;
end;

procedure THostShell.SyncHiddenConsoleArea(ACols, ARows: Integer);
begin
  if Assigned(FConsole) and not FConsole.Visible and (ACols > 0) and (ARows > 1) then
    FConsole.Area := TRectI.Make(0, 0, ACols - 1, Max(ARows - 1 - ChromeBottomRows, 1));
end;

procedure THostShell.ApplyConsoleLayout;
begin
  FMdi.LayoutMaximized(FCols, FRows);
end;

procedure THostShell.ShowConsoleMode;
begin
  EnsureConsole;
  FDualPanel.Visible := True;
  FDualPanel.ConsoleMode := True;
  FDualPanel.CmdFocused := False;
  FConsole.Visible := True;
  ApplyConsoleLayout;
  if not FConsole.Running then
    FConsole.EnsureShell(FDualPanel.ActiveLocalPath);
  FMdi.Activate(FConsole);
end;

procedure THostShell.ShowPanelMode;
var
  Cwd: string;
begin
  if Assigned(FConsole) and FSession.ConsoleCwdToPanels and FConsole.TakeCwdChange(Cwd) then
    FDualPanel.SetActivePanelDir(Cwd);
  if Assigned(FConsole) then
    FConsole.Visible := False;
  FDualPanel.ConsoleMode := False;
  FDualPanel.Visible := True;
  FMdi.Activate(FDualPanel);
end;

function THostShell.IsConsoleActiveInConsoleMode: Boolean;
begin
  Result := uKeyRouting.IsConsoleActiveInConsoleMode(FDualPanel, FMdi, FConsole);
end;

{ ---- dual panel commands --------------------------------------------------- }

procedure THostShell.DualPanelContentChanged(Sender: TObject);
begin
  Recompose;
end;

procedure THostShell.DualPanelQuitRequest(Sender: TObject);
begin
  FQuit := True;
end;

procedure THostShell.DualPanelOpenUpdates(Sender: TObject);
begin
  if Assigned(FUpdater) then
    FUpdater.OpenUpdatesDialog;
end;

procedure THostShell.UpdateTimerTick(Sender: TObject);
begin
  FUpdateTimer.Enabled := False;
  if Assigned(FUpdater) then
    FUpdater.StartupCheck;
end;

procedure THostShell.AttachUpdater;
var
  Host: TUpdateHost;
begin
  Host.ShowDialog :=
    function(ADecl: TDialogDeclaration; AOnCommand: TProc<string, string>): Boolean
    begin
      // Only over the panels: never inside an editor, viewer or terminal the
      // user is working in. The controller retries later.
      Result := Assigned(FDualPanel) and (FMdi.Active = FDualPanel) and
        FDualPanel.Visible and FDualPanel.ShowHostDialog(ADecl, AOnCommand, 'updates.md');
      if Result then
        Recompose;
    end;
  Host.HasBusyJob :=
    function: Boolean
    begin
      Result := Assigned(FDualPanel) and FDualPanel.HasBusyJob;
    end;
  Host.RequestClose :=
    procedure
    begin
      FQuit := True;
    end;
  Host.OpenFile :=
    procedure(APath: string)
    begin
      DualPanelOpenViewer(PathToFileUri(APath));
    end;
  FUpdater := TUpdateController.Create(Host);
  FDualPanel.OnOpenUpdates := DualPanelOpenUpdates;
  FUpdateTimer := TCoreTimer.Create(nil);
  FUpdateTimer.Interval := 5000;
  FUpdateTimer.OnTimer := UpdateTimerTick;
  FUpdateTimer.Enabled := True;
end;

procedure THostShell.DetachUpdater;
begin
  if Assigned(FUpdateTimer) then
    FUpdateTimer.Enabled := False;
  if Assigned(FUpdater) then
    FUpdater.BeforeExit;
  if Assigned(FDualPanel) then
    FDualPanel.OnOpenUpdates := nil;
  FreeAndNil(FUpdater);
end;

procedure THostShell.DualPanelOpenViewer(const AURI: string);
begin
  if AURI = '' then
    Exit;
  FDualPanel.OpenDocument(AURI, True);
  FMdi.Activate(FDualPanel);
  Recompose;
end;

procedure THostShell.DualPanelOpenEditor(const AURI: string);
begin
  if AURI = '' then
    Exit;
  FDualPanel.OpenDocument(AURI, False);
  FMdi.Activate(FDualPanel);
  Recompose;
end;

procedure THostShell.DualPanelRunCommand(const ACommand, AWorkingDir: string);
begin
  ShowConsoleMode;
  ApplyConsoleLayout;
  FConsole.RunCommand(ACommand, AWorkingDir);
  Recompose;
end;

procedure THostShell.DualPanelRunInBackground(Sender: TObject);
begin
  FPeekTimer.Enabled := False;
  FPeekTimer.Interval := ClampBackgroundShowMs(GConsoleSettings.BackgroundShowMs);
  FPeekTimer.Enabled := True;
end;

procedure THostShell.PeekTimerTick(Sender: TObject);
begin
  FPeekTimer.Enabled := False;
  if IsConsoleActiveInConsoleMode then
    ConsoleBackToPanels(Self);
end;

procedure THostShell.AltTimerTick(Sender: TObject);
begin
  FAltTimer.Enabled := False;
  // No key release arrives from a terminal: Alt counts as released when no
  // Alt key has come for a while, which closes Alt quick search and the
  // directory-history popup.
  SyncKeyModifiers(FHeldShift - [ssAlt]);
  Recompose;
end;

procedure THostShell.DriveTimerTick(Sender: TObject);
begin
  FDriveTimer.Enabled := False;
  // A terminal reports no key releases: the drive chosen with Ctrl+Left/Right
  // is applied when the keys stop coming.
  FDualPanel.ApplyDrivePreview;
  Recompose;
end;

procedure THostShell.DualPanelReturnWhenDone(Sender: TObject);
begin
  if Assigned(FConsole) then
    FConsole.ReturnToPanelsWhenDone;
end;

procedure THostShell.DualPanelShellCwdSync(const APath: string);
begin
  if Assigned(FConsole) then
    FConsole.SyncWorkingDir(APath);
end;

function THostShell.DualPanelShellReleaseDirs(const APaths: TArray<string>): Boolean;
begin
  Result := Assigned(FConsole) and FConsole.ReleaseWorkingDirs(APaths);
end;

function THostShell.DualPanelSaveConsoleOutput(const APath: string;
  out AError: string): Boolean;
begin
  if not Assigned(FConsole) then
  begin
    AError := T('ui.toast.noConsole', 'The background console has not been started yet');
    Exit(False);
  end;
  Result := FConsole.SaveOutputToFile(APath, AError);
end;

procedure THostShell.DualPanelClearConsoleBuffer(Sender: TObject);
begin
  if Assigned(FConsole) then
  begin
    FConsole.ClearOutputBuffer;
    Recompose;
  end;
end;

procedure THostShell.DualPanelToggleConsole(Sender: TObject);
begin
  if FDualPanel.ConsoleMode then
  begin
    if Assigned(FConsole) and FConsole.Visible then
      ShowPanelMode
    else
      ShowConsoleMode;
  end
  else if Assigned(FConsole) and FConsole.Visible and (FMdi.Active = FConsole) then
    ShowPanelMode
  else
    ShowConsoleMode;
  Recompose;
end;

procedure THostShell.DualPanelOpenTerminal(const AProfileId, ACwd: string);
begin
  DualPanelOpenTerminalWith(AProfileId, ACwd, '');
end;

procedure THostShell.DualPanelRunInPanelTerminal(const AProfileId, ACwd, ACommand: string);
begin
  if AProfileId = '' then
    Exit;
  if FDualPanel.ConsoleMode then
    ShowPanelMode;
  FDualPanel.RunInPanelTerminal(AProfileId, ACwd, ACommand);
  FMdi.Activate(FDualPanel);
  Recompose;
end;

procedure THostShell.DualPanelOpenTerminalWith(const AProfileId, ACwd, ACommand: string);
begin
  if AProfileId = '' then
    Exit;
  if FDualPanel.ConsoleMode then
    ShowPanelMode;
  FDualPanel.OpenTerminal(AProfileId, ACwd, ACommand);
  FMdi.Activate(FDualPanel);
  Recompose;
end;

function THostShell.DualPanelLaunchConsoleFile(const APath: string;
  AWhere: TLaunchPlacement): Boolean;
var
  Kind: TLaunchFileKind;
  Cwd, Profile, Line: string;
begin
  Kind := DetectLaunchFileKind(APath);
  Result := Kind <> lfkOther;
  if not Result then
    Exit;
  Cwd := ExtractFileDir(APath);
  Profile := GetConsoleProfile;
  case ChooseConsoleLaunch(Kind, Profile, Assigned(FConsole) and FConsole.ShellBusy,
    (AWhere = lpPanelTerminal) or ((AWhere = lpDefault) and FDualPanel.ProgramsInTerminal)) of
    cltConsole:
      begin
        Line := BuildConsoleLaunchLine(APath, Kind, Profile);
        FDualPanel.RecordConsoleCommand(Line);
        DualPanelRunCommand(Line, Cwd);
        if AWhere = lpBackground then
          DualPanelRunInBackground(Self);
      end;
    cltTerminal:
      begin
        Profile := TerminalProfileForLaunch(Kind);
        Line := BuildConsoleLaunchLine(APath, Kind, Profile);
        FDualPanel.RecordConsoleCommand(Line);
        DualPanelRunInPanelTerminal(Profile, Cwd, Line);
      end;
  else
    Result := False;
  end;
end;

procedure THostShell.ChangeConsoleProfile(const AProfileId: string);
var
  ProfileId: string;
  WasVisible: Boolean;
begin
  ProfileId := CanonicalShellProfileId(AProfileId);
  FSession.BackgroundConsoleProfile := ProfileId;
  if not Assigned(FConsole) or SameText(FConsole.ProfileId, ProfileId) then
    Exit;
  WasVisible := FConsole.Visible;
  FConsole.OnCloseRequest := nil;
  FConsole.OnContentChanged := nil;
  FConsole.OnBackToPanels := nil;
  FConsole.OnDismissConsole := nil;
  FConsole.OnFocusCommandLine := nil;
  FConsole.OnSyncDirToPanels := nil;
  FConsole.OnGetCmdHistory := nil;
  FConsole.OnRemoveCmdHistory := nil;
  FConsole.OnClearCmdHistory := nil;
  FConsole.OnCommandExecuted := nil;
  FMdi.CloseWindow(FConsole);
  FConsole := nil;
  if WasVisible then
    ShowConsoleMode
  else
  begin
    EnsureConsole;
    FConsole.EnsureShell(FDualPanel.ActiveLocalPath);
  end;
  Recompose;
end;

function THostShell.GetConsoleProfile: string;
begin
  if Assigned(FConsole) then
    Result := FConsole.ProfileId
  else
    Result := FSession.BackgroundConsoleProfile;
end;

function THostShell.GetConsoleStartOnLaunch: Boolean;
begin
  Result := FSession.ConsoleStartOnLaunch;
end;

procedure THostShell.SetConsoleStartOnLaunch(AValue: Boolean);
begin
  FSession.ConsoleStartOnLaunch := AValue;
end;

function THostShell.GetConsoleCwdToPanels: Boolean;
begin
  Result := FSession.ConsoleCwdToPanels;
end;

procedure THostShell.SetConsoleCwdToPanels(AValue: Boolean);
begin
  FSession.ConsoleCwdToPanels := AValue;
end;

{ ---- console commands ---------------------------------------------------- }

procedure THostShell.ConsoleContentChanged(Sender: TObject);
begin
  Recompose;
end;

procedure THostShell.ConsoleCloseRequest(Sender: TObject);
var
  ToFree: TConsoleWindow;
begin
  ToFree := FConsole;
  FConsole := nil;
  if Assigned(ToFree) then
  begin
    ToFree.OnCloseRequest := nil;
    ToFree.OnContentChanged := nil;
    ToFree.OnBackToPanels := nil;
    ToFree.OnDismissConsole := nil;
    ToFree.OnFocusCommandLine := nil;
    FMdi.CloseWindow(ToFree);
  end;
  ShowPanelMode;
  Recompose;
end;

procedure THostShell.ConsoleBackToPanels(Sender: TObject);
begin
  ShowPanelMode;
  Recompose;
end;

procedure THostShell.ConsoleDismiss(Sender: TObject);
begin
  if Assigned(FConsole) then
  begin
    ShowPanelMode;
    Recompose;
  end;
end;

procedure THostShell.ConsoleFocusCommandLine(Sender: TObject);
begin
  FDualPanel.FocusCommandLine;
  Recompose;
end;

procedure THostShell.ConsoleSyncDirToPanels(Sender: TObject);
var
  Cwd: string;
begin
  if not Assigned(FConsole) then
    Exit;
  Cwd := FConsole.PromptCwd;
  if Cwd = '' then
    Cwd := FConsole.WorkingDir;
  FDualPanel.SetActivePanelDir(Cwd);
  Recompose;
end;

function THostShell.ConsoleGetCmdHistory: TArray<string>;
begin
  Result := FDualPanel.GetCommandHistoryItems;
end;

procedure THostShell.ConsoleRemoveCmdHistory(const ACommand: string);
begin
  FDualPanel.RemoveCommandHistoryItem(ACommand);
end;

procedure THostShell.ConsoleClearCmdHistory;
begin
  FDualPanel.ClearCommandHistory;
end;

procedure THostShell.ConsoleCommandExecuted(const ACommand: string);
begin
  FDualPanel.RecordConsoleCommand(ACommand);
end;

{ ---- screen -------------------------------------------------------------- }

function THostShell.Title: string;
var
  Path: string;
  I: Integer;
begin
  Path := FDualPanel.ActiveLocalPath;
  if Path = '' then
    Result := 'MTN2'
  else
    Result := 'MTN2 - ' + Path;
  // A control character in a folder name must not reach the terminal.
  for I := Length(Result) downto 1 do
    if Result[I] < ' ' then
      Delete(Result, I, 1);
end;

procedure THostShell.Resize(ACols, ARows: Integer);
begin
  ACols := Max(ACols, 20);
  ARows := Max(ARows, 6);
  if (ACols = FCols) and (ARows = FRows) then
    Exit;
  FCols := ACols;
  FRows := ARows;
  AllocTerminalGrid(FGrid, FCols, FRows);
  FDirty := True;
end;

function THostShell.Compose: TTerminalGrid;
begin
  FMdi.LayoutMaximized(FCols, FRows);
  SyncHiddenConsoleArea(FCols, FRows);
  FMdi.Paint(FGrid, FCols, FRows);
  FDualPanel.PaintConsoleWindowButtons(FGrid, FCols);
  PaintOverlayCells(FGrid);
  FDirty := False;
  Result := FGrid;
end;

{ ---- input --------------------------------------------------------------- }

procedure THostShell.SyncKeyModifiers(AShift: TShiftState);
begin
  if uKeyRouting.SyncKeyModifiers(FDualPanel, FMdi, AShift) then
    Recompose;
end;

function THostShell.DispatchTerminalKey(var AKey: Word; var AKeyChar: Char;
  AShift: TShiftState): Boolean;
begin
  SyncKeyModifiers(AShift);
  Result := RouteTerminalKey(FDualPanel, FMdi, FConsole, AKey, AKeyChar, AShift);
end;

procedure THostShell.HandleKey(const AEvent: TTermEvent);
var
  Key: Word;
  Ch: Char;
  Shift: TShiftState;
begin
  Key := AEvent.Key;
  Ch := AEvent.KeyChar;
  Shift := AEvent.Shift;
  // Typing takes the console over from a command started in the background.
  FPeekTimer.Enabled := False;
  NormalizeKeyInput(Key, Ch, Shift, False);
  if (Key = 0) and (Ch = #9) then
    Key := vkTab;
  if MatchActionIn(ActiveKeymap, [kcGlobal], KeymapLookupKey(Key, Ch), Shift) =
     kaReloadKeymap then
  begin
    ReloadKeymap('');
    Recompose;
    Exit;
  end;
  DispatchTerminalKey(Key, Ch, Shift);
  FHeldShift := Shift;
  FAltTimer.Enabled := False;
  if ssAlt in Shift then
    FAltTimer.Enabled := True;
  FDriveTimer.Enabled := False;
  if FDualPanel.DrivePreviewActive then
    FDriveTimer.Enabled := True;
  Recompose;
end;

procedure THostShell.HandlePaste(const AText: string);
var
  I: Integer;
  Key: Word;
  Ch: Char;
begin
  // The pasted text is typed key by key into whatever has the keyboard.
  for I := 1 to Length(AText) do
  begin
    Ch := AText[I];
    if Ch = #10 then
      Continue;
    Key := 0;
    if Ch = #13 then
      Key := vkReturn
    else if Ch = #9 then
      Key := vkTab;
    if Key <> 0 then
      Ch := #0;
    DispatchTerminalKey(Key, Ch, []);
  end;
  Recompose;
end;

procedure THostShell.HandleMouseDown(const AEvent: TTermEvent);
var
  Col, Row, LocalCol, LocalRow: Integer;
  Shift: TShiftState;
  Dbl: Boolean;
  Active: TTerminalWindow;
  MenuClick: Boolean;
  Key: Word;
  KeyChar: Char;
  KeyShift: TShiftState;
  Tick: UInt64;
begin
  FPeekTimer.Enabled := False;
  Col := AEvent.Col;
  Row := AEvent.Row;
  Shift := AEvent.Shift;
  Tick := PlatformTickCount64;
  Dbl := (AEvent.Button = TMouseButton.mbLeft) and (Col = FLastClickCol) and
    (Row = FLastClickRow) and (Tick - FLastClickTick <= PlatformDoubleClickMs);
  if AEvent.Button = TMouseButton.mbLeft then
  begin
    FLastClickCol := Col;
    FLastClickRow := Row;
    FLastClickTick := Tick;
    if Dbl then
    begin
      FLastClickCol := -1;
      Include(Shift, ssDouble);
    end;
    FButtonsDown := FButtonsDown or 1;
  end;
  if AEvent.Button = TMouseButton.mbLeft then
    Include(Shift, ssLeft)
  else if AEvent.Button = TMouseButton.mbRight then
    Include(Shift, ssRight)
  else
    Include(Shift, ssMiddle);

  // The window buttons on the console frame sit above the console.
  if (AEvent.Button = TMouseButton.mbLeft) and
     FDualPanel.HandleConsoleFrameClick(Col - FDualPanel.Area.Left,
       Row - FDualPanel.Area.Top) then
    Exit;

  // The function bar below a console is the dual panel's.
  if (AEvent.Button = TMouseButton.mbLeft) and FDualPanel.Visible and
     FDualPanel.ConsoleMode and Assigned(FConsole) and FConsole.Visible and
     FDualPanel.HitTest(Col, Row) and
     FDualPanel.FunctionBarClickKey(Col - FDualPanel.Area.Left, Row - FDualPanel.Area.Top,
       Shift, Key, KeyChar, KeyShift) then
  begin
    DispatchTerminalKey(Key, KeyChar, KeyShift);
    Exit;
  end;

  // A dialog or menu the panels opened over another window (the editor) is
  // drawn above it and takes the click first.
  if (AEvent.Button = TMouseButton.mbLeft) and (FMdi.Active <> FDualPanel) and
     FDualPanel.Visible and (FDualPanel.HasOpenDialog or FDualPanel.TopMenuOpen) and
     FDualPanel.HitTest(Col, Row) then
  begin
    FDualPanel.HandleClick(Col - FDualPanel.Area.Left, Row - FDualPanel.Area.Top, Dbl, Shift);
    Exit;
  end;

  FMdi.ActivateAt(Col, Row);
  Active := FMdi.Active;
  if (AEvent.Button = TMouseButton.mbLeft) and Assigned(Active) and Active.HitTest(Col, Row) then
  begin
    LocalCol := Col - Active.Area.Left;
    LocalRow := Row - Active.Area.Top;
    if (Active is TDualPanelWindow) and
       TDualPanelWindow(Active).HandleMouseDown(LocalCol, LocalRow, Shift) then
      Exit;
    if (Active is TEditorWindow) and
       TEditorWindow(Active).HandleMouseDown(LocalCol, LocalRow, Shift) then
      Exit;
    if (Active is TConsoleWindow) and
       TConsoleWindow(Active).HandleMouseDown(LocalCol, LocalRow, Shift) then
      Exit;
  end;
  if Assigned(FConsole) and FConsole.Visible and FConsole.HitTest(Col, Row) and
     (FMdi.Active <> FConsole) and
     FConsole.HandleMouseDown(Col - FConsole.Area.Left, Row - FConsole.Area.Top, Shift) then
    Exit;

  if FDualPanel.Visible and FDualPanel.HitTest(Col, Row) then
  begin
    LocalCol := Col - FDualPanel.Area.Left;
    LocalRow := Row - FDualPanel.Area.Top;
    if AEvent.Button = TMouseButton.mbRight then
    begin
      if FDualPanel.RightClickOpensTopMenu(LocalCol, LocalRow) then
        Exit;
      FDualPanel.HandleClick(LocalCol, LocalRow, False, Shift, False);
      Exit;
    end;
    MenuClick := FDualPanel.TopMenuOpen or (LocalRow = 0) or FDualPanel.HasOpenDialog;
    FDualPanel.HandleClick(LocalCol, LocalRow, Dbl, Shift);
    // A press on a file row can turn into a drag to the other panel.
    if (AEvent.Button = TMouseButton.mbLeft) and not Dbl and not MenuClick then
      FDualPanel.ArmPanelDrag(LocalCol, LocalRow);
  end;
end;

procedure THostShell.HandleMouseMove(const AEvent: TTermEvent);
var
  Col, Row, LocalCol, LocalRow: Integer;
  Active: TTerminalWindow;
begin
  Col := AEvent.Col;
  Row := AEvent.Row;
  if FDualPanel.Visible and FDualPanel.TopMenuOpen then
  begin
    LocalCol := Col - FDualPanel.Area.Left;
    LocalRow := Row - FDualPanel.Area.Top;
    FDualPanel.HandleMouseMove(LocalCol, LocalRow);
    Exit;
  end;
  Active := FMdi.Active;
  if Active = nil then
    Exit;
  LocalCol := Col - Active.Area.Left;
  LocalRow := Row - Active.Area.Top;
  if (Active = FDualPanel) and FDualPanel.UpdatePanelDrag(LocalCol, LocalRow) then
    Exit;
  if Active is TDualPanelWindow then
    TDualPanelWindow(Active).HandleMouseMove(LocalCol, LocalRow)
  else if Active is TEditorWindow then
    TEditorWindow(Active).HandleMouseMove(LocalCol, LocalRow)
  else if Active is TConsoleWindow then
    TConsoleWindow(Active).HandleMouseMove(LocalCol, LocalRow);
end;

procedure THostShell.HandleMouseUp(const AEvent: TTermEvent);
var
  Col, Row: Integer;
  Btn: TWindowButton;
  Acts: Boolean;
begin
  if AEvent.Button <> TMouseButton.mbLeft then
    Exit;
  FButtonsDown := FButtonsDown and not 1;
  Col := AEvent.Col - FDualPanel.Area.Left;
  Row := AEvent.Row - FDualPanel.Area.Top;
  // Shift moves, as in the Windows drop; without it the items are copied.
  if FDualPanel.FinishPanelDrag(Col, Row, (ssShift in AEvent.Shift) and not (ssCtrl in AEvent.Shift)) then
    Exit;
  if FDualPanel.HandleMenuMouseUp(Col, Row) then
    Exit;
  if FDualPanel.ReleaseChromeButton(Col, Row, Btn, Acts) then
    Exit;
  if FDualPanel.Visible then
    FDualPanel.HandleMouseUp
  else if FMdi.Active is TEditorWindow then
    TEditorWindow(FMdi.Active).HandleMouseUp
  else if FMdi.Active is TConsoleWindow then
    TConsoleWindow(FMdi.Active).HandleMouseUp;
end;

procedure THostShell.HandleWheel(const AEvent: TTermEvent);
var
  Delta: Integer;
  K: Word;
  C: Char;
begin
  if AEvent.MouseAction = tmaWheelUp then
    Delta := 120
  else if AEvent.MouseAction = tmaWheelDown then
    Delta := -120
  else
    Exit;
  if FDualPanel.Visible and FDualPanel.HitTest(AEvent.Col, AEvent.Row) and
     FDualPanel.HandleMouseWheelAt(AEvent.Col - FDualPanel.Area.Left,
       AEvent.Row - FDualPanel.Area.Top, Delta) then
    Exit;
  if Assigned(FMdi.Active) then
  begin
    if (FMdi.Active is TBaseConsoleWindow) and
       TBaseConsoleWindow(FMdi.Active).HandleMouseWheel(Delta) then
      Exit;
    if Delta > 0 then
      K := vkUp
    else
      K := vkDown;
    C := #0;
    FMdi.Active.HandleInput(K, [], C);
  end;
end;

procedure THostShell.HandleMouse(const AEvent: TTermEvent);
begin
  case AEvent.MouseAction of
    tmaPress: HandleMouseDown(AEvent);
    tmaRelease: HandleMouseUp(AEvent);
    tmaMove:
      if AEvent.Button = TMouseButton.mbLeft then
        HandleMouseMove(AEvent);
    tmaWheelUp, tmaWheelDown, tmaWheelLeft, tmaWheelRight: HandleWheel(AEvent);
  end;
end;

procedure THostShell.HandleEvent(const AEvent: TTermEvent);
begin
  case AEvent.Kind of
    tekKey: HandleKey(AEvent);
    tekMouse:
      begin
        HandleMouse(AEvent);
        Recompose;
      end;
    tekPaste: HandlePaste(AEvent.Text);
  end;
end;

end.
