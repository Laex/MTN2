unit uEmbeddedWorkspaces;

{ Document and terminal workspace tabs. The window keeps the session list
  and asks this object to open, find and drop the embedded windows. A
  terminal is registered before its shell starts: the start can fail at
  once and ask to close the tab before Open returns. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uThemeTypes, uDualPanelTypes, uEditorWindow, uTerminalWorkspace, uBaseConsoleWindow;

type
  TEmbeddedIndexProc = procedure(AIndex: Integer) of object;
  TEmbeddedNotifyProc = procedure of object;
  TEmbeddedBoolProc = procedure(AValue: Boolean) of object;
  TEmbeddedBoolFunc = function: Boolean of object;
  TEmbeddedWorkspaceFunc = function: TDualPanelWorkspaceTab of object;

  TEmbeddedWorkspaceHost = record
    SelectWorkspace: TEmbeddedIndexProc;
    RemoveWorkspace: TEmbeddedIndexProc;
    NotifyChanged: TEmbeddedNotifyProc;
    SyncWindowTitle: TEmbeddedNotifyProc;
    SyncDirWatches: TEmbeddedNotifyProc;
    SetCmdFocused: TEmbeddedBoolProc;
    Alive: TEmbeddedBoolFunc;
    ActiveWorkspace: TEmbeddedWorkspaceFunc;
    OnCommandExecuted: TConsoleCommandEvent;
    OnGetCmdHistory: TConsoleGetHistoryEvent;
    OnRemoveCmdHistory: TConsoleCommandEvent;
    OnClearCmdHistory: TProc;
  end;

  TEmbeddedWorkspaces = class
  private
    FHost: TEmbeddedWorkspaceHost;
    FState: ^TDualPanelWindowState;
    FNextId: ^Cardinal;
    FDocuments: TObjectDictionary<Cardinal, TEditorWindow>;
    FTerminals: TObjectDictionary<Cardinal, TTerminalWorkspaceWindow>;
    procedure DocumentContentChanged(Sender: TObject);
    procedure DocumentCloseRequest(Sender: TObject);
    procedure TerminalContentChanged(Sender: TObject);
    procedure TerminalCloseRequest(Sender: TObject);
    procedure QueueFree(AObject: TObject);
  public
    constructor Create(var AState: TDualPanelWindowState; var ANextId: Cardinal;
      const AHost: TEmbeddedWorkspaceHost);
    destructor Destroy; override;
    function DocumentAt(AIndex: Integer): TEditorWindow;
    function TerminalAt(AIndex: Integer): TTerminalWorkspaceWindow;
    procedure ClearDocuments;
    procedure ClearTerminals;
    procedure DetachDocument(AId: Cardinal);
    procedure DetachTerminal(AId: Cardinal);
    procedure ShutdownTerminals;
    function TerminalCount: Integer;
    /// <summary>Captions of the terminals that run a program right now.</summary>
    function BusyTerminalCaptions: TArray<string>;
    procedure OpenBuiltIn(const AURI: string; AViewOnly: Boolean;
      const ATheme: IThemeRenderer);
    function OpenSurface(AHandle: Integer; const ATheme: IThemeRenderer): Boolean;
    procedure OpenTerminal(const AProfileId, ACwd, ACommand: string;
      const ATheme: IThemeRenderer; ACloseOnExit: Boolean);
    procedure RunInPanel(const AProfileId, ACwd, ACommand: string;
      const ATheme: IThemeRenderer; ACloseOnExit: Boolean);
    procedure CloseDocument(AIndex: Integer);
    procedure CloseTerminal(AIndex: Integer);
  end;

implementation

uses
  uDualPanelTabs, uFileHistory, uShellProfiles, uVfsTypes;

procedure TEmbeddedWorkspaces.QueueFree(AObject: TObject);
begin
  // The close request is still on this object's stack. Freeing it here
  // would release the object that is running the call.
  TThread.ForceQueue(nil,
    procedure
    begin
      AObject.Free;
    end);
end;

constructor TEmbeddedWorkspaces.Create(var AState: TDualPanelWindowState;
  var ANextId: Cardinal; const AHost: TEmbeddedWorkspaceHost);
begin
  inherited Create;
  FHost := AHost;
  FState := @AState;
  FNextId := @ANextId;
  FDocuments := TObjectDictionary<Cardinal, TEditorWindow>.Create([]);
  FTerminals := TObjectDictionary<Cardinal, TTerminalWorkspaceWindow>.Create([]);
end;

destructor TEmbeddedWorkspaces.Destroy;
begin
  ClearDocuments;
  ClearTerminals;
  FreeAndNil(FDocuments);
  FreeAndNil(FTerminals);
  inherited Destroy;
end;

function TEmbeddedWorkspaces.DocumentAt(AIndex: Integer): TEditorWindow;
var
  Ws: TDualPanelWorkspaceTab;
  Ed: TEditorWindow;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex > High(FState.WorkspaceTabs)) then
    Exit;
  Ws := FState.WorkspaceTabs[AIndex];
  if Ws.Kind <> wkDocument then
    Exit;
  if FDocuments.TryGetValue(Ws.Id, Ed) then
    Result := Ed;
