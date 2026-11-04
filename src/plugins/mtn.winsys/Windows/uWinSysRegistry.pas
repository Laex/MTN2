unit uWinSysRegistry;

{ The registry as folders (keys) and files (values) for reg://. A path is the
  list of segments: the hive name, then key names, and last a key or a value
  name. Every call returns a Win32 error code (0 = done). }

interface

uses
  System.SysUtils;

type
  TRegRow = record
    Name: string;
    IsKey: Boolean;
    Size: Int64;
    Modified: Int64;
  end;
  TRegRows = TArray<TRegRow>;

  TRegPathKind = (rpHiveList, rpKey, rpValue);

/// <summary>The keys and values inside the key ASegments names (the five hives
/// for no segments). Names are returned as path segments.</summary>
function RegListPath(const ASegments: TArray<string>; out ARows: TRegRows): Cardinal;

/// <summary>What the path is. A key wins over a value of the same name.</summary>
function RegPathInfo(const ASegments: TArray<string>; out AKind: TRegPathKind): Cardinal;

function RegReadValue(const ASegments: TArray<string>; out AType: Cardinal;
  out AData: TBytes): Cardinal;

/// <summary>Sets the value, creating it when it is missing. The key must exist.</summary>
function RegWriteValue(const ASegments: TArray<string>; AType: Cardinal;
  const AData: TBytes): Cardinal;

/// <summary>Deletes a key with everything inside it, or a value. A hive cannot be deleted.</summary>
function RegDeletePath(const ASegments: TArray<string>): Cardinal;

function RegCreateKeyPath(const ASegments: TArray<string>): Cardinal;

implementation

uses
  Winapi.Windows, uWinSysFormat;

function RegDeleteTreeW(AKey: HKEY; ASubKey: PWideChar): Longint; stdcall;
  external 'advapi32.dll' name 'RegDeleteTreeW';

const
  cHiveNames: array[0..4] of string = (
    'HKEY_CLASSES_ROOT', 'HKEY_CURRENT_USER', 'HKEY_LOCAL_MACHINE',
    'HKEY_USERS', 'HKEY_CURRENT_CONFIG');

function HiveHandle(const AName: string; out AHive: HKEY): Boolean;
begin
  Result := True;
  if SameText(AName, cHiveNames[0]) then
    AHive := HKEY_CLASSES_ROOT
  else if SameText(AName, cHiveNames[1]) then
    AHive := HKEY_CURRENT_USER
  else if SameText(AName, cHiveNames[2]) then
    AHive := HKEY_LOCAL_MACHINE
  else if SameText(AName, cHiveNames[3]) then
    AHive := HKEY_USERS
  else if SameText(AName, cHiveNames[4]) then
    AHive := HKEY_CURRENT_CONFIG
  else
  begin
    AHive := 0;
    Result := False;
  end;
end;

