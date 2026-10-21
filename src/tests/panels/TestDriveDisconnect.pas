unit TestDriveDisconnect;

{ Which volumes the Change Drive popup offers to disconnect with Del: removable
  and optical drives and network drives that have a letter, nothing else. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDriveDisconnect = class
  public
    [Test] procedure TestOnlyRemovableOpticalAndNetworkDrivesQualify;
    [Test] procedure TestDriveWithoutLetterDoesNotQualify;
    [Test] procedure TestRefusedDriveReportsWhy;
  end;

implementation

uses
  System.SysUtils, uDriveTypes, uPlatformDrives;

function MakeDrive(ALetter: Char; const AKind: string): TDriveInfo;
begin
  Result := Default(TDriveInfo);
  Result.Letter := ALetter;
  Result.RootPath := ALetter + ':\';
  Result.KindLabel := AKind;
end;

procedure TTestDriveDisconnect.TestOnlyRemovableOpticalAndNetworkDrivesQualify;
begin
  Assert.IsTrue(PlatformCanDisconnectDrive(MakeDrive('Y', 'Removable')), 'removable');
  Assert.IsTrue(PlatformCanDisconnectDrive(MakeDrive('Y', 'CD-ROM')), 'optical');
  Assert.IsTrue(PlatformCanDisconnectDrive(MakeDrive('Y', 'Network')), 'network');
  Assert.IsFalse(PlatformCanDisconnectDrive(MakeDrive('Y', 'Hard disk')), 'fixed disk');
  Assert.IsFalse(PlatformCanDisconnectDrive(MakeDrive('Y', 'RAM')), 'RAM disk');
  Assert.IsFalse(PlatformCanDisconnectDrive(MakeDrive('Y', '')), 'unknown kind');
end;

procedure TTestDriveDisconnect.TestDriveWithoutLetterDoesNotQualify;
var
  Share: TDriveInfo;
begin
  // A UNC share entry has neither a letter nor a mounted root of its own.
  Share := MakeDrive(#0, 'Network');
  Share.RootPath := '';
  Assert.IsFalse(PlatformCanDisconnectDrive(Share), 'a share without a letter or root');
end;

procedure TTestDriveDisconnect.TestRefusedDriveReportsWhy;
var
  Error: string;
begin
  Assert.IsFalse(PlatformDisconnectDrive(MakeDrive('Y', 'Hard disk'), Error),
    'a fixed disk is refused');
  Assert.AreNotEqual('', Error, 'the refusal carries a message');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDriveDisconnect);

end.
