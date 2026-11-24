library ArchiveToolsPlugin;

{ Native MTN2 plugin: Files > Test archive checks every entry of the ZIP under
  the cursor against its stored CRC-32 (other formats are handed to the 7-Zip
  plugin when it is loaded); Files > Pack each item packs every selected file
  or folder into its own ZIP in the other panel's folder. Both run in a
  background job. }

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uZipNames in '..\..\Core\uZipNames.pas',
  uArchiveTest in 'uArchiveTest.pas',
  uPackEach in 'uPackEach.pas';

const
  cPluginId = 'mtn.archivetools';
  cTestCommandId = 'archivetools.test';
  cPackCommandId = 'archivetools.packeach';
  cSevenZipTestCommand = 'sevenzip.test';
  cJobKey = 'run';

type
  TJobKind = (jkTest, jkPack);

var
  GHostApi: THostApiTable;
  GPostToMain: THostPostToMainFn;
  GBusy: Boolean;
  GCancel: Boolean;
  GShutdown: Boolean;
  GFinished: Boolean;
  GKind: TJobKind;
  GTitle: string;
  GStatus: string;
  GError: string;
  GFailed: TArray<string>;

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

function GetSettingText(const AKey: string): string;
var
  Plugin, Key: UTF8String;
  Buf: array[0..255] of AnsiChar;
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

function HostText(AFn: THostTextOutFn): string;
var
  Buf: UTF8String;
  Len: Int64;
begin
  Result := '';
  if not Assigned(AFn) then
    Exit;
  Len := AFn(nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Buf, Len + 1);
  Len := AFn(PAnsiChar(Buf), Length(Buf));
  if (Len > 0) and (Len < Length(Buf)) then
    Result := UTF8ToString(PAnsiChar(Buf));
end;

procedure AddControl(AChildren: TJSONArray; const AType, AId, AText: string;
  ACol, ARow, AWidth, AHeight: Integer; ADefault: Boolean = False; ACancel: Boolean = False);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', AType);
  if AId <> '' then
    O.AddPair('id', AId);
  if AText <> '' then
    O.AddPair('text', AText);
  if ADefault then
    O.AddPair('default', TJSONBool.Create(True));
  if ACancel then
    O.AddPair('cancel', TJSONBool.Create(True));
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(AHeight));
  AChildren.AddElement(O);
end;

function ShowDeclaration(ADecl: TJSONObject; ACallback: THostDialogCommandCallback): Boolean;
var
  Json, Plugin: UTF8String;
begin
  Json := UTF8String(ADecl.ToJSON);
  Plugin := UTF8String(cPluginId);
  Result := GHostApi.ShowDialog(PAnsiChar(Plugin), PAnsiChar(Json), ACallback, nil) = 0;
end;

function NewDialog(const ATitle: string; AWidth, AHeight: Integer;
  out AChildren: TJSONArray): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'dialog');
  Result.AddPair('version', '2.0');
  Result.AddPair('title', ATitle);
  Result.AddPair('width', TJSONNumber.Create(AWidth));
  Result.AddPair('height', TJSONNumber.Create(AHeight));
  AChildren := TJSONArray.Create;
  Result.AddPair('children', AChildren);
end;

{ ---- result dialog ------------------------------------------------------ }

