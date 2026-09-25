unit uZipNames;

{ ZIP entry-name helpers extracted from uZipVfs so path safety can be
  tested without opening an archive. }

interface

uses
  System.SysUtils;

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

end.
