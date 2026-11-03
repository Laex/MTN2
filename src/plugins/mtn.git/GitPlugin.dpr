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
  uGitRepo in 'uGitRepo.pas',
  uGitDiff in 'uGitDiff.pas',
  uGitMarks in 'uGitMarks.pas';

const
  cPluginId = 'mtn.git';
  /// <summary>The ABI the plugin needs to load, and the one that has SetStatusSegmentStyled:
  /// on an older host the colored segment is replaced by plain text.</summary>
  cNeededAbi = 4;
  cStyledSegmentAbi = 5;
  cOpenDocumentAbi = 6;
  cRowDecorationsAbi = 6;
  cJobsAbi = 7;
  cDiffJobKey = 'git.diff';
  cDiffCommand = 'git.diff';
  cBlameCommand = 'git.blame';
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
  /// <summary>The diff thread's answer for the main thread: the temp file to open,
  /// or the notice to show.</summary>
  GDiffFile: string;
  GDiffNotice: string;
  GDiffBusy: Boolean;
  /// <summary>Set on the main thread when the host job is cancelled; the diff thread polls it.</summary>
  GDiffCancel: Integer;
  GDiffJob: Boolean;
  /// <summary>Local folders of both panels, as the panels report them.</summary>
  GFolders: TArray<string>;
  /// <summary>Marks the worker computed (folder URI, JSON) and the folders the
  /// host holds marks for.</summary>
  GPendingMarkUris: TArray<string>;
  GPendingMarkJson: TArray<string>;
  GAppliedMarkUris: TArray<string>;

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

procedure ShowNotice(const AText: string; AKind: Int64);
var
  Text: UTF8String;
begin
  if not Assigned(GHostApi.ShowMessage) then
    Exit;
  Text := UTF8String(AText);
  GHostApi.ShowMessage(PAnsiChar(Text), AKind);
end;

function ReadPanelInfo: string;
var
  Buf: UTF8String;
  Len: Int64;
begin
  Result := '';
  if not Assigned(GHostApi.PanelInfo) then
    Exit;
  Len := GHostApi.PanelInfo(nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Buf, Len + 1);
  Len := GHostApi.PanelInfo(PAnsiChar(Buf), Length(Buf));
  if (Len > 0) and (Len < Length(Buf)) then
    Result := UTF8ToString(PAnsiChar(Buf));
end;

function HostHasJobs: Boolean;
begin
  Result := (GHostApi.AbiVersion >= cJobsAbi) and Assigned(GHostApi.JobBegin) and
    Assigned(GHostApi.JobEnd);
end;

procedure OnDiffJobCancel(AUserData: Pointer); cdecl;
begin
  TInterlocked.Exchange(GDiffCancel, 1);
end;

{ Main thread: lists the diff in the host's job list, where it can be cancelled. }
procedure BeginDiffJob(const ATitle: string);
var
  Plugin, Key, Title: UTF8String;
begin
  TInterlocked.Exchange(GDiffCancel, 0);
  GDiffJob := HostHasJobs;
  if not GDiffJob then
    Exit;
  Plugin := UTF8String(cPluginId);
  Key := UTF8String(cDiffJobKey);
  Title := UTF8String(ATitle);
  GHostApi.JobBegin(PAnsiChar(Plugin), PAnsiChar(Key), PAnsiChar(Title), @OnDiffJobCancel, nil);
end;

procedure EndDiffJob;
var
  Plugin, Key: UTF8String;
begin
  if not GDiffJob then
    Exit;
  GDiffJob := False;
  Plugin := UTF8String(cPluginId);
  Key := UTF8String(cDiffJobKey);
  GHostApi.JobEnd(PAnsiChar(Plugin), PAnsiChar(Key));
end;

{ Main thread: the diff is ready - open it in the built-in viewer. }
procedure MainShowDiff(AUserData: Pointer); cdecl;
var
  FileName, Notice: string;
  Uri: UTF8String;
begin
  try
    EndDiffJob;
    if TInterlocked.CompareExchange(GDiffCancel, 0, 0) <> 0 then
    begin
      GLock.Enter;
      try
        GDiffFile := '';
        GDiffNotice := '';
        GDiffBusy := False;
      finally
        GLock.Leave;
      end;
      ShowNotice(Tr('msg.cancelled', 'Cancelled.'), 0);
      Exit;
    end;
    GLock.Enter;
    try
      FileName := GDiffFile;
      Notice := GDiffNotice;
      GDiffFile := '';
      GDiffNotice := '';
      GDiffBusy := False;
    finally
      GLock.Leave;
    end;
    if FileName <> '' then
    begin
      Uri := UTF8String(PathToFileUri(FileName));
      if GHostApi.OpenDocument(PAnsiChar(Uri), 0) <> 0 then
        ShowNotice(Tr('msg.openFailed', 'The diff could not be shown.'), 1);
    end
    else if Notice <> '' then
      ShowNotice(Notice, 0);
  except
  end;
end;

type
  TGitDiffThread = class(TThread)
  private
    FPath, FName: string;
    FIsDir, FBlame: Boolean;
    FNoRepo, FNoChanges, FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const APath: string; AIsDir, ABlame: Boolean;
      const ANoRepo, ANoChanges, AError: string);
  end;

