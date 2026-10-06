unit uPluginServices;

{ Services of the running program that plugins can call: the document in the
  viewer / editor, the file panels, the clipboard, notices and host events.

  The window that owns the documents and panels registers its handlers with
  SetPluginHostServices; a service without a handler (tests, tools, a window
  that is not up yet) reports failure. The clipboard and notices need no
  window.

  Host events: the program publishes "doc.opened", "doc.saved" and
  "doc.closed" (payload JSON with the document "uri"); a plugin subscribes with
  PluginSubscribe and is not called after PluginEventsUnregister.

  Main thread only. }

interface

uses
  System.SysUtils;

type
  /// <summary>Text of the active document: AWhat 0 = selection, 1 = whole
  /// document (lines joined with LF), 2 = the line with the cursor. False when
  /// there is no text document or it has no such text.</summary>
  TPluginDocGetText = reference to function(AWhat: Integer; out AText: string): Boolean;
  /// <summary>Replaces that text (0 = selection, or inserts at the cursor when
  /// nothing is selected; 1 = whole document; 2 = the cursor line) as one undo
  /// step. False when there is no editable text document.</summary>
  TPluginDocReplace = reference to function(AWhat: Integer; const AText: string): Boolean;
  TPluginDocSetCursor = reference to function(ARow, ACol: Integer): Boolean;
  /// <summary>Opens AURI in a panel: ASide 0 = left, 1 = right, -1 = the active one.</summary>
  TPluginPanelGoto = reference to function(ASide: Integer; const AURI: string): Boolean;
  /// <summary>JSON list of a panel's rows (ASide as for TPluginPanelGoto).</summary>
  TPluginPanelList = reference to function(ASide: Integer): string;
  /// <summary>Puts the panel cursor on the row AURI; for a row in another folder the
  /// panel goes to that folder first and the cursor follows when it is listed.</summary>
  TPluginPanelSetCursor = reference to function(ASide: Integer; const AURI: string): Boolean;
  /// <summary>Selection of a panel: AMode 0 = select the rows matching the mask AArg,
  /// 1 = unselect them, 2 = clear the selection, 3 = select the row AArg (URI),
  /// 4 = unselect it. Folders are left out of the mask modes.</summary>
  TPluginPanelSelect = reference to function(ASide, AMode: Integer; const AArg: string): Boolean;
  /// <summary>Selects from (ARow1, ACol1) to (ARow2, ACol2), 0-based; the cursor goes to the end.</summary>
  TPluginDocSetSelection = reference to function(ARow1, ACol1, ARow2, ACol2: Integer): Boolean;
  TPluginDocLine = reference to function(AIndex: Integer; out AText: string): Boolean;

  TPluginHostServices = record
    /// <summary>JSON about the active text document, '' when there is none.</summary>
    DocInfo: TFunc<string>;
    DocGetText: TPluginDocGetText;
    DocReplace: TPluginDocReplace;
    DocSetCursor: TPluginDocSetCursor;
    /// <summary>JSON about both file panels, '' when the panels are not on screen.</summary>
    PanelInfo: TFunc<string>;
    PanelGoto: TPluginPanelGoto;
    PanelRefresh: TProc;
    PanelList: TPluginPanelList;
    PanelSetCursor: TPluginPanelSetCursor;
    PanelSelect: TPluginPanelSelect;
    DocSetSelection: TPluginDocSetSelection;
    DocLine: TPluginDocLine;
  end;

  /// <summary>Handler of a host event: topic and payload JSON.</summary>
  TPluginEventHandler = reference to procedure(const ATopic, APayloadJson: string);

procedure SetPluginHostServices(const AServices: TPluginHostServices);

