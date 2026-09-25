unit uFileRecycleBin;

{ Deleting a local path into the Windows Recycle Bin, via the modern
  IFileOperation Shell API with a legacy SHFileOperation fallback. Isolated
  from uFileVfs.pas because this is the only code in the local VFS provider
  that needs COM / Shell headers (Winapi.ShellAPI/ShlObj/ActiveX) — permanent
  delete (uFileVfs.DeleteTree) is plain filesystem I/O and doesn't. }

interface

uses
  uVfsTypes;

procedure DeleteToRecycleBin(const APath: string; var AError: TVfsError;
  AOnProgress: TVfsProgressCallback = nil);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  Winapi.Windows, Winapi.ShellAPI, Winapi.ShlObj, Winapi.ActiveX;

type
  /// <summary>Bridges IFileOperation's own progress notifications (the
  /// Recycle Bin delete runs with FOF_SILENT, so nothing else reports
  /// progress) to AOnProgress. Every method but UpdateProgress/PostDeleteItem
  /// is a required no-op — returning anything other than S_OK from a Pre*
  /// hook would tell the shell to abandon that item.</summary>
  TDeleteProgressSink = class(TInterfacedObject, IFileOperationProgressSink)
  private
    FOnProgress: TVfsProgressCallback;
    FLastPath: string;
  public
    constructor Create(AOnProgress: TVfsProgressCallback);
    function StartOperations: HResult; stdcall;
    function FinishOperations(hrResult: HResult): HResult; stdcall;
    function PreRenameItem(dwFlags: DWORD; const psiItem: IShellItem;
      pszNewName: LPCWSTR): HResult; stdcall;
    function PostRenameItem(dwFlags: DWORD; const psiItem: IShellItem;
      pszNewName: LPCWSTR; hrRename: HResult;
      const psiNewlyCreated: IShellItem): HResult; stdcall;
    function PreMoveItem(dwFlags: DWORD; const psiItem: IShellItem;
      const psiDestinationFolder: IShellItem; pszNewName: LPCWSTR): HResult; stdcall;
    function PostMoveItem(dwFlags: DWORD; const psiItem: IShellItem;
      const psiDestinationFolder: IShellItem; pszNewName: LPCWSTR;
      hrMove: HResult; const psiNewlyCreated: IShellItem): HResult; stdcall;
    function PreCopyItem(dwFlags: DWORD; const psiItem: IShellItem;
      const psiDestinationFolder: IShellItem; pszNewName: LPCWSTR): HResult; stdcall;
    function PostCopyItem(dwFlags: DWORD; const psiItem: IShellItem;
      const psiDestinationFolder: IShellItem; pszNewName: LPCWSTR;
      hrCopy: HResult; const psiNewlyCreated: IShellItem): HResult; stdcall;
    function PreDeleteItem(dwFlags: DWORD; const psiItem: IShellItem): HResult; stdcall;
    function PostDeleteItem(dwFlags: DWORD; const psiItem: IShellItem;
      hrDelete: HResult; const psiNewlyCreated: IShellItem): HResult; stdcall;
    function PreNewItem(dwFlags: DWORD; const psiDestinationFolder: IShellItem;
      pszNewName: LPCWSTR): HResult; stdcall;
    function PostNewItem(dwFlags: DWORD; const psiDestinationFolder: IShellItem;
      pszNewName: LPCWSTR; pszTemplateName: LPCWSTR; dwFileAttributes: DWORD;
      hrNew: HResult; const psiNewItem: IShellItem): HResult; stdcall;
    function UpdateProgress(iWorkTotal: UINT; iWorkSoFar: UINT): HResult; stdcall;
    function ResetTimer: HResult; stdcall;
    function PauseTimer: HResult; stdcall;
    function ResumeTimer: HResult; stdcall;
  end;

constructor TDeleteProgressSink.Create(AOnProgress: TVfsProgressCallback);
begin
  inherited Create;
  FOnProgress := AOnProgress;
end;

function TDeleteProgressSink.StartOperations: HResult;
begin
  Result := S_OK;
end;

function TDeleteProgressSink.FinishOperations(hrResult: HResult): HResult;
begin
  Result := S_OK;
end;

function TDeleteProgressSink.PreRenameItem(dwFlags: DWORD; const psiItem: IShellItem;
  pszNewName: LPCWSTR): HResult;
begin
  Result := S_OK;
end;

function TDeleteProgressSink.PostRenameItem(dwFlags: DWORD; const psiItem: IShellItem;
  pszNewName: LPCWSTR; hrRename: HResult;
  const psiNewlyCreated: IShellItem): HResult;
begin
  Result := S_OK;
end;

function TDeleteProgressSink.PreMoveItem(dwFlags: DWORD; const psiItem: IShellItem;
  const psiDestinationFolder: IShellItem; pszNewName: LPCWSTR): HResult;
begin
  Result := S_OK;
end;

function TDeleteProgressSink.PostMoveItem(dwFlags: DWORD; const psiItem: IShellItem;
  const psiDestinationFolder: IShellItem; pszNewName: LPCWSTR;
  hrMove: HResult; const psiNewlyCreated: IShellItem): HResult;
begin
  Result := S_OK;
end;

function TDeleteProgressSink.PreCopyItem(dwFlags: DWORD; const psiItem: IShellItem;
  const psiDestinationFolder: IShellItem; pszNewName: LPCWSTR): HResult;
begin
  Result := S_OK;
end;

function TDeleteProgressSink.PostCopyItem(dwFlags: DWORD; const psiItem: IShellItem;
  const psiDestinationFolder: IShellItem; pszNewName: LPCWSTR;
  hrCopy: HResult; const psiNewlyCreated: IShellItem): HResult;
begin
  Result := S_OK;
end;

function TDeleteProgressSink.PreDeleteItem(dwFlags: DWORD;
  const psiItem: IShellItem): HResult;
begin
  Result := S_OK;
end;

function TDeleteProgressSink.PostDeleteItem(dwFlags: DWORD; const psiItem: IShellItem;
  hrDelete: HResult; const psiNewlyCreated: IShellItem): HResult;
var
  PathPtr: LPWSTR;
begin
  Result := S_OK;
  if not Assigned(psiItem) then
    Exit;
  // SIGDN_FILESYSPATH, not SIGDN_NORMALDISPLAY: the job popup shows this as
  // a real path (ellipsized like every other path it displays), not a bare
  // display name.
  if Succeeded(psiItem.GetDisplayName(SIGDN_FILESYSPATH, PathPtr)) then
  begin
    FLastPath := PathPtr;
    CoTaskMemFree(PathPtr);
  end;
end;

function TDeleteProgressSink.PreNewItem(dwFlags: DWORD;
  const psiDestinationFolder: IShellItem; pszNewName: LPCWSTR): HResult;
begin
  Result := S_OK;
end;

function TDeleteProgressSink.PostNewItem(dwFlags: DWORD;
  const psiDestinationFolder: IShellItem; pszNewName: LPCWSTR;
  pszTemplateName: LPCWSTR; dwFileAttributes: DWORD; hrNew: HResult;
  const psiNewItem: IShellItem): HResult;
begin
  Result := S_OK;
end;

function TDeleteProgressSink.UpdateProgress(iWorkTotal: UINT; iWorkSoFar: UINT): HResult;
var
  OnProgress: TVfsProgressCallback;
  Path, Name: string;
  Done, Total: Int64;
begin
  Result := S_OK;
  if not Assigned(FOnProgress) or (iWorkTotal = 0) then
    Exit;
  OnProgress := FOnProgress;
  Path := FLastPath;
  Name := TPath.GetFileName(Path);
  Done := iWorkSoFar;
  Total := iWorkTotal;
  TThread.Queue(nil,
    procedure
    begin
      OnProgress(Done, Total, Name, 0, 0, Path, '');
    end);
end;

function TDeleteProgressSink.ResetTimer: HResult;
begin
  Result := S_OK;
end;

function TDeleteProgressSink.PauseTimer: HResult;
begin
  Result := S_OK;
end;

function TDeleteProgressSink.ResumeTimer: HResult;
begin
  Result := S_OK;
end;

function ShellDeleteErrorMessage(ACode: Integer): string;
begin
  // SHFileOperation uses its own pre-Win32 codes (not GetLastError).
  case ACode of
    $75: // DE_OPCANCELLED
      Result := 'Cancelled';
    $78: // DE_ACCESSDENIEDSRC
      Result := 'Access denied — cannot move to Recycle Bin ' +
        '(run as Administrator, or Shift+F8 for permanent delete)';
    $79: // DE_PATHTOODEEP
      Result := 'Path too deep for Recycle Bin';
    $7C: // DE_INVALIDFILES
      Result := 'Invalid path';
    $7D: // DE_DESTSAMETREE
      Result := 'Invalid recycle destination';
  else
    Result := Format('Recycle Bin failed (code %d)', [ACode]);
  end;
end;

function HResultDeleteErrorMessage(AHR: HRESULT): string;
var
  Code: DWORD;
begin
  // HRESULT with FACILITY_WIN32: 0x8007xxxx
  if (DWORD(AHR) and $FFFF0000) = $80070000 then
  begin
    Code := DWORD(AHR) and $FFFF;
    case Code of
      ERROR_ACCESS_DENIED:
        Exit('Access denied — cannot move to Recycle Bin ' +
          '(run as Administrator, or Shift+F8 for permanent delete)');
      ERROR_SHARING_VIOLATION:
        Exit('File is in use by another process');
      ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND:
        Exit('Path not found');
      ERROR_CANCELLED:
        Exit('Cancelled');
    end;
    Result := SysErrorMessage(Code);
    if Result <> '' then
      Exit;
  end;
  Result := Format('Recycle Bin failed (HRESULT 0x%x)', [AHR]);
end;

function DeleteToRecycleBinIFileOp(const APath: string; var AError: TVfsError;
  AOnProgress: TVfsProgressCallback): Boolean;
var
  Op: IFileOperation;
  Item: IShellItem;
  Sink: IFileOperationProgressSink;
  Cookie: DWORD;
  Advised: Boolean;
  HR: HRESULT;
  Aborted: BOOL;
  Full: string;
begin
  Result := False;
  Advised := False;
  Cookie := 0;
  Full := TPath.GetFullPath(APath);
  HR := CoCreateInstance(CLSID_FileOperation, nil, CLSCTX_INPROC_SERVER,
    IID_IFileOperation, Op);
  if Failed(HR) then
    Exit;

  // FOFX_SHOWELEVATIONPROMPT: allow UAC when deleting protected folders
  // (e.g. C:\inetpub) even with FOF_NOERRORUI.
  HR := Op.SetOperationFlags(FOF_ALLOWUNDO or FOF_NOCONFIRMATION or FOF_SILENT or
    FOF_NOERRORUI or FOFX_SHOWELEVATIONPROMPT);
  if Failed(HR) then
  begin
    AError := TVfsError.Make(vecIOError, HResultDeleteErrorMessage(HR),
      PathToFileUri(Full));
    Exit;
  end;

  HR := SHCreateItemFromParsingName(PWideChar(Full), nil, IID_IShellItem, Item);
  if Failed(HR) then
  begin
    AError := TVfsError.Make(vecIOError, HResultDeleteErrorMessage(HR),
      PathToFileUri(Full));
    Exit;
  end;

  HR := Op.DeleteItem(Item, nil);
  if Failed(HR) then
  begin
    AError := TVfsError.Make(vecIOError, HResultDeleteErrorMessage(HR),
      PathToFileUri(Full));
    Exit;
  end;

  if Assigned(AOnProgress) then
  begin
    Sink := TDeleteProgressSink.Create(AOnProgress);
    Advised := Succeeded(Op.Advise(Sink, Cookie));
  end;
  try
    HR := Op.PerformOperations;
  finally
    if Advised then
      Op.Unadvise(Cookie);
  end;
  if Failed(HR) then
  begin
    if not (LocalPathIsFile(Full) or LocalPathIsDirectory(Full)) then
      Exit(True); // gone despite HRESULT noise
    if (DWORD(HR) and $FFFF) = ERROR_CANCELLED then
      AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(Full))
    else if (DWORD(HR) and $FFFF) = ERROR_ACCESS_DENIED then
      AError := TVfsError.Make(vecAccessDenied, HResultDeleteErrorMessage(HR),
        PathToFileUri(Full))
    else
      AError := TVfsError.Make(vecIOError, HResultDeleteErrorMessage(HR),
        PathToFileUri(Full));
    Exit;
  end;

  Aborted := False;
  Op.GetAnyOperationsAborted(Aborted);
  if not (LocalPathIsFile(Full) or LocalPathIsDirectory(Full)) then
    Exit(True);
  if Aborted then
  begin
    AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(Full));
    Exit;
  end;
  AError := TVfsError.Make(vecIOError,
    'Delete verification failed: path still exists', PathToFileUri(Full));
