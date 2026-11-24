unit TestArchiveTest;

{ uArchiveTest: a healthy ZIP passes; a flipped byte in stored data and a
  truncated archive are reported; cancel stops the run. Throw-away files in
  %TEMP%. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestArchiveTest = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestHealthyArchivePasses;
    [Test] procedure TestFlippedByteIsReported;
    [Test] procedure TestTruncatedArchiveRaises;
    [Test] procedure TestCancelStopsTheRun;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, System.Zip,
  uArchiveTest;

var
  Dir: string;

function MakeZip(const AName: string; ACompression: TZipCompression): string;
var
  Z: TZipFile;
  Data: TBytes;
  I: Integer;
  M: TBytesStream;
begin
  SetLength(Data, 5000);
  for I := 0 to High(Data) do
    Data[I] := Byte(I * 13 + I shr 5);
  Result := TPath.Combine(Dir, AName);
  Z := TZipFile.Create;
  try
    Z.Open(Result, zmWrite);
    M := TBytesStream.Create(Data);
    try
      Z.Add(M, 'a.bin', ACompression);
      M.Position := 0;
      Z.Add(M, 'sub/b.bin', ACompression);
    finally
      M.Free;
    end;
    Z.Close;
  finally
    Z.Free;
  end;
end;

procedure TTestArchiveTest.SetupFixture;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-archtest');
  if TDirectory.Exists(Dir) then
    TDirectory.Delete(Dir, True);
  ForceDirectories(Dir);
end;

procedure TTestArchiveTest.TearDownFixture;
begin
  TDirectory.Delete(Dir, True);
end;

procedure TTestArchiveTest.TestHealthyArchivePasses;
var
  R: TArchiveTestResult;
begin
  R := TestZipArchive(MakeZip('ok.zip', zcDeflate), nil);
  Assert.AreEqual(2, R.Checked, 'both files read');
  Assert.AreEqual(0, R.Failed, 'no failures');
  Assert.IsFalse(R.Cancelled);
end;

procedure TTestArchiveTest.TestFlippedByteIsReported;
var
  P: string;
  B: TBytes;
  R: TArchiveTestResult;
begin
  P := MakeZip('flip.zip', zcStored);
  B := TFile.ReadAllBytes(P);
  B[100] := B[100] xor $FF; // inside the first entry's stored data
  TFile.WriteAllBytes(P, B);
  R := TestZipArchive(P, nil);
  Assert.AreEqual(1, R.Failed, 'one damaged entry');
  Assert.AreEqual(1, Integer(Length(R.Errors)), 'one message');
  Assert.IsTrue(R.Errors[0].StartsWith('a.bin: '), 'names the entry');
end;

procedure TTestArchiveTest.TestTruncatedArchiveRaises;
var
  P: string;
  B: TBytes;
  Raised: Boolean;
begin
  P := MakeZip('cut.zip', zcDeflate);
  B := TFile.ReadAllBytes(P);
  SetLength(B, Length(B) div 2);
  TFile.WriteAllBytes(P, B);
  Raised := False;
  try
    TestZipArchive(P, nil);
  except
    on Exception do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'a lost central directory is an error');
end;

procedure TTestArchiveTest.TestCancelStopsTheRun;
var
  R: TArchiveTestResult;
begin
  R := TestZipArchive(MakeZip('cancel.zip', zcDeflate),
    function: Boolean
    begin
      Result := True;
    end);
  Assert.IsTrue(R.Cancelled, 'cancelled');
  Assert.AreEqual(0, R.Checked, 'nothing checked after an immediate cancel');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestArchiveTest);

end.