end;

function TEmbeddedWorkspaces.TerminalAt(AIndex: Integer): TTerminalWorkspaceWindow;
var
  Ws: TDualPanelWorkspaceTab;
  Term: TTerminalWorkspaceWindow;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex > High(FState.WorkspaceTabs)) then
    Exit;
  Ws := FState.WorkspaceTabs[AIndex];
  if Ws.Kind <> wkTerminal then
    Exit;
  if FTerminals.TryGetValue(Ws.Id, Term) then
    Result := Term;
end;

procedure TEmbeddedWorkspaces.ClearDocuments;
var
  Pair: TPair<Cardinal, TEditorWindow>;
  Ed: TEditorWindow;
  Ids: TArray<Cardinal>;
  I, N: Integer;
begin
  if not Assigned(FDocuments) then
    Exit;
  N := 0;
  SetLength(Ids, FDocuments.Count);
  for Pair in FDocuments do
  begin
    Ids[N] := Pair.Key;
    Inc(N);
  end;
  for I := 0 to N - 1 do
  begin
    if FDocuments.TryGetValue(Ids[I], Ed) then
    begin
      Ed.OnCloseRequest := nil;
      Ed.OnContentChanged := nil;
      FDocuments.Remove(Ids[I]);
      Ed.Free;
    end;
  end;
  FDocuments.Clear;
end;

procedure TEmbeddedWorkspaces.ClearTerminals;
var
  Pair: TPair<Cardinal, TTerminalWorkspaceWindow>;
  Term: TTerminalWorkspaceWindow;
  Ids: TArray<Cardinal>;
  I, N: Integer;
begin
  if not Assigned(FTerminals) then
    Exit;
  N := 0;
  SetLength(Ids, FTerminals.Count);
  for Pair in FTerminals do
  begin
    Ids[N] := Pair.Key;
    Inc(N);
  end;
  for I := 0 to N - 1 do
  begin
    if FTerminals.TryGetValue(Ids[I], Term) then
    begin
      Term.OnCloseRequest := nil;
      Term.OnContentChanged := nil;
      FTerminals.Remove(Ids[I]);
      Term.Free;
    end;
  end;
  FTerminals.Clear;
end;

procedure TEmbeddedWorkspaces.DetachDocument(AId: Cardinal);
var
  Ed: TEditorWindow;
begin
  if not Assigned(FDocuments) or not FDocuments.TryGetValue(AId, Ed) then
    Exit;
  Ed.OnCloseRequest := nil;
  Ed.OnContentChanged := nil;
  FDocuments.Remove(AId);
  QueueFree(Ed);
end;

procedure TEmbeddedWorkspaces.DetachTerminal(AId: Cardinal);
var
  Term: TTerminalWorkspaceWindow;
begin
  if not Assigned(FTerminals) or not FTerminals.TryGetValue(AId, Term) then
    Exit;
  Term.OnCloseRequest := nil;
  Term.OnContentChanged := nil;
  FTerminals.Remove(AId);
  QueueFree(Term);
