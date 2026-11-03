unit TestTmpPanelCollect;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTmpPanelCollect = class
  private
    FDir: string;
    procedure Put(const ARelName, AText: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestOutputLinesBecomeExistingPaths;
    [Test] procedure TestRelativeNamesAreTakenFromTheBaseFolder;
    [Test] procedure TestGrepStyleSuffixIsCutOff;
    [Test] procedure TestFileUriAndQuotesAreAccepted;
    [Test] procedure TestRepeatedAndMissingNamesAreDropped;
    [Test] procedure TestDuplicatesAreGroupedByContent;
    [Test] procedure TestSameSizeDifferentContentIsNotADuplicate;
    [Test] procedure TestLargeFilesDifferingAfterTheHeadAreNotDuplicates;
    [Test] procedure TestEmptyFilesAreIgnored;
    [Test] procedure TestCancelledSearchReturnsNothingMore;
    [Test] procedure TestSearchReportsScanAndCompareProgress;
    [Test] procedure TestCapturesCommandOutput;
    [Test] procedure TestCommandStopsWhenAskedTo;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  uTmpPanelCollect, uTmpPanelRun;

procedure TTestTmpPanelCollect.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'mtn2-collect-' + TGUID.NewGuid.ToString.Substring(1, 8));
  TDirectory.CreateDirectory(FDir);
end;

procedure TTestTmpPanelCollect.TearDown;
begin
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

procedure TTestTmpPanelCollect.Put(const ARelName, AText: string);
var
  Path: string;
