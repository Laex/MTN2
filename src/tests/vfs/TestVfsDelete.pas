unit TestVfsDelete;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVfsDelete = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Winapi.Windows,
  uVfsTypes,
  uFileVfs;

var
  Vfs: IVirtualFileSystem;
  Tmp, F1, F2, Bang: string;
  ChangeH: THandle;
  URI1, URI2: string;
  Ev: TEvent;
  Ok: Boolean;
  ErrMsg, ErrURI: string;
  Mode: TVfsDeleteMode;
  LockH: THandle;
  Locked: string;

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

{ TTestVfsDelete }

procedure TTestVfsDelete.Run;
begin
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
    System.Writeln('URI1=', URI1);
    System.Writeln('Path1=', FileUriToPath(URI1));
    System.Writeln('=== RecycleAsync ===');
    Mode := vdmRecycleBin;
    WaitDelete(URI1, Mode);
    System.Writeln('Exists after=', TFile.Exists(F1));
    System.Writeln('=== PermanentAsync ===');
    Mode := vdmPermanent;
    WaitDelete(URI2, Mode);
    System.Writeln('Exists after=', TFile.Exists(F2));

    System.Writeln('=== Bang empty dir wipe ===');
    Bang := TPath.Combine(Tmp, '!Test!');
    ForceDirectories(Bang);
    System.Writeln('Bang exists before=', TDirectory.Exists(Bang));
    System.Writeln('URI=', PathToFileUri(Bang));
    System.Writeln('PathRoundTrip=', FileUriToPath(PathToFileUri(Bang)));
    Mode := vdmPermanent;
    WaitDelete(PathToFileUri(Bang), Mode);
    Assert.IsTrue(Ok, 'empty !Test! wipe succeeds');
    Assert.IsTrue(not LocalPathIsDirectory(Bang), 'empty !Test! is gone');

    System.Writeln('=== Bang nested dir wipe ===');
    Bang := TPath.Combine(Tmp, '!Nested!');
    ForceDirectories(TPath.Combine(Bang, 'sub'));
    TFile.WriteAllText(TPath.Combine(Bang, 'a.txt'), 'x');
    TFile.WriteAllText(TPath.Combine(TPath.Combine(Bang, 'sub'), 'b.txt'), 'y');
    WaitDelete(PathToFileUri(Bang), Mode);
    Assert.IsTrue(Ok, 'nested !Nested! wipe succeeds');
    Assert.IsTrue(not LocalPathIsDirectory(Bang), 'nested !Nested! is gone');

    System.Writeln('=== Bang dir wipe while change-notify handle is open ===');
    Bang := TPath.Combine(Tmp, '!Locked!');
    ForceDirectories(Bang);
    ChangeH := FindFirstChangeNotification(PChar(Bang), False,
      FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME);
    System.Writeln('WatchHandleValid=', ChangeH <> INVALID_HANDLE_VALUE);
    WaitDelete(PathToFileUri(Bang), Mode);
    if (ChangeH <> 0) and (ChangeH <> INVALID_HANDLE_VALUE) then
      FindCloseChangeNotification(ChangeH);
    Assert.IsTrue(Ok, 'watched !Locked! wipe succeeds');
    Assert.IsTrue(not LocalPathIsDirectory(Bang), 'watched !Locked! is gone');

    System.Writeln('=== Folder wipe while a child file is exclusively locked ===');
    Bang := TPath.Combine(Tmp, '!Busy!');
    ForceDirectories(Bang);
    Locked := TPath.Combine(Bang, 'open.txt');
    TFile.WriteAllText(Locked, 'busy');
    LockH := CreateFile(PChar(Locked), GENERIC_READ, 0, nil, OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL, 0);
    Assert.IsTrue((LockH <> 0) and (LockH <> INVALID_HANDLE_VALUE),
      'exclusive lock on child file');
    try
      WaitDelete(PathToFileUri(Bang), vdmPermanent);
      Assert.IsTrue(not Ok, 'busy folder wipe fails while a child is locked');
      Assert.IsTrue(SameText(ExcludeTrailingPathDelimiter(FileUriToPath(ErrURI)),
        ExcludeTrailingPathDelimiter(Locked)),
        'error URI names the locked child, not the parent folder');
    finally
      if (LockH <> 0) and (LockH <> INVALID_HANDLE_VALUE) then
        CloseHandle(LockH);
    end;
    WaitDelete(PathToFileUri(Bang), vdmPermanent);
    Assert.IsTrue(Ok, 'busy folder wipe succeeds after the lock is released');
  finally
    Ev.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestVfsDelete);

end.
