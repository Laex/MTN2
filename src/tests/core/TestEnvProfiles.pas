unit TestEnvProfiles;

{ uEnvProfiles: the environment profiles laid over a shell's environment and
  the environment.json file they come from. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEnvProfiles = class
  public
    [Test] procedure ValueIsSetAndAdded;
    [Test] procedure EmptyValueRemovesTheVariable;
    [Test] procedure LaterEntrySeesEarlierOne;
    [Test] procedure PercentReferenceIsExpanded;
    [Test] procedure UnknownPercentReferenceStaysAsWritten;
    [Test] procedure DisabledProfileIsIgnored;
    [Test] procedure ProfilesApplyInFileOrder;
    [Test] procedure EntryWithoutNameIsSkipped;
    [Test] procedure ValueMayContainEquals;
    [Test] procedure DollarReferenceIsExpandedOnPosix;
    [Test] procedure ProfilesComeBackFromTheFile;
    [Test] procedure MissingOrBrokenFileMeansNoProfiles;
    [Test] procedure ExampleFileIsCreatedOnce;
    [Test] procedure ExampleFileChangesNothing;
    [Test] procedure ProfileLimitedToShellsSkipsOthers;
    [Test] procedure FamilyAndBaseIdCoverMoreShells;
    [Test] procedure NamedProfileAppliesWhateverItsAutoFlag;
    [Test] procedure ShellListSurvivesTheFile;
    [Test] procedure OffProfileAppliesNowhere;
    [Test] procedure DefaultProfileComesFirstAndNeverNamed;
    [Test] procedure OlderEnabledSpellingIsRead;
    [Test] procedure NamesOfferedForChoiceSkipDefaultAndOff;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, uConfigLocation, uEnvProfiles;

function Profile(const AName: string; AEnabled: Boolean;
  const AVars: array of string): TEnvProfile;
var
  I: Integer;
begin
  Result := Default(TEnvProfile);
  Result.Name := AName;
  Result.Auto := AEnabled;
  SetLength(Result.Vars, Length(AVars));
  for I := 0 to High(AVars) do
    Result.Vars[I] := AVars[I];
end;

function OffProfile(AProfile: TEnvProfile): TEnvProfile;
begin
  Result := AProfile;
  Result.Off := True;
end;

function Apply(const ABase: array of string; const AProfiles: array of TEnvProfile): TArray<string>;
var
  Base: TArray<string>;
  Profiles: TEnvProfiles;
  I: Integer;
begin
  SetLength(Base, Length(ABase));
  for I := 0 to High(ABase) do
    Base[I] := ABase[I];
  SetLength(Profiles, Length(AProfiles));
  for I := 0 to High(AProfiles) do
    Profiles[I] := AProfiles[I];
  Result := ApplyEnvProfiles(Base, Profiles);
end;

function ValueOf(const AEnv: TArray<string>; const AName: string): string;
var
  Entry: string;
begin
  Result := '<unset>';
  for Entry in AEnv do
    if Entry.StartsWith(AName + '=') then
      Exit(Copy(Entry, Length(AName) + 2, MaxInt));
end;

function TempFile: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'mtn2-env-' +
    IntToStr(Random(MaxInt))), 'environment.json');
end;

procedure TTestEnvProfiles.ValueIsSetAndAdded;
var
  Env: TArray<string>;
begin
  Env := Apply(['A=1', 'B=2'], [Profile('p', True, ['A=10', 'C=3'])]);
  Assert.AreEqual('10', ValueOf(Env, 'A'));
  Assert.AreEqual('2', ValueOf(Env, 'B'));
  Assert.AreEqual('3', ValueOf(Env, 'C'));
  Assert.AreEqual(3, Integer(Length(Env)));
end;

procedure TTestEnvProfiles.EmptyValueRemovesTheVariable;
var
  Env: TArray<string>;
begin
  Env := Apply(['A=1', 'B=2'], [Profile('p', True, ['A='])]);
  Assert.AreEqual('<unset>', ValueOf(Env, 'A'));
  Assert.AreEqual('2', ValueOf(Env, 'B'));
end;

procedure TTestEnvProfiles.LaterEntrySeesEarlierOne;
var
  Env: TArray<string>;
begin
  Env := Apply([], [Profile('p', True, ['ROOT=base', 'HOME2=%ROOT%/x'])]);
  Assert.AreEqual('base/x', ValueOf(Env, 'HOME2'));
