program TestDelete;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  Winapi.ShellAPI,
  Winapi.ActiveX;

function Recycle(const APath: string): Integer;
var
  Op: TSHFileOpStructW;
  Buf: PWideChar;
  Len: Integer;
  Path: string;
  HR: HRESULT;
begin
  Path := ExcludeTrailingPathDelimiter(APath);
  Writeln('Path=', Path);
  Writeln('Exists file=', FileExists(Path), ' dir=', DirectoryExists(Path));
  HR := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  Writeln('CoInit HR=', IntToHex(HR, 8));
  Len := Length(Path);
  GetMem(Buf, (Len + 2) * SizeOf(WideChar));
  try
    Move(PWideChar(Path)^, Buf^, Len * SizeOf(WideChar));
    Buf[Len] := #0;
    Buf[Len + 1] := #0;
    FillChar(Op, SizeOf(Op), 0);
    Op.wFunc := FO_DELETE;
    Op.pFrom := Buf;
    Op.fFlags := FOF_ALLOWUNDO or FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI;
    Result := SHFileOperationW(Op);
    Writeln('SHFileOp Res=', Result, ' aborted=', Op.fAnyOperationsAborted);
    Writeln('Exists after=', FileExists(Path) or DirectoryExists(Path));
  finally
    FreeMem(Buf);
    if Succeeded(HR) then
      CoUninitialize;
  end;
end;

function Wipe(const APath: string): Boolean;
begin
  Result := DeleteFile(PChar(APath));
  Writeln('DeleteFile=', Result, ' err=', GetLastError);
  Writeln('Exists after=', FileExists(APath));
end;

var
  Tmp, F1, F2: string;
begin
  Tmp := TPath.Combine(TPath.GetTempPath, 'mtn2-del-test');
  ForceDirectories(Tmp);
  F1 := TPath.Combine(Tmp, 'recycle.txt');
  F2 := TPath.Combine(Tmp, 'wipe.txt');
  TFile.WriteAllText(F1, 'recycle-me');
  TFile.WriteAllText(F2, 'wipe-me');
  Writeln('=== RECYCLE ===');
  Recycle(F1);
  Writeln('=== WIPE ===');
  Wipe(F2);
end.
