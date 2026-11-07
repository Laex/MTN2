unit uWinSysFormat;

{ Pure text helpers of the Windows system plugin: addresses of reg://, proc://
  and svc://, the text form of a registry value (what F3 shows and F4 edits)
  and the names of the process rows. Nothing here calls the system, so the
  unit is tested on its own. }

interface

uses
  System.SysUtils;

type
  TWinSysKind = (wkNone, wkReg, wkProc, wkSvc);

const
  cRegNone = 0;
  cRegSz = 1;
  cRegExpandSz = 2;
  cRegBinary = 3;
  cRegDword = 4;
  cRegDwordBigEndian = 5;
  cRegLink = 6;
  cRegMultiSz = 7;
  cRegQword = 11;

  cRegDefaultName = '(Default)';

  /// <summary>Win32 ERROR_NOT_FOUND, which Winapi.Windows does not declare.</summary>
  cErrorNotFound = 1168;

/// <summary>Splits reg:///HKEY_CURRENT_USER/Software into the kind of the
/// address and its decoded path segments (none for the root). False when the
/// scheme is not one of reg, proc and svc.</summary>
function ParseWinSysUri(const AUri: string; out AKind: TWinSysKind;
  out ASegments: TArray<string>): Boolean;

/// <summary>A key, value or service name as one path segment: '/' is written
/// %2F and '%' is written %25, so a name never splits into two segments.</summary>
function EncodeSegment(const AName: string): string;
function DecodeSegment(const ASegment: string): string;

/// <summary>"chrome.exe (1234)": the row name of a process, unique per process.</summary>
function MakeProcessName(const AExe: string; APid: Cardinal): string;
function ParseProcessName(const AName: string; out APid: Cardinal): Boolean;

function RegTypeName(AType: Cardinal): string;
function RegTypeFromName(const AName: string; out AType: Cardinal): Boolean;

/// <summary>Types whose text form can be written back by ParseRegValueText.</summary>
function IsEditableRegType(AType: Cardinal): Boolean;

/// <summary>The text of a value: a "Type: REG_X" line, an empty line and the
/// data (the string, a number as 0x... (decimal), the lines of a multi-string,
/// a hex dump for anything else).</summary>
function FormatRegValue(AType: Cardinal; const AData: TBytes): string;

/// <summary>The data a text from FormatRegValue stands for. A text without the
/// Type line is of ADefaultType. False when the text does not fit the type or
/// the type cannot be written.</summary>
function ParseRegValueText(const AText: string; ADefaultType: Cardinal;
  out AType: Cardinal; out AData: TBytes): Boolean;

/// <summary>Bytes as lines "00000000  41 42 ...  |AB..|".</summary>
function HexDump(const AData: TBytes): string;

/// <summary>FILETIME ticks (100 ns since 1601, UTC) as seconds since 1970 UTC.</summary>
function FileTimeToUnixSeconds(ATicks: UInt64): Int64;

/// <summary>The message of a Win32 error number the plugin reports; the
/// system's own text on Windows, a short text for the numbers of uWinSysCodes
/// elsewhere.</summary>
function WinSysErrorText(AErr: Cardinal): string;

implementation

uses
  System.StrUtils,
{$IFDEF MSWINDOWS}
  Winapi.Windows;
{$ELSE}
  uWinSysCodes;
{$ENDIF}

function ParseWinSysUri(const AUri: string; out AKind: TWinSysKind;
  out ASegments: TArray<string>): Boolean;
var
  P: Integer;
  Scheme, Rest: string;
  Parts: TArray<string>;
  S: string;
  N: Integer;
begin
  AKind := wkNone;
  SetLength(ASegments, 0);
  P := Pos('://', AUri);
  if P < 2 then
    Exit(False);
  Scheme := LowerCase(Copy(AUri, 1, P - 1));
  if Scheme = 'reg' then
    AKind := wkReg
  else if Scheme = 'proc' then
    AKind := wkProc
  else if Scheme = 'svc' then
    AKind := wkSvc
  else
    Exit(False);
  Rest := Copy(AUri, P + 3, MaxInt);
  Parts := Rest.Split(['/'], TStringSplitOptions.ExcludeEmpty);
  N := 0;
  SetLength(ASegments, Length(Parts));
  for S in Parts do
  begin
    ASegments[N] := DecodeSegment(S);
    Inc(N);
  end;
  Result := True;
end;

function EncodeSegment(const AName: string): string;
begin
  Result := StringReplace(AName, '%', '%25', [rfReplaceAll]);
  Result := StringReplace(Result, '/', '%2F', [rfReplaceAll]);
end;

function DecodeSegment(const ASegment: string): string;
var
  I: Integer;
  Code: string;
