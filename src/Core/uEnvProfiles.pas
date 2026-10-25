unit uEnvProfiles;

{ Environment profiles: named, ordered lists of NAME=value entries from
  <config>\environment.json that are laid over the environment of every shell
  the program starts (terminal tabs and the command-line console).

  The file holds a "profiles" array; each profile has a "name", a "vars" array
  of "NAME=value" strings and these optional settings:
    "auto"    true (the default; "enabled" is the older spelling): the profile
              applies by itself to every shell it is meant for; false: it
              applies only to a shell profile that names it
    "shells"  the shell profile ids it is meant for; empty = every shell
    "off"     true switches the profile off altogether, even where it is named

  The profile called "default" applies to every shell it is meant for (unless
  it is off), first. A shell profile that names a profile gets default plus
  that one; any other shell gets default plus the "auto" profiles meant for it.

  Profiles apply in file order, entries in list order, so a later entry sees
  the result of an earlier one. An entry with an empty value removes the
  variable. %NAME% is replaced by the variable's current value on every
  platform; $NAME and the braced form too on POSIX. A %NAME% that names no variable
  is left as written. The file is re-read when its time stamp changes, so a
  shell started after an edit sees the edit and running shells keep their
  environment. A missing or corrupt file means no profiles. }

interface

type
  TEnvProfile = record
    Name: string;
    /// <summary>Applies by itself; False = only where a shell profile names it.</summary>
    Auto: Boolean;
    /// <summary>Switched off: applies nowhere, not even where it is named.</summary>
    Off: Boolean;
    /// <summary>NAME=value entries, applied in order.</summary>
    Vars: TArray<string>;
    /// <summary>Shell profile ids the profile is meant for ("pwsh", "wsl",
    /// "wsl:Ubuntu", a copy's "pwsh#2"); empty = every shell. A bare family
    /// name such as "wsl" also covers "wsl:Ubuntu", and a base id covers its
    /// copies.</summary>
    Shells: TArray<string>;
  end;

  TEnvProfiles = TArray<TEnvProfile>;

function DefaultEnvProfilesPath: string;

/// <summary>Empty when the file is missing or unreadable.</summary>
function LoadEnvProfiles(const APath: string): TEnvProfiles;
function SaveEnvProfiles(const APath: string; const AProfiles: TEnvProfiles): Boolean;

/// <summary>Writes a commented-out example file when APath does not exist yet;
/// True when the file exists afterwards.</summary>
function EnsureEnvProfilesFile(const APath: string): Boolean;

/// <summary>The text of AValue with the variable references replaced by their
/// values in AEnv (NAME=value entries).</summary>
function ExpandEnvValue(const AValue: string; const AEnv: TArray<string>): string;

/// <summary>ABase (NAME=value entries) with the enabled profiles applied.
/// Names are compared without case on Windows only.</summary>
function ApplyEnvProfiles(const ABase: TArray<string>;
  const AProfiles: TEnvProfiles): TArray<string>;

/// <summary>The profiles that apply to the shell AShellId: "default", then the
/// one named ANamed (whatever its "auto") when a name is given, else every
/// "auto" profile meant for the shell. Profiles that are off never apply.</summary>
function SelectEnvProfiles(const AProfiles: TEnvProfiles; const AShellId,
  ANamed: string): TEnvProfiles;

/// <summary>Names of the profiles in the default file that can be named by a
/// shell profile: in file order, without "default" and the ones that are off.</summary>
function EnvProfileNames: TArray<string>;

/// <summary>ABase with the profiles of the default file that apply to the
/// shell AShellId (see SelectEnvProfiles) applied; ABase itself when none
/// does.</summary>
function ShellEnvironment(const ABase: TArray<string>; const AShellId: string = '';
  const ANamed: string = ''): TArray<string>;

implementation

uses
  System.SysUtils, System.StrUtils, System.IOUtils, System.JSON,
  System.Generics.Collections, uConfigLocation, uShellProfiles;