function PluginDocInfo(out AJson: string): Boolean;
function PluginDocGetText(AWhat: Integer; out AText: string): Boolean;
function PluginDocReplace(AWhat: Integer; const AText: string): Boolean;
function PluginDocSetCursor(ARow, ACol: Integer): Boolean;
function PluginPanelInfo(out AJson: string): Boolean;
function PluginPanelGoto(ASide: Integer; const AURI: string): Boolean;
function PluginPanelRefresh: Boolean;
function PluginPanelList(ASide: Integer; out AJson: string): Boolean;
function PluginPanelSetCursor(ASide: Integer; const AURI: string): Boolean;
function PluginPanelSelect(ASide, AMode: Integer; const AArg: string): Boolean;
function PluginDocSetSelection(ARow1, ACol1, ARow2, ACol2: Integer): Boolean;
function PluginDocLine(AIndex: Integer; out AText: string): Boolean;

/// <summary>Plain text on the system clipboard; False when it holds none.</summary>
function PluginClipboardGet(out AText: string): Boolean;
function PluginClipboardSet(const AText: string): Boolean;

/// <summary>Shows AText as a notice (AKind 0 = information, 1 = warning).</summary>
procedure PluginShowMessage(const AText: string; AKind: Integer);

/// <summary>JSON about the program: version, language.</summary>
function PluginHostInfoJson: string;

/// <summary>Calls AHandler for every event of ATopic ("*" = all). The same
/// plugin subscribing to the same topic again replaces its handler.</summary>
procedure PluginSubscribe(const APluginId, ATopic: string; const AHandler: TPluginEventHandler);
procedure PluginEventsUnregister(const APluginId: string);
/// <summary>Tells the subscribers; a handler that raises does not stop the others.</summary>
procedure PluginPublishEvent(const ATopic, APayloadJson: string);
/// <summary>"doc.*" event payload for a document URI.</summary>
function PluginUriPayload(const AURI: string): string;
/// <summary>Some plugin listens: the program can skip building events nobody reads.</summary>
function PluginHasSubscribers: Boolean;

/// <summary>Changes whenever the plugin goes; a callback that remembers the value
/// from when it was scheduled and finds another one on arrival must be dropped.</summary>
function PluginGenerationOf(const APluginId: string): Integer;

/// <summary>Runs ACallback on the main thread. Safe to call from any thread. The call is
/// dropped when the plugin was unloaded in the meantime.</summary>
procedure PluginPostToMain(const APluginId: string; const ACallback: TProc);
/// <summary>A progress notice that stays up until PluginProgressEnd (APercent below 0 =
/// no percentage). One per APluginId + AId; main thread only.</summary>
procedure PluginProgressSet(const APluginId, AId, AText: string; APercent: Integer);
procedure PluginProgressEnd(const APluginId, AId: string);

implementation

uses
  System.Classes, System.Rtti, System.SyncObjs, System.Math, System.Generics.Collections,
  System.JSON,
  FMX.Platform, FMX.Types,
  uNotice, uStrings, uUpdater;

type
  TSubscription = record
    PluginId: string;
    Topic: string;
    Handler: TPluginEventHandler;
  end;

var
  GServices: TPluginHostServices;
  GSubscriptions: TList<TSubscription>;
  // Changes when a plugin goes; work posted by that plugin earlier is dropped.
  GGenerations: TDictionary<string, Integer>;
  GGenerationLock: TCriticalSection;

procedure SetPluginHostServices(const AServices: TPluginHostServices);
begin
  GServices := AServices;
end;

function PluginDocInfo(out AJson: string): Boolean;
begin
  AJson := '';
  if Assigned(GServices.DocInfo) then
    AJson := GServices.DocInfo();
  Result := AJson <> '';
end;

function PluginDocGetText(AWhat: Integer; out AText: string): Boolean;
begin
  AText := '';
  Result := Assigned(GServices.DocGetText) and (AWhat >= 0) and (AWhat <= 2) and
    GServices.DocGetText(AWhat, AText);
end;

function PluginDocReplace(AWhat: Integer; const AText: string): Boolean;
begin
  Result := Assigned(GServices.DocReplace) and (AWhat >= 0) and (AWhat <= 2) and
    GServices.DocReplace(AWhat, AText);