// Segments 1 .. ACount - 1 joined with backslashes.
function SubKeyPath(const ASegments: TArray<string>; ACount: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to ACount - 1 do
  begin
    if Result <> '' then
      Result := Result + '\';
    Result := Result + ASegments[I];
  end;
end;

// Opens the key of the first ACount segments. The handle is always closed with RegCloseKey.
function OpenKeyOf(const ASegments: TArray<string>; ACount: Integer; AAccess: REGSAM;
  out AKey: HKEY): Cardinal;
var
  Hive: HKEY;
begin
  AKey := 0;
  if (ACount < 1) or (ACount > Length(ASegments)) or not HiveHandle(ASegments[0], Hive) then
    Exit(ERROR_PATH_NOT_FOUND);
  Result := Cardinal(RegOpenKeyEx(Hive, PChar(SubKeyPath(ASegments, ACount)), 0, AAccess, AKey));
end;

function ValueNameOf(const ASegment: string): string;
begin
  if ASegment = cRegDefaultName then
    Result := ''
  else
    Result := ASegment;
end;

function TicksOf(const AFileTime: TFileTime): Int64;
var
  Local: TFileTime;
  Ticks: UInt64;
begin
  if (AFileTime.dwLowDateTime = 0) and (AFileTime.dwHighDateTime = 0) then
    Exit(0);
  if not FileTimeToLocalFileTime(AFileTime, Local) then
    Local := AFileTime;
  Ticks := (UInt64(Local.dwHighDateTime) shl 32) or Local.dwLowDateTime;
  Result := FileTimeToUnixSeconds(Ticks);
end;

function RegListPath(const ASegments: TArray<string>; out ARows: TRegRows): Cardinal;
var
  K: HKEY;
  SubKeys, MaxSubLen, Values, MaxValueNameLen: DWORD;
  KeyFt, ItemFt: TFileTime;
  Buf: array of WideChar;
  I, Count: Integer;
  Len, ValType, DataSize: DWORD;
  Err: Longint;
  Row: TRegRow;
  List: TRegRows;
begin
  SetLength(ARows, 0);
  if Length(ASegments) = 0 then
  begin
    SetLength(ARows, Length(cHiveNames));
    for I := 0 to High(cHiveNames) do
    begin
      ARows[I] := Default(TRegRow);
      ARows[I].Name := cHiveNames[I];
      ARows[I].IsKey := True;
    end;
    Exit(0);
  end;
  Result := OpenKeyOf(ASegments, Length(ASegments), KEY_READ, K);
  if Result <> 0 then
    Exit;
  try
    Err := RegQueryInfoKey(K, nil, nil, nil, @SubKeys, @MaxSubLen, nil, @Values,
      @MaxValueNameLen, nil, nil, @KeyFt);
    if Err <> 0 then
      Exit(Cardinal(Err));
    Count := 0;
    SetLength(List, Integer(SubKeys) + Integer(Values));
    SetLength(Buf, MaxSubLen + 2);
    for I := 0 to Integer(SubKeys) - 1 do
    begin
      Len := Length(Buf);
      Err := RegEnumKeyEx(K, I, PWideChar(Buf), Len, nil, nil, nil, @ItemFt);
      if Err = ERROR_NO_MORE_ITEMS then
        Break;
      if Err <> 0 then
        Continue;
      Row := Default(TRegRow);
      SetString(Row.Name, PWideChar(Buf), Len);
      Row.Name := EncodeSegment(Row.Name);
      Row.IsKey := True;
      Row.Modified := TicksOf(ItemFt);
      List[Count] := Row;
      Inc(Count);
    end;
    SetLength(Buf, MaxValueNameLen + 2);
    for I := 0 to Integer(Values) - 1 do
    begin
      Len := Length(Buf);
      DataSize := 0;
      Err := RegEnumValue(K, I, PWideChar(Buf), Len, nil, @ValType, nil, @DataSize);
      if Err = ERROR_NO_MORE_ITEMS then
        Break;
      if Err <> 0 then
        Continue;
      Row := Default(TRegRow);
      SetString(Row.Name, PWideChar(Buf), Len);
      if Row.Name = '' then
        Row.Name := cRegDefaultName
      else
        Row.Name := EncodeSegment(Row.Name);
      Row.Size := DataSize;
      Row.Modified := TicksOf(KeyFt);
      List[Count] := Row;
      Inc(Count);
    end;
    SetLength(List, Count);
    ARows := List;
  finally
    RegCloseKey(K);
  end;
end;

function RegPathInfo(const ASegments: TArray<string>; out AKind: TRegPathKind): Cardinal;
var
  K: HKEY;
  Hive: HKEY;
  Size: DWORD;
  N: Integer;
begin
  AKind := rpKey;
  N := Length(ASegments);
  if N = 0 then
  begin
    AKind := rpHiveList;
    Exit(0);
  end;
  if (N = 1) then
  begin
    if HiveHandle(ASegments[0], Hive) then
      Exit(0);
    Exit(ERROR_PATH_NOT_FOUND);
  end;
  Result := OpenKeyOf(ASegments, N, KEY_READ, K);
  if Result = 0 then
  begin
    RegCloseKey(K);
    Exit(0);
  end;
  if Result <> ERROR_FILE_NOT_FOUND then
    Exit;
  Result := OpenKeyOf(ASegments, N - 1, KEY_QUERY_VALUE, K);
  if Result <> 0 then
    Exit;
  try
    Size := 0;
    Result := Cardinal(RegQueryValueEx(K, PChar(ValueNameOf(ASegments[N - 1])), nil, nil, nil, @Size));
    if Result = 0 then
      AKind := rpValue;
  finally
    RegCloseKey(K);
  end;
end;

function RegReadValue(const ASegments: TArray<string>; out AType: Cardinal;
  out AData: TBytes): Cardinal;
var
  K: HKEY;
  Size: DWORD;
  Name: string;
  N, Attempt: Integer;
begin
  AType := 0;
  SetLength(AData, 0);
  N := Length(ASegments);
  if N < 2 then
    Exit(ERROR_FILE_NOT_FOUND);
  Result := OpenKeyOf(ASegments, N - 1, KEY_QUERY_VALUE, K);
  if Result <> 0 then
    Exit;
  try
    Name := ValueNameOf(ASegments[N - 1]);
    // The value can grow between the size query and the read; ask again.
    for Attempt := 1 to 4 do
    begin
      Size := 0;
      Result := Cardinal(RegQueryValueEx(K, PChar(Name), nil, @AType, nil, @Size));
      if Result <> 0 then
        Exit;
      SetLength(AData, Size);
      if Size = 0 then
        Exit(0);
      Result := Cardinal(RegQueryValueEx(K, PChar(Name), nil, @AType, @AData[0], @Size));
      if Result = ERROR_MORE_DATA then
        Continue;
      if Result = 0 then
        SetLength(AData, Size);
      Exit;
    end;
  finally
    RegCloseKey(K);
  end;
end;

function RegWriteValue(const ASegments: TArray<string>; AType: Cardinal;
  const AData: TBytes): Cardinal;
var
  K: HKEY;
  N: Integer;
  Dummy: Byte;
  P: Pointer;
begin
  N := Length(ASegments);
  if N < 2 then
    Exit(ERROR_ACCESS_DENIED);
  Result := OpenKeyOf(ASegments, N - 1, KEY_SET_VALUE, K);
  if Result <> 0 then
    Exit;
  try
    if Length(AData) > 0 then
      P := @AData[0]
    else
      P := @Dummy;
    Result := Cardinal(RegSetValueEx(K, PChar(ValueNameOf(ASegments[N - 1])), 0, AType, P, Length(AData)));
  finally
    RegCloseKey(K);
  end;
end;

function RegDeletePath(const ASegments: TArray<string>): Cardinal;
var
  Kind: TRegPathKind;
  K: HKEY;
  N: Integer;
begin
  N := Length(ASegments);
  if N < 2 then
    Exit(ERROR_ACCESS_DENIED);
  Result := RegPathInfo(ASegments, Kind);
  if Result <> 0 then
    Exit;
  if Kind = rpKey then
  begin
    Result := OpenKeyOf(ASegments, N - 1, KEY_WRITE or KEY_READ, K);
    if Result <> 0 then
      Exit;
    try
      Result := Cardinal(RegDeleteTreeW(K, PChar(ASegments[N - 1])));
    finally
      RegCloseKey(K);
    end;
  end
  else
  begin
    Result := OpenKeyOf(ASegments, N - 1, KEY_SET_VALUE, K);
    if Result <> 0 then
      Exit;
    try
      Result := Cardinal(RegDeleteValue(K, PChar(ValueNameOf(ASegments[N - 1]))));
    finally
      RegCloseKey(K);
    end;
  end;
end;

function RegCreateKeyPath(const ASegments: TArray<string>): Cardinal;
var
  Hive, K: HKEY;
begin
  if (Length(ASegments) < 2) or not HiveHandle(ASegments[0], Hive) then
    Exit(ERROR_ACCESS_DENIED);
  Result := Cardinal(RegCreateKeyEx(Hive, PChar(SubKeyPath(ASegments, Length(ASegments))), 0,
    nil, REG_OPTION_NON_VOLATILE, KEY_READ, nil, K, nil));
  if Result = 0 then
    RegCloseKey(K);
end;

end.
