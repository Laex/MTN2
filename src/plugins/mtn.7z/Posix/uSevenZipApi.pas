unit uSevenZipApi;

{ Archive engine of the 7z plugin on POSIX: drives a 7-Zip command line program
  (7zz, 7z, 7za or 7zr) instead of loading a library. The interface matches the
  Windows unit in plugins\mtn.7z\Windows; each build puts exactly one of the two
  folders on its unit search path. }

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.DateUtils, System.IOUtils,
  System.StrUtils;

type
  T7zItem = record
    Index: UInt32;
    Path: string;
    Size: Int64;
    IsDir: Boolean;
    Encrypted: Boolean;
    MTime: TDateTime;
    Attrib: Cardinal;
  end;

/// <summary>AProgramPath is the 7-Zip executable; True when it answers as 7-Zip.</summary>
function SevenZipLoadEngine(const AProgramPath: string): Boolean;
procedure SevenZipUnloadEngine;
function SevenZipEngineLoaded: Boolean;
function SevenZipListArchive(const AArchivePath: string; out AItems: TArray<T7zItem>;
  out AError: string): Boolean;
function SevenZipExtractFile(const AArchivePath, AInnerPath: string; AMaxBytes: Int64;
  out ABytes: TBytes; out AError: string): Boolean;
/// <summary>Unpacks one entry straight into a local file, so its size is not
/// bounded by the plugin buffer. A failed unpack removes the partial file.</summary>
function SevenZipExtractToFile(const AArchivePath, AInnerPath, ADestPath: string;
  out AError: string): Boolean;
function SevenZipCreateSimpleArchive(const AArchivePath, ASourceFile: string;
  out AError: string): Boolean;
function SevenZipAddLocalPath(const AArchivePath, ALocalPath, AInnerPath: string;
  AOverwrite: Boolean; out AError: string): Boolean;
/// <summary>Removes one entry, or a whole folder with its contents, from an
/// existing archive. The archive is rewritten; it stays unchanged on failure.</summary>
function SevenZipDeleteInner(const AArchivePath, AInnerPath: string;
  out AError: string): Boolean;
function SevenZipNormInner(const APath: string): string;
procedure SevenZipSetPassword(const AArchivePath, APassword: string);
procedure SevenZipClearPassword(const AArchivePath: string);
procedure SevenZipClearAllPasswords;
/// <summary>Packing into AArchivePath also encrypts the file names (7z header
/// encryption); it takes effect only while a password is set for the archive.</summary>
procedure SevenZipSetHeaderEncryption(const AArchivePath: string; AEnabled: Boolean);
/// <summary>Compression level (7-Zip -mx: 0 store ... 9 ultra) for entries packed
/// into AArchivePath from now on; a negative level restores the default.</summary>
procedure SevenZipSetCompressionLevel(const AArchivePath: string; ALevel: Integer);
function SevenZipTryGetPassword(const AArchivePath: string; out APassword: string): Boolean;

/// <summary>Extracts AEntryPath from AOuterArchivePath to a cached temp file
/// and returns its path, so the caller can re-open it as an archive in its
/// own right (archive-inside-archive chains, e.g. the .tar inside a .tar.gz).
/// Repeat calls for the same (outer archive, entry) pair reuse the cached
/// file as long as the outer archive's mtime hasn't changed.</summary>
function SevenZipResolveNestedArchive(const AOuterArchivePath, AEntryPath: string;
  out ATempFilePath: string; out AError: string): Boolean;

implementation

uses
  System.Generics.Collections, uPlatformProcess;

var
  GLock: TCriticalSection;
  GProgram: string;
  GPasswords: TDictionary<string, string>;
  GHeaderEncryption: TDictionary<string, Boolean>;
  GCompressionLevels: TDictionary<string, Integer>;
  GNestedCache: TDictionary<string, string>;
  GNestedSeq: Integer;
  GTempSeq: Integer;

