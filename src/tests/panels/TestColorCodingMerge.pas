unit TestColorCodingMerge;

{ Checks for uColorCoding's merge-by-name logic (embedded THEME_DEFAULT's
  "fileColoring" merged with the active theme file's "fileColoring" - see
  the unit header comment and ARCHITECTURE.md). Works against literal JSON
  strings, not embedded RCDATA - MergeColorCodingGroups / ParseColorCodingJson
  are pure functions, no resource lookup involved. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestColorCodingMerge = class
  public
    [SetupFixture] procedure SetupFixture;
    [Test] procedure TestParseGroupsKey;
    [Test] procedure TestParseFileColoringKey;
    [Test] procedure TestMergeOverridesByName;
    [Test] procedure TestMergePrependsNewNames;
    [Test] procedure TestMergeIsOrderIndependentForNames;
    [Test] procedure TestEnabledAndApplyToDefaultsAndParsing;
    [Test] procedure TestColorHexRoundTrip;
    [Test] procedure TestColorCodingGroupsToJsonRoundTrip;
  end;

implementation

uses
  System.SysUtils, System.UITypes,
  uColorCoding;

function IndexOfName(const AGroups: TArray<TColorCodingGroup>; const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AGroups) do
    if SameText(AGroups[I].Name, AName) then
      Exit(I);
  Result := -1;
end;

procedure TestParseGroupsKey;
var
  Groups: TArray<TColorCodingGroup>;
  Ok: Boolean;
begin
  Ok := ParseColorCodingJson(
    '{"groups":[{"name":"Archives","mask":"*.zip;*.rar","normal":{"fg":"#FF55FF"}}]}',
    Groups);
  Assert.IsTrue(Ok, 'parses successfully');
  Assert.IsTrue(Length(Groups) = 1, 'one group parsed');
  Assert.IsTrue(Groups[0].Name = 'Archives', 'name read correctly');
  Assert.IsTrue(Length(Groups[0].Masks) = 2, 'mask list split on ;');
  Assert.IsTrue(Groups[0].Colors[ccsNormal].Fg = TAlphaColor($FFFF55FF), 'normal.fg hex parsed');
  Assert.IsTrue(Groups[0].Colors[ccsSelected].Fg = 0, 'selected left unset (0)');
end;

procedure TestParseFileColoringKey;
var
  Groups: TArray<TColorCodingGroup>;
  Ok: Boolean;
begin
  Ok := ParseColorCodingJson(
    '{"fileColoring":[{"name":"Archives","mask":"*.zip","normal":{"fg":"#FF55FF"}}]}',
    Groups, 'fileColoring');
  Assert.IsTrue(Ok, 'parses successfully with the alternate array key');
  Assert.IsTrue(Length(Groups) = 1, 'one group parsed');

  // Wrong key for the shape actually in the JSON must not silently succeed.
  Ok := ParseColorCodingJson(
    '{"fileColoring":[{"name":"Archives","mask":"*.zip","normal":{"fg":"#FF55FF"}}]}',
    Groups); // default key 'groups' - not present in this JSON
  Assert.IsTrue(not Ok, 'default "groups" key does not match a "fileColoring" document');
end;

procedure TestMergeOverridesByName;
var
  Base, Override, Merged: TArray<TColorCodingGroup>;
begin
  ParseColorCodingJson(
    '{"groups":[' +
    '{"name":"Archives","mask":"*.zip","normal":{"fg":"#FF55FF"}},' +
    '{"name":"Executables","mask":"*.exe","normal":{"fg":"#55FF55"}}' +
    ']}', Base);
  ParseColorCodingJson(
    '{"groups":[{"name":"Archives","mask":"*.zip;*.rar","normal":{"fg":"#00FF00"}}]}',
    Override);

  Merged := MergeColorCodingGroups(Base, Override);

  Assert.IsTrue(Length(Merged) = 2, 'override by existing name does not grow the list');
  Assert.IsTrue(IndexOfName(Merged, 'Archives') = 0, 'Archives keeps its original position (index 0, base list order)');
  Assert.IsTrue(Merged[IndexOfName(Merged, 'Archives')].Colors[ccsNormal].Fg = TAlphaColor($FF00FF00),
    'Archives'' color comes from the override, not the base');
  Assert.IsTrue(Length(Merged[IndexOfName(Merged, 'Archives')].Masks) = 2,
    'Archives'' mask list also comes entirely from the override');
  Assert.IsTrue(Merged[IndexOfName(Merged, 'Executables')].Colors[ccsNormal].Fg = TAlphaColor($FF55FF55),
    'Executables (not overridden) keeps its base color');