end;

procedure TTestEnvProfiles.PercentReferenceIsExpanded;
var
  Env: TArray<string>;
begin
  Env := Apply(['PATH=/usr/bin'], [Profile('p', True, ['PATH=/opt/tools;%PATH%'])]);
  Assert.AreEqual('/opt/tools;/usr/bin', ValueOf(Env, 'PATH'));
end;

procedure TTestEnvProfiles.UnknownPercentReferenceStaysAsWritten;
begin
  Assert.AreEqual('a%NOPE%b', ExpandEnvValue('a%NOPE%b', ['X=1']));
  Assert.AreEqual('100%', ExpandEnvValue('100%', ['X=1']));
end;

procedure TTestEnvProfiles.DisabledProfileIsIgnored;
var
  Env: TArray<string>;
begin
  Env := Apply(['A=1'], [OffProfile(Profile('off', True, ['A=2', 'B=3']))]);
  Assert.AreEqual('1', ValueOf(Env, 'A'));
  Assert.AreEqual('<unset>', ValueOf(Env, 'B'));
end;

procedure TTestEnvProfiles.ProfilesApplyInFileOrder;
var
  Env: TArray<string>;
begin
  Env := Apply([], [Profile('first', True, ['A=1']), Profile('second', True, ['A=%A%2'])]);
  Assert.AreEqual('12', ValueOf(Env, 'A'));
end;

procedure TTestEnvProfiles.EntryWithoutNameIsSkipped;
var
  Env: TArray<string>;
begin
  Env := Apply(['A=1'], [Profile('p', True, ['no equals sign', '=value', 'B=2'])]);
  Assert.AreEqual(2, Integer(Length(Env)));
  Assert.AreEqual('2', ValueOf(Env, 'B'));
end;

procedure TTestEnvProfiles.ValueMayContainEquals;
var
  Env: TArray<string>;
begin
  Env := Apply([], [Profile('p', True, ['OPTS=--level=3'])]);
  Assert.AreEqual('--level=3', ValueOf(Env, 'OPTS'));
end;

procedure TTestEnvProfiles.DollarReferenceIsExpandedOnPosix;
begin
{$IFDEF MSWINDOWS}
  Assert.AreEqual('$X and ${X}', ExpandEnvValue('$X and ${X}', ['X=1']),
    'the dollar form is not a variable reference on Windows');
{$ELSE}
  Assert.AreEqual('1 and 1 and ', ExpandEnvValue('$X and ${X} and $NOPE', ['X=1']));
  Assert.AreEqual('cost $5', ExpandEnvValue('cost $5', ['X=1']));
{$ENDIF}
end;

procedure TTestEnvProfiles.ProfilesComeBackFromTheFile;
var
  Path: string;
  Back: TEnvProfiles;
begin
  Path := TempFile;
  try
    Assert.IsTrue(SaveEnvProfiles(Path, [Profile('work', True, ['A=1', 'B=%A%/x']),
      Profile('off', False, ['C='])]));
    Back := LoadEnvProfiles(Path);
    Assert.AreEqual(2, Integer(Length(Back)));
    Assert.AreEqual('work', Back[0].Name);
    Assert.IsTrue(Back[0].Auto);
    Assert.AreEqual('B=%A%/x', Back[0].Vars[1]);
    Assert.AreEqual('off', Back[1].Name);
    Assert.IsFalse(Back[1].Auto);
  finally
    TDirectory.Delete(ExtractFilePath(Path), True);
  end;
end;

procedure TTestEnvProfiles.MissingOrBrokenFileMeansNoProfiles;
var
  Path: string;
begin
  Path := TempFile;
  Assert.AreEqual(0, Integer(Length(LoadEnvProfiles(Path))), 'missing file');
  ForceDirectories(ExtractFilePath(Path));
  try
    TFile.WriteAllText(Path, '{ this is not json', TEncoding.UTF8);
    Assert.AreEqual(0, Integer(Length(LoadEnvProfiles(Path))), 'broken file');
    TFile.WriteAllText(Path, '{"profiles": 5}', TEncoding.UTF8);
    Assert.AreEqual(0, Integer(Length(LoadEnvProfiles(Path))), 'wrong type');
  finally
    TDirectory.Delete(ExtractFilePath(Path), True);
  end;
