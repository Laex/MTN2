library SplitFilePlugin;

{ Native MTN2 plugin: Files > Split / combine... cuts the file under the cursor
  into numbered parts (name.001, name.002, ...) of a chosen size, or joins the
  parts back into one file when the cursor is on any part. The work runs in a
  background job. }

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uPluginSdk in '..\..\Core\uPluginSdk.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uFileSplit in 'uFileSplit.pas';

const
  cPluginId = 'mtn.splitfile';
  cCommandId = 'splitfile.run';
  cJobKey = 'run';
  cSettingSize = 'size';
  cDefaultSize = '100M';

var
  GSrc: string;
  GDestDir: string;
  GParts: TArray<string>;
  GCombine: Boolean;
  GSizeText: string;
  GBusy: Boolean;
  GCancel: Boolean;
  GFinished: Boolean;
  GStatus: string;
  GError: string;

procedure AddInput(AChildren: TJSONArray; const AId, AValue, AHistory: string;
  ARow: Integer);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', 'input');
  O.AddPair('id', AId);
  O.AddPair('value', AValue);
  O.AddPair('col', TJSONNumber.Create(1));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(66));
  O.AddPair('height', TJSONNumber.Create(1));
  O.AddPair('history', AHistory);
  AChildren.AddElement(O);
end;

{ ---- background job ----------------------------------------------------- }

procedure OnJobFinished(AUserData: Pointer); cdecl;
begin
  try
    JobEndNow(cJobKey);
    GBusy := False;
    if GShutdown or GCancel or not GFinished then
      Exit;
    if Assigned(GHostApi.PanelRefresh) then
      GHostApi.PanelRefresh;
    if GError <> '' then
      Notice(GError, 1)
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

{ Creates the folder; raises when it cannot exist, so a bad path is reported. }
procedure EnsureFolder(const ADir: string);
begin
  if (ADir <> '') and not ForceDirectories(ADir) and not TDirectory.Exists(ADir) then
    raise Exception.CreateFmt(Tr('msg.badDest', 'Cannot create the folder %s'), [ADir]);
end;

procedure RunJob(const ASrc, ADest: string; const AParts: TArray<string>;
  ACombine: Boolean; APartSize: Int64);
var
  Cancelled: TSplitCancelled;
  Done: Boolean;
  Count: Integer;
  Err, Status: string;
begin
  Cancelled :=
    function: Boolean
    begin
      Result := GCancel or GShutdown;
    end;
  Done := False;
  Count := 0;
  Err := '';
  Status := '';
  try
    if ACombine then
    begin
      EnsureFolder(ExtractFilePath(ADest));
      Done := CombineParts(AParts, ADest, Cancelled);
      Status := Format(Tr('msg.combineDone', 'Created %s'), [ExtractFileName(ADest)]);
    end
    else
    begin
      EnsureFolder(ADest);
      Done := SplitFile(ASrc, ADest, APartSize, Cancelled, Count);
      Status := Format(Tr('msg.splitDone', '%d parts created'), [Count]);
    end;
  except
    on E: Exception do
      Err := E.Message;
  end;
  GStatus := Status;
  GError := Err;
  GFinished := Done or (Err <> '');
  SdkPostToMain(@OnJobFinished);
end;

procedure StartJob(const ASrc, ADest: string; const AParts: TArray<string>;
  ACombine: Boolean; APartSize: Int64);
var
  Title: string;
  Parts: TArray<string>;
begin
  GBusy := True;
  GCancel := False;
  GFinished := False;
  if ACombine then
    Title := Tr('dlg.combineTitle', 'Combine files')
  else
    Title := Tr('dlg.splitTitle', 'Split file');
  JobBeginNow(cJobKey, Title, @OnJobCancel);
  Parts := Copy(AParts);
  SdkRunWorker(
    procedure
    begin
      RunJob(ASrc, ADest, Parts, ACombine, APartSize);
    end);
end;

{ ---- dialogs ------------------------------------------------------------ }

