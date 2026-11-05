unit uMultiRename;

{ Batch rename rules: new names from a name mask and an extension mask, a
  search and replace (plain or regular expression), a counter and a letter
  case, plus the check that the whole batch can be applied. No I/O and no UI,
  so the rules are testable on their own.

  Masks understand these tokens, in any letter case: [N] the old name without
  extension, [E] the old extension (no dot), [C] the counter, [Date] and
  [Time] of the modification (yyyy-mm-dd, hh-nn-ss), [Year] [Month] [Day],
  [Parent] the name of the folder, [Size] in bytes, and the plugin values
  [Dim] [Camera] [Artist] [Title]. A token whose value is unknown is empty;
  characters a file name cannot hold become "_" in a value. Any other text,
  including a bracket that is not a token, is kept as typed. }

interface

type
  TRenameCase = (rcKeep, rcLower, rcUpper, rcFirstUpper, rcWordsUpper);

  TMultiRenameRules = record
    NameMask: string;
    ExtMask: string;
    Search: string;
    Replace: string;
    MatchCase: Boolean;
    CounterStart: Integer;
    CounterStep: Integer;
    CounterDigits: Integer;
    CaseMode: TRenameCase;
    /// <summary>Search is a regular expression and Replace may use $1.</summary>
    UseRegex: Boolean;
  end;

  /// <summary>What the tokens of one item expand to.</summary>
  TRenameItemInfo = record
    /// <summary>0 when unknown.</summary>
    Modified: TDateTime;
    /// <summary>-1 when unknown.</summary>
    Size: Int64;
    Parent: string;
    Dim: string;
    Camera: string;
    Artist: string;
    Title: string;
  end;

  TRenameProblem = (
    rpNone,
    rpUnchanged,  // the name stays as it is: nothing to do
    rpEmpty,
    rpInvalid,    // characters the file system does not accept
    rpDuplicate,  // two items of the batch get the same name
    rpExists);    // another item of the folder already has the name

  TRenamePlanItem = record
    OldName: string;
    NewName: string;
    Problem: TRenameProblem;
  end;

  TRenamePlan = TArray<TRenamePlanItem>;

function DefaultMultiRenameRules: TMultiRenameRules;
/// <summary>Info with nothing known.</summary>
function EmptyRenameItemInfo: TRenameItemInfo;

/// <summary>The new name of one item. AIndex (0-based) is its place in the
/// batch and drives the counter. Folders have no extension: the whole name
/// is [N].</summary>
function MultiRenameName(const AOldName: string; AIsDir: Boolean; AIndex: Integer;
  const ARules: TMultiRenameRules): string; overload;
function MultiRenameName(const AOldName: string; AIsDir: Boolean; AIndex: Integer;
  const ARules: TMultiRenameRules; const AInfo: TRenameItemInfo): string; overload;

/// <summary>New names for the whole batch and what, if anything, stops each
/// from being applied. AExisting lists every name in the folder, the batch
/// included. AInfos[i] describes ANames[i]; a missing one means nothing is
/// known.</summary>
function PlanMultiRename(const ANames: TArray<string>; const AIsDir: TArray<Boolean>;
  const AExisting: TArray<string>; const ARules: TMultiRenameRules): TRenamePlan; overload;
function PlanMultiRename(const ANames: TArray<string>; const AIsDir: TArray<Boolean>;
  const AExisting: TArray<string>; const ARules: TMultiRenameRules;
  const AInfos: TArray<TRenameItemInfo>): TRenamePlan; overload;

/// <summary>True when applying the plan would fail or overwrite something.</summary>
function RenamePlanBlocked(const APlan: TRenamePlan): Boolean;
/// <summary>Items that get a new name.</summary>
function RenamePlanChangeCount(const APlan: TRenamePlan): Integer;

implementation

uses
  System.SysUtils, System.Generics.Collections, System.RegularExpressions,
  uPlatformPaths;

function DefaultMultiRenameRules: TMultiRenameRules;
begin
  Result := Default(TMultiRenameRules);
  Result.NameMask := '[N]';
  Result.ExtMask := '[E]';
  Result.CounterStart := 1;
  Result.CounterStep := 1;
  Result.CounterDigits := 1;
  Result.CaseMode := rcKeep;
end;

function EmptyRenameItemInfo: TRenameItemInfo;
begin
  Result := Default(TRenameItemInfo);
  Result.Size := -1;
end;

procedure SplitName(const AName: string; AIsDir: Boolean; out ABase, AExt: string);
var
  P: Integer;
begin
  ABase := AName;
  AExt := '';
  if AIsDir then
    Exit;
  P := LastDelimiter('.', AName);
  if P > 1 then
  begin
    ABase := Copy(AName, 1, P - 1);
    AExt := Copy(AName, P + 1, MaxInt);
  end;
end;

function CounterText(AIndex: Integer; const ARules: TMultiRenameRules): string;
var
  Digits: Integer;
