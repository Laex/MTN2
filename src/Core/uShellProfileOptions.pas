unit uShellProfileOptions;

{ Per-profile console options kept in shellprofiles.json: copies of a shell
  profile (same shell, own settings), the order the profiles are listed in and
  who gets the keyboard - the program in the console or the host window. A
  copy has the id "<profile>#<N>"; its shell is the profile's (see
  NormalizeShellProfileId), its settings are its own. }

interface

type
  /// <summary>Who gets a key the host window also binds (F1, F9, Alt+letter
  /// menu keys, ...). Auto: the program while a full-screen application (mc,
  /// vim) is up in the console, the host otherwise.</summary>
  TProfileKeyMode = (pkmAuto, pkmProgram, pkmHost);

  TProfileEntry = record
    Id: string;
    Title: string;
    IsCopy: Boolean;
    KeyMode: TProfileKeyMode;
  end;
  TProfileEntries = TArray<TProfileEntry>;

function ProfileKeyMode(const AProfileId: string): TProfileKeyMode;
procedure SetProfileKeyMode(const AProfileId: string; AMode: TProfileKeyMode);
/// <summary>Auto -> Program -> Host -> Auto.</summary>
function NextProfileKeyMode(AMode: TProfileKeyMode): TProfileKeyMode;
function ProfileKeyModeTitle(AMode: TProfileKeyMode): string;

/// <summary>The available profiles and their copies in the saved order.</summary>
function ProfileEntriesOrdered: TProfileEntries;
/// <summary>New copy of the profile (or of the profile a copy was made from),
/// listed right after ASourceId and starting with its key mode; returns its
/// id, '' when ASourceId is empty.</summary>
function ProfileCopyAdd(const ASourceId: string): string;
/// <summary>Deletes a copy; False for a profile that is not a copy.</summary>
function ProfileCopyDelete(const AProfileId: string): Boolean;
/// <summary>Moves a listed profile ADelta places up (negative) or down in
/// the list ProfileEntriesOrdered returns; False at the end of the list.</summary>
function ProfileMove(const AProfileId: string; ADelta: Integer): Boolean;

/// <summary>Quick-launch key of the AIndex-th listed profile: 1-9, 0, then
/// A-Z; #0 beyond that.</summary>
function ProfileHotkeyChar(AIndex: Integer): Char;
/// <summary>The inverse of ProfileHotkeyChar (case-insensitive); -1 for a
/// character that is no quick-launch key.</summary>
function ProfileHotkeyIndex(AChar: Char): Integer;

/// <summary>Smallest unused "#N" (N >= 2) copy id of ABaseId.</summary>
function NextCopyProfileId(const ABaseId: string; const AUsedIds: TArray<string>): string;
/// <summary>AIds in the order of AOrder first, then the rest in their own
/// order.</summary>
function ApplyProfileOrder(const AIds, AOrder: TArray<string>): TArray<string>;

/// <summary>Points the settings file at APath and forgets what was loaded;
/// '' restores the default location.</summary>
procedure ShellProfileOptionsUsePath(const APath: string);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  System.Generics.Collections, System.Generics.Defaults, uConfigLocation,
  uShellProfiles, uStrings;

const
  cFileName = 'shellprofiles.json';

type
  TCopyRec = record
    Id: string;
    Name: string;
  end;

var
  GLoaded: Boolean = False;
  GPathOverride: string;
  GCopies: TList<TCopyRec>;
  GOrder: TList<string>;
  GModes: TDictionary<string, Integer>;

function StoragePath: string;
begin
  if GPathOverride <> '' then
    Exit(GPathOverride);
  Result := GetConfigFilePath(cFileName);
end;

function ModeName(AMode: TProfileKeyMode): string;
begin
  case AMode of
    pkmProgram: Result := 'program';
    pkmHost: Result := 'host';
  else
    Result := 'auto';
  end;
end;

function ModeFromName(const AName: string): TProfileKeyMode;
begin
  if SameText(AName, 'program') then
    Result := pkmProgram
  else if SameText(AName, 'host') then
    Result := pkmHost
  else
    Result := pkmAuto;
end;

procedure EnsureObjects;
begin
  if GCopies = nil then
    GCopies := TList<TCopyRec>.Create;
  if GOrder = nil then
    GOrder := TList<string>.Create;
  if GModes = nil then
    GModes := TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
end;

