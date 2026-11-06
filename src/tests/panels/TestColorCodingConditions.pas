unit TestColorCodingConditions;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestColorCodingConditions = class
  public
    [Test] procedure ParsesAndWritesTerms;
    [Test] procedure RejectsUnknownTerms;
    [Test] procedure SizeLimitsAreStrict;
    [Test] procedure SizeNeverMatchesAFolderOrUnknownSize;
    [Test] procedure AgeComparesWithTheModificationTime;
    [Test] procedure AttributesRequiredAndExcluded;
    [Test] procedure GroupWithConditionPicksTheColorOnlyWhenMet;
    [Test] procedure ConditionSurvivesTheJsonRoundTrip;
    [Test] procedure UnreadableConditionInJsonLeavesTheGroupUnrestricted;
  end;

implementation

uses
  System.SysUtils, System.UITypes,
  uColorCoding;

function MakeItem(const AName: string; ASize: Int64; AAge: Double;
  AAttrs: TColorCodingAttrs; ANow: TDateTime): TColorCodingItem;
begin
  Result := ColorCodingNameItem(AName, False);
  Result.Size := ASize;
  Result.ModTime := ANow - AAge;
  Result.Attrs := AAttrs;
end;

function ParseOk(const AText: string): TColorCodingCondition;
begin
  Assert.IsTrue(ColorCodingParseCondition(AText, Result), 'parses: ' + AText);
end;

procedure TTestColorCodingConditions.ParsesAndWritesTerms;
var
  C: TColorCodingCondition;
begin
  C := ParseOk('size>10M size<1G age<7d age>2w +HS -R');
  Assert.IsTrue(C.HasMinSize and (C.MinSize = 10 * 1024 * 1024), 'min size');
  Assert.IsTrue(C.HasMaxSize and (C.MaxSize = Int64(1) shl 30), 'max size');
  Assert.AreEqual(Int64(7 * 86400), C.NewerSecs, 'newer than 7 days');
  Assert.AreEqual(Int64(14 * 86400), C.OlderSecs, 'older than 2 weeks');
  Assert.IsTrue(C.Require = [ccatHidden, ccatSystem], 'required attributes');
  Assert.IsTrue(C.Exclude = [ccatReadOnly], 'excluded attributes');
  Assert.AreEqual('size>10m size<1g age<1w age>2w +HS -R',
    ColorCodingConditionText(C), 'canonical text');
  Assert.AreEqual('', ColorCodingConditionText(ParseOk('')), 'blank is no condition');
  Assert.AreEqual('size>500', ColorCodingConditionText(ParseOk('SIZE>500')), 'bytes, any case');
  Assert.AreEqual('age<90m', ColorCodingConditionText(ParseOk('age<90m')), 'minutes');
end;

procedure TTestColorCodingConditions.RejectsUnknownTerms;
var
  C: TColorCodingCondition;
  Text: string;
begin
  for Text in ['size', 'size>', 'size>x', 'size>10Q', 'age<7', 'age<0d', 'colour>1',
    '+Z', '+', 'size=5'] do
    Assert.IsFalse(ColorCodingParseCondition(Text, C), 'rejected: ' + Text);
end;

procedure TTestColorCodingConditions.SizeLimitsAreStrict;
var
  C: TColorCodingCondition;
  Now: TDateTime;
begin
  Now := EncodeDate(2026, 6, 1);
  C := ParseOk('size>1K size<2K');
  Assert.IsFalse(ColorCodingConditionMet(C, MakeItem('a', 1024, 1, [], Now), Now), 'equal to the lower bound');
  Assert.IsTrue(ColorCodingConditionMet(C, MakeItem('a', 1025, 1, [], Now), Now), 'inside');
  Assert.IsFalse(ColorCodingConditionMet(C, MakeItem('a', 2048, 1, [], Now), Now), 'equal to the upper bound');
  C := ParseOk('size>0');
  Assert.IsFalse(ColorCodingConditionMet(C, MakeItem('a', 0, 1, [], Now), Now), 'empty file is not above 0');
end;

procedure TTestColorCodingConditions.SizeNeverMatchesAFolderOrUnknownSize;
var
  C: TColorCodingCondition;
  Now: TDateTime;
  Dir: TColorCodingItem;
begin
  Now := EncodeDate(2026, 6, 1);
  Dir := ColorCodingNameItem('d', True);
  C := ParseOk('size<1G');
  Assert.IsFalse(ColorCodingConditionMet(C, Dir, Now), 'folder has no size');
  Assert.IsTrue(ColorCodingConditionMet(ParseOk(''), Dir, Now),
    'no condition accepts a folder');
end;

procedure TTestColorCodingConditions.AgeComparesWithTheModificationTime;
var
  C: TColorCodingCondition;
  Now: TDateTime;
  NoTime: TColorCodingItem;