procedure OnDamagedDialog(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
begin
end;

procedure ShowDamaged;
var
  Decl: TJSONObject;
  Kids, Items: TJSONArray;
  List: TJSONObject;
  Line: string;
begin
  Decl := NewDialog(GTitle, 78, 22, Kids);
  try
    AddControl(Kids, 'label', 'status', GStatus, 1, 0, 74, 1);
    List := TJSONObject.Create;
    List.AddPair('type', 'list');
    List.AddPair('id', 'lines');
    List.AddPair('selected', TJSONNumber.Create(0));
    Items := TJSONArray.Create;
    for Line in GFailed do
      Items.Add(Line);
    List.AddPair('items', Items);
    List.AddPair('col', TJSONNumber.Create(1));
    List.AddPair('row', TJSONNumber.Create(2));
    List.AddPair('width', TJSONNumber.Create(74));
    List.AddPair('height', TJSONNumber.Create(14));
    Kids.AddElement(List);
    AddControl(Kids, 'separator', '', '', 0, 16, 76, 1);
    AddControl(Kids, 'button', 'close', Tr('dlg.close', 'Close'), 31, 18, 14, 1, True, True);
    if not ShowDeclaration(Decl, @OnDamagedDialog) then
      Notice(GStatus, 1);
  finally
    Decl.Free;
  end;
end;

{ ---- background job ----------------------------------------------------- }

procedure JobEndNow;
var
  Plugin, Key: UTF8String;
begin
  if not Assigned(GHostApi.JobEnd) then
    Exit;
  Plugin := UTF8String(cPluginId);
  Key := UTF8String(cJobKey);
  GHostApi.JobEnd(PAnsiChar(Plugin), PAnsiChar(Key));
end;

procedure OnJobFinished(AUserData: Pointer); cdecl;
begin
  try
    JobEndNow;
    GBusy := False;
    if GShutdown or GCancel or not GFinished then
      Exit;
    if (GKind = jkPack) and Assigned(GHostApi.PanelRefresh) then
      GHostApi.PanelRefresh;
    if GError <> '' then
      Notice(GError, 1)
    else if Length(GFailed) > 0 then
      ShowDamaged
    else
      Notice(GStatus, 0);
  except
    // Never let an exception cross into the host.
  end;
end;

procedure OnJobCancel(AUserData: Pointer); cdecl;
begin
  GCancel := True;
end;

procedure RunJob(AKind: TJobKind; const APaths: TArray<string>; const ADestDir: string);
var
  Cancelled: TArchiveTestCancelled;
  R: TArchiveTestResult;
  Count: Integer;
  Done: Boolean;
  Err, Status: string;
  Failed: TArray<string>;
begin
  Cancelled :=
    function: Boolean
    begin
      Result := GCancel or GShutdown;
    end;
  Err := '';
  Status := '';
  Failed := nil;
  Done := False;
  try
    if AKind = jkTest then
    begin
      R := TestZipArchive(APaths[0], Cancelled);
      Done := not R.Cancelled;
      if R.Failed = 0 then
        Status := Format(Tr('msg.testOk', '%d files OK'), [R.Checked])
      else
      begin
        Status := Format(Tr('msg.testFailed', '%d of %d files are damaged:'),
          [R.Failed, R.Checked]);
        Failed := R.Errors;
      end;
    end
    else
    begin
      Count := 0;
      Done := PackEachToZip(APaths, ADestDir,
        function: Boolean
        begin
          Result := GCancel or GShutdown;
        end, Count);
      Status := Format(Tr('msg.packDone', '%d archives created'), [Count]);
    end;
  except
    on E: Exception do
      Err := E.Message;
  end;
  GStatus := Status;
  GError := Err;
  GFailed := Failed;
  GFinished := Done or (Err <> '');
  if not GShutdown and Assigned(GPostToMain) then
    GPostToMain(PAnsiChar(UTF8String(cPluginId)), @OnJobFinished, nil);
end;

procedure StartJob(AKind: TJobKind; const APaths: TArray<string>; const ADestDir: string);
var
  Plugin, Key, Title: UTF8String;
  Paths: TArray<string>;
begin
  GBusy := True;
  GCancel := False;
  GFinished := False;
  GKind := AKind;
  if AKind = jkTest then
    GTitle := Tr('dlg.testTitle', 'Test archive')
  else
    GTitle := Tr('dlg.packTitle', 'Pack each item');
  Plugin := UTF8String(cPluginId);
  Key := UTF8String(cJobKey);
  Title := UTF8String(GTitle);
  if Assigned(GHostApi.JobBegin) then
    GHostApi.JobBegin(PAnsiChar(Plugin), PAnsiChar(Key), PAnsiChar(Title), @OnJobCancel, nil);
  Paths := Copy(APaths);
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        RunJob(AKind, Paths, ADestDir);
      except
        // The job reports its own errors; nothing may escape the thread.
      end;
    end).Start;
end;

{ ---- commands ----------------------------------------------------------- }

{ The sources of the command: the selection of the active panel, or the row
  under the cursor, as paths on disk. ADestDir is the other panel's folder
  when that is a folder on disk. AAllLocal is False when some source is not
  on disk. False when nothing is selected. }
function CollectSources(out APaths: TArray<string>; out ADestDir: string;
  out AAllLocal: Boolean): Boolean;
var
  Root, Side, Other: TJSONValue;
  Active, Uri, OtherUri, OtherKey: string;
  Selected: TJSONArray;
  Uris: TArray<string>;
  I: Integer;
