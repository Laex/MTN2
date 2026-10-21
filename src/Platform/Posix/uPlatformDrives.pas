unit uPlatformDrives;

{ Volumes of the machine (Posix build: the mounted file systems, each given a
  letter so the Change Drive popup works as on Windows). The Windows build
  lives in Platform\Windows; each project puts exactly one of the two
  directories on its unit search path. }

interface

uses
  uDriveTypes;

/// <summary>Letter, root and kind of every mounted volume worth showing.
/// Never touches the volumes, so a hung network mount cannot block it.</summary>
function PlatformListDrives: TDriveInfoArray;

/// <summary>Letter, root and kind of the volume with this letter; False when
/// there is none.</summary>
function PlatformDriveByLetter(ALetter: Char; out AInfo: TDriveInfo): Boolean;

/// <summary>Letter of the volume that holds APath (the longest mount point
/// that is a prefix of it); #0 for a relative or empty path.</summary>
function PlatformDriveLetterOfPath(const APath: string): Char;

/// <summary>Fills the sizes of the volume. Queries the mount, so it can block
/// for a long time on an unresponsive network mount.</summary>
procedure PlatformFillDriveDetails(var AInfo: TDriveInfo);

/// <summary>Ends the calling thread at once, without any RTL cleanup.</summary>
procedure PlatformAbandonThread;

/// <summary>True for a volume that can be unmounted from the program: a
/// removable or optical medium or a network mount, never the root file system.
/// Does not touch the volume.</summary>
function PlatformCanDisconnectDrive(const AInfo: TDriveInfo): Boolean;

