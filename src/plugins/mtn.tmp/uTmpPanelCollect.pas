unit uTmpPanelCollect;

{ Pure helpers of the Temporary panel plugin: turning the text a command
  printed into file paths, and finding groups of files with identical content.
  No host calls, so both run in a worker thread and are covered by tests. }

interface

uses
  System.SysUtils, System.Classes;

type
  TCancelCheck = reference to function: Boolean;

  /// <summary>How far a duplicate search has got. Scanning: Scanned files seen so far,
  /// Dir is the folder being read. Comparing: Candidates files share a size with
  /// another one, Checked of them are read, FoundFiles lie in groups found so far.</summary>
  TDupProgress = record
    Comparing: Boolean;
    Dir: string;
    Scanned: Integer;
    Candidates: Integer;
    Checked: Integer;
    FoundFiles: Integer;
  end;
  TDupProgressCallback = reference to procedure(const AProgress: TDupProgress);

/// <summary>The existing file or folder a line of command output names, as a full
/// path; '' when the line names nothing that exists. A relative path is taken from
/// ABaseDir, "file:" URIs and forward slashes are accepted, and a trailing
/// ":line:text" (grep -n, rg -n) is cut off when the whole line is not a path.</summary>
function ResolvePanelizedPath(const ALine, ABaseDir: string): string;

/// <summary>The distinct existing paths named by the lines of AOutput, in output order.</summary>
function ParsePanelizeOutput(const AOutput, ABaseDir: string): TArray<string>;

/// <summary>Files under ARoot with the same size and the same SHA-256, grouped
/// (groups of two or more files; biggest files first, paths sorted inside a group).
/// Empty files and files smaller than AMinSize are ignored, as are symbolic links
/// and junctions. A file that cannot be read is skipped. ACancelled and AProgress
/// may be nil; AProgress is called often, on the calling thread.</summary>
function FindDuplicateGroups(const ARoot: string; AMinSize: Int64;
  const ACancelled: TCancelCheck;
  const AProgress: TDupProgressCallback = nil): TArray<TArray<string>>;

implementation

uses
  System.IOUtils, System.Hash, System.Math, System.Generics.Collections, System.Generics.Defaults,
  uVfsTypes;

const
  cHeadBytes = 64 * 1024;

function ResolvePanelizedPath(const ALine, ABaseDir: string): string;
var
  S, Candidate: string;
  P: Integer;

  function Exists(const APath: string; out AFull: string): Boolean;
  begin
    AFull := '';
    if APath = '' then
      Exit(False);
    try
      if TPath.IsPathRooted(APath) or (ABaseDir = '') then
        AFull := ExpandFileName(APath)
      else
        AFull := ExpandFileName(TPath.Combine(ABaseDir, APath));
    except
      Exit(False);
    end;
    Result := FileExists(AFull) or TDirectory.Exists(AFull);
  end;

begin
  Result := '';
  S := Trim(ALine);
  if (Length(S) >= 2) and (S[1] = '"') and (S[Length(S)] = '"') then
    S := Copy(S, 2, Length(S) - 2);
  if S = '' then
    Exit;
  if SameText(Copy(S, 1, 5), 'file:') then
  begin
    S := FileUriToPath(S);
    if S = '' then
      Exit;
  end;
{$IFDEF MSWINDOWS}
  S := StringReplace(S, '/', PathDelim, [rfReplaceAll]);
{$ENDIF}
  if Exists(S, Candidate) then
    Exit(ExcludeTrailingPathDelimiter(Candidate));
  // "path:12:text": try each prefix that ends before a colon (a drive colon at
  // position 2 is part of the path).
  for P := 3 to Length(S) do
    if S[P] = ':' then
      if Exists(Copy(S, 1, P - 1), Candidate) then
        Exit(ExcludeTrailingPathDelimiter(Candidate));
end;