procedure Save;
var
  Root, Keys, Obj: TJSONObject;
  Arr: TJSONArray;
  Pair: TPair<string, Integer>;
  C: TCopyRec;
  S, Path: string;
begin
  EnsureObjects;
  Path := StoragePath;
  Root := TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(1));
    Arr := TJSONArray.Create;
    Root.AddPair('order', Arr);
    for S in GOrder do
      Arr.Add(S);
    Arr := TJSONArray.Create;
    Root.AddPair('copies', Arr);
    for C in GCopies do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('id', C.Id);
      Obj.AddPair('name', C.Name);
      Arr.AddElement(Obj);
    end;
    Keys := TJSONObject.Create;
    Root.AddPair('keys', Keys);
    for Pair in GModes do
      if TProfileKeyMode(Pair.Value) <> pkmAuto then
        Keys.AddPair(Pair.Key, ModeName(TProfileKeyMode(Pair.Value)));
    try
      ForceDirectories(ExtractFilePath(Path));
      TFile.WriteAllText(Path, Root.ToJSON, TEncoding.UTF8);
    except
      // An unwritable settings folder only loses persistence; the options
      // stay in effect for this run.
    end;
  finally
    Root.Free;
  end;
end;

procedure EnsureLoaded;
var
  Content, Id, Name: string;
  Val: TJSONValue;
  Root, Keys: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  C: TCopyRec;
  Pair: TJSONPair;
begin
  if GLoaded then
    Exit;
  GLoaded := True;
  EnsureObjects;
  GCopies.Clear;
  GOrder.Clear;
  GModes.Clear;
  if not TFile.Exists(StoragePath) then
    Exit;
  try
    Content := TFile.ReadAllText(StoragePath, TEncoding.UTF8);
    Val := TJSONObject.ParseJSONValue(Content);
    if not (Val is TJSONObject) then
    begin
      Val.Free;
      Exit;
    end;
    Root := TJSONObject(Val);
    try
      if Root.TryGetValue<TJSONArray>('order', Arr) then
        for I := 0 to Arr.Count - 1 do
          if (Arr.Items[I] is TJSONString) and (Arr.Items[I].Value <> '') then
            GOrder.Add(Arr.Items[I].Value);
      if Root.TryGetValue<TJSONArray>('copies', Arr) then
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONObject then
          begin
            Id := '';
            Name := '';
            TJSONObject(Arr.Items[I]).TryGetValue<string>('id', Id);
            TJSONObject(Arr.Items[I]).TryGetValue<string>('name', Name);
            if ShellProfileCopySuffix(Id) = '' then
              Continue;
            C.Id := Id;
            C.Name := Name;
            GCopies.Add(C);
          end;
      if Root.TryGetValue<TJSONObject>('keys', Keys) then
        for Pair in Keys do
          GModes.AddOrSetValue(Pair.JsonString.Value,
            Ord(ModeFromName(Pair.JsonValue.Value)));
    finally
      Root.Free;
    end;
  except
    GCopies.Clear;
    GOrder.Clear;
    GModes.Clear;
  end;
end;

function ProfileKeyMode(const AProfileId: string): TProfileKeyMode;
var
  V: Integer;
begin
  EnsureLoaded;
  if GModes.TryGetValue(CanonicalShellProfileId(AProfileId), V) then
    Result := TProfileKeyMode(V)
  else
    Result := pkmAuto;
end;

procedure SetProfileKeyMode(const AProfileId: string; AMode: TProfileKeyMode);
begin
  EnsureLoaded;
  GModes.AddOrSetValue(CanonicalShellProfileId(AProfileId), Ord(AMode));
  Save;
end;

function NextProfileKeyMode(AMode: TProfileKeyMode): TProfileKeyMode;
begin
  case AMode of
    pkmAuto: Result := pkmProgram;
    pkmProgram: Result := pkmHost;
  else
    Result := pkmAuto;
  end;
end;

function ProfileKeyModeTitle(AMode: TProfileKeyMode): string;
begin
  case AMode of
    pkmProgram: Result := T('ui.profileKeys.program', 'program');
    pkmHost: Result := T('ui.profileKeys.host', 'host');
  else
    Result := T('ui.profileKeys.auto', 'auto');
  end;
end;

function ApplyProfileOrder(const AIds, AOrder: TArray<string>): TArray<string>;
var
  Used: TDictionary<string, Boolean>;
  S, Id: string;
  List: TList<string>;