end;

procedure TestMergePrependsNewNames;
var
  Base, Override, Merged: TArray<TColorCodingGroup>;
begin
  ParseColorCodingJson(
    '{"groups":[{"name":"Documents","mask":"*.txt","normal":{"fg":"#00AAAA"}}]}', Base);
  ParseColorCodingJson(
    '{"groups":[{"name":"MyCustom","mask":"*.foo","normal":{"fg":"#FFFFFF"}}]}', Override);

  Merged := MergeColorCodingGroups(Base, Override);

  Assert.IsTrue(Length(Merged) = 2, 'new name grows the list by one');
  Assert.IsTrue(Merged[0].Name = 'MyCustom', 'new entry is prepended (checked first, so it can win ties)');
  Assert.IsTrue(Merged[1].Name = 'Documents', 'base entry keeps its (relative) place after the new one');
end;

procedure TestMergeIsOrderIndependentForNames;
var
  EmbeddedGroups, ActiveFileGroups, Effective: TArray<TColorCodingGroup>;
begin
  // Mirrors uColorCoding.ReloadColorCoding's actual pipeline shape.
  ParseColorCodingJson(
    '{"fileColoring":[{"name":"Archives","mask":"*.zip","normal":{"fg":"#FF55FF"}}]}',
    EmbeddedGroups, 'fileColoring');
  ParseColorCodingJson(
    '{"fileColoring":[{"name":"Documents","mask":"*.txt","normal":{"fg":"#00AAAA"}}]}',
    ActiveFileGroups, 'fileColoring');

  Effective := MergeColorCodingGroups(EmbeddedGroups, ActiveFileGroups);

  Assert.IsTrue(Length(Effective) = 2, 'embedded default + active-file-only groups both present');
  Assert.IsTrue(IndexOfName(Effective, 'Archives') >= 0, 'embedded Archives survives into the effective list');
  Assert.IsTrue(IndexOfName(Effective, 'Documents') >= 0, 'active-file Documents survives into the effective list');
end;

procedure TestEnabledAndApplyToDefaultsAndParsing;
var
  Groups: TArray<TColorCodingGroup>;
begin
  ParseColorCodingJson(
    '{"groups":[{"name":"Plain","mask":"*.plain"}]}', Groups);
  Assert.IsTrue(Groups[0].Enabled, 'Enabled defaults to True when "enabled" is omitted');
  Assert.IsTrue(Groups[0].ApplyTo = ccaFilesAndDirs, 'ApplyTo defaults to ccaFilesAndDirs when "applyTo" is omitted');

  ParseColorCodingJson(
    '{"groups":[{"name":"Off","mask":"*.off","enabled":false,"applyTo":"dirs"}]}', Groups);
  Assert.IsTrue(not Groups[0].Enabled, '"enabled":false parses to Enabled=False');
  Assert.IsTrue(Groups[0].ApplyTo = ccaDirsOnly, '"applyTo":"dirs" parses to ccaDirsOnly');

  ParseColorCodingJson(
    '{"groups":[{"name":"FilesOnly","mask":"*.f","applyTo":"files"}]}', Groups);
  Assert.IsTrue(Groups[0].ApplyTo = ccaFilesOnly, '"applyTo":"files" parses to ccaFilesOnly');
end;

procedure TestColorHexRoundTrip;
var
  C: TAlphaColor;
