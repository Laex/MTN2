unit uWinFileAttr;

{ Local-file attribute, owner and timestamp helpers for the Set attributes
  dialog (Ctrl+Shift+A).
  R/H/S/A via SetFileAttributes (other NTFS bits are left untouched).
  Owner via GetNamedSecurityInfo / SetNamedSecurityInfo.
  Created / Modified / Accessed via GetFileAttributesEx / SetFileTime, in
  local time converted with FileTimeToLocalFileTime and back -- the same
  conversion the panel's date columns use (uFileVfs), so a time typed here
  is the time the panel then shows. }

interface

uses
  System.SysUtils;

type
  TFileAttrChoice = (facKeep, facSet, facClear);

  /// <summary>Local times; 0 = unknown (or, in the dialog state, differs
  /// between the selected items).</summary>
  TFileAttrTimes = record
    Created: TDateTime;
    Modified: TDateTime;
    Accessed: TDateTime;
  end;

  TFileAttrSnapshot = record
    ReadOnly: Boolean;
    Hidden: Boolean;
    System: Boolean;
    Archive: Boolean;
    Owner: string;
    Times: TFileAttrTimes;
  end;

  TFileAttrPlan = record
    ReadOnly: TFileAttrChoice;
    Hidden: TFileAttrChoice;
    System: TFileAttrChoice;
    Archive: TFileAttrChoice;
    ChangeOwner: Boolean;
    Owner: string;
    Recurse: Boolean;
    // Only the flagged times are written; the rest keep their value.
    SetCreated: Boolean;
    SetModified: Boolean;
    SetAccessed: Boolean;
    Times: TFileAttrTimes;
  end;

  TFileAttrDialogState = record
    Summary: string;
    Owner: string;
    OwnerMixed: Boolean;
    ReadOnly: TFileAttrChoice;
    Hidden: TFileAttrChoice;
    System: TFileAttrChoice;
    Archive: TFileAttrChoice;
    Times: TFileAttrTimes;
  end;

function FileAttrChoiceToIndex(AChoice: TFileAttrChoice): Integer;
function FileAttrIndexToChoice(AIndex: Integer): TFileAttrChoice;
function FileAttrPlanIsNoOp(const APlan: TFileAttrPlan): Boolean;
/// <summary>Short date + hh:nn:ss of the current locale; '' for 0.</summary>
function FormatFileAttrTime(ATime: TDateTime): string;
/// <summary>Parses what FormatFileAttrTime produces (seconds and the time
/// part are optional). False for '' and for dates a file time cannot hold.</summary>
function TryParseFileAttrTime(const AText: string; out ATime: TDateTime): Boolean;
function TryReadFileAttrSnapshot(const APath: string;
  out ASnap: TFileAttrSnapshot; out AError: string): Boolean;
function BuildFileAttrDialogState(const APaths: TArray<string>): TFileAttrDialogState;
function ApplyFileAttrPlan(const APath: string; const APlan: TFileAttrPlan;
  out AError: string): Boolean;
procedure ApplyFileAttrRoots(const APaths: TArray<string>;
  const APlan: TFileAttrPlan; out AOk, AFail: Integer;
  out AFirstFailPath, AFirstError: string);

implementation

uses
  System.IOUtils,
  Winapi.Windows, Winapi.AccCtrl, Winapi.AclAPI, uVfsTypes;

function FileAttrChoiceToIndex(AChoice: TFileAttrChoice): Integer;
begin
  Result := Ord(AChoice);
end;

function FileAttrIndexToChoice(AIndex: Integer): TFileAttrChoice;
begin
  if AIndex <= Ord(facKeep) then
    Exit(facKeep);
  if AIndex >= Ord(facClear) then
    Exit(facClear);
  Result := TFileAttrChoice(AIndex);
end;

function FileAttrPlanIsNoOp(const APlan: TFileAttrPlan): Boolean;
begin
  Result := (APlan.ReadOnly = facKeep) and (APlan.Hidden = facKeep) and
    (APlan.System = facKeep) and (APlan.Archive = facKeep) and
    (not APlan.ChangeOwner) and
    not (APlan.SetCreated or APlan.SetModified or APlan.SetAccessed);
end;

function FormatFileAttrTime(ATime: TDateTime): string;
begin
  if ATime = 0 then
    Exit('');
  Result := DateToStr(ATime) + ' ' + FormatDateTime('hh:nn:ss', ATime);
end;

function TryParseFileAttrTime(const AText: string; out ATime: TDateTime): Boolean;
var
  S: string;
begin
  S := Trim(AText);
  // FILETIME starts at 1601-01-01; a day of margin for the UTC shift.
  Result := (S <> '') and TryStrToDateTime(S, ATime) and
    (ATime >= EncodeDate(1601, 1, 2)) and (ATime < EncodeDate(9999, 12, 31));
end;

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

// Two items "have the same time" when the dialog would show the same text.
function MergeTime(ACur, AValue: TDateTime): TDateTime;
begin
  if FormatFileAttrTime(ACur) = FormatFileAttrTime(AValue) then
    Result := ACur
  else
    Result := 0;
end;

function SysErrorText: string;
begin
  Result := SysErrorMessage(GetLastError);
  if Result = '' then
    Result := 'Access denied';
end;

function MergeChoice(ACur: TFileAttrChoice; AValue: Boolean): TFileAttrChoice;
begin
  Result := ACur;
  case ACur of
    facSet:
      if not AValue then
        Result := facKeep;
    facClear:
      if AValue then
        Result := facKeep;
  else
    Result := facKeep;
  end;
end;

