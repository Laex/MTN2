library TmpPanelPlugin;

{ Native MTN2 VFS plugin: Far-style Temporary panel. Scheme tmp:/// holds
  references to real files (F5 onto the panel adds them; F8 deletes the
  real files because list rows use targetUri = file://). Two commands fill the
  panel: the files named by the output of a shell command, and the files of
  the current folder that have identical copies. }

uses
  System.SysUtils, System.Classes, System.JSON, System.SyncObjs, System.Math,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uTmpPanelStore in 'uTmpPanelStore.pas',
  uTmpPanelCollect in 'uTmpPanelCollect.pas',
  uTmpPanelRun in 'uTmpPanelRun.pas';

const
  cPluginId = 'mtn.tmp';
  cProgressId = 'tmp.collect';
  cSettingLastCommand = 'lastCommand';
  cCommandTimeoutMs = 120000;

type
  TCollectKind = (ckCommand, ckDuplicates);

  { What a worker thread hands back to the main thread. }
  TCollectJob = class
    Kind: TCollectKind;
    Command: string;
    BaseDir: string;
    Paths: TArray<string>;
    Groups: Integer;
    WastedBytes: Int64;
    Failed: Boolean;
  end;

var
  GBusy: Boolean;
  // Set on the main thread when the user cancels the host job; read by the worker.
  GCancel: Integer;
  GHostApi: THostApiTable;
  GVfsCallbacks: TVfsCallbacksCdecl;

function WriteUtf8Buf(const AData: UTF8String; ABuf: PAnsiChar; ABufSize: Int64;
  out ANegotiatedSize: Int64): Int64;
var
  Need: Int64;
begin
  Need := Length(AData);
  ANegotiatedSize := Need;
  if Need + 1 > ABufSize then
    Exit(Int64(verNeedsBiggerBuffer));
  if Need > 0 then
    Move(PAnsiChar(AData)^, ABuf^, Need);
  ABuf[Need] := #0;
  Result := Int64(verOk);
end;

procedure HostPublish(const ATopic, APayload: UTF8String);
var
  PluginId: UTF8String;
begin
  if not Assigned(GHostApi.HostPublish) then
    Exit;
  PluginId := UTF8String('mtn.tmp');
  GHostApi.HostPublish(PAnsiChar(PluginId), PAnsiChar(ATopic), PAnsiChar(APayload));
end;

procedure PublishNavigate;
begin
  HostPublish(UTF8String('panel.navigate'), UTF8String('{"uri":"tmp:///"}'));
end;

procedure PublishReload;
begin
  HostPublish(UTF8String('panel.reload'), UTF8String('{"uri":"tmp:///"}'));
end;

procedure MenuOpen(AUserData: Pointer); cdecl;
begin
  PublishNavigate;
end;

procedure MenuClear(AUserData: Pointer); cdecl;
begin
  TmpPanelClear;
  PublishReload;
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

procedure Notice(const AText: string; AKind: Int64);
var
  Text: UTF8String;
begin
  if not Assigned(GHostApi.ShowMessage) then
    Exit;
  Text := UTF8String(AText);
  GHostApi.ShowMessage(PAnsiChar(Text), AKind);
end;

const
  cProgressIntervalMs = 200;

function HostHasJobs: Boolean;
begin
  Result := (GHostApi.AbiVersion >= 7) and Assigned(GHostApi.JobBegin) and
    Assigned(GHostApi.JobEnd);
end;

function CancelRequested: Boolean;
begin
  Result := TInterlocked.CompareExchange(GCancel, 0, 0) <> 0;
end;

procedure OnJobCancel(AUserData: Pointer); cdecl;
begin
  TInterlocked.Exchange(GCancel, 1);
end;

{ A background job in the host's job list, which can be cancelled there; a host
  without jobs gets a plain progress notice. }
procedure BeginProgress(const ATitle: string);
var
  Id, Plugin, Text: UTF8String;
begin
  TInterlocked.Exchange(GCancel, 0);
  Plugin := UTF8String(cPluginId);
  Id := UTF8String(cProgressId);
  Text := UTF8String(ATitle);
  if HostHasJobs then
    GHostApi.JobBegin(PAnsiChar(Plugin), PAnsiChar(Id), PAnsiChar(Text), @OnJobCancel, nil)
  else if Assigned(GHostApi.ProgressSet) then
    GHostApi.ProgressSet(PAnsiChar(Plugin), PAnsiChar(Id), PAnsiChar(Text), -1);
end;

procedure EndProgress;
var
  Id, Plugin: UTF8String;
begin
  Plugin := UTF8String(cPluginId);
  Id := UTF8String(cProgressId);
  if HostHasJobs then
    GHostApi.JobEnd(PAnsiChar(Plugin), PAnsiChar(Id))
  else if Assigned(GHostApi.ProgressEnd) then
    GHostApi.ProgressEnd(PAnsiChar(Plugin), PAnsiChar(Id));
end;

function GetSettingText(const AKey: string): string;
var
  Plugin, Key: UTF8String;
  Buf: array[0..1023] of AnsiChar;
begin
  Result := '';
  if not Assigned(GHostApi.GetSetting) then
    Exit;
  Plugin := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Buf[0] := #0;
  if GHostApi.GetSetting(PAnsiChar(Plugin), PAnsiChar(Key), @Buf[0], SizeOf(Buf)) >= 0 then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

procedure SetSettingText(const AKey, AValue: string);
var
  Plugin, Key, Value: UTF8String;
begin
  if not Assigned(GHostApi.SetSetting) then
    Exit;
  Plugin := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Value := UTF8String(AValue);
  GHostApi.SetSetting(PAnsiChar(Plugin), PAnsiChar(Key), PAnsiChar(Value));
end;

{ Folder shown by the active file panel as a local path; '' when the active
  panel is not on a local folder (an archive, a plugin scheme) or unknown. }
function ActiveLocalFolder: string;
var
  Buf: UTF8String;
  Len: Int64;
  Root: TJSONValue;
  Active, Uri: string;
begin
  Result := '';
  if not Assigned(GHostApi.PanelInfo) then
    Exit;
  Len := GHostApi.PanelInfo(nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Buf, Len + 1);
  Len := GHostApi.PanelInfo(PAnsiChar(Buf), Length(Buf));
  if (Len <= 0) or (Len >= Length(Buf)) then
    Exit;
  Root := TJSONObject.ParseJSONValue(UTF8ToString(PAnsiChar(Buf)));
  try
    if not (Root is TJSONObject) or not Root.TryGetValue<string>('active', Active) then
      Exit;
    if not Root.TryGetValue<string>(Active + '.uri', Uri) then
      Exit;
  finally
    Root.Free;
  end;
  if SameText(Copy(Uri, 1, 5), 'file:') then
    Result := FileUriToPath(Uri);
end;

type
  { A status line for the host's job list, built by the worker. }
  TProgressNote = class
    Text: UTF8String;
    Percent: Integer;
  end;

{ Main thread: show a progress note in the job; stale notes (job already over) are dropped. }
procedure MainProgressNote(AUserData: Pointer); cdecl;
var
  Note: TProgressNote;
  Plugin, Id: UTF8String;
begin
  Note := TProgressNote(AUserData);
  try
    try
      if GBusy and HostHasJobs and Assigned(GHostApi.JobUpdate) then
      begin
        Plugin := UTF8String(cPluginId);
        Id := UTF8String(cProgressId);
        GHostApi.JobUpdate(PAnsiChar(Plugin), PAnsiChar(Id), PAnsiChar(Note.Text), Note.Percent);
      end;
    except
      // Never let an exception cross into the host.
    end;
  finally
    Note.Free;
  end;
end;

{ Worker thread: hands a status text to the main thread, at most a few times a second. }
procedure PostProgress(const AText: string; APercent: Integer; var ALastTick: UInt64);
var
  Note: TProgressNote;
  Plugin: UTF8String;
  Now: UInt64;
begin
  Now := TThread.GetTickCount64;
  if (ALastTick <> 0) and (Now - ALastTick < cProgressIntervalMs) then
    Exit;
  ALastTick := Now;
  if not (HostHasJobs and Assigned(GHostApi.JobUpdate) and Assigned(GHostApi.PostToMain)) then
    Exit;
  Note := TProgressNote.Create;
  Note.Text := UTF8String(AText);
  Note.Percent := APercent;
  Plugin := UTF8String(cPluginId);
  if GHostApi.PostToMain(PAnsiChar(Plugin), @MainProgressNote, Note) <> 0 then
    Note.Free;
end;

{ Statistics, then the folder being read, as the two lines of the job's status. }
function DuplicateStatus(const AProgress: TDupProgress; out APercent: Integer): string;
begin
  if AProgress.Comparing then
  begin
    Result := Format(Tr('msg.progressCompare',
      'Checked %d of %d files, in duplicate groups: %d'),
      [AProgress.Checked, AProgress.Candidates, AProgress.FoundFiles]);
    if AProgress.Candidates > 0 then
      APercent := Min(99, Round(AProgress.Checked * 100 / AProgress.Candidates))
    else
      APercent := -1;
  end
  else
  begin
    Result := Format(Tr('msg.progressScan', 'Scanned files: %d'), [AProgress.Scanned]);
    APercent := -1;
  end;
  Result := Result + #10 + ExcludeTrailingPathDelimiter(AProgress.Dir);
end;

{ Main thread: the worker finished - fill the panel and show it. }
procedure MainCollectDone(AUserData: Pointer); cdecl;
var
  Job: TCollectJob;
  Path: string;
begin
  Job := TCollectJob(AUserData);
  try
    try
      GBusy := False;
      EndProgress;
      if CancelRequested then
      begin
        Notice(Tr('msg.cancelled', 'Cancelled.'), 0);
        Exit;
      end;
      if Job.Failed then
      begin
        Notice(Tr('msg.commandFailed', 'The command could not be run or did not finish in time.'), 1);
        Exit;
      end;
      if Length(Job.Paths) = 0 then
      begin
        if Job.Kind = ckDuplicates then
          Notice(Tr('msg.noDuplicates', 'No duplicate files found in this folder.'), 0)
        else
          Notice(Tr('msg.noFiles', 'The command printed no names of existing files or folders.'), 0);
        Exit;
      end;
      TmpPanelClear;
      for Path in Job.Paths do
        TmpPanelAddFromUri(PathToFileUri(Path));
      PublishNavigate;
      if Job.Kind = ckDuplicates then
        Notice(Format(Tr('msg.duplicatesFound',
          '%d groups of identical files, %d files, %d MB could be freed'),
          [Job.Groups, Length(Job.Paths), Job.WastedBytes div (1024 * 1024)]), 0)
      else
        Notice(Format(Tr('msg.filesCollected', '%d files and folders in the temporary panel'),
          [Length(Job.Paths)]), 0);
    except
      // Never let an exception cross into the host.
    end;
  finally
    Job.Free;
  end;
end;

procedure PostJob(AJob: TCollectJob);
var
  Plugin: UTF8String;
begin
  Plugin := UTF8String(cPluginId);
  if (not Assigned(GHostApi.PostToMain)) or
     (GHostApi.PostToMain(PAnsiChar(Plugin), @MainCollectDone, AJob) <> 0) then
    AJob.Free;
end;

procedure RunCollectJob(AJob: TCollectJob);
var
  Output: string;
  Groups: TArray<TArray<string>>;
  G: TArray<string>;
  List: TStringList;
  Stream: TFileStream;
  Size: Int64;
  LastTick: UInt64;
begin
  LastTick := 0;
  try
    if AJob.Kind = ckCommand then
    begin
      AJob.Failed := not RunCommandCapture(AJob.Command, AJob.BaseDir, cCommandTimeoutMs, Output,
        function: Boolean
        begin
          Result := CancelRequested;
        end);
      if not AJob.Failed then
        AJob.Paths := ParsePanelizeOutput(Output, AJob.BaseDir);
    end
    else
    begin
      Groups := FindDuplicateGroups(AJob.BaseDir, 1,
        function: Boolean
        begin
          Result := CancelRequested;
        end,
        procedure(const AProgress: TDupProgress)
        var
          Percent: Integer;
          Text: string;
        begin
          Text := DuplicateStatus(AProgress, Percent);
          PostProgress(Text, Percent, LastTick);
        end);
      List := TStringList.Create;
      try
        for G in Groups do
        begin
          Size := 0;
          try
            Stream := TFileStream.Create(G[0], fmOpenRead or fmShareDenyNone);
            try
              Size := Stream.Size;
            finally
              Stream.Free;
            end;
          except
            Size := 0;
          end;
          Inc(AJob.WastedBytes, Size * (Length(G) - 1));
          Inc(AJob.Groups);
          List.AddStrings(G);
        end;
        AJob.Paths := List.ToStringArray;
      finally
        List.Free;
      end;
    end;
  except
    AJob.Failed := True;
  end;
  PostJob(AJob);
end;

procedure StartCollect(AKind: TCollectKind; const ACommand, ABaseDir: string);
var
  Job: TCollectJob;
begin
  Job := TCollectJob.Create;
  Job.Kind := AKind;
  Job.Command := ACommand;
  Job.BaseDir := ABaseDir;
  GBusy := True;
  if AKind = ckCommand then
    BeginProgress(Tr('msg.running', 'Running the command...'))
  else
    BeginProgress(Tr('msg.searching', 'Looking for duplicate files...'));
  TThread.CreateAnonymousThread(
    procedure
    begin
      RunCollectJob(Job);
    end).Start;
end;

procedure OnCommandDialog(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Root: TJSONValue;
  Command, Folder: string;
begin
  try
    if not SameText(string(AControlId), 'ok') then
      Exit;
    Command := '';
    Root := TJSONObject.ParseJSONValue(UTF8ToString(AValuesJson));
    try
      if Root is TJSONObject then
        Root.TryGetValue<string>('command', Command);
    finally
      Root.Free;
    end;
    Command := Trim(Command);
    if Command = '' then
      Exit;
    Folder := ActiveLocalFolder;
    if Folder = '' then
      Exit;
    SetSettingText(cSettingLastCommand, Command);
    StartCollect(ckCommand, Command, Folder);
  except
    // Never let an exception cross into the host.
  end;
end;

procedure AddControl(AChildren: TJSONArray; const AType, AId, AText, AValue: string;
  ACol, ARow, AWidth: Integer; ADefault: Boolean = False; ACancel: Boolean = False);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', AType);
  if AId <> '' then
    O.AddPair('id', AId);
  if AText <> '' then
    O.AddPair('text', AText);
  if AType = 'input' then
    O.AddPair('value', AValue);
  if ADefault then
    O.AddPair('default', TJSONBool.Create(True));
  if ACancel then
    O.AddPair('cancel', TJSONBool.Create(True));
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(1));
  AChildren.AddElement(O);
end;

procedure ShowCommandDialog(const AFolder: string);
var
  Decl: TJSONObject;
  Kids: TJSONArray;
  Json, Plugin: UTF8String;
begin
  Decl := TJSONObject.Create;
  try
    Decl.AddPair('type', 'dialog');
    Decl.AddPair('version', '2.0');
    Decl.AddPair('title', Tr('dlg.title', 'Panelize command output'));
    Decl.AddPair('width', TJSONNumber.Create(72));
    Decl.AddPair('height', TJSONNumber.Create(10));
    Kids := TJSONArray.Create;
    Decl.AddPair('children', Kids);
    AddControl(Kids, 'label', '', Tr('dlg.hint', 'Command (each output line names a file or folder):'),
      '', 2, 1, 66);
    AddControl(Kids, 'input', 'command', '', GetSettingText(cSettingLastCommand), 2, 2, 66);
    AddControl(Kids, 'label', '', Tr('dlg.folder', 'Run in: ') + AFolder, '', 2, 4, 66);
    AddControl(Kids, 'button', 'ok', Tr('dlg.ok', 'OK'), '', 22, 7, 12, True);
    AddControl(Kids, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), '', 37, 7, 12, False, True);
    Json := UTF8String(Decl.ToJSON);
  finally
    Decl.Free;
  end;
  Plugin := UTF8String(cPluginId);
  GHostApi.ShowDialog(PAnsiChar(Plugin), PAnsiChar(Json), @OnCommandDialog, nil);
end;

{ The folder to work in, or '' with a notice when a search cannot start now. }
function CollectFolder: string;
begin
  Result := '';
  if GBusy then
  begin
    Notice(Tr('msg.busy', 'The previous search is still running.'), 1);
    Exit;
  end;
  Result := ActiveLocalFolder;
  if Result = '' then
    Notice(Tr('msg.localOnly', 'Open a local folder in the active panel first.'), 1);
end;

procedure MenuPanelize(AUserData: Pointer); cdecl;
var
  Folder: string;
begin
  try
    Folder := CollectFolder;
    if (Folder <> '') and Assigned(GHostApi.ShowDialog) then
      ShowCommandDialog(Folder);
  except
    // Never let an exception cross into the host.
  end;
end;

procedure MenuDuplicates(AUserData: Pointer); cdecl;
var
  Folder: string;
begin
  try
    Folder := CollectFolder;
    if Folder <> '' then
      StartCollect(ckDuplicates, '', Folder);
  except
    // Never let an exception cross into the host.
  end;
end;

function TmpListDirectory(AURI: PAnsiChar; AUserData: Pointer;
  ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
var
  Json: UTF8String;
  Code: Int64;
begin
  ANegotiatedSize := 0;
  if not IsTmpPanelUri(UTF8ToString(AURI)) then
    Exit(Int64(verInvalidURI));
  Code := TmpPanelListJson(Json);
  if Code <> Int64(verOk) then
    Exit(Code);
  Result := WriteUtf8Buf(Json, ABuf, ABufSize, ANegotiatedSize);
end;

function TmpExists(AURI: PAnsiChar; AUserData: Pointer;
  out AIsDirectory: Int64): Int64; cdecl;
var
  IsDir: Boolean;
begin
  AIsDirectory := 0;
  if not IsTmpPanelUri(UTF8ToString(AURI)) then
    Exit(Int64(verInvalidURI));
  TmpPanelRootExists(IsDir);
  AIsDirectory := Ord(IsDir);
  Result := Int64(verOk);
end;

function TmpCopyItem(AFromURI, AToURI: PAnsiChar; AOverwrite: Int64;
  AUserData: Pointer): Int64; cdecl;
begin
  Result := TmpPanelAddFromUri(UTF8ToString(AFromURI));
end;

function TmpDelete(AURI: PAnsiChar; AMode: Int64; AUserData: Pointer): Int64; cdecl;
var
  S: string;
begin
  S := UTF8ToString(AURI);
  if IsTmpPanelUri(S) then
  begin
    TmpPanelClear;
    Exit(Int64(verOk));
  end;
  Result := TmpPanelRemoveFromUri(S);
end;

function TmpCreateDirectory(AURI: PAnsiChar; AUserData: Pointer): Int64; cdecl;
begin
  Result := Int64(verNotSupported);
end;

function TmpMoveItem(AFromURI, AToURI: PAnsiChar; AOverwrite: Int64;
  AUserData: Pointer): Int64; cdecl;
begin
  Result := Int64(verNotSupported);
end;

function TmpReadText(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
  ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
begin
  ANegotiatedSize := 0;
  Result := Int64(verNotSupported);
end;

function TmpReadBytes(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
  ABuf: PByte; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
begin
  ANegotiatedSize := 0;
  Result := Int64(verNotSupported);
end;

function TmpWriteText(AURI: PAnsiChar; AText: PAnsiChar; AUserData: Pointer): Int64; cdecl;
begin
  Result := Int64(verNotSupported);
end;

function TmpGetFreeSpace(ARootURI: PAnsiChar; AUserData: Pointer;
  out AFree, ATotal: Int64): Int64; cdecl;
begin
  AFree := 0;
  ATotal := 0;
  Result := Int64(verOk);
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
var
  PluginId, Scheme, Parent, OpenId, OpenCap, ClearId, ClearCap: UTF8String;
  PanelizeId, PanelizeCap, DupId, DupCap: UTF8String;
begin
  if AHostApi = nil then
    Exit(-1);
  GHostApi := AHostApi^;

  FillChar(GVfsCallbacks, SizeOf(GVfsCallbacks), 0);
  GVfsCallbacks.ListDirectory := @TmpListDirectory;
  GVfsCallbacks.Delete := @TmpDelete;
  GVfsCallbacks.CreateDirectory := @TmpCreateDirectory;
  GVfsCallbacks.CopyItem := @TmpCopyItem;
  GVfsCallbacks.MoveItem := @TmpMoveItem;
  GVfsCallbacks.ReadText := @TmpReadText;
  GVfsCallbacks.ReadBytes := @TmpReadBytes;
  GVfsCallbacks.WriteText := @TmpWriteText;
  GVfsCallbacks.Exists := @TmpExists;
  GVfsCallbacks.GetFreeSpace := @TmpGetFreeSpace;

  PluginId := UTF8String('mtn.tmp');
  Scheme := UTF8String('tmp');
  if Assigned(AHostApi.RegisterVfsScheme) then
    AHostApi.RegisterVfsScheme(PAnsiChar(PluginId), PAnsiChar(Scheme),
      @GVfsCallbacks, nil, 30);
  if Assigned(AHostApi.RegisterPanelPlugin) then
    AHostApi.RegisterPanelPlugin(PAnsiChar(PluginId), PAnsiChar(Scheme), 30);

  Parent := UTF8String('Plugins');
  OpenId := UTF8String('tmp_open');
  OpenCap := UTF8String('Temporary panel');
  ClearId := UTF8String('tmp_clear');
  ClearCap := UTF8String('Clear temporary panel');
  if Assigned(AHostApi.RegisterMenuItem) then
  begin
    AHostApi.RegisterMenuItem(PAnsiChar(PluginId), PAnsiChar(Parent),
      PAnsiChar(OpenId), PAnsiChar(OpenCap), @MenuOpen, nil, 40);
    AHostApi.RegisterMenuItem(PAnsiChar(PluginId), PAnsiChar(Parent),
      PAnsiChar(ClearId), PAnsiChar(ClearCap), @MenuClear, nil, 41);
    if Assigned(AHostApi.PanelInfo) and Assigned(AHostApi.PostToMain) then
    begin
      PanelizeId := UTF8String('tmp_panelize');
      PanelizeCap := UTF8String(Tr('menu.panelize', 'Panelize command output...'));
      DupId := UTF8String('tmp_duplicates');
      DupCap := UTF8String(Tr('menu.duplicates', 'Find duplicate files'));
      AHostApi.RegisterMenuItem(PAnsiChar(PluginId), PAnsiChar(Parent),
        PAnsiChar(PanelizeId), PAnsiChar(PanelizeCap), @MenuPanelize, nil, 42);
      AHostApi.RegisterMenuItem(PAnsiChar(PluginId), PAnsiChar(Parent),
        PAnsiChar(DupId), PAnsiChar(DupCap), @MenuDuplicates, nil, 43);
    end;
  end;
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  TmpPanelClear;
  FillChar(GHostApi, SizeOf(GHostApi), 0);
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