end;

procedure TTestEnvProfiles.ExampleFileIsCreatedOnce;
var
  Path: string;
  Back: TEnvProfiles;
begin
  Path := TempFile;
  try
    Assert.IsTrue(EnsureEnvProfilesFile(Path));
    Assert.IsTrue(TFile.Exists(Path));
    TFile.WriteAllText(Path, '{"profiles": []}', TEncoding.UTF8);
    Assert.IsTrue(EnsureEnvProfilesFile(Path));
    Back := LoadEnvProfiles(Path);
    Assert.AreEqual(0, Integer(Length(Back)), 'an existing file is not overwritten');
  finally
    TDirectory.Delete(ExtractFilePath(Path), True);
  end;
end;

procedure TTestEnvProfiles.ExampleFileChangesNothing;
var
  Path: string;
  Back: TEnvProfiles;
  Env: TArray<string>;
begin
  Path := TempFile;
  try
    Assert.IsTrue(EnsureEnvProfilesFile(Path));
    Back := LoadEnvProfiles(Path);
    Assert.AreEqual(1, Integer(Length(Back)));
    Assert.IsFalse(Back[0].Auto, 'the example profile applies only where it is named');
    Env := ApplyEnvProfiles(['A=1'], SelectEnvProfiles(Back, 'pwsh', ''));
    Assert.AreEqual(1, Integer(Length(Env)));
  finally
    TDirectory.Delete(ExtractFilePath(Path), True);
  end;
end;

function ProfilesNamed(const ANames: TArray<string>): TEnvProfiles;
var
  I: Integer;
begin
  SetLength(Result, Length(ANames));
  for I := 0 to High(ANames) do
    Result[I].Name := ANames[I];
end;

function Names(const AProfiles: TEnvProfiles): string;
var
  P: TEnvProfile;
begin
  Result := '';
  for P in AProfiles do
    Result := Result + P.Name + ';';
end;

function ProfileFor(const AName: string; AEnabled: Boolean;
  const AShells: array of string): TEnvProfile;
var
  I: Integer;
begin
  Result := Profile(AName, AEnabled, ['A=1']);
  SetLength(Result.Shells, Length(AShells));
  for I := 0 to High(AShells) do
    Result.Shells[I] := AShells[I];
end;

procedure TTestEnvProfiles.ProfileLimitedToShellsSkipsOthers;
var
  All: TEnvProfiles;
begin
  All := [ProfileFor('everywhere', True, []), ProfileFor('onlyps', True, ['pwsh'])];
  Assert.AreEqual('everywhere;onlyps;', Names(SelectEnvProfiles(All, 'pwsh', '')));
  Assert.AreEqual('everywhere;', Names(SelectEnvProfiles(All, 'cmd', '')));
  Assert.AreEqual('everywhere;', Names(SelectEnvProfiles(All, '', '')),
    'a run without a shell profile gets the unlimited ones');
end;

procedure TTestEnvProfiles.FamilyAndBaseIdCoverMoreShells;
var
  All: TEnvProfiles;
begin
  All := [ProfileFor('wslall', True, ['wsl']), ProfileFor('ubuntu', True, ['wsl:Ubuntu']),
    ProfileFor('copy', True, ['pwsh#2'])];
  Assert.AreEqual('wslall;ubuntu;', Names(SelectEnvProfiles(All, 'wsl:Ubuntu', '')));
  Assert.AreEqual('wslall;', Names(SelectEnvProfiles(All, 'wsl:Debian', '')));
  Assert.AreEqual('copy;', Names(SelectEnvProfiles(All, 'pwsh#2', '')));
  Assert.AreEqual('', Names(SelectEnvProfiles(All, 'pwsh', '')),
    'a profile limited to one copy does not apply to the base profile');
  All := [ProfileFor('base', True, ['pwsh'])];
  Assert.AreEqual('base;', Names(SelectEnvProfiles(All, 'pwsh#3', '')),
    'the base id covers its copies');
end;

procedure TTestEnvProfiles.NamedProfileAppliesWhateverItsAutoFlag;
var
  All: TEnvProfiles;
begin
  All := [ProfileFor('on', True, []), ProfileFor('manual', False, ['wsl'])];
  Assert.AreEqual('manual;', Names(SelectEnvProfiles(All, 'cmd', 'manual')),
    'the named profile is used as is, ignoring its auto flag and shell list');
  Assert.AreEqual('', Names(SelectEnvProfiles(All, 'cmd', 'missing')),
    'an unknown name adds nothing and the auto profiles do not apply either');
