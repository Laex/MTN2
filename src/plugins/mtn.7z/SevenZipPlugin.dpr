library SevenZipPlugin;

{ Native MTN2 VFS plugin: 7z:// backed by a local archive engine: 7z.dll from
  this folder on Windows, a 7-Zip command line program on POSIX (LGPL both).
  Archives open like folders; entries are listed, read, unpacked and packed. }

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uSevenZipApi,
  uPlatformProcess, uPlatformInfo,
  uSevenZipVfs in 'uSevenZipVfs.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas';

var
  GHostApi: PHostApiTable;
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

function WriteBytesBuf(const AData: TBytes; ABuf: PByte; ABufSize: Int64;
  out ANegotiatedSize: Int64): Int64;
begin
  ANegotiatedSize := Length(AData);
  if ANegotiatedSize > ABufSize then
    Exit(Int64(verNeedsBiggerBuffer));
  if ANegotiatedSize > 0 then
    Move(AData[0], ABuf^, ANegotiatedSize);
  Result := Int64(verOk);
end;

function SzListDirectory(AURI: PAnsiChar; AUserData: Pointer;
  ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
var
  ArchivePath, Inner: string;
  Json: UTF8String;
  Code: Int64;
begin
  ANegotiatedSize := 0;
  if not ParseSevenZipUri(UTF8ToString(AURI), ArchivePath, Inner) then
    Exit(Int64(verInvalidURI));
  if not SevenZipListToJson(ArchivePath, Inner, Json, Code) then
    Exit(Code);
  Result := WriteUtf8Buf(Json, ABuf, ABufSize, ANegotiatedSize);
end;

function SzExists(AURI: PAnsiChar; AUserData: Pointer;
  out AIsDirectory: Int64): Int64; cdecl;
var
  ArchivePath, Inner: string;
  IsDir: Boolean;
  Code: Int64;
begin
  AIsDirectory := 0;
  if not ParseSevenZipUri(UTF8ToString(AURI), ArchivePath, Inner) then
    Exit(Int64(verInvalidURI));
  if not SevenZipExistsAt(ArchivePath, Inner, IsDir, Code) then
    Exit(Code);
  AIsDirectory := Ord(IsDir);
  Result := Int64(verOk);
end;

function SzReadBytes(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
  ABuf: PByte; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
var
  ArchivePath, Inner: string;
  Data: TBytes;
  Code, Cap: Int64;
begin
  ANegotiatedSize := 0;
  if not ParseSevenZipUri(UTF8ToString(AURI), ArchivePath, Inner) then
    Exit(Int64(verInvalidURI));
  Cap := ABufSize;
  if (AMaxBytes > 0) and (AMaxBytes < Cap) then
    Cap := AMaxBytes;
  if not SevenZipReadFile(ArchivePath, Inner, Cap, Data, Code) then
  begin
    if Code = Int64(verNeedsBiggerBuffer) then
      ANegotiatedSize := Cap + 1;
    Exit(Code);
  end;
  Result := WriteBytesBuf(Data, ABuf, ABufSize, ANegotiatedSize);
end;

function SzReadText(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
  ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
var
  ArchivePath, Inner: string;
  Data: TBytes;
  Code, Cap: Int64;
  Text: UTF8String;
begin
  ANegotiatedSize := 0;
  if not ParseSevenZipUri(UTF8ToString(AURI), ArchivePath, Inner) then
    Exit(Int64(verInvalidURI));
  Cap := ABufSize;
  if (AMaxBytes > 0) and (AMaxBytes < Cap) then
    Cap := AMaxBytes;
  if not SevenZipReadFile(ArchivePath, Inner, Cap, Data, Code) then
    Exit(Code);
  SetLength(Text, Length(Data));
  if Length(Data) > 0 then
    Move(Data[0], Text[1], Length(Data));
  Result := WriteUtf8Buf(Text, ABuf, ABufSize, ANegotiatedSize);
end;

// An archive has no recycle bin, so both delete modes remove the entry. A
// path that descends into an archive nested inside another one points at a
// temporary extraction, which must not be edited.
function SzDelete(AURI: PAnsiChar; AMode: Int64; AUserData: Pointer): Int64; cdecl;
var
  URI, ArchivePath, Inner, Err: string;
begin
  URI := UTF8ToString(AURI);
  if not ParseSevenZipUri(URI, ArchivePath, Inner) then
    Exit(Int64(verInvalidURI));
  if (Pos('!/', URI) > 0) and (Pos('!/', Copy(URI, Pos('!/', URI) + 2, MaxInt)) > 0) then
    Exit(Int64(verNotSupported));
  if SevenZipNormInner(Inner) = '' then
    Exit(Int64(verNotSupported));
  if SevenZipDeleteInner(ArchivePath, Inner, Err) then
    Exit(Int64(verOk));
  if Err = 'Not found' then
    Result := Int64(verNotFound)
  else if (Err = 'Encrypted') or (Err = 'Cannot replace archive') then
    Result := Int64(verAccessDenied)
  else if (Err = 'This archive format cannot be updated') or (Err = '7-Zip is not available') then
    Result := Int64(verNotSupported)
  else
    Result := Int64(verIOError);
end;

function SzCreateDirectory(AURI: PAnsiChar; AUserData: Pointer): Int64; cdecl;
begin
  Result := Int64(verNotSupported);
end;

function SzCopyItem(AFromURI, AToURI: PAnsiChar; AOverwrite: Int64;
  AUserData: Pointer): Int64; cdecl;
var
  FromURI, ToURI, FromPath, ArchivePath, Inner, Dummy, Err: string;
begin
  FromURI := UTF8ToString(AFromURI);
  ToURI := UTF8ToString(AToURI);
  // Unpack an entry straight to a local file: no plugin-buffer size limit.
  if ParseSevenZipUri(FromURI, ArchivePath, Inner) then
  begin
    FromPath := FileUriToPath(ToURI);
    if (FromPath = '') or ParseSevenZipUri(ToURI, Dummy, Dummy) then
      Exit(Int64(verNotSupported));
    if (AOverwrite = 0) and TFile.Exists(FromPath) then
      Exit(Int64(verAlreadyExists));
    if SevenZipExtractToFile(ArchivePath, Inner, FromPath, Err) then
      Exit(Int64(verOk));
    if Err = 'Not found' then
      Exit(Int64(verNotFound));
    if Err = 'Encrypted' then
      Exit(Int64(verAccessDenied));
    Exit(Int64(verIOError));
  end;
  if not ParseSevenZipUri(ToURI, ArchivePath, Inner) then
    Exit(Int64(verNotSupported));
  if ParseSevenZipUri(FromURI, Dummy, Dummy) then
    Exit(Int64(verNotSupported));
  FromPath := FileUriToPath(FromURI);
  if FromPath = '' then
    Exit(Int64(verInvalidURI));
  if not SameText(ExtractFileExt(ArchivePath), '.7z') then
    Exit(Int64(verNotSupported));
  if Inner = '' then
    Inner := ExtractFileName(ExcludeTrailingPathDelimiter(FromPath));
  if not SevenZipAddLocalPath(ArchivePath, FromPath, Inner, AOverwrite <> 0, Err) then
  begin
    if Pos('already exists', LowerCase(Err)) > 0 then
      Exit(Int64(verAlreadyExists));
    Exit(Int64(verNotSupported));
  end;
  Result := Int64(verOk);
end;

function SzMoveItem(AFromURI, AToURI: PAnsiChar; AOverwrite: Int64;
  AUserData: Pointer): Int64; cdecl;
begin
  Result := Int64(verNotSupported);
end;

function SzWriteText(AURI: PAnsiChar; AText: PAnsiChar; AUserData: Pointer): Int64; cdecl;
begin
  Result := Int64(verNotSupported);
end;

function SzGetFreeSpace(ARootURI: PAnsiChar; AUserData: Pointer;
  out AFree, ATotal: Int64): Int64; cdecl;
var
  ArchivePath, Inner: string;
begin
  AFree := 0;
  ATotal := 0;
  if not ParseSevenZipUri(UTF8ToString(ARootURI), ArchivePath, Inner) then
    Exit(Int64(verInvalidURI));
  PlatformDiskSpace(ExtractFilePath(ArchivePath), AFree, ATotal);
  Result := Int64(verOk);
end;

const
  cHeaderKeyPrefix = 'header-encryption:';
  cLevelKeyPrefix = 'compression-level:';

// A key is an archive path (the value is its password), cHeaderKeyPrefix plus an
// archive path (any value asks for encrypted file names when packing) or
// cLevelKeyPrefix plus an archive path (the value is the 7-Zip level 0..9).
function mtn_plugin_set_secret(AKeyUtf8, AValueUtf8: PAnsiChar): Int64; cdecl;
var
  Key: string;
begin
  if AKeyUtf8 = nil then
    Exit(-1);
  Key := UTF8ToString(AKeyUtf8);
  if Key = '' then
    Exit(-1);
  if Key.StartsWith(cLevelKeyPrefix) then
  begin
    if AValueUtf8 = nil then
      SevenZipSetCompressionLevel(Copy(Key, Length(cLevelKeyPrefix) + 1, MaxInt), -1)
    else
      SevenZipSetCompressionLevel(Copy(Key, Length(cLevelKeyPrefix) + 1, MaxInt),
        StrToIntDef(UTF8ToString(AValueUtf8), -1));
    Exit(0);
  end;
  if Key.StartsWith(cHeaderKeyPrefix) then
  begin
    SevenZipSetHeaderEncryption(Copy(Key, Length(cHeaderKeyPrefix) + 1, MaxInt),
      AValueUtf8 <> nil);
    Exit(0);
  end;
  if AValueUtf8 = nil then
    SevenZipClearPassword(Key)
  else
    SevenZipSetPassword(Key, UTF8ToString(AValueUtf8));
  Result := 0;
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
var
  EnginePath: string;
begin
  if AHostApi = nil then
    Exit(-1);
  GHostApi := AHostApi;
  EnginePath := PlatformSevenZipEngine(ExtractFilePath(GetModuleName(HInstance)));
  if (EnginePath = '') or not SevenZipLoadEngine(EnginePath) then
    Exit(-2);

  FillChar(GVfsCallbacks, SizeOf(GVfsCallbacks), 0);
  GVfsCallbacks.ListDirectory := @SzListDirectory;
  GVfsCallbacks.Delete := @SzDelete;
  GVfsCallbacks.CreateDirectory := @SzCreateDirectory;
  GVfsCallbacks.CopyItem := @SzCopyItem;
  GVfsCallbacks.MoveItem := @SzMoveItem;
  GVfsCallbacks.ReadText := @SzReadText;
  GVfsCallbacks.ReadBytes := @SzReadBytes;
  GVfsCallbacks.WriteText := @SzWriteText;
  GVfsCallbacks.Exists := @SzExists;
  GVfsCallbacks.GetFreeSpace := @SzGetFreeSpace;

  if Assigned(AHostApi.RegisterVfsScheme) then
    AHostApi.RegisterVfsScheme(PAnsiChar(UTF8String('mtn.7z')),
      PAnsiChar(UTF8String('7z')), @GVfsCallbacks, nil, 40);
  if Assigned(AHostApi.RegisterPanelPlugin) then
    AHostApi.RegisterPanelPlugin(PAnsiChar(UTF8String('mtn.7z')),
      PAnsiChar(UTF8String('7z')), 40);
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  SevenZipClearAllPasswords;
  SevenZipUnloadEngine;
  GHostApi := nil;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown,
  mtn_plugin_set_secret;

begin
end.
