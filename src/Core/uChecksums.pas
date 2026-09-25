unit uChecksums;

{ File checksums (Files > Checksums..., Ctrl+Alt+H): MD5 / SHA-1 / SHA-256 /
  SHA-512 of local files, streamed in 1 MB blocks so a cancel flag stops a
  large file promptly; lines in the format sha256sum / 7-Zip / TC read and
  write ("hash *name"), and verification of a checksum file.

  Pure logic -- TDualPanelWindow runs it on a worker thread and shows the
  result. }

interface

uses
  System.SysUtils;

type
  TChecksumAlgo = (caMD5, caSHA1, caSHA256, caSHA512);

  /// <summary>True = stop (the user cancelled).</summary>
  TChecksumCancelled = reference to function: Boolean;

  TChecksumFile = record
    Path: string;
    /// <summary>Name as written into the checksum file: relative to the
    /// base folder, '\' separators.</summary>
    RelName: string;
  end;

  TChecksumVerifyStatus = (cvsOk, cvsFailed, cvsMissing, cvsError);

  TChecksumVerifyItem = record
    RelName: string;
    Status: TChecksumVerifyStatus;
  end;

const
  cChecksumAlgoNames: array[TChecksumAlgo] of string =
    ('MD5', 'SHA-1', 'SHA-256', 'SHA-512');
  cChecksumAlgoExts: array[TChecksumAlgo] of string =
    ('.md5', '.sha1', '.sha256', '.sha512');

/// <summary>Lower-case hex digest; '' when cancelled. Raises on read errors.</summary>
function HashFileHex(const APath: string; AAlgo: TChecksumAlgo;
  const ACancelled: TChecksumCancelled = nil): string;
function HashBytesHex(const AData: TBytes; AAlgo: TChecksumAlgo): string;

/// <summary>"hash *name" (binary mode marker, as 7-Zip / TC / sha256sum -b).</summary>
function FormatChecksumLine(const AHash, ARelName: string): string;
/// <summary>Accepts "hash  name", "hash *name" and BSD "SHA256 (name) = hash".
/// Blank lines and ';' / '#' comments give False.</summary>
function ParseChecksumLine(const ALine: string; out AHash, ARelName: string): Boolean;
function ChecksumAlgoFromExt(const AFileName: string; out AAlgo: TChecksumAlgo): Boolean;
/// <summary>Hex length of the digest: 32 / 40 / 64 / 128.</summary>
function ChecksumHexLength(AAlgo: TChecksumAlgo): Integer;

/// <summary>Files for APaths (files as is, folders recursively), names
/// relative to ABaseDir, sorted by name.</summary>
function CollectChecksumFiles(const APaths: TArray<string>;
  const ABaseDir: string): TArray<TChecksumFile>;
/// <summary>Where Save writes: "<file>.<ext>" for one file, else
/// "checksums.<ext>" in ABaseDir.</summary>
function ChecksumSaveFileName(const AFiles: TArray<TChecksumFile>;
  const ABaseDir: string; AAlgo: TChecksumAlgo): string;

/// <summary>Checks every line of AChecksumFile against the files next to
/// it. Returns False when cancelled (AItems then holds what was checked).</summary>
function VerifyChecksumFile(const AChecksumFile: string; AAlgo: TChecksumAlgo;
  out AItems: TArray<TChecksumVerifyItem>;
  const ACancelled: TChecksumCancelled = nil): Boolean;
function ChecksumVerifyStatusText(AStatus: TChecksumVerifyStatus): string;

implementation

uses
  System.Classes, System.IOUtils, System.Hash, System.StrUtils,
  System.Generics.Collections, System.Generics.Defaults;

const
  cBlockSize = 1024 * 1024;

function ChecksumHexLength(AAlgo: TChecksumAlgo): Integer;
begin
  case AAlgo of
    caMD5: Result := 32;
    caSHA1: Result := 40;
    caSHA256: Result := 64;
  else
    Result := 128;
  end;
