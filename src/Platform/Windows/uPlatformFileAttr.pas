unit uPlatformFileAttr;

{ Reading and writing the attributes, owner and times of one local file
  (Windows build): the R/H/S/A bits via SetFileAttributes, the owner via the
  security API, the times via SetFileTime. Times are local, converted the same
  way the panel's date columns do, so a time typed in the dialog is the time
  the panel then shows. The POSIX build lives in Platform\Posix; each project
  puts exactly one of the two directories on its unit search path. }

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

/// <summary>For a drive root such as 'F:\': its volume GUID path and its device
/// name; False for anything else.</summary>
function TryGetDriveRootInfo(const APath: string; out AVolume, ADevice: string): Boolean;

/// <summary>Accounts that can own a file: local users and the well-known
/// groups and service accounts, as DOMAIN/name. Empty where the owner is not
/// chosen from a list.</summary>
function ListFileOwnerCandidates: TArray<string>;

implementation

uses
  System.SysUtils, Winapi.Windows, Winapi.AccCtrl, Winapi.AclAPI, uVfsTypes;

type
  TUserInfo0 = record
    Name: PWideChar;
  end;
  PUserInfo0 = ^TUserInfo0;

function NetUserEnum(AServer: PWideChar; ALevel, AFilter: DWORD;
  out ABuf: Pointer; AMaxLen: DWORD; out ARead, ATotal: DWORD;
  AResume: PDWORD): DWORD; stdcall; external 'netapi32.dll';
function NetApiBufferFree(ABuf: Pointer): DWORD; stdcall; external 'netapi32.dll';

const
  FSCTL_SET_COMPRESSION = $0009C040;
  FSCTL_SET_SPARSE = $000900C4;
  COMPRESSION_FORMAT_NONE = 0;
  COMPRESSION_FORMAT_DEFAULT = 1;

function EncryptFileW(AFileName: PWideChar): BOOL; stdcall;
  external 'advapi32.dll' name 'EncryptFileW';
function DecryptFileW(AFileName: PWideChar; AReserved: DWORD): BOOL; stdcall;
  external 'advapi32.dll' name 'DecryptFileW';

function FileTimeToLocalDateTime(const AFT: TFileTime): TDateTime;
var
  LFT: TFileTime;
  ST: TSystemTime;
begin
  Result := 0;
  if (AFT.dwLowDateTime = 0) and (AFT.dwHighDateTime = 0) then
    Exit;
  if FileTimeToLocalFileTime(AFT, LFT) and FileTimeToSystemTime(LFT, ST) then
    Result := SystemTimeToDateTime(ST);
end;

function LocalDateTimeToFileTime(ATime: TDateTime; out AFT: TFileTime): Boolean;
var
  ST: TSystemTime;
  LFT: TFileTime;
begin
  DateTimeToSystemTime(ATime, ST);
  Result := SystemTimeToFileTime(ST, LFT) and LocalFileTimeToFileTime(LFT, AFT);
end;

function ReadFileAttrTimes(const APath: string; out ATimes: TFileAttrTimes): Boolean;
var
  Data: TWin32FileAttributeData;
begin
  ATimes := Default(TFileAttrTimes);
  Result := GetFileAttributesEx(PChar(WinApiPath(APath)), GetFileExInfoStandard, @Data);
  if not Result then
    Exit;
  ATimes.Created := FileTimeToLocalDateTime(Data.ftCreationTime);
  ATimes.Modified := FileTimeToLocalDateTime(Data.ftLastWriteTime);
  ATimes.Accessed := FileTimeToLocalDateTime(Data.ftLastAccessTime);
end;

function SysErrorText: string;
begin
  Result := SysErrorMessage(GetLastError);
  if Result = '' then
    Result := 'Access denied';
end;

function EnablePrivilege(const AName: string): Boolean;
var
  Token: THandle;
  TP: TTokenPrivileges;
  Dummy: DWORD;
