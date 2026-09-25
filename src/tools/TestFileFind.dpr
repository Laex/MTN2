program TestFileFind;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Math,
  System.SyncObjs,
  Winapi.Windows,
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uFileFind in '..\Core\uFileFind.pas';

var
  Ev: TEvent;
  Paths: TArray<string>;
  Err: TVfsError;
  ProgressHits: Integer;
  LastDir: string;

procedure WaitFind(const ARoot, AMask: string; ASubdirs: Boolean);
var
  Tick: Cardinal;
  Opts: TFindOptions;
begin
  SetLength(Paths, 0);
  Err := TVfsError.Ok;
  ProgressHits := 0;
  LastDir := '';
  Ev.ResetEvent;
  Writeln('--- Find root=', ARoot, ' mask=', AMask, ' sub=', ASubdirs);
  Opts := DefaultFindOptions(ARoot, AMask, ASubdirs);
  FindFilesAsync(Opts, nil,
    procedure(AFoundCount: Integer; const ACurrentDir: string)
    begin
      Inc(ProgressHits);
      LastDir := ACurrentDir;
    end,
    procedure(const APaths: TArray<string>; const AError: TVfsError)
    begin
      Paths := APaths;
      Err := AError;
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
  Writeln('  Err=', Ord(Err.Code), ' ', Err.Message, ' count=', Length(Paths),
    ' progress=', ProgressHits);
  var I, ShowN: Integer;
  ShowN := Min(Length(Paths), 8);
  for I := 0 to ShowN - 1 do
    Writeln('    ', Paths[I]);
  if Length(Paths) > ShowN then
    Writeln('    ...');
end;

var
  Root, Nested, Zipish: string;
  UriInsideZip: string;
begin
  Ev := TEvent.Create(nil, True, False, '');
  try
    Root := TPath.Combine(TPath.GetTempPath, 'mtn2-find-smoke');
    if TDirectory.Exists(Root) then
      TDirectory.Delete(Root, True);
    Nested := TPath.Combine(Root, 'sub');
    ForceDirectories(Nested);
    TFile.WriteAllText(TPath.Combine(Root, 'a.pas'), 'x');
    TFile.WriteAllText(TPath.Combine(Root, 'b.txt'), 'y');
    TFile.WriteAllText(TPath.Combine(Nested, 'c.pas'), 'z');
    TFile.WriteAllText(TPath.Combine(Nested, 'readme.md'), 'm');

    WaitFind(Root, '*.pas', True);
    WaitFind(Root, '*.pas', False);
    WaitFind(Root, '*.*', True);
    WaitFind(Root + '_missing', '*.*', True);

    // Simulate what Dual Panel does for archive URI (bug surface).
    UriInsideZip := PathToFileUri(TPath.Combine(Root, 'fake.zip')) + '!/docs';
    Zipish := FileUriToPath(UriInsideZip);
    Writeln('--- Archive URI round-trip');
    Writeln('  URI=', UriInsideZip);
    Writeln('  FileUriToPath=', Zipish);
    Writeln('  ExistsDir=', TDirectory.Exists(Zipish));
    WaitFind(Zipish, '*.*', True);

    // Correct root when inside zip should be archive base dir (parent of zip).
    WaitFind(TPath.GetDirectoryName(ArchiveBasePath(UriInsideZip)), '*.pas', True);
  finally
    Ev.Free;
  end;
end.