begin
  Result := '';
  I := 1;
  while I <= Length(ASegment) do
  begin
    if (ASegment[I] = '%') and (I + 2 <= Length(ASegment)) then
    begin
      Code := UpperCase(Copy(ASegment, I + 1, 2));
      if Code = '2F' then
      begin
        Result := Result + '/';
        Inc(I, 3);
        Continue;
      end;
      if Code = '25' then
      begin
        Result := Result + '%';
        Inc(I, 3);
        Continue;
      end;
    end;
    Result := Result + ASegment[I];
    Inc(I);
  end;
end;

function MakeProcessName(const AExe: string; APid: Cardinal): string;
begin
  Result := EncodeSegment(AExe) + ' (' + UIntToStr(APid) + ')';
end;

function ParseProcessName(const AName: string; out APid: Cardinal): Boolean;
var
  P: Integer;
  Digits: string;
  V: UInt64;
begin
  APid := 0;
  Result := False;
  if (AName = '') or (AName[Length(AName)] <> ')') then
    Exit;
  P := LastDelimiter('(', AName);
  if P < 2 then
    Exit;
  Digits := Copy(AName, P + 1, Length(AName) - P - 1);
  if not TryStrToUInt64(Digits, V) or (V > High(Cardinal)) then
    Exit;
  APid := Cardinal(V);
  Result := True;
end;

function RegTypeName(AType: Cardinal): string;
begin
  case AType of
    cRegNone: Result := 'REG_NONE';
    cRegSz: Result := 'REG_SZ';
    cRegExpandSz: Result := 'REG_EXPAND_SZ';
    cRegBinary: Result := 'REG_BINARY';
    cRegDword: Result := 'REG_DWORD';
    cRegDwordBigEndian: Result := 'REG_DWORD_BIG_ENDIAN';
    cRegLink: Result := 'REG_LINK';
    cRegMultiSz: Result := 'REG_MULTI_SZ';
    8: Result := 'REG_RESOURCE_LIST';
    9: Result := 'REG_FULL_RESOURCE_DESCRIPTOR';
    10: Result := 'REG_RESOURCE_REQUIREMENTS_LIST';
    cRegQword: Result := 'REG_QWORD';
  else
    Result := 'REG_UNKNOWN_' + UIntToStr(AType);
  end;
end;

function RegTypeFromName(const AName: string; out AType: Cardinal): Boolean;
var
  I: Cardinal;
begin
  for I := 0 to 11 do
    if SameText(RegTypeName(I), Trim(AName)) then
    begin
      AType := I;
      Exit(True);
    end;
  AType := 0;
  Result := False;
end;

function IsEditableRegType(AType: Cardinal): Boolean;
begin
  Result := AType in [cRegSz, cRegExpandSz, cRegDword, cRegQword, cRegMultiSz];
end;

function HexDump(const AData: TBytes): string;
var
  Line, Pos, I, Count: Integer;
  Hex, Asc: string;
  B: Byte;
begin
  Result := '';
  Pos := 0;
  Line := 0;
  while Pos < Length(AData) do
  begin
    Count := Length(AData) - Pos;
    if Count > 16 then
      Count := 16;
    Hex := '';
    Asc := '';
    for I := 0 to 15 do
    begin
      if I < Count then
      begin
        B := AData[Pos + I];
        Hex := Hex + IntToHex(B, 2) + ' ';
        if (B >= 32) and (B < 127) then
          Asc := Asc + Char(B)
        else
          Asc := Asc + '.';
      end
      else
        Hex := Hex + '   ';
    end;
    if Line > 0 then
      Result := Result + #10;
    Result := Result + IntToHex(Pos, 8) + '  ' + Hex + ' |' + Asc + '|';
    Inc(Pos, Count);
    Inc(Line);
  end;
end;

function WideText(const AData: TBytes): string;
var
  N: Integer;
begin
  N := Length(AData) div 2;
  if N = 0 then
    Exit('');
  SetString(Result, PChar(@AData[0]), N);
end;

function DataToString(const AData: TBytes): string;
var
  N: Integer;
