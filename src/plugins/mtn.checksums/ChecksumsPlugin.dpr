library ChecksumsPlugin;

{ Native MTN2 plugin: Ctrl+Alt+H (Files > Checksums...) hashes the selected
  files and folders on disk with MD5, SHA-1, SHA-256 or SHA-512 in a background
  job and shows the lines in a list that can be copied or saved as a checksum
  file. On a checksum file (.md5, .sha1, .sha256, .sha512) the command checks
  the files listed in it instead. }

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Math,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uPluginSdk in '..\..\Core\uPluginSdk.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uChecksums in 'uChecksums.pas';

const
  cPluginId = 'mtn.checksums';
  cCommandId = 'checksums.run';
  cKeyChord = 'Ctrl+Alt+H';
  cJobKey = 'run';
  cSettingAlgo = 'algo';
  cDefaultAlgo = Ord(caSHA256);

var
  GPaths: TArray<string>;
  GBaseDir: string;
  GAlgo: TChecksumAlgo;
  GVerify: Boolean;
  GBusy: Boolean;
  GCancel: Boolean;
  GTitle: string;
  GStatus: string;
  GError: string;
  GFinished: Boolean;
  GLines: TArray<string>;
  GSaveName: string;

function AlgoFromName(const AName: string; out AAlgo: TChecksumAlgo): Boolean;
var
  A: TChecksumAlgo;
begin
  for A := Low(TChecksumAlgo) to High(TChecksumAlgo) do
    if SameText(cChecksumAlgoNames[A], AName) then
    begin
      AAlgo := A;
      Exit(True);
    end;
  Result := False;
end;

{ ---- result list -------------------------------------------------------- }

procedure ShowResult(const AStatus: string); forward;

