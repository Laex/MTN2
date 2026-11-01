unit TestGitStatus;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestGitStatus = class
  public
    [Test] procedure TestParseCountsStagedChangedUntrackedAndConflicts;
    [Test] procedure TestParseReadsAheadBehindAndUpstream;
    [Test] procedure TestDetachedHeadShowsShortOid;
    [Test] procedure TestOutputWithoutBranchHeaderIsRejected;
    [Test] procedure TestFormatCleanAndDirty;
    [Test] procedure TestColorSettingAcceptsHexAndNames;
    [Test] procedure TestRefreshSecondsAreClamped;
    [Test] procedure TestSettingsRoundTripThroughTheStore;
    [Test] procedure TestUserColorsOverrideTheBadgeRoles;
    [Test] procedure TestSettingsDialogCarriesTheCurrentValues;
    [Test] procedure TestDialogAnswerIsParsedAndCleaned;
    [Test] procedure TestHostShowsTheCurrentValuesInTheInputs;
    [Test] procedure TestSpansJsonHasOneBadgePerKindOfChange;
    [Test] procedure TestSpansJsonOfACleanTreeSaysClean;
    [Test] procedure TestActivePanelUriFollowsTheActiveSide;
    [Test] procedure TestFolderOutsideAWorkTreeIsNotARepo;
    [Test] procedure TestReadsStatusOfARealRepository;
    [Test] procedure TestCursorRowComesFromTheActiveSide;
    [Test] procedure TestDiffOfAChangedFileAgainstHead;
    [Test] procedure TestDiffOutsideAWorkTreeIsNotARepo;
    [Test] procedure TestDiffFileKeepsTheTextAndGetsADiffExtension;
    [Test] procedure TestMarksNameTheRowsOfTheFolder;
    [Test] procedure TestMarksOfASubfolderUseItsPrefix;
    [Test] procedure TestRenamedFileTakesOnePathOnly;
    [Test] procedure TestPanelFoldersAreLocalAndUnique;
    [Test] procedure TestMarksOfARealRepository;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, System.JSON,
  uTerminalTypes, uDialogTypes, uDialogJson, uDialogLocaleLayout, uDialogHost,
  uPlatformProcess, uGitStatus, uGitSettings, uGitRepo, uGitDiff, uGitMarks;

const
  CRLF = #13#10;

procedure TTestGitStatus.TestParseCountsStagedChangedUntrackedAndConflicts;
var
  S: TGitStatus;