begin
  Result := False;
  APaths := nil;
  ADestDir := '';
  AAllLocal := True;
  Root := TJSONObject.ParseJSONValue(HostText(GHostApi.PanelInfo));
  try
    if not (Root is TJSONObject) or not Root.TryGetValue<string>('active', Active) then
      Exit;
    Side := TJSONObject(Root).GetValue(Active);
    if not (Side is TJSONObject) then
      Exit;
    if Side.TryGetValue<TJSONArray>('selected', Selected) then
      for I := 0 to Selected.Count - 1 do
        Uris := Uris + [Selected.Items[I].Value];
    if (Length(Uris) = 0) and Side.TryGetValue<string>('cursor', Uri) and (Uri <> '') then
      Uris := [Uri];
    if SameText(Active, 'left') then
      OtherKey := 'right'
    else
      OtherKey := 'left';
    Other := TJSONObject(Root).GetValue(OtherKey);
    if (Other is TJSONObject) and Other.TryGetValue<string>('uri', OtherUri) and
       SameText(Copy(OtherUri, 1, 8), 'file:///') then
      ADestDir := ExcludeTrailingPathDelimiter(FileUriToPath(OtherUri));
  finally
    Root.Free;
  end;
  if Length(Uris) = 0 then
    Exit;
  for Uri in Uris do
    if SameText(Copy(Uri, 1, 8), 'file:///') then
      APaths := APaths + [FileUriToPath(Uri)]
    else
      AAllLocal := False;
  Result := True;
end;

procedure CmdTest(AUserData: Pointer); cdecl;
var
  Paths: TArray<string>;
  DestDir: string;
  AllLocal: Boolean;
  Cmd: UTF8String;
begin
  try
    if GBusy then
    begin
      Notice(Tr('msg.busy', 'Another archive job is already running'), 1);
      Exit;
    end;
    if not CollectSources(Paths, DestDir, AllLocal) then
      Exit;
    if AllLocal and (Length(Paths) = 1) and TFile.Exists(Paths[0]) then
    begin
      if SameText(ExtractFileExt(Paths[0]), '.zip') then
      begin
        StartJob(jkTest, Paths, '');
        Exit;
      end;
      // Formats other than ZIP are tested by the 7-Zip plugin, when it is loaded.
      Cmd := UTF8String(cSevenZipTestCommand);
      if Assigned(GHostApi.ExecuteCommand) and (GHostApi.ExecuteCommand(PAnsiChar(Cmd)) = 0) then
        Exit;
    end;
    Notice(Tr('msg.oneZip', 'Select one ZIP archive on disk'), 1);
  except
    // Never let an exception cross into the host.
  end;
end;

procedure CmdPackEach(AUserData: Pointer); cdecl;
var
  Paths: TArray<string>;
  DestDir: string;
  AllLocal: Boolean;
begin
  try
    if GBusy then
    begin
      Notice(Tr('msg.busy', 'Another archive job is already running'), 1);
      Exit;
    end;
    if not CollectSources(Paths, DestDir, AllLocal) or not AllLocal or
       (Length(Paths) = 0) or
       not (TFile.Exists(Paths[0]) or TDirectory.Exists(Paths[0])) then
    begin
      Notice(Tr('msg.noSources', 'Select files or folders on disk'), 1);
      Exit;
    end;
    if (DestDir = '') or not TDirectory.Exists(DestDir) then
      DestDir := ExcludeTrailingPathDelimiter(
        ExtractFilePath(ExcludeTrailingPathDelimiter(Paths[0])));
    StartJob(jkPack, Paths, DestDir);
  except
    // Never let an exception cross into the host.
  end;
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
var
  PluginId, TestId, PackId: UTF8String;
begin
  if (AHostApi = nil) or (AHostApi.AbiVersion < 7) or not Assigned(AHostApi.PanelInfo) or
     not Assigned(AHostApi.PostToMain) or not Assigned(AHostApi.RegisterCommand) then
    Exit(-1);
  GHostApi := AHostApi^;
  GPostToMain := AHostApi.PostToMain;
  GShutdown := False;
  GBusy := False;
  PluginId := UTF8String(cPluginId);
  TestId := UTF8String(cTestCommandId);
  PackId := UTF8String(cPackCommandId);
  GHostApi.RegisterCommand(PAnsiChar(PluginId), PAnsiChar(TestId), @CmdTest, nil);
  GHostApi.RegisterCommand(PAnsiChar(PluginId), PAnsiChar(PackId), @CmdPackEach, nil);
  if Assigned(GHostApi.RegisterMenuItem) then
  begin
    GHostApi.RegisterMenuItem(PAnsiChar(PluginId), 'Files', PAnsiChar(TestId),
      PAnsiChar(UTF8String(Tr('menu.test', 'Test archive'))), @CmdTest, nil, 70);
    GHostApi.RegisterMenuItem(PAnsiChar(PluginId), 'Files', PAnsiChar(PackId),
      PAnsiChar(UTF8String(Tr('menu.pack', 'Pack each item'))), @CmdPackEach, nil, 71);
  end;
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  GShutdown := True;
  GCancel := True;
  FillChar(GHostApi, SizeOf(GHostApi), 0);
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