end;

function TEmbeddedWorkspaces.BusyTerminalCaptions: TArray<string>;
var
  Term: TTerminalWorkspaceWindow;
begin
  Result := nil;
  if not Assigned(FTerminals) then
    Exit;
  for Term in FTerminals.Values do
    if Term.HasRunningProgram then
      Result := Result + [Term.ProfileCaption];
end;

function TEmbeddedWorkspaces.TerminalCount: Integer;
begin
  if Assigned(FTerminals) then
    Result := FTerminals.Count
  else
    Result := 0;
end;

procedure TEmbeddedWorkspaces.ShutdownTerminals;
var
  Term: TTerminalWorkspaceWindow;
begin
  if not Assigned(FTerminals) then
    Exit;
  for Term in FTerminals.Values do
    if Assigned(Term) then
      Term.ShutdownForSessionEnd;
end;

procedure TEmbeddedWorkspaces.DocumentContentChanged(Sender: TObject);
var
  Ed: TEditorWindow;
  I: Integer;
begin
  if not FHost.Alive or not (Sender is TEditorWindow) then
    Exit;
  Ed := TEditorWindow(Sender);
  I := TDualPanelTabManager.FindWorkspaceIndexByKindAndId(
    FState.WorkspaceTabs, wkDocument, Ed.Id);
  if I >= 0 then
  begin
    if not FState.WorkspaceTabs[I].TitleCustom then
      FState.WorkspaceTabs[I].Title := Ed.TabCaption;
    FState.WorkspaceTabs[I].ViewOnly := Ed.ViewOnly;
    if I = FState.ActiveWorkspaceIndex then
      FHost.SyncWindowTitle;
  end;
  FHost.NotifyChanged;
end;

procedure TEmbeddedWorkspaces.DocumentCloseRequest(Sender: TObject);
var
  Ed, Found: TEditorWindow;
  I: Integer;
  IsStillRegistered: Boolean;
begin
  if not (Sender is TEditorWindow) then
    Exit;
  Ed := TEditorWindow(Sender);
  I := TDualPanelTabManager.FindWorkspaceIndexByKindAndId(
    FState.WorkspaceTabs, wkDocument, Ed.Id);
  IsStillRegistered := (I >= 0) and FDocuments.TryGetValue(Ed.Id, Found) and
    (Found = Ed);
  if IsStillRegistered then
  begin
    FHost.RemoveWorkspace(I);
    FHost.NotifyChanged;
  end;
end;

procedure TEmbeddedWorkspaces.CloseDocument(AIndex: Integer);
var
  Ws: TDualPanelWorkspaceTab;
  Ed: TEditorWindow;
begin
  Ws := FState.WorkspaceTabs[AIndex];
  if FDocuments.TryGetValue(Ws.Id, Ed) then
  begin
    // Activate so AskSave dialog paints on the document tab.
    if AIndex <> FState.ActiveWorkspaceIndex then
      FHost.SelectWorkspace(AIndex);
    Ed.BeginClose;
  end
  else
    FHost.RemoveWorkspace(AIndex);
end;

procedure TEmbeddedWorkspaces.OpenBuiltIn(const AURI: string; AViewOnly: Boolean;
  const ATheme: IThemeRenderer);
var
  I: Integer;
  Ws: TDualPanelWorkspaceTab;
  Ed: TEditorWindow;
  Cap: string;
