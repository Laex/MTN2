unit uRecycleBinVfs;

{ Virtual file system backend for recycle:// — browse and restore items in
  the Windows Recycle Bin. Mostly read-only, shaped like uSysFoldersVfs.pas/
  uFindVfs.pas: only ListDirectoryAsync/ExistsAsync are real; DeleteAsync
  does a real permanent purge; everything else is vecNotSupported.

  CROSS-PLATFORM (Этап 23): IShellFolder2/CSIDL_BITBUCKET are Windows-only;
  "recycle bin" isn't the same concept elsewhere (freedesktop Trash spec on
  Linux, a per-volume .Trashes on macOS) -- a port needs its own VFS backend
  behind the same recycle:// scheme, not a portable rewrite of this one.

  Validated against the live Shell APIs by src/tests/vfs/TestRecycleBin.dpr
  before this was written (see that file's header for the exact findings).
  Key facts that shape the design below:
  - IShellFolder2 bound to CSIDL_BITBUCKET enumerates real Recycle Bin
    entries. Column index 1 is "Original Location" on every locale/Windows
    version — the column ORDER is fixed by the shell even though the header
    TEXT is localized (confirmed against a live Russian-locale install).
  - GetDisplayNameOf(pidl, SHGDN_NORMAL) is NOT a plain leaf name for
    Recycle Bin items — it returns something closer to the full original
    path. GetDetailsOf(pidl, 0, ...) (the "Name" column) is closer but has
    its extension stripped whenever Explorer's "hide extensions for known
    file types" preference applies. GetDisplayNameOf(pidl, SHGDN_FORPARSING)
    reliably returns the item's real underlying filesystem path
    (`<drive>:\$Recycle.Bin\<SID>\$R<random><.ext>`) WITH the true
    extension — used both as this unit's stable URI identity (no PIDL/
    session caching needed between calls — every operation re-enumerates
    and matches by this path) and as the source of the true extension for
    reconstructing the original display name (column-0 name + this path's
    extension, only appended if column-0 doesn't already end with it).
  - Restoring is IFileOperation.MoveItem(item, originalFolderItem, itemName,
    nil) — there is no direct Win32 "Restore" call. }

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

/// <summary>Restore ARecycleUri's item back to its original location.
/// Synchronous (Shell COM calls) — run off the UI thread. Re-enumerates and
/// matches by real path each time; no session/PIDL state is kept between
/// calls.</summary>
function RestoreRecycleBinItem(const ARecycleUri: string; out AError: TVfsError): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  Winapi.Windows, Winapi.ActiveX, Winapi.ShlObj, Winapi.ShellAPI;

{ Thread-marshalling boilerplate — duplicated from uSysFoldersVfs.pas/
  uFindVfs.pas per established project convention (not factored out). }

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

{ Shell helpers }

function StrRetToStr(var AStrRet: TStrRet; APidl: PItemIDList): string;
var
  Buf: PWideChar;
begin
  Result := '';
  case AStrRet.uType of
    STRRET_WSTR:
      begin
        Buf := AStrRet.pOleStr;
        if Buf <> nil then
        begin
          Result := Buf;
          CoTaskMemFree(Buf);
        end;
      end;
    STRRET_OFFSET:
      if APidl <> nil then
        Result := PWideChar(@PByteArray(APidl)[AStrRet.uOffset]);
    STRRET_CSTR:
      Result := string(AStrRet.cStr);
  end;
end;

function OpenRecycleBinFolder(out AFolder: IShellFolder2; out AMalloc: IMalloc): Boolean;
var
  Desktop: IShellFolder;
  Pidl: PItemIDList;
begin
  Result := False;
  AFolder := nil;
  AMalloc := nil;
  if Failed(SHGetDesktopFolder(Desktop)) then
    Exit;
  if Failed(SHGetMalloc(AMalloc)) then
    Exit;
  if Failed(SHGetSpecialFolderLocation(0, CSIDL_BITBUCKET, Pidl)) then
    Exit;
  try
    Result := Succeeded(Desktop.BindToObject(Pidl, nil, IShellFolder2, AFolder)) and
      Assigned(AFolder);
  finally
    if Assigned(AMalloc) and (Pidl <> nil) then
      AMalloc.Free(Pidl);
  end;
end;

/// <summary>Reconstructs the item's true display name: the "Name" column
/// (extension possibly stripped by the "hide known extensions" preference)
/// plus the real extension from its SHGDN_FORPARSING path, appended only if
/// not already present.</summary>
function BuildItemName(const AColumn0Name, AParsingPath: string): string;
var
  Ext: string;
