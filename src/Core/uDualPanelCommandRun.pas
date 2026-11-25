unit uDualPanelCommandRun;

{ Running a command from the panels: the console under them, a new terminal
  tab, a detached process, and asking the shell to leave a folder before it
  is deleted. The window keeps the keymap entry points and the host events. }

interface

uses
  System.SysUtils,
  uDualPanelTypes, uDualPanelUiTypes, uVfsTypes;

type
  IDualPanelCommandHost = interface
    ['{B1E4C8A2-7F30-4D16-9A55-3C8E2B6D0F47}']
    function ActiveWorkspace: TDualPanelWorkspaceTab;
    function ActivePanel(var AWs: TDualPanelWorkspaceTab): TPanelState;
    function GetActiveRow(out AWs: TDualPanelWorkspaceTab; out APanel: TPanelState;
      out ATab: TTab; out ARows: TPanelRows; out ARow: TPanelRow;
      out AIdx: Integer): Boolean;
    function AutoSync: Boolean;
    function ShellCwdAssigned: Boolean;
    procedure ShellCwdSync(const APath: string);
    function ShellReleaseAssigned: Boolean;
    function ShellRelease(const APaths: TArray<string>): Boolean;
    function LaunchAssigned: Boolean;
    function LaunchFile(const APath: string; AWhere: TLaunchPlacement): Boolean;
    function RunCommandAssigned: Boolean;
    procedure RunCommand(const ACommand, AWorkingDir: string);
    procedure ReturnWhenDone;
    procedure RunInBackground;
    function CmdReady: Boolean;
    function CmdText: string;
    procedure CmdRemember(const AText: string);
    procedure CmdClear;
    function Life: ILifeFlag;
    procedure ShowInfo(const AText, AArg: string);
    procedure ShowWarning(const AText, AArg: string);
    function ConsoleProfile: string;
    function ReturnsToPanels: Boolean;
    procedure OpenTerminal(const AProfileId, ACwd, ACommand: string);
    procedure SetCmdFocused(AValue: Boolean);
    procedure NotifyChanged;
    procedure OpenStub(AKind: TStubKind; const ATitle, ADetail: string);
  end;

  TDualPanelCommandRun = class
  private
    FHost: IDualPanelCommandHost;
    function SendConsoleCommand(const ACommand: string): Boolean;
  public
    constructor Create(const AHost: IDualPanelCommandHost);
    function PanelCommandCwd: string;
    procedure PushShellCwdSync;
    procedure NotifyShellCwdSync;
    function ReleaseShellDirs(const ASources: TArray<string>): Boolean;
    procedure RunAfterShellRelease(const ASources: TArray<string>;
      const AAction: TProc);
    procedure SyncConsoleDirNow;
    procedure RunConsoleCommand(const ACommand: string);
    procedure RunInNewTab;
    procedure RunInBackground;
    function RunCursorFile(AWhere: TLaunchPlacement): Boolean;
    procedure RunDetachedFromCmdLine(const AText, ACwd: string);
    procedure RunDetachedOpenFolder(const AUri: string; const ATab: TTab;
      AIsParent: Boolean);
    procedure RunDetachedFile(const AUri: string);
    procedure RunDetached;
  end;

/// <summary>The local directory a typed command runs in. An archive uses the
/// folder that holds the archive; a find panel uses AFindRoot when that
/// session is known, otherwise the URI's own path.</summary>
function LocalCommandDirectory(const AURI: string; AFindKnown: Boolean;
  const AFindRoot: string): string;

/// <summary>Local paths the shell can leave, in the same order, skipping
/// archives, find results and URIs with no path. One allocation for the
/// whole list.</summary>
function LocalShellPaths(const ASources: TArray<string>): TArray<string>;

implementation

uses
  System.Classes, System.IOUtils,
  uFindSession, uPanelUriLabels, uShellAssoc, uShellProfiles, uStrings;

function LocalCommandDirectory(const AURI: string; AFindKnown: Boolean;
  const AFindRoot: string): string;
begin
  Result := FileUriToPath(AURI);
  if HasArchiveChain(AURI) then
    Result := SafeDirectoryName(ArchiveBasePath(AURI))
  else if IsFindUri(AURI) and AFindKnown then
    Result := AFindRoot;
end;

function LocalShellPaths(const ASources: TArray<string>): TArray<string>;
var
  Path, URI: string;
  N: Integer;