function ParsePanelizeOutput(const AOutput, ABaseDir: string): TArray<string>;
var
  Lines: TStringList;
  Seen: TDictionary<string, Boolean>;
  List: TList<string>;
  I: Integer;
  Path, Key: string;
begin
  Lines := TStringList.Create;
  Seen := TDictionary<string, Boolean>.Create;
  List := TList<string>.Create;
  try
    Lines.Text := AOutput;
    for I := 0 to Lines.Count - 1 do
    begin
      Path := ResolvePanelizedPath(Lines[I], ABaseDir);
      if Path = '' then
        Continue;
      Key := LowerCase(Path);
      if Seen.ContainsKey(Key) then
        Continue;
      Seen.Add(Key, True);
      List.Add(Path);
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Seen.Free;
    Lines.Free;
  end;
end;

function IsLinkOrJunction(const APath: string): Boolean;
var
  Attr: Integer;
begin
  Attr := FileGetAttr(APath);
  Result := (Attr <> -1) and ((Attr and faSymLink) <> 0);
end;

type
  TSearchState = class
    Progress: TDupProgress;
    Callback: TDupProgressCallback;
    procedure Report;
  end;

procedure TSearchState.Report;
begin
  if Assigned(Callback) then
    Callback(Progress);
end;

procedure Walk(const ADir: string; AMinSize: Int64; const ACancelled: TCancelCheck;
  ABySize: TDictionary<Int64, TList<string>>; AState: TSearchState);
var
  Files, Dirs: TArray<string>;
  F, D: string;
  Size: Int64;
  Bucket: TList<string>;
begin
  if Assigned(ACancelled) and ACancelled() then
    Exit;
  AState.Progress.Dir := ADir;
  AState.Report;
  try
    Files := TDirectory.GetFiles(ADir);
  except
    SetLength(Files, 0);
  end;
  for F in Files do
  begin
    if IsLinkOrJunction(F) then
      Continue;
    Inc(AState.Progress.Scanned);
    try
      Size := TFile.GetSize(F);
    except
      Continue;
    end;
    if (Size <= 0) or (Size < AMinSize) then
      Continue;
    if not ABySize.TryGetValue(Size, Bucket) then
    begin
      Bucket := TList<string>.Create;
      ABySize.Add(Size, Bucket);
    end;
    Bucket.Add(F);
  end;
  AState.Report;
  try
    Dirs := TDirectory.GetDirectories(ADir);
  except
    SetLength(Dirs, 0);
  end;
  for D in Dirs do
    if not IsLinkOrJunction(D) then
      Walk(D, AMinSize, ACancelled, ABySize, AState);
end;

// SHA-256 of the first AMaxBytes bytes of AFile (all of it when AMaxBytes <= 0);
// '' when the file cannot be read.
function HashFile(const AFile: string; AMaxBytes: Int64;
  const ACancelled: TCancelCheck): string;
var
  Stream: TFileStream;
  Hash: THashSHA2;
  Buf: TBytes;
  Left: Int64;
  N: Integer;
begin
  Result := '';
  try
    Stream := TFileStream.Create(AFile, fmOpenRead or fmShareDenyNone);
    try
      Hash := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
      SetLength(Buf, 256 * 1024);
      if AMaxBytes > 0 then
        Left := AMaxBytes
      else
        Left := Stream.Size;
      while Left > 0 do
      begin
        if Assigned(ACancelled) and ACancelled() then
          Exit('');
        N := Stream.Read(Buf[0], Integer(Min(Left, Length(Buf))));
        if N <= 0 then
          Break;
        Hash.Update(Buf, N);
        Dec(Left, N);
      end;
      Result := Hash.HashAsString;
    finally
      Stream.Free;
    end;
  except
    Result := '';
  end;
end;

// Splits AFiles into the groups whose hash (of the first AMaxBytes bytes) agrees;
// groups of one are dropped.
procedure SplitByHash(const AFiles: TArray<string>; AMaxBytes: Int64;
  const ACancelled: TCancelCheck; AOut: TList<TArray<string>>; AState: TSearchState;
  ACountsAsChecked: Boolean);
