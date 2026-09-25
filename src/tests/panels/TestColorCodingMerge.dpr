program TestColorCodingMerge;

{$APPTYPE CONSOLE}

{ Checks for uColorCoding's merge-by-name logic (embedded THEME_DEFAULT's
  "fileColoring" merged with the active theme file's "fileColoring" — see
  the unit header comment and ARCHITECTURE.md). Works against literal JSON
  strings, not embedded RCDATA — MergeColorCodingGroups / ParseColorCodingJson
  are pure functions, no resource lookup involved. }

uses
  System.SysUtils, System.UITypes,
  uColorCoding in '..\..\Core\uColorCoding.pas';

var
  Failed: Integer;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if ACond then
    Writeln('  OK  ', AMsg)
  else
  begin
    Inc(Failed);
    Writeln('  FAIL ', AMsg);
  end;
end;

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
  Writeln('ParseColorCodingJson with the default "groups" key');
  Ok := ParseColorCodingJson(
    '{"groups":[{"name":"Archives","mask":"*.zip;*.rar","normal":{"fg":"#FF55FF"}}]}',
    Groups);
  Expect(Ok, 'parses successfully');
  Expect(Length(Groups) = 1, 'one group parsed');
  Expect(Groups[0].Name = 'Archives', 'name read correctly');
  Expect(Length(Groups[0].Masks) = 2, 'mask list split on ;');
  Expect(Groups[0].Colors[ccsNormal].Fg = TAlphaColor($FFFF55FF), 'normal.fg hex parsed');
  Expect(Groups[0].Colors[ccsSelected].Fg = 0, 'selected left unset (0)');
end;

procedure TestParseFileColoringKey;
var
  Groups: TArray<TColorCodingGroup>;
  Ok: Boolean;
begin
  Writeln('ParseColorCodingJson with "fileColoring" key (theme file shape)');
  Ok := ParseColorCodingJson(
    '{"fileColoring":[{"name":"Archives","mask":"*.zip","normal":{"fg":"#FF55FF"}}]}',
    Groups, 'fileColoring');
  Expect(Ok, 'parses successfully with the alternate array key');
  Expect(Length(Groups) = 1, 'one group parsed');

  // Wrong key for the shape actually in the JSON must not silently succeed.
  Ok := ParseColorCodingJson(
    '{"fileColoring":[{"name":"Archives","mask":"*.zip","normal":{"fg":"#FF55FF"}}]}',
    Groups); // default key 'groups' — not present in this JSON
  Expect(not Ok, 'default "groups" key does not match a "fileColoring" document');
end;

procedure TestMergeOverridesByName;
var
  Base, Override, Merged: TArray<TColorCodingGroup>;
begin
  Writeln('MergeColorCodingGroups: matching Name overrides in place (same position)');
  ParseColorCodingJson(
    '{"groups":[' +
    '{"name":"Archives","mask":"*.zip","normal":{"fg":"#FF55FF"}},' +
    '{"name":"Executables","mask":"*.exe","normal":{"fg":"#55FF55"}}' +
    ']}', Base);
  ParseColorCodingJson(
    '{"groups":[{"name":"Archives","mask":"*.zip;*.rar","normal":{"fg":"#00FF00"}}]}',
    Override);

  Merged := MergeColorCodingGroups(Base, Override);

  Expect(Length(Merged) = 2, 'override by existing name does not grow the list');
  Expect(IndexOfName(Merged, 'Archives') = 0, 'Archives keeps its original position (index 0, base list order)');
  Expect(Merged[IndexOfName(Merged, 'Archives')].Colors[ccsNormal].Fg = TAlphaColor($FF00FF00),
    'Archives'' color comes from the override, not the base');
  Expect(Length(Merged[IndexOfName(Merged, 'Archives')].Masks) = 2,
    'Archives'' mask list also comes entirely from the override');
  Expect(Merged[IndexOfName(Merged, 'Executables')].Colors[ccsNormal].Fg = TAlphaColor($FF55FF55),
    'Executables (not overridden) keeps its base color');
end;

procedure TestMergePrependsNewNames;
var
  Base, Override, Merged: TArray<TColorCodingGroup>;
begin
  Writeln('MergeColorCodingGroups: unmatched Name is prepended (checked before the base list)');
  ParseColorCodingJson(
    '{"groups":[{"name":"Documents","mask":"*.txt","normal":{"fg":"#00AAAA"}}]}', Base);
  ParseColorCodingJson(
    '{"groups":[{"name":"MyCustom","mask":"*.foo","normal":{"fg":"#FFFFFF"}}]}', Override);

  Merged := MergeColorCodingGroups(Base, Override);

  Expect(Length(Merged) = 2, 'new name grows the list by one');
  Expect(Merged[0].Name = 'MyCustom', 'new entry is prepended (checked first, so it can win ties)');
  Expect(Merged[1].Name = 'Documents', 'base entry keeps its (relative) place after the new one');
end;

procedure TestMergeIsOrderIndependentForNames;
var
  EmbeddedGroups, ActiveFileGroups, Effective: TArray<TColorCodingGroup>;
