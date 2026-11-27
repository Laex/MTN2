unit TestGitOps;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestGitOps = class
  private
    FDir: string;
    procedure Git(const AArgs: TArray<string>);
    function GitText(const AArgs: TArray<string>): string;
    procedure Put(const AName, AText: string);
    function Staged: string;
    procedure CommitAll(const AMessage: string);
  public
    [Setup] procedure SetUp;
    [TearDown] procedure TearDown;
    [Test] procedure TestNamesAreSplitIntoBatchesThatFitACommandLine;
    [Test] procedure TestStageAddsOnlyTheNamedFiles;
    [Test] procedure TestStageRecordsADeletionInsideAFolder;
    [Test] procedure TestUnstageWorksBeforeTheFirstCommitAndKeepsTheFile;
    [Test] procedure TestCommitKeepsANonLatinMessage;
    [Test] procedure TestCommitWithNothingStagedFailsWithGitsAnswer;
    [Test] procedure TestBranchesNameTheCurrentOneAndSwitchChangesIt;
    [Test] procedure TestSwitchKeepsLocalChangesItWouldOverwrite;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, uPlatformProcess, uGitOps;

const
  // A Cyrillic word, spelled by code so the source stays ASCII.
  cWord = #$0444#$0430#$0439#$043B;

procedure TTestGitOps.SetUp;
var
  Output: string;
  Code: Cardinal;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'mtn2-git-ops-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
  Assert.IsTrue((PlatformRunCaptured('git', ['init', '-q', '-b', 'main', FDir], '', 15000, nil,
    Output, Code) = srOk) and (Code = 0), 'git init: ' + Output);
  Git(['config', 'user.name', 't']);
  Git(['config', 'user.email', 't@example.com']);
  Git(['config', 'commit.gpgsign', 'false']);
end;

procedure TTestGitOps.TearDown;
var
  Name: string;
begin
  // git marks its object files read-only, which stops a folder delete on Windows.
  for Name in TDirectory.GetFiles(FDir, '*', TSearchOption.soAllDirectories) do
    TFile.SetAttributes(Name, []);
  TDirectory.Delete(FDir, True);
end;

function TTestGitOps.GitText(const AArgs: TArray<string>): string;
var
  Code: Cardinal;
  Args: TArray<string>;
begin
  Args := ['-C', FDir];
  Args := Args + AArgs;
  Assert.IsTrue((PlatformRunCaptured('git', Args, '', 15000, nil,
    Result, Code) = srOk) and (Code = 0), 'git ' + string.Join(' ', AArgs) + ': ' + Result);
  Result := Result.Replace(#13, '').Trim;
end;

procedure TTestGitOps.Git(const AArgs: TArray<string>);
begin
  GitText(AArgs);
end;

procedure TTestGitOps.Put(const AName, AText: string);
var
  Path: string;
begin
  Path := TPath.Combine(FDir, AName.Replace('/', PathDelim));
  TDirectory.CreateDirectory(TPath.GetDirectoryName(Path));
  TFile.WriteAllText(Path, AText);
end;

function TTestGitOps.Staged: string;
var
  Files: TArray<string>;
  Output: string;
begin
  Assert.IsTrue(GitStagedFiles(FDir, nil, Files, Output), Output);
  Result := string.Join('|', Files);
end;

procedure TTestGitOps.CommitAll(const AMessage: string);
begin
  Git(['add', '-A']);
  Git(['commit', '-q', '-m', AMessage]);
end;

procedure TTestGitOps.TestNamesAreSplitIntoBatchesThatFitACommandLine;
var
  Batches: TArray<TArray<string>>;
  Batch: TArray<string>;
  Joined: string;
  Long: string;
begin
  Long := StringOfChar('x', 40);
  Batches := GitNameBatches(['aaaa', 'bbbb', Long, 'cccc'], 12);
  Joined := '';
  for Batch in Batches do
    Joined := Joined + '[' + string.Join(',', Batch) + ']';
  Assert.AreEqual('[aaaa,bbbb][' + Long + '][cccc]', Joined);
  Assert.AreEqual<Integer>(0, Length(GitNameBatches(nil, 12)));
end;

procedure TTestGitOps.TestStageAddsOnlyTheNamedFiles;
var
  Output: string;
begin
  Put(cWord + ' [1].txt', 'a');
  Put(cWord + ' 1.txt', 'b');
  Put('other.txt', 'c');
  // Brackets are a file name here, not a wildcard that also matches "... 1.txt".
  Assert.IsTrue(GitStagePaths(FDir, [cWord + ' [1].txt'], nil, Output), Output);
  Assert.AreEqual(cWord + ' [1].txt', Staged);
end;

procedure TTestGitOps.TestStageRecordsADeletionInsideAFolder;
var
  Output: string;
begin
  Put('sub/gone.txt', 'a');
  Put('sub/stays.txt', 'b');
  CommitAll('first');
  TFile.Delete(TPath.Combine(FDir, 'sub' + PathDelim + 'gone.txt'));
  Assert.IsTrue(GitStagePaths(FDir, ['sub'], nil, Output), Output);
  Assert.AreEqual('D  sub/gone.txt', GitText(['status', '--porcelain']));
end;

procedure TTestGitOps.TestUnstageWorksBeforeTheFirstCommitAndKeepsTheFile;
var
  Output: string;
begin
  Put('a.txt', 'a');
  Put('b.txt', 'b');
  Git(['add', 'a.txt', 'b.txt']);
  Assert.IsTrue(GitUnstagePaths(FDir, ['a.txt'], nil, Output), Output);
  Assert.AreEqual('b.txt', Staged);
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDir, 'a.txt')));
end;