begin
  Result := WideText(AData);
  N := Length(Result);
  while (N > 0) and (Result[N] = #0) do
    Dec(N);
  SetLength(Result, N);
end;

function ReadDword(const AData: TBytes): Cardinal;
begin
  Result := 0;
  if Length(AData) >= 4 then
    Move(AData[0], Result, 4);
end;

function ReadQword(const AData: TBytes): UInt64;
begin
  Result := 0;
  if Length(AData) >= 8 then
    Move(AData[0], Result, 8);
end;

function MultiSzLines(const AData: TBytes): string;
var
  Text: string;
  N: Integer;
begin
  Text := WideText(AData);
  N := Length(Text);
  // The list ends with an empty string: drop the terminators, keep the separators.
  while (N > 0) and (Text[N] = #0) do
    Dec(N);
  Result := StringReplace(Copy(Text, 1, N), #0, #10, [rfReplaceAll]);
end;

function FormatRegValue(AType: Cardinal; const AData: TBytes): string;
var
  V: Cardinal;
  Q: UInt64;
  Body: string;
begin
  case AType of
    cRegSz, cRegExpandSz, cRegLink:
      Body := DataToString(AData);
    cRegDword:
      begin
        V := ReadDword(AData);
        Body := '0x' + IntToHex(V, 8) + ' (' + UIntToStr(V) + ')';
      end;
    cRegDwordBigEndian:
      begin
        V := ReadDword(AData);
        V := ((V and $FF) shl 24) or ((V and $FF00) shl 8) or
          ((V shr 8) and $FF00) or (V shr 24);
        Body := '0x' + IntToHex(V, 8) + ' (' + UIntToStr(V) + ')';
      end;
    cRegQword:
      begin
        Q := ReadQword(AData);
        Body := '0x' + IntToHex(Int64(Q), 16) + ' (' + UIntToStr(Q) + ')';
      end;
    cRegMultiSz:
      Body := MultiSzLines(AData);
  else
    Body := HexDump(AData);
  end;
  Result := 'Type: ' + RegTypeName(AType) + #10#10 + Body;
end;

function StringToWideData(const AText: string; AExtraNuls: Integer): TBytes;
var
  Bytes: Integer;
begin
  Bytes := Length(AText) * 2;
  SetLength(Result, Bytes + AExtraNuls * 2);
  if Bytes > 0 then
    Move(PChar(AText)^, Result[0], Bytes);
  if AExtraNuls > 0 then
    FillChar(Result[Bytes], AExtraNuls * 2, 0);
end;

function ParseNumber(const ABody: string; AMax: UInt64; out AValue: UInt64): Boolean;
var
  Token: string;
  P: Integer;
begin
  Token := Trim(ABody);
  P := Pos(' ', Token);
  if P > 0 then
    Token := Copy(Token, 1, P - 1);
  if Token = '' then
    Exit(False);
  if StartsText('0x', Token) then
    Token := '$' + Copy(Token, 3, MaxInt);
  Result := TryStrToUInt64(Token, AValue) and (AValue <= AMax);
end;

function ParseRegValueText(const AText: string; ADefaultType: Cardinal;
  out AType: Cardinal; out AData: TBytes): Boolean;
var
  Body, Head: string;
  P, I: Integer;
  Lines: TArray<string>;
  Joined: string;
  N: UInt64;
  D: Cardinal;
begin
  SetLength(AData, 0);
  AType := ADefaultType;
  Body := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  if StartsText('Type:', Body) then
  begin
    P := Pos(#10, Body);
    if P = 0 then
      P := Length(Body) + 1;
    Head := Copy(Body, 6, P - 6);
    if not RegTypeFromName(Head, AType) then
      Exit(False);
    Body := Copy(Body, P + 1, MaxInt);
    if StartsStr(#10, Body) then
      Delete(Body, 1, 1);
  end;
  if not IsEditableRegType(AType) then
    Exit(False);
  case AType of
    cRegSz, cRegExpandSz:
      begin
        if EndsStr(#10, Body) then
          Delete(Body, Length(Body), 1);
        AData := StringToWideData(Body, 1);
      end;
    cRegDword:
      begin
        if not ParseNumber(Body, High(Cardinal), N) then
          Exit(False);
        D := Cardinal(N);
        SetLength(AData, 4);
        Move(D, AData[0], 4);
      end;
    cRegQword:
      begin
        if not ParseNumber(Body, High(UInt64), N) then
          Exit(False);
        SetLength(AData, 8);
        Move(N, AData[0], 8);
      end;
    cRegMultiSz:
      begin
        Lines := Body.Split([#10]);
        P := Length(Lines);
        while (P > 0) and (Lines[P - 1] = '') do
          Dec(P);
        Joined := '';
        for I := 0 to P - 1 do
          Joined := Joined + Lines[I] + #0;
        AData := StringToWideData(Joined, 1);
      end;
  end;
  Result := True;
end;

function FileTimeToUnixSeconds(ATicks: UInt64): Int64;
const
  cEpochDiff: UInt64 = 116444736000000000;
begin
  if ATicks < cEpochDiff then
    Exit(0);
  Result := Int64((ATicks - cEpochDiff) div 10000000);
end;

function WinSysErrorText(AErr: Cardinal): string;
begin
{$IFDEF MSWINDOWS}
  Result := Trim(SysErrorMessage(AErr));
{$ELSE}
  case AErr of
    ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND, ERROR_SERVICE_DOES_NOT_EXIST:
      Result := 'Not found';
    ERROR_ACCESS_DENIED, ERROR_PRIVILEGE_NOT_HELD:
      Result := 'Access denied';
    ERROR_INVALID_FUNCTION:
      Result := 'Not supported here';
    ERROR_SERVICE_REQUEST_TIMEOUT:
      Result := 'The request timed out';
    ERROR_INVALID_PARAMETER:
      Result := 'Invalid parameter';
    ERROR_ALREADY_EXISTS:
      Result := 'Already exists';
  else
    Result := 'Error ' + IntToStr(AErr);
  end;
{$ENDIF}
end;

end.
