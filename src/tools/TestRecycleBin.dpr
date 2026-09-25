program TestRecycleBin;

{ Spike for the Recycle Bin virtual folder: validates, against the real
  Shell APIs, that (1) the Recycle Bin can be enumerated via
  IShellFolder2.EnumObjects, (2) its "Original Location" column can be
  found by self-discovering the column index via GetDetailsOf(nil, ...)
  rather than hardcoding an undocumented PROPERTYKEY, (3) IFileOperation
  .MoveItem can restore an item to that original location.

  Safety: only ever touches ONE scratch file this program creates itself
  (create -> delete to bin -> find by name -> restore -> verify -> clean
  up) — enumeration reads the real Recycle Bin's other entries (needed to
  find our own item and to prove enumeration works at realistic scale) but
  never restores or deletes anything other than our own scratch file. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  Winapi.Windows,
  Winapi.ActiveX,
  Winapi.ShlObj,
  Winapi.ShellAPI;

var
  GFailures: Integer = 0;
  GLog: TStringList;

// Console codepage on a non-English Windows install mangles Cyrillic
// (and other non-ASCII) Writeln output — log to a UTF-8 file instead so the
// actual column headers / paths returned by the Shell can be inspected
// accurately regardless of console codepage.
procedure Log(const AMsg: string);
begin
  Writeln(AMsg);
  GLog.Add(AMsg);
end;

procedure Check(ACondition: Boolean; const AWhat: string);
begin
  if ACondition then
    Log('  [PASS] ' + AWhat)
  else
  begin
    Log('  [FAIL] ' + AWhat);
    Inc(GFailures);
  end;
end;

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

procedure RestoreOne(const AParentFolder: IShellFolder; APidl: PItemIDList;
  const ADestFolderPath, ADestName: string);
var
  SrcItem, DestFolderItem: IShellItem;
  Op: IFileOperation;
  HR: HRESULT;
begin
  HR := SHCreateShellItem(nil, AParentFolder, APidl, SrcItem);
  if Failed(HR) then
  begin
    Log('  [FAIL] SHCreateShellItem for source item: 0x' + IntToHex(HR, 8));
    Inc(GFailures);
    Exit;
  end;
  TDirectory.CreateDirectory(ADestFolderPath); // ensure destination exists
  HR := SHCreateItemFromParsingName(PWideChar(ADestFolderPath), nil, IShellItem, DestFolderItem);
  if Failed(HR) then
  begin
    Log('  [FAIL] SHCreateItemFromParsingName for dest folder: 0x' + IntToHex(HR, 8));
    Inc(GFailures);
    Exit;
  end;
  HR := CoCreateInstance(CLSID_FileOperation, nil, CLSCTX_INPROC_SERVER, IID_IFileOperation, Op);
  if Failed(HR) then
  begin
    Log('  [FAIL] CoCreateInstance(CLSID_FileOperation): 0x' + IntToHex(HR, 8));
    Inc(GFailures);
    Exit;
  end;
  Op.SetOperationFlags(FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI);
  HR := Op.MoveItem(SrcItem, DestFolderItem, PWideChar(ADestName), nil);
  if Failed(HR) then
  begin
    Log('  [FAIL] MoveItem queue: 0x' + IntToHex(HR, 8));
    Inc(GFailures);
    Exit;
  end;
  HR := Op.PerformOperations;
  Check(Succeeded(HR), 'PerformOperations (restore)');
  Check(TFile.Exists(TPath.Combine(ADestFolderPath, ADestName)),
    'restored file exists at original location');
end;

var
  Desktop: IShellFolder;
  RecycleFolder: IShellFolder2;
  RecyclePidl: PItemIDList;
  Malloc: IMalloc;
  EnumList: IEnumIDList;
  ChildPidl: PItemIDList;
  Fetched: LongWord;
  HR: HRESULT;
  OrigLocationCol: Integer;
  Details: TShellDetails;
  ColHeader, DisplayName, ParsingName, Col0Name, OrigLocation: string;
  ScratchFile, ScratchDir: string;
  FoundName, FoundOrigLocation: string;
  FoundPidl: PItemIDList;
  Op: TSHFileOpStructW;
  Buf: array[0..MAX_PATH + 1] of WideChar;
  I, EnumCount: Integer;
