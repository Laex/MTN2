program TestCreateLink;

{ Spike/regression for uLinkUtils: exercises symlink (file + dir), hardlink,
  and junction creation against real Win32 APIs in a scratch temp directory.
  Symlink creation without Developer Mode/elevation is expected to fail with
  a clean error (not a crash) — that path is reported, not treated as a
  hard failure of the run. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  uTextEncoding in '..\Core\uTextEncoding.pas',
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uLinkUtils in '..\Core\uLinkUtils.pas';

var
  GRoot: string;
  GFailures: Integer = 0;

procedure Check(ACondition: Boolean; const AWhat: string);
begin
  if ACondition then
    Writeln('  [PASS] ', AWhat)
  else
  begin
    Writeln('  [FAIL] ', AWhat);
    Inc(GFailures);
  end;
end;

procedure ReportOptional(ASucceeded: Boolean; const AWhat: string; const AError: TVfsError);
begin
  if ASucceeded then
    Writeln('  [PASS] ', AWhat)
  else
    Writeln('  [SKIP] ', AWhat, ' — ', AError.Message,
      ' (expected without Developer Mode/elevation on some systems)');
end;

procedure TestHardlink;
var
  SrcFile, LinkFile: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  Writeln('-- Hardlink (file) --');
  SrcFile := TPath.Combine(GRoot, 'source.txt');
  LinkFile := TPath.Combine(GRoot, 'hardlink.txt');
  TFile.WriteAllText(SrcFile, 'hello');
  Ok := CreateFileLink(LinkFile, SrcFile, lkHardlink, Err);
  Check(Ok, 'CreateFileLink(lkHardlink) succeeds');
  if Ok then
  begin
    Check(TFile.Exists(LinkFile), 'hardlink target file exists');
    Check(TFile.ReadAllText(LinkFile) = 'hello', 'hardlink content matches source');
  end
  else
    Writeln('    error: ', Err.Message);
end;

procedure TestSymlinkFile;
var
  SrcFile, LinkFile: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  Writeln('-- Symbolic link (file) --');
  SrcFile := TPath.Combine(GRoot, 'source.txt');
  LinkFile := TPath.Combine(GRoot, 'symlink.txt');
  Ok := CreateFileLink(LinkFile, SrcFile, lkSymlinkFile, Err);
  ReportOptional(Ok, 'CreateFileLink(lkSymlinkFile)', Err);
  if Ok then
    Check(TFile.Exists(LinkFile), 'symlink target resolves');
end;

procedure TestSymlinkDir;
var
  SrcDir, LinkDir: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  Writeln('-- Symbolic link (directory) --');
  SrcDir := TPath.Combine(GRoot, 'srcdir');
  LinkDir := TPath.Combine(GRoot, 'symlinkdir');
  TDirectory.CreateDirectory(SrcDir);
  TFile.WriteAllText(TPath.Combine(SrcDir, 'inside.txt'), 'x');
  Ok := CreateFileLink(LinkDir, SrcDir, lkSymlinkDir, Err);
  ReportOptional(Ok, 'CreateFileLink(lkSymlinkDir)', Err);
  if Ok then
    Check(TFile.Exists(TPath.Combine(LinkDir, 'inside.txt')), 'symlink dir resolves to contents');
end;

procedure TestJunction;
var
  SrcDir, LinkDir: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  Writeln('-- Junction --');
  SrcDir := TPath.Combine(GRoot, 'srcdir');
  LinkDir := TPath.Combine(GRoot, 'junctiondir');
  Ok := CreateFileLink(LinkDir, SrcDir, lkJunction, Err);
  Check(Ok, 'CreateFileLink(lkJunction) succeeds');
  if Ok then
    Check(TFile.Exists(TPath.Combine(LinkDir, 'inside.txt')), 'junction resolves to contents')
  else
    Writeln('    error: ', Err.Message);
end;

begin
  Randomize;
  GRoot := TPath.Combine(TPath.GetTempPath, 'mtn2_testcreatelink_' + IntToStr(Random(100000)));
  TDirectory.CreateDirectory(GRoot);
  try
    TestHardlink;
    TestSymlinkFile;
    TestSymlinkDir;
    TestJunction;
  finally
    try
      TDirectory.Delete(GRoot, True);
    except
    end;
  end;

  Writeln;
  if GFailures = 0 then
    Writeln('ALL REQUIRED CHECKS PASSED (symlink creation may have been skipped — see above)')
  else
    Writeln(GFailures, ' CHECK(S) FAILED');
  ExitCode := GFailures;
end.
