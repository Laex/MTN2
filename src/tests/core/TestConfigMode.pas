unit TestConfigMode;

{ uConfigMode on temporary "program" and "standard settings" folders: what a
  switch moves, what it leaves, what it reports beforehand and how it backs
  out. The running program's own portable.dat is never touched. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConfigMode = class
  public
    [Test] procedure TestStandardToPortableMovesSettings;
    [Test] procedure TestPortableToStandardMovesSettingsBack;
    [Test] procedure TestOnlySettingsFilesMove;
    [Test] procedure TestPlanCountsAndWarns;
    [Test] procedure TestReplacedTargetFileIsKept;
    [Test] procedure TestFailureRestoresTheOldPlace;
    [Test] procedure TestSameFolderIsBlocked;
    [Test] procedure TestEmptySourceStillSwitches;
    [Test] procedure TestSummaryFitsTheDialogInEveryLanguage;
    [Test] procedure TestDialogShrinksToItsText;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, uConfigLocation, uConfigMode, uStrings, uCharWidth, uDialogTypes;

type
  TTempPair = class
  public
    Root, ProgramDir, StandardDir: string;
    constructor Create;
    destructor Destroy; override;
    function Marker: string;
  end;

constructor TTempPair.Create;
begin
  inherited Create;
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-config-mode-' + TGUID.NewGuid.ToString);
  ProgramDir := TPath.Combine(Root, 'program');
  StandardDir := TPath.Combine(Root, 'standard');
  ForceDirectories(ProgramDir);
end;

destructor TTempPair.Destroy;
begin
  try
    TDirectory.Delete(Root, True);
  except
    // In the temp area; a leftover does no harm.
  end;
  inherited;
end;

function TTempPair.Marker: string;
begin
  Result := TPath.Combine(ProgramDir, cPortableMarkerName);
end;

procedure Put(const ADir, ARel, AText: string);
var
  Path: string;
begin
  Path := TPath.Combine(ADir, ARel);
  ForceDirectories(ExtractFilePath(Path));
  TFile.WriteAllText(Path, AText);
end;

function Get(const ADir, ARel: string): string;
begin
  Result := TFile.ReadAllText(TPath.Combine(ADir, ARel));
end;

function Has(const ADir, ARel: string): Boolean;
begin
  Result := TFile.Exists(TPath.Combine(ADir, ARel));
end;

procedure TTestConfigMode.TestStandardToPortableMovesSettings;
var
  P: TTempPair;
  Leftover: Integer;
  Err: string;
begin
  P := TTempPair.Create;
  try
    Put(P.StandardDir, 'session.json', '{"a":1}');
    Put(P.StandardDir, 'history.json', '[]');
    Put(P.StandardDir, 'themes\Mine.theme.json', '{"name":"Mine"}');
    Assert.IsTrue(SwitchConfigModeFor(P.ProgramDir, P.StandardDir, cmStandard, Leftover, Err), Err);
    Assert.AreEqual(0, Leftover);
    Assert.AreEqual('{"a":1}', Get(P.ProgramDir, 'session.json'));
    Assert.AreEqual('[]', Get(P.ProgramDir, 'history.json'));
    Assert.AreEqual('{"name":"Mine"}', Get(P.ProgramDir, 'themes\Mine.theme.json'));
    Assert.IsTrue(TFile.Exists(P.Marker), 'portable.dat switches the program to its own folder');
    Assert.IsFalse(Has(P.StandardDir, 'session.json'), 'the originals are gone');
    Assert.IsFalse(TDirectory.Exists(P.StandardDir), 'the emptied standard folder is removed');
  finally
    P.Free;
  end;
end;

procedure TTestConfigMode.TestPortableToStandardMovesSettingsBack;
var
  P: TTempPair;
  Leftover: Integer;
  Err: string;
begin
  P := TTempPair.Create;
  try
    TFile.WriteAllText(P.Marker, 'x');
    Put(P.ProgramDir, 'session.json', '{"a":2}');
    Put(P.ProgramDir, 'themes\Mine.theme.json', '{"name":"Mine"}');
    Assert.IsTrue(SwitchConfigModeFor(P.ProgramDir, P.StandardDir, cmPortable, Leftover, Err), Err);
    Assert.AreEqual('{"a":2}', Get(P.StandardDir, 'session.json'));
    Assert.AreEqual('{"name":"Mine"}', Get(P.StandardDir, 'themes\Mine.theme.json'));
    Assert.IsFalse(TFile.Exists(P.Marker), 'without portable.dat the standard folder is used');
    Assert.IsFalse(Has(P.ProgramDir, 'session.json'));
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(P.ProgramDir, 'themes')), 'the emptied themes folder is removed');
  finally
    P.Free;
  end;