end;

procedure DeleteToRecycleBin(const APath: string; var AError: TVfsError;
  AOnProgress: TVfsProgressCallback);
var
  Op: TSHFileOpStructW;
  Buf: PWideChar;
  Len: Integer;
  Path: string;
  Res: Integer;
  HR: HRESULT;
begin
  Path := ExcludeTrailingPathDelimiter(TPath.GetFullPath(APath));
  if Path = '' then
  begin
    AError := TVfsError.Make(vecInvalidURI, 'Invalid path', PathToFileUri(APath));
    Exit;
  end;
  if not (LocalPathIsFile(Path) or LocalPathIsDirectory(Path)) then
  begin
    AError := TVfsError.Make(vecNotFound, 'Path not found', PathToFileUri(Path));
    Exit;
  end;

  // Shell recycle APIs need COM on this thread (anonymous workers have none).
  HR := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  if Failed(HR) and (HR <> RPC_E_CHANGED_MODE) then
  begin
    AError := TVfsError.Make(vecIOError,
      'Recycle Bin unavailable (COM init failed)', PathToFileUri(Path));
    Exit;
  end;
  Buf := nil;
  try
    // Prefer modern IFileOperation (Explorer path + UAC elevation prompt).
    AError := TVfsError.Ok;
    AError.URI := PathToFileUri(Path);
    if DeleteToRecycleBinIFileOp(Path, AError, AOnProgress) then
      Exit;
    if AError.Code <> vecOk then
      Exit; // real failure from IFileOperation — do not hide behind SHFileOp

    // Fallback: legacy SHFileOperation.
    AError := TVfsError.Ok;
    AError.URI := PathToFileUri(Path);
    Len := Length(Path);
    GetMem(Buf, (Len + 2) * SizeOf(WideChar));
    if Len > 0 then
      Move(PWideChar(Path)^, Buf^, Len * SizeOf(WideChar));
    Buf[Len] := #0;
    Buf[Len + 1] := #0;

    FillChar(Op, SizeOf(Op), 0);
    Op.Wnd := 0;
    Op.wFunc := FO_DELETE;
    Op.pFrom := Buf;
    Op.pTo := nil;
    Op.fFlags := FOF_ALLOWUNDO or FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI;

    Res := SHFileOperationW(Op);
    if not (LocalPathIsFile(Path) or LocalPathIsDirectory(Path)) then
      Exit;
    if Op.fAnyOperationsAborted then
    begin
      AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(Path));
      Exit;
    end;
    if Res <> 0 then
    begin
      if Res = $78 then
        AError := TVfsError.Make(vecAccessDenied, ShellDeleteErrorMessage(Res),
          PathToFileUri(Path))
      else
        AError := TVfsError.Make(vecIOError, ShellDeleteErrorMessage(Res),
          PathToFileUri(Path));
      Exit;
    end;
    AError := TVfsError.Make(vecIOError,
      'Delete verification failed: path still exists', PathToFileUri(Path));
  finally
    if Buf <> nil then
      FreeMem(Buf);
    if Succeeded(HR) then
      CoUninitialize;
  end;
end;

end.
