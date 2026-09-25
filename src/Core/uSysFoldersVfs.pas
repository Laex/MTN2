unit uSysFoldersVfs;

{ Virtual file system backend for sys://folders.
  Lists Windows system directories (Desktop, Documents, Downloads, AppData, etc.).
  Each entry has TargetURI set to its real file:// path.

  CROSS-PLATFORM (Этап 23): the folder set/lookup (SHGetKnownFolderPath-class
  APIs) is Windows-only; POSIX equivalents are XDG user dirs (Linux) /
  NSSearchPathForDirectoriesInDomains (macOS) -- different sources, same
  sys://folders scheme and TargetURI contract for callers. }

interface

uses
  uVfsTypes, uTextEncoding;

type
  TSysFoldersVirtualFileSystem = class(TInterfacedObject, IVirtualFileSystem)
  public
    procedure ListDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsListCallback);
    procedure DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
      ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
      AOnDone: TVfsBoolCallback);
    procedure CreateDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsBoolCallback);
    procedure CopyAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure MoveAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure ReadTextAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
    procedure ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
    procedure WriteTextAsync(const AURI, AText: string; AEncoding: TTextFileEncoding;
      ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
    procedure ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsExistsCallback);
    procedure GetFreeSpaceAsync(const ARootURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsFreeSpaceCallback);
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, Winapi.Windows, Winapi.ShLObj;

procedure QueueList(const AOnDone: TVfsListCallback; const AItems: TArray<TVfsEntry>;
  const AError: TVfsError);
var
  Items: TArray<TVfsEntry>;
  Err: TVfsError;
  Cb: TVfsListCallback;
begin
  Items := AItems;
  Err := AError;
  Cb := AOnDone;
  if not Assigned(Cb) then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      Cb(Items, Err);
    end);
end;

procedure QueueBool(const AOnDone: TVfsBoolCallback; AOk: Boolean; const AError: TVfsError);
var
  Ok: Boolean;
  Err: TVfsError;
  Cb: TVfsBoolCallback;
begin
  Ok := AOk;
  Err := AError;
  Cb := AOnDone;
  if not Assigned(Cb) then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      Cb(Ok, Err);
    end);
end;

procedure QueueExists(const AOnDone: TVfsExistsCallback; AExists, AIsDir: Boolean;
  const AError: TVfsError);
var
  Exists, IsDir: Boolean;
  Err: TVfsError;
  Cb: TVfsExistsCallback;
begin
  Exists := AExists;
  IsDir := AIsDir;
  Err := AError;
  Cb := AOnDone;
  if not Assigned(Cb) then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      Cb(Exists, IsDir, Err);
    end);
end;

procedure QueueText(const AOnDone: TVfsTextCallback; const AText: string;
  AEncoding: TTextFileEncoding; const AError: TVfsError);
var
  Text: string;
  Enc: TTextFileEncoding;
  Err: TVfsError;
  Cb: TVfsTextCallback;
begin
  Text := AText;
  Enc := AEncoding;
  Err := AError;
  Cb := AOnDone;
  if not Assigned(Cb) then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      Cb(Text, Enc, Err);
    end);
end;

procedure QueueBytes(const AOnDone: TVfsBytesCallback; const ABytes: TBytes;
  const AError: TVfsError);
var
  Bytes: TBytes;
  Err: TVfsError;
  Cb: TVfsBytesCallback;
begin
  Bytes := ABytes;
  Err := AError;
  Cb := AOnDone;
  if not Assigned(Cb) then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      Cb(Bytes, Err);
    end);
end;

function GetSpecialFolderPath(ACSIDL: Integer): string;
var
  Path: array[0..MAX_PATH] of Char;
begin
  Result := '';
  if SHGetFolderPath(0, ACSIDL, 0, SHGFP_TYPE_CURRENT, Path) = S_OK then
    Result := string(Path);
end;

procedure AddSysFolder(var AList: TArray<TVfsEntry>; const AName: string; ACSIDL: Integer);
var
  RealPath: string;
  E: TVfsEntry;
  N: Integer;
begin
  RealPath := GetSpecialFolderPath(ACSIDL);
  if (RealPath = '') or not TDirectory.Exists(RealPath) then
    Exit;
  FillChar(E, SizeOf(E), 0);
  E.Name := AName;
  E.IsDirectory := True;
  E.TargetURI := PathToFileUri(RealPath);
  try
    E.ModificationTime := TDirectory.GetLastWriteTime(RealPath);
  except
  end;
  N := Length(AList);
  SetLength(AList, N + 1);
  AList[N] := E;
