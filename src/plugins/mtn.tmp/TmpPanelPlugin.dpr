library TmpPanelPlugin;

{ Native MTN2 VFS plugin: Far-style Temporary panel. Scheme tmp:/// holds
  references to real files (F5 onto the panel adds them; F8 deletes the
  real files because list rows use targetUri = file://). }

uses
  System.SysUtils, System.Classes,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uTmpPanelStore in 'uTmpPanelStore.pas';

var
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

  Parent := UTF8String('Commands');
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