begin
  Writeln('End-to-end shape: embedded THEME_DEFAULT merged with the active theme file');
  // Mirrors uColorCoding.ReloadColorCoding's actual pipeline shape.
  ParseColorCodingJson(
    '{"fileColoring":[{"name":"Archives","mask":"*.zip","normal":{"fg":"#FF55FF"}}]}',
    EmbeddedGroups, 'fileColoring');
  ParseColorCodingJson(
    '{"fileColoring":[{"name":"Documents","mask":"*.txt","normal":{"fg":"#00AAAA"}}]}',
    ActiveFileGroups, 'fileColoring');

  Effective := MergeColorCodingGroups(EmbeddedGroups, ActiveFileGroups);

  Expect(Length(Effective) = 2, 'embedded default + active-file-only groups both present');
  Expect(IndexOfName(Effective, 'Archives') >= 0, 'embedded Archives survives into the effective list');
  Expect(IndexOfName(Effective, 'Documents') >= 0, 'active-file Documents survives into the effective list');
end;

procedure TestEnabledAndApplyToDefaultsAndParsing;
var
  Groups: TArray<TColorCodingGroup>;
begin
  Writeln('Enabled/ApplyTo: defaults when omitted, parsed when present');
  ParseColorCodingJson(
    '{"groups":[{"name":"Plain","mask":"*.plain"}]}', Groups);
  Expect(Groups[0].Enabled, 'Enabled defaults to True when "enabled" is omitted');
  Expect(Groups[0].ApplyTo = ccaFilesAndDirs, 'ApplyTo defaults to ccaFilesAndDirs when "applyTo" is omitted');

  ParseColorCodingJson(
    '{"groups":[{"name":"Off","mask":"*.off","enabled":false,"applyTo":"dirs"}]}', Groups);
  Expect(not Groups[0].Enabled, '"enabled":false parses to Enabled=False');
  Expect(Groups[0].ApplyTo = ccaDirsOnly, '"applyTo":"dirs" parses to ccaDirsOnly');

  ParseColorCodingJson(
    '{"groups":[{"name":"FilesOnly","mask":"*.f","applyTo":"files"}]}', Groups);
  Expect(Groups[0].ApplyTo = ccaFilesOnly, '"applyTo":"files" parses to ccaFilesOnly');
end;

procedure TestColorHexRoundTrip;
var
  C: TAlphaColor;
begin
  Writeln('ColorToHex / HexToColor round-trip');
  Expect(ColorToHex(0) = '', 'ColorToHex(0) is empty (unset)');
  Expect(SameText(ColorToHex(TAlphaColor($FFFF55FF)), '#FF55FF'), 'ColorToHex formats #RRGGBB');
  Expect(HexToColor('#FF55FF', C) and (C = TAlphaColor($FFFF55FF)), 'HexToColor parses with leading #');
  Expect(HexToColor('55aaCC', C) and (C = TAlphaColor($FF55AACC)), 'HexToColor parses without # (case-insensitive)');
  Expect(not HexToColor('not-a-color', C), 'HexToColor rejects garbage');
end;

procedure TestColorCodingGroupsToJsonRoundTrip;
var
  Original, RoundTripped: TArray<TColorCodingGroup>;
  Json: string;
begin
  Writeln('ColorCodingGroupsToJson: serialize then re-parse matches the original');
  ParseColorCodingJson(
    '{"fileColoring":[' +
    '{"name":"Archives","mask":"*.zip;*.rar","applyTo":"files","normal":{"fg":"#FF55FF"},"selected":{"bg":"#000000"}},' +
    '{"name":"Disabled","mask":"*.bak","enabled":false}' +
    ']}', Original, 'fileColoring');

  Json := ColorCodingGroupsToJson(Original);
  Expect(ParseColorCodingJson(Json, RoundTripped, 'fileColoring'), 'serialized JSON re-parses as "fileColoring"');
  Expect(Length(RoundTripped) = 2, 'both groups survive the round trip');

  Expect(RoundTripped[IndexOfName(RoundTripped, 'Archives')].Enabled, 'enabled:true is omitted, defaults back to True');
  Expect(RoundTripped[IndexOfName(RoundTripped, 'Archives')].ApplyTo = ccaFilesOnly, 'applyTo survives the round trip');
  Expect(Length(RoundTripped[IndexOfName(RoundTripped, 'Archives')].Masks) = 2, 'multi-mask survives the round trip');
  Expect(RoundTripped[IndexOfName(RoundTripped, 'Archives')].Colors[ccsNormal].Fg = TAlphaColor($FFFF55FF),
    'normal.fg survives the round trip');
  Expect(RoundTripped[IndexOfName(RoundTripped, 'Archives')].Colors[ccsSelected].Bg = TAlphaColor($FF000000),
    'selected.bg survives the round trip');

  Expect(not RoundTripped[IndexOfName(RoundTripped, 'Disabled')].Enabled,
    'enabled:false is written out and survives the round trip');
end;

begin
  Failed := 0;
  try
    TestParseGroupsKey;
    TestParseFileColoringKey;
    TestMergeOverridesByName;
    TestMergePrependsNewNames;
    TestMergeIsOrderIndependentForNames;
    TestEnabledAndApplyToDefaultsAndParsing;
    TestColorHexRoundTrip;
    TestColorCodingGroupsToJsonRoundTrip;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.Message);
      Halt(2);
    end;
  end;
  Writeln;
  if Failed = 0 then
  begin
    Writeln('All checks passed.');
    Halt(0);
  end;
  Writeln('Failed: ', Failed);
  Halt(1);
end.
