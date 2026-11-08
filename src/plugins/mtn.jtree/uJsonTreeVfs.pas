unit uJsonTreeVfs;

{ The version 2 VFS callbacks for jtree:///. A JSON or YAML file is a read-only tree:
  listing, existence, reading a value and copying a value or a subtree out to a local
  file. Everything that changes the tree is refused. }

interface

uses
  uPluginHostAbi;

function JsonTreeVfsCallbacks: TVfsCallbacksCdeclV2;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, uVfsTypes, uJsonTree;

function UriOf(AURI: PAnsiChar): string;
begin
  Result := string(UTF8String(AURI));
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

function CodeOf(AResult: TJtResult; ACtx: PVfsOpContext; const AError: string): Int64;
begin
  case AResult of
    jrOk: Result := Ord(verOk);
    jrNotFound: Result := Fail(ACtx, verNotFound, AError);
  else
    Result := Fail(ACtx, verIOError, AError);
  end;
end;

procedure PutBytes(const ABytes: TBytes; ABuf: PByte; ABufSize: Int64; ATerminate: Boolean;
  out ANegotiated: Int64; out AFits: Boolean);
var
  Need: Int64;
begin
  Need := Length(ABytes);
  if ATerminate then
    Inc(Need);
  AFits := Need <= ABufSize;
  // Fitting: the length of the data alone (no terminator); otherwise the size to ask for.
  if AFits then
    ANegotiated := Length(ABytes)
  else
    ANegotiated := Need;
  if not AFits then
    Exit;
  if Length(ABytes) > 0 then
    Move(ABytes[0], ABuf^, Length(ABytes));
  if ATerminate then
    ABuf[Length(ABytes)] := 0;
end;

function EntryJson(const AEntry: TJtEntry): TJSONObject;
var
  Extra: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AEntry.Name);
  Result.AddPair('size', TJSONNumber.Create(AEntry.Size));
  Result.AddPair('isDir', TJSONBool.Create(AEntry.IsDir));
  Result.AddPair('isLink', TJSONBool.Create(False));
  Result.AddPair('isHidden', TJSONBool.Create(False));
  Extra := TJSONObject.Create;
  Extra.AddPair('type', AEntry.Kind);
  Extra.AddPair('value', AEntry.Preview);
  Result.AddPair('extra', Extra);
end;

function VfsListDirectory(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  AOffset: Int64; ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64;
  out AMore: Int64): Int64; cdecl;
var
  FilePath, Err: string;
  Path: TArray<string>;
  Entries: TJtEntries;
  Arr: TJSONArray;
  Entry: TJtEntry;
  Bytes: TBytes;
  Fits: Boolean;
begin
  ANegotiatedSize := 0;
  AMore := 0;
  try
    if not ParseTreeUri(UriOf(AURI), FilePath, Path) then
      Exit(Ord(verInvalidURI));
    // The whole listing goes in one page; a bigger one is asked again with a bigger buffer.
    if AOffset > 0 then
      Exit(Ord(verOk));
    Result := CodeOf(TreeList(FilePath, Path, Entries, Err), ACtx, Err);
    if Result <> Ord(verOk) then
      Exit;
    Arr := TJSONArray.Create;
    try
      for Entry in Entries do
        Arr.AddElement(EntryJson(Entry));
      Bytes := TEncoding.UTF8.GetBytes(Arr.ToJSON);
    finally
      Arr.Free;
    end;
    PutBytes(Bytes, PByte(ABuf), ABufSize, True, ANegotiatedSize, Fits);
    if Fits then
      Result := Ord(verOk)
    else
      Result := Ord(verNeedsBiggerBuffer);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsExists(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  out AIsDirectory: Int64): Int64; cdecl;
var
  FilePath, Err: string;
  Path: TArray<string>;
  IsDir: Boolean;
begin
  AIsDirectory := 0;
  try
    if not ParseTreeUri(UriOf(AURI), FilePath, Path) then
      Exit(Ord(verInvalidURI));
    Result := CodeOf(TreeStat(FilePath, Path, IsDir, Err), ACtx, Err);
    if (Result = Ord(verOk)) and IsDir then
      AIsDirectory := 1;
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function ReadValue(AURI: PAnsiChar; AMaxBytes: Int64; ACtx: PVfsOpContext; ABuf: PByte;
  ABufSize: Int64; ATerminate: Boolean; out ANegotiated: Int64): Int64;