end;

procedure TTestConfigMode.TestOnlySettingsFilesMove;
var
  P: TTempPair;
  Leftover: Integer;
  Err: string;
  Files: TArray<string>;
begin
  P := TTempPair.Create;
  try
    TFile.WriteAllText(P.Marker, 'x');
    Put(P.ProgramDir, 'MTN2.exe', 'program');
    Put(P.ProgramDir, 'notes.txt', 'not a setting');
    Put(P.ProgramDir, 'plugins\mtn.demo\plugin.json', '{}');
    Put(P.ProgramDir, 'resource\themes\Nord.theme.json', '{}');
    Put(P.ProgramDir, 'keymap.json.bak-1', 'old keymap');
    Put(P.ProgramDir, 'session.json.before-switch', 'earlier backup');
    Put(P.ProgramDir, 'session.json', '{}');
    Files := ConfigFilesIn(P.ProgramDir);
    Assert.AreEqual(2, Integer(Length(Files)), string.Join(',', Files));
    Assert.IsTrue(SwitchConfigModeFor(P.ProgramDir, P.StandardDir, cmPortable, Leftover, Err), Err);
    Assert.IsTrue(Has(P.ProgramDir, 'MTN2.exe'), 'the program stays');
    Assert.IsTrue(Has(P.ProgramDir, 'notes.txt'));
    Assert.IsTrue(Has(P.ProgramDir, 'plugins\mtn.demo\plugin.json'), 'plugin manifests are not settings');
    Assert.IsTrue(Has(P.ProgramDir, 'resource\themes\Nord.theme.json'), 'shipped themes stay');
    Assert.IsTrue(Has(P.ProgramDir, 'session.json.before-switch'), 'an earlier backup is not moved');
    Assert.IsTrue(Has(P.StandardDir, 'keymap.json.bak-1'), 'a backup copy of a settings file moves with them');
  finally
    P.Free;
  end;
end;

procedure TTestConfigMode.TestPlanCountsAndWarns;
var
  P: TTempPair;
  Plan: TConfigModePlan;
begin
  P := TTempPair.Create;
  try
    Put(P.StandardDir, 'session.json', '12345');
    Put(P.StandardDir, 'history.json', '123');
    Put(P.ProgramDir, 'history.json', 'older');
    Plan := PlanConfigModeSwitchFor(P.ProgramDir, P.StandardDir, cmStandard);
    Assert.IsTrue(Plan.CanSwitch);
    Assert.IsTrue(Plan.ToMode = cmPortable);
    Assert.AreEqual(2, Plan.FileCount);
    Assert.AreEqual<Int64>(8, Plan.TotalBytes);
    Assert.AreEqual(1, Plan.ReplacedCount);
    Assert.IsTrue(cwTargetHasFiles in Plan.Warnings, 'a file in the target is replaced');
    Assert.IsFalse(cwNothingToMove in Plan.Warnings);
  finally
    P.Free;
  end;
end;

procedure TTestConfigMode.TestReplacedTargetFileIsKept;
var
  P: TTempPair;
  Leftover: Integer;
  Err: string;
begin
  P := TTempPair.Create;
  try
    Put(P.StandardDir, 'session.json', 'new');
    Put(P.ProgramDir, 'session.json', 'old');
    Assert.IsTrue(SwitchConfigModeFor(P.ProgramDir, P.StandardDir, cmStandard, Leftover, Err), Err);
    Assert.AreEqual('new', Get(P.ProgramDir, 'session.json'));
    Assert.AreEqual('old', Get(P.ProgramDir, 'session.json' + cBackupSuffix), 'the replaced file is kept');
  finally
    P.Free;
  end;
end;

procedure TTestConfigMode.TestFailureRestoresTheOldPlace;
var
  P: TTempPair;
  Leftover: Integer;
  Err: string;
begin
  P := TTempPair.Create;
  try
    Put(P.StandardDir, 'a.json', 'first');
    Put(P.StandardDir, 'session.json', 'second');
    // A folder where the second file has to go: the copy fails after the first succeeded.
    ForceDirectories(TPath.Combine(P.ProgramDir, 'session.json'));
    Assert.IsFalse(SwitchConfigModeFor(P.ProgramDir, P.StandardDir, cmStandard, Leftover, Err));
    Assert.IsTrue(Err <> '');
    Assert.IsFalse(TFile.Exists(P.Marker), 'the mode is unchanged');
    Assert.IsFalse(Has(P.ProgramDir, 'a.json'), 'the copy made before the failure is removed');
    Assert.AreEqual('first', Get(P.StandardDir, 'a.json'), 'the originals are intact');
    Assert.AreEqual('second', Get(P.StandardDir, 'session.json'));
  finally
    P.Free;
  end;
