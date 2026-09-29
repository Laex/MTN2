unit uDescriptIon;

{ File descriptions in a Descript.ion file, the format FAR and Total Commander
  share: one line per file, "name description"; a name with spaces is quoted.
  A file is read as UTF-8 when it is valid UTF-8, else in the system ANSI code
  page, and written back the same way; a new file is UTF-8 with a BOM. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults;

/// <summary>ADir plus the file name, whatever case an existing file has.</summary>
function DescriptionsFilePath(const ADir: string): string;
function ParseDescriptionLine(const ALine: string; out AName, ADescription: string): Boolean;
function FormatDescriptionLine(const AName, ADescription: string): string;
/// <summary>Descriptions of the files in ADir by name, case-insensitive; empty
/// when the folder has no Descript.ion. The caller frees the result.</summary>
function LoadDescriptions(const ADir: string): TDictionary<string, string>;
/// <summary>Sets the description of AName in ADir's Descript.ion; '' removes it,
/// and the file itself when nothing is left. False when it cannot be written.</summary>
function StoreDescription(const ADir, AName, ADescription: string): Boolean;

implementation

uses
  System.IOUtils;

const
  cFileName = 'Descript.ion';

function DescriptionsFilePath(const ADir: string): string;
var
  Found: string;
begin
  Result := TPath.Combine(ADir, cFileName);
  if TFile.Exists(Result) then
    Exit;
  if TDirectory.Exists(ADir) then
    for Found in TDirectory.GetFiles(ADir, '*.ion') do
      if SameText(TPath.GetFileName(Found), cFileName) then
        Exit(Found);
end;

function ParseDescriptionLine(const ALine: string; out AName, ADescription: string): Boolean;
var
  Line: string;
  P: Integer;
begin
  AName := '';
  ADescription := '';
  Line := Trim(ALine);
  Result := Line <> '';
  if not Result then
    Exit;
  if Line[1] = '"' then
  begin
    P := Pos('"', Line, 2);
    if P = 0 then
      Exit(False);
    AName := Copy(Line, 2, P - 2);
    ADescription := Trim(Copy(Line, P + 1, MaxInt));
  end
  else
  begin
    P := Pos(' ', Line);
    if P = 0 then
      AName := Line
    else
    begin
      AName := Copy(Line, 1, P - 1);
      ADescription := Trim(Copy(Line, P + 1, MaxInt));
    end;
  end;
  Result := AName <> '';
end;

function FormatDescriptionLine(const AName, ADescription: string): string;
begin
  if (Pos(' ', AName) > 0) or (Pos('"', AName) > 0) then
    Result := '"' + AName + '" ' + ADescription
  else
    Result := AName + ' ' + ADescription;
end;

function IsValidUtf8(const ABytes: TBytes): Boolean;
var
  I, Extra: Integer;
  B: Byte;
begin
  I := 0;
  while I < Length(ABytes) do
  begin
    B := ABytes[I];
    if B < $80 then
      Extra := 0
    else if (B and $E0) = $C0 then
      Extra := 1
    else if (B and $F0) = $E0 then
      Extra := 2
    else if (B and $F8) = $F0 then
      Extra := 3
    else
      Exit(False);
    while Extra > 0 do
    begin
      Inc(I);
      if (I >= Length(ABytes)) or ((ABytes[I] and $C0) <> $80) then
        Exit(False);
      Dec(Extra);
    end;
    Inc(I);
  end;
  Result := True;
end;

function ReadLines(const APath: string; out AEncoding: TEncoding;
  out AHasBom: Boolean): TArray<string>;
var
  Bytes: TBytes;
  Text: string;
  Offset: Integer;
begin
  AEncoding := TEncoding.UTF8;
  AHasBom := False;
  Result := nil;
  if not TFile.Exists(APath) then
    Exit;
  Bytes := TFile.ReadAllBytes(APath);
  Offset := TEncoding.GetBufferEncoding(Bytes, AEncoding, TEncoding.Default);
  AHasBom := Offset > 0;
  if Offset = 0 then
  begin
    // No BOM: UTF-8 when the bytes are valid UTF-8, else the ANSI code page.
    if IsValidUtf8(Bytes) then
      AEncoding := TEncoding.UTF8
    else
      AEncoding := TEncoding.ANSI;
  end;
  Text := AEncoding.GetString(Bytes, Offset, Length(Bytes) - Offset);
  Text := StringReplace(Text, #13#10, #10, [rfReplaceAll]);
  Result := Text.Split([#10]);
end;

function LoadDescriptions(const ADir: string): TDictionary<string, string>;
var
  Enc: TEncoding;
  HasBom: Boolean;
  Line, Name, Desc: string;
begin
  Result := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  try
    for Line in ReadLines(DescriptionsFilePath(ADir), Enc, HasBom) do
      if ParseDescriptionLine(Line, Name, Desc) and (Desc <> '') then
        Result.AddOrSetValue(Name, Desc);
  except
    // An unreadable file has no descriptions.
    Result.Clear;
  end;
end;

function StoreDescription(const ADir, AName, ADescription: string): Boolean;
var
  Path: string;
  Enc: TEncoding;
  Lines: TArray<string>;
  Kept: TList<string>;
  Line, Name, Desc, Text: string;
  Replaced, HasBom: Boolean;
  Bytes: TBytes;
begin
  Path := DescriptionsFilePath(ADir);
  Kept := TList<string>.Create;
  try
    try
      Lines := ReadLines(Path, Enc, HasBom);
      Replaced := False;
      for Line in Lines do
      begin
        if Line = '' then
          Continue;
        if ParseDescriptionLine(Line, Name, Desc) and SameText(Name, AName) then
        begin
          if (ADescription <> '') and not Replaced then
            Kept.Add(FormatDescriptionLine(AName, ADescription));
          Replaced := True;
        end
        else
          Kept.Add(Line);
      end;
      if (ADescription <> '') and not Replaced then
        Kept.Add(FormatDescriptionLine(AName, ADescription));
      if Kept.Count = 0 then
      begin
        if TFile.Exists(Path) then
          TFile.Delete(Path);
        Exit(True);
      end;
      Text := string.Join(#13#10, Kept.ToArray) + #13#10;
      if not TFile.Exists(Path) then
      begin
        Path := TPath.Combine(ADir, cFileName);
        Enc := TEncoding.UTF8;
        HasBom := True;
      end;
      Bytes := Enc.GetBytes(Text);
      if HasBom then
        Bytes := Enc.GetPreamble + Bytes;
      TFile.WriteAllBytes(Path, Bytes);
      Result := True;
    except
      Result := False;
    end;
  finally
    Kept.Free;
  end;
end;

end.
