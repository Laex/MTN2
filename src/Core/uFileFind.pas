unit uFileFind;

{ Async file-name / content search (Stage 11). Walks the local filesystem off
  the UI thread and reports progress / results via TThread.Queue. }

interface

uses
  System.SysUtils, System.Classes,
  uVfsTypes;

const
  cFindMaxResults = 5000;
  cFindMaxContentBytes = 4 * 1024 * 1024;

type
  TFindOptions = record
    RootPath: string;
    Mask: string;              // one or several masks: *.pas;*.dfm
    ContainingText: string;    // empty = name/mask only
    Subdirs: Boolean;
    CaseSensitive: Boolean;
    WholeWords: Boolean;
    SearchFolders: Boolean;    // include matching directories in results
    UseRegex: Boolean;         // ContainingText is a regex pattern, not plain text
  end;

  /// <summary>One search hit. Line/Snippet are 0/'' unless ContainingText was
  /// set — then they point at the first matching line (1-based).</summary>
  TFindHit = record
    Path: string;
    Line: Integer;
    Snippet: string;
  end;

  TFindProgressCallback = reference to procedure(AFoundCount: Integer;
    const ACurrentDir: string);
  TFindDoneCallback = reference to procedure(const AHits: TArray<TFindHit>;
    const AError: TVfsError);

function DefaultFindOptions(const ARootPath, AMask: string;
  ASubdirs: Boolean = True): TFindOptions;

/// <summary>Split `*.pas;*.dfm` / comma-separated masks (empty → `*.*`).</summary>
function SplitMasks(const AMask: string): TArray<string>;
/// <summary>True if AName matches any mask from SplitMasks / System.Masks.</summary>
function NameMatchesAnyMask(const AName: string;
  const AMasks: TArray<string>): Boolean;
/// <summary>Compiles APattern as a regex just to check it's well-formed;
/// AError carries the exception message on failure. Call before starting an
/// AUseRegex search so a bad pattern is reported instantly instead of
/// failing file-by-file mid-walk.</summary>
function ValidateRegexPattern(const APattern: string; out AError: string): Boolean;

procedure FindFilesAsync(const AOptions: TFindOptions; ACancel: IJobCancelToken;
  AOnProgress: TFindProgressCallback; AOnDone: TFindDoneCallback);

implementation

uses
  System.IOUtils, System.Masks, System.Generics.Collections,
  System.RegularExpressions;

function DefaultFindOptions(const ARootPath, AMask: string;
  ASubdirs: Boolean): TFindOptions;
begin
  Result.RootPath := ARootPath;
  Result.Mask := AMask;
  Result.ContainingText := '';
  Result.Subdirs := ASubdirs;
  Result.CaseSensitive := False;
  Result.WholeWords := False;
  Result.SearchFolders := False;
  Result.UseRegex := False;
end;

function SplitMasks(const AMask: string): TArray<string>;
var
  S, Part: string;
  I, Start, N: Integer;
begin
  S := Trim(AMask);
  if S = '' then
    S := '*.*';
  SetLength(Result, 0);
  Start := 1;
  N := 0;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = ';') or (S[I] = ',') then
    begin
      Part := Trim(Copy(S, Start, I - Start));
      if Part <> '' then
      begin
        Inc(N);
        SetLength(Result, N);
        Result[N - 1] := Part;
      end;
      Start := I + 1;
    end;
  if Length(Result) = 0 then
  begin
    SetLength(Result, 1);
    Result[0] := '*.*';
  end;
end;

function NameMatchesAnyMask(const AName: string;
  const AMasks: TArray<string>): Boolean;
var
  M: string;
begin
  for M in AMasks do
  begin
    // FAR / Win32: * and *.* match every name, including names without a dot.
    // System.Masks treats '.' as literal, so bare MatchesMask(Name, '*.*') would
    // skip extensionless files like hash-{GUID} temp names.
    if SameText(M, '*') or SameText(M, '*.*') then
      Exit(True);
    if MatchesMask(AName, M) then
      Exit(True);
  end;
  Result := False;
end;

function IsWordChar(C: Char): Boolean;
begin
  Result := ((C >= '0') and (C <= '9')) or
    ((C >= 'A') and (C <= 'Z')) or
    ((C >= 'a') and (C <= 'z')) or
    (C = '_') or (Ord(C) > 127);
end;

function TextContainsAbs(const AHaystack, ANeedle: string; ACaseSensitive,
  AWholeWords: Boolean): Boolean;