const
  cEnvProfilesFile = 'environment.json';
  cDefaultProfileName = 'default';

function NamesEqual(const A, B: string): Boolean;
begin
{$IFDEF MSWINDOWS}
  Result := SameText(A, B);
{$ELSE}
  Result := A = B;
{$ENDIF}
end;

function EntryName(const AEntry: string): string;
var
  P: Integer;
begin
  // A leading '=' belongs to the name (Windows keeps per-drive folders as =C:).
  P := Pos('=', Copy(AEntry, 2, MaxInt));
  if P = 0 then
    Result := AEntry
  else
    Result := Copy(AEntry, 1, P);
end;

function EntryValue(const AEntry: string): string;
begin
  Result := Copy(AEntry, Length(EntryName(AEntry)) + 2, MaxInt);
end;

function FindEntry(const AEnv: TArray<string>; const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AEnv) do
    if NamesEqual(EntryName(AEnv[I]), AName) then
      Exit(I);
  Result := -1;
end;

function LookupEnv(const AEnv: TArray<string>; const AName: string;
  out AValue: string): Boolean;
var
  I: Integer;
begin
  I := FindEntry(AEnv, AName);
  Result := I >= 0;
  if Result then
    AValue := EntryValue(AEnv[I])
  else
    AValue := '';
end;

function IsNameChar(C: Char; AFirst: Boolean): Boolean;
begin
  Result := (C = '_') or ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z'));
  if not Result and not AFirst then
    Result := (C >= '0') and (C <= '9');
end;

function ExpandEnvValue(const AValue: string; const AEnv: TArray<string>): string;
var
  I, J: Integer;
  Name, Val: string;
begin
  Result := '';
  I := 1;
  while I <= Length(AValue) do
  begin
    if AValue[I] = '%' then
    begin
      J := PosEx('%', AValue, I + 1);
      if J > I + 1 then
      begin
        Name := Copy(AValue, I + 1, J - I - 1);
        if LookupEnv(AEnv, Name, Val) then
        begin
          Result := Result + Val;
          I := J + 1;
          Continue;
        end;
      end;
    end
{$IFNDEF MSWINDOWS}
    else if (AValue[I] = '$') and (I < Length(AValue)) then
    begin
      if AValue[I + 1] = '{' then
      begin
        J := PosEx('}', AValue, I + 2);
        if J > I + 2 then
        begin
          LookupEnv(AEnv, Copy(AValue, I + 2, J - I - 2), Val);
          Result := Result + Val;
          I := J + 1;
          Continue;
        end;
      end
      else if IsNameChar(AValue[I + 1], True) then
      begin
        J := I + 1;
        while (J <= Length(AValue)) and IsNameChar(AValue[J], False) do
          Inc(J);
        LookupEnv(AEnv, Copy(AValue, I + 1, J - I - 1), Val);
        Result := Result + Val;
        I := J;
        Continue;
      end;
    end
{$ENDIF}
    ;
    Result := Result + AValue[I];
    Inc(I);
  end;
end;

function ApplyEnvProfiles(const ABase: TArray<string>;
  const AProfiles: TEnvProfiles): TArray<string>;
var
  List: TList<string>;
  Prof: TEnvProfile;
  Entry, Name, Val: string;
  I, P: Integer;
  Cur: TArray<string>;
begin
  List := TList<string>.Create;
  try
    List.AddRange(ABase);
    for Prof in AProfiles do
    begin
      if Prof.Off then
        Continue;
      for Entry in Prof.Vars do
      begin
        P := Pos('=', Copy(Entry, 2, MaxInt));
        if P = 0 then
          Continue;
        Name := Trim(Copy(Entry, 1, P));
        if Name = '' then
          Continue;
        Cur := List.ToArray;
        Val := ExpandEnvValue(Copy(Entry, P + 2, MaxInt), Cur);
        I := FindEntry(Cur, Name);
        if Val = '' then
        begin
          if I >= 0 then
            List.Delete(I);
        end
        else if I >= 0 then
          List[I] := EntryName(Cur[I]) + '=' + Val
        else
          List.Add(Name + '=' + Val);
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function DefaultEnvProfilesPath: string;
begin
  Result := GetConfigFilePath(cEnvProfilesFile);