begin
  Now := EncodeDate(2026, 6, 1);
  C := ParseOk('age<7d');
  Assert.IsTrue(ColorCodingConditionMet(C, MakeItem('a', 1, 3, [], Now), Now), '3 days old');
  Assert.IsFalse(ColorCodingConditionMet(C, MakeItem('a', 1, 8, [], Now), Now), '8 days old');
  C := ParseOk('age>30d');
  Assert.IsTrue(ColorCodingConditionMet(C, MakeItem('a', 1, 45, [], Now), Now), '45 days old');
  Assert.IsFalse(ColorCodingConditionMet(C, MakeItem('a', 1, 2, [], Now), Now), '2 days old');
  NoTime := MakeItem('a', 1, 0, [], Now);
  NoTime.ModTime := 0;
  Assert.IsFalse(ColorCodingConditionMet(C, NoTime, Now), 'unknown time never matches an age');
end;

procedure TTestColorCodingConditions.AttributesRequiredAndExcluded;
var
  C: TColorCodingCondition;
  Now: TDateTime;
begin
  Now := EncodeDate(2026, 6, 1);
  C := ParseOk('+H -R');
  Assert.IsTrue(ColorCodingConditionMet(C, MakeItem('a', 1, 1, [ccatHidden], Now), Now), 'hidden');
  Assert.IsFalse(ColorCodingConditionMet(C, MakeItem('a', 1, 1, [], Now), Now), 'not hidden');
  Assert.IsFalse(ColorCodingConditionMet(C, MakeItem('a', 1, 1, [ccatHidden, ccatReadOnly], Now), Now),
    'hidden but read-only');
  C := ParseOk('+H -H');
  Assert.IsTrue(C.Require = [], 'the later sign wins: not required');
  Assert.IsTrue(C.Exclude = [ccatHidden], 'the later sign wins: excluded');
end;

procedure TTestColorCodingConditions.GroupWithConditionPicksTheColorOnlyWhenMet;
var
  Groups: TArray<TColorCodingGroup>;
  Big, Small: TColorCodingItem;
  Fg, Bg: TAlphaColor;
begin
  Assert.IsTrue(ParseColorCodingJson(
    '{"groups":[' +
    '{"name":"Big logs","mask":"*.log","when":"size>1M","sortPriority":3,"normal":{"fg":"#FF0000"}},' +
    '{"name":"Logs","mask":"*.log","normal":{"fg":"#00FF00"}}]}', Groups), 'parses');
  SetActiveColorCodingGroups(Groups);
  Big := ColorCodingNameItem('a.log', False);
  Big.Size := 5 * 1024 * 1024;
  Small := ColorCodingNameItem('b.log', False);
  Small.Size := 10;
  Assert.IsTrue(ColorCodingResolveItem(Big, ccsNormal, Fg, Bg), 'big log');
  Assert.AreEqual(TAlphaColor($FFFF0000), Fg, 'conditional group wins for a big file');
  Assert.AreEqual(3, ColorCodingSortPriorityItem(Big), 'its priority applies');
  Assert.IsTrue(ColorCodingResolveItem(Small, ccsNormal, Fg, Bg), 'small log');
  Assert.AreEqual(TAlphaColor($FF00FF00), Fg, 'falls through to the next group');
  Assert.AreEqual(0, ColorCodingSortPriorityItem(Small), 'priority of the next group');
  Assert.IsTrue(ColorCodingResolve('c.log', False, ccsNormal, Fg, Bg), 'name-only lookup');
  Assert.AreEqual(TAlphaColor($FF00FF00), Fg, 'unknown size does not meet the condition');
end;

procedure TTestColorCodingConditions.ConditionSurvivesTheJsonRoundTrip;
var
  Groups, Again: TArray<TColorCodingGroup>;
begin
  Assert.IsTrue(ParseColorCodingJson(
    '{"fileColoring":[{"name":"Old","mask":"*","when":"age>30d +A","normal":{"fg":"#808080"}},' +
    '{"name":"Plain","mask":"*"}]}', Groups, 'fileColoring'), 'parses');
  Again := nil;
  Assert.IsTrue(ParseColorCodingJson(ColorCodingGroupsToJson(Groups), Again, 'fileColoring'),
    'written JSON parses');
  Assert.AreEqual(ColorCodingConditionText(Groups[0].Cond),
    ColorCodingConditionText(Again[0].Cond), 'condition kept');
  Assert.AreEqual(Int64(30 * 86400), Again[0].Cond.OlderSecs, 'age kept');
  Assert.IsTrue(Again[0].Cond.Require = [ccatArchive], 'attribute kept');
  Assert.AreEqual('', ColorCodingConditionText(Again[1].Cond), 'no condition stays none');
  Assert.IsFalse(ColorCodingGroupsToJson([Groups[1]]).Contains('"when"'), 'nothing written without a condition');
end;

procedure TTestColorCodingConditions.UnreadableConditionInJsonLeavesTheGroupUnrestricted;
var
  Groups: TArray<TColorCodingGroup>;
begin
  Assert.IsTrue(ParseColorCodingJson(
    '{"groups":[{"name":"X","mask":"*","when":"size>>>"}]}', Groups), 'parses');
  Assert.AreEqual('', ColorCodingConditionText(Groups[0].Cond), 'no condition');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestColorCodingConditions);
end.