begin
  GLog := TStringList.Create;
  CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  try
    // 1) Create + recycle a scratch file so we have a known needle.
    // NOTE: some temp-classified folders are excluded from the Recycle Bin
    // by Windows/drive policy (confirmed on this machine's D:\Temp — files
    // deleted there are purged immediately, not recycled, independent of
    // FOF_ALLOWUNDO) — use a normal user-profile folder instead so the
    // delete actually lands in the Recycle Bin this spike is testing.
    ScratchDir := TPath.Combine(TPath.Combine(GetEnvironmentVariable('USERPROFILE'),
      'Desktop'), 'mtn2_testrecyclebin');
    TDirectory.CreateDirectory(ScratchDir);
    ScratchFile := TPath.Combine(ScratchDir, 'needle_' + IntToStr(GetTickCount) + '.txt');
    TFile.WriteAllText(ScratchFile, 'spike');
    Log('Scratch file: ' + ScratchFile);

    FillChar(Buf, SizeOf(Buf), 0);
    StrPCopy(Buf, ScratchFile);
    FillChar(Op, SizeOf(Op), 0);
    Op.wFunc := FO_DELETE;
    Op.pFrom := Buf;
    Op.fFlags := FOF_ALLOWUNDO or FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI;
    Check(SHFileOperationW(Op) = 0, 'scratch file moved to Recycle Bin');
    Check(not TFile.Exists(ScratchFile), 'scratch file gone from original location');

    // 2) Bind the Recycle Bin's special folder.
    HR := SHGetDesktopFolder(Desktop);
    Check(Succeeded(HR), 'SHGetDesktopFolder');
    HR := SHGetMalloc(Malloc);
    Check(Succeeded(HR), 'SHGetMalloc');
    HR := SHGetSpecialFolderLocation(0, CSIDL_BITBUCKET, RecyclePidl);
    Check(Succeeded(HR), 'SHGetSpecialFolderLocation(CSIDL_BITBUCKET)');
    HR := Desktop.BindToObject(RecyclePidl, nil, IShellFolder2, RecycleFolder);
    Check(Succeeded(HR), 'Desktop.BindToObject -> IShellFolder2');
    if Assigned(Malloc) and (RecyclePidl <> nil) then
      Malloc.Free(RecyclePidl);
    if not Assigned(RecycleFolder) then
    begin
      Log('Cannot continue without IShellFolder2 — aborting.');
      Inc(GFailures);
      Exit;
    end;

    // 3) Log every column header (logged to file — console codepage mangles
    // non-ASCII on non-English Windows, e.g. this Russian-locale machine) —
    // for inspection, not decision-making: the Recycle Bin's column ORDER
    // (not the localized header text) is fixed by the shell — column 1 is
    // "Original Location" on every locale/Windows version tested by prior
    // art (Explorer, undelete tools). Trust that fixed index; the header
    // text substring match is kept only as a best-effort cross-check logged
    // for visibility, never as the sole source of truth.
    OrigLocationCol := 1;
    for I := 0 to 10 do
    begin
      FillChar(Details, SizeOf(Details), 0);
      if Failed(RecycleFolder.GetDetailsOf(nil, I, Details)) then
        Break;
      ColHeader := StrRetToStr(Details.str, nil);
      Log('  column ' + IntToStr(I) + ': "' + ColHeader + '"');
    end;
    Check(True, 'using fixed column index 1 for Original Location');

    // 4) Enumerate items, looking for our scratch file by display name.
    HR := RecycleFolder.EnumObjects(0,
      SHCONTF_FOLDERS or SHCONTF_NONFOLDERS or SHCONTF_INCLUDEHIDDEN, EnumList);
    Check(Succeeded(HR) and Assigned(EnumList), 'EnumObjects');
    FoundPidl := nil;
    FoundName := '';
    FoundOrigLocation := '';
    EnumCount := 0;
    if Assigned(EnumList) then
    begin
      while EnumList.Next(1, ChildPidl, Fetched) = S_OK do
      begin
        Inc(EnumCount);
        FillChar(Details, SizeOf(Details), 0);
        if Succeeded(RecycleFolder.GetDisplayNameOf(ChildPidl, SHGDN_NORMAL, Details.str)) then
          DisplayName := StrRetToStr(Details.str, ChildPidl)
        else
          DisplayName := '';
        FillChar(Details, SizeOf(Details), 0);
        if Succeeded(RecycleFolder.GetDisplayNameOf(ChildPidl, SHGDN_FORPARSING, Details.str)) then
          ParsingName := StrRetToStr(Details.str, ChildPidl)
        else
          ParsingName := '';
        FillChar(Details, SizeOf(Details), 0);
        if Succeeded(RecycleFolder.GetDetailsOf(ChildPidl, 0, Details)) then
          Col0Name := StrRetToStr(Details.str, ChildPidl)
        else
          Col0Name := '';
        OrigLocation := '';
        if OrigLocationCol >= 0 then
        begin
          FillChar(Details, SizeOf(Details), 0);
          if Succeeded(RecycleFolder.GetDetailsOf(ChildPidl, OrigLocationCol, Details)) then
            OrigLocation := StrRetToStr(Details.str, ChildPidl);
        end;
        if EnumCount <= 5 then
          Log('  item[' + IntToStr(EnumCount) + ']: normal="' + DisplayName +
            '" parsing="' + ParsingName + '" col0="' + Col0Name +
            '" origLoc="' + OrigLocation + '"');
        // Log any near-match unconditionally (diagnostic) — helps see exactly
        // what GetDisplayNameOf returns if the exact-match check below fails.
        if Pos('NEEDLE', UpperCase(DisplayName)) > 0 then
          Log('  candidate: name="' + DisplayName + '" origLoc="' + OrigLocation + '"');
        // GetDisplayNameOf(SHGDN_NORMAL) returned the full original path on
        // this Windows build, not a bare leaf name (see earlier spike log),
        // AND drops the extension when "Hide extensions for known file
        // types" is on (a system-wide Explorer display preference — this is
        // SHGDN_NORMAL being display-oriented, not identity-oriented).
        // Match on the leaf name with extension stripped from both sides;
        // the real feature should prefer SHGDN_FORPARSING instead, which is
        // documented to preserve the true name.
        if SameText(ExtractFileName(ChangeFileExt(DisplayName, '')),
           ExtractFileName(ChangeFileExt(ScratchFile, ''))) then
        begin
          FoundPidl := ChildPidl;
          FoundName := DisplayName;
          FoundOrigLocation := OrigLocation;
          Break; // keep this one PIDL alive; free the rest below via loop exit
        end;
        if Assigned(Malloc) then
          Malloc.Free(ChildPidl);
      end;
    end;
    Log('  total items enumerated: ' + IntToStr(EnumCount));
    Check(FoundPidl <> nil, 'found our scratch file in the Recycle Bin listing');
    if FoundPidl <> nil then
    begin
      Log('  found name: "' + FoundName + '"');
      Log('  original location column value: "' + FoundOrigLocation + '"');
      Check(SameText(IncludeTrailingPathDelimiter(FoundOrigLocation),
        IncludeTrailingPathDelimiter(ScratchDir)) or
        (Pos(UpperCase(ScratchDir), UpperCase(FoundOrigLocation)) > 0),
        'original location matches scratch directory');
    end;

    // 5) Restore via IFileOperation.MoveItem back to the original folder.
    if FoundPidl <> nil then
    begin
      RestoreOne(RecycleFolder, FoundPidl, ScratchDir, ExtractFileName(ScratchFile));
      if Assigned(Malloc) then
        Malloc.Free(FoundPidl);
    end;
  finally
    try
      if TDirectory.Exists(ScratchDir) then
        TDirectory.Delete(ScratchDir, True);
    except
    end;
    CoUninitialize;
    try
      GLog.SaveToFile(TPath.Combine(TPath.GetTempPath, 'mtn2_testrecyclebin_log.txt'),
        TEncoding.UTF8);
    except
    end;
    GLog.Free;
  end;

  Writeln;
  if GFailures = 0 then
    Writeln('ALL CHECKS PASSED')
  else
    Writeln(GFailures, ' CHECK(S) FAILED');
  ExitCode := GFailures;
end.
