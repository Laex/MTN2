library GitPlugin;

{ Native MTN2 plugin: git statistics of the active panel's folder in the status
  line (branch, ahead/behind, staged, changed, untracked, conflicts). A worker
  thread follows the active panel and runs git; the segment is set on the main
  thread through PostToMain. }

uses
  System.SysUtils, System.Classes, System.SyncObjs,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uGitStatus in 'uGitStatus.pas',
  uGitSettings in 'uGitSettings.pas',
  uGitRepo in 'uGitRepo.pas';

const
  cPluginId = 'mtn.git';
  /// <summary>The ABI the plugin needs to load, and the one that has SetStatusSegmentStyled:
  /// on an older host the colored segment is replaced by plain text.</summary>
  cNeededAbi = 4;
  cStyledSegmentAbi = 5;
  cSegmentId = 'git';
  cPollMs = 1000;

type
  TGitWorker = class(TThread)
  private
    FWake: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Wake;
  end;

var
  GHostApi: THostApiTable;
  GLock: TCriticalSection;
  GActiveUri: string;
  GPendingText: string;
  GPendingJson: string;
  GLabels: TGitLabels;
  GSettings: TGitSettings;
  GDirty: Boolean;
  GWorker: TGitWorker;

{ Colored parts when the host has them, the plain text otherwise. }
procedure SetSegment(const AText, AJson: string);
var
  Id, Seg, Text, Json: UTF8String;
begin
  Id := UTF8String(cPluginId);
  Seg := UTF8String(cSegmentId);
  if (AJson <> '') and (GHostApi.AbiVersion >= cStyledSegmentAbi) and
     Assigned(GHostApi.SetStatusSegmentStyled) then
  begin
    Json := UTF8String(AJson);
    GHostApi.SetStatusSegmentStyled(PAnsiChar(Id), PAnsiChar(Seg), PAnsiChar(Json));
  end
  else if Assigned(GHostApi.SetStatusSegment) then
  begin
    Text := UTF8String(AText);
    GHostApi.SetStatusSegment(PAnsiChar(Id), PAnsiChar(Seg), PAnsiChar(Text));
  end;
end;

function Tr(const AKey, ADefault: string): string;
var
  Id, Key, Def: UTF8String;
  Buf: array[0..255] of AnsiChar;
  Len: Int64;
begin
  Result := ADefault;
  if not Assigned(GHostApi.Translate) then
    Exit;
  Id := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Def := UTF8String(ADefault);
  Len := GHostApi.Translate(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(Def), @Buf[0], SizeOf(Buf));
  if (Len >= 0) and (Len < SizeOf(Buf)) then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

function GetSettingText(const AKey: string): string;
var
  Id, Key: UTF8String;
  Buf: array[0..127] of AnsiChar;
begin
  Result := '';
  if not Assigned(GHostApi.GetSetting) then
    Exit;
  Id := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Buf[0] := #0;
  if GHostApi.GetSetting(PAnsiChar(Id), PAnsiChar(Key), @Buf[0], SizeOf(Buf)) >= 0 then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

procedure PutSettingText(const AKey, AValue: string);
var
  Id, Key, Value: UTF8String;
begin
  if not Assigned(GHostApi.SetSetting) then
    Exit;
  Id := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Value := UTF8String(AValue);
  GHostApi.SetSetting(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(Value));
end;

{ Main thread: takes new settings into use; the worker rebuilds the segment. }
procedure ApplySettings(const ASettings: TGitSettings);
begin
  GLock.Enter;
  try
    GSettings := ASettings;
    GDirty := True;
  finally
    GLock.Leave;
  end;
  if Assigned(GWorker) then
    GWorker.Wake;
end;

procedure OnSettingsAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  New: TGitSettings;
begin
  try
    if not SameText(string(AControlId), 'ok') then
      Exit;
    New := GitSettingsFromDialogValues(UTF8ToString(AValuesJson));
    WriteGitSettings(New,
      procedure(AKey, AValue: string)
      begin
        PutSettingText(AKey, AValue);
      end);
    ApplySettings(New);
  except
  end;
end;

{ The "Settings" button of the plugins dialog. }
procedure OnConfigure(AUserData: Pointer); cdecl;
var
  Id, Json: UTF8String;
  Current: TGitSettings;
begin
  try
    if not Assigned(GHostApi.ShowDialog) then
      Exit;
    GLock.Enter;
    try
      Current := GSettings;
    finally
      GLock.Leave;
    end;
    Id := UTF8String(cPluginId);
    Json := UTF8String(GitSettingsDialogJson(Current,
      function(AKey, ADefault: string): string
      begin
        Result := Tr(AKey, ADefault);
      end));
    GHostApi.ShowDialog(PAnsiChar(Id), PAnsiChar(Json), @OnSettingsAnswer, nil);
  except
  end;
end;

{ Main thread: the words of the badges in the program language. }
procedure LoadLabels;
var
  L: TGitLabels;
begin
  L := DefaultGitLabels;
  L.Ahead := Tr('label.ahead', L.Ahead);
  L.Behind := Tr('label.behind', L.Behind);
  L.Staged := Tr('label.staged', L.Staged);
  L.Changed := Tr('label.changed', L.Changed);
  L.Untracked := Tr('label.untracked', L.Untracked);
  L.Conflicts := Tr('label.conflicts', L.Conflicts);
  L.Clean := Tr('label.clean', L.Clean);
  GLock.Enter;
  try
    GLabels := L;
    GDirty := True;
  finally
    GLock.Leave;
  end;
end;

{ Main thread: remembers the folder of the active panel. A screen without panels
  (a viewer, a dialog) keeps the last folder. }