begin
  List := TList<string>.Create;
  Used := TDictionary<string, Boolean>.Create;
  try
    for S in AOrder do
      for Id in AIds do
        if SameText(Id, S) and not Used.ContainsKey(LowerCase(Id)) then
        begin
          Used.Add(LowerCase(Id), True);
          List.Add(Id);
        end;
    for Id in AIds do
      if not Used.ContainsKey(LowerCase(Id)) then
      begin
        Used.Add(LowerCase(Id), True);
        List.Add(Id);
      end;
    Result := List.ToArray;
  finally
    Used.Free;
    List.Free;
  end;
end;

function NextCopyProfileId(const ABaseId: string; const AUsedIds: TArray<string>): string;
var
  N: Integer;
  S: string;
  Taken: Boolean;
begin
  N := 2;
  repeat
    Result := ABaseId + '#' + IntToStr(N);
    Taken := False;
    for S in AUsedIds do
      if SameText(S, Result) then
        Taken := True;
    Inc(N);
  until not Taken;
end;

/// <summary>Every profile and copy, base profiles in their default order each
/// followed by its copies, with availability of the shell they run.</summary>
procedure CollectAll(out AIds, ATitles: TArray<string>; out AAvailable: TArray<Boolean>);
var
  Profiles: TShellProfileArray;
  P: TShellProfileInfo;
  C: TCopyRec;
  N: Integer;

  procedure Add(const AId, ATitle: string; AAvail: Boolean);
  begin
    N := Length(AIds);
    SetLength(AIds, N + 1);
    SetLength(ATitles, N + 1);
    SetLength(AAvailable, N + 1);
    AIds[N] := AId;
    ATitles[N] := ATitle;
    AAvailable[N] := AAvail;
  end;

begin
  SetLength(AIds, 0);
  SetLength(ATitles, 0);
  SetLength(AAvailable, 0);
  Profiles := EnumerateShellProfiles;
  for P in Profiles do
  begin
    Add(P.Id, P.Title, P.Available);
    for C in GCopies do
      if SameText(NormalizeShellProfileId(C.Id), P.Id) then
        Add(C.Id, C.Name, P.Available);
  end;
end;

function ProfileEntriesOrdered: TProfileEntries;
var
  Ids, Titles, Ordered: TArray<string>;
  Avail: TArray<Boolean>;
  I, J, N: Integer;
begin
  EnsureLoaded;
  CollectAll(Ids, Titles, Avail);
  Ordered := ApplyProfileOrder(Ids, GOrder.ToArray);
  SetLength(Result, 0);
  for I := 0 to High(Ordered) do
    for J := 0 to High(Ids) do
      if SameText(Ids[J], Ordered[I]) then
      begin
        if Avail[J] then
        begin
          N := Length(Result);
          SetLength(Result, N + 1);
          Result[N].Id := Ids[J];
          Result[N].Title := Titles[J];
          Result[N].IsCopy := ShellProfileCopySuffix(Ids[J]) <> '';
          Result[N].KeyMode := ProfileKeyMode(Ids[J]);
        end;
        Break;
      end;
end;

procedure StoreOrder(const AIds: TArray<string>);
var
  S: string;
begin
  GOrder.Clear;
  for S in AIds do
    GOrder.Add(S);
end;

function AllOrderedIds: TArray<string>;
var
  Ids, Titles: TArray<string>;
  Avail: TArray<Boolean>;
begin
  CollectAll(Ids, Titles, Avail);
  Result := ApplyProfileOrder(Ids, GOrder.ToArray);
end;

function ProfileCopyAdd(const ASourceId: string): string;
var
  Base, Title: string;
  Ids, Titles, Ordered, UsedIds: TArray<string>;
  Avail: TArray<Boolean>;
  C: TCopyRec;
  I, At: Integer;
  List: TList<string>;