end;

procedure TTestConfigMode.TestSameFolderIsBlocked;
var
  P: TTempPair;
  Plan: TConfigModePlan;
  Leftover: Integer;
  Err: string;
begin
  P := TTempPair.Create;
  try
    Plan := PlanConfigModeSwitchFor(P.ProgramDir, P.ProgramDir, cmStandard);
    Assert.IsFalse(Plan.CanSwitch);
    Assert.IsTrue(cbSameFolder in Plan.Blockers);
    Assert.IsFalse(SwitchConfigModeFor(P.ProgramDir, P.ProgramDir, cmStandard, Leftover, Err));
    Assert.IsFalse(TFile.Exists(P.Marker), 'nothing is changed');
  finally
    P.Free;
  end;
end;

procedure TTestConfigMode.TestEmptySourceStillSwitches;
var
  P: TTempPair;
  Plan: TConfigModePlan;
  Leftover: Integer;
  Err: string;
begin
  P := TTempPair.Create;
  try
    Plan := PlanConfigModeSwitchFor(P.ProgramDir, P.StandardDir, cmStandard);
    Assert.IsTrue(Plan.CanSwitch);
    Assert.IsTrue(cwNothingToMove in Plan.Warnings);
    Assert.IsTrue(SwitchConfigModeFor(P.ProgramDir, P.StandardDir, cmStandard, Leftover, Err), Err);
    Assert.IsTrue(TFile.Exists(P.Marker));
  finally
    P.Free;
  end;
end;

procedure TTestConfigMode.TestSummaryFitsTheDialogInEveryLanguage;
var
  P: TTempPair;
  Plan: TConfigModePlan;
  Locale, Line: string;
  Lines: TArray<string>;
begin
  P := TTempPair.Create;
  try
    // Every line the summary can hold at once: blockers first, then warnings.
    Plan := Default(TConfigModePlan);
    Plan.FromMode := cmPortable;
    Plan.ToMode := cmStandard;
    Plan.SourceDir := P.ProgramDir;
    Plan.TargetDir := P.StandardDir;
    Plan.FileCount := 12;
    Plan.TotalBytes := 123456;
    Plan.ReplacedCount := 3;
    for Locale in ['en', 'ru', 'de', 'zh'] do
    begin
      SetLocale(Locale);
      try
        Plan.Blockers := [];
        Plan.Warnings := [cwTargetHasFiles, cwSystemProgramFolder, cwNetworkProgramFolder];
        Lines := ConfigModeSummaryLines(Plan);
        Assert.AreEqual(8, Integer(Length(Lines)), Locale + ': 5 fixed lines and 3 warnings');
        Plan.Blockers := [cbOverridden, cbSameFolder, cbProgramFolderReadOnly,
          cbTargetFolderReadOnly, cbSourceUnreadable];
        Lines := ConfigModeSummaryLines(Plan);
        Assert.AreEqual(8, Integer(Length(Lines)), Locale + ': never more than the dialog holds');
        for Line in Lines do
          Assert.IsTrue(TextDisplayWidth(Line) <= cSummaryMaxWidth,
            Locale + ' line is wider than the dialog: ' + Line);
      finally
        SetLocale('en');
      end;
    end;
  finally
    P.Free;
  end;
end;

procedure TTestConfigMode.TestDialogShrinksToItsText;
var
  Full, Short: TDialogDeclaration;
  Lines: TArray<string>;
  I, Labels, Marked: Integer;
begin
  SetLength(Lines, cConfigLocationLines);
  for I := 0 to High(Lines) do
    Lines[I] := 'line ' + IntToStr(I);
  Full := BuildConfigLocationDialog('Title', Lines, 'Switch');
  SetLength(Lines, 5);
  Short := BuildConfigLocationDialog('Title', Lines, 'Switch');
  Assert.AreEqual(3, Full.Height - Short.Height, 'three unused text rows are cut');
  Labels := 0;
  Marked := 0;
  for I := 0 to High(Short.Controls) do
    if (Short.Controls[I].Kind = dckLabel) and (Copy(Short.Controls[I].Id, 1, 4) = 'line') then
    begin
      Inc(Labels);
      if Short.Controls[I].Marked then
        Inc(Marked);
    end;
  Assert.AreEqual(5, Labels, 'only the used lines remain');
  Assert.AreEqual(2, Marked, 'the two folder lines are marked');
  for I := 0 to High(Short.Controls) do
    if Short.Controls[I].Kind = dckButton then
      Assert.IsTrue(Short.Controls[I].Row < Short.Height, 'buttons stay inside the frame');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConfigMode);

end.
