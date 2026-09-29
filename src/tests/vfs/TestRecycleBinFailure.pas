unit TestRecycleBinFailure;

{ Deleting into the Recycle Bin when the Shell cannot move an item (a file
  held open inside the folder): DeleteToRecycleBin returns an error for the
  caller to act on - not a cancel, which the job would close without a
  word - and the folder stays where it was. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRecycleBinFailure = class
  public
    [Test] procedure TestLockedFileIsAnError;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, Winapi.Windows, Winapi.ActiveX,
  uVfsTypes, uFileRecycleBin;

procedure TTestRecycleBinFailure.TestLockedFileIsAnError;
var
  Dir, Locked: string;
  Hold: TFileStream;
  Err: TVfsError;
begin
  // A folder on the user's profile: temp folders may bypass the Recycle Bin.
  Dir := TPath.Combine(GetEnvironmentVariable('USERPROFILE'),
    'mtn2-recycle-failure-' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(Dir);
  Locked := TPath.Combine(Dir, 'held-open.txt');
  Hold := TFileStream.Create(Locked, fmCreate or fmShareExclusive);
  try
    Hold.WriteBuffer(PAnsiChar('busy')^, 4);
    CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
    try
      Err := TVfsError.Ok;
      DeleteToRecycleBin(Dir, Err);
    finally
      CoUninitialize;
    end;
    Assert.IsTrue(TDirectory.Exists(Dir), 'the folder stays');
    Assert.IsTrue(Err.Code <> vecOk, 'not reported as done');
    Assert.IsTrue(Err.Code <> vecCancelled,
      'not reported as cancelled: ' + Err.Message);
    Assert.IsTrue(Err.URI <> '', 'the error names the item');
  finally
    Hold.Free;
    if TDirectory.Exists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRecycleBinFailure);

end.