procedure ShowOptions(const ADest, ASize, AStatus: string); forward;

procedure OnOptionsDialog(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Root: TJSONValue;
  Dest, SizeText: string;
  PartSize: Int64;
begin
  try
    if not SameText(string(AControlId), 'ok') then
      Exit;
    Root := TJSONObject.ParseJSONValue(UTF8ToString(AValuesJson));
    try
      if not (Root is TJSONObject) or not Root.TryGetValue<string>('dest', Dest) then
        Exit;
      if not Root.TryGetValue<string>('size', SizeText) then
        SizeText := '';
    finally
      Root.Free;
    end;
    Dest := Trim(Dest);
    SizeText := Trim(SizeText);
    if Dest = '' then
    begin
      ShowOptions('', SizeText, Tr('msg.noDest', 'Enter where the result goes'));
      Exit;
    end;
    if GCombine then
    begin
      if TPath.IsRelativePath(Dest) then
        Dest := TPath.Combine(ExtractFilePath(GSrc), Dest);
      StartJob(GSrc, Dest, GParts, True, 0);
      Exit;
    end;
    if not ParseSplitSize(SizeText, PartSize) or (PartSize < cSplitMinPartSize) then
    begin
      ShowOptions(Dest, SizeText,
        Tr('msg.badSize', 'Part size: a number with K, M or G, at least 1K'));
      Exit;
    end;
    GSizeText := SizeText;
    SetSettingText(cSettingSize, SizeText);
    StartJob(GSrc, Dest, nil, False, PartSize);
  except
    // Never let an exception cross into the host.
  end;
end;

procedure ShowOptions(const ADest, ASize, AStatus: string);
var
  Decl: TJSONObject;
  Kids: TJSONArray;
  Height, ButtonRow: Integer;
begin
  if GCombine then
  begin
    Height := 10;
    ButtonRow := 6;
  end
  else
  begin
    Height := 13;
    ButtonRow := 9;
  end;
  Decl := NewDialog(Tr('dlg.title', 'Split / combine'), 70, Height, Kids);
  try
    if GCombine then
    begin
      AddControl(Kids, 'label', 'lbl_dest', Tr('dlg.resultFile', 'Result file:'), 1, 0, 66, 1);
      AddInput(Kids, 'dest', ADest, 'combinedest', 1);
    end
    else
    begin
      AddControl(Kids, 'label', 'lbl_dest', Tr('dlg.partsFolder', 'Parts go to folder:'), 1, 0, 66, 1);
      AddInput(Kids, 'dest', ADest, 'splitdest', 1);
      AddControl(Kids, 'label', 'lbl_size',
        Tr('dlg.partSize', 'Part size (for example 700M, 1.44M, 4G, 65536):'), 1, 3, 66, 1);
      AddInput(Kids, 'size', ASize, 'splitsize', 4);
    end;
    AddControl(Kids, 'label', 'status', AStatus, 1, ButtonRow - 2, 66, 1);
    AddControl(Kids, 'separator', '', '', 0, ButtonRow - 1, 68, 1);
    if GCombine then
      AddControl(Kids, 'button', 'ok', Tr('dlg.combine', 'Combine'), 19, ButtonRow, 14, 1, True)
    else
      AddControl(Kids, 'button', 'ok', Tr('dlg.split', 'Split'), 19, ButtonRow, 14, 1, True);
    AddControl(Kids, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), 35, ButtonRow, 14, 1,
      False, True);
    if not ShowDeclaration(Decl, @OnOptionsDialog) then
      Notice(Tr('msg.noDialog', 'The dialog cannot be shown now.'), 1);
  finally
    Decl.Free;
  end;
end;

{ ---- command ------------------------------------------------------------ }

{ The file the command works on (the row under the cursor, or the single
  selected file) and the folder of the other panel. Returns False, with a
  notice, when there is not exactly one file on disk. }
