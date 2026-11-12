unit uRecycleBinVfs;

{ Virtual file system backend for recycle:// (POSIX build): browse, restore and
  purge the items of the user's trash (freedesktop.org Trash specification).
  Only ListDirectoryAsync, ExistsAsync and DeleteAsync (a permanent purge) do
  work; everything else is vecNotSupported. An item is identified by its real
  path under Trash/files; its original location comes from the matching
  Trash/info/<name>.trashinfo. The Windows build lives in Platform\Windows;
  each project puts exactly one of the two directories on its unit search
  path. }

interface

uses
  uVfsTypes, uTextEncoding;

type
  TRecycleBinVirtualFileSystem = class(TInterfacedObject, IVirtualFileSystem)
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

const
  cRecycleBinRootUri = 'recycle:///';

/// <summary>Restores ARecycleUri's item to its original location. Synchronous;
/// run it off the UI thread.</summary>
function RestoreRecycleBinItem(const ARecycleUri: string; out AError: TVfsError): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, Posix.Base, Posix.Errno,
  uFileRecycleBin;

function c_rename(AOld, ANew: MarshaledAString): Integer; cdecl;
  external libc name 'rename';

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
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(Cb) then
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
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(Cb) then
        Cb(Ok, Err);
    end);
end;

procedure QueueExists(const AOnDone: TVfsExistsCallback; AExists, AIsDir: Boolean;
  const AError: TVfsError);
var
  Ex, Dir: Boolean;
  Err: TVfsError;
  Cb: TVfsExistsCallback;
begin
  Ex := AExists;
  Dir := AIsDir;
  Err := AError;
  Cb := AOnDone;
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(Cb) then
        Cb(Ex, Dir, Err);
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
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(Cb) then
        Cb(Text, Enc, Err);
    end);
end;

function PercentDecode(const AText: string): string;
var
  Bytes: TBytes;
  I, N: Integer;
  B: Byte;
begin
  SetLength(Bytes, 0);
  I := 1;
  while I <= Length(AText) do
  begin
    if (AText[I] = '%') and (I + 2 <= Length(AText)) and
       TryStrToInt('$' + Copy(AText, I + 1, 2), N) then
    begin
      B := Byte(N);
      Inc(I, 3);
    end
    else
    begin
      if Ord(AText[I]) < 128 then
      begin
        B := Byte(Ord(AText[I]));
        Inc(I);
      end
      else
      begin
        Bytes := Bytes + TEncoding.UTF8.GetBytes(AText[I]);
        Inc(I);
        Continue;
      end;
    end;
    SetLength(Bytes, Length(Bytes) + 1);
    Bytes[High(Bytes)] := B;
  end;
  Result := TEncoding.UTF8.GetString(Bytes);
end;

function FilesDir: string;
begin
  Result := TPath.Combine(TrashDirectory, 'files');
end;

function InfoPathFor(const AItemName: string): string;
begin
  Result := TPath.Combine(TPath.Combine(TrashDirectory, 'info'),
    AItemName + '.trashinfo');
end;

// Original absolute path of a trashed item, '' when its info file is missing.
function OriginalPath(const AItemName: string): string;
var
  Lines: TStringList;
  Line, Info: string;
begin
  Result := '';
  Info := InfoPathFor(AItemName);
  if not TFile.Exists(Info) then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(Info, TEncoding.UTF8);
    for Line in Lines do
      if Line.StartsWith('Path=') then
      begin
        Result := PercentDecode(Trim(Copy(Line, 6, MaxInt)));
        Exit;
      end;
  finally
    Lines.Free;
  end;
end;

// The item name under Trash/files that a recycle:// URI addresses.
function ItemNameOf(const AUri: string): string;
var
  Path: string;
begin
  Path := RecycleUriToPath(AUri);
  if (Path = '') or not SameText(ExtractFilePath(Path), IncludeTrailingPathDelimiter(FilesDir)) then
    Result := ''
  else
    Result := ExtractFileName(Path);
end;

function RestoreRecycleBinItem(const ARecycleUri: string; out AError: TVfsError): Boolean;
var
  Item, Orig, Src: string;
  A, B: UTF8String;
begin
  AError := TVfsError.Ok;
  Result := False;
  Item := ItemNameOf(ARecycleUri);
  Orig := '';
  if Item <> '' then
    Orig := OriginalPath(Item);
  if Orig = '' then
  begin
    AError := TVfsError.Make(vecNotFound, 'Original location is unknown', ARecycleUri);
    Exit;
  end;
  if TFile.Exists(Orig) or TDirectory.Exists(Orig) then
  begin
    AError := TVfsError.Make(vecIOError, 'The original location is taken', ARecycleUri);
    Exit;
  end;
  try
    ForceDirectories(ExtractFilePath(Orig));
  except
    on E: Exception do
    begin
      AError := TVfsError.Make(vecIOError, E.Message, ARecycleUri);
      Exit;
    end;
  end;
  Src := TPath.Combine(FilesDir, Item);
  A := UTF8String(Src);
  B := UTF8String(Orig);
  if c_rename(MarshaledAString(A), MarshaledAString(B)) <> 0 then
  begin
    AError := TVfsError.Make(vecIOError, SysErrorMessage(GetLastError), ARecycleUri);
    Exit;
  end;
  try
    TFile.Delete(InfoPathFor(Item));
  except
  end;
  Result := True;