end;

function LoadEnvProfiles(const APath: string): TEnvProfiles;
var
  RootVal: TJSONValue;
  Arr: TJSONArray;
  Item, VarsVal: TJSONValue;
  Vars: TJSONArray;
  Prof: TEnvProfile;
  I: Integer;
begin
  Result := nil;
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
  try
    RootVal := TJSONObject.ParseJSONValue(TFile.ReadAllText(APath, TEncoding.UTF8));
  except
    Exit;
  end;
  try
    if not (RootVal is TJSONObject) then
      Exit;
    if not TJSONObject(RootVal).TryGetValue<TJSONArray>('profiles', Arr) then
      Exit;
    for Item in Arr do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Prof := Default(TEnvProfile);
      Prof.Name := TJSONObject(Item).GetValue<string>('name', '');
      Prof.Auto := TJSONObject(Item).GetValue<Boolean>('enabled', True);
      Prof.Auto := TJSONObject(Item).GetValue<Boolean>('auto', Prof.Auto);
      Prof.Off := TJSONObject(Item).GetValue<Boolean>('off', False);
      VarsVal := TJSONObject(Item).GetValue('shells');
      if VarsVal is TJSONArray then
        for I := 0 to TJSONArray(VarsVal).Count - 1 do
          if TJSONArray(VarsVal).Items[I] is TJSONString then
          begin
            SetLength(Prof.Shells, Length(Prof.Shells) + 1);
            Prof.Shells[High(Prof.Shells)] := TJSONArray(VarsVal).Items[I].Value;
          end;
      VarsVal := TJSONObject(Item).GetValue('vars');
      if VarsVal is TJSONArray then
      begin
        Vars := TJSONArray(VarsVal);
        for I := 0 to Vars.Count - 1 do
          if Vars.Items[I] is TJSONString then
          begin
            SetLength(Prof.Vars, Length(Prof.Vars) + 1);
            Prof.Vars[High(Prof.Vars)] := Vars.Items[I].Value;
          end;
      end;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Prof;
    end;
  finally
    RootVal.Free;
  end;
end;

function SaveEnvProfiles(const APath: string; const AProfiles: TEnvProfiles): Boolean;
var
  Root, Obj: TJSONObject;
  Arr, Vars: TJSONArray;
  Prof: TEnvProfile;
  Entry, Dir: string;
begin
  Result := False;
  Root := TJSONObject.Create;
  try
    try
      Arr := TJSONArray.Create;
      Root.AddPair('profiles', Arr);
      for Prof in AProfiles do
      begin
        Obj := TJSONObject.Create;
        Arr.AddElement(Obj);
        Obj.AddPair('name', Prof.Name);
        Obj.AddPair('auto', TJSONBool.Create(Prof.Auto));
        if Prof.Off then
          Obj.AddPair('off', TJSONBool.Create(True));
        if Length(Prof.Shells) > 0 then
        begin
          Vars := TJSONArray.Create;
          Obj.AddPair('shells', Vars);
          for Entry in Prof.Shells do
            Vars.Add(Entry);
        end;
        Vars := TJSONArray.Create;
        Obj.AddPair('vars', Vars);
        for Entry in Prof.Vars do
          Vars.Add(Entry);
      end;
      Dir := ExtractFilePath(APath);
      if Dir <> '' then
        ForceDirectories(Dir);
      TFile.WriteAllText(APath, Root.Format(2), TEncoding.UTF8);
      Result := True;
    except
      { leave Result = False }
    end;
  finally
    Root.Free;
  end;
