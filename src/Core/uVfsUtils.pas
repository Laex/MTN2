unit uVfsUtils;

{ VFS Common Utilities: Encapsulates path parsing, file mask matching,
  size formatting, URI scheme extraction, and numeric (natural) name compare. }

interface

uses
  System.SysUtils, System.Masks, System.IOUtils;

/// <summary>Case-insensitive compare that treats digit runs as numbers
/// (file2 &lt; file10). Text between the digit runs is compared as a whole
/// run in the user's locale, for every alphabet ("абрикос" &lt; "Яблоко",
/// "ёж" &lt; "жа"). Used by panel/VFS name sorting.</summary>
function CompareNaturalText(const Left, Right: string): Integer;

type
  TVfsUtils = class
  public
    class function MatchesMask(const AFileName, AMask: string): Boolean;
    class function FormatFileSize(ASize: Int64): string;
    class function ExtractScheme(const AURI: string): string;
    class function IsFileUri(const AURI: string): Boolean;
    class function CleanPathDelimiter(const APath: string): string;
  end;

/// <summary>A free path next to ADest, named ADest plus ASuffix (and a number
/// when that name is taken). '' when no free name was found.</summary>
function UnusedSiblingPath(const ADest, ASuffix: string): string;

/// <summary>True for the root of a volume: a drive root, a share root or the
/// POSIX root. A delete never runs on such a path.</summary>
function IsVolumeRootPath(const APath: string): Boolean;

/// <summary>Removes a file or a folder with its content; a link inside is
/// removed as a node, never followed. A missing path counts as removed.</summary>
function DeletePathTree(const APath: string): Boolean;

/// <summary>Makes AStaged become ADest. An existing ADest is moved aside
/// first and put back if AStaged cannot take its place, so a failed replace
/// does not leave ADest missing. AStaged is consumed on success.</summary>
function ReplacePathWith(const AStaged, ADest: string; out AError: string): Boolean;

implementation

uses
  uPlatformInfo, uPlatformUpdate, uPlatformFileOps, uVfsTypes;

// One non-digit run of each name. Whole runs, never single chars mixed with
// an ASCII fast path: per-char "ASCII ordinal, else locale" is not
// transitive ("A" < "_" by code, "_" < U+2014 < "A" by locale) and would
// scramble the sort. SORT_STRINGSORT keeps '-' and '''' significant, so
// "a-b" and "ab" do not compare equal.
function CompareTextRun(const ALeft: string; ALeftStart, ALeftLen: Integer;
  const ARight: string; ARightStart, ARightLen: Integer): Integer;
begin
  if (ALeftLen = 0) or (ARightLen = 0) then
    Exit(Ord(ALeftLen > 0) - Ord(ARightLen > 0));
  Result := PlatformCompareTextRun(ALeft, ALeftStart, ALeftLen, ARight, ARightStart,
    ARightLen);
end;

function CompareNaturalText(const Left, Right: string): Integer;
var
  IL, IR, LenL, LenR: Integer;
  ZerosL, ZerosR, DigitsL, DigitsR, PL, PR: Integer;

  function IsDigit(C: Char): Boolean; inline;
  begin
    Result := (C >= '0') and (C <= '9');
  end;

begin
  IL := 1;
  IR := 1;
  LenL := Length(Left);
  LenR := Length(Right);
  while (IL <= LenL) and (IR <= LenR) do
  begin
    if IsDigit(Left[IL]) and IsDigit(Right[IR]) then
    begin
      ZerosL := 0;
      while (IL <= LenL) and (Left[IL] = '0') do
      begin
        Inc(IL);
        Inc(ZerosL);
      end;
      ZerosR := 0;
      while (IR <= LenR) and (Right[IR] = '0') do
      begin
        Inc(IR);
        Inc(ZerosR);
      end;
      PL := IL;
      while (IL <= LenL) and IsDigit(Left[IL]) do
        Inc(IL);
      DigitsL := IL - PL;
      PR := IR;
      while (IR <= LenR) and IsDigit(Right[IR]) do
        Inc(IR);
      DigitsR := IR - PR;
      if DigitsL <> DigitsR then
      begin
        if DigitsL < DigitsR then
          Exit(-1);
        Exit(1);
      end;
      while PL < IL do
      begin
        if Left[PL] <> Right[PR] then
        begin
          if Left[PL] < Right[PR] then
            Exit(-1);
          Exit(1);
        end;
        Inc(PL);
        Inc(PR);
      end;
      if ZerosL <> ZerosR then
      begin
        if ZerosL < ZerosR then
          Exit(-1);
        Exit(1);
      end;
    end
    else
    begin
      // Text up to the next digit on each side (empty on the side that is
      // already at a digit: digits sort before text).
      PL := IL;
      while (IL <= LenL) and not IsDigit(Left[IL]) do
        Inc(IL);
      PR := IR;
      while (IR <= LenR) and not IsDigit(Right[IR]) do
        Inc(IR);
      Result := CompareTextRun(Left, PL, IL - PL, Right, PR, IR - PR);
      if Result <> 0 then
        Exit;
    end;
  end;
  if IL <= LenL then
    Result := 1
  else if IR <= LenR then
    Result := -1
  else
    Result := 0;
