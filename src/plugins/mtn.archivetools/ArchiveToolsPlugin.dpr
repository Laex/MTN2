library ArchiveToolsPlugin;

{ Native MTN2 plugin: Files > Test archive checks every entry of the ZIP under
  the cursor against its stored CRC-32 (other formats are handed to the 7-Zip
  plugin when it is loaded); Files > Pack each item packs every selected file
  or folder into its own ZIP in the other panel's folder. Both run in a
  background job. }

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uPluginSdk in '..\..\Core\uPluginSdk.pas',
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
  GBusy: Boolean;
  GCancel: Boolean;
  GFinished: Boolean;
  GKind: TJobKind;
  GTitle: string;
  GStatus: string;
  GError: string;
  GFailed: TArray<string>;

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

procedure OnJobFinished(AUserData: Pointer); cdecl;
begin
  try
    JobEndNow(cJobKey);
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
  SdkPostToMain(@OnJobFinished);
end;

procedure StartJob(AKind: TJobKind; const APaths: TArray<string>; const ADestDir: string);
var
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
  JobBeginNow(cJobKey, GTitle, @OnJobCancel);
  Paths := Copy(APaths);
  SdkRunWorker(
    procedure
    begin
      RunJob(AKind, Paths, ADestDir);
    end);
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
  SdkAttach(AHostApi, cPluginId);
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
  GCancel := True;
  SdkDetach;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
