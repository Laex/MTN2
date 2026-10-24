unit uDriveTypes;

{ Description of a volume as the Change Drive popup and the info panel show
  it. Filled by uPlatformDrives; uDriveInfo adds caching and formatting. }

interface

type
  TDriveInfo = record
    Letter: Char;        // single-character key of the volume; #0 when none
    RootPath: string;    // e.g. 'C:\' or '/home'
    KindLabel: string;   // Hard disk / Removable / Network / CD-ROM / RAM; '' unknown
    FsName: string;      // NTFS, FAT32, ext4, ...
    LabelOrPath: string; // volume label or UNC for network
    TotalBytes: Int64;
    FreeBytes: Int64;
    SerialNumber: Cardinal;
    VolumeFlags: Cardinal;
    Device: string;       // /dev/sda2, server:/export; '' when the platform has none
    MountOptions: string; // rw,noatime,...; '' when the platform has none
  end;

  TDriveInfoArray = TArray<TDriveInfo>;

/// <summary>True for a mounted file system that is machinery, not a place
/// people browse: kernel and container file systems, mounts of single files
/// (/etc/hosts in a container), runtime directories under /run (except
/// removable media), snap, docker and similar. Pure string test, no I/O.</summary>
function IsNoiseMount(const AMountPoint, AFsType: string): Boolean;

implementation

uses
  System.SysUtils;

function IsNoiseMount(const AMountPoint, AFsType: string): Boolean;
const
  cFsTypes: array[0..29] of string = ('proc', 'sysfs', 'devtmpfs', 'devpts',
    'cgroup', 'cgroup2', 'pstore', 'bpf', 'tracefs', 'debugfs', 'securityfs',
    'configfs', 'fusectl', 'mqueue', 'hugetlbfs', 'autofs', 'binfmt_misc',
    'overlay', 'aufs', 'squashfs', 'nsfs', 'rpc_pipefs', 'efivarfs', 'selinuxfs',
    'ramfs', 'fuse.gvfsd-fuse', 'fuse.portal', 'fuse.lxcfs', 'fuse.snapfuse',
    'fuse.fuse-overlayfs');
  cPrefixes: array[0..12] of string = ('/proc', '/sys', '/snap/', '/var/snap/',
    '/etc/', '/var/lib/docker', '/var/lib/containers',
    '/var/lib/kubelet', '/var/lib/lxcfs', '/var/lib/snapd', '/var/lib/incus',
    '/var/lib/lxd', '/run/');
var
  I: Integer;
begin
  Result := True;
  if AMountPoint = '' then
    Exit;
  for I := Low(cFsTypes) to High(cFsTypes) do
    if AFsType = cFsTypes[I] then
      Exit;
  // tmpfs only where people look for files.
  if (AFsType = 'tmpfs') and (AMountPoint <> '/tmp') and (AMountPoint <> '/dev/shm') then
    Exit;
  if AMountPoint.StartsWith('/run/media/') then
    Exit(False);
  for I := Low(cPrefixes) to High(cPrefixes) do
    if AMountPoint.StartsWith(cPrefixes[I]) or (AMountPoint + '/' = cPrefixes[I]) then
      Exit;
  Result := False;
end;

end.