end;

function PluginDocSetCursor(ARow, ACol: Integer): Boolean;
begin
  Result := Assigned(GServices.DocSetCursor) and GServices.DocSetCursor(ARow, ACol);
end;

function PluginPanelInfo(out AJson: string): Boolean;
begin
  AJson := '';
  if Assigned(GServices.PanelInfo) then
    AJson := GServices.PanelInfo();
  Result := AJson <> '';
end;

function PluginPanelGoto(ASide: Integer; const AURI: string): Boolean;
begin
  Result := Assigned(GServices.PanelGoto) and (AURI <> '') and (ASide >= -1) and (ASide <= 1) and
    GServices.PanelGoto(ASide, AURI);
end;

function PluginPanelRefresh: Boolean;
begin
  Result := Assigned(GServices.PanelRefresh);
  if Result then
    GServices.PanelRefresh();
end;

function PluginPanelList(ASide: Integer; out AJson: string): Boolean;
begin
  AJson := '';
  if Assigned(GServices.PanelList) and (ASide >= -1) and (ASide <= 1) then
    AJson := GServices.PanelList(ASide);
  Result := AJson <> '';
end;

function PluginPanelSetCursor(ASide: Integer; const AURI: string): Boolean;
begin
  Result := Assigned(GServices.PanelSetCursor) and (AURI <> '') and (ASide >= -1) and
    (ASide <= 1) and GServices.PanelSetCursor(ASide, AURI);
end;

function PluginPanelSelect(ASide, AMode: Integer; const AArg: string): Boolean;
begin
  Result := Assigned(GServices.PanelSelect) and (ASide >= -1) and (ASide <= 1) and
    (AMode >= 0) and (AMode <= 4) and ((AMode = 2) or (AArg <> '')) and
    GServices.PanelSelect(ASide, AMode, AArg);
end;

function PluginDocSetSelection(ARow1, ACol1, ARow2, ACol2: Integer): Boolean;
begin
  Result := Assigned(GServices.DocSetSelection) and
    GServices.DocSetSelection(ARow1, ACol1, ARow2, ACol2);
end;

function PluginDocLine(AIndex: Integer; out AText: string): Boolean;
begin
  AText := '';
  Result := Assigned(GServices.DocLine) and (AIndex >= 0) and GServices.DocLine(AIndex, AText);
end;

function PluginClipboardGet(out AText: string): Boolean;
var
  Svc: IFMXClipboardService;
  V: TValue;
begin
  AText := '';
  if not TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
    Exit(False);
  V := Svc.GetClipboard;
  if not V.IsEmpty and V.IsType<string> then
    AText := V.AsString;
  Result := AText <> '';
end;

function PluginClipboardSet(const AText: string): Boolean;
var
  Svc: IFMXClipboardService;
begin
  Result := TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc);
  if Result then
    Svc.SetClipboard(AText);
end;

procedure PluginShowMessage(const AText: string; AKind: Integer);
begin
  if AText = '' then
    Exit;
  if AKind = 1 then
    Notice('%s', AText, tkWarning)
  else
    Notice('%s', AText, tkInfo);
end;

function PluginHostInfoJson: string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('version', AppVersionString);
    Obj.AddPair('language', CurrentLocale);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

procedure PluginSubscribe(const APluginId, ATopic: string; const AHandler: TPluginEventHandler);
var
  Sub: TSubscription;
  I: Integer;
begin
  if (Trim(APluginId) = '') or (Trim(ATopic) = '') or not Assigned(AHandler) then
    Exit;
  Sub.PluginId := LowerCase(Trim(APluginId));
  Sub.Topic := Trim(ATopic);
  Sub.Handler := AHandler;
  for I := 0 to GSubscriptions.Count - 1 do
    if (GSubscriptions[I].PluginId = Sub.PluginId) and SameText(GSubscriptions[I].Topic, Sub.Topic) then
    begin
      GSubscriptions[I] := Sub;
      Exit;
    end;
  GSubscriptions.Add(Sub);