end;

procedure TTestEnvProfiles.ShellListSurvivesTheFile;
var
  Path: string;
  Back: TEnvProfiles;
begin
  Path := TempFile;
  try
    Assert.IsTrue(SaveEnvProfiles(Path, [ProfileFor('a', True, ['pwsh', 'wsl:Ubuntu']),
      ProfileFor('b', True, [])]));
    Back := LoadEnvProfiles(Path);
    Assert.AreEqual(2, Integer(Length(Back[0].Shells)));
    Assert.AreEqual('wsl:Ubuntu', Back[0].Shells[1]);
    Assert.AreEqual(0, Integer(Length(Back[1].Shells)));
  finally
    TDirectory.Delete(ExtractFilePath(Path), True);
  end;
end;

procedure TTestEnvProfiles.OffProfileAppliesNowhere;
var
  All: TEnvProfiles;
begin
  All := [OffProfile(ProfileFor('x', True, [])), OffProfile(ProfileFor('default', True, []))];
  Assert.AreEqual('', Names(SelectEnvProfiles(All, 'cmd', '')));
  Assert.AreEqual('', Names(SelectEnvProfiles(All, 'cmd', 'x')), 'not even where it is named');
end;

procedure TTestEnvProfiles.DefaultProfileComesFirstAndNeverNamed;
var
  All: TEnvProfiles;
begin
  All := [ProfileFor('auto1', True, []), ProfileFor('default', False, []),
    ProfileFor('manual', False, [])];
  Assert.AreEqual('default;auto1;', Names(SelectEnvProfiles(All, 'cmd', '')),
    'default applies although it is not auto, and goes before the others');
  Assert.AreEqual('default;manual;', Names(SelectEnvProfiles(All, 'cmd', 'manual')),
    'a named profile comes on top of default');
  Assert.AreEqual('default;', Names(SelectEnvProfiles(All, 'cmd', 'default')),
    'naming default adds nothing to it');
  All := [ProfileFor('default', True, ['pwsh'])];
  Assert.AreEqual('', Names(SelectEnvProfiles(All, 'cmd', '')),
    'default keeps its shell list');
end;

procedure TTestEnvProfiles.OlderEnabledSpellingIsRead;
var
  Path: string;
  Back: TEnvProfiles;
begin
  Path := TempFile;
  ForceDirectories(ExtractFilePath(Path));
  try
    TFile.WriteAllText(Path, '{"profiles":[{"name":"a","enabled":false,"vars":["A=1"]},' +
      '{"name":"b","auto":false,"enabled":true,"vars":[]},{"name":"c","vars":[]},' +
      '{"name":"d","off":true,"vars":[]}]}', TEncoding.UTF8);
    Back := LoadEnvProfiles(Path);
    Assert.AreEqual(4, Integer(Length(Back)));
    Assert.IsFalse(Back[0].Auto, 'enabled false');
    Assert.IsFalse(Back[1].Auto, 'auto wins over enabled');
    Assert.IsTrue(Back[2].Auto, 'auto by default');
    Assert.IsFalse(Back[2].Off);
    Assert.IsTrue(Back[3].Off);
  finally
    TDirectory.Delete(ExtractFilePath(Path), True);
  end;
end;

procedure TTestEnvProfiles.NamesOfferedForChoiceSkipDefaultAndOff;
var
  Dir, Prev: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-envnames-' + IntToStr(Random(MaxInt)));
  ForceDirectories(Dir);
  Prev := ConfigDirectoryOverride;
  SetConfigDirectoryOverride(Dir);
  try
    Assert.AreEqual(0, Integer(Length(EnvProfileNames)), 'no file, no names');
    Assert.IsTrue(SaveEnvProfiles(DefaultEnvProfilesPath, [Profile('default', True, ['A=1']),
      Profile('one', True, ['A=1']), OffProfile(Profile('gone', True, ['A=2'])),
      Profile('two', False, ['A=2'])]));
    Assert.AreEqual('one;two;', Names(ProfilesNamed(EnvProfileNames)));
  finally
    SetConfigDirectoryOverride(Prev);
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEnvProfiles);

end.