procedure OnResultDialog(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Id, Text: string;
  Clip: UTF8String;
begin
  try
    Id := string(AControlId);
    if SameText(Id, 'copy') then
    begin
      Clip := UTF8String(string.Join(sLineBreak, GLines));
      if Assigned(GHostApi.ClipboardSet) then
        GHostApi.ClipboardSet(PAnsiChar(Clip));
      ShowResult(Tr('msg.copied', 'Copied to the clipboard'));
    end
    else if SameText(Id, 'save') then
    begin
      try
        TFile.WriteAllText(GSaveName, string.Join(sLineBreak, GLines) + sLineBreak,
          TEncoding.UTF8);
        Text := Tr('msg.saved', 'Saved: ') + ExtractFileName(GSaveName);
        if Assigned(GHostApi.PanelRefresh) then
          GHostApi.PanelRefresh;
      except
        on E: Exception do
          Text := E.Message;
      end;
      ShowResult(Text);
    end;
  except
    // Never let an exception cross into the host.
  end;
end;

procedure ShowResult(const AStatus: string);
var
  Decl: TJSONObject;
  Kids, Items: TJSONArray;
  List: TJSONObject;
  Line: string;
  X: Integer;
begin
  Decl := NewDialog(GTitle, 78, 22, Kids);
  try
    AddControl(Kids, 'label', 'status', AStatus, 1, 0, 74, 1);
    List := TJSONObject.Create;
    List.AddPair('type', 'list');
    List.AddPair('id', 'lines');
    List.AddPair('selected', TJSONNumber.Create(0));
    Items := TJSONArray.Create;
    for Line in GLines do
      Items.Add(Line);
    if Items.Count = 0 then
      Items.Add(Tr('msg.none', '(none)'));
    List.AddPair('items', Items);
    List.AddPair('col', TJSONNumber.Create(1));
    List.AddPair('row', TJSONNumber.Create(2));
    List.AddPair('width', TJSONNumber.Create(74));
    List.AddPair('height', TJSONNumber.Create(14));
    Kids.AddElement(List);
    AddControl(Kids, 'separator', '', '', 0, 16, 76, 1);
    X := 15;
    AddControl(Kids, 'button', 'copy', Tr('dlg.copy', '&Copy'), X, 18, 14, 1);
    if not GVerify then
    begin
      Inc(X, 16);
      AddControl(Kids, 'button', 'save', Tr('dlg.save', '&Save'), X, 18, 14, 1);
    end;
    Inc(X, 16);
    AddControl(Kids, 'button', 'close', Tr('dlg.close', 'Close'), X, 18, 14, 1, True, True);
    if not ShowDeclaration(Decl, @OnResultDialog) then
      Notice(Tr('msg.noDialog', 'The dialog cannot be shown now.'), 1);
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
    if GError <> '' then
    begin
      Notice(GError, 1);
      Exit;
    end;
    ShowResult(GStatus);
  except
    // Never let an exception cross into the host.
  end;
end;

procedure OnJobCancel(AUserData: Pointer); cdecl;
begin
  GCancel := True;
end;

procedure RunJob(const APaths: TArray<string>; const ABase: string; AAlgo: TChecksumAlgo;
  AVerify: Boolean);
var
  Files: TArray<TChecksumFile>;
  Items: TArray<TChecksumVerifyItem>;
  Lines: TArray<string>;
  I, Bad: Integer;
  Hash, Status, SaveName, Err: string;
  Done: Boolean;
  Cancelled: TChecksumCancelled;
begin
  Cancelled :=
    function: Boolean
    begin
      Result := GCancel or GShutdown;
    end;
  Lines := nil;
  Err := '';
  SaveName := '';
  Status := '';
  Bad := 0;
  Done := True;
  try
    if AVerify then
    begin
      Done := VerifyChecksumFile(APaths[0], AAlgo, Items, Cancelled);
      for I := 0 to High(Items) do
      begin
        Lines := Lines + [Format('%-8s %s',
          [ChecksumVerifyStatusText(Items[I].Status), Items[I].RelName])];
        if Items[I].Status <> cvsOk then
          Inc(Bad);
      end;
      Status := Format(Tr('msg.verified', '%d checked, %d not OK: %s'),
        [Length(Items), Bad, ExtractFileName(APaths[0])]);
    end
    else
    begin
      Files := CollectChecksumFiles(APaths, ABase);
      for I := 0 to High(Files) do
      begin
        if Cancelled() then
        begin
          Done := False;
          Break;
        end;
        try
          Hash := HashFileHex(Files[I].Path, AAlgo, Cancelled);
        except
          on E: Exception do
          begin
            Hash := 'ERROR: ' + E.Message;
            Inc(Bad);
          end;
        end;
        if (Hash = '') and Cancelled() then
        begin
          Done := False;
          Break;
        end;
        Lines := Lines + [FormatChecksumLine(Hash, Files[I].RelName)];
      end;
      SaveName := ChecksumSaveFileName(Files, ABase, AAlgo);
      Status := Format(Tr('msg.done', '%d files'), [Length(Files)]);
      if Bad > 0 then
        Status := Status + Format(Tr('msg.errors', ', %d not read'), [Bad]);
    end;
  except
    on E: Exception do
      Err := E.Message;
  end;
  GLines := Lines;
  GSaveName := SaveName;
  GStatus := Status;
  GError := Err;
  GFinished := Done;
  SdkPostToMain(@OnJobFinished);
end;

procedure StartJob(AAlgo: TChecksumAlgo; AVerify: Boolean);
var
  Paths: TArray<string>;
  Base: string;
begin
  GAlgo := AAlgo;
  GVerify := AVerify;
  GBusy := True;
  GCancel := False;
  GFinished := False;
  GTitle := Tr('dlg.title', 'Checksums') + ' ' + cChecksumAlgoNames[AAlgo];
  JobBeginNow(cJobKey, GTitle, @OnJobCancel);
  Paths := Copy(GPaths);
  Base := GBaseDir;
  SdkRunWorker(
    procedure
    begin
      RunJob(Paths, Base, AAlgo, AVerify);
    end);
end;

{ ---- command ------------------------------------------------------------ }

procedure OnOptionsDialog(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Root: TJSONValue;
  Name: string;
  Algo: TChecksumAlgo;
begin
  try
    if not SameText(string(AControlId), 'ok') then
      Exit;
    Root := TJSONObject.ParseJSONValue(UTF8ToString(AValuesJson));
    try
      if not (Root is TJSONObject) or
         not Root.TryGetValue<string>('algo', Name) or
         not AlgoFromName(Name, Algo) then
        Exit;
    finally
      Root.Free;
    end;
    SetSettingText(cSettingAlgo, IntToStr(Ord(Algo)));
    StartJob(Algo, False);
  except
    // Never let an exception cross into the host.
  end;
end;

procedure ShowOptions;
var
  Decl: TJSONObject;
  Kids, Names: TJSONArray;
  Drop: TJSONObject;
  A: TChecksumAlgo;
  Saved: Integer;
begin
  Saved := StrToIntDef(GetSettingText(cSettingAlgo), cDefaultAlgo);
  Saved := EnsureRange(Saved, 0, Ord(High(TChecksumAlgo)));
  Decl := NewDialog(Tr('dlg.title', 'Checksums'), 44, 9, Kids);
  try
    AddControl(Kids, 'label', 'lbl_algo', Tr('dlg.algorithm', 'Algorithm:'), 1, 1, 12, 1);
    Drop := TJSONObject.Create;
    Drop.AddPair('type', 'dropdown');
    Drop.AddPair('id', 'algo');
    Drop.AddPair('selected', TJSONNumber.Create(Saved));
    Names := TJSONArray.Create;
    for A := Low(TChecksumAlgo) to High(TChecksumAlgo) do
      Names.Add(cChecksumAlgoNames[A]);
    Drop.AddPair('items', Names);
    Drop.AddPair('col', TJSONNumber.Create(14));
    Drop.AddPair('row', TJSONNumber.Create(1));
    Drop.AddPair('width', TJSONNumber.Create(27));
    Drop.AddPair('height', TJSONNumber.Create(1));
    Kids.AddElement(Drop);
    AddControl(Kids, 'separator', '', '', 0, 3, 42, 1);
    AddControl(Kids, 'button', 'ok', Tr('dlg.ok', 'OK'), 8, 5, 12, 1, True);
    AddControl(Kids, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), 22, 5, 12, 1, False, True);
    if not ShowDeclaration(Decl, @OnOptionsDialog) then
      Notice(Tr('msg.noDialog', 'The dialog cannot be shown now.'), 1);
  finally
    Decl.Free;
  end;
end;

{ The files the command works on: the selection of the active panel, or the
  row under the cursor. Returns False (with a notice) when none is on disk. }
function CollectSources: Boolean;
var
  Root, Side: TJSONValue;
  Active, Uri, Panel: string;
  Selected: TJSONArray;
  I: Integer;
  Uris: TArray<string>;
begin
  Result := False;
  GPaths := nil;
  Root := TJSONObject.ParseJSONValue(HostText(GHostApi.PanelInfo));
  try
    if not (Root is TJSONObject) or not Root.TryGetValue<string>('active', Active) then
      Exit;
    Side := TJSONObject(Root).GetValue(Active);
    if not (Side is TJSONObject) then
      Exit;
    Side.TryGetValue<string>('uri', Panel);
    if Side.TryGetValue<TJSONArray>('selected', Selected) then
      for I := 0 to Selected.Count - 1 do
        Uris := Uris + [Selected.Items[I].Value];
    if (Length(Uris) = 0) and Side.TryGetValue<string>('cursor', Uri) and (Uri <> '') then
      Uris := [Uri];
  finally
    Root.Free;
  end;
  if Length(Uris) = 0 then
    Exit;
  for Uri in Uris do
  begin
    if not SameText(Copy(Uri, 1, 8), 'file:///') then
    begin
      Notice(Tr('msg.localOnly', 'Only for files and folders on disk'), 1);
      Exit;
    end;
    GPaths := GPaths + [FileUriToPath(Uri)];
  end;
  GBaseDir := FileUriToPath(Panel);
  Result := True;
end;

procedure CmdRun(AUserData: Pointer); cdecl;
var
  Algo: TChecksumAlgo;
begin
  try
    if GBusy then
    begin
      Notice(Tr('msg.busy', 'Checksums are already being calculated'), 1);
      Exit;
    end;
    if not CollectSources then
      Exit;
    // A checksum file on its own is verified, not hashed.
    if (Length(GPaths) = 1) and TFile.Exists(GPaths[0]) and
       ChecksumAlgoFromExt(GPaths[0], Algo) then
      StartJob(Algo, True)
    else
      ShowOptions;
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
  PluginId, CommandId, Chord: UTF8String;
begin
  if (AHostApi = nil) or (AHostApi.AbiVersion < 7) or not Assigned(AHostApi.PanelInfo) or
     not Assigned(AHostApi.ShowDialog) or not Assigned(AHostApi.PostToMain) or
     not Assigned(AHostApi.RegisterCommand) then
    Exit(-1);
  SdkAttach(AHostApi, cPluginId);
  GBusy := False;
  PluginId := UTF8String(cPluginId);
  CommandId := UTF8String(cCommandId);
  Chord := UTF8String(cKeyChord);
  GHostApi.RegisterCommand(PAnsiChar(PluginId), PAnsiChar(CommandId), @CmdRun, nil);
  if Assigned(GHostApi.RegisterKeyBinding) then
    GHostApi.RegisterKeyBinding(PAnsiChar(PluginId), PAnsiChar(CommandId), PAnsiChar(Chord));
  if Assigned(GHostApi.RegisterMenuItem) then
    GHostApi.RegisterMenuItem(PAnsiChar(PluginId), 'Files', PAnsiChar(CommandId),
      PAnsiChar(UTF8String(Tr('menu.run', '&Checksums...'))), @CmdRun, nil, 50);
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