function CollectSource: Boolean;
var
  Root, Side, Other: TJSONValue;
  Active, Uri, OtherUri, OtherKey: string;
  Selected: TJSONArray;
  Uris: TArray<string>;
  Count: Integer;
begin
  Result := False;
  GSrc := '';
  GDestDir := '';
  Count := 0;
  Root := TJSONObject.ParseJSONValue(HostText(GHostApi.PanelInfo));
  try
    if not (Root is TJSONObject) or not Root.TryGetValue<string>('active', Active) then
      Exit;
    Side := TJSONObject(Root).GetValue(Active);
    if not (Side is TJSONObject) then
      Exit;
    // More than one selected file is rejected below; their URIs are not copied.
    Count := 0;
    if Side.TryGetValue<TJSONArray>('selected', Selected) then
      Count := Selected.Count;
    if Count = 1 then
      Uris := [Selected.Items[0].Value]
    else if (Count = 0) and Side.TryGetValue<string>('cursor', Uri) and (Uri <> '') then
    begin
      Uris := [Uri];
      Count := 1;
    end;
    if SameText(Active, 'left') then
      OtherKey := 'right'
    else
      OtherKey := 'left';
    Other := TJSONObject(Root).GetValue(OtherKey);
    if (Other is TJSONObject) and Other.TryGetValue<string>('uri', OtherUri) and
       SameText(Copy(OtherUri, 1, 8), 'file:///') then
      GDestDir := ExcludeTrailingPathDelimiter(FileUriToPath(OtherUri));
  finally
    Root.Free;
  end;
  if Count = 0 then
    Exit;
  if (Count <> 1) or not SameText(Copy(Uris[0], 1, 8), 'file:///') or
     not TFile.Exists(FileUriToPath(Uris[0])) then
  begin
    Notice(Tr('msg.oneFile', 'Select one file on disk'), 1);
    Exit;
  end;
  GSrc := FileUriToPath(Uris[0]);
  if (GDestDir = '') or not TDirectory.Exists(GDestDir) then
    GDestDir := ExcludeTrailingPathDelimiter(ExtractFilePath(GSrc));
  Result := True;
end;

procedure CmdRun(AUserData: Pointer); cdecl;
var
  Base: string;
  Idx: Integer;
begin
  try
    if GBusy then
    begin
      Notice(Tr('msg.busy', 'A split or combine is already running'), 1);
      Exit;
    end;
    if not CollectSource then
      Exit;
    GParts := nil;
    if SplitPartInfo(ExtractFileName(GSrc), Base, Idx) then
      GParts := CollectSplitParts(GSrc);
    GCombine := Length(GParts) > 0;
    if GCombine then
      ShowOptions(TPath.Combine(GDestDir, ExtractFileName(CombineDefaultName(GSrc))), '', '')
    else
    begin
      GSizeText := GetSettingText(cSettingSize);
      if GSizeText = '' then
        GSizeText := cDefaultSize;
      ShowOptions(GDestDir, GSizeText, '');
    end;
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
  PluginId, CommandId: UTF8String;
begin
  if (AHostApi = nil) or (AHostApi.AbiVersion < 7) or not Assigned(AHostApi.PanelInfo) or
     not Assigned(AHostApi.ShowDialog) or not Assigned(AHostApi.PostToMain) or
     not Assigned(AHostApi.RegisterCommand) then
    Exit(-1);
  SdkAttach(AHostApi, cPluginId);
  GBusy := False;
  PluginId := UTF8String(cPluginId);
  CommandId := UTF8String(cCommandId);
  GHostApi.RegisterCommand(PAnsiChar(PluginId), PAnsiChar(CommandId), @CmdRun, nil);
  if Assigned(GHostApi.RegisterMenuItem) then
    GHostApi.RegisterMenuItem(PAnsiChar(PluginId), 'Files', PAnsiChar(CommandId),
      PAnsiChar(UTF8String(Tr('menu.run', 'Split / combine...'))), @CmdRun, nil, 60);
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
