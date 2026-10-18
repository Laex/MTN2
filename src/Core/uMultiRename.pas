unit uMultiRename;

{ Batch rename rules: new names from a name mask and an extension mask, a
  search and replace, a counter and a letter case, plus the check that the
  whole batch can be applied. No I/O and no UI, so the rules are testable on
  their own.

  Masks understand three tokens: [N] the old name without extension, [E] the
  old extension (no dot) and [C] the counter. Any other text, including a
  bracket that is not a token, is kept as typed. }

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

/// <summary>The new name of one item. AIndex (0-based) is its place in the
/// batch and drives the counter. Folders have no extension: the whole name
/// is [N].</summary>
function MultiRenameName(const AOldName: string; AIsDir: Boolean; AIndex: Integer;
  const ARules: TMultiRenameRules): string;

/// <summary>New names for the whole batch and what, if anything, stops each
/// from being applied. AExisting lists every name in the folder, the batch
/// included.</summary>
function PlanMultiRename(const ANames: TArray<string>; const AIsDir: TArray<Boolean>;
  const AExisting: TArray<string>; const ARules: TMultiRenameRules): TRenamePlan;

/// <summary>True when applying the plan would fail or overwrite something.</summary>
function RenamePlanBlocked(const APlan: TRenamePlan): Boolean;
/// <summary>Items that get a new name.</summary>
function RenamePlanChangeCount(const APlan: TRenamePlan): Integer;

implementation

uses
  System.SysUtils, System.Generics.Collections, uPlatformPaths;

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

function ExpandMask(const AMask, ABase, AExt, ACounter: string): string;
var
  I: Integer;
  Tok: string;
begin
  Result := '';
  I := 1;
  while I <= Length(AMask) do
  begin
    if (AMask[I] = '[') and (I + 2 <= Length(AMask)) and (AMask[I + 2] = ']') then
    begin
      Tok := UpperCase(Copy(AMask, I + 1, 1));
      if Tok = 'N' then
      begin
        Result := Result + ABase;
        Inc(I, 3);
        Continue;
      end
      else if Tok = 'E' then
      begin
        Result := Result + AExt;
        Inc(I, 3);
        Continue;
      end
      else if Tok = 'C' then
      begin
        Result := Result + ACounter;
        Inc(I, 3);
        Continue;
      end;
    end;
    Result := Result + AMask[I];
    Inc(I);
  end;
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
var
  Base, Ext, NewBase, NewExt, Counter: string;
  Flags: TReplaceFlags;
begin
  SplitName(AOldName, AIsDir, Base, Ext);
  Counter := CounterText(AIndex, ARules);
  NewBase := ExpandMask(ARules.NameMask, Base, Ext, Counter);
  if AIsDir then
    NewExt := ''
  else
    NewExt := ExpandMask(ARules.ExtMask, Base, Ext, Counter);
  if ARules.Search <> '' then
  begin
    Flags := [rfReplaceAll];
    if not ARules.MatchCase then
      Include(Flags, rfIgnoreCase);
    NewBase := StringReplace(NewBase, ARules.Search, ARules.Replace, Flags);
    NewExt := StringReplace(NewExt, ARules.Search, ARules.Replace, Flags);
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
var
  I: Integer;
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
      Result[I].NewName := MultiRenameName(ANames[I], AIsDir[I], I, ARules);
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