begin
  Result := False;
  if not OpenProcessToken(GetCurrentProcess, TOKEN_ADJUST_PRIVILEGES or TOKEN_QUERY,
    Token) then
    Exit;
  try
    if not LookupPrivilegeValue(nil, PChar(AName), TP.Privileges[0].Luid) then
      Exit;
    TP.PrivilegeCount := 1;
    TP.Privileges[0].Attributes := SE_PRIVILEGE_ENABLED;
    Dummy := 0;
    AdjustTokenPrivileges(Token, False, TP, 0, PTokenPrivileges(nil)^, Dummy);
    Result := GetLastError = ERROR_SUCCESS;
  finally
    CloseHandle(Token);
  end;
end;

function ReadFileOwner(const APath: string; out AOwner: string): Boolean;
var
  SD: PSECURITY_DESCRIPTOR;
  OwnerSid: PSID;
  NameBuf, DomBuf: array[0..255] of Char;
  NameLen, DomLen: DWORD;
  Use: SID_NAME_USE;
begin
  Result := False;
  AOwner := '';
  OwnerSid := nil;
  SD := nil;
  if GetNamedSecurityInfo(PChar(APath), SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION,
    @OwnerSid, nil, nil, nil, SD) <> ERROR_SUCCESS then
    Exit;
  try
    NameLen := Length(NameBuf);
    DomLen := Length(DomBuf);
    if not LookupAccountSid(nil, OwnerSid, NameBuf, NameLen, DomBuf, DomLen, Use) then
      Exit;
    if DomBuf[0] <> #0 then
      AOwner := string(DomBuf) + '\' + string(NameBuf)
    else
      AOwner := string(NameBuf);
    Result := AOwner <> '';
  finally
    if Assigned(SD) then
      LocalFree(HLOCAL(SD));
  end;
end;

function SidAccountName(const ASidText: string): string;
var
  Sid: PSID;
  NameBuf, DomBuf: array[0..255] of Char;
  NameLen, DomLen: DWORD;
  Use: SID_NAME_USE;
begin
  Result := '';
  Sid := nil;
  if not ConvertStringSidToSid(PChar(ASidText), Sid) then
    Exit;
  try
    NameLen := Length(NameBuf);
    DomLen := Length(DomBuf);
    if LookupAccountSid(nil, Sid, NameBuf, NameLen, DomBuf, DomLen, Use) then
      if DomBuf[0] <> #0 then
        Result := string(DomBuf) + '' + string(NameBuf)
      else
        Result := string(NameBuf);
  finally
    LocalFree(HLOCAL(Sid));
  end;
end;

function ListFileOwnerCandidates: TArray<string>;
const
  cWellKnown: array[0..3] of string = ('S-1-5-32-544', 'S-1-5-18',
    'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464', 'S-1-5-32-545');
var
  List: TArray<string>;
  Buf: Pointer;
  Read, Total, I: DWORD;
  Computer: array[0..MAX_COMPUTERNAME_LENGTH] of Char;
  CompLen: DWORD;
  Name: string;

  procedure Add(const AName: string);
  var
    S: string;
  begin
    if AName = '' then
      Exit;
    for S in List do
      if SameText(S, AName) then
        Exit;
    List := List + [AName];
  end;

begin
  List := nil;
  for Name in cWellKnown do
    Add(SidAccountName(Name));
  CompLen := Length(Computer);
  if not GetComputerName(Computer, CompLen) then
    Computer[0] := #0;
  Buf := nil;
  if NetUserEnum(nil, 0, 0, Buf, DWORD(-1), Read, Total, nil) = 0 then
  try
    for I := 0 to Read - 1 do
      Add(string(Computer) + '' + string(PUserInfo0(PByte(Buf) + I * SizeOf(TUserInfo0)).Name));
  finally
    NetApiBufferFree(Buf);
  end;
  Result := List;
end;

function PlatformFileModeSupported: Boolean;
begin
  Result := False;
end;

function TryReadFileAttrSnapshot(const APath: string;
  out ASnap: TFileAttrSnapshot; out AError: string): Boolean;
var
  Attr: DWORD;
