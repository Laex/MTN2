unit TestFileFind;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFileFind = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Math,
  System.SyncObjs,
  Winapi.Windows,
  uVfsTypes,
  uFileFind;

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
    procedure(const AHits: TArray<TFindHit>; const AError: TVfsError)
    begin
      SetLength(Paths, Length(AHits));
      for var H := 0 to High(AHits) do
        Paths[H] := AHits[H].Path;
      Err := AError;
      Ev.SetEvent;
    end);
  Tick := GetTickCount;
  while Ev.WaitFor(50) <> wrSignaled do
  begin
    CheckSynchronize;
    if GetTickCount - Tick > 15000 then
      Assert.Fail('find timed out: ' + ARoot);
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

{ TTestFileFind }

procedure TTestFileFind.Run;
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
    Assert.IsTrue(Length(Paths) = 2, '*.pas with subfolders finds a.pas and sub\c.pas');
    WaitFind(Root, '*.pas', False);
    Assert.IsTrue(Length(Paths) = 1, '*.pas without subfolders finds only a.pas');
    WaitFind(Root, '*.*', True);
    Assert.IsTrue(Length(Paths) = 4, '*.* with subfolders finds every file');
    WaitFind(Root + '_missing', '*.*', True);
    Assert.IsTrue(Length(Paths) = 0, 'missing root finds nothing');

    // Simulate what Dual Panel does for archive URI (bug surface).
    UriInsideZip := PathToFileUri(TPath.Combine(Root, 'fake.zip')) + '!/docs';
    Zipish := FileUriToPath(UriInsideZip);
    System.Writeln('--- Archive URI round-trip');
    System.Writeln('  URI=', UriInsideZip);
    System.Writeln('  FileUriToPath=', Zipish);
    System.Writeln('  ExistsDir=', TDirectory.Exists(Zipish));
    WaitFind(Zipish, '*.*', True);

    // Correct root when inside zip should be archive base dir (parent of zip).
    WaitFind(TPath.GetDirectoryName(ArchiveBasePath(UriInsideZip)), '*.pas', True);
  finally
    Ev.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFileFind);

end.