end;

type
  /// <summary>One interface over the System.Hash records.</summary>
  THasher = record
    Algo: TChecksumAlgo;
    MD5: THashMD5;
    SHA1: THashSHA1;
    SHA2: THashSHA2;
    procedure Init(AAlgo: TChecksumAlgo);
    procedure Update(const ABuffer: TBytes; ACount: Integer);
    function Hex: string;
  end;

procedure THasher.Init(AAlgo: TChecksumAlgo);
begin
  Algo := AAlgo;
  case AAlgo of
    caMD5: MD5 := THashMD5.Create;
    caSHA1: SHA1 := THashSHA1.Create;
    caSHA256: SHA2 := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
    caSHA512: SHA2 := THashSHA2.Create(THashSHA2.TSHA2Version.SHA512);
  end;
end;

procedure THasher.Update(const ABuffer: TBytes; ACount: Integer);
begin
  if ACount <= 0 then
    Exit;
  case Algo of
    caMD5: MD5.Update(ABuffer, ACount);
    caSHA1: SHA1.Update(ABuffer, ACount);
  else
    SHA2.Update(ABuffer, ACount);
  end;
end;

function THasher.Hex: string;
begin
  case Algo of
    caMD5: Result := MD5.HashAsString;
    caSHA1: Result := SHA1.HashAsString;
  else
    Result := SHA2.HashAsString;
  end;
  Result := LowerCase(Result);
end;

function HashBytesHex(const AData: TBytes; AAlgo: TChecksumAlgo): string;
var
  H: THasher;
begin
  H.Init(AAlgo);
  H.Update(AData, Length(AData));
  Result := H.Hex;
end;

function HashFileHex(const APath: string; AAlgo: TChecksumAlgo;
  const ACancelled: TChecksumCancelled): string;
var
  H: THasher;
  Stream: TFileStream;
  Buffer: TBytes;
  N: Integer;
begin
  Result := '';
  H.Init(AAlgo);
  SetLength(Buffer, cBlockSize);
  Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    repeat
      if Assigned(ACancelled) and ACancelled() then
        Exit('');
      N := Stream.Read(Buffer, 0, cBlockSize);
      H.Update(Buffer, N);
    until N < cBlockSize;
  finally
    Stream.Free;
  end;
  Result := H.Hex;
end;

function FormatChecksumLine(const AHash, ARelName: string): string;
begin
  Result := AHash + ' *' + ARelName;
end;

function IsHex(const S: string): Boolean;
var
  C: Char;
begin
  Result := S <> '';
  for C in S do
    if not CharInSet(C, ['0'..'9', 'a'..'f', 'A'..'F']) then
      Exit(False);
end;

function ParseChecksumLine(const ALine: string; out AHash, ARelName: string): Boolean;
var
  S: string;
  P, Q: Integer;
begin
  Result := False;
  AHash := '';
  ARelName := '';
  S := Trim(ALine);
  if (S = '') or (S[1] = ';') or (S[1] = '#') then
    Exit;
  // BSD / openssl: "SHA256 (name) = hash"
  P := Pos(' (', S);
  Q := LastDelimiter('=', S);
  if (P > 0) and (Q > P) and (Pos(') =', S) > 0) and IsHex(Trim(Copy(S, Q + 1, MaxInt))) then
  begin
    AHash := LowerCase(Trim(Copy(S, Q + 1, MaxInt)));
    ARelName := Copy(S, P + 2, LastDelimiter(')', Copy(S, 1, Q)) - P - 2);
    Exit(ARelName <> '');
  end;
  // GNU / 7-Zip / TC: "hash  name" or "hash *name"
  P := Pos(' ', S);
  if P < 2 then
    Exit;
  AHash := LowerCase(Copy(S, 1, P - 1));
  if not IsHex(AHash) then
    Exit;
  ARelName := Copy(S, P + 1, MaxInt);
  if (ARelName <> '') and CharInSet(ARelName[1], [' ', '*']) then
    Delete(ARelName, 1, 1);
  Result := ARelName <> '';