var
  H, N: string;
  I, L: Integer;
  BeforeOk, AfterOk: Boolean;
begin
  if ANeedle = '' then
    Exit(True);
  if ACaseSensitive then
  begin
    H := AHaystack;
    N := ANeedle;
  end
  else
  begin
    H := AnsiLowerCase(AHaystack);
    N := AnsiLowerCase(ANeedle);
  end;
  L := Length(N);
  if L = 0 then
    Exit(True);
  if not AWholeWords then
    Exit(Pos(N, H) > 0);
  I := 1;
  while I <= Length(H) - L + 1 do
  begin
    if Copy(H, I, L) = N then
    begin
      BeforeOk := (I = 1) or not IsWordChar(H[I - 1]);
      AfterOk := (I + L > Length(H)) or not IsWordChar(H[I + L]);
      if BeforeOk and AfterOk then
        Exit(True);
    end;
    Inc(I);
  end;
  Result := False;
end;

function ValidateRegexPattern(const APattern: string; out AError: string): Boolean;
var
  Re: TRegEx;
begin
  AError := '';
  try
    // TRegEx.Create alone does not compile the pattern — it stays lazy until
    // the first IsMatch/Match call, so a malformed pattern only raises there.
    // Force that now so a bad pattern is caught here, not mid-walk.
    Re := TRegEx.Create(APattern);
    Re.IsMatch('');
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

const
  cFindSnippetMaxLen = 200;

function TrimSnippet(const ALine: string): string;
begin
  Result := Trim(ALine);
  if Length(Result) > cFindSnippetMaxLen then
    Result := Copy(Result, 1, cFindSnippetMaxLen) + #$2026;
end;

/// <summary>Reads APath (size-capped like the old FileContainsText) and scans
/// it line by line for ANeedle — plain substring/whole-word, or (AUseRegex)
/// a compiled regex. Returns the first matching line (1-based) and a
/// trimmed copy of it. A malformed regex is caught per-file (defensive:
/// callers should already have validated the pattern once via
/// ValidateRegexPattern before starting the walk) and just means no match,
/// not a crashed job.</summary>
function FileContentMatch(const APath, ANeedle: string; ACaseSensitive,
  AWholeWords, AUseRegex: Boolean; out ALine: Integer; out ASnippet: string): Boolean;
var
  Bytes: TBytes;
  Text: string;
  FS: TFileStream;
  Lines: TArray<string>;
  Opts: TRegExOptions;
  I: Integer;
begin
  ALine := 0;
  ASnippet := '';
  if ANeedle = '' then
    Exit(True);
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if (FS.Size <= 0) or (FS.Size > cFindMaxContentBytes) then
        Exit(False);
      SetLength(Bytes, FS.Size);
      FS.ReadBuffer(Bytes[0], FS.Size);
    finally
      FS.Free;
    end;
    try
      Text := TEncoding.UTF8.GetString(Bytes);
    except
      Text := TEncoding.Default.GetString(Bytes);
    end;
    Lines := Text.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
    if AUseRegex then
    begin
      Opts := [roNotEmpty];
      if not ACaseSensitive then
        Opts := Opts + [roIgnoreCase];
      for I := 0 to High(Lines) do
        try
          if TRegEx.IsMatch(Lines[I], ANeedle, Opts) then
          begin
            ALine := I + 1;
            ASnippet := TrimSnippet(Lines[I]);
            Exit(True);
          end;
        except
          // Malformed pattern reaching here despite upfront validation —
          // treat as no match on this line rather than aborting the job.
        end;
    end
    else
      for I := 0 to High(Lines) do
        if TextContainsAbs(Lines[I], ANeedle, ACaseSensitive, AWholeWords) then
        begin
          ALine := I + 1;
          ASnippet := TrimSnippet(Lines[I]);
          Exit(True);
        end;
    Result := False;
  except
    Result := False;
  end;
end;

procedure FindFilesAsync(const AOptions: TFindOptions; ACancel: IJobCancelToken;
  AOnProgress: TFindProgressCallback; AOnDone: TFindDoneCallback);
var
  Opts: TFindOptions;
  Cancel: IJobCancelToken;
  OnProgress: TFindProgressCallback;
  OnDone: TFindDoneCallback;
  Masks: TArray<string>;
