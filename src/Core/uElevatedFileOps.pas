unit uElevatedFileOps;

{ Copy, move or delete of local paths through the Shell IFileOperation API with
  one UAC prompt for the whole batch, the way Explorer does it. The panels
  copy and move with plain file I/O, which fails with "Access denied" in a
  protected folder (C:\Program Files); the job controller then offers to repeat
  the rest of the job here. The Shell shows its own progress, conflict and
  error dialogs. Paths are plain Win32 paths: the Shell rejects the \\?\ prefix. }

interface

type
  TElevatedFileOp = (efoCopy, efoMove, efoDelete);

/// <summary>True when the process already runs with an elevated token (UAC
/// would add nothing).</summary>
function IsProcessElevated: Boolean;

/// <summary>Runs AOp on every ASrcPaths[I] (ADstPaths[I] is its new full path
/// for copy/move; unused for delete) as one Shell operation with a single UAC
/// prompt. ARecycle: a delete goes to the Recycle Bin. AOverwrite: replace
/// existing destinations without asking. Needs no COM set up by the caller; run
/// it off the UI thread. ACancelled is set when the user declined the prompt
/// or cancelled; AMessage carries the failure text otherwise.</summary>
function ElevatedFileBatch(AOp: TElevatedFileOp; const ASrcPaths,
  ADstPaths: TArray<string>; ARecycle, AOverwrite: Boolean; AOwnerWindow: NativeUInt;
  out AMessage: string; out ACancelled: Boolean): Boolean;

implementation

uses
  System.SysUtils, System.IOUtils,
  Winapi.Windows, Winapi.ShellAPI, Winapi.ShlObj, Winapi.ActiveX;

function IsProcessElevated: Boolean;
var
  Token: THandle;
  Elev: TOKEN_ELEVATION;
  Size: DWORD;
begin
  Result := False;
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token) then
    Exit;
  try
    if GetTokenInformation(Token, TokenElevation, @Elev, SizeOf(Elev), Size) then
      Result := Elev.TokenIsElevated <> 0;
  finally
    CloseHandle(Token);
  end;
end;

function ElevatedFileBatch(AOp: TElevatedFileOp; const ASrcPaths,
  ADstPaths: TArray<string>; ARecycle, AOverwrite: Boolean; AOwnerWindow: NativeUInt;
  out AMessage: string; out ACancelled: Boolean): Boolean;
var
  Op: IFileOperation;
  Item, DestDir: IShellItem;
  Flags: DWORD;
  HR, Inited: HRESULT;
  Aborted: BOOL;
  I: Integer;
  DestPath, DestName: string;
begin
  Result := False;
  AMessage := '';
  ACancelled := False;
  if (Length(ASrcPaths) = 0) or
     ((AOp <> efoDelete) and (Length(ADstPaths) <> Length(ASrcPaths))) then
  begin
    AMessage := 'Nothing to do';
    Exit;
  end;
  Inited := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  try
    HR := CoCreateInstance(CLSID_FileOperation, nil, CLSCTX_INPROC_SERVER,
      IID_IFileOperation, Op);
    if Failed(HR) then
    begin
      AMessage := 'Shell file operation unavailable';
      Exit;
    end;
    // One UAC prompt for the whole batch; the Shell asks about conflicts and
    // reports errors itself.
    Flags := FOFX_SHOWELEVATIONPROMPT or FOF_NOCONFIRMMKDIR;
    if AOverwrite then
      Flags := Flags or FOF_NOCONFIRMATION;
    if (AOp = efoDelete) and ARecycle then
      Flags := Flags or FOF_ALLOWUNDO;
    if (AOp = efoDelete) and not ARecycle then
      Flags := Flags or FOF_NOCONFIRMATION;
    Op.SetOperationFlags(Flags);
    if AOwnerWindow <> 0 then
      Op.SetOwnerWindow(HWND(AOwnerWindow));

    for I := 0 to High(ASrcPaths) do
    begin
      HR := SHCreateItemFromParsingName(PWideChar(ASrcPaths[I]), nil,
        IID_IShellItem, Item);
      if Failed(HR) then
      begin
        AMessage := SysErrorMessage(DWORD(HR) and $FFFF);
        Exit;
      end;
      if AOp = efoDelete then
        HR := Op.DeleteItem(Item, nil)
      else
      begin
        DestPath := ExtractFilePath(ADstPaths[I]);
        DestName := ExtractFileName(ADstPaths[I]);
        if DestPath <> '' then
          try
            TDirectory.CreateDirectory(DestPath);
          except
            // the Shell creates it, with elevation if it must
          end;
        // "C:\" keeps its backslash: "C:" would mean the drive's current folder.
        if Length(DestPath) > 3 then
          DestPath := ExcludeTrailingPathDelimiter(DestPath);
        HR := SHCreateItemFromParsingName(PWideChar(DestPath), nil,
          IID_IShellItem, DestDir);
        if Failed(HR) then
        begin
          AMessage := SysErrorMessage(DWORD(HR) and $FFFF);
          Exit;
        end;
        if AOp = efoCopy then
          HR := Op.CopyItem(Item, DestDir, PWideChar(DestName), nil)
        else
          HR := Op.MoveItem(Item, DestDir, PWideChar(DestName), nil);
      end;
      if Failed(HR) then
      begin
        AMessage := SysErrorMessage(DWORD(HR) and $FFFF);
        Exit;
      end;
    end;

    HR := Op.PerformOperations;
    Aborted := False;
    Op.GetAnyOperationsAborted(Aborted);
    if Failed(HR) then
    begin
      ACancelled := Aborted or (HR = E_ABORT) or
        ((DWORD(HR) and $FFFF) = ERROR_CANCELLED);
      if not ACancelled then
        AMessage := SysErrorMessage(DWORD(HR) and $FFFF);
      Exit;
    end;
    if Aborted then
    begin
      ACancelled := True;
      Exit;
    end;
    Result := True;
  finally
    Item := nil;
    DestDir := nil;
    Op := nil;
    if Succeeded(Inited) then
      CoUninitialize;
  end;
end;

end.
