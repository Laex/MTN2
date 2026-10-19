unit uPlatformFileAttr;

{ Reading and writing the attributes, owner and times of one local file (POSIX
  build). The read-only flag is the absence of write permission, hidden means a
  name that starts with a dot, the system and archive flags do not exist; the
  owner is the user name, the times are the change, modification and access
  times (the creation time is the inode change time). The Windows build lives
  in Platform\Windows; each project puts exactly one of the two directories on
  its unit search path. }

interface

uses
  uFileAttrTypes;

/// <summary>True where files have permission bits and a group (the Set
/// attributes command then shows the permissions dialog).</summary>
function PlatformFileModeSupported: Boolean;

/// <summary>Reads the attributes, owner and times of APath.</summary>
function TryReadFileAttrSnapshot(const APath: string;
  out ASnap: TFileAttrSnapshot; out AError: string): Boolean;

/// <summary>Applies APlan to the single item APath (no recursion).</summary>
function ApplyFileAttrOne(const APath: string; const APlan: TFileAttrPlan;
  out AError: string): Boolean;

/// <summary>Drive roots (volume GUID and device) are a Windows notion: always False.</summary>
function TryGetDriveRootInfo(const APath: string; out AVolume, ADevice: string): Boolean;

/// <summary>Accounts that can own a file: local users and the well-known
/// groups and service accounts, as DOMAIN/name. Empty where the owner is not
/// chosen from a list.</summary>
function ListFileOwnerCandidates: TArray<string>;

implementation

uses
  System.SysUtils, System.DateUtils, Posix.Base, Posix.SysStat;

type
  TPasswd = record
    pw_name: MarshaledAString;
    pw_passwd: MarshaledAString;
    pw_uid: Cardinal;
    pw_gid: Cardinal;
  end;
  PPasswd = ^TPasswd;

  TGroupEntry = record
    gr_name: MarshaledAString;
    gr_passwd: MarshaledAString;
    gr_gid: Cardinal;
  end;
  PGroupEntry = ^TGroupEntry;

  TTimeVal = record
    Sec: Int64;
    USec: Int64;
  end;

function c_getpwuid(AUid: Cardinal): PPasswd; cdecl; external libc name 'getpwuid';
function c_getpwnam(AName: MarshaledAString): PPasswd; cdecl; external libc name 'getpwnam';
function c_getgrgid(AGid: Cardinal): PGroupEntry; cdecl; external libc name 'getgrgid';
function c_getgrnam(AName: MarshaledAString): PGroupEntry; cdecl; external libc name 'getgrnam';
function c_chown(APath: MarshaledAString; AUid, AGid: Cardinal): Integer; cdecl;
  external libc name 'chown';
function c_utimes(APath: MarshaledAString; ATimes: Pointer): Integer; cdecl;
  external libc name 'utimes';

function SysErrorText: string;
begin
  Result := SysErrorMessage(GetLastError);
  if Result = '' then
    Result := 'Access denied';
end;

function UnixToLocal(ASeconds: Int64): TDateTime;
begin
  Result := UnixToDateTime(ASeconds, False);
end;

function LocalToUnix(ATime: TDateTime): Int64;
begin
  Result := DateTimeToUnix(ATime, False);
end;

function UserNameOf(AUid: Cardinal): string;
var
  P: PPasswd;
begin
  P := c_getpwuid(AUid);
  if (P <> nil) and (P^.pw_name <> nil) then
    Result := UTF8ToString(P^.pw_name)
  else
    Result := IntToStr(AUid);
end;

function GroupNameOf(AGid: Cardinal): string;
var
  G: PGroupEntry;
begin
  G := c_getgrgid(AGid);
  if (G <> nil) and (G^.gr_name <> nil) then
    Result := UTF8ToString(G^.gr_name)
  else
    Result := IntToStr(AGid);
end;

function PlatformFileModeSupported: Boolean;
begin
  Result := True;
end;

function ListFileOwnerCandidates: TArray<string>;
begin
  Result := nil;
end;

function TryGetDriveRootInfo(const APath: string; out AVolume, ADevice: string): Boolean;
begin
  AVolume := '';
  ADevice := '';
  Result := False;
end;

function TryReadFileAttrSnapshot(const APath: string;
  out ASnap: TFileAttrSnapshot; out AError: string): Boolean;
var
  St: _stat;
  P: UTF8String;
begin
  Result := False;
  ASnap := Default(TFileAttrSnapshot);
  AError := '';
  P := UTF8String(ExcludeTrailingPathDelimiter(APath));
  if stat(MarshaledAString(P), St) <> 0 then
  begin
    AError := SysErrorText;
    Exit;
  end;
  ASnap.ReadOnly := (St.st_mode and S_IWUSR) = 0;
  ASnap.Hidden := Copy(ExtractFileName(ExcludeTrailingPathDelimiter(APath)), 1, 1) = '.';
  ASnap.Owner := UserNameOf(St.st_uid);
  ASnap.Group := GroupNameOf(St.st_gid);
  ASnap.Mode := St.st_mode and $FFF;
  ASnap.Times.Created := UnixToLocal(St.st_ctime);
  ASnap.Times.Modified := UnixToLocal(St.st_mtime);
  ASnap.Times.Accessed := UnixToLocal(St.st_atime);
  Result := True;