begin
  Ext := ExtractFileExt(AParsingPath);
  if (Ext <> '') and not AColumn0Name.EndsWith(Ext, True) then
    Result := AColumn0Name + Ext
  else
    Result := AColumn0Name;
end;

/// <summary>Re-enumerates the Recycle Bin looking for the item whose real
/// (SHGDN_FORPARSING) path matches ATargetPath. On success returns the
/// found PIDL (caller must AMalloc.Free it) plus its original location and
/// reconstructed display name.</summary>
function FindRecycleItemByPath(const ATargetPath: string;
  out AFolder: IShellFolder2; out AMalloc: IMalloc; out AFoundPidl: PItemIDList;
  out AOrigLocation, AItemName: string): Boolean;
var
  EnumList: IEnumIDList;
  ChildPidl: PItemIDList;
  Fetched: LongWord;
  Details: TShellDetails;
  ParsingPath, Col0: string;
begin
  Result := False;
  AFoundPidl := nil;
  AOrigLocation := '';
  AItemName := '';
  if not OpenRecycleBinFolder(AFolder, AMalloc) then
    Exit;
  if Failed(AFolder.EnumObjects(0,
     SHCONTF_FOLDERS or SHCONTF_NONFOLDERS or SHCONTF_INCLUDEHIDDEN, EnumList)) or
     not Assigned(EnumList) then
    Exit;
  while EnumList.Next(1, ChildPidl, Fetched) = S_OK do
  begin
    FillChar(Details, SizeOf(Details), 0);
    ParsingPath := '';
    if Succeeded(AFolder.GetDisplayNameOf(ChildPidl, SHGDN_FORPARSING, Details.str)) then
      ParsingPath := StrRetToStr(Details.str, ChildPidl);
    if SameText(ParsingPath, ATargetPath) then
    begin
      AFoundPidl := ChildPidl;
      FillChar(Details, SizeOf(Details), 0);
      if Succeeded(AFolder.GetDetailsOf(ChildPidl, 1, Details)) then
        AOrigLocation := StrRetToStr(Details.str, ChildPidl);
      FillChar(Details, SizeOf(Details), 0);
      Col0 := '';
      if Succeeded(AFolder.GetDetailsOf(ChildPidl, 0, Details)) then
        Col0 := StrRetToStr(Details.str, ChildPidl);
      AItemName := BuildItemName(Col0, ParsingPath);
      Result := True;
      Exit; // keep this PIDL alive for the caller — do not free it below
    end;
    if Assigned(AMalloc) then
      AMalloc.Free(ChildPidl);
  end;
end;

function RestoreRecycleBinItem(const ARecycleUri: string; out AError: TVfsError): Boolean;
var
  TargetPath, OrigLocation, ItemName: string;
  Folder: IShellFolder2;
  Malloc: IMalloc;
  FoundPidl: PItemIDList;
  SrcItem, DestFolderItem: IShellItem;
  Op: IFileOperation;
  HR: HRESULT;
  ComInited: Boolean;