constructor TGitDiffThread.Create(const APath: string; AIsDir, ABlame: Boolean;
  const ANoRepo, ANoChanges, AError: string);
begin
  FPath := APath;
  FIsDir := AIsDir;
  FBlame := ABlame;
  FName := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
  FNoRepo := ANoRepo;
  FNoChanges := ANoChanges;
  FError := AError;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TGitDiffThread.Execute;
var
  Text, FileName, Notice: string;
  R: TGitDiffResult;
begin
  FileName := '';
  Notice := '';
  try
    if FBlame then
      R := ReadGitBlame(FPath,
        function: Boolean
        begin
          Result := Terminated or (TInterlocked.CompareExchange(GDiffCancel, 0, 0) <> 0);
        end, Text)
    else
      R := ReadGitDiff(FPath, FIsDir,
        function: Boolean
        begin
          Result := Terminated or (TInterlocked.CompareExchange(GDiffCancel, 0, 0) <> 0);
        end, Text);
    case R of
      gdOk:
        if FBlame then
          FileName := WriteBlameFile(FName, Text)
        else
          FileName := WriteDiffFile(FName, Text);
      gdNoChanges: Notice := FNoChanges;
      gdNotRepo: Notice := FNoRepo;
    else
      Notice := FError;
    end;
  except
    Notice := FError;
  end;
  GLock.Enter;
  try
    GDiffFile := FileName;
    GDiffNotice := Notice;
  finally
    GLock.Leave;
  end;
  if Assigned(GHostApi.PostToMain) then
    GHostApi.PostToMain(PAnsiChar(UTF8String(cPluginId)), MainShowDiff, nil);
end;

{ The change (or, with ABlame, the line authors) of the row under the cursor, in the
  viewer. }
procedure StartView(ABlame: Boolean);
var
  Uri: string;
  IsDir: Boolean;
begin
  try
    if (GHostApi.AbiVersion < cOpenDocumentAbi) or not Assigned(GHostApi.OpenDocument) then
    begin
      ShowNotice(Tr('msg.needNewer', 'This needs a newer MTN2.'), 1);
      Exit;
    end;
    if not ActivePanelCursor(ReadPanelInfo, Uri, IsDir) or not Uri.StartsWith('file:', True) or
       (ABlame and IsDir) then
    begin
      ShowNotice(Tr('msg.noFile', 'Put the cursor on a file or folder of a local git folder.'), 0);
      Exit;
    end;
    GLock.Enter;
    try
      if GDiffBusy then
        Exit;
      GDiffBusy := True;
    finally
      GLock.Leave;
    end;
    if ABlame then
    begin
      BeginDiffJob(Tr('msg.blameJob', 'Git blame'));
      TGitDiffThread.Create(FileUriToPath(Uri), False, True,
        Tr('msg.notRepo', 'This folder is not in a git working tree.'),
        Tr('msg.noBlame', 'Git has no history for this file.'),
        Tr('msg.error', 'git did not answer.'));
    end
    else
    begin
      BeginDiffJob(Tr('msg.diffJob', 'Git diff'));
      TGitDiffThread.Create(FileUriToPath(Uri), IsDir, False,
        Tr('msg.notRepo', 'This folder is not in a git working tree.'),
        Tr('msg.noChanges', 'No changes against HEAD.'),
        Tr('msg.error', 'git did not answer.'));
    end;
  except
  end;
end;

{ The "Git diff" command. }
procedure CmdDiff(AUserData: Pointer); cdecl;
begin
  StartView(False);
end;

{ The "Git blame" command. }
procedure CmdBlame(AUserData: Pointer); cdecl;
begin
  StartView(True);
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
    GFolders := PanelFolderUris(UTF8ToString(PAnsiChar(Buf)));
  finally
    GLock.Leave;
  end;
end;

function HasUri(const AUris: TArray<string>; const AUri: string): Boolean;
var
  U: string;
begin
  for U in AUris do
    if U = AUri then
      Exit(True);
  Result := False;
end;

function MarksAvailable: Boolean;
begin
  Result := (GHostApi.AbiVersion >= cRowDecorationsAbi) and Assigned(GHostApi.SetRowDecorations);
end;

procedure SetMarks(const AUri, AJson: string);
var
  Id, Uri, Json: UTF8String;