begin
  Assert.IsTrue(ParseGitStatus(
    '# branch.oid 0123456789abcdef' + #10 +
    '# branch.head main' + #10 +
    '1 M. N... 100644 100644 100644 a b src/a.pas' + #10 +
    '1 .M N... 100644 100644 100644 a b src/b.pas' + #10 +
    '1 MM N... 100644 100644 100644 a b src/c.pas' + #10 +
    '2 R. N... 100644 100644 100644 a b R100 new.pas' + #9 + 'old.pas' + #10 +
    'u UU N... 100644 100644 100644 100644 a b c d.pas' + #10 +
    '? new.txt' + #10 +
    '? other.txt' + #10, S), 'parsed');
  Assert.AreEqual('main', S.Branch);
  Assert.AreEqual(3, S.Staged, 'staged: M., MM, R.');
  Assert.AreEqual(2, S.Changed, 'changed: .M, MM');
  Assert.AreEqual(2, S.Untracked);
  Assert.AreEqual(1, S.Conflicts);
  Assert.IsFalse(S.Detached);
end;

procedure TTestGitStatus.TestParseReadsAheadBehindAndUpstream;
var
  S: TGitStatus;
begin
  Assert.IsTrue(ParseGitStatus(
    '# branch.oid abc' + CRLF + '# branch.head dev' + CRLF +
    '# branch.upstream origin/dev' + CRLF + '# branch.ab +3 -2' + CRLF, S));
  Assert.IsTrue(S.HasUpstream);
  Assert.AreEqual(3, S.Ahead);
  Assert.AreEqual(2, S.Behind);
end;

procedure TTestGitStatus.TestDetachedHeadShowsShortOid;
var
  S: TGitStatus;
begin
  Assert.IsTrue(ParseGitStatus(
    '# branch.oid 0123456789abcdef' + #10 + '# branch.head (detached)' + #10, S));
  Assert.IsTrue(S.Detached);
  Assert.AreEqual('0123456', S.Branch);
  Assert.AreEqual('git:@0123456 clean', FormatGitStatus(S));
end;

procedure TTestGitStatus.TestOutputWithoutBranchHeaderIsRejected;
var
  S: TGitStatus;
begin
  Assert.IsFalse(ParseGitStatus('', S), 'empty');
  Assert.IsFalse(ParseGitStatus('fatal: not a git repository', S), 'error text');
end;

procedure TTestGitStatus.TestFormatCleanAndDirty;
var
  S: TGitStatus;
begin
  S := Default(TGitStatus);
  S.Branch := 'main';
  Assert.AreEqual('git:main clean', FormatGitStatus(S));
  S.Ahead := 1;
  S.Behind := 2;
  S.Staged := 3;
  S.Changed := 4;
  S.Untracked := 5;
  S.Conflicts := 6;
  Assert.AreEqual('git:main ^1 v2 +3 ~4 ?5 !6', FormatGitStatus(S));
end;

procedure TTestGitStatus.TestSpansJsonHasOneBadgePerKindOfChange;
var
  S: TGitStatus;
  L: TGitLabels;
  Arr: TJSONArray;
  Texts: string;
  I: Integer;
begin
  S := Default(TGitStatus);
  S.Branch := 'main';
  S.Ahead := 2;
  S.Changed := 4;
  S.Conflicts := 1;
  L := DefaultGitLabels;
  Arr := TJSONObject.ParseJSONValue(GitStatusSpansJson(S, L)) as TJSONArray;
  try
    Texts := '';
    for I := 0 to Arr.Count - 1 do
      Texts := Texts + Arr.Items[I].GetValue<string>('t') + '|';
    Assert.AreEqual(' main | | ahead 2 | | modified 4 | | conflicts 1 |', Texts);
    Assert.AreEqual('accent', Arr.Items[0].GetValue<string>('role'));
    Assert.AreEqual('info', Arr.Items[2].GetValue<string>('role'));
    Assert.AreEqual('warn', Arr.Items[4].GetValue<string>('role'));
    Assert.AreEqual('error', Arr.Items[6].GetValue<string>('role'));
  finally
    Arr.Free;
  end;
  L.Ahead := 'forward';
  Assert.IsTrue(Pos('forward 2', GitStatusSpansJson(S, L)) > 0, 'translated words');
end;

procedure TTestGitStatus.TestSpansJsonOfACleanTreeSaysClean;
var
  S: TGitStatus;
begin
  S := Default(TGitStatus);
  S.Branch := StringOfChar('b', 40);
  Assert.IsTrue(Pos(' clean ', GitStatusSpansJson(S, DefaultGitLabels)) > 0, 'clean badge');
  Assert.IsTrue(Pos(StringOfChar('b', 24), GitStatusSpansJson(S, DefaultGitLabels)) = 0,
    'a long branch name is shortened');
end;

procedure TTestGitStatus.TestColorSettingAcceptsHexAndNames;
begin
  Assert.AreEqual('#AABBCC', NormalizeColorSetting('#aabbcc'));
  Assert.AreEqual('#AABBCC', NormalizeColorSetting(' aabbcc '));
  Assert.AreEqual('#FFFFFF', NormalizeColorSetting('White'));
  Assert.AreEqual('', NormalizeColorSetting(''));
  Assert.AreEqual('', NormalizeColorSetting('#12345'), 'too short');
  Assert.AreEqual('', NormalizeColorSetting('#GGGGGG'), 'not hex');
  Assert.AreEqual('', NormalizeColorSetting('#-12345'), 'sign is not a digit');
  Assert.AreEqual('', NormalizeColorSetting('nocolor'), 'unknown name');
end;

procedure TTestGitStatus.TestRefreshSecondsAreClamped;
begin
  Assert.IsTrue(ParseRefreshSeconds('10') = 10);
  Assert.IsTrue(ParseRefreshSeconds('') = cDefaultRefreshSec, 'never set');
  Assert.IsTrue(ParseRefreshSeconds('abc') = cDefaultRefreshSec, 'not a number');
  Assert.IsTrue(ParseRefreshSeconds('0') = cMinRefreshSec, 'too small');
  Assert.IsTrue(ParseRefreshSeconds('999999') = cMaxRefreshSec, 'too large');
end;

procedure TTestGitStatus.TestSettingsRoundTripThroughTheStore;
var
  Store: TStringList;
  S, R: TGitSettings;
begin
  Store := TStringList.Create;
  try
    S := DefaultGitSettings;
    S.RefreshSec := 12;
    S.Colors.Fg[gbStaged] := '#112233';
    S.Colors.Bg[gbClean] := '#445566';
    WriteGitSettings(S,
      procedure(AKey, AValue: string)
      begin
        Store.Values[AKey] := AValue;
      end);
    R := ReadGitSettings(
      function(AKey: string): string
      begin
        Result := Store.Values[AKey];
      end);
    Assert.IsTrue(R.RefreshSec = 12);
    Assert.AreEqual('#112233', R.Colors.Fg[gbStaged]);
    Assert.AreEqual('#445566', R.Colors.Bg[gbClean]);
    Assert.AreEqual(DefaultGitSettings.Colors.Fg[gbBranch], R.Colors.Fg[gbBranch], 'unset = standard');
    R := ReadGitSettings(
      function(AKey: string): string
      begin
        Result := '';
      end);
    Assert.IsTrue(R.RefreshSec = cDefaultRefreshSec, 'defaults when nothing is stored');
  finally
    Store.Free;
  end;
end;

procedure TTestGitStatus.TestUserColorsOverrideTheBadgeRoles;
var
  S: TGitStatus;
  C: TGitColors;
  Arr: TJSONArray;
  Dummy: string;
begin
  S := Default(TGitStatus);
  S.Branch := 'main';
  S.Staged := 1;
  C := Default(TGitColors);
  C.Fg[gbStaged] := '#112233';
  C.Bg[gbStaged] := '#445566';
  C.Bg[gbBranch] := '#778899';
  Arr := TJSONObject.ParseJSONValue(GitStatusSpansJson(S, DefaultGitLabels, C)) as TJSONArray;
  try
    Assert.AreEqual('#778899', Arr.Items[0].GetValue<string>('bg'), 'branch background');
    Assert.IsFalse(Arr.Items[0].TryGetValue<string>('fg', Dummy), 'branch text color stays default');
    Assert.AreEqual('ok', Arr.Items[2].GetValue<string>('role'), 'role stays under the colors');
    Assert.AreEqual('#112233', Arr.Items[2].GetValue<string>('fg'));
    Assert.AreEqual('#445566', Arr.Items[2].GetValue<string>('bg'));
  finally
    Arr.Free;
  end;
end;

procedure TTestGitStatus.TestSettingsDialogCarriesTheCurrentValues;
var
  S: TGitSettings;
  Root: TJSONObject;
  Kids: TJSONArray;
  I, Inputs, Buttons, Samples: Integer;
  Found: Boolean;
begin
  S := DefaultGitSettings;
  S.RefreshSec := 7;
  S.Colors.Fg[gbChanged] := '#ABCDEF';
  Root := TJSONObject.ParseJSONValue(GitSettingsDialogJson(S,
    function(AKey, ADefault: string): string
    begin
      Result := ADefault;
    end)) as TJSONObject;
  try
    Assert.AreEqual('2.0', Root.GetValue<string>('version'));
    Kids := Root.GetValue<TJSONArray>('children');
    Inputs := 0;
    Buttons := 0;
    Samples := 0;
    Found := False;
    for I := 0 to Kids.Count - 1 do
    begin
      if Kids.Items[I].GetValue<string>('type') = 'input' then
        Inc(Inputs);
      if Kids.Items[I].GetValue<string>('type') = 'button' then
        Inc(Buttons);
      if Kids.Items[I].GetValue<string>('type') = 'colorsample' then
      begin
        Inc(Samples);
        Assert.IsTrue(Pos('fg.', Kids.Items[I].GetValue<string>('fgFrom')) = 1, 'sample follows the text color field');
      end;
      if Kids.Items[I].GetValue<string>('id', '') = 'refresh' then
      begin
        Assert.AreEqual('dropdown', Kids.Items[I].GetValue<string>('type'));
        Assert.AreEqual('5', Kids.Items[I].GetValue<TJSONArray>('items').Items[
          Kids.Items[I].GetValue<Integer>('selected')].Value, 'nearest period chosen');
      end;
      if Kids.Items[I].GetValue<string>('id', '') = 'fg.changed' then
      begin
        Assert.AreEqual('#ABCDEF', Kids.Items[I].GetValue<string>('value'));
        Found := True;
      end;
    end;
    Assert.IsTrue(Inputs = 2 * (Ord(High(TGitBadge)) + 1), 'two colors per badge');
    Assert.IsTrue(Buttons = 2, 'OK and Cancel');
    Assert.IsTrue(Samples = Ord(High(TGitBadge)) + 1, 'a sample per badge');
    Assert.IsTrue(Found, 'current color shown');
  finally
    Root.Free;
  end;
end;

procedure TTestGitStatus.TestDialogAnswerIsParsedAndCleaned;
var
  S: TGitSettings;
begin
  S := GitSettingsFromDialogValues(
    '{"refresh":"3","fg.staged":"red","bg.staged":"zzz","fg.clean":"#0a0b0c"}');
  Assert.IsTrue(S.RefreshSec = 3);
  Assert.AreEqual('#C62828', S.Colors.Fg[gbStaged]);
  Assert.AreEqual(DefaultGitSettings.Colors.Bg[gbStaged], S.Colors.Bg[gbStaged],
    'an unknown color gives the standard one');
  Assert.AreEqual('#0A0B0C', S.Colors.Fg[gbClean]);
  S := GitSettingsFromDialogValues('garbage');
  Assert.IsTrue(S.RefreshSec = cDefaultRefreshSec, 'bad answer gives the defaults');
end;

procedure TTestGitStatus.TestHostShowsTheCurrentValuesInTheInputs;
var
  S: TGitSettings;
  Decl: TDialogDeclaration;
  C: TDialogControl;
  Seen: string;
  Host: TDialogHost;
  Grid: TTerminalGrid;
  Screen: string;
  Y, X: Integer;
begin
  S := DefaultGitSettings;
  S.RefreshSec := 7;
  S.Colors.Fg[gbChanged] := '#ABCDEF';
  Assert.IsTrue(TryParseDialogJson(GitSettingsDialogJson(S,
    function(AKey, ADefault: string): string
    begin
      Result := ADefault;
    end), Decl), 'the host parses the dialog');
  FitDialogToTranslatedText(Decl);
  Seen := '';
  for C in Decl.Controls do
    if SameText(C.Id, 'fg.changed') then
      Seen := Seen + C.Id + '=' + C.Edit.Text + ';';
  Assert.AreEqual('fg.changed=#ABCDEF;', Seen);
  Host := TDialogHost.Create(nil);
  try
    Host.Open(Decl, nil);
    Assert.AreEqual('#ABCDEF', Host.GetInputValue('fg.changed'));
    AllocTerminalGrid(Grid, 80, 24);
    Host.Draw(Grid, 80, 24);
    Screen := '';
    for Y := 0 to 23 do
    begin
      for X := 0 to 79 do
        Screen := Screen + Grid[Y][X].CharValue;
      Screen := Screen + #10;
    end;
    Assert.IsTrue(Pos('#ABCDEF', Screen) > 0, 'the value is drawn: ' + Screen);
  finally
    Host.Free;
  end;
end;

procedure TTestGitStatus.TestActivePanelUriFollowsTheActiveSide;
const
  Json = '{"active":"right","left":{"uri":"file:///C:/a"},"right":{"uri":"file:///C:/b"}}';
begin
  Assert.AreEqual('file:///C:/b', ActivePanelUri(Json));
  Assert.AreEqual('', ActivePanelUri(''), 'no panels');
  Assert.AreEqual('', ActivePanelUri('not json'), 'bad json');
  Assert.AreEqual('', ActivePanelUri('{"active":"left"}'), 'no side object');
end;

procedure TTestGitStatus.TestFolderOutsideAWorkTreeIsNotARepo;
var
  Dir: string;
  S: TGitStatus;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-git-none-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Dir);
  try
    // A temp folder can sit under a working tree on a developer machine: only
    // assert when it does not.
    if IsInsideGitWorkTree(Dir) then
      Exit;
    Assert.IsTrue(ReadGitStatus(Dir, nil, S) = grNotRepo);
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestGitStatus.TestReadsStatusOfARealRepository;
var
  Dir, Output: string;
  S: TGitStatus;
  Code: Cardinal;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-git-repo-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Dir);
  try
    if (PlatformRunCaptured('git', ['init', '-q', '-b', 'main', Dir], '', 15000, nil,
         Output, Code) <> srOk) or (Code <> 0) then
    begin
      Assert.Pass('git is not available');
      Exit;
    end;
    TFile.WriteAllText(TPath.Combine(Dir, 'a.txt'), 'x');
    Assert.IsTrue(IsInsideGitWorkTree(Dir));
    Assert.IsTrue(ReadGitStatus(Dir, nil, S) = grOk);
    Assert.AreEqual('main', S.Branch);
    Assert.IsTrue(S.Untracked = 1);
    Assert.AreEqual('git:main ?1', FormatGitStatus(S));
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestGitStatus.TestCursorRowComesFromTheActiveSide;
const
  Json = '{"active":"left","left":{"uri":"file:///C:/a","cursor":"file:///C:/a/x.txt",' +
    '"cursorIsDirectory":false},"right":{"uri":"file:///C:/b","cursor":"file:///C:/b/d",' +
    '"cursorIsDirectory":true}}';
var
  Uri: string;
  IsDir: Boolean;
begin
  Assert.IsTrue(ActivePanelCursor(Json, Uri, IsDir));
  Assert.AreEqual('file:///C:/a/x.txt', Uri);
  Assert.IsFalse(IsDir);
  Assert.IsTrue(ActivePanelCursor(StringReplace(Json, 'left"', 'right"', []), Uri, IsDir));
  Assert.IsTrue(IsDir, 'folder row');
  Assert.IsFalse(ActivePanelCursor('{"active":"left","left":{"uri":"file:///C:/a"}}', Uri, IsDir),
    'no cursor row');
  Assert.IsFalse(ActivePanelCursor('', Uri, IsDir), 'no panels');
end;

procedure TTestGitStatus.TestDiffOfAChangedFileAgainstHead;
var
  Dir, Output, Text, FileName: string;
  Code: Cardinal;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-git-diff-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Dir);
  try
    if (PlatformRunCaptured('git', ['init', '-q', '-b', 'main', Dir], '', 15000, nil,
         Output, Code) <> srOk) or (Code <> 0) then
    begin
      Assert.Pass('git is not available');
      Exit;
    end;
    FileName := TPath.Combine(Dir, 'a.txt');
    TFile.WriteAllText(FileName, 'one' + CRLF);
    Assert.IsTrue((PlatformRunCaptured('git', ['-C', Dir, 'add', 'a.txt'], '', 15000, nil,
      Output, Code) = srOk) and (Code = 0), 'add');
    Assert.IsTrue((PlatformRunCaptured('git', ['-C', Dir, '-c', 'user.name=t', '-c',
      'user.email=t@example.com', 'commit', '-q', '-m', 'first'], '', 15000, nil,
      Output, Code) = srOk) and (Code = 0), 'commit');
    Assert.IsTrue(ReadGitDiff(FileName, False, nil, Text) = gdNoChanges, 'clean file');
    TFile.WriteAllText(FileName, 'one' + CRLF + 'two' + CRLF);
    Assert.IsTrue(ReadGitDiff(FileName, False, nil, Text) = gdOk, 'changed file');
    Assert.IsTrue(Pos('+two', Text) > 0, 'the added line is in the diff: ' + Text);
    Assert.IsTrue(ReadGitDiff(Dir, True, nil, Text) = gdOk, 'changed folder');
    Assert.IsTrue(Pos('a.txt', Text) > 0, 'the folder diff names the file');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestGitStatus.TestDiffOutsideAWorkTreeIsNotARepo;
var
  Dir, Text: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-git-diff-none-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Dir);
  try
    if IsInsideGitWorkTree(Dir) then
      Exit;
    TFile.WriteAllText(TPath.Combine(Dir, 'a.txt'), 'x');
    Assert.IsTrue(ReadGitDiff(TPath.Combine(Dir, 'a.txt'), False, nil, Text) = gdNotRepo);
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestGitStatus.TestDiffFileKeepsTheTextAndGetsADiffExtension;
var
  Path: string;