begin
  Result := False;
  AError := TVfsError.Ok;
  TargetPath := RecycleUriToPath(ARecycleUri);
  if TargetPath = '' then
  begin
    AError := TVfsError.Make(vecInvalidURI, 'Invalid recycle:// URI', ARecycleUri);
    Exit;
  end;

  HR := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  ComInited := Succeeded(HR) or (HR = RPC_E_CHANGED_MODE);
  try
    try
      if not FindRecycleItemByPath(TargetPath, Folder, Malloc, FoundPidl,
         OrigLocation, ItemName) then
      begin
        AError := TVfsError.Make(vecNotFound, 'Item no longer in Recycle Bin', ARecycleUri);
        Exit;
      end;
      try
        if OrigLocation = '' then
        begin
          AError := TVfsError.Make(vecIOError, 'Cannot determine original location', ARecycleUri);
          Exit;
        end;
        HR := SHCreateShellItem(nil, IShellFolder(Folder), FoundPidl, SrcItem);
        if Failed(HR) then
        begin
          AError := TVfsError.Make(vecIOError, 'Cannot resolve Recycle Bin item', ARecycleUri);
          Exit;
        end;
        if not TDirectory.Exists(OrigLocation) then
          TDirectory.CreateDirectory(OrigLocation);
        HR := SHCreateItemFromParsingName(PWideChar(OrigLocation), nil, IShellItem, DestFolderItem);
        if Failed(HR) then
        begin
          AError := TVfsError.Make(vecIOError,
            'Original location no longer available: ' + OrigLocation, ARecycleUri);
          Exit;
        end;
        HR := CoCreateInstance(CLSID_FileOperation, nil, CLSCTX_INPROC_SERVER,
          IID_IFileOperation, Op);
        if Failed(HR) then
        begin
          AError := TVfsError.Make(vecIOError, 'Cannot start restore operation', ARecycleUri);
          Exit;
        end;
        Op.SetOperationFlags(FOF_ALLOWUNDO or FOF_NOCONFIRMATION or FOF_SILENT or
          FOF_NOERRORUI or FOFX_SHOWELEVATIONPROMPT);
        HR := Op.MoveItem(SrcItem, DestFolderItem, PWideChar(ItemName), nil);
        if Succeeded(HR) then
          HR := Op.PerformOperations;
        if Failed(HR) then
        begin
          AError := TVfsError.Make(vecIOError,
            Format('Restore failed (0x%.8x)', [Cardinal(HR)]), ARecycleUri);
          Exit;
        end;
        Result := True;
      finally
        if Assigned(Malloc) and (FoundPidl <> nil) then
          Malloc.Free(FoundPidl);
      end;
    except
      // A background-thread exception here would otherwise kill the worker
      // silently (see uDualPanelWindow.RestoreCursorItemFromRecycleBin: it
      // only reports back via TThread.Queue after this function returns) —
      // never let one escape unreported.
      on E: Exception do
      begin
        Result := False;
        AError := TVfsError.Make(vecIOError, 'Restore failed: ' + E.Message, ARecycleUri);
      end;
    end;
  finally
    if ComInited then
      CoUninitialize;
  end;
end;

function PurgeRecycleBinItem(const ARecycleUri: string; out AError: TVfsError): Boolean;
var
  TargetPath, OrigLocation, ItemName: string;
  Folder: IShellFolder2;
  Malloc: IMalloc;
  FoundPidl: PItemIDList;
  Item: IShellItem;
  Op: IFileOperation;
  HR: HRESULT;
  ComInited: Boolean;
begin
  Result := False;
  AError := TVfsError.Ok;
  TargetPath := RecycleUriToPath(ARecycleUri);
  if TargetPath = '' then
  begin
    AError := TVfsError.Make(vecInvalidURI, 'Invalid recycle:// URI', ARecycleUri);
    Exit;
  end;
  HR := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  ComInited := Succeeded(HR) or (HR = RPC_E_CHANGED_MODE);
  try
    try
      if not FindRecycleItemByPath(TargetPath, Folder, Malloc, FoundPidl,
         OrigLocation, ItemName) then
      begin
        AError := TVfsError.Make(vecNotFound, 'Item no longer in Recycle Bin', ARecycleUri);
        Exit;
      end;
      try
        HR := SHCreateShellItem(nil, IShellFolder(Folder), FoundPidl, Item);
        if Failed(HR) then
        begin
          AError := TVfsError.Make(vecIOError, 'Cannot resolve Recycle Bin item', ARecycleUri);
          Exit;
        end;
        HR := CoCreateInstance(CLSID_FileOperation, nil, CLSCTX_INPROC_SERVER,
          IID_IFileOperation, Op);
        if Failed(HR) then
        begin
          AError := TVfsError.Make(vecIOError, 'Cannot start delete operation', ARecycleUri);
          Exit;
        end;
        // No FOF_ALLOWUNDO — this permanently purges the item.
        Op.SetOperationFlags(FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI);
        HR := Op.DeleteItem(Item, nil);
        if Succeeded(HR) then
          HR := Op.PerformOperations;
        if Failed(HR) then
        begin
          AError := TVfsError.Make(vecIOError,
            Format('Purge failed (0x%.8x)', [Cardinal(HR)]), ARecycleUri);
          Exit;
        end;
        Result := True;
      finally
        if Assigned(Malloc) and (FoundPidl <> nil) then
          Malloc.Free(FoundPidl);
      end;
    except
      // Same reasoning as RestoreRecycleBinItem — never let an exception
      // escape and silently kill the calling background thread.
      on E: Exception do
      begin
        Result := False;
        AError := TVfsError.Make(vecIOError, 'Purge failed: ' + E.Message, ARecycleUri);
      end;
    end;
  finally
    if ComInited then
      CoUninitialize;
  end;
end;