begin
  Id := UTF8String(cPluginId);
  Uri := UTF8String(AUri);
  Json := UTF8String(AJson);
  GHostApi.SetRowDecorations(PAnsiChar(Id), PAnsiChar(Uri), PAnsiChar(Json));
end;

{ Main thread: hands the computed marks to the host and drops those of folders
  that left the panels. }
procedure MainApplyMarks(AUserData: Pointer); cdecl;
var
  Uris, Jsons, Applied: TArray<string>;
  I: Integer;
begin
  try
    if not MarksAvailable then
      Exit;
    GLock.Enter;
    try
      Uris := GPendingMarkUris;
      Jsons := GPendingMarkJson;
    finally
      GLock.Leave;
    end;
    for I := 0 to High(GAppliedMarkUris) do
      if not HasUri(Uris, GAppliedMarkUris[I]) then
        SetMarks(GAppliedMarkUris[I], '');
    for I := 0 to High(Uris) do
      SetMarks(Uris[I], Jsons[I]);
    Applied := Copy(Uris);
    GAppliedMarkUris := Applied;
  except
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
  Uri, LastUri, Dir, Text, Json, LastText, FoldersKey, LastFoldersKey, MarkKey, LastMarkKey: string;
  Folders, MarkUris, MarkJsons: TArray<string>;
  MarkJson, F: string;
  LastRun: UInt64;
  Status: TGitStatus;
  Labels: TGitLabels;
  Settings: TGitSettings;
  Dirty: Boolean;
  Cancelled: TFunc<Boolean>;
begin
  LastUri := #0;
  LastText := #0;
  LastFoldersKey := #0;
  LastMarkKey := #0;
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
      Folders := GFolders;
      Labels := GLabels;
      Settings := GSettings;
      Dirty := GDirty;
      GDirty := False;
    finally
      GLock.Leave;
    end;
    if Dirty then
      LastText := #0;
    FoldersKey := string.Join('|', Folders);
    if (Uri = LastUri) and (FoldersKey = LastFoldersKey) and (TThread.GetTickCount64 - LastRun < UInt64(Settings.RefreshSec) * 1000) and not Dirty then
      Continue;
    LastUri := Uri;
    LastFoldersKey := FoldersKey;
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
    if MarksAvailable then
    begin
      MarkUris := nil;
      MarkJsons := nil;
      MarkKey := '';
      for F in Folders do
      begin
        if not ReadGitMarks(FileUriToPath(F), Cancelled, MarkJson) then
          MarkJson := '';
        MarkUris := MarkUris + [F];
        MarkJsons := MarkJsons + [MarkJson];
        MarkKey := MarkKey + F + #1 + MarkJson + #2;
      end;
      if not Terminated and (MarkKey <> LastMarkKey) then
      begin
        LastMarkKey := MarkKey;
        GLock.Enter;
        try
          GPendingMarkUris := MarkUris;
          GPendingMarkJson := MarkJsons;
        finally
          GLock.Leave;
        end;
        PostToMain(MainApplyMarks);
      end;
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
  if (AHostApi.AbiVersion >= cOpenDocumentAbi) and Assigned(GHostApi.RegisterCommand) then
  begin
    Id := UTF8String(cPluginId);
    GHostApi.RegisterCommand(PAnsiChar(Id), cDiffCommand, @CmdDiff, nil);
    GHostApi.RegisterKeyBinding(PAnsiChar(Id), cDiffCommand, 'Ctrl+Shift+D');
    if Assigned(GHostApi.RegisterMenuItem) then
      GHostApi.RegisterMenuItem(PAnsiChar(Id), 'Plugins', 'git_diff',
        PAnsiChar(UTF8String(Tr('ui.menu.diff', 'Git diff of the file'))), @CmdDiff, nil, 70);
    GHostApi.RegisterCommand(PAnsiChar(Id), cBlameCommand, @CmdBlame, nil);
    if Assigned(GHostApi.RegisterMenuItem) then
      GHostApi.RegisterMenuItem(PAnsiChar(Id), 'Plugins', 'git_blame',
        PAnsiChar(UTF8String(Tr('ui.menu.blame', 'Git blame of the file'))), @CmdBlame, nil, 71);
  end;
  LoadLabels;
  ReadActiveUri;
  GWorker := TGitWorker.Create;
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
var
  I: Integer;
begin
  if Assigned(GWorker) then
  begin
    GWorker.Terminate;
    GWorker.Wake;
    GWorker.WaitFor;
    FreeAndNil(GWorker);
  end;
  if MarksAvailable then
  begin
    for I := 0 to High(GAppliedMarkUris) do
      SetMarks(GAppliedMarkUris[I], '');
    GAppliedMarkUris := nil;
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