var
  Groups: TObjectDictionary<string, TList<string>>;
  F, H: string;
  Bucket: TList<string>;
  Pair: TPair<string, TList<string>>;
begin
  Groups := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  try
    for F in AFiles do
    begin
      AState.Progress.Dir := ExtractFilePath(F);
      AState.Report;
      H := HashFile(F, AMaxBytes, ACancelled);
      if ACountsAsChecked then
      begin
        Inc(AState.Progress.Checked);
        AState.Report;
      end;
      if H = '' then
        Continue;
      if not Groups.TryGetValue(H, Bucket) then
      begin
        Bucket := TList<string>.Create;
        Groups.Add(H, Bucket);
      end;
      Bucket.Add(F);
    end;
    for Pair in Groups do
      if Pair.Value.Count >= 2 then
      begin
        AOut.Add(Pair.Value.ToArray);
        if ACountsAsChecked then
          Inc(AState.Progress.FoundFiles, Pair.Value.Count);
      end;
    if ACountsAsChecked then
      AState.Report;
  finally
    Groups.Free;
  end;
end;

function FindDuplicateGroups(const ARoot: string; AMinSize: Int64;
  const ACancelled: TCancelCheck;
  const AProgress: TDupProgressCallback): TArray<TArray<string>>;
var
  State: TSearchState;
  BySize: TObjectDictionary<Int64, TList<string>>;
  Sizes: TList<Int64>;
  Heads: TList<TArray<string>>;
  Pair: TPair<Int64, TList<string>>;
  Size: Int64;
  G: TArray<string>;
  I: Integer;
  Found: TList<TArray<string>>;
begin
  BySize := TObjectDictionary<Int64, TList<string>>.Create([doOwnsValues]);
  Sizes := TList<Int64>.Create;
  Found := TList<TArray<string>>.Create;
  State := TSearchState.Create;
  State.Callback := AProgress;
  try
    Walk(ARoot, AMinSize, ACancelled, BySize, State);
    for Pair in BySize do
      if Pair.Value.Count >= 2 then
      begin
        Sizes.Add(Pair.Key);
        Inc(State.Progress.Candidates, Pair.Value.Count);
      end;
    State.Progress.Comparing := True;
    State.Report;
    Sizes.Sort(TComparer<Int64>.Construct(
      function(const A, B: Int64): Integer
      begin
        if A > B then
          Result := -1
        else if A < B then
          Result := 1
        else
          Result := 0;
      end));
    for Size in Sizes do
    begin
      if Assigned(ACancelled) and ACancelled() then
        Break;
      Heads := TList<TArray<string>>.Create;
      try
        // Same size: compare the first 64 KB first, read whole files only when
        // those agree and the file is longer than that.
        if Size <= cHeadBytes then
          SplitByHash(BySize[Size].ToArray, 0, ACancelled, Found, State, True)
        else
        begin
          SplitByHash(BySize[Size].ToArray, cHeadBytes, ACancelled, Heads, State, False);
          // Files whose head is unique are done; the rest are read whole.
          Inc(State.Progress.Checked, Length(BySize[Size].ToArray));
          for G in Heads do
            Dec(State.Progress.Checked, Length(G));
          for G in Heads do
            SplitByHash(G, 0, ACancelled, Found, State, True);
        end;
      finally
        Heads.Free;
      end;
    end;
    SetLength(Result, Found.Count);
    for I := 0 to Found.Count - 1 do
    begin
      G := Found[I];
      TArray.Sort<string>(G, TComparer<string>.Construct(
        function(const A, B: string): Integer
        begin
          Result := CompareText(A, B);
        end));
      Result[I] := G;
    end;
  finally
    State.Free;
    Found.Free;
    Sizes.Free;
    BySize.Free;
  end;
end;

end.