end;

procedure TSysFoldersVirtualFileSystem.ListDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsListCallback);
var
  URI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsListCallback;
begin
  URI := AURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Items: TArray<TVfsEntry>;
      Err: TVfsError;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      SetLength(Items, 0);
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', URI)
        else
        begin
          AddSysFolder(Items, 'Desktop', CSIDL_DESKTOPDIRECTORY);
          AddSysFolder(Items, 'Documents', CSIDL_PERSONAL);
          AddSysFolder(Items, 'Downloads', CSIDL_PROFILE);
          try
            if TDirectory.Exists(TPath.Combine(GetSpecialFolderPath(CSIDL_PROFILE), 'Downloads')) then
              Items[High(Items)].TargetURI := PathToFileUri(TPath.Combine(GetSpecialFolderPath(CSIDL_PROFILE), 'Downloads'));
          except
          end;
          if Length(Items) > 0 then
            Items[High(Items)].Name := 'Downloads';

          AddSysFolder(Items, 'Pictures', CSIDL_MYPICTURES);
          AddSysFolder(Items, 'Music', CSIDL_MYMUSIC);
          AddSysFolder(Items, 'Videos', CSIDL_MYVIDEO);
          AddSysFolder(Items, 'Program Files', CSIDL_PROGRAM_FILES);
          AddSysFolder(Items, 'Program Files (x86)', CSIDL_PROGRAM_FILESX86);
          AddSysFolder(Items, 'Windows', CSIDL_WINDOWS);
          AddSysFolder(Items, 'System32', CSIDL_SYSTEM);
          AddSysFolder(Items, 'AppData (Roaming)', CSIDL_APPDATA);
          AddSysFolder(Items, 'AppData (Local)', CSIDL_LOCAL_APPDATA);
          AddSysFolder(Items, 'UserProfile', CSIDL_PROFILE);
          AddSysFolder(Items, 'Common AppData', CSIDL_COMMON_APPDATA);
        end;
      except
        on Ex: Exception do
          Err := TVfsError.Make(vecIOError, Ex.Message, URI);
      end;
      QueueList(OnDone, Items, Err);
    end).Start;
end;

procedure TSysFoldersVirtualFileSystem.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
begin
  QueueBool(AOnDone, False, TVfsError.Make(vecNotSupported, 'Read-only virtual system folders', AURI));
end;

procedure TSysFoldersVirtualFileSystem.CreateDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  QueueBool(AOnDone, False, TVfsError.Make(vecNotSupported, 'Read-only virtual system folders', AURI));
end;

procedure TSysFoldersVirtualFileSystem.CopyAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite, APreserveTimestamps: Boolean);
begin
  QueueBool(AOnDone, False, TVfsError.Make(vecNotSupported, 'Read-only virtual system folders', AFromURI));
end;

procedure TSysFoldersVirtualFileSystem.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite, APreserveTimestamps: Boolean);
begin
  QueueBool(AOnDone, False, TVfsError.Make(vecNotSupported, 'Read-only virtual system folders', AFromURI));
end;

procedure TSysFoldersVirtualFileSystem.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
begin
  QueueText(AOnDone, '', tfeUtf8, TVfsError.Make(vecNotSupported, 'Not a text file', AURI));
end;

procedure TSysFoldersVirtualFileSystem.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
begin
  QueueBytes(AOnDone, nil, TVfsError.Make(vecNotSupported, 'Not a binary file', AURI));
end;

procedure TSysFoldersVirtualFileSystem.WriteTextAsync(const AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  QueueBool(AOnDone, False, TVfsError.Make(vecNotSupported, 'Read-only virtual system folders', AURI));
end;

procedure TSysFoldersVirtualFileSystem.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
begin
  QueueExists(AOnDone, True, True, TVfsError.Ok);
end;

procedure TSysFoldersVirtualFileSystem.GetFreeSpaceAsync(const ARootURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsFreeSpaceCallback);
var
  Cb: TVfsFreeSpaceCallback;
begin
  Cb := AOnDone;
  if Assigned(Cb) then
    TThread.Queue(nil,
      procedure
      begin
        Cb(-1, -1, TVfsError.Ok);
      end);
end;

end.
