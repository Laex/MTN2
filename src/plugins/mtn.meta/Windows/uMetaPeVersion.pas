unit uMetaPeVersion;

{ The version resource of an executable or library (Windows). }

interface

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

function ReadPeVersionSummary(const AFileName: string): string;
var
  Handle: DWORD;
  Size: DWORD;
  Block: TBytes;
  Trans: PLangAndCodePage;
  Len: UINT;
  Lang, Version, Company, Description: string;
  Fixed: PVSFixedFileInfo;
begin
  Result := '';
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
  Company := QueryText(@Block[0], Lang, 'CompanyName');
  Description := QueryText(@Block[0], Lang, 'FileDescription');
  Fixed := nil;
  Len := 0;
  if VerQueryValue(@Block[0], '\', Pointer(Fixed), Len) and (Fixed <> nil) and
     (Len >= SizeOf(TVSFixedFileInfo)) then
    Version := Format('%d.%d.%d.%d', [Fixed^.dwFileVersionMS shr 16, Fixed^.dwFileVersionMS and $FFFF,
      Fixed^.dwFileVersionLS shr 16, Fixed^.dwFileVersionLS and $FFFF])
  else
    Version := QueryText(@Block[0], Lang, 'FileVersion');
  AddPart(Result, Version);
  AddPart(Result, Company);
  AddPart(Result, Description);
end;

end.