end;

function ChecksumAlgoFromExt(const AFileName: string; out AAlgo: TChecksumAlgo): Boolean;
var
  Ext: string;
  A: TChecksumAlgo;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  for A := Low(TChecksumAlgo) to High(TChecksumAlgo) do
    if Ext = cChecksumAlgoExts[A] then
    begin
      AAlgo := A;
      Exit(True);
    end;
  Result := False;
end;

function CollectChecksumFiles(const APaths: TArray<string>;
  const ABaseDir: string): TArray<TChecksumFile>;
var
  List: TList<TChecksumFile>;
  Base: string;

  procedure AddFile(const APath: string);
  var
    F: TChecksumFile;
  begin
    F.Path := APath;
    if (Base <> '') and StartsText(Base, APath) then
      F.RelName := Copy(APath, Length(Base) + 1, MaxInt)
    else
      F.RelName := ExtractFileName(APath);
    List.Add(F);
  end;

var
  P, F: string;
begin
  Base := ABaseDir;
  if Base <> '' then
    Base := IncludeTrailingPathDelimiter(Base);
  List := TList<TChecksumFile>.Create;
  try
    for P in APaths do
      if TDirectory.Exists(P) then
      begin
        for F in TDirectory.GetFiles(P, '*', TSearchOption.soAllDirectories) do
          AddFile(F);
      end
      else if TFile.Exists(P) then
        AddFile(P);
    List.Sort(TComparer<TChecksumFile>.Construct(
      function(const A, B: TChecksumFile): Integer
      begin
        Result := CompareText(A.RelName, B.RelName);
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function ChecksumSaveFileName(const AFiles: TArray<TChecksumFile>;
  const ABaseDir: string; AAlgo: TChecksumAlgo): string;
begin
  if Length(AFiles) = 1 then
    Result := AFiles[0].Path + cChecksumAlgoExts[AAlgo]
  else
    Result := TPath.Combine(ABaseDir, 'checksums' + cChecksumAlgoExts[AAlgo]);
end;

function VerifyChecksumFile(const AChecksumFile: string; AAlgo: TChecksumAlgo;
  out AItems: TArray<TChecksumVerifyItem>; const ACancelled: TChecksumCancelled): Boolean;
var
  Lines: TArray<string>;
  Line, Hash, Name, Dir, Path, Actual: string;
  Item: TChecksumVerifyItem;
  List: TList<TChecksumVerifyItem>;
begin
  Result := True;
  Dir := ExtractFilePath(AChecksumFile);
  Lines := TFile.ReadAllLines(AChecksumFile);
  List := TList<TChecksumVerifyItem>.Create;
  try
    for Line in Lines do
    begin
      if not ParseChecksumLine(Line, Hash, Name) then
        Continue;
      if Assigned(ACancelled) and ACancelled() then
        Exit(False);
      Item.RelName := Name;
      Path := TPath.Combine(Dir, StringReplace(Name, '/', '\', [rfReplaceAll]));
      if not TFile.Exists(Path) then
        Item.Status := cvsMissing
      else
        try
          Actual := HashFileHex(Path, AAlgo, ACancelled);
          if Actual = '' then
            Exit(False); // cancelled mid-file
          if SameText(Actual, Hash) then
            Item.Status := cvsOk
          else
            Item.Status := cvsFailed;
        except
          Item.Status := cvsError;
        end;
      List.Add(Item);
    end;
  finally
    AItems := List.ToArray;
    List.Free;
  end;
end;

function ChecksumVerifyStatusText(AStatus: TChecksumVerifyStatus): string;
begin
  case AStatus of
    cvsOk: Result := 'OK';
    cvsFailed: Result := 'FAILED';
    cvsMissing: Result := 'MISSING';
  else
    Result := 'ERROR';
  end;
end;

end.
