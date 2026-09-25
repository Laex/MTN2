unit uDualPanelCmd;

{ Command-line path resolution, Tab-complete, and Dual Panel prompt drawing. }

interface

uses
  System.SysUtils, System.StrUtils, System.IOUtils, System.Math, System.UITypes,
  uVfsTypes, uTerminalTypes, uInputLine;

{ Resolves AText as a navigable path relative to ABaseDir (panel cwd).
  Returns True and a file:// URI when the text is a path that should navigate
  the panel; False means run as a shell command instead. }
function TryResolvePanelCommandPath(const AText, ABaseDir: string;
  out AURI: string): Boolean;

function ExpandEnvVars(const AText: string): string;

/// <summary>Quote for cmd.exe when value has spaces / special chars.</summary>
function CmdLineQuoteIfNeeded(const AValue: string): string;
/// <summary>0-based [AStart, AEnd) span of the token under caret.</summary>
procedure CmdLineTokenBounds(const AText: string; ACursor: Integer;
  out AStart, AEnd: Integer);
function CmdLineExtractToken(const AText: string; ACursor: Integer): string;
/// <summary>Replace token at caret with ACompletion (quotes applied).</summary>
function CmdLineApplyCompletion(const AText: string; ACursor: Integer;
  const ACompletion: string; out ANewText: string;
  out ANewCursor: Integer): Boolean;
/// <summary>Case-insensitive prefix filter; skips empty / '.' / '..'.</summary>
function FilterCompletions(const ANames: TArray<string>;
  const APrefix: string): TArray<string>;
/// <summary>True when the Tab token names a path (has '\', '/' or starts
/// with a drive "X:"), so completion reads the disk, not the panel list.</summary>
function CmdLineTokenIsPath(const AToken: string): Boolean;
/// <summary>Disk entries for a path token: the folder part is kept as typed
/// and the last part is a case-insensitive prefix. A relative folder is
/// resolved against ABaseDir. Folders first, then files, each sorted.</summary>
function CmdLinePathCompletions(const AToken, ABaseDir: string): TArray<string>;

/// <summary>Shorten a path for on-screen display (head...tail). AMaxLen is
/// character count excluding the trailing #0 PathCompactPathEx expects.</summary>
function CompactDisplayPath(const APath: string; AMaxLen: Integer): string;
/// <summary>Dual Panel cmdline prompt: compact path + "&gt; ", total width ≤
/// AMaxPrefixCells (typically grid width div 3).</summary>
function FormatCmdLinePrefix(const APath: string; AMaxPrefixCells: Integer): string;
function CmdLinePrefixMaxCells(AWidth: Integer): Integer;
function CmdLinePathLabel(const AURI: string): string;

type
  TCmdLineColorProc = procedure(out AFg, ABg: TAlphaColor) of object;

  TDualPanelCmdLineDrawHost = record
    ResolveStripColors: TCmdLineColorProc;
    ResolveFocusAccent: TCmdLineColorProc;
  end;

procedure ResolveCmdLineInputColors(AFocused: Boolean;
  AStripFg, AStripBg, AAccentFg, AAccentBg: TAlphaColor;
  out AColors: TInputLineColors);
procedure DrawDualPanelCommandLine(const AHost: TDualPanelCmdLineDrawHost;
  const ABuffer: TTerminalGrid; AY, AWidth: Integer; const AURI: string;
  var ACmd: TInputLine; AFocused, ACursorVisible: Boolean);
/// <summary>Screen column where the command line's edit field starts (after
/// the path prompt), for mapping a mouse click to a caret position.</summary>
function DualPanelCmdLineEditX(const AURI: string; AWidth: Integer): Integer;

implementation

uses
  Winapi.Windows, Winapi.ShLwApi, System.Generics.Collections, System.Generics.Defaults;

function ExpandEnvVars(const AText: string): string;
var
  PStart, PEnd: Integer;
  VarName, VarVal: string;
begin
  Result := AText;
  if Pos('%', Result) = 0 then
    Exit;

  PStart := Pos('%', Result);
  while PStart > 0 do
  begin
    PEnd := PosEx('%', Result, PStart + 1);
    if PEnd > PStart + 1 then
    begin
      VarName := Copy(Result, PStart + 1, PEnd - PStart - 1);
      VarVal := System.SysUtils.GetEnvironmentVariable(VarName);
      if VarVal <> '' then
      begin
        Result := Copy(Result, 1, PStart - 1) + VarVal + Copy(Result, PEnd + 1, MaxInt);
        PStart := Pos('%', Result);
        Continue;
      end;
    end;
    Break;
  end;
