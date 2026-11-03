unit uGitDiff;

{ "git diff" of the row under the cursor of the active panel: finds the row in the
  host's panel JSON, asks git for the change against HEAD (against the index in a
  repository without commits) and writes it to a temp file the built-in viewer
  can open. }

interface

uses
  System.SysUtils;

type
  /// <summary>gdNoChanges also stands for "nothing to show": a file git does not
  /// track has no blame.</summary>
  TGitDiffResult = (gdOk, gdNoChanges, gdNotRepo, gdError);

/// <summary>The row under the cursor of the active panel in the JSON of the host's
/// PanelInfo; False when the cursor is on no row (an empty panel, the ".." row).</summary>
function ActivePanelCursor(const APanelInfoJson: string; out AUri: string;
  out AIsDir: Boolean): Boolean;

/// <summary>The change of APath (a file or, with AIsDir, a folder) against HEAD.</summary>
function ReadGitDiff(const APath: string; AIsDir: Boolean; const ACancelled: TFunc<Boolean>;
  out AText: string): TGitDiffResult;

/// <summary>Writes the diff text to a file named after AName in the temp folder and
/// returns its path.</summary>
function WriteDiffFile(const AName, AText: string): string;

/// <summary>The commit, author and date of every line of the file APath
/// (git blame); gdNoChanges when git does not track the file.</summary>
function ReadGitBlame(const APath: string; const ACancelled: TFunc<Boolean>;
  out AText: string): TGitDiffResult;

/// <summary>Writes the blame text to AName + ".blame" in the temp folder and
/// returns its path.</summary>
function WriteBlameFile(const AName, AText: string): string;

implementation

uses
  System.IOUtils, System.JSON, uGitRepo;

function ActivePanelCursor(const APanelInfoJson: string; out AUri: string;
  out AIsDir: Boolean): Boolean;
var
  Root, Side: TJSONValue;
  Active: string;
begin
  AUri := '';
  AIsDir := False;
  if APanelInfoJson = '' then
    Exit(False);
  Root := TJSONObject.ParseJSONValue(APanelInfoJson);
  try
    if not (Root is TJSONObject) or not Root.TryGetValue<string>('active', Active) then
      Exit(False);
    Side := Root.GetValue<TJSONValue>(Active, nil);
    if not (Side is TJSONObject) or not Side.TryGetValue<string>('cursor', AUri) then
      Exit(False);
    Side.TryGetValue<Boolean>('cursorIsDirectory', AIsDir);
    Result := AUri <> '';
  finally
    Root.Free;
  end;
end;

function ReadGitDiff(const APath: string; AIsDir: Boolean; const ACancelled: TFunc<Boolean>;
  out AText: string): TGitDiffResult;
var
  Dir, Spec: string;
  Code: Cardinal;
begin
  AText := '';
  if AIsDir then
  begin
    Dir := ExcludeTrailingPathDelimiter(APath);
    Spec := '.';
  end
  else
  begin
    Dir := ExtractFileDir(APath);
    Spec := ExtractFileName(APath);
  end;
  if not IsInsideGitWorkTree(Dir) then
    Exit(gdNotRepo);
  if not RunGit(['-C', Dir, '--no-optional-locks', 'diff', 'HEAD', '--no-color',
       '--no-ext-diff', '--', Spec], ACancelled, AText, Code) then
    Exit(gdError);
  if Code <> 0 then
  begin
    // No commit yet: HEAD does not exist, the index is the base.
    if not RunGit(['-C', Dir, '--no-optional-locks', 'diff', '--no-color',
         '--no-ext-diff', '--', Spec], ACancelled, AText, Code) then
      Exit(gdError);
    if Code <> 0 then
      Exit(gdError);
  end;
  if Trim(AText) = '' then
    Exit(gdNoChanges);
  Result := gdOk;
end;

function WriteTempText(const AFolder, AName, AExt, AText: string): string;
var
  Dir: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, AFolder);
  TDirectory.CreateDirectory(Dir);
  Result := TPath.Combine(Dir, TPath.GetFileName(AName) + AExt);
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

function WriteDiffFile(const AName, AText: string): string;
begin
  Result := WriteTempText('mtn2-git-diff', AName, '.diff', AText);
end;

function ReadGitBlame(const APath: string; const ACancelled: TFunc<Boolean>;
  out AText: string): TGitDiffResult;
var
  Dir, Output: string;
  Code: Cardinal;
begin
  AText := '';
  Dir := ExtractFileDir(APath);
  if not IsInsideGitWorkTree(Dir) then
    Exit(gdNotRepo);
  // Untracked files have no history: "git ls-files --error-unmatch" tells them
  // apart from a real failure of blame.
  if not RunGit(['-C', Dir, '--no-optional-locks', 'ls-files', '--error-unmatch', '--',
       ExtractFileName(APath)], ACancelled, Output, Code) then
    Exit(gdError);
  if Code <> 0 then
    Exit(gdNoChanges);
  if not RunGit(['-C', Dir, '--no-optional-locks', 'blame', '--date=short', '--',
       ExtractFileName(APath)], ACancelled, AText, Code) then
    Exit(gdError);
  if Code <> 0 then
    Exit(gdNoChanges);
  if Trim(AText) = '' then
    Exit(gdNoChanges);
  Result := gdOk;
end;

function WriteBlameFile(const AName, AText: string): string;
begin
  Result := WriteTempText('mtn2-git-blame', AName, '.blame', AText);
end;

end.