var
  FilePath, Err, Text: string;
  Path: TArray<string>;
  Bytes: TBytes;
  Fits: Boolean;
begin
  ANegotiated := 0;
  try
    if not ParseTreeUri(UriOf(AURI), FilePath, Path) then
      Exit(Ord(verInvalidURI));
    Result := CodeOf(TreeText(FilePath, Path, Text, Err), ACtx, Err);
    if Result <> Ord(verOk) then
      Exit;
    Bytes := TEncoding.UTF8.GetBytes(Text);
    if (AMaxBytes > 0) and (Length(Bytes) > AMaxBytes) then
      SetLength(Bytes, AMaxBytes);
    PutBytes(Bytes, ABuf, ABufSize, ATerminate, ANegotiated, Fits);
    if Fits then
      Result := Ord(verOk)
    else
      Result := Ord(verNeedsBiggerBuffer);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsReadText(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext; ABuf: PAnsiChar; ABufSize: Int64;
  out ANegotiatedSize: Int64): Int64; cdecl;
begin
  Result := ReadValue(AURI, AMaxBytes, ACtx, PByte(ABuf), ABufSize, True, ANegotiatedSize);
end;

function VfsReadBytes(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext; ABuf: PByte; ABufSize: Int64;
  out ANegotiatedSize: Int64): Int64; cdecl;
begin
  Result := ReadValue(AURI, AMaxBytes, ACtx, ABuf, ABufSize, False, ANegotiatedSize);
end;

function VfsCopyItem(AFromURI, AToURI: PAnsiChar; AFlags: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  FilePath, Err, Text, Target: string;
  Path: TArray<string>;
begin
  try
    if not ParseTreeUri(UriOf(AFromURI), FilePath, Path) then
      Exit(Fail(ACtx, verNotSupported, 'Only values can be copied out of a tree'));
    Target := FileUriToPath(UriOf(AToURI));
    if Target = '' then
      Exit(Fail(ACtx, verNotSupported, 'A tree can be copied to a local folder only'));
    Result := CodeOf(TreeText(FilePath, Path, Text, Err), ACtx, Err);
    if Result <> Ord(verOk) then
      Exit;
    if TFile.Exists(Target) and ((AFlags and 1) = 0) then
      Exit(Fail(ACtx, verAlreadyExists, 'The file exists'));
    TFile.WriteAllText(Target, Text, TUTF8Encoding.Create(False));
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsRefuseUri(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext): Int64; cdecl;
begin
  Result := Fail(ACtx, verNotSupported, 'The tree is read-only');
end;

function VfsDelete(AURI: PAnsiChar; AMode: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
begin
  Result := Fail(ACtx, verNotSupported, 'The tree is read-only');
end;

function VfsMoveItem(AFromURI, AToURI: PAnsiChar; AFlags: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
begin
  Result := Fail(ACtx, verNotSupported, 'The tree is read-only');
end;

function VfsWriteText(AURI: PAnsiChar; AText: PAnsiChar; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
begin
  Result := Fail(ACtx, verNotSupported, 'The tree is read-only');
end;

function VfsGetFreeSpace(ARootURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  out AFree, ATotal: Int64): Int64; cdecl;
begin
  AFree := 0;
  ATotal := 0;
  Result := Ord(verNotSupported);
end;

function JsonTreeVfsCallbacks: TVfsCallbacksCdeclV2;
begin
  Result := Default(TVfsCallbacksCdeclV2);
  Result.ListDirectory := VfsListDirectory;
  Result.Delete := VfsDelete;
  Result.CreateDirectory := VfsRefuseUri;
  Result.CopyItem := VfsCopyItem;
  Result.MoveItem := VfsMoveItem;
  Result.ReadText := VfsReadText;
  Result.ReadBytes := VfsReadBytes;
  Result.WriteText := VfsWriteText;
  Result.Exists := VfsExists;
  Result.GetFreeSpace := VfsGetFreeSpace;
end;

end.