end;

function TryResolvePanelCommandPath(const AText, ABaseDir: string;
  out AURI: string): Boolean;
var
  S, Combined, OriginalText: string;
  IsCd: Boolean;
begin
  Result := False;
  AURI := '';
  OriginalText := Trim(AText);
  if OriginalText = '' then
    Exit;

  IsCd := False;
  S := OriginalText;

  // Strip "cd " / "cd /d " / "chdir " prefixes
  if SameText(Copy(S, 1, 3), 'cd ') then
  begin
    IsCd := True;
    S := Trim(Copy(S, 4, MaxInt));
  end
  else if SameText(Copy(S, 1, 6), 'cd /d ') then
  begin
    IsCd := True;
    S := Trim(Copy(S, 7, MaxInt));
  end
  else if SameText(Copy(S, 1, 5), 'cd/d ') then
  begin
    IsCd := True;
    S := Trim(Copy(S, 6, MaxInt));
  end
  else if SameText(Copy(S, 1, 6), 'chdir ') then
  begin
    IsCd := True;
    S := Trim(Copy(S, 7, MaxInt));
  end;

  // Command lines with option switches (e.g. "dir /o", "dir /w") are commands, not directories
  if not IsCd then
  begin
    if (Pos(' /', OriginalText) > 0) or (Pos(' -', OriginalText) > 0) then
      Exit(False);
  end;

  // Expand environment variables (%APPDATA%, %USERPROFILE%, %TEMP%, etc.)
  S := ExpandEnvVars(S);

  if S.StartsWith('file:', True) then
  begin
    AURI := PathToFileUri(FileUriToPath(S));
    Exit(AURI <> '');
  end;

  // Any other "scheme://..." (sftp://, ws://, a future plugin scheme, ...):
  // pass through unchanged, same as the file: branch above but generic.
  // Without this, a typed "sftp://user@host/path" fell into the relative-
  // path branch below and was silently mistranslated into a bogus local
  // file:// URI (TPath.Combine(cwd, "sftp://user@host/path")).
  if Pos('://', S) > 0 then
  begin
    AURI := S;
    Exit(True);
  end;

  // Absolute Windows path / UNC / drive root "D:"
  if ((Length(S) >= 2) and (S[2] = ':')) or S.StartsWith('\\') then
  begin
    if (Length(S) = 2) and (S[2] = ':') then
      S := S + PathDelim;
    AURI := PathToFileUri(S);
    Exit(True);
  end;

  if ABaseDir = '' then
    Exit;

  // Explicit "cd ...", or relative paths starting with ".", "\", or "/"
  if IsCd or S.StartsWith('.') or S.StartsWith('\') or S.StartsWith('/') then
  begin
    Combined := TPath.Combine(ABaseDir, S);
    AURI := PathToFileUri(Combined);
    Exit(True);
  end;

  // Relative path without "cd" or "." (e.g. "subfolder\child"):
  // Only treat as path if command line contains no spaces (e.g. "dir /o" has spaces)
  if (Pos(' ', OriginalText) = 0) and ((Pos('\', S) > 0) or (Pos('/', S) > 0)) then
  begin
    Combined := TPath.Combine(ABaseDir, S);
    AURI := PathToFileUri(Combined);
    Exit(True);
  end;
end;

function CmdLineQuoteIfNeeded(const AValue: string): string;
begin
  if (AValue = '') or ((Pos(' ', AValue) = 0) and (Pos('"', AValue) = 0) and
     (Pos('&', AValue) = 0) and (Pos('(', AValue) = 0)) then
    Exit(AValue);
  Result := '"' + StringReplace(AValue, '"', '""', [rfReplaceAll]) + '"';
end;

procedure CmdLineTokenBounds(const AText: string; ACursor: Integer;
  out AStart, AEnd: Integer);
var
  N, I: Integer;
  InQuote: Boolean;
begin
  N := Length(AText);
  if ACursor < 0 then
    ACursor := 0;
  if ACursor > N then
    ACursor := N;

  InQuote := False;
  for I := 1 to ACursor do
    if AText[I] = '"' then
      InQuote := not InQuote;

  if InQuote then
  begin
    // Opening quote is at 1-based I; token span includes the opening quote
    // through closing quote (or EOL) so ApplyCompletion can replace the whole
    // quoted token with a freshly quoted completion.
    I := ACursor;
    while (I >= 1) and (AText[I] <> '"') do
      Dec(I);
    if I >= 1 then
      AStart := I - 1 // 0-based index of '"'
    else
      AStart := 0;
    AEnd := ACursor;
    while (AEnd < N) and (AText[AEnd + 1] <> '"') do
      Inc(AEnd);
    if (AEnd < N) and (AText[AEnd + 1] = '"') then
      Inc(AEnd); // include closing quote
  end
  else
  begin
    AStart := ACursor;
    while (AStart > 0) and (AText[AStart] <> ' ') and (AText[AStart] <> #9) do
      Dec(AStart);
    AEnd := ACursor;
    while (AEnd < N) and (AText[AEnd + 1] <> ' ') and (AText[AEnd + 1] <> #9) do
      Inc(AEnd);
  end;
end;

function CmdLineExtractToken(const AText: string; ACursor: Integer): string;
var
  AStart, AEnd: Integer;
  Raw: string;
begin
  CmdLineTokenBounds(AText, ACursor, AStart, AEnd);
  Raw := Copy(AText, AStart + 1, AEnd - AStart);
  if (Length(Raw) >= 2) and (Raw[1] = '"') then
  begin
    if Raw[Length(Raw)] = '"' then
      Result := Copy(Raw, 2, Length(Raw) - 2)
    else
      Result := Copy(Raw, 2, MaxInt);
  end
  else
    Result := Raw;
end;

function CmdLineApplyCompletion(const AText: string; ACursor: Integer;
  const ACompletion: string; out ANewText: string;
  out ANewCursor: Integer): Boolean;
var
  AStart, AEnd: Integer;
  Quoted: string;
begin
  Result := False;
  if ACompletion = '' then
    Exit;
  CmdLineTokenBounds(AText, ACursor, AStart, AEnd);
  Quoted := CmdLineQuoteIfNeeded(ACompletion);
  ANewText := Copy(AText, 1, AStart) + Quoted + Copy(AText, AEnd + 1, MaxInt);
  ANewCursor := AStart + Length(Quoted);
  Result := True;
end;

function FilterCompletions(const ANames: TArray<string>;
  const APrefix: string): TArray<string>;
var
  I, N: Integer;
  Name: string;
begin
  SetLength(Result, Length(ANames));
  N := 0;
  for I := 0 to High(ANames) do
  begin
    Name := ANames[I];
    while (Name <> '') and ((Name[Length(Name)] = '/') or
      (Name[Length(Name)] = '\')) do
      Delete(Name, Length(Name), 1);
    if (Name = '') or (Name = '.') or (Name = '..') then
      Continue;
    if (APrefix = '') or Name.StartsWith(APrefix, True) then
    begin
      Result[N] := Name;
      Inc(N);
    end;
  end;
  SetLength(Result, N);
end;

function CmdLineTokenIsPath(const AToken: string): Boolean;
begin
  Result := (Pos('\', AToken) > 0) or (Pos('/', AToken) > 0) or
    ((Length(AToken) >= 2) and (AToken[2] = ':') and CharInSet(UpCase(AToken[1]), ['A'..'Z']));
end;

function CmdLinePathCompletions(const AToken, ABaseDir: string): TArray<string>;
var
  Cut, I: Integer;
  DirPart, NamePrefix, Dir: string;
  Dirs, Files: TArray<string>;
  SR: TSearchRec;
begin
  SetLength(Result, 0);
  if not CmdLineTokenIsPath(AToken) then
    Exit;
  // Split after the last separator; "C:" alone is a folder part too.
  Cut := 0;
  for I := Length(AToken) downto 1 do
    if CharInSet(AToken[I], ['\', '/']) then
    begin
      Cut := I;
      Break;
    end;
  if (Cut = 0) and (Length(AToken) >= 2) and (AToken[2] = ':') then
    Cut := 2;
  DirPart := Copy(AToken, 1, Cut);
  NamePrefix := Copy(AToken, Cut + 1, MaxInt);
  Dir := StringReplace(DirPart, '/', '\', [rfReplaceAll]);
  if Dir = '' then
    Dir := ABaseDir
  else if (Length(Dir) = 2) and (Dir[2] = ':') then
    Dir := Dir + '\'
  else if not TPath.IsPathRooted(Dir) then
    Dir := TPath.Combine(ABaseDir, Dir);
  if (Dir = '') or not TDirectory.Exists(Dir) then
    Exit;
  SetLength(Dirs, 0);
  SetLength(Files, 0);
  if System.SysUtils.FindFirst(TPath.Combine(Dir, '*'), faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then
          Continue;
        if (NamePrefix <> '') and not StartsText(NamePrefix, SR.Name) then
          Continue;
        if (SR.Attr and faDirectory) <> 0 then
          Dirs := Dirs + [DirPart + SR.Name]
        else
          Files := Files + [DirPart + SR.Name];
      until System.SysUtils.FindNext(SR) <> 0;
    finally
      System.SysUtils.FindClose(SR);
    end;
  TArray.Sort<string>(Dirs, TIStringComparer.Ordinal);
  TArray.Sort<string>(Files, TIStringComparer.Ordinal);
  Result := Dirs + Files;
end;

function CompactDisplayPath(const APath: string; AMaxLen: Integer): string;
var
  Buf: string;
  Head, Tail: Integer;
begin
  if AMaxLen < 1 then
    Exit('');
  if Length(APath) <= AMaxLen then
    Exit(APath);
  if AMaxLen < 4 then
    Exit(Copy(APath, 1, AMaxLen));
  SetLength(Buf, AMaxLen);
  if PathCompactPathEx(PChar(Buf), PChar(APath), Cardinal(AMaxLen) + 1, 0) then
  begin
    Result := PChar(Buf);
    if Result <> '' then
      Exit;
  end;
  Head := (AMaxLen - 3) div 2;
  Tail := AMaxLen - 3 - Head;
  if Tail < 1 then
    Exit(Copy(APath, 1, AMaxLen));
  Result := Copy(APath, 1, Head) + '...' +
    Copy(APath, Length(APath) - Tail + 1, MaxInt);
end;

function FormatCmdLinePrefix(const APath: string; AMaxPrefixCells: Integer): string;
const
  cPromptSuffix = '>';
  cMinPrefixCells = Length(cPromptSuffix) + 1;
var
  MaxPathLen: Integer;
  DisplayPath: string;
begin
  if AMaxPrefixCells <= cMinPrefixCells then
    Exit(cPromptSuffix);
  MaxPathLen := AMaxPrefixCells - Length(cPromptSuffix);
  DisplayPath := CompactDisplayPath(APath, MaxPathLen);
  Result := DisplayPath + cPromptSuffix;
end;

function CmdLinePrefixMaxCells(AWidth: Integer): Integer;
begin
  Result := Max(AWidth div 3, Length('> ') + 1);
end;

function CmdLinePathLabel(const AURI: string): string;
begin
  if IsRecycleBinUri(AURI) then
    Result := VfsUriTitle(AURI)
  else
    Result := FileUriToPath(AURI);
end;

procedure ResolveCmdLineInputColors(AFocused: Boolean;
  AStripFg, AStripBg, AAccentFg, AAccentBg: TAlphaColor;
  out AColors: TInputLineColors);
begin
  AColors.Fg := AStripFg;
  AColors.Bg := AStripBg;
  if AFocused then
  begin
    AColors.SelFg := AAccentFg;
    AColors.SelBg := AAccentBg;
  end
  else
  begin
    AColors.SelFg := AStripFg;
    AColors.SelBg := AStripBg;
  end;
  AColors.CaretFg := AColors.SelFg;
  AColors.CaretBg := AColors.SelBg;
end;

function DualPanelCmdLineEditX(const AURI: string; AWidth: Integer): Integer;
begin
  Result := Length(FormatCmdLinePrefix(CmdLinePathLabel(AURI),
    CmdLinePrefixMaxCells(AWidth)));
end;

procedure DrawDualPanelCommandLine(const AHost: TDualPanelCmdLineDrawHost;
  const ABuffer: TTerminalGrid; AY, AWidth: Integer; const AURI: string;
  var ACmd: TInputLine; AFocused, ACursorVisible: Boolean);
var
  Colors: TInputLineColors;
  StripFg, StripBg, AccFg, AccBg: TAlphaColor;
  Prefix: string;
  EditW: Integer;
begin
  AHost.ResolveStripColors(StripFg, StripBg);
  if AFocused then
    AHost.ResolveFocusAccent(AccFg, AccBg)
  else
  begin
    AccFg := StripFg;
    AccBg := StripBg;
  end;
  ResolveCmdLineInputColors(AFocused, StripFg, StripBg, AccFg, AccBg, Colors);
  FillGridRect(ABuffer, 0, AY, AWidth - 1, AY, ' ', Colors.Fg, Colors.Bg);
  Prefix := FormatCmdLinePrefix(CmdLinePathLabel(AURI), CmdLinePrefixMaxCells(AWidth));
  PutGridText(ABuffer, 0, AY, Prefix, Colors.Fg, Colors.Bg);
  EditW := AWidth - Length(Prefix);
  if EditW > 0 then
    InputLineDraw(ABuffer, Length(Prefix), AY, EditW, ACmd, AFocused, Colors,
      ACursorVisible);
end;

end.