begin
  Assert.IsTrue(ColorToHex(0) = '', 'ColorToHex(0) is empty (unset)');
  Assert.IsTrue(SameText(ColorToHex(TAlphaColor($FFFF55FF)), '#FF55FF'), 'ColorToHex formats #RRGGBB');
  Assert.IsTrue(HexToColor('#FF55FF', C) and (C = TAlphaColor($FFFF55FF)), 'HexToColor parses with leading #');
  Assert.IsTrue(HexToColor('55aaCC', C) and (C = TAlphaColor($FF55AACC)), 'HexToColor parses without # (case-insensitive)');
  Assert.IsTrue(not HexToColor('not-a-color', C), 'HexToColor rejects garbage');
end;

procedure TestColorCodingGroupsToJsonRoundTrip;
var
  Original, RoundTripped: TArray<TColorCodingGroup>;
  Json: string;
begin
  ParseColorCodingJson(
    '{"fileColoring":[' +
    '{"name":"Archives","mask":"*.zip;*.rar","applyTo":"files","normal":{"fg":"#FF55FF"},"selected":{"bg":"#000000"}},' +
    '{"name":"Disabled","mask":"*.bak","enabled":false}' +
    ']}', Original, 'fileColoring');

  Json := ColorCodingGroupsToJson(Original);
  Assert.IsTrue(ParseColorCodingJson(Json, RoundTripped, 'fileColoring'), 'serialized JSON re-parses as "fileColoring"');
  Assert.IsTrue(Length(RoundTripped) = 2, 'both groups survive the round trip');

  Assert.IsTrue(RoundTripped[IndexOfName(RoundTripped, 'Archives')].Enabled, 'enabled:true is omitted, defaults back to True');
  Assert.IsTrue(RoundTripped[IndexOfName(RoundTripped, 'Archives')].ApplyTo = ccaFilesOnly, 'applyTo survives the round trip');
  Assert.IsTrue(Length(RoundTripped[IndexOfName(RoundTripped, 'Archives')].Masks) = 2, 'multi-mask survives the round trip');
  Assert.IsTrue(RoundTripped[IndexOfName(RoundTripped, 'Archives')].Colors[ccsNormal].Fg = TAlphaColor($FFFF55FF),
    'normal.fg survives the round trip');
  Assert.IsTrue(RoundTripped[IndexOfName(RoundTripped, 'Archives')].Colors[ccsSelected].Bg = TAlphaColor($FF000000),
    'selected.bg survives the round trip');

  Assert.IsTrue(not RoundTripped[IndexOfName(RoundTripped, 'Disabled')].Enabled,
    'enabled:false is written out and survives the round trip');
end;

{ TTestColorCodingMerge }

procedure TTestColorCodingMerge.SetupFixture;
begin
end;

procedure TTestColorCodingMerge.TestParseGroupsKey;
begin
  TestColorCodingMerge.TestParseGroupsKey;
end;

procedure TTestColorCodingMerge.TestParseFileColoringKey;
begin
  TestColorCodingMerge.TestParseFileColoringKey;
end;

procedure TTestColorCodingMerge.TestMergeOverridesByName;
begin
  TestColorCodingMerge.TestMergeOverridesByName;
end;

procedure TTestColorCodingMerge.TestMergePrependsNewNames;
begin
  TestColorCodingMerge.TestMergePrependsNewNames;
end;

procedure TTestColorCodingMerge.TestMergeIsOrderIndependentForNames;
begin
  TestColorCodingMerge.TestMergeIsOrderIndependentForNames;
end;

procedure TTestColorCodingMerge.TestEnabledAndApplyToDefaultsAndParsing;
begin
  TestColorCodingMerge.TestEnabledAndApplyToDefaultsAndParsing;
end;

procedure TTestColorCodingMerge.TestColorHexRoundTrip;
begin
  TestColorCodingMerge.TestColorHexRoundTrip;
end;

procedure TTestColorCodingMerge.TestColorCodingGroupsToJsonRoundTrip;
begin
  TestColorCodingMerge.TestColorCodingGroupsToJsonRoundTrip;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestColorCodingMerge);

end.