end;

function PurgeRecycleBinItem(const AUri: string; out AError: TVfsError): Boolean;
var
  Item, Src: string;
begin
  AError := TVfsError.Ok;
  Item := ItemNameOf(AUri);
  if Item = '' then
  begin
    AError := TVfsError.Make(vecNotFound, 'Not a Recycle Bin item', AUri);
    Exit(False);
  end;
  Src := TPath.Combine(FilesDir, Item);
  try
    if TDirectory.Exists(Src) then
      TDirectory.Delete(Src, True)
    else if TFile.Exists(Src) then
      TFile.Delete(Src);
    if TFile.Exists(InfoPathFor(Item)) then
      TFile.Delete(InfoPathFor(Item));
    Result := True;
  except
    on E: Exception do
    begin
      AError := TVfsError.Make(vecIOError, E.Message, AUri);
      Result := False;
    end;
  end;
end;

procedure TRecycleBinVirtualFileSystem.ListDirectoryAsync(const AURI: string;
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
      Dir, Path, Orig: string;
      E: TVfsEntry;
      N: Integer;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      SetLength(Items, 0);
      try
        Dir := FilesDir;
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', URI)
        else if TDirectory.Exists(Dir) then
          for Path in TDirectory.GetFileSystemEntries(Dir) do
          begin
            if JobCancelRequested(Cancel) then
              Break;
            FillChar(E, SizeOf(E), 0);
            Orig := OriginalPath(ExtractFileName(Path));
            if Orig <> '' then
              E.Name := ExtractFileName(Orig)
            else
              E.Name := ExtractFileName(Path);
            E.IsDirectory := TDirectory.Exists(Path);
            // The row's URI comes from TargetURI; it stays a recycle:// URI so
            // Delete keeps routing through this provider's permanent purge.
            E.TargetURI := RecyclePathToUri(Path);
            try
              if E.IsDirectory then
                E.Size := -1
              else
                E.Size := TFile.GetSize(Path);
              E.ModificationTime := TFile.GetLastWriteTime(Path);
            except
            end;
            N := Length(Items);
            SetLength(Items, N + 1);
            Items[N] := E;
          end;
      except
        on Ex: Exception do
          Err := TVfsError.Make(vecIOError, Ex.Message, URI);
      end;
      QueueList(OnDone, Items, Err);
    end).Start;
end;

procedure TRecycleBinVirtualFileSystem.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
var
  URI: string;
  OnDone: TVfsBoolCallback;
begin
  URI := AURI;
  OnDone := AOnDone;
  // Trash items are already "deleted": Delete here is always a permanent purge.
  TThread.CreateAnonymousThread(
    procedure
    var
      Err: TVfsError;
      Ok: Boolean;
    begin
      Ok := PurgeRecycleBinItem(URI, Err);
      QueueBool(OnDone, Ok, Err);
    end).Start;
end;

procedure TRecycleBinVirtualFileSystem.CreateDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  QueueBool(AOnDone, False, TVfsError.Make(vecNotSupported, 'Recycle Bin is read-only', AURI));
end;

procedure TRecycleBinVirtualFileSystem.CopyAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite, APreserveTimestamps: Boolean);
begin
  QueueBool(AOnDone, False, TVfsError.Make(vecNotSupported,
    'Copy from Recycle Bin is not supported - use Restore', AFromURI));
end;

procedure TRecycleBinVirtualFileSystem.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite, APreserveTimestamps: Boolean);
begin
  QueueBool(AOnDone, False, TVfsError.Make(vecNotSupported,
    'Use Restore to move an item out of the Recycle Bin', AFromURI));
end;

procedure TRecycleBinVirtualFileSystem.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
begin
  QueueText(AOnDone, '', tfeUtf8, TVfsError.Make(vecNotSupported, 'Not a text file', AURI));
end;

procedure TRecycleBinVirtualFileSystem.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
begin
  QueueBytes(AOnDone, nil, TVfsError.Make(vecNotSupported, 'Not a binary file', AURI));
end;

procedure TRecycleBinVirtualFileSystem.WriteTextAsync(const AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  QueueBool(AOnDone, False, TVfsError.Make(vecNotSupported, 'Recycle Bin is read-only', AURI));
end;

procedure TRecycleBinVirtualFileSystem.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
var
  Path: string;
begin
  if SameText(AURI, cRecycleBinRootUri) or SameText(AURI, 'recycle://') then
    QueueExists(AOnDone, True, True, TVfsError.Ok)
  else
  begin
    Path := RecycleUriToPath(AURI);
    QueueExists(AOnDone, TDirectory.Exists(Path) or TFile.Exists(Path),
      TDirectory.Exists(Path), TVfsError.Ok);
  end;
end;

procedure TRecycleBinVirtualFileSystem.GetFreeSpaceAsync(const ARootURI: string;
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
