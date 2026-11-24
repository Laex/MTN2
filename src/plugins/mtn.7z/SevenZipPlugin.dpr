library SevenZipPlugin;

{ Native MTN2 VFS plugin: 7z:// backed by a local archive engine: 7z.dll from
  this folder on Windows, a 7-Zip command line program on POSIX (LGPL both).
  Archives open like folders; entries are listed, read, unpacked and packed. }

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Math, System.SyncObjs,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uPluginSdk in '..\..\Core\uPluginSdk.pas',
  uSevenZipApi,
  uPlatformProcess, uPlatformInfo,
  uSevenZipVfs in 'uSevenZipVfs.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas';

var
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
  IsDir: Boolean;
  Code: Int64;
begin
  FromURI := UTF8ToString(AFromURI);
  ToURI := UTF8ToString(AToURI);
  // Unpack an entry straight to a local file: no plugin-buffer size limit.
  if ParseSevenZipUri(FromURI, ArchivePath, Inner) then
  begin
    FromPath := FileUriToPath(ToURI);
    if (FromPath = '') or ParseSevenZipUri(ToURI, Dummy, Dummy) then
      Exit(Int64(verNotSupported));
    // A folder unpacks in one pass over the archive: unpacking its files one
    // by one re-reads a solid archive from the start for every file.
    if SevenZipExistsAt(ArchivePath, Inner, IsDir, Code) and IsDir then
    begin
      if SevenZipExtractTree(ArchivePath, Inner, FromPath, AOverwrite <> 0, Err) then
        Exit(Int64(verOk));
      if Err = 'Already exists' then
        Exit(Int64(verAlreadyExists));
    end
    else
    begin
      if (AOverwrite = 0) and TFile.Exists(FromPath) then
        Exit(Int64(verAlreadyExists));
      if SevenZipExtractToFile(ArchivePath, Inner, FromPath, Err) then
        Exit(Int64(verOk));
    end;
    if Err = 'Not found' then
      Exit(Int64(verNotFound));
    if (Err = 'Encrypted') or (Err = 'Access denied') then
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

const
  cPluginId = 'mtn.7z';
  cTestCommand = 'sevenzip.test';
  cTestJobKey = 'archive.test';

var
  GTestBusy: Integer;
  GTestCancel: Integer;
  GTestText: string;
  GTestKind: Int64;
  GTestJob: Boolean;
  GTestLock: TCriticalSection;

/// <summary>The file under the cursor of the active panel (a file: URI); empty
/// when the cursor is on no file.</summary>
function CursorFileUri: string;
var
  Root, Side: TJSONValue;
  Active: string;
  IsDir: Boolean;
  Json: string;
begin
  Result := '';
  Json := HostText(GHostApi.PanelInfo);
  if Json = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(Json);
  try
    if not (Root is TJSONObject) or not Root.TryGetValue<string>('active', Active) then
      Exit;
    Side := Root.GetValue<TJSONValue>(Active, nil);
    if not (Side is TJSONObject) or not Side.TryGetValue<string>('cursor', Result) then
      Exit('');
    IsDir := False;
    Side.TryGetValue<Boolean>('cursorIsDirectory', IsDir);
    if IsDir then
      Result := '';
  finally
    Root.Free;
  end;
end;

function HostHasJobs: Boolean;
begin
  Result := (GHostApi.AbiVersion >= 7) and Assigned(GHostApi.JobBegin) and
    Assigned(GHostApi.JobEnd);
end;

procedure OnTestJobCancel(AUserData: Pointer); cdecl;
begin
  TInterlocked.Exchange(GTestCancel, 1);
end;

procedure EndTestJob;
var
  Plugin, Key: UTF8String;
begin
  if not GTestJob then
    Exit;
  GTestJob := False;
  Plugin := UTF8String(cPluginId);
  Key := UTF8String(cTestJobKey);
  GHostApi.JobEnd(PAnsiChar(Plugin), PAnsiChar(Key));
end;

{ Main thread: the run is over - report it. }
procedure MainTestDone(AUserData: Pointer); cdecl;
var
  Text: string;
  Kind: Int64;
begin
  try
    EndTestJob;
    GTestLock.Enter;
    try
      Text := GTestText;
      Kind := GTestKind;
      GTestText := '';
    finally
      GTestLock.Leave;
    end;
    TInterlocked.Exchange(GTestBusy, 0);
    if Text <> '' then
      Notice(Text, Kind);
  except
  end;
end;

type
  TArchiveTestThread = class(TThread)
  private
    FPath: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const APath: string);
  end;