begin
  Opts := AOptions;
  Opts.RootPath := ExcludeTrailingPathDelimiter(Trim(Opts.RootPath));
  if (Length(Opts.RootPath) = 2) and (Opts.RootPath[2] = ':') then
    Opts.RootPath := Opts.RootPath + PathDelim;
  if Trim(Opts.Mask) = '' then
    Opts.Mask := '*.*';
  Masks := SplitMasks(Opts.Mask);
  Cancel := ACancel;
  OnProgress := AOnProgress;
  OnDone := AOnDone;

  TThread.CreateAnonymousThread(
    procedure
    var
      List: TList<TFindHit>;
      Err: TVfsError;
      LastProgressTick: Cardinal;
      Hits: TArray<TFindHit>;
      Stack: TStack<string>;
      Dir, Full, Name: string;
      SR: TSearchRec;
      Code: Integer;
      IsDir: Boolean;
      Needle: string;
      Hit: TFindHit;
      HitLine: Integer;
      HitSnippet: string;

      procedure EmitProgress(ACount: Integer; const ADir: string);
      var
        CapCount: Integer;
        CapDir: string;
      begin
        if not Assigned(OnProgress) then
          Exit;
        CapCount := ACount;
        CapDir := ADir;
        TThread.Queue(nil,
          procedure
          begin
            if Assigned(OnProgress) then
              OnProgress(CapCount, CapDir);
          end);
      end;

      function ContentMatch(const AFilePath: string; out ALine: Integer;
        out ASnippet: string): Boolean;
      begin
        if Needle = '' then
        begin
          ALine := 0;
          ASnippet := '';
          Exit(True);
        end;
        Result := FileContentMatch(AFilePath, Needle, Opts.CaseSensitive,
          Opts.WholeWords, Opts.UseRegex, ALine, ASnippet);
      end;

    begin
      Err := TVfsError.Ok;
      List := TList<TFindHit>.Create;
      Stack := TStack<string>.Create;
      LastProgressTick := 0;
      Needle := Opts.ContainingText;
      try
        try
          if JobCancelRequested(Cancel) then
            Err := TVfsError.Make(vecCancelled, 'Cancelled', Opts.RootPath)
          else if not TDirectory.Exists(Opts.RootPath) then
            Err := TVfsError.Make(vecNotFound, 'Path not found', Opts.RootPath)
          else
          begin
            Stack.Push(Opts.RootPath);
            while (Stack.Count > 0) and not JobCancelRequested(Cancel) and
              (List.Count < cFindMaxResults) do
            begin
              Dir := Stack.Pop;
              if (LastProgressTick = 0) or
                 (TThread.GetTickCount - LastProgressTick >= 80) then
              begin
                LastProgressTick := TThread.GetTickCount;
                EmitProgress(List.Count, Dir);
              end;

              Code := FindFirst(TPath.Combine(Dir, '*'), faAnyFile, SR);
              try
                while Code = 0 do
                begin
                  if JobCancelRequested(Cancel) or (List.Count >= cFindMaxResults) then
                    Break;
                  Name := SR.Name;
                  if (Name <> '.') and (Name <> '..') then
                  begin
                    Full := TPath.Combine(Dir, Name);
                    IsDir := (SR.Attr and faDirectory) <> 0;
                    if IsDir then
                    begin
                      if Opts.SearchFolders and NameMatchesAnyMask(Name, Masks) and
                         (Needle = '') then
                      begin
                        Hit.Path := Full;
                        Hit.Line := 0;
                        Hit.Snippet := '';
                        List.Add(Hit);
                      end;
                      if Opts.Subdirs then
                        Stack.Push(Full);
                    end
                    else if NameMatchesAnyMask(Name, Masks) then
                    begin
                      if ContentMatch(Full, HitLine, HitSnippet) then
                      begin
                        Hit.Path := Full;
                        Hit.Line := HitLine;
                        Hit.Snippet := HitSnippet;
                        List.Add(Hit);
                      end;
                    end;
                  end;
                  Code := FindNext(SR);
                end;
              finally
                FindClose(SR);
              end;
            end;

            if JobCancelRequested(Cancel) then
              Err := TVfsError.Make(vecCancelled, 'Cancelled', Opts.RootPath);
          end;
        except
          on E: Exception do
            Err := TVfsError.Make(vecIOError, E.Message, Opts.RootPath);
        end;
        Hits := List.ToArray;
      finally
        Stack.Free;
        List.Free;
      end;

      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Hits, Err);
        end);
    end).Start;
end;

end.