end;

function EnsureEnvProfilesFile(const APath: string): Boolean;
var
  Sample: TEnvProfiles;
begin
  if TFile.Exists(APath) then
    Exit(True);
  SetLength(Sample, 1);
  Sample[0].Name := 'example';
  Sample[0].Auto := False;
  Sample[0].Shells := ['pwsh', 'wsl'];
  Sample[0].Vars := ['EXAMPLE_VARIABLE=value', 'EXAMPLE_PATH=%PATH%', 'EXAMPLE_REMOVED='];
  Result := SaveEnvProfiles(APath, Sample);
end;

var
  GPath: string;
  GStamp: TDateTime;
  GProfiles: TEnvProfiles;
  GLoaded: Boolean;

function CurrentProfiles: TEnvProfiles;
var
  Path: string;
  Stamp: TDateTime;
begin
  Path := DefaultEnvProfilesPath;
  if TFile.Exists(Path) then
    Stamp := TFile.GetLastWriteTime(Path)
  else
    Stamp := 0;
  if not GLoaded or (Stamp <> GStamp) or (Path <> GPath) then
  begin
    GProfiles := LoadEnvProfiles(Path);
    GStamp := Stamp;
    GPath := Path;
    GLoaded := True;
  end;
  Result := GProfiles;
end;

function ShellCovers(const AEntry, AShellId: string): Boolean;
var
  Base, Family: string;
begin
  Base := AShellId;
  Base := Copy(Base, 1, Length(Base) - Length(ShellProfileCopySuffix(Base)));
  Family := Copy(Base, 1, Pos(':', Base + ':') - 1);
  Result := SameText(AEntry, AShellId) or SameText(AEntry, Base) or
    SameText(AEntry, Family);
end;

function IsDefaultProfile(const AProfile: TEnvProfile): Boolean;
begin
  Result := SameText(AProfile.Name, cDefaultProfileName);
end;

function MeantFor(const AProfile: TEnvProfile; const AShellId: string): Boolean;
var
  Entry: string;
begin
  Result := Length(AProfile.Shells) = 0;
  for Entry in AProfile.Shells do
    if ShellCovers(Entry, AShellId) then
      Result := True;
end;

function SelectEnvProfiles(const AProfiles: TEnvProfiles; const AShellId,
  ANamed: string): TEnvProfiles;
var
  Prof: TEnvProfile;
begin
  Result := nil;
  for Prof in AProfiles do
    if not Prof.Off and IsDefaultProfile(Prof) and MeantFor(Prof, AShellId) then
      Result := Result + [Prof];
  for Prof in AProfiles do
  begin
    if Prof.Off or IsDefaultProfile(Prof) then
      Continue;
    if ANamed <> '' then
    begin
      if SameText(Prof.Name, ANamed) then
        Result := Result + [Prof];
    end
    else if Prof.Auto and MeantFor(Prof, AShellId) then
      Result := Result + [Prof];
  end;
end;

function EnvProfileNames: TArray<string>;
var
  Prof: TEnvProfile;
begin
  Result := nil;
  for Prof in CurrentProfiles do
    if (Prof.Name <> '') and not Prof.Off and not IsDefaultProfile(Prof) then
      Result := Result + [Prof.Name];
end;

function ShellEnvironment(const ABase: TArray<string>; const AShellId: string;
  const ANamed: string): TArray<string>;
var
  Chosen: TEnvProfiles;
  P: TEnvProfile;
  Any: Boolean;
begin
  Chosen := SelectEnvProfiles(CurrentProfiles, AShellId, ANamed);
  Any := False;
  for P in Chosen do
    if Length(P.Vars) > 0 then
      Any := True;
  if Any then
    Result := ApplyEnvProfiles(ABase, Chosen)
  else
    Result := ABase;
end;

end.