begin
  Digits := ARules.CounterDigits;
  if Digits < 1 then
    Digits := 1;
  Result := IntToStr(ARules.CounterStart + AIndex * ARules.CounterStep);
  while Length(Result) < Digits do
    Result := '0' + Result;
end;

// A metadata value as a file name part: characters the file system rejects
// become "_".
function SafeValue(const AValue: string): string;
var
  I: Integer;
begin
  Result := AValue;
  for I := 1 to Length(Result) do
    if (Result[I] < ' ') or CharInSet(Result[I], ['\', '/', ':', '*', '?', '"', '<', '>', '|']) then
      Result[I] := '_';
end;

// The expansion of the token ATok (upper case); False for a word that is not a token.
function TokenValue(const ATok, ABase, AExt, ACounter: string;
  const AInfo: TRenameItemInfo; out AValue: string): Boolean;

  function Stamp(const AFormat: string): string;
  begin
    if AInfo.Modified = 0 then
      Result := ''
    else
      Result := FormatDateTime(AFormat, AInfo.Modified);
  end;

begin
  Result := True;
  if ATok = 'N' then
    AValue := ABase
  else if ATok = 'E' then
    AValue := AExt
  else if ATok = 'C' then
    AValue := ACounter
  else if ATok = 'DATE' then
    AValue := Stamp('yyyy"-"mm"-"dd')
  else if ATok = 'TIME' then
    AValue := Stamp('hh"-"nn"-"ss')
  else if ATok = 'YEAR' then
    AValue := Stamp('yyyy')
  else if ATok = 'MONTH' then
    AValue := Stamp('mm')
  else if ATok = 'DAY' then
    AValue := Stamp('dd')
  else if ATok = 'PARENT' then
    AValue := SafeValue(AInfo.Parent)
  else if ATok = 'SIZE' then
  begin
    if AInfo.Size >= 0 then
      AValue := IntToStr(AInfo.Size)
    else
      AValue := '';
  end
  else if ATok = 'DIM' then
    AValue := SafeValue(AInfo.Dim)
  else if ATok = 'CAMERA' then
    AValue := SafeValue(AInfo.Camera)
  else if ATok = 'ARTIST' then
    AValue := SafeValue(AInfo.Artist)
  else if ATok = 'TITLE' then
    AValue := SafeValue(AInfo.Title)
  else
  begin
    AValue := '';
    Result := False;
  end;
end;

function ExpandMask(const AMask, ABase, AExt, ACounter: string;
  const AInfo: TRenameItemInfo): string;
const
  cMaxTokenLen = 8;
var
  I, J: Integer;
  Value: string;
begin
  Result := '';
  I := 1;
  while I <= Length(AMask) do
  begin
    if AMask[I] = '[' then
    begin
      J := I + 1;
      while (J <= Length(AMask)) and (J - I <= cMaxTokenLen) and (AMask[J] <> ']') do
        Inc(J);
      if (J <= Length(AMask)) and (AMask[J] = ']') and (J > I + 1) and
         TokenValue(UpperCase(Copy(AMask, I + 1, J - I - 1)), ABase, AExt, ACounter,
           AInfo, Value) then
      begin
        Result := Result + Value;
        I := J + 1;
        Continue;
      end;
    end;
    Result := Result + AMask[I];
    Inc(I);
  end;
end;

// Search and replace over one name part; a pattern that is not a valid
// regular expression leaves the text as it is.
function ReplaceInPart(const AText: string; const ARules: TMultiRenameRules): string;
var
  Flags: TReplaceFlags;
  Options: TRegExOptions;
begin
  if ARules.UseRegex then
  begin
    Options := [];
    if not ARules.MatchCase then
      Include(Options, roIgnoreCase);
    try
      Result := TRegEx.Replace(AText, ARules.Search, ARules.Replace, Options);
    except
      on Exception do
        Result := AText;
    end;
    Exit;
  end;
  Flags := [rfReplaceAll];
  if not ARules.MatchCase then
    Include(Flags, rfIgnoreCase);
  Result := StringReplace(AText, ARules.Search, ARules.Replace, Flags);
end;

function WordsUpper(const S: string; AFirstOnly: Boolean): string;
var
  I: Integer;
  AtStart: Boolean;
begin
  Result := LowerCase(S);
  AtStart := True;
  for I := 1 to Length(Result) do
  begin
    if AtStart and (Result[I] <> ' ') then
    begin
      Result[I] := UpperCase(Result[I])[1];
      AtStart := False;
      if AFirstOnly then
        Break;
    end
    else if not AFirstOnly and CharInSet(Result[I], [' ', '_', '-', '.', '(', '[']) then
      AtStart := True;
  end;
end;

function MultiRenameName(const AOldName: string; AIsDir: Boolean; AIndex: Integer;
  const ARules: TMultiRenameRules): string;
begin
  Result := MultiRenameName(AOldName, AIsDir, AIndex, ARules, EmptyRenameItemInfo);
end;

function MultiRenameName(const AOldName: string; AIsDir: Boolean; AIndex: Integer;
  const ARules: TMultiRenameRules; const AInfo: TRenameItemInfo): string;
var
  Base, Ext, NewBase, NewExt, Counter: string;
begin
  SplitName(AOldName, AIsDir, Base, Ext);
  Counter := CounterText(AIndex, ARules);
  NewBase := ExpandMask(ARules.NameMask, Base, Ext, Counter, AInfo);
  if AIsDir then
    NewExt := ''
  else
    NewExt := ExpandMask(ARules.ExtMask, Base, Ext, Counter, AInfo);
  if ARules.Search <> '' then
  begin
    NewBase := ReplaceInPart(NewBase, ARules);
    NewExt := ReplaceInPart(NewExt, ARules);
  end;
  case ARules.CaseMode of
    rcLower:
      begin
        NewBase := LowerCase(NewBase);
        NewExt := LowerCase(NewExt);
      end;
    rcUpper:
      begin
        NewBase := UpperCase(NewBase);
        NewExt := UpperCase(NewExt);
      end;
    rcFirstUpper:
      NewBase := WordsUpper(NewBase, True);
    rcWordsUpper:
      NewBase := WordsUpper(NewBase, False);
  end;
  Result := NewBase;
  if NewExt <> '' then
    Result := Result + '.' + NewExt;
end;

function NameIsValid(const AName: string): Boolean;
var
  Ch: Char;
begin
  Result := AName <> '';
  if not Result then
    Exit;
  for Ch in AName do
    if (Ch < ' ') or (Ch = '/') or (not PlatformPosixPaths and CharInSet(Ch, ['\', ':', '*', '?', '"', '<', '>', '|'])) then
      Exit(False);
  if not PlatformPosixPaths and CharInSet(AName[Length(AName)], [' ', '.']) then
    Exit(False);
end;

function Key(const AName: string): string;
begin
  if PlatformPosixPaths then
    Result := AName
  else
    Result := LowerCase(AName);
end;

function PlanMultiRename(const ANames: TArray<string>; const AIsDir: TArray<Boolean>;
  const AExisting: TArray<string>; const ARules: TMultiRenameRules): TRenamePlan;
begin
  Result := PlanMultiRename(ANames, AIsDir, AExisting, ARules, nil);
end;

function PlanMultiRename(const ANames: TArray<string>; const AIsDir: TArray<Boolean>;
  const AExisting: TArray<string>; const ARules: TMultiRenameRules;
  const AInfos: TArray<TRenameItemInfo>): TRenamePlan;
var
  I: Integer;
  Info: TRenameItemInfo;
  Taken: TDictionary<string, Integer>;
  Count: Integer;
  Existing: string;
begin
  SetLength(Result, Length(ANames));
  Taken := TDictionary<string, Integer>.Create;
  try
    for I := 0 to High(ANames) do
    begin
      Result[I].OldName := ANames[I];
      if I <= High(AInfos) then
        Info := AInfos[I]
      else
        Info := EmptyRenameItemInfo;
      Result[I].NewName := MultiRenameName(ANames[I], AIsDir[I], I, ARules, Info);
      Result[I].Problem := rpNone;
      if Result[I].NewName = ANames[I] then
        Result[I].Problem := rpUnchanged
      else if Result[I].NewName = '' then
        Result[I].Problem := rpEmpty
      else if not NameIsValid(Result[I].NewName) then
        Result[I].Problem := rpInvalid;
    end;
    // A name already used by a folder item blocks the item unless it is only
    // a case change of that item's own name.
    for I := 0 to High(Result) do
      if Result[I].Problem = rpNone then
        for Existing in AExisting do
          if (Key(Existing) = Key(Result[I].NewName)) and
             (Key(Existing) <> Key(Result[I].OldName)) then
          begin
            Result[I].Problem := rpExists;
            Break;
          end;
    for I := 0 to High(Result) do
      if Result[I].Problem in [rpNone, rpUnchanged] then
      begin
        if Taken.TryGetValue(Key(Result[I].NewName), Count) then
          Taken[Key(Result[I].NewName)] := Count + 1
        else
          Taken.Add(Key(Result[I].NewName), 1);
      end;
    for I := 0 to High(Result) do
      if (Result[I].Problem = rpNone) and
         Taken.TryGetValue(Key(Result[I].NewName), Count) and (Count > 1) then
        Result[I].Problem := rpDuplicate;
  finally
    Taken.Free;
  end;
end;

function RenamePlanBlocked(const APlan: TRenamePlan): Boolean;
var
  Item: TRenamePlanItem;
begin
  for Item in APlan do
    if not (Item.Problem in [rpNone, rpUnchanged]) then
      Exit(True);
  Result := False;
end;

function RenamePlanChangeCount(const APlan: TRenamePlan): Integer;
var
  Item: TRenamePlanItem;
begin
  Result := 0;
  for Item in APlan do
    if Item.Problem = rpNone then
      Inc(Result);
end;

end.