constructor TArchiveTestThread.Create(const APath: string);
begin
  FPath := APath;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TArchiveTestThread.Execute;
var
  R: T7zTestResult;
  Err, Text: string;
  Kind: Int64;
  I: Integer;
begin
  Kind := 0;
  try
    if not SevenZipTestArchive(FPath,
      function: Boolean
      begin
        Result := Terminated or (TInterlocked.CompareExchange(GTestCancel, 0, 0) <> 0);
      end, R, Err) then
    begin
      Kind := 1;
      if Err = 'Encrypted' then
        Text := Tr('msg.testEncrypted', 'The archive is encrypted: open it and enter the password first.')
      else
        Text := Tr('msg.testUnsupported', 'This archive cannot be tested.');
    end
    else if R.Cancelled then
      Text := Tr('msg.cancelled', 'Cancelled.')
    else if R.Failed = 0 then
      Text := Format(Tr('msg.testOk', '%d files OK'), [R.Checked])
    else
    begin
      Kind := 1;
      Text := Format(Tr('msg.testFailed', '%d of %d files are damaged:'), [R.Failed, R.Checked]);
      for I := 0 to Min(High(R.Errors), 9) do
        Text := Text + sLineBreak + R.Errors[I];
      if Length(R.Errors) > 10 then
        Text := Text + sLineBreak + '...';
    end;
  except
    Kind := 1;
    Text := Tr('msg.testUnsupported', 'This archive cannot be tested.');
  end;
  GTestLock.Enter;
  try
    GTestText := Text;
    GTestKind := Kind;
  finally
    GTestLock.Leave;
  end;
  if Assigned(GHostApi.PostToMain) then
    GHostApi.PostToMain(PAnsiChar(UTF8String(cPluginId)), MainTestDone, nil);
end;

{ The "Test archive" command: checks the archive under the cursor of the active
  panel against its checksums, in the background. }
procedure CmdTestArchive(AUserData: Pointer); cdecl;
var
  Plugin, Key, Title: UTF8String;
  Uri, Local: string;
begin
  try
    if not Assigned(GHostApi.PostToMain) then
      Exit;
    Uri := CursorFileUri;
    Local := '';
    if Uri <> '' then
      Local := FileUriToPath(Uri);
    if (Local = '') or not TFile.Exists(Local) then
    begin
      Notice(Tr('msg.testNoFile', 'Put the cursor on an archive file on disk.'), 0);
      Exit;
    end;
    if TInterlocked.CompareExchange(GTestBusy, 1, 0) <> 0 then
      Exit;
    TInterlocked.Exchange(GTestCancel, 0);
    GTestJob := HostHasJobs;
    if GTestJob then
    begin
      Plugin := UTF8String(cPluginId);
      Key := UTF8String(cTestJobKey);
      Title := UTF8String(Tr('msg.testJob', 'Archive test'));
      GHostApi.JobBegin(PAnsiChar(Plugin), PAnsiChar(Key), PAnsiChar(Title), @OnTestJobCancel, nil);
    end;
    TArchiveTestThread.Create(Local);
  except
    TInterlocked.Exchange(GTestBusy, 0);
  end;
end;

{$IFDEF MSWINDOWS}
const
  cSfxCommand = 'sevenzip.sfx';

var
  GSfxText: string;
  GSfxBusy: Integer;

{ The self-extracting module (7z.sfx) of this plugin folder, 7-Zip or Far ArcLite. }
function FindSfxModule: string;
var
  Candidates: TArray<string>;
  C, PF: string;
begin
  PF := GetEnvironmentVariable('ProgramFiles');
  Candidates := [
    TPath.Combine(ExtractFilePath(GetModuleName(HInstance)), '7z.sfx'),
    TPath.Combine(PF, '7-Zip\7z.sfx'),
    TPath.Combine(PF, 'Far Manager\Plugins\ArcLite\7z.sfx')];
  for C in Candidates do
    if (C <> '') and TFile.Exists(C) then
      Exit(C);
  Result := '';
end;

procedure MainSfxDone(AUserData: Pointer); cdecl;
var
  Text: string;
begin
  GTestLock.Enter;
  try
    Text := GSfxText;
  finally
    GTestLock.Leave;
  end;
  TInterlocked.Exchange(GSfxBusy, 0);
  Notice(Text, 0);
end;

{ Writes ASfx followed by the archive as AOut: a program that unpacks the archive. }
function WriteSfx(const ASfx, AArchive, AOut: string; out AError: string): Boolean;
var
  Dst, Src: TFileStream;
