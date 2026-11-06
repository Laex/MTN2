unit uMetaPeVersion;

{ The version resource of an executable or library (Windows). }

interface

type
  TPeVersion = record
    /// <summary>"1.2.3.4".</summary>
    Version: string;
    /// <summary>The four parts packed high to low, so numbers sort as versions do.</summary>
    VersionKey: Int64;
    Company: string;
    Description: string;
  end;

/// <summary>The version, company and description from the version resource of
/// AFileName; False when the file has none.</summary>
function ReadPeVersion(const AFileName: string; out AInfo: TPeVersion): Boolean;

/// <summary>"1.2.3.4  |  Company  |  Description" from the version resource of AFileName;
/// '' when the file has none.</summary>
function ReadPeVersionSummary(const AFileName: string): string;

implementation

uses
  System.SysUtils, Winapi.Windows;

type
  TLangAndCodePage = record
    Language: Word;
    CodePage: Word;
  end;
  PLangAndCodePage = ^TLangAndCodePage;

function QueryText(ABlock: Pointer; const ALang, AName: string): string;
var
  Value: PChar;
  Len: UINT;
begin
  Result := '';
  Value := nil;
  Len := 0;
  if VerQueryValue(ABlock, PChar('\StringFileInfo\' + ALang + '\' + AName), Pointer(Value), Len) and
     (Len > 0) and (Value <> nil) then
    Result := Trim(string(Value));
end;

procedure AddPart(var AText: string; const APart: string);
begin
  if APart = '' then
    Exit;
  if AText <> '' then
    AText := AText + '  |  ';
  AText := AText + APart;
end;

function ReadPeVersion(const AFileName: string; out AInfo: TPeVersion): Boolean;
var
  Handle: DWORD;
  Size: DWORD;
  Block: TBytes;
  Trans: PLangAndCodePage;
  Len: UINT;
  Lang: string;
  Fixed: PVSFixedFileInfo;
begin
  Result := False;
  AInfo := Default(TPeVersion);
  Size := GetFileVersionInfoSize(PChar(AFileName), Handle);
  if Size = 0 then
    Exit;
  SetLength(Block, Size);
  if not GetFileVersionInfo(PChar(AFileName), 0, Size, @Block[0]) then
    Exit;
  Trans := nil;
  Len := 0;
  if VerQueryValue(@Block[0], '\VarFileInfo\Translation', Pointer(Trans), Len) and
     (Len >= SizeOf(TLangAndCodePage)) and (Trans <> nil) then
    Lang := IntToHex(Trans^.Language, 4) + IntToHex(Trans^.CodePage, 4)
  else
    Lang := '040904B0';
  AInfo.Company := QueryText(@Block[0], Lang, 'CompanyName');
  AInfo.Description := QueryText(@Block[0], Lang, 'FileDescription');
  Fixed := nil;
  Len := 0;
  if VerQueryValue(@Block[0], '\', Pointer(Fixed), Len) and (Fixed <> nil) and
     (Len >= SizeOf(TVSFixedFileInfo)) then
  begin
    AInfo.Version := Format('%d.%d.%d.%d', [Fixed^.dwFileVersionMS shr 16,
      Fixed^.dwFileVersionMS and $FFFF, Fixed^.dwFileVersionLS shr 16,
      Fixed^.dwFileVersionLS and $FFFF]);
    AInfo.VersionKey := (Int64(Fixed^.dwFileVersionMS) shl 32) or Fixed^.dwFileVersionLS;
  end
  else
    AInfo.Version := QueryText(@Block[0], Lang, 'FileVersion');
  Result := True;
end;

function ReadPeVersionSummary(const AFileName: string): string;
var
  Info: TPeVersion;
begin
  Result := '';
  if not ReadPeVersion(AFileName, Info) then
    Exit;
  AddPart(Result, Info.Version);
  AddPart(Result, Info.Company);
  AddPart(Result, Info.Description);
end;

end.
