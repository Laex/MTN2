library DescribePlugin;

{ Native MTN2 plugin: Files > Describe (Ctrl+Alt+Z) stores a one-line description
  of the selected items, or of the item under the cursor, in the Descript.ion
  file of the folder (the Far and Total Commander format). The panels read the
  same file for the status line. Local folders only. }

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Generics.Collections,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uDescriptIon in '..\..\Core\uDescriptIon.pas';

const
  cPluginId = 'mtn.describe';
  cCommandId = 'describe.run';
  cDialogWidth = 60;

var
  GHostApi: THostApiTable;
  GShutdown: Boolean;
  GDir: string;
  GNames: TArray<string>;
  GValue: string;
  GPrompt: string;

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

function HostPanelListText: string;
var
  Buf: UTF8String;
  Len: Int64;
begin
  Result := '';
  if not Assigned(GHostApi.PanelList) then
    Exit;
  Len := GHostApi.PanelList(-1, nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Buf, Len + 1);
  Len := GHostApi.PanelList(-1, PAnsiChar(Buf), Length(Buf));
  if (Len > 0) and (Len < Length(Buf)) then
    Result := UTF8ToString(PAnsiChar(Buf));
end;

function StripSlash(const AName: string): string;
begin
  Result := AName;
  if (Result <> '') and (Result[Length(Result)] = '/') then
    Delete(Result, Length(Result), 1);
end;

{ ---- dialog ------------------------------------------------------------- }

procedure AddItem(AChildren: TJSONArray; const AType, AId, AText: string;
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

function BuildDeclaration: TJSONObject;
var
  Kids: TJSONArray;
  Field: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'dialog');
  Result.AddPair('version', '2.0');
  Result.AddPair('title', Tr('dlg.title', 'Describe'));
  Result.AddPair('width', TJSONNumber.Create(cDialogWidth));
  Result.AddPair('height', TJSONNumber.Create(8));
  Kids := TJSONArray.Create;
  Result.AddPair('children', Kids);
  AddItem(Kids, 'label', 'prompt', GPrompt, 1, 0, cDialogWidth - 4);
  Field := TJSONObject.Create;
  Field.AddPair('type', 'input');
  Field.AddPair('id', 'text');
  Field.AddPair('value', GValue);
  Field.AddPair('col', TJSONNumber.Create(1));
  Field.AddPair('row', TJSONNumber.Create(1));
  Field.AddPair('width', TJSONNumber.Create(cDialogWidth - 4));
  Field.AddPair('height', TJSONNumber.Create(1));
  Kids.AddElement(Field);
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
  List, Info, Side: TJSONValue;
  Rows, Selected: TJSONArray;
  Row: TJSONValue;
  Sel: TArray<string>;
  Uri, Name, ActiveSide, DirUri: string;
  Cursor, I: Integer;
begin
  Result := False;
  GNames := nil;
  List := TJSONObject.ParseJSONValue(HostPanelListText);
  Info := TJSONObject.ParseJSONValue(HostText(GHostApi.PanelInfo));
  try
    if not (List is TJSONObject) or not (Info is TJSONObject) or
       not TJSONObject(List).TryGetValue<string>('uri', DirUri) or
       not TJSONObject(List).TryGetValue<TJSONArray>('rows', Rows) then
    begin
      Notice(Tr('msg.nothing', 'Nothing to describe'), 1);
      Exit;
    end;
    GDir := '';
    if DirUri.StartsWith('file:', True) and (Pos('!/', DirUri) = 0) then
      GDir := FileUriToPath(DirUri);
    if (GDir = '') or not TDirectory.Exists(GDir) then
    begin
      Notice(Tr('msg.local', 'Descriptions need a folder on a local disk'), 1);
      Exit;
    end;
    if TJSONObject(Info).TryGetValue<string>('active', ActiveSide) then
    begin
      Side := TJSONObject(Info).GetValue(ActiveSide);
      if (Side is TJSONObject) and TJSONObject(Side).TryGetValue<TJSONArray>('selected', Selected) then
        for I := 0 to Selected.Count - 1 do
          Sel := Sel + [Selected.Items[I].Value];
    end;
    if Length(Sel) > 0 then
    begin
      for Row in Rows do
        if (Row is TJSONObject) and TJSONObject(Row).TryGetValue<string>('uri', Uri) and
           TJSONObject(Row).TryGetValue<string>('name', Name) then
          for I := 0 to High(Sel) do
            if Sel[I] = Uri then
            begin
              GNames := GNames + [StripSlash(Name)];
              Break;
            end;
    end
    else if TJSONObject(List).TryGetValue<Integer>('cursor', Cursor) and
            (Cursor >= 0) and (Cursor < Rows.Count) and (Rows.Items[Cursor] is TJSONObject) and
            TJSONObject(Rows.Items[Cursor]).TryGetValue<string>('name', Name) then
      GNames := [StripSlash(Name)];
    if Length(GNames) = 0 then
    begin
      Notice(Tr('msg.nothing', 'Nothing to describe'), 1);
      Exit;
    end;
    Result := True;
  finally
    List.Free;
    Info.Free;
  end;
end;

procedure CmdRun(AUserData: Pointer); cdecl;
var
  Decl: TJSONObject;
  Json, Plugin: UTF8String;
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
      Json := UTF8String(Decl.ToJSON);
    finally
      Decl.Free;
    end;
    Plugin := UTF8String(cPluginId);
    if not Assigned(GHostApi.ShowDialog) or
       (GHostApi.ShowDialog(PAnsiChar(Plugin), PAnsiChar(Json), @OnDialogCommand, nil) <> 0) then
      Notice(Tr('msg.noDialog', 'The dialog cannot be shown now'), 1);
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
  GHostApi := AHostApi^;
  GShutdown := False;
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
  GShutdown := True;
  GNames := nil;
  FillChar(GHostApi, SizeOf(GHostApi), 0);
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
