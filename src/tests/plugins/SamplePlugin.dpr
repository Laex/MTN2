library SamplePlugin;

{ Minimal reference plugin DLL exercising the mtn_plugin_* ABI end-to-end:
  exports the three required entry points, and in mtn_plugin_init registers
  a "sample://" VFS scheme and one "Commands" menu item. Used by
  TestPluginLoader.dpr to verify TPluginLoader LoadLibrary()s and
  wires up a real DLL, not just an in-process unit call. }

uses
  System.SysUtils, System.Classes,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas';

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
  // Demo callback - a real plugin would do something UI-visible here.
end;

procedure SampleCommandRun(AUserData: Pointer); cdecl;
begin
  if (GHostApi <> nil) and Assigned(GHostApi.HostPublish) then
    GHostApi.HostPublish(PAnsiChar(UTF8String('SamplePlugin')),
      PAnsiChar(UTF8String('sample.ran')), PAnsiChar(UTF8String('{}')));
end;

{ Takes the activation of rows whose URI ends in ".take" (directories excluded). }
function SamplePanelActivate(AUserData: Pointer; APanelURI, ARowURI: PAnsiChar;
  AIsDirectory: Int64): Int64; cdecl;
var
  U: AnsiString;
begin
  U := AnsiString(ARowURI);
  if (AIsDirectory = 0) and (Copy(U, Length(U) - 4, 5) = '.take') then
    Result := 1
  else
    Result := 0;
end;

procedure SampleConfigure(AUserData: Pointer); cdecl;
var
  Buf: array[0..63] of AnsiChar;
begin
  if (GHostApi = nil) or not Assigned(GHostApi.SetSetting) or not Assigned(GHostApi.GetSetting) then
    Exit;
  GHostApi.SetSetting(PAnsiChar(UTF8String('SamplePlugin')), 'mode', 'fast');
  Buf[0] := #0;
  if GHostApi.GetSetting(PAnsiChar(UTF8String('SamplePlugin')), 'mode', @Buf[0], SizeOf(Buf)) >= 0 then
    GHostApi.HostPublish(PAnsiChar(UTF8String('SamplePlugin')),
      PAnsiChar(UTF8String('sample.configured')), @Buf[0]);
end;

procedure SampleDialogAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
begin
  if (GHostApi <> nil) and Assigned(GHostApi.HostPublish) then
    GHostApi.HostPublish(PAnsiChar(UTF8String('SamplePlugin')),
      PAnsiChar(UTF8String('sample.dialog.answer')), AControlId);
end;

procedure SampleDialogRun(AUserData: Pointer); cdecl;
const
  cDialog: UTF8String =
    '{"type":"dialog","title":"Sample","children":[' +
    '{"type":"button","id":"ok","text":"OK","default":true}]}';
begin
  if (GHostApi <> nil) and Assigned(GHostApi.ShowDialog) then
    GHostApi.ShowDialog(PAnsiChar(UTF8String('SamplePlugin')), PAnsiChar(cDialog),
      @SampleDialogAnswer, nil);
end;

{ Handles Wipe typed on the keyboard; lets the menu item and every other
  command through. }
function SampleCommandHook(AUserData: Pointer; ACommand, AOrigin: PAnsiChar): Int64; cdecl;
begin
  if (StrComp(AOrigin, 'key') = 0) then
    Result := 1
  else
    Result := 0;
end;

{ ".samplehandled" files are opened by the plugin itself; ".sampledoc" files
  are redirected to a sample:// text file for the viewer and left to the
  built-in editor. }
function SampleDocProvider(AUserData: Pointer; AURI, AMode: PAnsiChar;
  ARedirect: PAnsiChar; ARedirectCap: Int64): Int64; cdecl;
const
  cTarget: AnsiString = 'sample:///redirected.txt';
var
  U: AnsiString;
begin
  U := AnsiString(AURI);
  if Copy(U, Length(U) - 13, 14) = '.samplehandled' then
    Exit(1);
  if (StrComp(AMode, 'view') <> 0) or (Length(cTarget) + 1 > ARedirectCap) then
    Exit(0);
  StrCopy(ARedirect, PAnsiChar(cTarget));
  Result := 2;
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

  if Assigned(AHostApi.RegisterCommand) then
    AHostApi.RegisterCommand(PAnsiChar(UTF8String('SamplePlugin')),
      PAnsiChar(UTF8String('sample.hello')), @SampleCommandRun, nil);

  if Assigned(AHostApi.RegisterCommand) then
    AHostApi.RegisterCommand(PAnsiChar(UTF8String('SamplePlugin')),
      PAnsiChar(UTF8String('sample.dialog')), @SampleDialogRun, nil);

  if Assigned(AHostApi.RegisterKeyBinding) then
    AHostApi.RegisterKeyBinding(PAnsiChar(UTF8String('SamplePlugin')),
      PAnsiChar(UTF8String('sample.hello')), PAnsiChar(UTF8String('Ctrl+Alt+F12')));

  if Assigned(AHostApi.RegisterCommandHook) then
    AHostApi.RegisterCommandHook(PAnsiChar(UTF8String('SamplePlugin')),
      PAnsiChar(UTF8String('Wipe')), @SampleCommandHook, nil, 100);

  if Assigned(AHostApi.RegisterSettings) then
    AHostApi.RegisterSettings(PAnsiChar(UTF8String('SamplePlugin')), @SampleConfigure, nil);

  if Assigned(AHostApi.SetCommandCaption) then
    AHostApi.SetCommandCaption(PAnsiChar(UTF8String('SamplePlugin')),
      PAnsiChar(UTF8String('sample.hello')), PAnsiChar(UTF8String('Hello')));

  if Assigned(AHostApi.SetStatusSegment) then
    AHostApi.SetStatusSegment(PAnsiChar(UTF8String('SamplePlugin')),
      PAnsiChar(UTF8String('state')), PAnsiChar(UTF8String('sample-status')));

  if Assigned(AHostApi.RegisterPanelActivate) then
    AHostApi.RegisterPanelActivate(PAnsiChar(UTF8String('SamplePlugin')),
      PAnsiChar(UTF8String('sample')), @SamplePanelActivate, nil);

  if Assigned(AHostApi.RegisterDocumentProvider) then
    AHostApi.RegisterDocumentProvider(PAnsiChar(UTF8String('SamplePlugin')),
      PAnsiChar(UTF8String('.sampledoc,.samplehandled')), 3, @SampleDocProvider, nil, 100);

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