/// <summary>Unmounts the volume (udisksctl for a block device, else umount).
/// Blocks while the program runs, so call it off the UI thread. AError carries
/// the program's own message on failure.</summary>
function PlatformDisconnectDrive(const AInfo: TDriveInfo; out AError: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults, Posix.Base,
  Posix.Pthread, Posix.SysStatvfs, uPlatformInfo, uPlatformProcess;

type
  TMount = record
    MountPoint: string;
    FsType: string;
    Source: string;
  end;

const
  // First letter given to a mount; the root file system comes first.
  cFirstLetter = 'A';
  cLastLetter = 'Z';

function IsPseudoFs(const AFsType: string): Boolean;
const
  cPseudo: array[0..23] of string = ('proc', 'sysfs', 'devtmpfs', 'devpts',
    'cgroup', 'cgroup2', 'pstore', 'bpf', 'tracefs', 'debugfs', 'securityfs',
    'configfs', 'fusectl', 'mqueue', 'hugetlbfs', 'autofs', 'binfmt_misc',
    'overlay', 'squashfs', 'nsfs', 'rpc_pipefs', 'efivarfs', 'selinuxfs',
    'fuse.gvfsd-fuse');
var
  I: Integer;
begin
  for I := Low(cPseudo) to High(cPseudo) do
    if AFsType = cPseudo[I] then
      Exit(True);
  Result := False;
end;

function UnescapeMountField(const AText: string): string;
var
  I, Code: Integer;
begin
  // /proc/self/mountinfo writes space, tab, newline and backslash as \NNN.
  Result := '';
  I := 1;
  while I <= Length(AText) do
  begin
    if (AText[I] = '\') and (I + 3 <= Length(AText)) and
       TryStrToInt('0' + Copy(AText, I + 1, 3), Code) then
    begin
      Result := Result + Chr(Code);
      Inc(I, 4);
    end
    else
    begin
      Result := Result + AText[I];
      Inc(I);
    end;
  end;
end;

function ReadMounts: TArray<TMount>;
var
  Lines, Parts: TStringList;
  Line: string;
  M: TMount;
  Sep, I: Integer;
  List: TList<TMount>;
  Seen: TStringList;
begin
  List := TList<TMount>.Create;
  Lines := TStringList.Create;
  Seen := TStringList.Create;
  Parts := TStringList.Create;
  try
    Seen.Sorted := True;
    Seen.Duplicates := dupIgnore;
    Parts.Delimiter := ' ';
    Parts.StrictDelimiter := True;
    Lines.Text := PlatformReadTextFile('/proc/self/mountinfo');
    for Line in Lines do
    begin
      // id parent major:minor root mountpoint options [optional...] - fstype source superopts
      Parts.DelimitedText := Line;
      Sep := -1;
      for I := 6 to Parts.Count - 1 do
        if Parts[I] = '-' then
        begin
          Sep := I;
          Break;
        end;
      if (Sep < 0) or (Sep + 2 >= Parts.Count) then
        Continue;
      M.MountPoint := UnescapeMountField(Parts[4]);
      M.FsType := Parts[Sep + 1];
      M.Source := UnescapeMountField(Parts[Sep + 2]);
      if IsPseudoFs(M.FsType) or (M.MountPoint = '') then
        Continue;
      // tmpfs only where people look for files; skip /run/user, /sys, /dev...
      if (M.FsType = 'tmpfs') and (M.MountPoint <> '/tmp') and
         (M.MountPoint <> '/dev/shm') then
        Continue;
      if M.MountPoint.StartsWith('/snap/') or M.MountPoint.StartsWith('/var/lib/docker') or
         M.MountPoint.StartsWith('/proc') or M.MountPoint.StartsWith('/sys') then
        Continue;
      if Seen.IndexOf(M.MountPoint) >= 0 then
        Continue;
      Seen.Add(M.MountPoint);
      List.Add(M);
    end;
    List.Sort(TComparer<TMount>.Construct(
      function(const L, R: TMount): Integer
      begin
        Result := CompareStr(L.MountPoint, R.MountPoint);
      end));
    Result := List.ToArray;
  finally
    Parts.Free;
    Seen.Free;
    Lines.Free;
    List.Free;
  end;
end;

function KindOf(const AMount: TMount): string;
begin
  if (AMount.FsType = 'nfs') or (AMount.FsType = 'nfs4') or (AMount.FsType = 'cifs') or
     (AMount.FsType = 'smb3') or AMount.FsType.StartsWith('fuse.sshfs') or
     AMount.FsType.StartsWith('9p') then
    Result := 'Network'
  else if AMount.FsType = 'tmpfs' then
    Result := 'RAM'
  else if (AMount.FsType = 'iso9660') or (AMount.FsType = 'udf') then
    Result := 'CD-ROM'
  else if AMount.MountPoint.StartsWith('/media/') or AMount.MountPoint.StartsWith('/run/media/') then
    Result := 'Removable'
  else
    Result := 'Hard disk';
end;

function InfoOf(const AMount: TMount; ALetter: Char): TDriveInfo;
begin
  Result.Letter := ALetter;
  Result.RootPath := AMount.MountPoint;
  Result.KindLabel := KindOf(AMount);
  // The file system and the mount point arrive with PlatformFillDriveDetails:
  // the drive cache treats an entry that has them as already answered.
  Result.FsName := '';
  Result.LabelOrPath := '';
  Result.TotalBytes := 0;
  Result.FreeBytes := 0;
  Result.SerialNumber := 0;
  Result.VolumeFlags := 0;
end;

function PlatformListDrives: TDriveInfoArray;
var
  Mounts: TArray<TMount>;
  I, N: Integer;
begin
  Mounts := ReadMounts;
  N := Length(Mounts);
  if N > Ord(cLastLetter) - Ord(cFirstLetter) + 1 then
    N := Ord(cLastLetter) - Ord(cFirstLetter) + 1;
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := InfoOf(Mounts[I], Chr(Ord(cFirstLetter) + I));
end;

function PlatformDriveByLetter(ALetter: Char; out AInfo: TDriveInfo): Boolean;
var
  Drives: TDriveInfoArray;
  I: Integer;
begin
  Drives := PlatformListDrives;
  for I := 0 to High(Drives) do
    if Drives[I].Letter = UpCase(ALetter) then
    begin
      AInfo := Drives[I];
      Exit(True);
    end;
  Result := False;
end;

function PlatformDriveLetterOfPath(const APath: string): Char;
var
  Drives: TDriveInfoArray;
  I, BestLen: Integer;
  Root: string;
begin
  Result := #0;
  if (APath = '') or (APath[1] <> '/') then
    Exit;
  Drives := PlatformListDrives;
  BestLen := -1;
  for I := 0 to High(Drives) do
  begin
    Root := Drives[I].RootPath;
    if Root = '/' then
    begin
      if BestLen < 1 then
      begin
        BestLen := 1;
        Result := Drives[I].Letter;
      end;
    end
    else if (APath = Root) or APath.StartsWith(Root + '/') then
      if Length(Root) > BestLen then
      begin
        BestLen := Length(Root);
        Result := Drives[I].Letter;
      end;
  end;
end;

procedure PlatformFillDriveDetails(var AInfo: TDriveInfo);
var
  St: _statvfs;
  Path: UTF8String;
  Mount: TMount;
begin
  for Mount in ReadMounts do
    if Mount.MountPoint = AInfo.RootPath then
    begin
      AInfo.FsName := Mount.FsType;
      AInfo.LabelOrPath := Mount.MountPoint;
      Break;
    end;
  AInfo.TotalBytes := 0;
  AInfo.FreeBytes := 0;
  Path := UTF8String(AInfo.RootPath);
  if statvfs(MarshaledAString(Path), St) = 0 then
  begin
    AInfo.TotalBytes := Int64(St.f_blocks) * Int64(St.f_frsize);
    AInfo.FreeBytes := Int64(St.f_bavail) * Int64(St.f_frsize);
  end;
end;

procedure PlatformAbandonThread;
var
  Ret: Integer;
begin
  Ret := 0;
  pthread_exit(Ret);
end;

function PlatformCanDisconnectDrive(const AInfo: TDriveInfo): Boolean;
begin
  Result := (AInfo.RootPath <> '') and (AInfo.RootPath <> '/') and
    ((AInfo.KindLabel = 'Removable') or (AInfo.KindLabel = 'CD-ROM') or
     (AInfo.KindLabel = 'Network'));
end;

function PlatformDisconnectDrive(const AInfo: TDriveInfo; out AError: string): Boolean;
var
  Mounts: TArray<TMount>;
  Mount: TMount;
  Source, Output: string;
  ExitCode: Cardinal;
  Spawn: TSpawnResult;
begin
  AError := '';
  if not PlatformCanDisconnectDrive(AInfo) then
  begin
    AError := 'This drive cannot be disconnected';
    Result := False;
    Exit;
  end;
  Source := '';
  Mounts := ReadMounts;
  for Mount in Mounts do
    if Mount.MountPoint = AInfo.RootPath then
    begin
      Source := Mount.Source;
      Break;
    end;
  // A block device goes through udisks, which lets an ordinary user unmount
  // what the desktop mounted; anything else (or a missing udisksctl) falls
  // back to umount on the mount point.
  Spawn := srSpawnFailed;
  ExitCode := 1;
  if Source.StartsWith('/dev/') then
    Spawn := PlatformRunCaptured('udisksctl', ['unmount', '-b', Source], '', 30000, nil,
      Output, ExitCode);
  if (Spawn <> srOk) or (ExitCode <> 0) then
    Spawn := PlatformRunCaptured('umount', [AInfo.RootPath], '', 30000, nil, Output, ExitCode);
  Result := (Spawn = srOk) and (ExitCode = 0);
  if not Result then
  begin
    AError := Trim(Output);
    if AError = '' then
      AError := 'The volume could not be unmounted';
  end;
end;

end.