begin
  if AURI = '' then
    Exit;
  // Alt+F11 history: every F3/F4, re-activating an already open tab included.
  FileHistoryPush(AURI, not AViewOnly);
  I := TDualPanelTabManager.FindDocumentWorkspaceIndex(
    FState.WorkspaceTabs, AURI, AViewOnly);
  if I >= 0 then
  begin
    FHost.SelectWorkspace(I);
    FHost.NotifyChanged;
    Exit;
  end;

  Cap := FileUriTitle(AURI);
  if Cap = '' then
    Cap := 'Document';
  Ed := TEditorWindow.Create(ATheme, FNextId^);
  Ed.Embedded := True;
  Ed.OnContentChanged := DocumentContentChanged;
  Ed.OnCloseRequest := DocumentCloseRequest;
  Ed.Open(AURI, AViewOnly);

  Ws := TDualPanelTabManager.MakeEmbeddedWorkspaceTab(
    FNextId^, TDualPanelTabManager.EmbeddedDocumentTitle(Ed.TabCaption, Cap),
    wkDocument, FHost.ActiveWorkspace.Id);
  Inc(FNextId^);
  Ws.DocURI := AURI;
  Ws.ViewOnly := AViewOnly;

  FDocuments.AddOrSetValue(Ws.Id, Ed);
  TDualPanelTabManager.InsertWorkspaceAfterActive(
    FState.WorkspaceTabs, FState.ActiveWorkspaceIndex, Ws);
  FHost.SyncWindowTitle;
  FHost.SyncDirWatches;
  FHost.NotifyChanged;
end;

function TEmbeddedWorkspaces.OpenSurface(AHandle: Integer;
  const ATheme: IThemeRenderer): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
  Ed: TEditorWindow;
  Uri: string;
begin
  Uri := 'plugin-surface:' + IntToStr(AHandle);
  Ed := TEditorWindow.Create(ATheme, FNextId^);
  Ed.Embedded := True;
  Ed.OnContentChanged := DocumentContentChanged;
  Ed.OnCloseRequest := DocumentCloseRequest;
  Ed.OpenSurface(AHandle);

  Ws := TDualPanelTabManager.MakeEmbeddedWorkspaceTab(
    FNextId^, TDualPanelTabManager.EmbeddedDocumentTitle(Ed.TabCaption, 'Picture'),
    wkDocument, FHost.ActiveWorkspace.Id);
  Inc(FNextId^);
  Ws.DocURI := Uri;
  Ws.ViewOnly := True;

  FDocuments.AddOrSetValue(Ws.Id, Ed);
  TDualPanelTabManager.InsertWorkspaceAfterActive(
    FState.WorkspaceTabs, FState.ActiveWorkspaceIndex, Ws);
  FHost.SyncWindowTitle;
  FHost.NotifyChanged;
  Result := True;
end;

procedure TEmbeddedWorkspaces.TerminalContentChanged(Sender: TObject);
var
  Term, Found: TTerminalWorkspaceWindow;
  I: Integer;
  IsActiveTerminalTab: Boolean;
begin
  if not FHost.Alive or not (Sender is TTerminalWorkspaceWindow) then
    Exit;
  Term := TTerminalWorkspaceWindow(Sender);
  I := TDualPanelTabManager.FindWorkspaceIndexByKindAndId(
    FState.WorkspaceTabs, wkTerminal, Term.Id);
  IsActiveTerminalTab := (I >= 0) and FTerminals.TryGetValue(Term.Id, Found) and
    (Found = Term) and (I = FState.ActiveWorkspaceIndex);
  if IsActiveTerminalTab then
    FHost.SyncWindowTitle;
  FHost.NotifyChanged;
end;

procedure TEmbeddedWorkspaces.TerminalCloseRequest(Sender: TObject);
var
  Term, Found: TTerminalWorkspaceWindow;
  I: Integer;
  IsStillRegistered: Boolean;
begin
  if not (Sender is TTerminalWorkspaceWindow) then
    Exit;
  Term := TTerminalWorkspaceWindow(Sender);
  I := TDualPanelTabManager.FindWorkspaceIndexByKindAndId(
    FState.WorkspaceTabs, wkTerminal, Term.Id);
  IsStillRegistered := (I >= 0) and FTerminals.TryGetValue(Term.Id, Found) and
    (Found = Term);
  if IsStillRegistered then
  begin
    FHost.RemoveWorkspace(I);
    FHost.NotifyChanged;
  end;
end;

procedure TEmbeddedWorkspaces.CloseTerminal(AIndex: Integer);
var
  Ws: TDualPanelWorkspaceTab;
  Term: TTerminalWorkspaceWindow;
