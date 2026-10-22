unit uWinFileAttr;

{ Dialog logic of the Set attributes command (Ctrl+Shift+A): merging the state
  of several items, parsing and formatting times, applying a plan to a list of
  roots (optionally recursively). Reading and writing one file is
  uPlatformFileAttr. }

interface

uses
  System.SysUtils, uFileAttrTypes;

function FileAttrChoiceToIndex(AChoice: TFileAttrChoice): Integer;
function FileAttrIndexToChoice(AIndex: Integer): TFileAttrChoice;
function FileAttrPlanIsNoOp(const APlan: TFileAttrPlan): Boolean;
/// <summary>Short date + hh:nn:ss of the current locale; '' for 0.</summary>
function FormatFileAttrTime(ATime: TDateTime): string;
/// <summary>Parses what FormatFileAttrTime produces (seconds and the time
/// part are optional). False for '' and for dates a file time cannot hold.</summary>
function TryParseFileAttrTime(const AText: string; out ATime: TDateTime): Boolean;
function BuildFileAttrDialogState(const APaths: TArray<string>): TFileAttrDialogState;
function ApplyFileAttrPlan(const APath: string; const APlan: TFileAttrPlan;
  out AError: string): Boolean;
procedure ApplyFileAttrRoots(const APaths: TArray<string>;
  const APlan: TFileAttrPlan; out AOk, AFail: Integer;
  out AFirstFailPath, AFirstError: string);

implementation

uses
  System.IOUtils, uPlatformFileAttr, uVfsTypes;

function FileAttrChoiceToIndex(AChoice: TFileAttrChoice): Integer;
begin
  Result := Ord(AChoice);
end;

function FileAttrIndexToChoice(AIndex: Integer): TFileAttrChoice;
begin
  if AIndex <= Ord(facKeep) then
    Exit(facKeep);
  if AIndex >= Ord(facClear) then
    Exit(facClear);
  Result := TFileAttrChoice(AIndex);
end;

function FileAttrPlanIsNoOp(const APlan: TFileAttrPlan): Boolean;
begin
  Result := (APlan.ReadOnly = facKeep) and (APlan.Hidden = facKeep) and
    (APlan.System = facKeep) and (APlan.Archive = facKeep) and
    (APlan.Compressed = facKeep) and (APlan.Encrypted = facKeep) and
    (APlan.NotIndexed = facKeep) and (APlan.Sparse = facKeep) and
    (APlan.Temporary = facKeep) and (APlan.Offline = facKeep) and
    (APlan.Immutable = facKeep) and (APlan.AppendOnly = facKeep) and (APlan.NoDump = facKeep) and
    (not APlan.ChangeOwner) and (not APlan.ChangeGroup) and (not APlan.ChangeMode) and
    not (APlan.SetCreated or APlan.SetModified or APlan.SetAccessed);
end;

function FormatFileAttrTime(ATime: TDateTime): string;
begin
  if ATime = 0 then
    Exit('');
  Result := DateToStr(ATime) + ' ' + FormatDateTime('hh:nn:ss', ATime);
end;

function TryParseFileAttrTime(const AText: string; out ATime: TDateTime): Boolean;
var
  S: string;
begin
  S := Trim(AText);
  // FILETIME starts at 1601-01-01; a day of margin for the UTC shift.
  Result := (S <> '') and TryStrToDateTime(S, ATime) and
    (ATime >= EncodeDate(1601, 1, 2)) and (ATime < EncodeDate(9999, 12, 31));
end;

// Two items "have the same time" when the dialog would show the same text.
function MergeTime(ACur, AValue: TDateTime): TDateTime;
begin
  if FormatFileAttrTime(ACur) = FormatFileAttrTime(AValue) then
    Result := ACur
  else
    Result := 0;
end;

function MergeChoice(ACur: TFileAttrChoice; AValue: Boolean): TFileAttrChoice;
begin
  Result := ACur;
  case ACur of
    facSet:
      if not AValue then
        Result := facKeep;
    facClear:
      if AValue then
        Result := facKeep;
  else
    Result := facKeep;
  end;
end;

function ChoiceFromFlag(AValue: Boolean): TFileAttrChoice;
begin
  if AValue then
    Result := facSet
  else
    Result := facClear;
end;

function BuildFileAttrDialogState(const APaths: TArray<string>): TFileAttrDialogState;
var
  I: Integer;
  Snap: TFileAttrSnapshot;
  Err: string;
  First: Boolean;