function SevenZipNormInner(const APath: string): string;
begin
  Result := StringReplace(Trim(APath), '\', '/', [rfReplaceAll]);
  while (Length(Result) > 0) and (Result[1] = '/') do
    Delete(Result, 1, 1);
  while (Length(Result) > 0) and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

function PasswordKey(const APath: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(Trim(APath));
end;

procedure SevenZipSetPassword(const AArchivePath, APassword: string);
begin
  GLock.Acquire;
  try
    GPasswords.AddOrSetValue(PasswordKey(AArchivePath), APassword);
  finally
    GLock.Release;
  end;
end;

procedure SevenZipClearPassword(const AArchivePath: string);
begin
  GLock.Acquire;
  try
    GPasswords.Remove(PasswordKey(AArchivePath));
  finally
    GLock.Release;
  end;
end;

procedure SevenZipClearAllPasswords;
begin
  GLock.Acquire;
  try
    GPasswords.Clear;
    GHeaderEncryption.Clear;
    GCompressionLevels.Clear;
  finally
    GLock.Release;
  end;
end;

procedure SevenZipSetHeaderEncryption(const AArchivePath: string; AEnabled: Boolean);
begin
  GLock.Acquire;
  try
    if AEnabled then
      GHeaderEncryption.AddOrSetValue(PasswordKey(AArchivePath), True)
    else
      GHeaderEncryption.Remove(PasswordKey(AArchivePath));
  finally
    GLock.Release;
  end;
end;

procedure SevenZipSetCompressionLevel(const AArchivePath: string; ALevel: Integer);
begin
  GLock.Acquire;
  try
    if ALevel > 9 then
      ALevel := 9;
    if ALevel >= 0 then
      GCompressionLevels.AddOrSetValue(PasswordKey(AArchivePath), ALevel)
    else
      GCompressionLevels.Remove(PasswordKey(AArchivePath));
  finally
    GLock.Release;
  end;
end;

function CompressionLevelWanted(const AArchivePath: string): Integer;
begin
  GLock.Acquire;
  try
    if not GCompressionLevels.TryGetValue(PasswordKey(AArchivePath), Result) then
      Result := -1;
  finally
    GLock.Release;
  end;
end;

function HeaderEncryptionWanted(const AArchivePath: string): Boolean;
begin
  GLock.Acquire;
  try
    Result := GHeaderEncryption.ContainsKey(PasswordKey(AArchivePath));
  finally
    GLock.Release;
  end;
end;

function SevenZipTryGetPassword(const AArchivePath: string; out APassword: string): Boolean;
begin
  GLock.Acquire;
  try
    Result := GPasswords.TryGetValue(PasswordKey(AArchivePath), APassword);
  finally
    GLock.Release;
  end;
end;

function EngineProgram: string;
begin
  GLock.Acquire;
  try
    Result := GProgram;
  finally
    GLock.Release;
  end;
end;

function RunEngine(const AArgs: TArray<string>; out AOutput: string;
  out AExitCode: Cardinal): Boolean;
begin
  AOutput := '';
  AExitCode := 0;
  Result := (EngineProgram <> '') and
    (PlatformRunCaptured(EngineProgram, AArgs, '', 0, nil, AOutput, AExitCode) = srOk);
end;

/// <summary>Arguments after the command word: no prompts, no progress, plain
/// names (-spd), and the archive password when one was entered.</summary>
function CommonArgs(const AArchivePath: string; AWildcards: Boolean): TArray<string>;
var
  Password: string;
begin
  Result := ['-y', '-bd'];
  if not AWildcards then
    Result := Result + ['-spd'];
  if SevenZipTryGetPassword(AArchivePath, Password) and (Password <> '') then
    Result := Result + ['-p' + Password];
end;

/// <summary>True when the program's messages ask for a password or reject
/// one. The archive's own path is left out, so a file named after the word
/// does not count.</summary>
function LooksEncrypted(const AOutput, AArchivePath: string): Boolean;
var
  Text: string;
begin
  Text := AOutput.Replace(AArchivePath, '');
  Result := ContainsText(Text, 'password') or ContainsText(Text, 'encrypted') or
    ContainsText(Text, 'Break signaled');
end;

function ParseTime(const AText: string): TDateTime;
var
  Y, M, D, H, N, S: Word;
begin
  Result := 0;
  if Length(AText) >= 19 then
  begin
    Y := StrToIntDef(Copy(AText, 1, 4), 0);
    M := StrToIntDef(Copy(AText, 6, 2), 0);
    D := StrToIntDef(Copy(AText, 9, 2), 0);
    H := StrToIntDef(Copy(AText, 12, 2), 0);
    N := StrToIntDef(Copy(AText, 15, 2), 0);
    S := StrToIntDef(Copy(AText, 18, 2), 0);
    if not TryEncodeDateTime(Y, M, D, H, N, S, 0, Result) then
      Result := 0;
  end;
end;

procedure ParseListing(const AOutput, AArchivePath: string; out AItems: TArray<T7zItem>);
var
  Lines: TArray<string>;
  Line, Key, Value: string;
  Item: T7zItem;
  Have: Boolean;
  P: Integer;
  List: TList<T7zItem>;

  procedure Flush;
  begin
    if Have then
    begin
      Item.Index := List.Count;
      List.Add(Item);
    end;
    Item := Default(T7zItem);
    Have := False;
  end;

begin
  List := TList<T7zItem>.Create;
  try
    Item := Default(T7zItem);
    Have := False;
    Lines := AOutput.Replace(#13, '').Split([#10]);
    for Line in Lines do
    begin
      if Line = '' then
      begin
        Flush;
        Continue;
      end;
      P := Pos(' = ', Line);
      if P = 0 then
        Continue;
      Key := Copy(Line, 1, P - 1);
      Value := Copy(Line, P + 3, MaxInt);
      if Key = 'Path' then
      begin
        Flush;
        Item.Path := SevenZipNormInner(Value);
        Have := True;
      end
      else if not Have then
        Continue
      else if Key = 'Size' then
        Item.Size := StrToInt64Def(Value, 0)
      else if Key = 'Folder' then
        Item.IsDir := Value = '+'
      else if Key = 'Encrypted' then
        Item.Encrypted := Value = '+'
      else if Key = 'Modified' then
        Item.MTime := ParseTime(Value)
      else if Key = 'Attributes' then
      begin
        if (Value <> '') and (Value[1] = 'D') then
          Item.IsDir := True;
      end;
    end;
    Flush;
    AItems := List.ToArray;
  finally
    List.Free;
  end;
  // A single-stream compressor (gzip, bzip2, xz) may carry no file name:
  // show the archive's own name without its outer extension.
  if (Length(AItems) = 1) and (AItems[0].Path = '') then
    AItems[0].Path := TPath.GetFileNameWithoutExtension(AArchivePath);
end;

function SevenZipLoadEngine(const AProgramPath: string): Boolean;
var
  Output: string;
  Code: Cardinal;
begin
  GLock.Acquire;
  try
    if GProgram <> '' then
      Exit(True);
    GProgram := AProgramPath;
  finally
    GLock.Release;
  end;
  Result := RunEngine([], Output, Code) and
    (ContainsText(Output, '7-Zip') or ContainsText(Output, 'p7zip'));
  if not Result then
  begin
    GLock.Acquire;
    try
      GProgram := '';
    finally
      GLock.Release;
    end;
  end;
end;

procedure SevenZipClearNestedCache;
var
  Dir: string;
begin
  GLock.Acquire;
  try
    if Assigned(GNestedCache) then
      GNestedCache.Clear;
  finally
    GLock.Release;
  end;
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-7z-nested');
  if TDirectory.Exists(Dir) then
    try
      TDirectory.Delete(Dir, True);
    except
      // A file still open stays behind in the temp folder.
    end;
end;

procedure SevenZipUnloadEngine;
begin
  GLock.Acquire;
  try
    GProgram := '';
    if Assigned(GPasswords) then
      GPasswords.Clear;
    if Assigned(GHeaderEncryption) then
      GHeaderEncryption.Clear;
    if Assigned(GCompressionLevels) then
      GCompressionLevels.Clear;
  finally
    GLock.Release;
  end;
  SevenZipClearNestedCache;
end;

function SevenZipEngineLoaded: Boolean;
begin
  Result := EngineProgram <> '';
end;

function SevenZipListArchive(const AArchivePath: string; out AItems: TArray<T7zItem>;
  out AError: string): Boolean;
var
  Output: string;
  Code: Cardinal;
begin
  SetLength(AItems, 0);
  AError := '';
  if not SevenZipEngineLoaded then
  begin
    AError := '7-Zip is not available';
    Exit(False);
  end;
  if not FileExists(AArchivePath) then
  begin
    AError := 'Archive not found';
    Exit(False);
  end;
  Result := RunEngine(['l', '-slt', '-ba'] + CommonArgs(AArchivePath, False) + ['--', AArchivePath],
    Output, Code) and (Code <= 1);
  if not Result then
  begin
    if LooksEncrypted(Output, AArchivePath) then
      AError := 'Encrypted'
    else
      AError := 'Not a supported archive';
    Exit;
  end;
  ParseListing(Output, AArchivePath, AItems);
end;

function NewTempDir: string;
begin
  GLock.Acquire;
  try
    Inc(GTempSeq);
    Result := TPath.Combine(TPath.GetTempPath,
      Format('mtn2-7z-%d-%d', [TThread.CurrentThread.ThreadID, GTempSeq]));
  finally
    GLock.Release;
  end;
  TDirectory.CreateDirectory(Result);
end;

procedure DropTempDir(const ADir: string);
begin
  try
    TDirectory.Delete(ADir, True);
  except
    // Best effort: a leftover temp folder is harmless.
  end;
end;

function FindFile(const AItems: TArray<T7zItem>; const AWant: string; out AItem: T7zItem): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(AItems) do
    if (not AItems[I].IsDir) and (AItems[I].Path = AWant) then
    begin
      AItem := AItems[I];
      Exit(True);
    end;
  Result := False;
end;

/// <summary>Unpacks one file entry into a fresh temp folder; AFile receives
/// its path, ADir the folder to remove afterwards.</summary>
function UnpackEntry(const AArchivePath, AWant: string; out ADir, AFile, AError: string): Boolean;
var
  Output: string;
  Code: Cardinal;
begin
  ADir := NewTempDir;
  AFile := TPath.Combine(ADir, AWant.Replace('/', PathDelim));
  Result := RunEngine(['x'] + CommonArgs(AArchivePath, False) + ['-o' + ADir, '--', AArchivePath, AWant],
    Output, Code) and (Code <= 1) and FileExists(AFile);
  if not Result then
  begin
    if LooksEncrypted(Output, AArchivePath) then
      AError := 'Encrypted'
    else
      AError := 'Extract failed';
    DropTempDir(ADir);
    ADir := '';
  end;
end;

function SevenZipExtractFile(const AArchivePath, AInnerPath: string; AMaxBytes: Int64;
  out ABytes: TBytes; out AError: string): Boolean;
var
  Items: TArray<T7zItem>;
  Item: T7zItem;
  Want, Dir, FileName, Output: string;
  Code: Cardinal;
begin
  Result := False;
  SetLength(ABytes, 0);
  AError := '';
  Want := SevenZipNormInner(AInnerPath);
  if Want = '' then
  begin
    AError := 'Empty inner path';
    Exit;
  end;
  if not SevenZipListArchive(AArchivePath, Items, AError) then
    Exit;
  if not FindFile(Items, Want, Item) then
  begin
    AError := 'Not found';
    Exit;
  end;
  if (AMaxBytes > 0) and (Item.Size > AMaxBytes) then
  begin
    // An encrypted entry that does not fit is still tested, so a wrong
    // password is reported as such rather than as a size problem.
    if Item.Encrypted and (not RunEngine(['t'] + CommonArgs(AArchivePath, False) +
         ['--', AArchivePath, Want], Output, Code) or (Code > 1)) then
      AError := 'Encrypted'
    else
      AError := 'Too large';
    Exit;
  end;
  if not UnpackEntry(AArchivePath, Want, Dir, FileName, AError) then
    Exit;
  try
    ABytes := TFile.ReadAllBytes(FileName);
    Result := True;
  finally
    DropTempDir(Dir);
  end;
end;

function SevenZipExtractToFile(const AArchivePath, AInnerPath, ADestPath: string;
  out AError: string): Boolean;
var
  Items: TArray<T7zItem>;
  Item: T7zItem;
  Want, Dir, FileName: string;
begin
  Result := False;
  AError := '';
  Want := SevenZipNormInner(AInnerPath);
  if Want = '' then
  begin
    AError := 'Empty inner path';
    Exit;
  end;
  if not SevenZipListArchive(AArchivePath, Items, AError) then
    Exit;
  if not FindFile(Items, Want, Item) then
  begin
    AError := 'Not found';
    Exit;
  end;
  if not UnpackEntry(AArchivePath, Want, Dir, FileName, AError) then
    Exit;
  try
    try
      if ExtractFilePath(ADestPath) <> '' then
        TDirectory.CreateDirectory(ExtractFilePath(ADestPath));
      TFile.Copy(FileName, ADestPath, True);
      Result := True;
    except
      on E: Exception do
      begin
        AError := E.Message;
        DeleteFile(ADestPath);
      end;
    end;
  finally
    DropTempDir(Dir);
  end;
end;

function SevenZipCreateSimpleArchive(const AArchivePath, ASourceFile: string;
  out AError: string): Boolean;
begin
  Result := SevenZipAddLocalPath(AArchivePath, ASourceFile,
    ExtractFileName(ASourceFile), True, AError);
end;

function SevenZipResolveNestedArchive(const AOuterArchivePath, AEntryPath: string;
  out ATempFilePath: string; out AError: string): Boolean;
var
  Want, Key, Dir, FileName, Cached: string;
  OuterStamp: TDateTime;
  Items: TArray<T7zItem>;
  Item: T7zItem;
  Data: TBytes;
begin
  Result := False;
  AError := '';
  ATempFilePath := '';
  Want := SevenZipNormInner(AEntryPath);
  if Want = '' then
  begin
    AError := 'Empty inner path';
    Exit;
  end;
  OuterStamp := 0;
  if FileExists(AOuterArchivePath) then
    OuterStamp := TFile.GetLastWriteTime(AOuterArchivePath);
  Key := AOuterArchivePath + '|' + Want + '|' + FormatDateTime('yyyymmddhhnnsszzz', OuterStamp);

  GLock.Acquire;
  try
    if GNestedCache.TryGetValue(Key, Cached) and FileExists(Cached) then
    begin
      ATempFilePath := Cached;
      Exit(True);
    end;
  finally
    GLock.Release;
  end;

  if not SevenZipListArchive(AOuterArchivePath, Items, AError) then
    Exit;
  if not FindFile(Items, Want, Item) then
  begin
    AError := 'Not found';
    Exit;
  end;
  if not SevenZipExtractFile(AOuterArchivePath, Want, Item.Size + 4096, Data, AError) then
    Exit;

  GLock.Acquire;
  try
    Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-7z-nested');
    TDirectory.CreateDirectory(Dir);
    Inc(GNestedSeq);
    FileName := Format('n%.6d_%s', [GNestedSeq, ExtractFileName(Want)]);
    if ExtractFileName(Want) = '' then
      FileName := Format('n%.6d.bin', [GNestedSeq]);
    Cached := TPath.Combine(Dir, FileName);
    TFile.WriteAllBytes(Cached, Data);
    GNestedCache.AddOrSetValue(Key, Cached);
  finally
    GLock.Release;
  end;
  ATempFilePath := Cached;
  Result := True;
end;

function SevenZipAddLocalPath(const AArchivePath, ALocalPath, AInnerPath: string;
  AOverwrite: Boolean; out AError: string): Boolean;
var
  Items: TArray<T7zItem>;
  Item: T7zItem;
  Want, Stage, Target, Dummy, Output, Password: string;
  Code: Cardinal;
  Args: TArray<string>;
begin
  Result := False;
  AError := '';
  Want := SevenZipNormInner(AInnerPath);
  if (Want = '') or not (FileExists(ALocalPath) or DirectoryExists(ALocalPath)) then
  begin
    AError := 'Nothing to pack';
    Exit;
  end;
  if not SevenZipEngineLoaded then
  begin
    AError := '7-Zip is not available';
    Exit;
  end;
  if (not AOverwrite) and FileExists(AArchivePath) and
     SevenZipListArchive(AArchivePath, Items, Dummy) then
    for Item in Items do
      if (Item.Path = Want) or Item.Path.StartsWith(Want + '/') then
      begin
        AError := 'Already exists';
        Exit;
      end;

  // The program stores the paths it is given below the folder named before
  // the wildcard, so the inner path is built as a real tree to pack from.
  Stage := NewTempDir;
  try
    Target := TPath.Combine(Stage, Want.Replace('/', PathDelim));
    try
      TDirectory.CreateDirectory(ExtractFilePath(Target));
      if DirectoryExists(ALocalPath) then
        TDirectory.Copy(ALocalPath, Target)
      else
        TFile.Copy(ALocalPath, Target, True);
    except
      on E: Exception do
      begin
        AError := 'Cannot read source: ' + E.Message;
        Exit;
      end;
    end;
    Args := ['a'] + CommonArgs(AArchivePath, True);
    if SameText(ExtractFileExt(AArchivePath), '.7z') then
    begin
      Args := Args + ['-t7z'];
      if SevenZipTryGetPassword(AArchivePath, Password) and (Password <> '') and
         HeaderEncryptionWanted(AArchivePath) then
        Args := Args + ['-mhe=on'];
      if CompressionLevelWanted(AArchivePath) >= 0 then
        Args := Args + ['-mx=' + IntToStr(CompressionLevelWanted(AArchivePath))];
    end;
    Args := Args + ['--', AArchivePath, IncludeTrailingPathDelimiter(Stage) + '*'];
    if not RunEngine(Args, Output, Code) or (Code > 1) then
    begin
      if LooksEncrypted(Output, AArchivePath) then
        AError := 'Encrypted'
      else
        AError := 'Cannot write archive';
      Exit;
    end;
    Result := True;
  finally
    DropTempDir(Stage);
  end;
end;

function SevenZipDeleteInner(const AArchivePath, AInnerPath: string;
  out AError: string): Boolean;
var
  Items: TArray<T7zItem>;
  Item: T7zItem;
  Want, Dummy, Output: string;
  Code: Cardinal;
  Found: Boolean;
begin
  Result := False;
  AError := '';
  Want := SevenZipNormInner(AInnerPath);
  if (Want = '') or not FileExists(AArchivePath) then
  begin
    AError := 'Not found';
    Exit;
  end;
  if not SevenZipEngineLoaded then
  begin
    AError := '7-Zip is not available';
    Exit;
  end;
  Found := False;
  if SevenZipListArchive(AArchivePath, Items, Dummy) then
    for Item in Items do
      if (Item.Path = Want) or Item.Path.StartsWith(Want + '/') then
      begin
        Found := True;
        Break;
      end;
  if not Found then
  begin
    AError := 'Not found';
    Exit;
  end;
  if not RunEngine(['d'] + CommonArgs(AArchivePath, True) +
       ['--', AArchivePath, Want, Want + '/*'], Output, Code) or (Code > 1) then
  begin
    if LooksEncrypted(Output, AArchivePath) then
      AError := 'Encrypted'
    else
      AError := 'Cannot write archive';
    Exit;
  end;
  Result := True;
end;

initialization
  GLock := TCriticalSection.Create;
  GPasswords := TDictionary<string, string>.Create;
  GHeaderEncryption := TDictionary<string, Boolean>.Create;
  GCompressionLevels := TDictionary<string, Integer>.Create;
  GNestedCache := TDictionary<string, string>.Create;

finalization
  SevenZipUnloadEngine;
  FreeAndNil(GPasswords);
  FreeAndNil(GHeaderEncryption);
  FreeAndNil(GCompressionLevels);
  FreeAndNil(GNestedCache);
  FreeAndNil(GLock);

end.
