library DescribePlugin;

{ Native MTN2 plugin: Files > Describe (Ctrl+Alt+Z) stores a one-line description
  of the selected items, or of the item under the cursor, in the Descript.ion
  file of the folder (the Far and Total Commander format). The panels read the
  same file for the status line. Local folders only. }

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Generics.Collections,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uPluginSdk in '..\..\Core\uPluginSdk.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uDescriptIon in '..\..\Core\uDescriptIon.pas';

const
  cPluginId = 'mtn.describe';
  cCommandId = 'describe.run';
  cDialogWidth = 60;

var
  GDir: string;
  GNames: TArray<string>;
  GValue: string;
  GPrompt: string;

function StripSlash(const AName: string): string;
begin
  Result := AName;
  if (Result <> '') and (Result[Length(Result)] = '/') then
    Delete(Result, Length(Result), 1);
end;

{ ---- dialog ------------------------------------------------------------- }

function BuildDeclaration: TJSONObject;
var
  Kids: TJSONArray;
begin
  Result := NewDialog(Tr('dlg.title', 'Describe'), cDialogWidth, 8, Kids);
  AddItem(Kids, 'label', 'prompt', GPrompt, 1, 0, cDialogWidth - 4);
  AddField(Kids, 'text', GValue, 1, 1, cDialogWidth - 4);
  AddItem(Kids, 'separator', '', '', 0, 3, cDialogWidth - 2);
  AddItem(Kids, 'button', 'ok', Tr('dlg.ok', 'OK'), cDialogWidth div 2 - 12, 5, 10, True);
  AddItem(Kids, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), cDialogWidth div 2 + 2, 5, 10,
    False, True);
end;

procedure OnDialogCommand(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Root: TJSONValue;
  Text, Name: string;
  Ok: Boolean;
begin
  try
    if GShutdown or not SameText(string(AControlId), 'ok') or (AValuesJson = nil) then
      Exit;
    Root := TJSONObject.ParseJSONValue(UTF8ToString(AValuesJson));
    try
      if not (Root is TJSONObject) then
        Exit;
      Text := '';
      TJSONObject(Root).TryGetValue<string>('text', Text);
    finally
      Root.Free;
    end;
    Text := Trim(Text);
    Ok := True;
    for Name in GNames do
      Ok := StoreDescription(GDir, Name, Text) and Ok;
    if Assigned(GHostApi.PanelRefresh) then
      GHostApi.PanelRefresh;
    if not Ok then
      Notice(Tr('msg.failed', 'Cannot write Descript.ion here'), 1);
  except
    // Never let an exception cross into the host.
  end;
end;

{ ---- panel -------------------------------------------------------------- }

{ Reads the panel: the names of the selected rows of the active panel, or of
  the row under the cursor. False, with a message shown, when there are none. }
function CollectNames: Boolean;
var
  DirUri: string;
  Names: TList<string>;
begin
  Result := False;
  GNames := nil;
  GDir := '';
  Names := TList<string>.Create;
  try
    if not ForEachSelectedRow(DirUri,
      procedure(ARow: TJSONObject)
      var
        Name: string;
      begin
        if ARow.TryGetValue<string>('name', Name) then
          Names.Add(StripSlash(Name));
      end) then
    begin
      Notice(Tr('msg.nothing', 'Nothing to describe'), 1);
      Exit;
    end;
    GNames := Names.ToArray;
    if DirUri.StartsWith('file:', True) and (Pos('!/', DirUri) = 0) then
      GDir := FileUriToPath(DirUri);
    if (GDir = '') or not TDirectory.Exists(GDir) then
    begin
      Notice(Tr('msg.local', 'Descriptions need a folder on a local disk'), 1);
      Exit;
    end;
    if Length(GNames) = 0 then
    begin
      Notice(Tr('msg.nothing', 'Nothing to describe'), 1);
      Exit;
    end;
    Result := True;
  finally
    Names.Free;
  end;
end;

procedure CmdRun(AUserData: Pointer); cdecl;
var
  Decl: TJSONObject;
  Map: TDictionary<string, string>;
begin
  try
    if not CollectNames then
      Exit;
    GValue := '';
    if Length(GNames) = 1 then
    begin
      GPrompt := GNames[0];
      Map := LoadDescriptions(GDir);
      try
        if not Map.TryGetValue(GNames[0], GValue) then
          GValue := '';
      finally
        Map.Free;
      end;
    end
    else
      GPrompt := Format(Tr('dlg.many', '%d items'), [Length(GNames)]);
    Decl := BuildDeclaration;
    try
      if not ShowDeclaration(Decl, @OnDialogCommand) then
        Notice(Tr('msg.noDialog', 'The dialog cannot be shown now'), 1);
    finally
      Decl.Free;
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
  if (AHostApi = nil) or (AHostApi.AbiVersion < 13) or not Assigned(AHostApi.PanelInfo) or
     not Assigned(AHostApi.PanelList) or not Assigned(AHostApi.ShowDialog) or
     not Assigned(AHostApi.RegisterCommand) then
    Exit(-1);
  SdkAttach(AHostApi, cPluginId);
  PluginId := UTF8String(cPluginId);
  CommandId := UTF8String(cCommandId);
  GHostApi.RegisterCommand(PAnsiChar(PluginId), PAnsiChar(CommandId), @CmdRun, nil);
  if Assigned(GHostApi.RegisterKeyBinding) then
    GHostApi.RegisterKeyBinding(PAnsiChar(PluginId), PAnsiChar(CommandId), 'Ctrl+Alt+Z');
  if Assigned(GHostApi.RegisterMenuItem) then
    GHostApi.RegisterMenuItem(PAnsiChar(PluginId), 'Files', PAnsiChar(CommandId),
      PAnsiChar(UTF8String(Tr('menu.run', 'Describe...'))), @CmdRun, nil, 55);
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  GNames := nil;
  SdkDetach;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
