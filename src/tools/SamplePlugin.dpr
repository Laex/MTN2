library SamplePlugin;

{ Minimal reference plugin DLL exercising the mtn_plugin_* ABI end-to-end:
  exports the three required entry points, and in mtn_plugin_init registers
  a "sample://" VFS scheme and one "Commands" menu item. Used by
  TestPluginLoader.dpr to verify TPluginLoader actually LoadLibrary()s and
  wires up a real DLL, not just an in-process unit call. }

uses
  System.SysUtils, System.Classes,
  uPluginHostAbi in '..\Core\uPluginHostAbi.pas';

var
  GHostApi: PHostApiTable;

function SampleListDirectory(AURI: PAnsiChar; AUserData: Pointer;
  ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
const
  cJson: UTF8String =
    '[{"name":"sample-item.txt","ext":"txt","size":42,"isDir":false}]';
begin
  ANegotiatedSize := Length(cJson) + 1; // + trailing #0
  if ANegotiatedSize > ABufSize then
    Exit(Int64(verNeedsBiggerBuffer));
  Move(PAnsiChar(cJson)^, ABuf^, Length(cJson) + 1);
  ANegotiatedSize := Length(cJson);
  Result := Int64(verOk);
end;

function SampleExists(AURI: PAnsiChar; AUserData: Pointer;
  out AIsDirectory: Int64): Int64; cdecl;
begin
  AIsDirectory := 0;
  Result := Int64(verOk); // everything under sample:// "exists" for this demo
end;

function SampleNotSupported: Int64; cdecl;
begin
  Result := Int64(verNotSupported);
end;

function SampleDelete(AURI: PAnsiChar; AMode: Int64; AUserData: Pointer): Int64; cdecl;
begin
  Result := Int64(verNotSupported);
end;

function SampleCreateDirectory(AURI: PAnsiChar; AUserData: Pointer): Int64; cdecl;
begin
  Result := Int64(verNotSupported);
end;

function SampleCopyItem(AFromURI, AToURI: PAnsiChar; AOverwrite: Int64;
  AUserData: Pointer): Int64; cdecl;
begin
  Result := Int64(verNotSupported);
end;

function SampleMoveItem(AFromURI, AToURI: PAnsiChar; AOverwrite: Int64;
  AUserData: Pointer): Int64; cdecl;
begin
  Result := Int64(verNotSupported);
end;

function SampleReadText(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
  ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
begin
  ANegotiatedSize := 0;
  Result := Int64(verNotSupported);
end;

function SampleReadBytes(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
  ABuf: PByte; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
begin
  ANegotiatedSize := 0;
  Result := Int64(verNotSupported);
end;

function SampleWriteText(AURI: PAnsiChar; AText: PAnsiChar; AUserData: Pointer): Int64; cdecl;
begin
  Result := Int64(verNotSupported);
end;

function SampleGetFreeSpace(ARootURI: PAnsiChar; AUserData: Pointer;
  out AFree, ATotal: Int64): Int64; cdecl;
begin
  AFree := 0;
  ATotal := 0;
  Result := Int64(verOk);
end;

procedure SampleMenuOnClick(AUserData: Pointer); cdecl;
begin
  // Demo callback — a real plugin would do something UI-visible here.
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
var
  Callbacks: TVfsCallbacksCdecl;
begin
  if AHostApi = nil then
    Exit(-1);
  GHostApi := AHostApi;

  FillChar(Callbacks, SizeOf(Callbacks), 0);
  Callbacks.ListDirectory := @SampleListDirectory;
  Callbacks.Delete := @SampleDelete;
  Callbacks.CreateDirectory := @SampleCreateDirectory;
  Callbacks.CopyItem := @SampleCopyItem;
  Callbacks.MoveItem := @SampleMoveItem;
  Callbacks.ReadText := @SampleReadText;
  Callbacks.ReadBytes := @SampleReadBytes;
  Callbacks.WriteText := @SampleWriteText;
  Callbacks.Exists := @SampleExists;
  Callbacks.GetFreeSpace := @SampleGetFreeSpace;

  if Assigned(AHostApi.RegisterVfsScheme) then
    AHostApi.RegisterVfsScheme(PAnsiChar(UTF8String('SamplePlugin')),
      PAnsiChar(UTF8String('sample')), @Callbacks, nil, 50);

  if Assigned(AHostApi.RegisterMenuItem) then
    AHostApi.RegisterMenuItem(PAnsiChar(UTF8String('SamplePlugin')),
      PAnsiChar(UTF8String('Commands')), PAnsiChar(UTF8String('sample_item')),
      PAnsiChar(UTF8String('Sample Plugin Item')), @SampleMenuOnClick, nil, 100);

  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  GHostApi := nil;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