begin
  Result := False;
  AError := '';
  try
    Dst := TFileStream.Create(AOut, fmCreate);
    try
      Src := TFileStream.Create(ASfx, fmOpenRead or fmShareDenyWrite);
      try
        Dst.CopyFrom(Src, 0);
      finally
        Src.Free;
      end;
      Src := TFileStream.Create(AArchive, fmOpenRead or fmShareDenyWrite);
      try
        Dst.CopyFrom(Src, 0);
      finally
        Src.Free;
      end;
    finally
      Dst.Free;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      if TFile.Exists(AOut) then
        TFile.Delete(AOut);
    end;
  end;
end;

{ The "Make self-extracting archive" command: turns the .7z under the cursor into
  a program next to it; an existing file is never replaced. }
procedure CmdMakeSfx(AUserData: Pointer); cdecl;
var
  Uri, Local, Sfx, Target, DoneFmt, FailText: string;
  N: Integer;
begin
  try
    if not Assigned(GHostApi.PostToMain) then
      Exit;
    Uri := CursorFileUri;
    Local := '';
    if Uri <> '' then
      Local := FileUriToPath(Uri);
    if (Local = '') or not TFile.Exists(Local) or not SameText(ExtractFileExt(Local), '.7z') then
    begin
      Notice(Tr('msg.sfxNoFile', 'Put the cursor on a .7z archive on disk.'), 0);
      Exit;
    end;
    Sfx := FindSfxModule;
    if Sfx = '' then
    begin
      Notice(Tr('msg.sfxNoModule', '7z.sfx was not found: put it into the plugin folder.'), 1);
      Exit;
    end;
    if TInterlocked.CompareExchange(GSfxBusy, 1, 0) <> 0 then
      Exit;
    Target := ChangeFileExt(Local, '.exe');
    N := 1;
    while TFile.Exists(Target) do
    begin
      Inc(N);
      Target := ChangeFileExt(Local, '') + ' (' + IntToStr(N) + ').exe';
    end;
    DoneFmt := Tr('msg.sfxDone', 'Created %s');
    FailText := Tr('msg.sfxFailed', 'Could not create the program: ');
    TThread.CreateAnonymousThread(
      procedure
      var
        Err, Text: string;
      begin
        if WriteSfx(Sfx, Local, Target, Err) then
          Text := Format(DoneFmt, [ExtractFileName(Target)])
        else
          Text := FailText + Err;
        GTestLock.Enter;
        try
          GSfxText := Text;
        finally
          GTestLock.Leave;
        end;
        if Assigned(GHostApi.PostToMain) then
          GHostApi.PostToMain(PAnsiChar(UTF8String(cPluginId)), MainSfxDone, nil)
        else
          TInterlocked.Exchange(GSfxBusy, 0);
      end).Start;
  except
    TInterlocked.Exchange(GSfxBusy, 0);
  end;
end;
{$ENDIF}

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
  SdkAttach(AHostApi, cPluginId);
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
  GTestLock := TCriticalSection.Create;
  if Assigned(AHostApi.RegisterCommand) and Assigned(AHostApi.PanelInfo) and
     Assigned(AHostApi.PostToMain) then
  begin
    AHostApi.RegisterCommand(PAnsiChar(UTF8String(cPluginId)), PAnsiChar(UTF8String(cTestCommand)),
      @CmdTestArchive, nil);
    if Assigned(AHostApi.RegisterMenuItem) then
      AHostApi.RegisterMenuItem(PAnsiChar(UTF8String(cPluginId)), 'Plugins',
        PAnsiChar(UTF8String(cTestCommand)),
        PAnsiChar(UTF8String(Tr('ui.menu.test', 'Test archive (checksums)'))),
        @CmdTestArchive, nil, 72);
{$IFDEF MSWINDOWS}
    AHostApi.RegisterCommand(PAnsiChar(UTF8String(cPluginId)), PAnsiChar(UTF8String(cSfxCommand)),
      @CmdMakeSfx, nil);
    if Assigned(AHostApi.RegisterMenuItem) then
      AHostApi.RegisterMenuItem(PAnsiChar(UTF8String(cPluginId)), 'Plugins',
        PAnsiChar(UTF8String(cSfxCommand)),
        PAnsiChar(UTF8String(Tr('ui.menu.sfx', 'Make self-extracting archive (.exe)'))),
        @CmdMakeSfx, nil, 73);
{$ENDIF}
  end;
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  TInterlocked.Exchange(GTestCancel, 1);
  SevenZipClearAllPasswords;
  SevenZipUnloadEngine;
  SdkDetach;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown,
  mtn_plugin_set_secret;

begin
end.
