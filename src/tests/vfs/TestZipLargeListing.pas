unit TestZipLargeListing;

{ Listing a folder of a zip with tens of thousands of entries must stay
  linear: building the central-directory tree once, not comparing every new
  name with the names already listed. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestZipLargeListing = class
  public
    [Test] procedure ListingOneFolderOfManyEntriesIsFast;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip, System.Diagnostics,
  uVfsTypes, uZipVfs;

const
  cEntryCount = 40000;

procedure TTestZipLargeListing.ListingOneFolderOfManyEntriesIsFast;
var
  Dir, ZipPath: string;
  Zip: TZipFile;
  I: Integer;
  Count: Integer;
  Done: Boolean;
  Err: TVfsError;
  Watch: TStopwatch;
  Fs: IVirtualFileSystem;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-ziplist-' + TGUID.NewGuid.ToString.Trim(['{', '}']));
  TDirectory.CreateDirectory(Dir);
  try
    ZipPath := TPath.Combine(Dir, 'many.zip');
    Zip := TZipFile.Create;
    try
      Zip.Open(ZipPath, zmWrite);
      for I := 1 to cEntryCount do
        Zip.Add(TBytes(nil), Format('data/file%d.txt', [I]));
      Zip.Close;
    finally
      Zip.Free;
    end;

    Fs := TZipVirtualFileSystem.Create;
    Done := False;
    Count := -1;
    Err := TVfsError.Ok;
    Watch := TStopwatch.StartNew;
    Fs.ListDirectoryAsync(EnsureArchiveRootUri(PathToFileUri(ZipPath)) + 'data', nil,
      procedure(const AItems: TArray<TVfsEntry>; const AError: TVfsError)
      begin
        Count := Length(AItems);
        Err := AError;
        Done := True;
      end);
    while not Done and (Watch.ElapsedMilliseconds < 60000) do
      CheckSynchronize(10);
    Watch.Stop;
    Assert.IsTrue(Done and (Err.Code = vecOk), 'listing succeeds: done=' + BoolToStr(Done, True) +
      ', ' + Err.Message + ', ' + IntToStr(Watch.ElapsedMilliseconds) + ' ms');
    Assert.AreEqual<Integer>(cEntryCount, Count, 'every entry is listed once');
    Assert.IsTrue(Watch.ElapsedMilliseconds < 5000,
      'listing took ' + IntToStr(Watch.ElapsedMilliseconds) + ' ms');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestZipLargeListing);

end.
