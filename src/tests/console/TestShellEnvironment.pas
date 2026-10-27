unit TestShellEnvironment;

{ A shell started while an environment profile applies sees the profile's
  variables (uEnvProfiles through uConPty): the enabled profiles, those
  limited to the shell, or the one a shell profile (copy) names. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestShellEnvironment = class
  public
    [Test] procedure EnabledProfileReachesTheShell;
    [Test] procedure DisabledProfileDoesNotReachTheShell;
    [Test] procedure ProfileLimitedToAnotherShellDoesNotReachTheShell;
    [Test] procedure NamedProfileOfAShellCopyAddsToDefaultOnly;
    [Test] procedure DefaultProfileReachesEveryShell;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, uPlatformPaths, uConPty,
  uConfigLocation, uEnvProfiles, uShellProfileOptions;

const
  cVarName = 'MTN2_PROFILE_TEST';
  cVarValue = 'profile-value-7431';

function WaitUntil(const APredicate: TFunc<Boolean>; ATimeoutMs: Integer): Boolean;
var
  Waited: Integer;
begin
  Waited := 0;
  while not APredicate() and (Waited < ATimeoutMs) do
  begin
    CheckSynchronize(20);
    Inc(Waited, 20);
  end;
  Result := APredicate();
end;

function BaseShell: string;
begin
  if PlatformPosixPaths then
    Result := 'sh'
  else
    Result := 'cmd';
end;

function Profile(const AName: string; AEnabled: Boolean; const AValue: string;
  const AShells: TArray<string>): TEnvProfile;
begin
  Result := Default(TEnvProfile);
  Result.Name := AName;
  Result.Auto := AEnabled;
  Result.Vars := [cVarName + '=' + AValue];
  Result.Shells := AShells;
end;

// Starts the shell AShellId in a scratch settings folder holding AProfiles
// (and the environment name AEnvName for AShellId), runs `echo` of the
// profile variable and returns the shell's output once it has answered.
function ShellEchoOfVariable(const AShellId, AEnvName: string;
  const AProfiles: TEnvProfiles): string;
var
  Dir, Output, Cmd, Prev: string;
  S: TConPtySession;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-envshell-' + IntToStr(Random(MaxInt)));
  ForceDirectories(Dir);
  Prev := ConfigDirectoryOverride;
  SetConfigDirectoryOverride(Dir);
  ShellProfileOptionsUsePath(TPath.Combine(Dir, 'shellprofiles.json'));
  Output := '';
  S := TConPtySession.Create;
  try
    Assert.IsTrue(SaveEnvProfiles(DefaultEnvProfilesPath, AProfiles));
    SetProfileEnvName(AShellId, AEnvName);
    if PlatformPosixPaths then
      Cmd := 'echo "[$' + cVarName + ']" mtn2-end'#13
    else
      Cmd := 'echo [%' + cVarName + '%] mtn2-end'#13#10;
    S.OnOutput :=
      procedure(const AText: string)
      begin
        Output := Output + AText;
      end;
    Assert.IsTrue(S.StartShell(AShellId, GetCurrentDir, 120, 24), 'the shell starts: ' + S.LastError);
    CheckSynchronize(500);
    S.WriteInput(Cmd);
    // The typed line also ends with the marker; the answer is the second one.
    WaitUntil(function: Boolean
      begin
        Result := Pos('mtn2-end', Copy(Output, Pos('mtn2-end', Output) + 8, MaxInt)) > 0;
      end, 8000);
    Result := Output;
    S.Terminate;
  finally
    S.Free;
    ShellProfileOptionsUsePath('');
    SetConfigDirectoryOverride(Prev);
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestShellEnvironment.EnabledProfileReachesTheShell;
begin
  Assert.IsTrue(Pos('[' + cVarValue + '] mtn2-end',
    ShellEchoOfVariable(BaseShell, '', [Profile('test', True, cVarValue, nil)])) > 0,
    'the shell sees the profile variable');
end;

procedure TTestShellEnvironment.DisabledProfileDoesNotReachTheShell;
begin
  Assert.IsFalse(Pos(cVarValue,
    ShellEchoOfVariable(BaseShell, '', [Profile('test', False, cVarValue, nil)])) > 0,
    'a disabled profile adds nothing');
end;

procedure TTestShellEnvironment.ProfileLimitedToAnotherShellDoesNotReachTheShell;
begin
  Assert.IsFalse(Pos(cVarValue,
    ShellEchoOfVariable(BaseShell, '',
      [Profile('test', True, cVarValue, ['no-such-shell'])])) > 0,
    'a profile limited to other shells adds nothing');
end;

procedure TTestShellEnvironment.NamedProfileOfAShellCopyAddsToDefaultOnly;
var
  Output: string;
begin
  Output := ShellEchoOfVariable(BaseShell + '#2', 'named', [
    Profile('always', True, 'always-value', nil),
    Profile('named', False, 'named-value', nil)]);
  Assert.IsTrue(Pos('[named-value] mtn2-end', Output) > 0,
    'the copy starts with the profile it names, whatever its auto flag');
  Assert.IsFalse(Pos('always-value', Output) > 0,
    'the auto profiles do not apply on top of a named one');
end;

procedure TTestShellEnvironment.DefaultProfileReachesEveryShell;
begin
  Assert.IsTrue(Pos('[default-value] mtn2-end',
    ShellEchoOfVariable(BaseShell, '', [Profile('default', False, 'default-value', nil)])) > 0,
    'default applies although it is not auto');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestShellEnvironment);

end.