begin
  Result := Default(TFileAttrDialogState);
  Result.ReadOnly := facKeep;
  Result.Hidden := facKeep;
  Result.System := facKeep;
  Result.Archive := facKeep;
  Result.Compressed := facKeep;
  Result.Encrypted := facKeep;
  Result.NotIndexed := facKeep;
  Result.Sparse := facKeep;
  Result.Temporary := facKeep;
  Result.Offline := facKeep;
  Result.Immutable := facKeep;
  Result.AppendOnly := facKeep;
  Result.NoDump := facKeep;
  Result.Owner := '';
  Result.OwnerMixed := False;
  Result.Mode := -1;
  if Length(APaths) = 0 then
  begin
    Result.Summary := 'No items';
    Exit;
  end;
  if Length(APaths) = 1 then
  begin
    Result.Summary := ExtractFileName(ExcludeTrailingPathDelimiter(APaths[0]));
    // A drive root has no file name: it is shown by its path, with its volume and device.
    if TryGetDriveRootInfo(APaths[0], Result.Volume, Result.Device) then
      Result.Summary := APaths[0];
    if Result.Summary = '' then
      Result.Summary := APaths[0];
  end
  else
    Result.Summary := Format('%d items', [Length(APaths)]);
  First := True;
  for I := 0 to High(APaths) do
  begin
    if not TryReadFileAttrSnapshot(APaths[I], Snap, Err) then
      Continue;
    if First then
    begin
      Result.ReadOnly := ChoiceFromFlag(Snap.ReadOnly);
      Result.Hidden := ChoiceFromFlag(Snap.Hidden);
      Result.System := ChoiceFromFlag(Snap.System);
      Result.Archive := ChoiceFromFlag(Snap.Archive);
      Result.Compressed := ChoiceFromFlag(Snap.Compressed);
      Result.Encrypted := ChoiceFromFlag(Snap.Encrypted);
      Result.NotIndexed := ChoiceFromFlag(Snap.NotIndexed);
      Result.Sparse := ChoiceFromFlag(Snap.Sparse);
      Result.Temporary := ChoiceFromFlag(Snap.Temporary);
      Result.Offline := ChoiceFromFlag(Snap.Offline);
      Result.Immutable := ChoiceFromFlag(Snap.Immutable);
      Result.AppendOnly := ChoiceFromFlag(Snap.AppendOnly);
      Result.NoDump := ChoiceFromFlag(Snap.NoDump);
      Result.Owner := Snap.Owner;
      Result.Mode := Snap.Mode;
      Result.Group := Snap.Group;
      Result.Times := Snap.Times;
      First := False;
    end
    else
    begin
      Result.ReadOnly := MergeChoice(Result.ReadOnly, Snap.ReadOnly);
      Result.Hidden := MergeChoice(Result.Hidden, Snap.Hidden);
      Result.System := MergeChoice(Result.System, Snap.System);
      Result.Archive := MergeChoice(Result.Archive, Snap.Archive);
      Result.Compressed := MergeChoice(Result.Compressed, Snap.Compressed);
      Result.Encrypted := MergeChoice(Result.Encrypted, Snap.Encrypted);
      Result.NotIndexed := MergeChoice(Result.NotIndexed, Snap.NotIndexed);
      Result.Sparse := MergeChoice(Result.Sparse, Snap.Sparse);
      Result.Temporary := MergeChoice(Result.Temporary, Snap.Temporary);
      Result.Offline := MergeChoice(Result.Offline, Snap.Offline);
      Result.Immutable := MergeChoice(Result.Immutable, Snap.Immutable);
      Result.AppendOnly := MergeChoice(Result.AppendOnly, Snap.AppendOnly);
      Result.NoDump := MergeChoice(Result.NoDump, Snap.NoDump);
      Result.Times.Created := MergeTime(Result.Times.Created, Snap.Times.Created);
      Result.Times.Modified := MergeTime(Result.Times.Modified, Snap.Times.Modified);
      Result.Times.Accessed := MergeTime(Result.Times.Accessed, Snap.Times.Accessed);
      if not SameText(Result.Owner, Snap.Owner) then
      begin
        Result.OwnerMixed := True;
        Result.Owner := '(mixed)';
      end;
    end;
  end;
  if First then
    Result.Summary := Result.Summary + ' (unreadable)';
end;

procedure CountOne(const APath: string; const APlan: TFileAttrPlan;
  var AOk, AFail: Integer; var AFirstFailPath, AFirstError: string);
var
  Err: string;
begin
  if ApplyFileAttrOne(APath, APlan, Err) then
    Inc(AOk)
  else
  begin
    Inc(AFail);
    if AFirstError = '' then
    begin
      AFirstFailPath := APath;
      AFirstError := Err;
    end;
  end;
end;

function ApplyFileAttrPlan(const APath: string; const APlan: TFileAttrPlan;
  out AError: string): Boolean;
var
  Ok, Fail: Integer;
  FirstPath: string;
begin
  Ok := 0;
  Fail := 0;
  FirstPath := '';
  AError := '';
  ApplyFileAttrRoots(TArray<string>.Create(APath), APlan, Ok, Fail, FirstPath,
    AError);
  Result := Fail = 0;
end;

procedure ApplyFileAttrRoots(const APaths: TArray<string>;
  const APlan: TFileAttrPlan; out AOk, AFail: Integer;
  out AFirstFailPath, AFirstError: string);
var
  Raw, Root, One: string;
  Files, Dirs: TArray<string>;
begin
  AOk := 0;
  AFail := 0;
  AFirstFailPath := '';
  AFirstError := '';
  for Raw in APaths do
  begin
    Root := ExcludeTrailingPathDelimiter(Raw);
    // 'F:' alone means the current folder of drive F: - a drive root keeps its backslash.
    if (Length(Root) = 2) and (Root[2] = ':') then
      Root := Root + PathDelim;
    if Root = '' then
    begin
      Inc(AFail);
      if AFirstError = '' then
      begin
        AFirstFailPath := Raw;
        AFirstError := 'Empty path';
      end;
      Continue;
    end;
    CountOne(Root, APlan, AOk, AFail, AFirstFailPath, AFirstError);
    if (not APlan.Recurse) or (not TDirectory.Exists(WinApiPath(Root))) then
      Continue;
    try
      Files := TDirectory.GetFiles(Root, '*', TSearchOption.soAllDirectories);
      Dirs := TDirectory.GetDirectories(Root, '*', TSearchOption.soAllDirectories);
    except
      on E: Exception do
      begin
        Inc(AFail);
        if AFirstError = '' then
        begin
          AFirstFailPath := Root;
          AFirstError := E.Message;
        end;
        Continue;
      end;
    end;
    for One in Files do
      CountOne(One, APlan, AOk, AFail, AFirstFailPath, AFirstError);
    for One in Dirs do
      CountOne(One, APlan, AOk, AFail, AFirstFailPath, AFirstError);
  end;
end;

end.