begin
  Ws := FState.WorkspaceTabs[AIndex];
  // No ask-to-close flow: CloseWorkspace fires OnCloseRequest synchronously
  // (TBaseConsoleWindow.DoClose), which TerminalCloseRequest turns into
  // RemoveWorkspace for this tab.
  if FTerminals.TryGetValue(Ws.Id, Term) then
    Term.CloseWorkspace
  else
    FHost.RemoveWorkspace(AIndex);
end;

procedure TEmbeddedWorkspaces.OpenTerminal(const AProfileId, ACwd, ACommand: string;
  const ATheme: IThemeRenderer; ACloseOnExit: Boolean);
var
  I: Integer;
  Ws: TDualPanelWorkspaceTab;
  Term: TTerminalWorkspaceWindow;
  Profiles: TShellProfileArray;
  ProfTitle: string;
begin
  if AProfileId = '' then
    Exit;
  FHost.SetCmdFocused(False);

  ProfTitle := AProfileId;
  Profiles := EnumerateShellProfiles;
  for I := 0 to High(Profiles) do
    if Profiles[I].Id = AProfileId then
    begin
      ProfTitle := Profiles[I].Title;
      Break;
    end;

  Term := TTerminalWorkspaceWindow.Create(ATheme, FNextId^);
  Term.CloseOnExit := ACloseOnExit;
  Term.OnContentChanged := TerminalContentChanged;
  Term.OnCloseRequest := TerminalCloseRequest;
  Term.OnCommandExecuted := FHost.OnCommandExecuted;
  Term.OnGetCmdHistory := FHost.OnGetCmdHistory;
  Term.OnRemoveCmdHistory := FHost.OnRemoveCmdHistory;
  Term.OnClearCmdHistory := FHost.OnClearCmdHistory;

  Ws := TDualPanelTabManager.MakeEmbeddedWorkspaceTab(
    FNextId^, ProfTitle, wkTerminal, FHost.ActiveWorkspace.Id);
  Inc(FNextId^);
  Ws.TermProfileId := AProfileId;

  // Register the tab before Start: unlike Ed.Open, PTY Start can fail
  // synchronously and fire ProcessExited -> DoCloseWorkspace ->
  // OnCloseRequest -> TerminalCloseRequest before control returns here,
  // and that handler needs to find this tab to clean it up.
  FTerminals.AddOrSetValue(Ws.Id, Term);
  TDualPanelTabManager.InsertWorkspaceAfterActive(
    FState.WorkspaceTabs, FState.ActiveWorkspaceIndex, Ws);

  Term.Start(AProfileId, ACwd);
  // Start may already have torn the tab down via TerminalCloseRequest
  // (which picks its own fallback active tab). Do not touch the active
  // index again if that happened.
  if not FTerminals.ContainsKey(Ws.Id) then
    Exit;
  // The shell buffers what is typed before its first prompt.
  if ACommand <> '' then
    Term.SendCommand(ACommand);

  FHost.SyncWindowTitle;
  FHost.SyncDirWatches;
  FHost.NotifyChanged;
end;

procedure TEmbeddedWorkspaces.RunInPanel(const AProfileId, ACwd, ACommand: string;
  const ATheme: IThemeRenderer; ACloseOnExit: Boolean);
var
  I: Integer;
  Ws: TDualPanelWorkspaceTab;
  Term: TTerminalWorkspaceWindow;
begin
  Ws := FHost.ActiveWorkspace;
  if Ws.Kind = wkPanels then
    for I := 0 to High(FState.WorkspaceTabs) do
      if (FState.WorkspaceTabs[I].Kind = wkTerminal) and
         (FState.WorkspaceTabs[I].OriginWorkspaceId = Ws.Id) and
         (FState.WorkspaceTabs[I].TermProfileId = AProfileId) and
         FTerminals.TryGetValue(FState.WorkspaceTabs[I].Id, Term) and
         Term.IsIdle then
      begin
        FHost.SetCmdFocused(False);
        Term.RunInDir(ACwd, ACommand);
        FHost.SelectWorkspace(I);
        FHost.NotifyChanged;
        Exit;
      end;
  OpenTerminal(AProfileId, ACwd, ACommand, ATheme, ACloseOnExit);
end;

end.
