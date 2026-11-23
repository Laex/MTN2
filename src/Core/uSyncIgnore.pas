unit uSyncIgnore;

{ Exclusion rules for the folder comparison of Directory Sync.
  The rules are gitignore patterns gathered from .gitignore-style files,
  a robocopy job file (/XD and /XF lists), the ignore filters of an Obsidian
  vault and a free-form list; junctions and symbolic links to folders can be
  skipped as well. A rule decides about one file or folder; a skipped folder
  is not entered, so nothing below it is listed. }

interface

type
  TSyncFilterOptions = record
    /// <summary>Folders that are junctions or symbolic links are not entered.</summary>
    SkipJunctions: Boolean;
    /// <summary>.gitignore, .geminiignore and .obsidianignore of every folder.</summary>
    UseIgnoreFiles: Boolean;
    /// <summary>exclude.rcj of the compared roots (robocopy /XD and /XF).</summary>
    UseRobocopyFile: Boolean;
    /// <summary>userIgnoreFilters of .obsidian/app.json in the compared roots.</summary>
    UseObsidian: Boolean;
    /// <summary>More gitignore patterns, separated by ";" or line breaks.</summary>
    Extra: string;
  end;

  ISyncFilter = interface
    ['{B1E4F5A2-6C3D-4E8B-9A17-5D2C0F7E3B64}']
    /// <summary>True when the entry is left out. ARel is relative to the
    /// compared root and uses the platform path delimiter.</summary>
    function Skip(const ARel: string; AIsDir, AIsLink: Boolean): Boolean;
    /// <summary>Called before a folder is scanned: its own ignore files
    /// start to apply to what is inside.</summary>
    procedure EnterDir(const ARel, ADir: string);
  end;

function DefaultSyncFilterOptions: TSyncFilterOptions;
function SyncFilterOptionsActive(const AOptions: TSyncFilterOptions): Boolean;
/// <summary>The filter for the options; ARoots are the compared folders (their
/// top-level rule files are read now).</summary>
function NewSyncFilter(const AOptions: TSyncFilterOptions;
  const ARoots: array of string): ISyncFilter;
