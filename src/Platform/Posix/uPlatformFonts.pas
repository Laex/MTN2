unit uPlatformFonts;

{ Installed font families (Posix build, fontconfig through the fc-list
  tool). The Windows build lives in Platform\Windows; each project puts
  exactly one of the two directories on its unit search path. }

interface

/// <summary>Monospace family used when nothing else is configured or
/// installed.</summary>
function PlatformDefaultMonoFont: string;

/// <summary>True when a font family with this exact name is installed.</summary>
function PlatformFontInstalled(const AName: string): Boolean;

/// <summary>Names of the installed monospace families.</summary>
function PlatformMonoFonts: TArray<string>;

/// <summary>Path of the font file that serves a family in a style; '' when
/// none is found. The closest installed style is returned when the exact one
/// is missing.</summary>
function PlatformFontFile(const AFamily: string; ABold, AItalic: Boolean): string;

/// <summary>Path of a font file that has a glyph for the code point (CJK,
/// symbols); '' when none is found.</summary>
function PlatformFontFileForChar(ACodePoint: Integer): string;

implementation

uses
  System.SysUtils, System.Classes, Posix.Base;

function popen(ACommand, AMode: MarshaledAString): Pointer; cdecl;
  external libc name 'popen';
function pclose(AStream: Pointer): Integer; cdecl;
  external libc name 'pclose';
function fread(ABuf: Pointer; ASize, ACount: NativeUInt; AStream: Pointer): NativeUInt; cdecl;
  external libc name 'fread';

function RunCapture(const ACommand: string): string;
var
  Pipe: Pointer;
  Buf: array[0..4095] of Byte;
  Got: NativeUInt;
  Bytes: TBytes;
  Cmd: UTF8String;
begin
  Result := '';
  Cmd := UTF8String(ACommand);
  Pipe := popen(MarshaledAString(Cmd), 'r');
  if Pipe = nil then
    Exit;
  try
    repeat
      Got := fread(@Buf[0], 1, SizeOf(Buf), Pipe);
      if Got > 0 then
      begin
        SetLength(Bytes, Length(Bytes) + Got);
        Move(Buf[0], Bytes[Length(Bytes) - Got], Got);
      end;
    until Got = 0;
  finally
    pclose(Pipe);
  end;
  Result := TEncoding.UTF8.GetString(Bytes);
end;

function FamiliesOf(const AQuery: string): TArray<string>;
var
  Lines: TStringList;
  List: TStringList;
  Line, Family: string;
begin
  Lines := TStringList.Create;
  List := TStringList.Create;
  try
    List.CaseSensitive := False;
    Lines.Text := RunCapture('fc-list ' + AQuery + ' -f ''%{family}\n'' 2>/dev/null');
    for Line in Lines do
    begin
      // A font can carry several names ("Name,Alias"): the first is canonical.
      Family := Trim(Line);
      if Pos(',', Family) > 0 then
        Family := Trim(Copy(Family, 1, Pos(',', Family) - 1));
      if (Family <> '') and (List.IndexOf(Family) < 0) then
        List.Add(Family);
    end;
    Result := List.ToStringArray;
  finally
    List.Free;
    Lines.Free;
  end;
end;

function PlatformDefaultMonoFont: string;
begin
  Result := 'DejaVu Sans Mono';
end;

function PlatformFontInstalled(const AName: string): Boolean;
var
  Face: string;
  Name: string;
begin
  Face := Trim(AName);
  Result := False;
  if Face = '' then
    Exit;
  for Name in FamiliesOf('') do
    if SameText(Name, Face) then
      Exit(True);
end;

function PlatformMonoFonts: TArray<string>;
begin
  Result := FamiliesOf(':spacing=mono');
end;

function MatchedFile(const APattern: string): string;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := RunCapture('fc-match -f ''%{file}\n'' ''' + APattern + ''' 2>/dev/null');
    Result := '';
    if Lines.Count > 0 then
      Result := Trim(Lines[0]);
  finally
    Lines.Free;
  end;
end;

function PlatformFontFile(const AFamily: string; ABold, AItalic: Boolean): string;
var
  Pattern: string;
begin
  Pattern := StringReplace(Trim(AFamily), '''', '', [rfReplaceAll]);
  if ABold then
    Pattern := Pattern + ':weight=bold';
  if AItalic then
    Pattern := Pattern + ':slant=italic';
  Result := MatchedFile(Pattern);
end;

function PlatformFontFileForChar(ACodePoint: Integer): string;
const
  // Fonts of a Windows host that WSL mounts; fontconfig does not know them.
  cHostCjkFonts: array[0..4] of string = (
    '/mnt/c/Windows/Fonts/msyh.ttc', '/mnt/c/Windows/Fonts/simsun.ttc',
    '/mnt/c/Windows/Fonts/msgothic.ttc', '/mnt/c/Windows/Fonts/malgun.ttf',
    '/mnt/c/Windows/Fonts/YuGothR.ttc');
var
  Lines: TStringList;
  Charset, Name: string;
begin
  Charset := ':charset=' + IntToHex(ACodePoint, 1);
  // fc-match always answers with its best guess, covering the character or
  // not; fc-list names only the fonts that have it.
  Lines := TStringList.Create;
  try
    Lines.Text := RunCapture('fc-list ''' + Charset + ''' -f ''%{file}\n'' 2>/dev/null');
    Result := '';
    if Lines.Count > 0 then
      Result := Trim(Lines[0]);
  finally
    Lines.Free;
  end;
  if (Result = '') and (ACodePoint >= $2E80) then
    for Name in cHostCjkFonts do
      if FileExists(Name) then
        Exit(Name);
  if Result = '' then
    Result := MatchedFile(Charset);
end;

end.
