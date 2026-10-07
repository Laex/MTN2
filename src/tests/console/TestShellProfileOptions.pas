unit TestShellProfileOptions;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestShellProfileOptions = class
  strict private
    FPath: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure CopyIdKeepsShellOfProfile;
    [Test] procedure HotkeysCoverDigitsThenLetters;
    [Test] procedure NextCopyIdSkipsUsedNumbers;
    [Test] procedure SavedOrderComesFirst;
    [Test] procedure KeyModeSurvivesReload;
    [Test] procedure CopyAddMoveDeleteRoundTrip;
    [Test] procedure ProfileIsNotDeletable;
    [Test] procedure TerminalKeysUseXtermSequences;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, System.UITypes,
  uShellProfiles, uShellProfileOptions, uTerminalKeys;

procedure TTestShellProfileOptions.Setup;
begin
  FPath := TPath.Combine(TPath.GetTempPath, 'mtn2-shellprofiles-test.json');
  if TFile.Exists(FPath) then
    TFile.Delete(FPath);
  ShellProfileOptionsUsePath(FPath);
end;

procedure TTestShellProfileOptions.TearDown;
begin
  ShellProfileOptionsUsePath('');
  if TFile.Exists(FPath) then
    TFile.Delete(FPath);
end;

procedure TTestShellProfileOptions.CopyIdKeepsShellOfProfile;
begin
  Assert.AreEqual('cmd', NormalizeShellProfileId('cmd#2'));
  Assert.AreEqual('cmd#2', CanonicalShellProfileId('cmd#2'));
  Assert.AreEqual('wsl:Ubuntu', NormalizeShellProfileId('wsl:Ubuntu#12'));
  Assert.AreEqual('#12', ShellProfileCopySuffix('wsl:Ubuntu#12'));
  Assert.AreEqual('', ShellProfileCopySuffix('wsl:Ubuntu'));
  Assert.AreEqual('', ShellProfileCopySuffix('#2'), 'a bare suffix is no copy');
  Assert.AreEqual('', ShellProfileCopySuffix('cmd#'), 'no number, no copy');
  Assert.AreEqual(#13#10, ProfileReturnSeq('cmd#3'));
  Assert.AreEqual(#10, ProfileReturnSeq('wsl#3'));
end;

procedure TTestShellProfileOptions.HotkeysCoverDigitsThenLetters;
var
  I: Integer;
begin
  Assert.AreEqual('1', string(ProfileHotkeyChar(0)));
  Assert.AreEqual('9', string(ProfileHotkeyChar(8)));
  Assert.AreEqual('0', string(ProfileHotkeyChar(9)));
  Assert.AreEqual('A', string(ProfileHotkeyChar(10)));
  Assert.AreEqual('Z', string(ProfileHotkeyChar(35)));
  Assert.AreEqual(#0, ProfileHotkeyChar(36));
  for I := 0 to 35 do
    Assert.AreEqual(I, ProfileHotkeyIndex(ProfileHotkeyChar(I)));
  Assert.AreEqual(10, ProfileHotkeyIndex('a'));
  Assert.AreEqual(-1, ProfileHotkeyIndex('-'));
end;

procedure TTestShellProfileOptions.NextCopyIdSkipsUsedNumbers;
begin
  Assert.AreEqual('cmd#2', NextCopyProfileId('cmd', ['cmd', 'pwsh']));
  Assert.AreEqual('cmd#4', NextCopyProfileId('cmd', ['cmd', 'cmd#2', 'cmd#3']));
  Assert.AreEqual('cmd#2', NextCopyProfileId('cmd', ['cmd', 'cmd#3']));
end;

procedure TTestShellProfileOptions.SavedOrderComesFirst;
var
  R: TArray<string>;
begin
  R := ApplyProfileOrder(['a', 'b', 'c', 'd'], ['c', 'x', 'a']);
  Assert.AreEqual(4, Integer(Length(R)));
  Assert.AreEqual('c', R[0]);
  Assert.AreEqual('a', R[1]);
  Assert.AreEqual('b', R[2]);
  Assert.AreEqual('d', R[3]);
end;

procedure TTestShellProfileOptions.KeyModeSurvivesReload;
begin
  Assert.IsTrue(ProfileKeyMode('cmd') = pkmAuto, 'the default is auto');
  SetProfileKeyMode('cmd', pkmProgram);
  SetProfileKeyMode('cmd#2', pkmHost);
  ShellProfileOptionsUsePath(FPath); // forgets what is in memory
  Assert.IsTrue(ProfileKeyMode('cmd') = pkmProgram);
  Assert.IsTrue(ProfileKeyMode('cmd#2') = pkmHost);
  Assert.IsTrue(ProfileKeyMode('pwsh') = pkmAuto);
  Assert.IsTrue(NextProfileKeyMode(pkmAuto) = pkmProgram);
  Assert.IsTrue(NextProfileKeyMode(pkmProgram) = pkmHost);
  Assert.IsTrue(NextProfileKeyMode(pkmHost) = pkmAuto);
end;

procedure TTestShellProfileOptions.CopyAddMoveDeleteRoundTrip;
var
  Id: string;
  E: TProfileEntries;
  I, At: Integer;
begin
  SetProfileKeyMode('cmd', pkmProgram);
  Id := ProfileCopyAdd('cmd');
  Assert.AreEqual('cmd#2', Id);
  Assert.IsTrue(ProfileKeyMode(Id) = pkmProgram, 'a copy starts with the settings of its source');

  E := ProfileEntriesOrdered;
  At := -1;
  for I := 0 to High(E) do
    if E[I].Id = Id then
      At := I;
  Assert.IsTrue(At > 0, 'the copy is listed');
  Assert.AreEqual('cmd', E[At - 1].Id, 'right after its source');
  Assert.IsTrue(E[At].IsCopy);

  Assert.IsTrue(ProfileMove(Id, -1));
  E := ProfileEntriesOrdered;
  Assert.AreEqual(Id, E[At - 1].Id, 'moved up');
  Assert.IsFalse(ProfileMove(E[0].Id, -1), 'the first profile cannot go up');

  // Everything is stored, so a new run lists the same.
  ShellProfileOptionsUsePath(FPath);
  E := ProfileEntriesOrdered;
  Assert.AreEqual(Id, E[At - 1].Id, 'order survives a reload');

  Assert.IsTrue(ProfileCopyDelete(Id));
  E := ProfileEntriesOrdered;
  for I := 0 to High(E) do
    Assert.AreNotEqual(Id, E[I].Id);
  Assert.IsTrue(ProfileKeyMode(Id) = pkmAuto, 'a deleted copy forgets its settings');
end;

procedure TTestShellProfileOptions.ProfileIsNotDeletable;
begin
  Assert.IsFalse(ProfileCopyDelete('cmd'));
end;

procedure TTestShellProfileOptions.TerminalKeysUseXtermSequences;
var
  S: string;
begin
  Assert.IsTrue(EncodeTerminalKey(vkF1, [], #0, False, S));
  Assert.AreEqual(#27'OP', S);
  Assert.IsTrue(EncodeTerminalKey(vkF5, [], #0, False, S));
  Assert.AreEqual(#27'[15~', S);
  Assert.IsTrue(EncodeTerminalKey(vkF10, [], #0, False, S));
  Assert.AreEqual(#27'[21~', S);
  Assert.IsTrue(EncodeTerminalKey(vkF5, [ssShift], #0, False, S));
  Assert.AreEqual(#27'[15;2~', S);
  Assert.IsTrue(EncodeTerminalKey(vkF3, [ssCtrl], #0, False, S));
  Assert.AreEqual(#27'[1;5R', S);
  Assert.IsTrue(EncodeTerminalKey(vkLeft, [ssCtrl], #0, False, S));
  Assert.AreEqual(#27'[1;5D', S);
  Assert.IsTrue(EncodeTerminalKey(vkUp, [], #0, True, S));
  Assert.AreEqual(#27'OA', S, 'application cursor keys');
  Assert.IsTrue(EncodeTerminalKey(vkUp, [], #0, False, S));
  Assert.AreEqual(#27'[A', S);
  Assert.IsTrue(EncodeTerminalKey(vkDelete, [], #0, False, S));
  Assert.AreEqual(#27'[3~', S);
  Assert.IsTrue(EncodeTerminalKey(vkTab, [ssShift], #0, False, S));
  Assert.AreEqual(#27'[Z', S);
  Assert.IsTrue(EncodeTerminalKey(vkU, [ssCtrl], #0, False, S));
  Assert.AreEqual(#21, S, 'Ctrl+U');
  Assert.IsTrue(EncodeTerminalKey(vkX, [ssAlt], 'x', False, S));
  Assert.AreEqual(#27'x', S);
  Assert.IsTrue(EncodeTerminalKey(vkX, [ssAlt], #0, False, S));
  Assert.AreEqual(#27'x', S, 'the letter comes from the key when no character arrives');
  Assert.IsFalse(EncodeTerminalKey(vkA, [], 'a', False, S), 'a plain character has no sequence');
  Assert.IsFalse(EncodeTerminalKey(vkReturn, [], #13, False, S));
  Assert.IsFalse(EncodeTerminalKey(vkEscape, [], #27, False, S));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestShellProfileOptions);

end.