begin
  Path := WriteDiffFile('some name.txt', '+line' + CRLF);
  try
    Assert.AreEqual('some name.txt.diff', TPath.GetFileName(Path));
    Assert.AreEqual('+line' + CRLF, TFile.ReadAllText(Path, TEncoding.UTF8));
  finally
    TFile.Delete(Path);
  end;
end;

procedure TTestGitStatus.TestMarksNameTheRowsOfTheFolder;
var
  Obj: TJSONObject;
  Z: string;
begin
  Z := ' M changed.txt' + #0 + 'A  staged.txt' + #0 + '?? new.txt' + #0 +
    'UU clash.txt' + #0 + 'AM both.txt' + #0 + '!! ignored.log' + #0 + '?? dir/' + #0 +
    ' M dir2/a.txt' + #0 + 'A  dir2/b.txt' + #0;
  Obj := TJSONObject.ParseJSONValue(GitMarksJson(Z, '')) as TJSONObject;
  try
    Assert.AreEqual('warn', Obj.Values['changed.txt'].Value);
    Assert.AreEqual('ok', Obj.Values['staged.txt'].Value);
    Assert.AreEqual('info', Obj.Values['new.txt'].Value);
    Assert.AreEqual('error', Obj.Values['clash.txt'].Value);
    Assert.AreEqual('warn', Obj.Values['both.txt'].Value, 'staged and edited again');
    Assert.IsNull(Obj.Values['ignored.log'], 'ignored files are not marked');
    Assert.AreEqual('info', Obj.Values['dir'].Value, 'untracked folder');
    Assert.AreEqual('warn', Obj.Values['dir2'].Value, 'the folder takes the most urgent state inside');
  finally
    Obj.Free;
  end;