begin
  Result := '';
  if Trim(ASourceId) = '' then
    Exit;
  EnsureLoaded;
  Base := NormalizeShellProfileId(ASourceId);
  CollectAll(Ids, Titles, Avail);
  UsedIds := Ids;
  Result := NextCopyProfileId(Base, UsedIds);
  Title := ShellProfileTitle(Base);
  for I := 0 to High(Ids) do
    if SameText(Ids[I], Base) then
      Title := Titles[I];
  C.Id := Result;
  C.Name := T('ui.shellProfiles.copyTitle', '%s (copy %s)',
    [Title, Copy(ShellProfileCopySuffix(Result), 2, MaxInt)]);
  GCopies.Add(C);

  Ordered := AllOrderedIds;
  List := TList<string>.Create;
  try
    List.AddRange(Ordered);
    At := -1;
    for I := 0 to List.Count - 1 do
      if SameText(List[I], ASourceId) or SameText(List[I], CanonicalShellProfileId(ASourceId)) then
        At := I;
    if At < 0 then
      List.Add(Result)
    else
      List.Insert(At + 1, Result);
    StoreOrder(List.ToArray);
  finally
    List.Free;
  end;
  // The copy starts with the settings of the profile it was made from.
  if ProfileKeyMode(ASourceId) <> pkmAuto then
    GModes.AddOrSetValue(Result, Ord(ProfileKeyMode(ASourceId)));
  Save;
end;

function ProfileCopyDelete(const AProfileId: string): Boolean;
var
  I: Integer;
  Id: string;
  Ordered: TArray<string>;
  List: TList<string>;
begin
  Result := False;
  EnsureLoaded;
  Id := CanonicalShellProfileId(AProfileId);
  if ShellProfileCopySuffix(Id) = '' then
    Exit;
  for I := GCopies.Count - 1 downto 0 do
    if SameText(GCopies[I].Id, Id) then
    begin
      GCopies.Delete(I);
      Result := True;
    end;
  if not Result then
    Exit;
  GModes.Remove(Id);
  List := TList<string>.Create;
  try
    Ordered := GOrder.ToArray;
    for I := 0 to High(Ordered) do
      if not SameText(Ordered[I], Id) then
        List.Add(Ordered[I]);
    StoreOrder(List.ToArray);
  finally
    List.Free;
  end;
  Save;
end;

function ProfileMove(const AProfileId: string; ADelta: Integer): Boolean;
var
  Listed: TProfileEntries;
  Ids, Rest: TArray<string>;
  All: TArray<string>;
  I, From, Target: Integer;
  Tmp: string;
  InListed: Boolean;
begin
  Result := False;
  EnsureLoaded;
  Listed := ProfileEntriesOrdered;
  From := -1;
  for I := 0 to High(Listed) do
    if SameText(Listed[I].Id, AProfileId) then
      From := I;
  Target := From + ADelta;
  if (From < 0) or (Target < 0) or (Target > High(Listed)) or (ADelta = 0) then
    Exit;
  SetLength(Ids, Length(Listed));
  for I := 0 to High(Listed) do
    Ids[I] := Listed[I].Id;
  Tmp := Ids[From];
  if Target > From then
    for I := From to Target - 1 do
      Ids[I] := Ids[I + 1]
  else
    for I := From downto Target + 1 do
      Ids[I] := Ids[I - 1];
  Ids[Target] := Tmp;
  // Profiles that are not listed (a shell that is not installed) keep their
  // place behind the listed ones.
  All := AllOrderedIds;
  SetLength(Rest, 0);
  for Tmp in All do
  begin
    InListed := False;
    for I := 0 to High(Ids) do
      if SameText(Ids[I], Tmp) then
        InListed := True;
    if not InListed then
      Rest := Rest + [Tmp];
  end;
  StoreOrder(Ids + Rest);
  Save;
  Result := True;
end;

function ProfileHotkeyChar(AIndex: Integer): Char;
begin
  if (AIndex >= 0) and (AIndex <= 8) then
    Result := Char(Ord('1') + AIndex)
  else if AIndex = 9 then
    Result := '0'
  else if (AIndex >= 10) and (AIndex <= 35) then
    Result := Char(Ord('A') + AIndex - 10)
  else
    Result := #0;
end;

function ProfileHotkeyIndex(AChar: Char): Integer;
begin
  AChar := UpCase(AChar);
  if (AChar >= '1') and (AChar <= '9') then
    Result := Ord(AChar) - Ord('1')
  else if AChar = '0' then
    Result := 9
  else if (AChar >= 'A') and (AChar <= 'Z') then
    Result := 10 + Ord(AChar) - Ord('A')
  else
    Result := -1;
end;

procedure ShellProfileOptionsUsePath(const APath: string);
begin
  GPathOverride := APath;
  GLoaded := False;
end;

initialization

finalization
  GCopies.Free;
  GOrder.Free;
  GModes.Free;

end.
