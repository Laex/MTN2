unit uZipNames;

{ ZIP entry-name helpers extracted from uZipVfs so path safety can be
  tested without opening an archive. }

interface

uses
  System.SysUtils, System.Zip;

/// <summary>Opens-for-reading ZipFile whose entry names without the UTF-8
/// flag are decoded as UTF-8 when the bytes are valid UTF-8 (archives made by
/// macOS and many Linux tools), otherwise as the OEM code page.</summary>
function NewReadZipFile: TZipFile;
/// <summary>True when ABytes[0..ACount-1] is well-formed UTF-8.</summary>
function IsValidUtf8(ABytes: PByte; ACount: Integer): Boolean;
function NormZipName(const AName: string): string;
function IsUnsafeZipName(const AName: string): Boolean;
/// <summary>True when ASegments is an outer file-backed zip (no nested
/// zip!/inner.zip layers). Nested stacks are Length >= 2.</summary>
function ZipWriteAllowed(const ASegments: TArray<string>): Boolean;
/// <summary>APrefWithSlash is already normalized and either empty or ends
/// with '/'. False when the name is outside the prefix or the rest is empty.</summary>
function ZipRestAfterPrefix(const ANormName, APrefWithSlash: string;
  out ARest: string): Boolean;
function ZipNameEqualsOrUnder(const AName, APrefix: string): Boolean;

implementation

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows;
{$ENDIF}

type
  TZipNameEncoding = class(TUTF8Encoding)
  strict private
    FOem: TEncoding;
    function OemString(ABytes: PByte; ACount: Integer): string;
  protected
    function GetCharCount(Bytes: PByte; ByteCount: Integer): Integer; overload; override;
    function GetChars(Bytes: PByte; ByteCount: Integer; Chars: PChar;
      CharCount: Integer): Integer; overload; override;
  public
    constructor Create;
    destructor Destroy; override;
  end;

var
  GZipNameEncoding: TZipNameEncoding;

function IsValidUtf8(ABytes: PByte; ACount: Integer): Boolean;
var
  I, Extra: Integer;
  B: Byte;
begin
  I := 0;
  while I < ACount do
  begin
    B := ABytes[I];
    Inc(I);
    if B < $80 then
      Continue;
    if (B >= $C2) and (B <= $DF) then
      Extra := 1
    else if (B >= $E0) and (B <= $EF) then
      Extra := 2
    else if (B >= $F0) and (B <= $F4) then
      Extra := 3
    else
      Exit(False);
    if I + Extra > ACount then
      Exit(False);
    while Extra > 0 do
    begin
      if (ABytes[I] and $C0) <> $80 then
        Exit(False);
      Inc(I);
      Dec(Extra);
    end;
  end;
  Result := True;
end;

constructor TZipNameEncoding.Create;
begin
  inherited Create;
{$IFDEF MSWINDOWS}
  FOem := TEncoding.GetEncoding(GetOEMCP);
{$ELSE}
  FOem := TEncoding.GetEncoding(437);
{$ENDIF}
end;

destructor TZipNameEncoding.Destroy;
begin
  FOem.Free;
  inherited;
end;

function TZipNameEncoding.OemString(ABytes: PByte; ACount: Integer): string;
var
  B: TBytes;
begin
  SetLength(B, ACount);
  if ACount > 0 then
    Move(ABytes^, B[0], ACount);
  Result := FOem.GetString(B);
end;

function TZipNameEncoding.GetCharCount(Bytes: PByte; ByteCount: Integer): Integer;
begin
  if IsValidUtf8(Bytes, ByteCount) then
    Result := inherited GetCharCount(Bytes, ByteCount)
  else
    Result := Length(OemString(Bytes, ByteCount));
end;

function TZipNameEncoding.GetChars(Bytes: PByte; ByteCount: Integer;
  Chars: PChar; CharCount: Integer): Integer;
var
  S: string;
begin
  if IsValidUtf8(Bytes, ByteCount) then
    Result := inherited GetChars(Bytes, ByteCount, Chars, CharCount)
  else
  begin
    S := OemString(Bytes, ByteCount);
    Result := Length(S);
    if Result > CharCount then
      Result := CharCount;
    if Result > 0 then
      Move(PChar(S)^, Chars^, Result * SizeOf(Char));
  end;
end;

function NewReadZipFile: TZipFile;
begin
  Result := TZipFile.Create;
  Result.Encoding := GZipNameEncoding;
end;

function NormZipName(const AName: string): string;
begin
  Result := StringReplace(AName, '\', '/', [rfReplaceAll]);
  while (Length(Result) > 0) and (Result[1] = '/') do
    Delete(Result, 1, 1);
  while (Length(Result) > 0) and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

function IsUnsafeZipName(const AName: string): Boolean;
var
  N: string;
begin
  N := NormZipName(AName);
  Result := (N = '') or N.Contains('../') or N.StartsWith('..') or
    (Pos(':', N) > 0);
end;

function ZipWriteAllowed(const ASegments: TArray<string>): Boolean;
begin
  Result := Length(ASegments) < 2;
end;

function ZipRestAfterPrefix(const ANormName, APrefWithSlash: string;
  out ARest: string): Boolean;
begin
  if APrefWithSlash = '' then
    ARest := ANormName
  else if ANormName.StartsWith(APrefWithSlash, True) then
    ARest := Copy(ANormName, Length(APrefWithSlash) + 1, MaxInt)
  else
  begin
    ARest := '';
    Exit(False);
  end;
  Result := ARest <> '';
end;

function ZipNameEqualsOrUnder(const AName, APrefix: string): Boolean;
var
  N, P: string;
begin
  N := NormZipName(AName);
  P := NormZipName(APrefix);
  Result := (P <> '') and (SameText(N, P) or N.StartsWith(P + '/', True));
end;

initialization
  GZipNameEncoding := TZipNameEncoding.Create;

finalization
  GZipNameEncoding.Free;

end.