begin
  Result := False;
  ASnap := Default(TFileAttrSnapshot);
  ASnap.Mode := -1;
  AError := '';
  Attr := GetFileAttributes(PChar(WinApiPath(APath)));
  if Attr = INVALID_FILE_ATTRIBUTES then
  begin
    AError := SysErrorText;
    Exit;
  end;
  ASnap.ReadOnly := (Attr and FILE_ATTRIBUTE_READONLY) <> 0;
  ASnap.Hidden := (Attr and FILE_ATTRIBUTE_HIDDEN) <> 0;
  ASnap.System := (Attr and FILE_ATTRIBUTE_SYSTEM) <> 0;
  ASnap.Archive := (Attr and FILE_ATTRIBUTE_ARCHIVE) <> 0;
  ASnap.Compressed := (Attr and FILE_ATTRIBUTE_COMPRESSED) <> 0;
  ASnap.Encrypted := (Attr and FILE_ATTRIBUTE_ENCRYPTED) <> 0;
  ASnap.NotIndexed := (Attr and FILE_ATTRIBUTE_NOT_CONTENT_INDEXED) <> 0;
  ASnap.Sparse := (Attr and FILE_ATTRIBUTE_SPARSE_FILE) <> 0;
  ASnap.Temporary := (Attr and FILE_ATTRIBUTE_TEMPORARY) <> 0;
  ASnap.Offline := (Attr and FILE_ATTRIBUTE_OFFLINE) <> 0;
  if not ReadFileOwner(APath, ASnap.Owner) then
    ASnap.Owner := '(unknown)';
  ReadFileAttrTimes(APath, ASnap.Times);
  Result := True;
end;

function ApplyAttrBits(Attr: DWORD; AChoice: TFileAttrChoice; ABit: DWORD): DWORD;
begin
  Result := Attr;
  case AChoice of
    facSet: Result := Result or ABit;
    facClear: Result := Result and not ABit;
  else
    ;
  end;
end;

function ApplyFileAttributesOnly(const APath: string; const APlan: TFileAttrPlan;
  out AError: string): Boolean;
var
  Attr, Next: DWORD;
begin
  Result := False;
  AError := '';
  Attr := GetFileAttributes(PChar(WinApiPath(APath)));
  if Attr = INVALID_FILE_ATTRIBUTES then
  begin
    AError := SysErrorText;
    Exit;
  end;
  Next := Attr;
  Next := ApplyAttrBits(Next, APlan.ReadOnly, FILE_ATTRIBUTE_READONLY);
  Next := ApplyAttrBits(Next, APlan.Hidden, FILE_ATTRIBUTE_HIDDEN);
  Next := ApplyAttrBits(Next, APlan.System, FILE_ATTRIBUTE_SYSTEM);
  Next := ApplyAttrBits(Next, APlan.Archive, FILE_ATTRIBUTE_ARCHIVE);
  Next := ApplyAttrBits(Next, APlan.NotIndexed, FILE_ATTRIBUTE_NOT_CONTENT_INDEXED);
  Next := ApplyAttrBits(Next, APlan.Temporary, FILE_ATTRIBUTE_TEMPORARY);
  Next := ApplyAttrBits(Next, APlan.Offline, FILE_ATTRIBUTE_OFFLINE);
  if Next = Attr then
    Exit(True);
  if not SetFileAttributes(PChar(WinApiPath(APath)), Next) then
  begin
    AError := SysErrorText;
    Exit;
  end;
  Result := True;
end;

// Compression and the sparse flag are file system settings changed with a
// control code on an open handle; encryption has its own calls. Each is done
// only when the file is not in the wanted state already.
function ChoiceWantsChange(AChoice: TFileAttrChoice; ACurrentlySet: Boolean): Boolean;
begin
  Result := ((AChoice = facSet) and not ACurrentlySet) or
    ((AChoice = facClear) and ACurrentlySet);
end;

function ControlCodeOn(const APath: string; ACode: DWORD; var AValue; ASize: DWORD;
  out AError: string): Boolean;
var
  H: THandle;
  Returned: DWORD;