end;

function GenerationOf(const AKey: string): Integer;
begin
  GGenerationLock.Enter;
  try
    if not GGenerations.TryGetValue(AKey, Result) then
      Result := 0;
  finally
    GGenerationLock.Leave;
  end;
end;

function PluginGenerationOf(const APluginId: string): Integer;
begin
  Result := GenerationOf(LowerCase(Trim(APluginId)));
end;

function PluginHasSubscribers: Boolean;
begin
  Result := GSubscriptions.Count > 0;
end;

procedure PluginPostToMain(const APluginId: string; const ACallback: TProc);
var
  Key: string;
  Gen: Integer;
begin
  Key := LowerCase(Trim(APluginId));
  if (Key = '') or not Assigned(ACallback) then
    Exit;
  Gen := GenerationOf(Key);
  // Always queued, also from the main thread: the caller finishes before the work runs.
  TThread.ForceQueue(nil,
    procedure
    begin
      if GenerationOf(Key) <> Gen then
        Exit;
      try
        ACallback();
      except
        // A faulty plugin callback must not break the message loop.
      end;
    end);
end;

procedure PluginProgressSet(const APluginId, AId, AText: string; APercent: Integer);
var
  Req: TNoticeRequest;
begin
  if (Trim(APluginId) = '') or (AText = '') then
    Exit;
  Req := TNoticeRequest.Make('%s', AText);
  if APercent >= 0 then
    Req.Arg := Format('%s  %d%%', [AText, Min(APercent, 100)]);
  Req.Tag := LowerCase(Trim(APluginId)) + ':' + AId;
  // Stays up until the plugin ends it (a notice shows for a few seconds otherwise).
  Req.DurationMs := 600000;
  Req.Always := True;
  NoticeRequest(Req);
end;

procedure PluginProgressEnd(const APluginId, AId: string);
begin
  NoticeDismiss(LowerCase(Trim(APluginId)) + ':' + AId);
end;

procedure PluginEventsUnregister(const APluginId: string);
var
  Key: string;
  I: Integer;
begin
  Key := LowerCase(Trim(APluginId));
  GGenerationLock.Enter;
  try
    GGenerations.AddOrSetValue(Key, GenerationOf(Key) + 1);
  finally
    GGenerationLock.Leave;
  end;
  for I := GSubscriptions.Count - 1 downto 0 do
    if GSubscriptions[I].PluginId = Key then
      GSubscriptions.Delete(I);
end;

procedure PluginPublishEvent(const ATopic, APayloadJson: string);
var
  Snapshot: TArray<TSubscription>;
  Sub: TSubscription;

  // A plugin unloaded by an earlier handler of this event is not called.
  function StillSubscribed: Boolean;
  var
    I: Integer;
  begin
    for I := 0 to GSubscriptions.Count - 1 do
      if (GSubscriptions[I].PluginId = Sub.PluginId) and SameText(GSubscriptions[I].Topic, Sub.Topic) then
        Exit(True);
    Result := False;
  end;

begin
  if GSubscriptions.Count = 0 then
    Exit;
  Snapshot := GSubscriptions.ToArray;
  for Sub in Snapshot do
    if ((Sub.Topic = '*') or SameText(Sub.Topic, ATopic)) and StillSubscribed then
      try
        Sub.Handler(ATopic, APayloadJson);
      except
        // A faulty plugin handler must not break the program or the other subscribers.
      end;
end;

function PluginUriPayload(const AURI: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('uri', AURI);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

initialization
  GSubscriptions := TList<TSubscription>.Create;
  GGenerations := TDictionary<string, Integer>.Create;
  GGenerationLock := TCriticalSection.Create;

finalization
  GServices := Default(TPluginHostServices);
  FreeAndNil(GSubscriptions);
  FreeAndNil(GGenerations);
  FreeAndNil(GGenerationLock);

end.
