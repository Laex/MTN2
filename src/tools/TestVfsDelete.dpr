program TestVfsDelete;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Winapi.Windows,
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uFileVfs in '..\Core\uFileVfs.pas';

var
  Vfs: IVirtualFileSystem;
  Tmp, F1, F2, Bang: string;
  ChangeH: THandle;
  URI1, URI2: string;
  Ev: TEvent;
  Ok: Boolean;
  ErrMsg, ErrURI: string;
  Mode: TVfsDeleteMode;
  Failed: Integer;
  LockH: THandle;
  Locked: string;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if ACond then
    Writeln('  OK  ', AMsg)
  else
  begin
    Inc(Failed);
    Writeln('  FAIL ', AMsg);
  end;
end;

procedure WaitDelete(const AURI: string; AMode: TVfsDeleteMode);
var
  Tick: Cardinal;
begin
  Ok := False;
  ErrMsg := '';
  Ev.ResetEvent;
  Vfs.DeleteAsync(AURI, AMode, nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Ok := ASuccess;
      ErrMsg := AError.Message;
      ErrURI := AError.URI;
      Ev.SetEvent;
    end);
  Tick := GetTickCount;
  while Ev.WaitFor(50) <> wrSignaled do
  begin
    CheckSynchronize;
    if GetTickCount - Tick > 15000 then
    begin
      Writeln('TIMEOUT');
      Exit;
    end;
  end;
  CheckSynchronize;
  Writeln('Success=', Ok, ' Msg=', ErrMsg);
end;

begin
  Failed := 0;
  Ev := TEvent.Create(nil, True, False, '');
  try
    Vfs := TFileVirtualFileSystem.Create;
    Tmp := TPath.Combine(TPath.GetTempPath, 'mtn2-vfs-del');
    ForceDirectories(Tmp);
    F1 := TPath.Combine(Tmp, 'recycle.txt');
    F2 := TPath.Combine(Tmp, 'wipe.txt');
    TFile.WriteAllText(F1, 'recycle');
    TFile.WriteAllText(F2, 'wipe');
    URI1 := PathToFileUri(F1);
    URI2 := PathToFileUri(F2);
    Writeln('URI1=', URI1);
    Writeln('Path1=', FileUriToPath(URI1));
    Writeln('=== RecycleAsync ===');
    Mode := vdmRecycleBin;
    WaitDelete(URI1, Mode);
    Writeln('Exists after=', TFile.Exists(F1));
    Writeln('=== PermanentAsync ===');
    Mode := vdmPermanent;
    WaitDelete(URI2, Mode);
    Writeln('Exists after=', TFile.Exists(F2));

    Writeln('=== Bang empty dir wipe ===');
    Bang := TPath.Combine(Tmp, '!Test!');
    ForceDirectories(Bang);
    Writeln('Bang exists before=', TDirectory.Exists(Bang));
    Writeln('URI=', PathToFileUri(Bang));
    Writeln('PathRoundTrip=', FileUriToPath(PathToFileUri(Bang)));
    Mode := vdmPermanent;
    WaitDelete(PathToFileUri(Bang), Mode);
    Expect(Ok, 'empty !Test! wipe succeeds');
    Expect(not LocalPathIsDirectory(Bang), 'empty !Test! is gone');

    Writeln('=== Bang nested dir wipe ===');
    Bang := TPath.Combine(Tmp, '!Nested!');
    ForceDirectories(TPath.Combine(Bang, 'sub'));
    TFile.WriteAllText(TPath.Combine(Bang, 'a.txt'), 'x');
    TFile.WriteAllText(TPath.Combine(TPath.Combine(Bang, 'sub'), 'b.txt'), 'y');
    WaitDelete(PathToFileUri(Bang), Mode);
    Expect(Ok, 'nested !Nested! wipe succeeds');
    Expect(not LocalPathIsDirectory(Bang), 'nested !Nested! is gone');

    Writeln('=== Bang dir wipe while change-notify handle is open ===');
    Bang := TPath.Combine(Tmp, '!Locked!');
    ForceDirectories(Bang);
    ChangeH := FindFirstChangeNotification(PChar(Bang), False,
      FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME);
    Writeln('WatchHandleValid=', ChangeH <> INVALID_HANDLE_VALUE);
    WaitDelete(PathToFileUri(Bang), Mode);
    if (ChangeH <> 0) and (ChangeH <> INVALID_HANDLE_VALUE) then
      FindCloseChangeNotification(ChangeH);
    Expect(Ok, 'watched !Locked! wipe succeeds');
    Expect(not LocalPathIsDirectory(Bang), 'watched !Locked! is gone');

    Writeln('=== Folder wipe while a child file is exclusively locked ===');
    Bang := TPath.Combine(Tmp, '!Busy!');
    ForceDirectories(Bang);
    Locked := TPath.Combine(Bang, 'open.txt');
    TFile.WriteAllText(Locked, 'busy');
    LockH := CreateFile(PChar(Locked), GENERIC_READ, 0, nil, OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL, 0);
    Expect((LockH <> 0) and (LockH <> INVALID_HANDLE_VALUE),
      'exclusive lock on child file');
    try
      WaitDelete(PathToFileUri(Bang), vdmPermanent);
      Expect(not Ok, 'busy folder wipe fails while a child is locked');
      Expect(SameText(ExcludeTrailingPathDelimiter(FileUriToPath(ErrURI)),
        ExcludeTrailingPathDelimiter(Locked)),
        'error URI names the locked child, not the parent folder');
    finally
      if (LockH <> 0) and (LockH <> INVALID_HANDLE_VALUE) then
        CloseHandle(LockH);
    end;
    WaitDelete(PathToFileUri(Bang), vdmPermanent);
    Expect(Ok, 'busy folder wipe succeeds after the lock is released');
  finally
    Ev.Free;
  end;
  if Failed > 0 then
  begin
    Writeln('Failed: ', Failed);
    Halt(1);
  end;
  Writeln('All VfsDelete checks passed.');
end.