begin
  SetLength(Result, Length(ASources));
  N := 0;
  for URI in ASources do
  begin
    if HasArchiveChain(URI) or IsFindUri(URI) then
      Continue;
    Path := FileUriToPath(URI);
    if Path <> '' then
    begin
      Result[N] := Path;
      Inc(N);
    end;
  end;
  SetLength(Result, N);
end;

constructor TDualPanelCommandRun.Create(const AHost: IDualPanelCommandHost);
begin
  inherited Create;
  FHost := AHost;
end;

function TDualPanelCommandRun.PanelCommandCwd: string;
var
  Ws: TDualPanelWorkspaceTab;
  URI: string;
  FindData: TFindSessionData;
  Known: Boolean;
  Root: string;
begin
  Ws := FHost.ActiveWorkspace;
  URI := ActiveTab(FHost.ActivePanel(Ws)).CurrentURI;
  Known := False;
  Root := '';
  if IsFindUri(URI) and TryGetFindSessionFromUri(URI, FindData) then
  begin
    Known := True;
    Root := FindData.RootPath;
  end;
  Result := LocalCommandDirectory(URI, Known, Root);
end;

procedure TDualPanelCommandRun.PushShellCwdSync;
var
  Ws: TDualPanelWorkspaceTab;
  URI, Path: string;
begin
  if not FHost.ShellCwdAssigned then
    Exit;
  Ws := FHost.ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  URI := ActiveTab(FHost.ActivePanel(Ws)).CurrentURI;
  // Archive / find: leave shell cwd at last local path (no silent cd).
  if HasArchiveChain(URI) or IsFindUri(URI) then
    Exit;
  Path := FileUriToPath(URI);
  if Path = '' then
    Exit;
  FHost.ShellCwdSync(Path);
end;

procedure TDualPanelCommandRun.NotifyShellCwdSync;
begin
  // By default the console and the active panel keep their own directory;
  // this only fires the automatic push when the user opted in.
  if FHost.AutoSync then
    PushShellCwdSync;
end;

function TDualPanelCommandRun.ReleaseShellDirs(const ASources: TArray<string>): Boolean;
var
  Paths: TArray<string>;
begin
  Result := False;
  if not FHost.ShellReleaseAssigned then
    Exit;
  // One allocation for the selection. Growing the list per path stalls
  // deleting or moving many folders.
  Paths := LocalShellPaths(ASources);
  if Length(Paths) > 0 then
    Result := FHost.ShellRelease(Paths);
end;

procedure TDualPanelCommandRun.RunAfterShellRelease(const ASources: TArray<string>;
  const AAction: TProc);
var
  Life: ILifeFlag;
begin
  if not ReleaseShellDirs(ASources) then
  begin
    AAction();
    Exit;
  end;
  // The shell needs a moment to process the cd before the folder is touched.
  Life := FHost.Life;
  TThread.ForceQueue(nil,
    procedure
    begin
      if Life.Alive then
        AAction();
    end, 250);
end;

procedure TDualPanelCommandRun.SyncConsoleDirNow;
var
  Ws: TDualPanelWorkspaceTab;
  URI, Path: string;
begin
  Ws := FHost.ActiveWorkspace;
  if not FHost.ShellCwdAssigned or (Ws.Kind <> wkPanels) then
    Exit;
  // Same rules as PushShellCwdSync, which stays silent: it also runs on
  // every panel navigation when auto-sync is on.
  URI := ActiveTab(FHost.ActivePanel(Ws)).CurrentURI;
  if HasArchiveChain(URI) or IsFindUri(URI) then
    Path := ''
  else
    Path := FileUriToPath(URI);
  if Path = '' then
  begin
    FHost.ShowWarning(T('ui.toast.consoleDirUnavailable',
      'The console cannot go into this folder'), '');
    Exit;
  end;
  PushShellCwdSync;
  FHost.ShowInfo(T('ui.toast.consoleDir', 'Console folder: %s'), Path);
end;

procedure TDualPanelCommandRun.RunConsoleCommand(const ACommand: string);
begin
  if SendConsoleCommand(ACommand) then
    // Only a command typed under the panels sends the program back to them;
    // one typed in the background console stays in the console.
    if FHost.ReturnsToPanels then
      FHost.ReturnWhenDone;
end;

procedure TDualPanelCommandRun.RunInNewTab;
var
  Cmd, Profile: string;
