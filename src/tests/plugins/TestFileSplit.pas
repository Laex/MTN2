unit TestFileSplit;

{ uFileSplit: size parsing, part names, splitting a file (including sizes that
  are not a multiple of the part size and larger than one copy block), joining
  the parts back byte for byte, cancel cleanup, refusal to overwrite. Works
  on throw-away files in %TEMP%. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFileSplit = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestParseSize;
    [Test] procedure TestPartNames;
    [Test] procedure TestSplitAndCombineRoundTrip;
    [Test] procedure TestExactMultipleAndEmptyFile;
    [Test] procedure TestCancelRemovesParts;
    [Test] procedure TestRefusesToOverwrite;
    [Test] procedure TestCollectStopsAtGap;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes,
  uFileSplit;

var
  Dir: string;

function MakeFile(const AName: string; ASize: Integer): string;
var
  Data: TBytes;
  I: Integer;
begin
  SetLength(Data, ASize);
  for I := 0 to High(Data) do
    Data[I] := Byte(I * 7 + I shr 9);
  Result := TPath.Combine(Dir, AName);
  TFile.WriteAllBytes(Result, Data);
end;

function Cnt(const A: TArray<string>): Integer;
begin
  Result := Length(A);
end;

function SameBytes(const A, B: string): Boolean;
var
  X, Y: TBytes;
begin
  X := TFile.ReadAllBytes(A);
  Y := TFile.ReadAllBytes(B);
  Result := (Length(X) = Length(Y)) and CompareMem(X, Y, Length(X));
end;

procedure TTestFileSplit.SetupFixture;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-split-test');
  if TDirectory.Exists(Dir) then
    TDirectory.Delete(Dir, True);
  ForceDirectories(Dir);
end;

procedure TTestFileSplit.TearDownFixture;
begin
  TDirectory.Delete(Dir, True);
end;

procedure TTestFileSplit.TestParseSize;
var
  N: Int64;
begin
  Assert.IsTrue(ParseSplitSize('1000', N) and (N = 1000), 'plain bytes');
  Assert.IsTrue(ParseSplitSize('64k', N) and (N = 65536), 'K');
  Assert.IsTrue(ParseSplitSize('700 MB', N) and (N = 700 * 1024 * 1024), 'MB with space');
  Assert.IsTrue(ParseSplitSize('1.44M', N) and (N = Trunc(1.44 * 1024 * 1024)), 'fraction');
  Assert.IsTrue(ParseSplitSize('1,5K', N) and (N = 1536), 'comma decimal');
  Assert.IsTrue(ParseSplitSize('4G', N) and (N = Int64(4) * 1024 * 1024 * 1024), 'G');
  Assert.IsFalse(ParseSplitSize('', N), 'empty');
  Assert.IsFalse(ParseSplitSize('abc', N), 'text');
  Assert.IsFalse(ParseSplitSize('0', N), 'zero');
  Assert.IsFalse(ParseSplitSize('-5M', N), 'negative');
  Assert.IsFalse(ParseSplitSize('M', N), 'unit only');
end;

procedure TTestFileSplit.TestPartNames;
var
  Base: string;
  Idx: Integer;
begin
  Assert.AreEqual('a.bin.001', SplitPartName('a.bin', 1), 'first');
  Assert.AreEqual('a.bin.1000', SplitPartName('a.bin', 1000), 'four digits');
  Assert.IsTrue(SplitPartInfo('a.bin.007', Base, Idx) and (Base = 'a.bin') and (Idx = 7),
    'part info');
  Assert.IsFalse(SplitPartInfo('a.bin', Base, Idx), 'no number');
  Assert.IsFalse(SplitPartInfo('a.12', Base, Idx), 'two digits are an ordinary extension');
  Assert.IsFalse(SplitPartInfo('a.000', Base, Idx), 'zero is not a part');
  Assert.IsFalse(SplitPartInfo('a.$1F', Base, Idx), 'hex is not a part');
  Assert.AreEqual(3, SplitPartCount(25, 10), 'ceil');
  Assert.AreEqual(1, SplitPartCount(0, 10), 'empty file');
  Assert.AreEqual(2, SplitPartCount(20, 10), 'exact multiple');
  Assert.AreEqual('x.bin', CombineDefaultName('x.bin.002'), 'default join name');
end;

procedure TTestFileSplit.TestSplitAndCombineRoundTrip;
var
  Src, Out1: string;
  Count: Integer;
  Parts: TArray<string>;
  Sub: string;
begin
  // 2.5 MB in 1 MiB parts + a 1000-byte tail: crosses the copy block size.
  Src := MakeFile('round.bin', 2 * 1024 * 1024 + 512 * 1024 + 1000);
  Sub := TPath.Combine(Dir, 'out1');
  ForceDirectories(Sub);
  Assert.IsTrue(SplitFile(Src, Sub, 1024 * 1024, nil, Count), 'split finished');
  Assert.AreEqual(3, Count, 'part count');
  Assert.AreEqual(Int64(1024 * 1024), TFile.GetSize(TPath.Combine(Sub, 'round.bin.001')),
    'first part is full');
  Assert.AreEqual(Int64(512 * 1024 + 1000), TFile.GetSize(TPath.Combine(Sub, 'round.bin.003')),
    'last part is the rest');
  Parts := CollectSplitParts(TPath.Combine(Sub, 'round.bin.002'));
  Assert.AreEqual(3, Cnt(Parts), 'all parts found from a middle one');
  Out1 := TPath.Combine(Dir, 'round.joined');
  Assert.IsTrue(CombineParts(Parts, Out1, nil), 'join finished');
  Assert.IsTrue(SameBytes(Src, Out1), 'joined file equals the original');
  Assert.IsFalse(TFile.Exists(Out1 + '.tmp'), 'no temporary file is left');
end;

procedure TTestFileSplit.TestExactMultipleAndEmptyFile;
var
  Src, Sub: string;
  Count: Integer;
begin
  Sub := TPath.Combine(Dir, 'out2');
  ForceDirectories(Sub);
  Src := MakeFile('exact.bin', 4096);
  Assert.IsTrue(SplitFile(Src, Sub, 2048, nil, Count), 'exact split');
  Assert.AreEqual(2, Count, 'no empty trailing part');
  Assert.IsFalse(TFile.Exists(TPath.Combine(Sub, 'exact.bin.003')), 'no third part');
  Src := MakeFile('empty.bin', 0);
  Assert.IsTrue(SplitFile(Src, Sub, 2048, nil, Count), 'empty split');
  Assert.AreEqual(1, Count, 'one empty part');
  Assert.AreEqual(Int64(0), TFile.GetSize(TPath.Combine(Sub, 'empty.bin.001')), 'part is empty');
end;

procedure TTestFileSplit.TestCancelRemovesParts;
var
  Src, Sub, Joined: string;
  Count, Calls: Integer;
  Parts: TArray<string>;
begin
  Src := MakeFile('cancel.bin', 3 * 1024 * 1024);
  Sub := TPath.Combine(Dir, 'out3');
  ForceDirectories(Sub);
  Calls := 0;
  Assert.IsFalse(SplitFile(Src, Sub, 1024 * 1024,
    function: Boolean
    begin
      Inc(Calls);
      Result := Calls > 2;
    end, Count), 'cancelled split reports False');
  Assert.AreEqual(0, Cnt(TDirectory.GetFiles(Sub, 'cancel.bin.*')), 'parts are removed');

  Assert.IsTrue(SplitFile(Src, Sub, 1024 * 1024, nil, Count), 'split for the join test');
  Parts := CollectSplitParts(TPath.Combine(Sub, 'cancel.bin.001'));
  Joined := TPath.Combine(Dir, 'cancel.joined');
  Calls := 0;
  Assert.IsFalse(CombineParts(Parts, Joined,
    function: Boolean
    begin
      Inc(Calls);
      Result := Calls > 1;
    end), 'cancelled join reports False');
  Assert.IsFalse(TFile.Exists(Joined), 'no result');
  Assert.IsFalse(TFile.Exists(Joined + '.tmp'), 'no temporary file');
end;

procedure TTestFileSplit.TestRefusesToOverwrite;
var
  Src, Sub, Joined: string;
  Count: Integer;
  Parts: TArray<string>;
  Raised: Boolean;
begin
  Src := MakeFile('keep.bin', 3000);
  Sub := TPath.Combine(Dir, 'out4');
  ForceDirectories(Sub);
  Assert.IsTrue(SplitFile(Src, Sub, 1000, nil, Count), 'first split');
  Raised := False;
  try
    SplitFile(Src, Sub, 1000, nil, Count);
  except
    on EInOutError do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'a second split into the same folder is refused');
  Assert.AreEqual(3, Cnt(CollectSplitParts(TPath.Combine(Sub, 'keep.bin.001'))),
    'the first set is untouched');

  Parts := CollectSplitParts(TPath.Combine(Sub, 'keep.bin.001'));
  Joined := MakeFile('existing.out', 10);
  Raised := False;
  try
    CombineParts(Parts, Joined, nil);
  except
    on EInOutError do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'joining onto an existing file is refused');
  Assert.AreEqual(Int64(10), TFile.GetSize(Joined), 'the existing file is untouched');

  Raised := False;
  try
    CombineParts(Parts, Parts[1], nil);
  except
    on EInOutError do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'joining onto a part is refused');
end;

procedure TTestFileSplit.TestCollectStopsAtGap;
var
  Sub: string;
begin
  Sub := TPath.Combine(Dir, 'out5');
  ForceDirectories(Sub);
  TFile.WriteAllText(TPath.Combine(Sub, 'g.001'), 'a');
  TFile.WriteAllText(TPath.Combine(Sub, 'g.002'), 'b');
  TFile.WriteAllText(TPath.Combine(Sub, 'g.004'), 'd');
  Assert.AreEqual(2, Cnt(CollectSplitParts(TPath.Combine(Sub, 'g.002'))), 'stops before the gap');
  Assert.AreEqual(2, Cnt(CollectSplitParts(TPath.Combine(Sub, 'g.004'))),
    'a part after the gap finds the run from number 1');
  Assert.AreEqual(0, Cnt(CollectSplitParts(TPath.Combine(Sub, 'plain.txt'))), 'not a part');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFileSplit);

end.