end;

class function TVfsUtils.MatchesMask(const AFileName, AMask: string): Boolean;
var
  LMask: string;
begin
  if (AMask = '') or (AMask = '*') or (AMask = '*.*') then
    Exit(True);

  LMask := AMask;
  try
    Result := System.Masks.MatchesMask(AFileName, LMask);
  except
    Result := False;
  end;
end;

class function TVfsUtils.FormatFileSize(ASize: Int64): string;
begin
  if ASize < 1024 then
    Result := Format('%d B', [ASize])
  else if ASize < 1024 * 1024 then
    Result := Format('%.1f KB', [ASize / 1024])
  else if ASize < 1024 * 1024 * 1024 then
    Result := Format('%.1f MB', [ASize / (1024 * 1024)])
  else
    Result := Format('%.2f GB', [ASize / (1024 * 1024 * 1024)]);
end;

class function TVfsUtils.ExtractScheme(const AURI: string): string;
var
  LPos: Integer;
begin
  LPos := Pos('://', AURI);
  if LPos > 0 then
    Result := Copy(AURI, 1, LPos - 1).ToLower
  else
    Result := '';
end;

class function TVfsUtils.IsFileUri(const AURI: string): Boolean;
begin
  Result := AURI.StartsWith('file://', True);
end;

class function TVfsUtils.CleanPathDelimiter(const APath: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(APath);
end;

function PathIsPresent(const APath: string): Boolean;
begin
  Result := (APath <> '') and (TFile.Exists(APath) or TDirectory.Exists(APath));
end;

function UnusedSiblingPath(const ADest, ASuffix: string): string;
var
  N: Integer;
begin
  Result := ADest + ASuffix;
  N := 0;
  while PathIsPresent(Result) do
  begin
    Inc(N);
    if N > 1000 then
      Exit('');
    Result := ADest + ASuffix + IntToStr(N);
  end;
end;

function IsVolumeRootPath(const APath: string): Boolean;
var
  P: string;
begin
  P := ExcludeTrailingPathDelimiter(APath);
  Result := (P = '') or SameText(ExtractFileDrive(P), P);
end;

// Removes APath and everything under it. A link is removed as a single node:
// the folder it points at is never entered.
function RemoveTreeNode(const APath: string): Boolean;
var
  SR: TSearchRec;
  Code: Integer;
  Err: TVfsError;
begin
  if PlatformIsLinkNode(APath) then
    Exit(PlatformDeleteNode(APath, False, Err));
  if not LocalPathIsDirectory(APath) then
    Exit(PlatformDeleteNode(APath, False, Err));
  Result := True;
  Code := FindFirst(WinApiPath(SafeCombinePath(APath, '*')), faAnyFile, SR);
  try
    while Code = 0 do
    begin
      if (SR.Name <> '.') and (SR.Name <> '..') and
         not RemoveTreeNode(SafeCombinePath(APath, SR.Name)) then
        Result := False;
      Code := FindNext(SR);
    end;
  finally
    System.SysUtils.FindClose(SR);
  end;
  if Result then
    Result := PlatformDeleteNode(APath, True, Err);
end;

function DeletePathTree(const APath: string): Boolean;
begin
  Result := True;
  if (APath = '') or not (PathIsPresent(APath) or PlatformIsLinkNode(APath)) then
    Exit;
  try
    Result := RemoveTreeNode(APath);
  except
    Result := False;
  end;
end;

function ReplacePathWith(const AStaged, ADest: string; out AError: string): Boolean;
var
  Hold, MoveError: string;
begin
  AError := '';
  if not PathIsPresent(ADest) then
    Exit(PlatformMoveFile(AStaged, ADest, False, AError));
  // Move the current occupant aside before the staged path takes the name.
  // Deleting it first would lose it when the following rename fails.
  Hold := UnusedSiblingPath(ADest, '.mtnhold');
  if Hold = '' then
  begin
    AError := 'Cannot make room to replace the destination';
    Exit(False);
  end;
  if not PlatformMoveFile(ADest, Hold, False, AError) then
    Exit(False);
  if not PlatformMoveFile(AStaged, ADest, False, MoveError) then
  begin
    AError := MoveError;
    if not PlatformMoveFile(Hold, ADest, False, MoveError) then
      AError := AError + '; restore failed: ' + MoveError;
    Exit(False);
  end;
  DeletePathTree(Hold);
  Result := True;
end;

end.