begin
  Result := False;
  AError := '';
  H := CreateFile(PChar(WinApiPath(APath)), GENERIC_READ or GENERIC_WRITE,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS, 0);
  if H = INVALID_HANDLE_VALUE then
  begin
    AError := SysErrorText;
    Exit;
  end;
  try
    Returned := 0;
    if not DeviceIoControl(H, ACode, @AValue, ASize, nil, 0, Returned, nil) then
    begin
      AError := SysErrorText;
      Exit;
    end;
  finally
    CloseHandle(H);
  end;
  Result := True;
end;

function ApplyFileSystemFlags(const APath: string; const APlan: TFileAttrPlan;
  out AError: string): Boolean;
var
  Attr: DWORD;
  Format: Word;
  Sparse: Byte;
begin
  Result := False;
  AError := '';
  if (APlan.Compressed = facKeep) and (APlan.Encrypted = facKeep) and
     (APlan.Sparse = facKeep) then
    Exit(True);
  Attr := GetFileAttributes(PChar(WinApiPath(APath)));
  if Attr = INVALID_FILE_ATTRIBUTES then
  begin
    AError := SysErrorText;
    Exit;
  end;
  // Encryption and compression exclude each other: leaving one before taking
  // the other is what the user asked for when both are in the plan.
  if ChoiceWantsChange(APlan.Compressed, (Attr and FILE_ATTRIBUTE_COMPRESSED) <> 0) and
     (APlan.Compressed = facClear) then
  begin
    Format := COMPRESSION_FORMAT_NONE;
    if not ControlCodeOn(APath, FSCTL_SET_COMPRESSION, Format, SizeOf(Format), AError) then
      Exit;
  end;
  if ChoiceWantsChange(APlan.Encrypted, (Attr and FILE_ATTRIBUTE_ENCRYPTED) <> 0) then
  begin
    if APlan.Encrypted = facSet then
    begin
      if not EncryptFileW(PWideChar(WinApiPath(APath))) then
      begin
        AError := SysErrorText;
        Exit;
      end;
    end
    else if not DecryptFileW(PWideChar(WinApiPath(APath)), 0) then
    begin
      AError := SysErrorText;
      Exit;
    end;
  end;
  if ChoiceWantsChange(APlan.Compressed, (Attr and FILE_ATTRIBUTE_COMPRESSED) <> 0) and
     (APlan.Compressed = facSet) then
  begin
    Format := COMPRESSION_FORMAT_DEFAULT;
    if not ControlCodeOn(APath, FSCTL_SET_COMPRESSION, Format, SizeOf(Format), AError) then
      Exit;
  end;
  if ChoiceWantsChange(APlan.Sparse, (Attr and FILE_ATTRIBUTE_SPARSE_FILE) <> 0) then
  begin
    if APlan.Sparse = facSet then
      Sparse := 1
    else
      Sparse := 0;
    if not ControlCodeOn(APath, FSCTL_SET_SPARSE, Sparse, SizeOf(Sparse), AError) then
      Exit;
  end;
  Result := True;
end;

function TryGetDriveRootInfo(const APath: string; out AVolume, ADevice: string): Boolean;
var
  Root: string;
  Buf: array[0..MAX_PATH + 1] of Char;
begin
  AVolume := '';
  ADevice := '';
  Result := False;
  if (Length(APath) < 2) or (Length(APath) > 3) or (APath[2] <> ':') then
    Exit;
  Root := UpCase(APath[1]) + ':\';
  if GetVolumeNameForVolumeMountPoint(PChar(Root), Buf, Length(Buf)) then
    AVolume := string(Buf);
  if QueryDosDevice(PChar(Root[1] + ':'), Buf, Length(Buf)) <> 0 then
    ADevice := string(Buf);
  Result := (AVolume <> '') or (ADevice <> '');
end;

function ApplyFileTimes(const APath: string; const APlan: TFileAttrPlan;
  out AError: string): Boolean;
var
  H: THandle;
  C, A, M: TFileTime;
  PC, PA, PM: PFileTime;

  function Prepare(AUse: Boolean; ATime: TDateTime; var AFT: TFileTime;
    out AP: PFileTime): Boolean;
  begin
    AP := nil;
    Result := True;
    if not AUse then
      Exit;
    Result := LocalDateTimeToFileTime(ATime, AFT);
    if Result then
      AP := @AFT;
  end;