{ TRecycleBinVirtualFileSystem }

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
      ComInited: Boolean;
      HR: HRESULT;
      Folder: IShellFolder2;
      Malloc: IMalloc;
      EnumList: IEnumIDList;
      ChildPidl: PItemIDList;
      Fetched: LongWord;
      Details: TShellDetails;
      ParsingPath, Col0, OrigLocation: string;
      E: TVfsEntry;
      N: Integer;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      SetLength(Items, 0);
      HR := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
      ComInited := Succeeded(HR) or (HR = RPC_E_CHANGED_MODE);
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', URI)
        else if not OpenRecycleBinFolder(Folder, Malloc) then
          Err := TVfsError.Make(vecIOError, 'Recycle Bin unavailable', URI)
        else if Failed(Folder.EnumObjects(0,
           SHCONTF_FOLDERS or SHCONTF_NONFOLDERS or SHCONTF_INCLUDEHIDDEN, EnumList)) or
           not Assigned(EnumList) then
          Err := TVfsError.Make(vecIOError, 'Cannot enumerate Recycle Bin', URI)
        else
        begin
          while EnumList.Next(1, ChildPidl, Fetched) = S_OK do
          begin
            if JobCancelRequested(Cancel) then
            begin
              Malloc.Free(ChildPidl);
              Break;
            end;
            FillChar(Details, SizeOf(Details), 0);
            ParsingPath := '';
            if Succeeded(Folder.GetDisplayNameOf(ChildPidl, SHGDN_FORPARSING, Details.str)) then
              ParsingPath := StrRetToStr(Details.str, ChildPidl);
            FillChar(Details, SizeOf(Details), 0);
            Col0 := '';
            if Succeeded(Folder.GetDetailsOf(ChildPidl, 0, Details)) then
              Col0 := StrRetToStr(Details.str, ChildPidl);
            FillChar(Details, SizeOf(Details), 0);
            OrigLocation := '';
            if Succeeded(Folder.GetDetailsOf(ChildPidl, 1, Details)) then
              OrigLocation := StrRetToStr(Details.str, ChildPidl);
            Malloc.Free(ChildPidl);

            if ParsingPath = '' then
              Continue;
            FillChar(E, SizeOf(E), 0);
            E.Name := BuildItemName(Col0, ParsingPath);
            E.IsDirectory := TDirectory.Exists(ParsingPath);
            // TVfsEntry has no URI field of its own — RowsFromVfsItems
            // (uDualPanelTypes.pas) uses TargetURI as the row's actual URI
            // whenever set (falling back to JoinFileUri(dir, Name) — always
            // a file:// URI — otherwise, which would be wrong here). Every
            // entry MUST set TargetURI, and it must stay a recycle:// URI
            // (not file://) so Delete/etc. keep routing through this
            // provider's DeleteAsync (permanent purge) instead of silently
            // falling through to the plain file backend.
            E.TargetURI := RecyclePathToUri(ParsingPath);
            try
              if not E.IsDirectory and TFile.Exists(ParsingPath) then
              begin
                E.Size := TFile.GetSize(ParsingPath);
                E.ModificationTime := TFile.GetLastWriteTime(ParsingPath);
              end;
            except
            end;
            N := Length(Items);
            SetLength(Items, N + 1);
            Items[N] := E;
          end;
        end;
      except
        on Ex: Exception do
          Err := TVfsError.Make(vecIOError, Ex.Message, URI);
      end;
      if ComInited then
        CoUninitialize;
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
  // Recycle Bin items are already "deleted" — Delete here always means a
  // real permanent purge (AMode is ignored: there is nowhere further to
  // recycle to).
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
    'Copy from Recycle Bin is not supported — use Restore', AFromURI));
end;

procedure TRecycleBinVirtualFileSystem.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite, APreserveTimestamps: Boolean);
begin
  // Restore is exposed as a dedicated RestoreRecycleBinItem function, called
  // directly by the UI rather than routed through IVirtualFileSystem.MoveAsync
  // — TVfsRegistryRoot.MoveAsync special-cases only find:// and archive
  // chains today, so bypassing it here is simpler than extending it.
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
begin
  if SameText(AURI, cRecycleBinRootUri) or SameText(AURI, 'recycle://') then
    QueueExists(AOnDone, True, True, TVfsError.Ok)
  else
    QueueExists(AOnDone, TDirectory.Exists(RecycleUriToPath(AURI)) or
      TFile.Exists(RecycleUriToPath(AURI)), TDirectory.Exists(RecycleUriToPath(AURI)),
      TVfsError.Ok);
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
