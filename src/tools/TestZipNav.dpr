program TestZipNav;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Winapi.Windows,
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uFileVfs in '..\Core\uFileVfs.pas',
  uZipVfs in '..\Core\uZipVfs.pas',
  uFindSession in '..\Core\uFindSession.pas',
  uFindVfs in '..\Core\uFindVfs.pas',
  uVfsRegistry in '..\Core\uVfsRegistry.pas',
  uVfsRouter in '..\Core\uVfsRouter.pas';

var
  Vfs: IVirtualFileSystem;
  Ev: TEvent;
  LastItems: TArray<TVfsEntry>;
  LastErr: TVfsError;

procedure WaitList(const AURI: string);
var
  Tick: Cardinal;
begin
  SetLength(LastItems, 0);
  LastErr := TVfsError.Ok;
  Ev.ResetEvent;
  Writeln('--- List: ', AURI);
  Writeln('    Parent=', ParentVfsUri(AURI));
  Writeln('    Title=', VfsUriTitle(AURI));
  Writeln('    Resolve=', ResolveVfsUri(AURI));
  Vfs.ListDirectoryAsync(AURI, nil,
    procedure(const AItems: TArray<TVfsEntry>; const AError: TVfsError)
    begin
      LastItems := AItems;
      LastErr := AError;
      Ev.SetEvent;
    end);
  Tick := GetTickCount;
  while Ev.WaitFor(50) <> wrSignaled do
  begin
    CheckSynchronize;
    if GetTickCount - Tick > 10000 then
    begin
      Writeln('TIMEOUT');
      Exit;
    end;
  end;
  CheckSynchronize;
  Writeln('    Err.Code=', Ord(LastErr.Code), ' Msg=', LastErr.Message,
    ' Count=', Length(LastItems));
  var I: Integer;
  for I := 0 to High(LastItems) do
    Writeln('      ', LastItems[I].Name, ' dir=', LastItems[I].IsDirectory,
      ' join=', JoinVfsUri(AURI, LastItems[I].Name));
end;

var
  ZipPath, RootURI, DocsURI, SubURI, UpURI: string;
begin
  Ev := TEvent.Create(nil, True, False, '');
  try
    Vfs := CreateDefaultVfs;
    ZipPath := TPath.Combine(TPath.GetTempPath, 'mtn2-zip-parent-bug\test.zip');
    if not TFile.Exists(ZipPath) then
    begin
      Writeln('Missing zip: ', ZipPath);
      Halt(1);
    end;
    RootURI := EnsureArchiveRootUri(PathToFileUri(ZipPath));
    DocsURI := JoinVfsUri(RootURI, 'docs');
    SubURI := JoinVfsUri(DocsURI, 'sub');
    WaitList(RootURI);
    WaitList(DocsURI);
    WaitList(SubURI);
    UpURI := ParentVfsUri(SubURI);
    Writeln('Up from sub => ', UpURI, ' SameDocs=', SameVfsUri(UpURI, DocsURI));
    WaitList(UpURI);
    UpURI := ParentVfsUri(DocsURI);
    Writeln('Up from docs => ', UpURI, ' SameRoot=', SameVfsUri(UpURI, RootURI));
    WaitList(UpURI);
  finally
    Ev.Free;
  end;
end.