/// <summary>Glob match on "/"-separated text: "*" and "?" stay inside one
/// name, "**" crosses folders, "[a-z]" is a character class. Case is ignored.</summary>
function SyncGlobMatch(const APattern, AText: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  System.Generics.Collections;

type
  TIgnoreRule = record
    /// <summary>Folder the rule file lives in, "a/b/" or empty for the root.</summary>
    Base: string;
    Pattern: string;
    Negate, DirOnly, FileOnly, Anchored: Boolean;
  end;

function DefaultSyncFilterOptions: TSyncFilterOptions;
begin
  Result := Default(TSyncFilterOptions);
  Result.SkipJunctions := True;
end;

function SyncFilterOptionsActive(const AOptions: TSyncFilterOptions): Boolean;
begin
  Result := AOptions.SkipJunctions or AOptions.UseIgnoreFiles or
    AOptions.UseRobocopyFile or AOptions.UseObsidian or
    (Trim(AOptions.Extra) <> '');
end;

function ClassMatch(const P: string; var PI: Integer; ACh: Char;
  out AMatched: Boolean): Boolean;
// P[PI] = '['. Returns False when the class is not closed (the bracket is a
// plain character); otherwise PI moves past the closing bracket.
var
  J: Integer;
  Neg, Hit: Boolean;
  Lo, Hi: Char;
begin
  Result := False;
  AMatched := False;
  J := PI + 1;
  Neg := (J <= Length(P)) and ((P[J] = '!') or (P[J] = '^'));
  if Neg then
    Inc(J);
  Hit := False;
  while (J <= Length(P)) and ((P[J] <> ']') or (J = PI + 1) or
    (Neg and (J = PI + 2))) do
  begin
    Lo := P[J];
    Hi := Lo;
    if (J + 2 <= Length(P)) and (P[J + 1] = '-') and (P[J + 2] <> ']') then
    begin
      Hi := P[J + 2];
      Inc(J, 2);
    end;
    if (ACh >= Lo) and (ACh <= Hi) then
      Hit := True;
    Inc(J);
  end;
  if J > Length(P) then
    Exit;
  PI := J + 1;
  AMatched := Hit <> Neg;
  Result := True;
end;

function MatchAt(const P, T: string; PI, TI: Integer): Boolean;
var
  K, J, Next: Integer;
  Hit: Boolean;
begin
  while PI <= Length(P) do
  begin
    case P[PI] of
      '*':
        begin
          if (PI < Length(P)) and (P[PI + 1] = '*') then
          begin
            K := PI + 2;
            if K > Length(P) then
              Exit(True);
            if (P[K] = '/') and ((PI = 1) or (P[PI - 1] = '/')) then
            begin
              // "**/": zero or more folders.
              Inc(K);
              J := TI;
              while True do
              begin
                if MatchAt(P, T, K, J) then
                  Exit(True);
                while (J <= Length(T)) and (T[J] <> '/') do
                  Inc(J);
                if J > Length(T) then
                  Exit(False);
                Inc(J);
              end;
            end;
            for J := TI to Length(T) + 1 do
              if MatchAt(P, T, K, J) then
                Exit(True);
            Exit(False);
          end;
          K := PI + 1;
          J := TI;
          while True do
          begin
            if MatchAt(P, T, K, J) then
              Exit(True);
            if (J > Length(T)) or (T[J] = '/') then
              Exit(False);
            Inc(J);
          end;
        end;
      '?':
        begin
          if (TI > Length(T)) or (T[TI] = '/') then
            Exit(False);
          Inc(PI);
          Inc(TI);
        end;
      '[':
        begin
          if TI > Length(T) then
            Exit(False);
          Next := PI;
          if ClassMatch(P, Next, T[TI], Hit) then
          begin
            if not Hit or (T[TI] = '/') then
              Exit(False);
            PI := Next;
            Inc(TI);
          end
          else
          begin
            if (TI > Length(T)) or (T[TI] <> '[') then
              Exit(False);
            Inc(PI);
            Inc(TI);
          end;
        end;
      '\':
        begin
          if PI < Length(P) then
            Inc(PI);
          if (TI > Length(T)) or (T[TI] <> P[PI]) then
            Exit(False);
          Inc(PI);
          Inc(TI);
        end;
    else
      if (TI > Length(T)) or (T[TI] <> P[PI]) then
        Exit(False);
      Inc(PI);
      Inc(TI);
    end;
  end;
  Result := TI > Length(T);
end;

function SyncGlobMatch(const APattern, AText: string): Boolean;
begin
  Result := MatchAt(LowerCase(APattern), LowerCase(AText), 1, 1);
end;

// One gitignore line; False for a blank line or a comment.
function ParseIgnoreLine(const ALine, ABase: string;
  out ARule: TIgnoreRule): Boolean;
var
  S: string;
begin
  ARule := Default(TIgnoreRule);
  ARule.Base := ABase;
  S := TrimRight(ALine);
  if (S = '') or (S[1] = '#') then
    Exit(False);
  if S[1] = '!' then
  begin
    ARule.Negate := True;
    Delete(S, 1, 1);
  end
  else if (Length(S) > 1) and (S[1] = '\') and ((S[2] = '#') or (S[2] = '!')) then
    Delete(S, 1, 1);
  if (S <> '') and (S[Length(S)] = '/') then
  begin
    ARule.DirOnly := True;
    Delete(S, Length(S), 1);
  end;
  if (S <> '') and (S[1] = '/') then
  begin
    ARule.Anchored := True;
    Delete(S, 1, 1);
  end
  else if Pos('/', S) > 0 then
    ARule.Anchored := True;
  ARule.Pattern := S;
  Result := S <> '';
end;

procedure AddRule(var ARules: TArray<TIgnoreRule>; const ARule: TIgnoreRule);
begin
  SetLength(ARules, Length(ARules) + 1);
  ARules[High(ARules)] := ARule;
end;

procedure AddIgnoreText(var ARules: TArray<TIgnoreRule>; const AText,
  ABase: string);
var
  Lines: TStringList;
  I: Integer;
  Rule: TIgnoreRule;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    for I := 0 to Lines.Count - 1 do
      if ParseIgnoreLine(Lines[I], ABase, Rule) then
        AddRule(ARules, Rule);
  finally
    Lines.Free;
  end;
end;

function ReadTextOrEmpty(const AFile: string): string;
begin
  Result := '';
  if not TFile.Exists(AFile) then
    Exit;
  try
    Result := TFile.ReadAllText(AFile, TEncoding.UTF8);
  except
    Result := '';
  end;
end;

function ToSlashes(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

// The path of an /XD or /XF entry relative to one of the roots, "" when it is
// outside all of them.
function RootRelative(const AEntry: string; const ARoots: array of string): string;
var
  I: Integer;
  Root, Full: string;
begin
  Result := '';
  Full := ToSlashes(AEntry);
  for I := 0 to High(ARoots) do
  begin
    Root := ToSlashes(ExcludeTrailingPathDelimiter(ARoots[I])) + '/';
    if (Length(Full) > Length(Root)) and SameText(Copy(Full, 1, Length(Root)), Root) then
      Exit(Copy(Full, Length(Root) + 1, MaxInt));
  end;
end;

function SplitJobTokens(const AText: string): TArray<string>;
var
  Lines: TStringList;
  Line, Tok: string;
  I, L: Integer;
  Quoted: Boolean;
  Res: TList<string>;
begin
  Res := TList<string>.Create;
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    for L := 0 to Lines.Count - 1 do
    begin
      Line := Lines[L];
      if Copy(TrimLeft(Line), 1, 2) = '::' then
        Continue;
      Tok := '';
      Quoted := False;
      for I := 1 to Length(Line) do
        if Line[I] = '"' then
          Quoted := not Quoted
        else if (not Quoted) and ((Line[I] = ' ') or (Line[I] = #9)) then
        begin
          if Tok <> '' then
            Res.Add(Tok);
          Tok := '';
        end
        else
          Tok := Tok + Line[I];
      if Tok <> '' then
        Res.Add(Tok);
    end;
    Result := Res.ToArray;
  finally
    Lines.Free;
    Res.Free;
  end;
end;

// Robocopy job file: the names after /XD are folders, after /XF files; a name
// is matched at any depth, a full path only where it lies under a root.
procedure AddRobocopyText(var ARules: TArray<TIgnoreRule>; const AText: string;
  const ARoots: array of string);
var
  Tokens: TArray<string>;
  Tok, Rel: string;
  Mode: Char;
  Rule: TIgnoreRule;
begin
  Mode := #0;
  Tokens := SplitJobTokens(AText);
  for Tok in Tokens do
  begin
    // A switch has no further slash; a POSIX full path starts with one.
    if (Tok <> '') and (Tok[1] = '/') and (Pos('/', Copy(Tok, 2, MaxInt)) = 0) then
    begin
      if SameText(Tok, '/XD') then
        Mode := 'D'
      else if SameText(Tok, '/XF') then
        Mode := 'F'
      else
        Mode := #0;
      Continue;
    end;
    if Mode = #0 then
      Continue;
    Rule := Default(TIgnoreRule);
    Rule.DirOnly := Mode = 'D';
    Rule.FileOnly := Mode = 'F';
    if (Pos('\', Tok) > 0) or (Pos(':', Tok) > 0) or (Pos('/', Tok) > 0) then
    begin
      Rel := RootRelative(Tok, ARoots);
      if Rel = '' then
        Continue;
      Rule.Pattern := Rel;
      Rule.Anchored := True;
    end
    else
      Rule.Pattern := Tok;
    AddRule(ARules, Rule);
  end;
end;

procedure AddObsidianText(var ARules: TArray<TIgnoreRule>; const AJson: string);
var
  Root, Arr: TJSONValue;
  Item: TJSONValue;
  Rule: TIgnoreRule;
begin
  if AJson = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(AJson);
  if Root = nil then
    Exit;
  try
    Arr := Root.FindValue('userIgnoreFilters');
    if Arr is TJSONArray then
      for Item in TJSONArray(Arr) do
        if (Item is TJSONString) and
           ParseIgnoreLine(TJSONString(Item).Value, '', Rule) then
          AddRule(ARules, Rule);
  finally
    Root.Free;
  end;
end;

type
  TSyncFilter = class(TInterfacedObject, ISyncFilter)
  private
    FOptions: TSyncFilterOptions;
    FRules: TArray<TIgnoreRule>;
    FSeenDirs: TDictionary<string, Boolean>;
    procedure LoadIgnoreFiles(const ADir, ABase: string);
  public
    constructor Create(const AOptions: TSyncFilterOptions;
      const ARoots: array of string);
    destructor Destroy; override;
    function Skip(const ARel: string; AIsDir, AIsLink: Boolean): Boolean;
    procedure EnterDir(const ARel, ADir: string);
  end;

const
  cIgnoreFileNames: array[0..2] of string =
    ('.gitignore', '.geminiignore', '.obsidianignore');

constructor TSyncFilter.Create(const AOptions: TSyncFilterOptions;
  const ARoots: array of string);
var
  I: Integer;
  Part: string;
begin
  inherited Create;
  FOptions := AOptions;
  FSeenDirs := TDictionary<string, Boolean>.Create;
  SetLength(FRules, 0);
  for Part in AOptions.Extra.Replace(sLineBreak, ';').Split([';']) do
    AddIgnoreText(FRules, Trim(Part), '');
  for I := 0 to High(ARoots) do
  begin
    if ARoots[I] = '' then
      Continue;
    if AOptions.UseIgnoreFiles then
      LoadIgnoreFiles(ARoots[I], '');
    if AOptions.UseRobocopyFile then
      AddRobocopyText(FRules, ReadTextOrEmpty(TPath.Combine(ARoots[I],
        'exclude.rcj')), ARoots);
    if AOptions.UseObsidian then
      AddObsidianText(FRules, ReadTextOrEmpty(TPath.Combine(
        TPath.Combine(ARoots[I], '.obsidian'), 'app.json')));
  end;
end;

destructor TSyncFilter.Destroy;
begin
  FSeenDirs.Free;
  inherited;
end;

procedure TSyncFilter.LoadIgnoreFiles(const ADir, ABase: string);
var
  Key, Name: string;
begin
  Key := LowerCase(ExcludeTrailingPathDelimiter(ADir));
  if FSeenDirs.ContainsKey(Key) then
    Exit;
  FSeenDirs.Add(Key, True);
  for Name in cIgnoreFileNames do
    AddIgnoreText(FRules, ReadTextOrEmpty(TPath.Combine(ADir, Name)), ABase);
end;

procedure TSyncFilter.EnterDir(const ARel, ADir: string);
begin
  if FOptions.UseIgnoreFiles and (ARel <> '') then
    LoadIgnoreFiles(ADir, ToSlashes(ARel) + '/');
end;

function TSyncFilter.Skip(const ARel: string; AIsDir, AIsLink: Boolean): Boolean;
var
  Rel, Sub: string;
  I: Integer;
  R: TIgnoreRule;
begin
  if AIsDir and AIsLink and FOptions.SkipJunctions then
    Exit(True);
  Result := False;
  Rel := ToSlashes(ARel);
  for I := 0 to High(FRules) do
  begin
    R := FRules[I];
    if (R.DirOnly and not AIsDir) or (R.FileOnly and AIsDir) then
      Continue;
    if R.Base <> '' then
    begin
      if not SameText(Copy(Rel, 1, Length(R.Base)), R.Base) then
        Continue;
      Sub := Copy(Rel, Length(R.Base) + 1, MaxInt);
    end
    else
      Sub := Rel;
    if R.Anchored then
    begin
      if SyncGlobMatch(R.Pattern, Sub) then
        Result := not R.Negate;
    end
    else if SyncGlobMatch(R.Pattern, Copy(Sub, LastDelimiter('/', Sub) + 1, MaxInt)) then
      Result := not R.Negate;
  end;
end;

function NewSyncFilter(const AOptions: TSyncFilterOptions;
  const ARoots: array of string): ISyncFilter;
begin
  Result := TSyncFilter.Create(AOptions, ARoots);
end;

end.
