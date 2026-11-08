library EverythingPlugin;

{ Native MTN2 plugin: the results of a search in the Everything program as a panel
  (everything:///<query>). The rows point at the real files (targetUri), so viewing,
  editing, copying and deleting act on them. Plugins menu: Everything search. }

uses
  System.SysUtils,
  System.JSON,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uEverythingFormat in 'uEverythingFormat.pas',
  uEverythingIpc in 'uEverythingIpc.pas';

const
  cPluginId = 'mtn.everything';
  // Found files sit in many folders: nothing can be created or renamed in the list.
  cFBarJson =
    '{"root":{"F7":"","Shift+F4":"","Shift+F5":"","Shift+F6":""},' +
    '"inside":{"F7":"","Shift+F4":"","Shift+F5":"","Shift+F6":""}}';
  cScheme: UTF8String = 'everything';
  cMaxResults = 5000;

var
  GHost: PHostApiTable;
  GCallbacks: TVfsCallbacksCdeclV2;
  GLastQuery: string;

function Tr(const AKey, ADefault: string): string;
var
  Id, Key, Def: UTF8String;
  Buf: array[0..511] of AnsiChar;
  Len: Int64;
begin
  Result := ADefault;
  if (GHost = nil) or not Assigned(GHost.Translate) then
    Exit;
  Id := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Def := UTF8String(ADefault);
  Len := GHost.Translate(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(Def), @Buf[0], SizeOf(Buf));
  if (Len >= 0) and (Len < SizeOf(Buf)) then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

function Fail(ACtx: PVfsOpContext; ACode: TVfsCdeclResult; const AText: string): Int64;
var
  Text: UTF8String;
begin
  if (ACtx <> nil) and Assigned(ACtx^.SetErrorText) and (AText <> '') then
  begin
    Text := UTF8String(Copy(AText, 1, 400));
    ACtx^.SetErrorText(ACtx, PAnsiChar(Text));
  end;
  Result := Ord(ACode);
end;

function ItemsJson(const AItems: TEvItems): UTF8String;
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  Item: TEvItem;
begin
  Arr := TJSONArray.Create;
  try
    for Item in AItems do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('name', Item.Name);
      Obj.AddPair('size', TJSONNumber.Create(0));
      Obj.AddPair('isDir', TJSONBool.Create(Item.IsDir));
      Obj.AddPair('isLink', TJSONBool.Create(False));
      Obj.AddPair('isHidden', TJSONBool.Create(Item.Name.StartsWith('.')));
      Obj.AddPair('targetUri', PathToFileUri(ItemPath(Item)));
      Arr.AddElement(Obj);
    end;
    Result := UTF8String(Arr.ToJSON);
  finally
    Arr.Free;
  end;
end;

function VfsListDirectory(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  AOffset: Int64; ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64;
  out AMore: Int64): Int64; cdecl;
var
  Query, Err: string;
  Items: TEvItems;
  Json: UTF8String;
begin
  ANegotiatedSize := 0;
  AMore := 0;
  try
    if not ParseEverythingUri(string(UTF8String(AURI)), Query) then
      Exit(Ord(verInvalidURI));
    // The whole result goes in one page; a bigger one is asked again with a bigger buffer.
    if AOffset > 0 then
      Exit(Ord(verOk));
    if Trim(Query) = '' then
      Json := '[]'
    else
    begin
      if not EverythingSearch(Query, cMaxResults, Items, Err) then
        Exit(Fail(ACtx, verIOError, Tr('msg.failed', 'Everything: ') + Err));
      Json := ItemsJson(Items);
    end;
    if Length(Json) + 1 > ABufSize then
    begin
      ANegotiatedSize := Length(Json) + 1;
      Exit(Ord(verNeedsBiggerBuffer));
    end;
    if Length(Json) > 0 then
      Move(Json[1], ABuf^, Length(Json));
    ABuf[Length(Json)] := #0;
    ANegotiatedSize := Length(Json);
    Result := Ord(verOk);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsExists(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  out AIsDirectory: Int64): Int64; cdecl;
var
  Query: string;
begin
  AIsDirectory := 1;
  if ParseEverythingUri(string(UTF8String(AURI)), Query) then
    Result := Ord(verOk)
  else
    Result := Ord(verInvalidURI);
end;

function VfsDelete(AURI: PAnsiChar; AMode: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
begin
  Result := Ord(verNotSupported);
end;

function VfsCreateDirectory(AURI: PAnsiChar; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
begin
  Result := Ord(verNotSupported);
end;

function VfsCopyItem(AFromURI, AToURI: PAnsiChar; AFlags: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
begin
  Result := Ord(verNotSupported);
end;

function VfsReadText(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext; ABuf: PAnsiChar; ABufSize: Int64;
  out ANegotiatedSize: Int64): Int64; cdecl;
begin
  ANegotiatedSize := 0;
  Result := Ord(verNotSupported);
end;

function VfsReadBytes(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext; ABuf: PByte; ABufSize: Int64;
  out ANegotiatedSize: Int64): Int64; cdecl;
begin
  ANegotiatedSize := 0;
  Result := Ord(verNotSupported);
end;

function VfsWriteText(AURI: PAnsiChar; AText: PAnsiChar; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
begin
  Result := Ord(verNotSupported);
end;

function VfsGetFreeSpace(ARootURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  out AFree, ATotal: Int64): Int64; cdecl;
begin
  AFree := 0;
  ATotal := 0;
  Result := Ord(verNotSupported);
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

procedure OnSearchDialog(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Root: TJSONValue;
  Query: string;
  Uri: UTF8String;
begin
  try
    if string(UTF8String(AControlId)) <> 'ok' then
      Exit;
    Root := TJSONObject.ParseJSONValue(string(UTF8String(AValuesJson)));
    if Root = nil then
      Exit;
    try
      if not (Root is TJSONObject) or not TJSONObject(Root).TryGetValue<string>('query', Query) then
        Exit;
    finally
      Root.Free;
    end;
    Query := Trim(Query);
    if Query = '' then
      Exit;
    GLastQuery := Query;
    Uri := UTF8String(EverythingUri(Query));
    GHost.PanelGoto(-1, PAnsiChar(Uri));
  except
    // Never let an exception cross into the host.
  end;
end;

procedure MenuSearch(AUserData: Pointer); cdecl;
var
  Decl: TJSONObject;
  Kids: TJSONArray;
  Json, Plugin: UTF8String;
begin
  try
    if not Assigned(GHost.ShowDialog) or not Assigned(GHost.PanelGoto) then
      Exit;
    Decl := TJSONObject.Create;
    try
      Decl.AddPair('type', 'dialog');
      Decl.AddPair('version', '2.0');
      Decl.AddPair('title', Tr('dlg.title', 'Everything search'));
      Decl.AddPair('width', TJSONNumber.Create(60));
      Decl.AddPair('height', TJSONNumber.Create(8));
      Kids := TJSONArray.Create;
      Decl.AddPair('children', Kids);
      AddControl(Kids, 'label', '', Tr('dlg.hint', 'Search for:'), '', 2, 1, 54);
      AddControl(Kids, 'input', 'query', '', GLastQuery, 2, 2, 54);
      AddControl(Kids, 'button', 'ok', Tr('dlg.ok', 'OK'), '', 16, 4, 12, True);
      AddControl(Kids, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), '', 31, 4, 12, False, True);
      Json := UTF8String(Decl.ToJSON);
    finally
      Decl.Free;
    end;
    Plugin := UTF8String(cPluginId);
    GHost.ShowDialog(PAnsiChar(Plugin), PAnsiChar(Json), @OnSearchDialog, nil);
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
  Id, Parent, Item, Caption: UTF8String;
begin
  Result := -1;
  try
    if (AHostApi = nil) or (AHostApi.AbiVersion < 4) or
       not Assigned(AHostApi.RegisterVfsSchemeV2) then
      Exit;
    GHost := AHostApi;
    Id := UTF8String(cPluginId);
    GCallbacks.ListDirectory := VfsListDirectory;
    GCallbacks.Delete := VfsDelete;
    GCallbacks.CreateDirectory := VfsCreateDirectory;
    GCallbacks.CopyItem := VfsCopyItem;
    GCallbacks.MoveItem := VfsCopyItem;
    GCallbacks.ReadText := VfsReadText;
    GCallbacks.ReadBytes := VfsReadBytes;
    GCallbacks.WriteText := VfsWriteText;
    GCallbacks.Exists := VfsExists;
    GCallbacks.GetFreeSpace := VfsGetFreeSpace;
    AHostApi.RegisterVfsSchemeV2(PAnsiChar(Id), PAnsiChar(cScheme), @GCallbacks, nil, 60);
    if Assigned(AHostApi.RegisterPanelPlugin) then
      AHostApi.RegisterPanelPlugin(PAnsiChar(Id), PAnsiChar(cScheme), 60);
    if Assigned(AHostApi.SetPanelFBar) then
      AHostApi.SetPanelFBar(PAnsiChar(Id), PAnsiChar(cScheme), PAnsiChar(UTF8String(cFBarJson)));
    if Assigned(AHostApi.RegisterMenuItem) then
    begin
      Parent := 'Plugins';
      Item := 'everything_search';
      Caption := UTF8String(Tr('menu.search', 'Everything search...'));
      AHostApi.RegisterMenuItem(PAnsiChar(Id), PAnsiChar(Parent), PAnsiChar(Item),
        PAnsiChar(Caption), @MenuSearch, nil, 50);
    end;
    Result := 0;
  except
    Result := -1;
  end;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  GHost := nil;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