begin
  Result := False;
  AError := '';
  if not (APlan.SetCreated or APlan.SetModified or APlan.SetAccessed) then
    Exit(True);
  if not (Prepare(APlan.SetCreated, APlan.Times.Created, C, PC) and
          Prepare(APlan.SetModified, APlan.Times.Modified, M, PM) and
          Prepare(APlan.SetAccessed, APlan.Times.Accessed, A, PA)) then
  begin
    AError := 'Invalid date';
    Exit;
  end;
  // FILE_WRITE_ATTRIBUTES is allowed on read-only files; BACKUP_SEMANTICS
  // is what lets CreateFile open a directory.
  H := CreateFile(PChar(WinApiPath(APath)), FILE_WRITE_ATTRIBUTES,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS, 0);
  if H = INVALID_HANDLE_VALUE then
  begin
    AError := SysErrorText;
    Exit;
  end;
  try
    if not SetFileTime(H, PC, PA, PM) then
    begin
      AError := SysErrorText;
      Exit;
    end;
  finally
    CloseHandle(H);
  end;
  Result := True;
end;

function ApplyFileOwner(const APath, AOwner: string; out AError: string): Boolean;
var
  SidLen, DomLen: DWORD;
  Use: SID_NAME_USE;
  Sid: PSID;
  Domain: string;
  Code: DWORD;
begin
  Result := False;
  AError := '';
  if Trim(AOwner) = '' then
  begin
    AError := 'Owner name is empty';
    Exit;
  end;
  SidLen := 0;
  DomLen := 0;
  LookupAccountName(nil, PChar(AOwner), nil, SidLen, nil, DomLen, Use);
  if (SidLen = 0) then
  begin
    AError := 'Unknown account: ' + AOwner;
    Exit;
  end;
  GetMem(Sid, SidLen);
  try
    SetLength(Domain, DomLen);
    if DomLen > 0 then
    begin
      if not LookupAccountName(nil, PChar(AOwner), Sid, SidLen, PChar(Domain),
        DomLen, Use) then
      begin
        AError := SysErrorText;
        Exit;
      end;
    end
    else if not LookupAccountName(nil, PChar(AOwner), Sid, SidLen, nil, DomLen, Use) then
    begin
      AError := SysErrorText;
      Exit;
    end;
    Code := SetNamedSecurityInfo(PChar(APath), SE_FILE_OBJECT,
      OWNER_SECURITY_INFORMATION, Sid, nil, nil, nil);
    if Code = ERROR_ACCESS_DENIED then
    begin
      EnablePrivilege('SeTakeOwnershipPrivilege');
      EnablePrivilege('SeRestorePrivilege');
      Code := SetNamedSecurityInfo(PChar(APath), SE_FILE_OBJECT,
        OWNER_SECURITY_INFORMATION, Sid, nil, nil, nil);
    end;
    if Code <> ERROR_SUCCESS then
    begin
      AError := SysErrorMessage(Code);
      if AError = '' then
        AError := Format('Set owner failed (%d)', [Code]);
      Exit;
    end;
    Result := True;
  finally
    FreeMem(Sid);
  end;
end;

function ApplyFileAttrOne(const APath: string; const APlan: TFileAttrPlan;
  out AError: string): Boolean;
var
  Err, CurOwner: string;
begin
  Result := False;
  AError := '';
  if not ApplyFileAttributesOnly(APath, APlan, Err) then
  begin
    AError := Err;
    Exit;
  end;
  if not ApplyFileSystemFlags(APath, APlan, Err) then
  begin
    AError := Err;
    Exit;
  end;
  if not ApplyFileTimes(APath, APlan, Err) then
  begin
    AError := Err;
    Exit;
  end;
  if APlan.ChangeOwner then
  begin
    CurOwner := '';
    if ReadFileOwner(APath, CurOwner) and SameText(CurOwner, Trim(APlan.Owner)) then
    begin
      Result := True;
      Exit;
    end;
    if not ApplyFileOwner(APath, APlan.Owner, Err) then
    begin
      AError := Err;
      Exit;
    end;
  end;
  Result := True;
end;

end.