end;

function ApplyMode(const APath: string; const APlan: TFileAttrPlan;
  out AError: string): Boolean;
var
  St: _stat;
  P: UTF8String;
  Mode: Cardinal;
const
  cWriteBits = S_IWUSR or S_IWGRP or S_IWOTH;
begin
  Result := False;
  AError := '';
  if (APlan.ReadOnly = facKeep) and not APlan.ChangeMode then
    Exit(True);
  P := UTF8String(ExcludeTrailingPathDelimiter(APath));
  if stat(MarshaledAString(P), St) <> 0 then
  begin
    AError := SysErrorText;
    Exit;
  end;
  Mode := St.st_mode and $FFF;
  if APlan.ChangeMode then
    Mode := Cardinal(APlan.Mode) and $FFF
  else if APlan.ReadOnly = facSet then
    Mode := Mode and not cWriteBits
  else
    Mode := Mode or S_IWUSR;
  if Mode = (St.st_mode and $FFF) then
    Exit(True);
  if chmod(MarshaledAString(P), Mode) <> 0 then
  begin
    AError := SysErrorText;
    Exit;
  end;
  Result := True;
end;

function ApplyTimes(const APath: string; const APlan: TFileAttrPlan;
  out AError: string): Boolean;
var
  St: _stat;
  P: UTF8String;
  T: array[0..1] of TTimeVal;
begin
  Result := False;
  AError := '';
  // The creation time cannot be set; only access and modification are.
  if not (APlan.SetModified or APlan.SetAccessed) then
    Exit(True);
  P := UTF8String(ExcludeTrailingPathDelimiter(APath));
  if stat(MarshaledAString(P), St) <> 0 then
  begin
    AError := SysErrorText;
    Exit;
  end;
  T[0].Sec := St.st_atime;
  T[0].USec := 0;
  T[1].Sec := St.st_mtime;
  T[1].USec := 0;
  if APlan.SetAccessed then
    T[0].Sec := LocalToUnix(APlan.Times.Accessed);
  if APlan.SetModified then
    T[1].Sec := LocalToUnix(APlan.Times.Modified);
  if c_utimes(MarshaledAString(P), @T[0]) <> 0 then
  begin
    AError := SysErrorText;
    Exit;
  end;
  Result := True;
end;

function ApplyOwner(const APath: string; const APlan: TFileAttrPlan;
  out AError: string): Boolean;
var
  Name, GroupName, P: UTF8String;
  Pw: PPasswd;
  Gr: PGroupEntry;
  Uid, Gid: Cardinal;
begin
  Result := False;
  AError := '';
  Uid := Cardinal(-1);
  Gid := Cardinal(-1);
  if APlan.ChangeOwner then
  begin
    if Trim(APlan.Owner) = '' then
    begin
      AError := 'Owner name is empty';
      Exit;
    end;
    Name := UTF8String(Trim(APlan.Owner));
    Pw := c_getpwnam(MarshaledAString(Name));
    if Pw = nil then
    begin
      AError := 'Unknown account: ' + APlan.Owner;
      Exit;
    end;
    Uid := Pw^.pw_uid;
  end;
  if APlan.ChangeGroup and (Trim(APlan.Group) <> '') then
  begin
    GroupName := UTF8String(Trim(APlan.Group));
    Gr := c_getgrnam(MarshaledAString(GroupName));
    if Gr = nil then
    begin
      AError := 'Unknown group: ' + APlan.Group;
      Exit;
    end;
    Gid := Gr^.gr_gid;
  end;
  P := UTF8String(ExcludeTrailingPathDelimiter(APath));
  if c_chown(MarshaledAString(P), Uid, Gid) <> 0 then
  begin
    AError := SysErrorText;
    Exit;
  end;
  Result := True;
end;

function ApplyFileAttrOne(const APath: string; const APlan: TFileAttrPlan;
  out AError: string): Boolean;
var
  Err: string;
  Snap: TFileAttrSnapshot;
  Plan: TFileAttrPlan;
begin
  Result := False;
  AError := '';
  if not ApplyMode(APath, APlan, Err) then
  begin
    AError := Err;
    Exit;
  end;
  if not ApplyTimes(APath, APlan, Err) then
  begin
    AError := Err;
    Exit;
  end;
  if APlan.ChangeOwner or (APlan.ChangeGroup and (Trim(APlan.Group) <> '')) then
  begin
    // chown is skipped for what would not change, so a plain user can set the
    // group of an item it owns without tripping over an unchanged owner.
    Plan := APlan;
    if TryReadFileAttrSnapshot(APath, Snap, Err) then
    begin
      if Plan.ChangeOwner and SameText(Snap.Owner, Trim(Plan.Owner)) then
        Plan.ChangeOwner := False;
      if Plan.ChangeGroup and SameText(Snap.Group, Trim(Plan.Group)) then
        Plan.ChangeGroup := False;
    end;
    if (Plan.ChangeOwner or (Plan.ChangeGroup and (Trim(Plan.Group) <> ''))) and
       not ApplyOwner(APath, Plan, Err) then
    begin
      AError := Err;
      Exit;
    end;
  end;
  Result := True;
end;

end.