procedure TTestGitOps.TestCommitKeepsANonLatinMessage;
var
  Output, Message: string;
begin
  Put('a.txt', 'a');
  Git(['add', 'a.txt']);
  Message := cWord + ' "quoted" 100% \ end';
  Assert.IsTrue(GitCommitStaged(FDir, Message, nil, Output), Output);
  Assert.AreEqual(Message, GitText(['log', '-1', '--format=%s']));
  Assert.AreEqual('', Staged);
end;

procedure TTestGitOps.TestCommitWithNothingStagedFailsWithGitsAnswer;
var
  Output: string;
begin
  Put('a.txt', 'a');
  CommitAll('first');
  Assert.IsFalse(GitCommitStaged(FDir, 'second', nil, Output));
  Assert.IsTrue(Output.Trim <> '', 'git says why');
end;

procedure TTestGitOps.TestBranchesNameTheCurrentOneAndSwitchChangesIt;
var
  Branches: TArray<string>;
  Current, Output: string;
begin
  Put('a.txt', 'a');
  CommitAll('first');
  Git(['branch', 'feature/' + cWord]);
  Assert.IsTrue(GitBranches(FDir, nil, Branches, Current, Output), Output);
  Assert.AreEqual('feature/' + cWord + '|main', string.Join('|', Branches));
  Assert.AreEqual('main', Current);
  Assert.IsTrue(GitSwitchBranch(FDir, 'feature/' + cWord, nil, Output), Output);
  Assert.IsTrue(GitBranches(FDir, nil, Branches, Current, Output), Output);
  Assert.AreEqual('feature/' + cWord, Current);
  Assert.IsFalse(GitSwitchBranch(FDir, 'missing', nil, Output));
  Assert.IsTrue(Output.Trim <> '', 'git says why');
end;

procedure TTestGitOps.TestSwitchKeepsLocalChangesItWouldOverwrite;
var
  Output: string;
begin
  Put('a.txt', 'one');
  CommitAll('first');
  Git(['checkout', '-q', '-b', 'other']);
  Put('a.txt', 'two');
  CommitAll('second');
  Git(['checkout', '-q', 'main']);
  Put('a.txt', 'local');
  Assert.IsFalse(GitSwitchBranch(FDir, 'other', nil, Output));
  Assert.IsTrue(Output.Contains('a.txt'), 'git names the file: ' + Output);
  Assert.AreEqual('local', TFile.ReadAllText(TPath.Combine(FDir, 'a.txt')));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGitOps);

end.
