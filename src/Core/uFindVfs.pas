unit uFindVfs;

{ Virtual panel for Alt+F7 results: find://session/<id>/ lists hit files.
  Row TargetURI points at real file:// so View/Copy use the file backend. }

interface

uses
  uVfsTypes, uTextEncoding;

type
  TFindVirtualFileSystem = class(TInterfacedObject, IVirtualFileSystem)
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
  System.SysUtils, System.Classes, System.IOUtils, Winapi.Windows,
  uFindSession;

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

function DisplayNameForHit(const ARoot, AFull: string): string;
var
  RootSlash: string;
begin
  RootSlash := IncludeTrailingPathDelimiter(ARoot);
  if AFull.StartsWith(RootSlash, True) then
    Result := Copy(AFull, Length(RootSlash) + 1, MaxInt)
  else if SameText(AFull, ARoot) then
    Result := ExtractFileName(AFull)
  else
    Result := AFull;
  if Result = '' then
    Result := ExtractFileName(AFull);
end;

procedure TFindVirtualFileSystem.ListDirectoryAsync(const AURI: string;
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
      Data: TFindSessionData;
      Items: TArray<TVfsEntry>;
      Err: TVfsError;
      I: Integer;
      Path: string;
      E: TVfsEntry;
      Attr: DWORD;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      SetLength(Items, 0);
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', URI)
        else if not IsFindUri(URI) then
          Err := TVfsError.Make(vecInvalidURI, 'Not a find URI', URI)
        else if not TryGetFindSessionFromUri(URI, Data) then
          Err := TVfsError.Make(vecNotFound, 'Find session expired', URI)
        else
        begin
          SetLength(Items, Length(Data.Hits));
          for I := 0 to High(Data.Hits) do
          begin
            if JobCancelRequested(Cancel) then
            begin
              Err := TVfsError.Make(vecCancelled, 'Cancelled', URI);
              SetLength(Items, 0);
              Break;
            end;
            Path := Data.Hits[I].Path;
            E.Name := DisplayNameForHit(Data.RootPath, Path);
            E.Extension := LowerCase(TPath.GetExtension(Path));
            E.MatchLine := Data.Hits[I].Line;
            E.MatchSnippet := Data.Hits[I].Snippet;
            E.IsDirectory := False;
            E.IsHidden := False;
            E.IsReadOnly := False;
            E.IsSystem := False;
            E.IsArchive := False;
            E.IsCompressed := False;
            E.IsEncrypted := False;
            E.IsTemporary := False;
            E.IsOffline := False;
            E.IsLink := False;
            E.TargetURI := PathToFileUri(Path);
            E.Size := -1;
            E.CreationTime := 0;
            E.ModificationTime := 0;
            E.AccessTime := 0;
            try
              if TFile.Exists(WinApiPath(Path)) and not TDirectory.Exists(WinApiPath(Path)) then
              begin
                E.Size := TFile.GetSize(WinApiPath(Path));
                E.ModificationTime := TFile.GetLastWriteTime(WinApiPath(Path));
                E.CreationTime := TFile.GetCreationTime(WinApiPath(Path));
                E.AccessTime := TFile.GetLastAccessTime(WinApiPath(Path));
              end
              else if TDirectory.Exists(WinApiPath(Path)) then
              begin
                E.Size := -1;
                E.IsDirectory := True;
                E.ModificationTime := TDirectory.GetLastWriteTime(WinApiPath(Path));
                E.CreationTime := TDirectory.GetCreationTime(WinApiPath(Path));
                E.AccessTime := TDirectory.GetLastAccessTime(WinApiPath(Path));
              end;
                Attr := GetFileAttributes(PChar(WinApiPath(Path)));
                if Attr <> INVALID_FILE_ATTRIBUTES then
                begin
                  E.IsHidden := ((Attr and FILE_ATTRIBUTE_HIDDEN) <> 0) or
                    ((Attr and FILE_ATTRIBUTE_SYSTEM) <> 0);
                  E.IsReadOnly := (Attr and FILE_ATTRIBUTE_READONLY) <> 0;
                  E.IsSystem := (Attr and FILE_ATTRIBUTE_SYSTEM) <> 0;
                  E.IsArchive := (Attr and FILE_ATTRIBUTE_ARCHIVE) <> 0;
                  E.IsCompressed := (Attr and FILE_ATTRIBUTE_COMPRESSED) <> 0;
                  E.IsEncrypted := (Attr and FILE_ATTRIBUTE_ENCRYPTED) <> 0;
                  E.IsTemporary := (Attr and FILE_ATTRIBUTE_TEMPORARY) <> 0;
                  E.IsOffline := (Attr and FILE_ATTRIBUTE_OFFLINE) <> 0;
                  E.IsLink := (Attr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0;
                end;
            except
              // keep defaults
            end;
            Items[I] := E;
          end;
        end;
      except
        on Ex: Exception do
          Err := TVfsError.Make(vecIOError, Ex.Message, URI);
      end;
      QueueList(OnDone, Items, Err);
    end).Start;
end;

procedure TFindVirtualFileSystem.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
begin
  QueueBool(AOnDone, False,
    TVfsError.Make(vecNotSupported, 'Cannot delete find:// session', AURI));
end;

procedure TFindVirtualFileSystem.CreateDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  QueueBool(AOnDone, False,
    TVfsError.Make(vecNotSupported, 'Cannot mkdir in find://', AURI));
end;

procedure TFindVirtualFileSystem.CopyAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
begin
  QueueBool(AOnDone, False,
    TVfsError.Make(vecNotSupported, 'Copy find:// session unsupported', AFromURI));
end;

procedure TFindVirtualFileSystem.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
begin
  QueueBool(AOnDone, False,
    TVfsError.Make(vecNotSupported, 'Cannot move find:// session', AFromURI));
end;

procedure TFindVirtualFileSystem.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
begin
  QueueText(AOnDone, '', tfeUtf8,
    TVfsError.Make(vecNotSupported, 'Not a file', AURI));
end;

procedure TFindVirtualFileSystem.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
begin
  QueueBytes(AOnDone, nil,
    TVfsError.Make(vecNotSupported, 'Not a file', AURI));
end;

procedure TFindVirtualFileSystem.WriteTextAsync(const AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  QueueBool(AOnDone, False,
    TVfsError.Make(vecNotSupported, 'Cannot write find://', AURI));
end;

procedure TFindVirtualFileSystem.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
var
  URI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsExistsCallback;
begin
  URI := AURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Data: TFindSessionData;
      Err: TVfsError;
      Exists: Boolean;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      Exists := False;
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', URI)
        else
          Exists := TryGetFindSessionFromUri(URI, Data);
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, URI);
      end;
      QueueExists(OnDone, Exists, True, Err);
    end).Start;
end;

procedure TFindVirtualFileSystem.GetFreeSpaceAsync(const ARootURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsFreeSpaceCallback);
var
  RootURI: string;
  OnDone: TVfsFreeSpaceCallback;
  Data: TFindSessionData;
  Path: string;
begin
  RootURI := ARootURI;
  OnDone := AOnDone;
  if TryGetFindSessionFromUri(RootURI, Data) then
    Path := Data.RootPath
  else
    Path := '';
  TThread.CreateAnonymousThread(
    procedure
    var
      Err: TVfsError;
      FreeAvail, TotalNum: UInt64;
      FreeB, TotalB, DoneFree, DoneTotal: Int64;
      DoneErr: TVfsError;
      DriveLocal: string;
    begin
      Err := TVfsError.Ok;
      Err.URI := RootURI;
      FreeB := -1;
      TotalB := -1;
      try
        DriveLocal := ExtractFileDrive(Path);
        if DriveLocal = '' then
          Err := TVfsError.Make(vecInvalidURI, 'No drive root', RootURI)
        else
        begin
          DriveLocal := IncludeTrailingPathDelimiter(DriveLocal);
          if GetDiskFreeSpaceEx(PChar(DriveLocal), FreeAvail, TotalNum, nil) then
          begin
            FreeB := Int64(FreeAvail);
            TotalB := Int64(TotalNum);
          end
          else
            Err := TVfsError.Make(vecIOError, 'GetDiskFreeSpaceEx failed', RootURI);
        end;
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, RootURI);
      end;
      DoneFree := FreeB;
      DoneTotal := TotalB;
      DoneErr := Err;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(DoneFree, DoneTotal, DoneErr);
        end);
    end).Start;
end;

end.