procedure ReadActiveUri;
var
  Buf: UTF8String;
  Len: Int64;
  Uri: string;
begin
  if not Assigned(GHostApi.PanelInfo) then
    Exit;
  Len := GHostApi.PanelInfo(nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Buf, Len + 1);
  Len := GHostApi.PanelInfo(PAnsiChar(Buf), Length(Buf));
  if (Len <= 0) or (Len >= Length(Buf)) then
    Exit;
  Uri := ActivePanelUri(UTF8ToString(PAnsiChar(Buf)));
  GLock.Enter;
  try
    GActiveUri := Uri;
  finally
    GLock.Leave;
  end;
end;

procedure MainTick(AUserData: Pointer); cdecl;
begin
  try
    ReadActiveUri;
  except
  end;
end;

procedure MainApply(AUserData: Pointer); cdecl;
var
  Text, Json: string;
begin
  try
    GLock.Enter;
    try
      Text := GPendingText;
      Json := GPendingJson;
    finally
      GLock.Leave;
    end;
    SetSegment(Text, Json);
  except
  end;
end;

procedure OnHostEvent(AUserData: Pointer; ATopic, APayloadJson: PAnsiChar); cdecl;
begin
  try
    if SameText(string(ATopic), 'language.changed') then
      LoadLabels;
    ReadActiveUri;
    if Assigned(GWorker) then
      GWorker.Wake;
  except
  end;
end;

procedure PostToMain(ACallback: THostMainCallback);
var
  Id: UTF8String;
begin
  if not Assigned(GHostApi.PostToMain) then
    Exit;
  Id := UTF8String(cPluginId);
  GHostApi.PostToMain(PAnsiChar(Id), ACallback, nil);
end;

{ TGitWorker }

constructor TGitWorker.Create;
begin
  FWake := TEvent.Create(nil, False, False, '');
  inherited Create(False);
end;

destructor TGitWorker.Destroy;
begin
  FWake.Free;
  inherited;
end;

procedure TGitWorker.Wake;
begin
  FWake.SetEvent;
end;

procedure TGitWorker.Execute;
var
  Uri, LastUri, Dir, Text, Json, LastText: string;
  LastRun: UInt64;
  Status: TGitStatus;
  Labels: TGitLabels;
  Settings: TGitSettings;
  Dirty: Boolean;
  Cancelled: TFunc<Boolean>;
begin
  LastUri := #0;
  LastText := #0;
  LastRun := 0;
  Cancelled :=
    function: Boolean
    begin
      Result := Terminated;
    end;
  while not Terminated do
  begin
    PostToMain(MainTick);
    FWake.WaitFor(cPollMs);
    if Terminated then
      Break;
    GLock.Enter;
    try
      Uri := GActiveUri;
      Labels := GLabels;
      Settings := GSettings;
      Dirty := GDirty;
      GDirty := False;
    finally
      GLock.Leave;
    end;
    if Dirty then
      LastText := #0;
    if (Uri = LastUri) and (TThread.GetTickCount64 - LastRun < UInt64(Settings.RefreshSec) * 1000) and not Dirty then
      Continue;
    LastUri := Uri;
    Text := '';
    Json := '';
    Dir := '';
    if Uri.StartsWith('file:', True) then
      Dir := FileUriToPath(Uri);
    if (Dir <> '') and (ReadGitStatus(Dir, Cancelled, Status) = grOk) then
    begin
      Text := FormatGitStatus(Status);
      Json := GitStatusSpansJson(Status, Labels, Settings.Colors);
    end;
    LastRun := TThread.GetTickCount64;
    if Terminated then
      Break;
    // The text alone decides: the badges carry the same numbers; a new language
    // is a new text through Dirty.
    if Text <> LastText then
    begin
      LastText := Text;
      GLock.Enter;
      try
        GPendingText := Text;
        GPendingJson := Json;
      finally
        GLock.Leave;
      end;
      PostToMain(MainApply);
    end;
  end;
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cNeededAbi;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
var
  Id, Topic: UTF8String;
begin
  if AHostApi = nil then
    Exit(-1);
  GHostApi := AHostApi^;
  if not (Assigned(GHostApi.SetStatusSegment) and Assigned(GHostApi.PanelInfo) and
     Assigned(GHostApi.PostToMain) and Assigned(GHostApi.Subscribe)) then
    Exit(-1);
  GLock := TCriticalSection.Create;
  GLabels := DefaultGitLabels;
  GSettings := ReadGitSettings(
    function(AKey: string): string
    begin
      Result := GetSettingText(AKey);
    end);
  if Assigned(GHostApi.RegisterSettings) then
  begin
    Id := UTF8String(cPluginId);
    GHostApi.RegisterSettings(PAnsiChar(Id), @OnConfigure, nil);
  end;
  Id := UTF8String(cPluginId);
  Topic := UTF8String('panel.dir');
  GHostApi.Subscribe(PAnsiChar(Id), PAnsiChar(Topic), @OnHostEvent, nil);
  Topic := UTF8String('language.changed');
  GHostApi.Subscribe(PAnsiChar(Id), PAnsiChar(Topic), @OnHostEvent, nil);
  LoadLabels;
  ReadActiveUri;
  GWorker := TGitWorker.Create;
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  if Assigned(GWorker) then
  begin
    GWorker.Terminate;
    GWorker.Wake;
    GWorker.WaitFor;
    FreeAndNil(GWorker);
  end;
  SetSegment('', '');
  FreeAndNil(GLock);
  FillChar(GHostApi, SizeOf(GHostApi), 0);
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