begin
  Path := TPath.Combine(FDir, StringReplace(
    StringReplace(ARelName, '/', PathDelim, [rfReplaceAll]), '\', PathDelim, [rfReplaceAll]));
  TDirectory.CreateDirectory(ExtractFilePath(Path));
  TFile.WriteAllText(Path, AText);
end;

procedure TTestTmpPanelCollect.TestOutputLinesBecomeExistingPaths;
var
  Paths: TArray<string>;
begin
  Put('a.txt', 'a');
  Put('b.txt', 'b');
  Paths := ParsePanelizeOutput(
    TPath.Combine(FDir, 'a.txt') + sLineBreak + TPath.Combine(FDir, 'b.txt') + sLineBreak, '');
  Assert.AreEqual(2, Integer(Length(Paths)));
  Assert.AreEqual(TPath.Combine(FDir, 'a.txt'), Paths[0]);
  Assert.AreEqual(TPath.Combine(FDir, 'b.txt'), Paths[1]);
end;

procedure TTestTmpPanelCollect.TestRelativeNamesAreTakenFromTheBaseFolder;
var
  Paths: TArray<string>;
begin
  Put('sub\x.txt', 'x');
  Paths := ParsePanelizeOutput('sub\x.txt' + sLineBreak + 'sub/x.txt', FDir);
  Assert.AreEqual(1, Integer(Length(Paths)));
  Assert.AreEqual(TPath.Combine(TPath.Combine(FDir, 'sub'), 'x.txt'), Paths[0]);
end;

procedure TTestTmpPanelCollect.TestGrepStyleSuffixIsCutOff;
begin
  Put('code.pas', 'x');
  Assert.AreEqual(TPath.Combine(FDir, 'code.pas'),
    ResolvePanelizedPath('code.pas:12:procedure Foo;', FDir));
end;

procedure TTestTmpPanelCollect.TestFileUriAndQuotesAreAccepted;
begin
  Put('q.txt', 'x');
  Assert.AreEqual(TPath.Combine(FDir, 'q.txt'),
    ResolvePanelizedPath('"' + TPath.Combine(FDir, 'q.txt') + '"', ''));
  Assert.AreEqual(TPath.Combine(FDir, 'q.txt'),
    ResolvePanelizedPath('file:///' + StringReplace(TPath.Combine(FDir, 'q.txt'), '\', '/', [rfReplaceAll]), ''));
end;

procedure TTestTmpPanelCollect.TestRepeatedAndMissingNamesAreDropped;
var
  Paths: TArray<string>;
begin
  Put('only.txt', 'x');
  Paths := ParsePanelizeOutput('only.txt' + sLineBreak + 'ONLY.TXT' + sLineBreak +
    'no-such-file.txt' + sLineBreak + sLineBreak + 'text without a path', FDir);
  Assert.AreEqual(1, Integer(Length(Paths)));
end;

procedure TTestTmpPanelCollect.TestDuplicatesAreGroupedByContent;
var
  Groups: TArray<TArray<string>>;
begin
  Put('one.txt', 'same content');
  Put('sub\two.txt', 'same content');
  Put('three.txt', 'other content');
  Groups := FindDuplicateGroups(FDir, 1, nil);
  Assert.AreEqual(1, Integer(Length(Groups)));
  Assert.AreEqual(2, Integer(Length(Groups[0])));
  Assert.AreEqual(TPath.Combine(FDir, 'one.txt'), Groups[0][0]);
  Assert.AreEqual(TPath.Combine(TPath.Combine(FDir, 'sub'), 'two.txt'), Groups[0][1]);
end;

procedure TTestTmpPanelCollect.TestSameSizeDifferentContentIsNotADuplicate;
begin
  Put('a.txt', 'abcd');
  Put('b.txt', 'abce');
  Assert.AreEqual(0, Integer(Length(FindDuplicateGroups(FDir, 1, nil))));
end;

procedure TTestTmpPanelCollect.TestLargeFilesDifferingAfterTheHeadAreNotDuplicates;
var
  Head: string;
  Groups: TArray<TArray<string>>;
begin
  Head := StringOfChar('x', 100 * 1024);
  Put('big1.bin', Head + 'tail one');
  Put('big2.bin', Head + 'tail two');
  Put('big3.bin', Head + 'tail one');
  Groups := FindDuplicateGroups(FDir, 1, nil);
  Assert.AreEqual(1, Integer(Length(Groups)));
  Assert.AreEqual(2, Integer(Length(Groups[0])));
  Assert.AreEqual(TPath.Combine(FDir, 'big1.bin'), Groups[0][0]);
  Assert.AreEqual(TPath.Combine(FDir, 'big3.bin'), Groups[0][1]);
end;

procedure TTestTmpPanelCollect.TestEmptyFilesAreIgnored;
begin
  Put('e1.txt', '');
  Put('e2.txt', '');
  Assert.AreEqual(0, Integer(Length(FindDuplicateGroups(FDir, 1, nil))));
end;

procedure TTestTmpPanelCollect.TestCancelledSearchReturnsNothingMore;
var
  Found: TArray<TArray<string>>;
begin
  Put('a.txt', 'same');
  Put('b.txt', 'same');
  Found := FindDuplicateGroups(FDir, 1,
    function: Boolean
    begin
      Result := True;
    end);
  Assert.AreEqual(0, Integer(Length(Found)));
end;

procedure TTestTmpPanelCollect.TestSearchReportsScanAndCompareProgress;
var
  Last, LastScan: TDupProgress;
  Dirs: TStringList;
begin
  Put('a.txt', 'same');
  Put('sub/b.txt', 'same');
  Put('sub/c.txt', 'unique one');
  Put('d.txt', 'other!');
  Last := Default(TDupProgress);
  LastScan := Default(TDupProgress);
  Dirs := TStringList.Create;
  try
    FindDuplicateGroups(FDir, 1, nil,
      procedure(const AProgress: TDupProgress)
      begin
        if not AProgress.Comparing then
        begin
          LastScan := AProgress;
          Dirs.Add(AProgress.Dir);
        end;
        Last := AProgress;
      end);
    Assert.AreEqual(4, LastScan.Scanned, 'every file is counted while scanning');
    Assert.IsTrue(Dirs.IndexOf(TPath.Combine(FDir, 'sub')) >= 0, 'the folder being read is reported');
    Assert.IsTrue(Last.Comparing);
    Assert.AreEqual(2, Last.Candidates, 'only files sharing a size are compared');
    Assert.AreEqual(2, Last.Checked);
    Assert.AreEqual(2, Last.FoundFiles);
  finally
    Dirs.Free;
  end;
end;

procedure TTestTmpPanelCollect.TestCapturesCommandOutput;
{$IFDEF MSWINDOWS}
var
  Output: string;
begin
  Put('listed.txt', 'x');
  Assert.IsTrue(RunCommandCapture('dir /b', FDir, 20000, Output));
  Assert.IsTrue(Pos('listed.txt', Output) > 0);
  Assert.AreEqual(1, Integer(Length(ParsePanelizeOutput(Output, FDir))));
  Assert.IsFalse(RunCommandCapture('ping -n 30 127.0.0.1 > nul', FDir, 300, Output));
end;
{$ELSE}
begin
  Assert.Pass('Command capture is implemented on Windows only.');
end;
{$ENDIF}

procedure TTestTmpPanelCollect.TestCommandStopsWhenAskedTo;
{$IFDEF MSWINDOWS}
var
  Output: string;
  Started: UInt64;
begin
  Started := TThread.GetTickCount64;
  Assert.IsFalse(RunCommandCapture('ping -n 30 127.0.0.1 > nul', FDir, 60000, Output,
    function: Boolean
    begin
      Result := True;
    end));
  Assert.IsTrue(TThread.GetTickCount64 - Started < 10000, 'the process is killed, not waited for');
end;
{$ELSE}
begin
  Assert.Pass('Command capture is implemented on Windows only.');
end;
{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestTmpPanelCollect);

end.