begin
  if not FHost.CmdReady then
    Exit;
  Cmd := Trim(FHost.CmdText);
  if Cmd = '' then
  begin
    RunCursorFile(lpPanelTerminal);
    Exit;
  end;
  FHost.CmdRemember(Cmd);
  FHost.CmdClear;
  Profile := FHost.ConsoleProfile;
  if Profile = '' then
    Profile := cShellProfileCmd;
  FHost.OpenTerminal(Profile, PanelCommandCwd, Cmd);
end;

procedure TDualPanelCommandRun.RunInBackground;
var
  Text: string;
begin
  if not FHost.CmdReady then
    Exit;
  Text := FHost.CmdText;
  if Trim(Text) = '' then
  begin
    RunCursorFile(lpBackground);
    Exit;
  end;
  FHost.CmdRemember(Text);
  if SendConsoleCommand(Text) then
    FHost.RunInBackground;
end;

function TDualPanelCommandRun.RunCursorFile(AWhere: TLaunchPlacement): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
  Path: string;
begin
  Result := False;
  if not FHost.LaunchAssigned or
     not FHost.GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    Exit;
  if Row.IsParent or Row.IsDirectory or HasArchiveChain(Row.URI) then
    Exit;
  Path := FileUriToPath(Row.URI);
  if (Path = '') or not LocalPathIsFile(Path) then
    Exit;
  Result := FHost.LaunchFile(Path, AWhere);
  if Result then
    FHost.NotifyChanged;
end;

function TDualPanelCommandRun.SendConsoleCommand(const ACommand: string): Boolean;
var
  Cmd, Cwd: string;
begin
  Result := False;
  Cmd := Trim(ACommand);
  if Cmd = '' then
    Exit;
  Cwd := PanelCommandCwd;
  if FHost.CmdReady then
    FHost.CmdClear;
  // Leave cmdline unfocused so scroll/typing reach the Console buffer.
  FHost.SetCmdFocused(False);
  FHost.NotifyChanged;
  if FHost.RunCommandAssigned then
    FHost.RunCommand(Cmd, Cwd);
  Result := True;
end;

procedure TDualPanelCommandRun.RunDetachedFromCmdLine(const AText, ACwd: string);
begin
  if FHost.CmdReady then
    FHost.CmdClear;
  FHost.SetCmdFocused(False);
  if not ShellRunDetached(AText, ACwd) then
    FHost.OpenStub(skShellInfo, 'Run failed', AText)
  else
    FHost.NotifyChanged;
end;

procedure TDualPanelCommandRun.RunDetachedOpenFolder(const AUri: string;
  const ATab: TTab; AIsParent: Boolean);
var
  Path: string;
begin
  Path := PanelItemFullPath(AUri, ATab.CurrentURI, AIsParent);
  if (Path = '') or (not TDirectory.Exists(Path)) then
    Exit;
  if not ShellOpenFile(Path) then
    FHost.OpenStub(skShellInfo, 'Explorer failed', Path)
  else
    FHost.NotifyChanged;
end;

procedure TDualPanelCommandRun.RunDetachedFile(const AUri: string);
var
  Path, Cmd, Cwd: string;
begin
  Path := FileUriToPath(AUri);
  if (Path = '') or (not TFile.Exists(Path)) then
    Exit;
  if Pos(' ', Path) > 0 then
    Cmd := '"' + Path + '"'
  else
    Cmd := Path;
  Cwd := SafeDirectoryName(Path);
  if not ShellRunDetached(Cmd, Cwd) then
    FHost.OpenStub(skShellInfo, 'Run failed', Path)
  else
    FHost.NotifyChanged;
end;

procedure TDualPanelCommandRun.RunDetached;
var
  Text, Cwd: string;
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
begin
  Text := '';
  if FHost.CmdReady then
    Text := Trim(FHost.CmdText);
  Cwd := PanelCommandCwd;

  if Text <> '' then
  begin
    RunDetachedFromCmdLine(Text, Cwd);
    Exit;
  end;

  // Empty cmdline > file/folder under cursor (separate process, not ConPTY).
  if not FHost.GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    Exit;
  if Row.URI = '' then
    Exit;

  // Directories and ".." > open in Explorer (shell folder open).
  // ".." opens the current panel folder, not the parent (FAR Shift+Enter semantics).
  if Row.IsDirectory or Row.IsParent then
  begin
    RunDetachedOpenFolder(Row.URI, Tab, Row.IsParent);
    Exit;
  end;

  RunDetachedFile(Row.URI);
end;

end.
