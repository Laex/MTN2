unit uGitOps;

{ The git commands that change a repository: add to and remove from the index,
  commit, switch the branch. Each runs in the folder ADir and returns True when
  git exited with code 0; AOutput is what git printed. Names are relative to
  ADir and are taken literally, so "[", "*" or ":" in a file name stay part of
  the name. There is no time limit: hooks and large trees take as long as they
  take, and ACancelled stops them. }

interface

uses
  System.SysUtils;

/// <summary>Splits ANames into groups whose names together stay within
/// AMaxChars, so one command line is never too long. A longer name gets a group
/// of its own.</summary>
function GitNameBatches(const ANames: TArray<string>; AMaxChars: Integer): TArray<TArray<string>>;

/// <summary>Adds the files and folders to the index, deletions included.</summary>
function GitStagePaths(const ADir: string; const ANames: TArray<string>;
  const ACancelled: TFunc<Boolean>; out AOutput: string): Boolean;

/// <summary>Removes the files and folders from the index; the files stay as
/// they are.</summary>
function GitUnstagePaths(const ADir: string; const ANames: TArray<string>;
  const ACancelled: TFunc<Boolean>; out AOutput: string): Boolean;

/// <summary>The files of the index that differ from HEAD, relative to the root
/// of the working tree.</summary>
function GitStagedFiles(const ADir: string; const ACancelled: TFunc<Boolean>;
  out AFiles: TArray<string>; out AOutput: string): Boolean;

function GitCommitStaged(const ADir, AMessage: string; const ACancelled: TFunc<Boolean>;
  out AOutput: string): Boolean;

/// <summary>The local branches; ACurrent is '' on a detached HEAD.</summary>
function GitBranches(const ADir: string; const ACancelled: TFunc<Boolean>;
  out ABranches: TArray<string>; out ACurrent: string; out AOutput: string): Boolean;

/// <summary>Checks out a local branch. git refuses when that would overwrite
/// local changes.</summary>
function GitSwitchBranch(const ADir, ABranch: string; const ACancelled: TFunc<Boolean>;
  out AOutput: string): Boolean;

implementation

uses
  uGitRepo;

const
  // A Windows command line holds 32767 characters; the names get a part of it.
  cMaxNameChars = 8000;

function GitNameBatches(const ANames: TArray<string>; AMaxChars: Integer): TArray<TArray<string>>;
var
  Name: string;
  Batch: TArray<string>;
  Used: Integer;
begin
  Result := nil;
  Batch := nil;
  Used := 0;
  for Name in ANames do
  begin
    if (Batch <> nil) and (Used + Length(Name) > AMaxChars) then
    begin
      Result := Result + [Batch];
      Batch := nil;
      Used := 0;
    end;
    Batch := Batch + [Name];
    Inc(Used, Length(Name));
  end;
  if Batch <> nil then
    Result := Result + [Batch];
end;

function GitIn(const ADir: string; const AArgs: TArray<string>; const ACancelled: TFunc<Boolean>;
  out AOutput: string): Boolean;
var
  Args: TArray<string>;
  Code: Cardinal;
begin
  // quotepath=false: names outside ASCII come back as they are, not as octal.
  Args := ['-C', ADir, '--literal-pathspecs', '-c', 'core.quotepath=false'];
  Args := Args + AArgs;
  Result := RunGit(Args, ACancelled, AOutput, Code, 0) and (Code = 0);
end;

function GitOnNames(const ADir: string; const ACommand, ANames: TArray<string>;
  const ACancelled: TFunc<Boolean>; out AOutput: string): Boolean;
var
  Batch, Args: TArray<string>;
begin
  AOutput := '';
  Result := ANames <> nil;
  for Batch in GitNameBatches(ANames, cMaxNameChars) do
  begin
    Args := Copy(ACommand);
    Args := Args + ['--'] + Batch;
    if not GitIn(ADir, Args, ACancelled, AOutput) then
      Exit(False);
  end;
end;

function GitStagePaths(const ADir: string; const ANames: TArray<string>;
  const ACancelled: TFunc<Boolean>; out AOutput: string): Boolean;
begin
  Result := GitOnNames(ADir, ['add', '-A'], ANames, ACancelled, AOutput);
end;

function GitUnstagePaths(const ADir: string; const ANames: TArray<string>;
  const ACancelled: TFunc<Boolean>; out AOutput: string): Boolean;
begin
  // "reset" also works in a repository that has no commit yet.
  Result := GitOnNames(ADir, ['reset', '-q'], ANames, ACancelled, AOutput);
end;

function NonEmptyLines(const AText: string): TArray<string>;
var
  Line: string;
begin
  Result := nil;
  for Line in AText.Replace(#13, '').Split([#10]) do
    if Line <> '' then
      Result := Result + [Line];
end;

function GitStagedFiles(const ADir: string; const ACancelled: TFunc<Boolean>;
  out AFiles: TArray<string>; out AOutput: string): Boolean;
begin
  AFiles := nil;
  Result := GitIn(ADir, ['diff', '--cached', '--name-only'], ACancelled, AOutput);
  if Result then
    AFiles := NonEmptyLines(AOutput);
end;

function GitCommitStaged(const ADir, AMessage: string; const ACancelled: TFunc<Boolean>;
  out AOutput: string): Boolean;
begin
  Result := GitIn(ADir, ['commit', '-m', AMessage], ACancelled, AOutput);
end;

function GitBranches(const ADir: string; const ACancelled: TFunc<Boolean>;
  out ABranches: TArray<string>; out ACurrent: string; out AOutput: string): Boolean;
var
  Head: string;
begin
  ABranches := nil;
  ACurrent := '';
  Result := GitIn(ADir, ['for-each-ref', '--format=%(refname:lstrip=2)', 'refs/heads'],
    ACancelled, AOutput);
  if not Result then
    Exit;
  ABranches := NonEmptyLines(AOutput);
  // Exit code 1 here means a detached HEAD, which has no current branch.
  if GitIn(ADir, ['symbolic-ref', '--short', '-q', 'HEAD'], ACancelled, Head) then
    ACurrent := Head.Trim;
end;

function GitSwitchBranch(const ADir, ABranch: string; const ACancelled: TFunc<Boolean>;
  out AOutput: string): Boolean;
begin
  // The trailing "--" keeps a branch name from being read as a file name.
  Result := GitIn(ADir, ['checkout', ABranch, '--'], ACancelled, AOutput);
end;

end.
