unit TestPosixDrives;

{ Volumes on POSIX systems: the quick list names only the mount, the details
  (file system, mount point, sizes) come with PlatformFillDriveDetails, so the
  drive cache knows it still has to query them. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPosixDrives = class
  public
    [Test] procedure QuickListLeavesDetailsOpen;
    [Test] procedure DetailsNameFileSystemAndMountPoint;
    [Test] procedure MachineryMountsAreHidden;
    [Test] procedure PlacesToBrowseAreKept;
  end;

implementation

uses
  uPlatformPaths, uPlatformDrives, uDriveTypes;

procedure TTestPosixDrives.QuickListLeavesDetailsOpen;
var
  Drives: TDriveInfoArray;
begin
  if not PlatformPosixPaths then
    Exit;
  Drives := PlatformListDrives;
  Assert.IsTrue(Length(Drives) > 0, 'the root file system is listed');
  Assert.AreEqual('', Drives[0].FsName, 'file system comes with the details');
  Assert.AreEqual(Int64(0), Drives[0].TotalBytes, 'sizes come with the details');
end;

procedure TTestPosixDrives.DetailsNameFileSystemAndMountPoint;
var
  Info: TDriveInfo;
begin
  if not PlatformPosixPaths then
    Exit;
  Assert.IsTrue(PlatformDriveByLetter(PlatformDriveLetterOfPath('/'), Info), 'volume of /');
  PlatformFillDriveDetails(Info);
  Assert.AreNotEqual('', Info.FsName, 'file system');
  Assert.AreEqual(Info.RootPath, Info.LabelOrPath, 'the mount point is shown');
  Assert.IsTrue(Info.TotalBytes > 0, 'total size');
end;

procedure TTestPosixDrives.MachineryMountsAreHidden;
begin
  Assert.IsTrue(IsNoiseMount('/proc', 'proc'), 'proc');
  Assert.IsTrue(IsNoiseMount('/run/user/1000', 'tmpfs'), 'per-user tmpfs');
  Assert.IsTrue(IsNoiseMount('/var/lib/docker/overlay2/x/merged', 'overlay'), 'container overlay');
  Assert.IsTrue(IsNoiseMount('/etc/hosts', 'ext4'), 'single-file bind mount');
  Assert.IsTrue(IsNoiseMount('/run/credentials/x', 'ramfs'), 'credentials ramfs');
  Assert.IsTrue(IsNoiseMount('/run/snapd/ns', 'tmpfs'), 'snap namespaces');
  Assert.IsTrue(IsNoiseMount('/snap/core/1', 'squashfs'), 'snap image');
  Assert.IsTrue(IsNoiseMount('', 'ext4'), 'no mount point');
end;

procedure TTestPosixDrives.PlacesToBrowseAreKept;
begin
  Assert.IsFalse(IsNoiseMount('/', 'ext4'), 'root');
  Assert.IsFalse(IsNoiseMount('/home', 'btrfs'), 'home');
  Assert.IsFalse(IsNoiseMount('/boot/efi', 'vfat'), 'efi partition');
  Assert.IsFalse(IsNoiseMount('/mnt/data', 'xfs'), 'data disk');
  Assert.IsFalse(IsNoiseMount('/run/media/user/USB', 'exfat'), 'removable media');
  Assert.IsFalse(IsNoiseMount('/tmp', 'tmpfs'), 'tmp');
  Assert.IsFalse(IsNoiseMount('/srv/share', 'nfs4'), 'network mount');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPosixDrives);

end.