function ChoiceFromFlag(AValue: Boolean): TFileAttrChoice;
begin
  if AValue then
    Result := facSet
  else
    Result := facClear;
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

function TryReadFileAttrSnapshot(const APath: string;
  out ASnap: TFileAttrSnapshot; out AError: string): Boolean;
var
  Attr: DWORD;
begin
  Result := False;
  ASnap := Default(TFileAttrSnapshot);
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
  if not ReadFileOwner(APath, ASnap.Owner) then
    ASnap.Owner := '(unknown)';
  ReadFileAttrTimes(APath, ASnap.Times);
  Result := True;
end;

function BuildFileAttrDialogState(const APaths: TArray<string>): TFileAttrDialogState;
var
  I: Integer;
  Snap: TFileAttrSnapshot;
  Err: string;
  First: Boolean;
begin
  Result := Default(TFileAttrDialogState);
  Result.ReadOnly := facKeep;
  Result.Hidden := facKeep;
  Result.System := facKeep;
  Result.Archive := facKeep;
  Result.Owner := '';
  Result.OwnerMixed := False;
  if Length(APaths) = 0 then
  begin
    Result.Summary := 'No items';
    Exit;
  end;
  if Length(APaths) = 1 then
    Result.Summary := ExtractFileName(ExcludeTrailingPathDelimiter(APaths[0]))
  else
    Result.Summary := Format('%d items', [Length(APaths)]);
  First := True;
  for I := 0 to High(APaths) do
  begin
    if not TryReadFileAttrSnapshot(APaths[I], Snap, Err) then
      Continue;
    if First then
    begin
      Result.ReadOnly := ChoiceFromFlag(Snap.ReadOnly);
      Result.Hidden := ChoiceFromFlag(Snap.Hidden);
      Result.System := ChoiceFromFlag(Snap.System);
      Result.Archive := ChoiceFromFlag(Snap.Archive);
      Result.Owner := Snap.Owner;
      Result.Times := Snap.Times;
      First := False;
    end
    else
    begin
      Result.ReadOnly := MergeChoice(Result.ReadOnly, Snap.ReadOnly);
      Result.Hidden := MergeChoice(Result.Hidden, Snap.Hidden);
      Result.System := MergeChoice(Result.System, Snap.System);
      Result.Archive := MergeChoice(Result.Archive, Snap.Archive);
      Result.Times.Created := MergeTime(Result.Times.Created, Snap.Times.Created);
      Result.Times.Modified := MergeTime(Result.Times.Modified, Snap.Times.Modified);
      Result.Times.Accessed := MergeTime(Result.Times.Accessed, Snap.Times.Accessed);
      if not SameText(Result.Owner, Snap.Owner) then
      begin
        Result.OwnerMixed := True;
        Result.Owner := '(mixed)';
      end;
    end;
  end;
  if First then
    Result.Summary := Result.Summary + ' (unreadable)';
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
  if Next = Attr then
    Exit(True);
  if not SetFileAttributes(PChar(WinApiPath(APath)), Next) then
  begin
    AError := SysErrorText;
    Exit;
  end;
  Result := True;
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

procedure CountOne(const APath: string; const APlan: TFileAttrPlan;
  var AOk, AFail: Integer; var AFirstFailPath, AFirstError: string);
var
  Err: string;
begin
  if ApplyFileAttrOne(APath, APlan, Err) then
    Inc(AOk)
  else
  begin
    Inc(AFail);
    if AFirstError = '' then
    begin
      AFirstFailPath := APath;
      AFirstError := Err;
    end;
  end;
end;

function ApplyFileAttrPlan(const APath: string; const APlan: TFileAttrPlan;
  out AError: string): Boolean;
var
  Ok, Fail: Integer;
  FirstPath: string;
begin
  Ok := 0;
  Fail := 0;
  FirstPath := '';
  AError := '';
  ApplyFileAttrRoots(TArray<string>.Create(APath), APlan, Ok, Fail, FirstPath,
    AError);
  Result := Fail = 0;
end;

procedure ApplyFileAttrRoots(const APaths: TArray<string>;
  const APlan: TFileAttrPlan; out AOk, AFail: Integer;
  out AFirstFailPath, AFirstError: string);
var
  Raw, Root, One: string;
  Files, Dirs: TArray<string>;
begin
  AOk := 0;
  AFail := 0;
  AFirstFailPath := '';
  AFirstError := '';
  for Raw in APaths do
  begin
    Root := ExcludeTrailingPathDelimiter(Raw);
    if Root = '' then
    begin
      Inc(AFail);
      if AFirstError = '' then
      begin
        AFirstFailPath := Raw;
        AFirstError := 'Empty path';
      end;
      Continue;
    end;
    CountOne(Root, APlan, AOk, AFail, AFirstFailPath, AFirstError);
    if (not APlan.Recurse) or (not TDirectory.Exists(WinApiPath(Root))) then
      Continue;
    try
      Files := TDirectory.GetFiles(Root, '*', TSearchOption.soAllDirectories);
      Dirs := TDirectory.GetDirectories(Root, '*', TSearchOption.soAllDirectories);
    except
      on E: Exception do
      begin
        Inc(AFail);
        if AFirstError = '' then
        begin
          AFirstFailPath := Root;
          AFirstError := E.Message;
        end;
        Continue;
      end;
    end;
    for One in Files do
      CountOne(One, APlan, AOk, AFail, AFirstFailPath, AFirstError);
    for One in Dirs do
      CountOne(One, APlan, AOk, AFail, AFirstFailPath, AFirstError);
  end;
end;

end.