end;

procedure TTestGitStatus.TestMarksOfASubfolderUseItsPrefix;
var
  Obj: TJSONObject;
  Z: string;
begin
  Z := ' M top.txt' + #0 + ' M sub/in.txt' + #0 + '?? sub/deep/x.txt' + #0;
  Obj := TJSONObject.ParseJSONValue(GitMarksJson(Z, 'sub/')) as TJSONObject;
  try
    Assert.AreEqual(2, Obj.Count);
    Assert.AreEqual('warn', Obj.Values['in.txt'].Value);
    Assert.AreEqual('info', Obj.Values['deep'].Value);
  finally
    Obj.Free;
  end;
end;

procedure TTestGitStatus.TestRenamedFileTakesOnePathOnly;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.ParseJSONValue(
    GitMarksJson('R  new.txt' + #0 + 'old.txt' + #0 + ' M other.txt' + #0, '')) as TJSONObject;
  try
    Assert.AreEqual('ok', Obj.Values['new.txt'].Value);
    Assert.IsNull(Obj.Values['old.txt'], 'the old path is skipped');
    Assert.AreEqual('warn', Obj.Values['other.txt'].Value);
  finally
    Obj.Free;
  end;
end;

procedure TTestGitStatus.TestPanelFoldersAreLocalAndUnique;
const
  Json = '{"active":"left","left":{"uri":"file:///C:/a"},"right":{"uri":"file:///C:/a"}}';
var
  Uris: TArray<string>;
begin
  Uris := PanelFolderUris(Json);
  Assert.AreEqual(1, Integer(Length(Uris)), 'same folder in both panels');
  Uris := PanelFolderUris('{"left":{"uri":"file:///C:/a"},"right":{"uri":"sftp://host/x"}}');
  Assert.AreEqual(1, Integer(Length(Uris)), 'a remote folder is left out');
  Assert.AreEqual(0, Integer(Length(PanelFolderUris(''))), 'no panels');
end;

procedure TTestGitStatus.TestMarksOfARealRepository;
var
  Dir, Output, Json: string;
  Code: Cardinal;
  Obj: TJSONObject;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-git-marks-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Dir);
  try
    if (PlatformRunCaptured('git', ['init', '-q', '-b', 'main', Dir], '', 15000, nil,
         Output, Code) <> srOk) or (Code <> 0) then
    begin
      Assert.Pass('git is not available');
      Exit;
    end;
    TDirectory.CreateDirectory(TPath.Combine(Dir, 'sub'));
    TFile.WriteAllText(TPath.Combine(Dir, 'sub' + PathDelim + 'x.txt'), 'x');
    TFile.WriteAllText(TPath.Combine(Dir, 'top.txt'), 'x');
    Assert.IsTrue((PlatformRunCaptured('git', ['-C', Dir, 'add', '.'], '', 15000, nil,
      Output, Code) = srOk) and (Code = 0), 'add');
    Assert.IsTrue((PlatformRunCaptured('git', ['-C', Dir, '-c', 'user.name=t', '-c',
      'user.email=t@example.com', 'commit', '-q', '-m', 'first'], '', 15000, nil,
      Output, Code) = srOk) and (Code = 0), 'commit');
    TFile.WriteAllText(TPath.Combine(Dir, 'sub' + PathDelim + 'x.txt'), 'changed');
    TFile.WriteAllText(TPath.Combine(Dir, 'sub' + PathDelim + 'new.txt'), 'x');
    Assert.IsTrue(ReadGitMarks(Dir, nil, Json), 'root');
    Obj := TJSONObject.ParseJSONValue(Json) as TJSONObject;
    try
      Assert.AreEqual(1, Obj.Count);
      Assert.AreEqual('warn', Obj.Values['sub'].Value);
    finally
      Obj.Free;
    end;
    Assert.IsTrue(ReadGitMarks(TPath.Combine(Dir, 'sub'), nil, Json), 'subfolder');
    Obj := TJSONObject.ParseJSONValue(Json) as TJSONObject;
    try
      Assert.AreEqual(2, Obj.Count);
      Assert.AreEqual('warn', Obj.Values['x.txt'].Value);
      Assert.AreEqual('info', Obj.Values['new.txt'].Value);
    finally
      Obj.Free;
    end;
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGitStatus);

end.
