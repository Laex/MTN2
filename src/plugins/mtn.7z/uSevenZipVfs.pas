unit uSevenZipVfs;

{ 7z:// URI grammar and listing helpers for the native 7-Zip plugin.
  Canonical form: 7z:///<abs-path>!/<inner>  (inner empty = archive root). }

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.DateUtils, System.IOUtils,
  uSevenZipApi, uPluginHostAbi;

function ParseSevenZipUri(const AURI: string; out AArchivePath, AInnerPath: string): Boolean;
function SevenZipListToJson(const AArchivePath, AInnerPath: string;
  out AJson: UTF8String; out ACode: Int64): Boolean;
function SevenZipExistsAt(const AArchivePath, AInnerPath: string;
  out AIsDir: Boolean; out ACode: Int64): Boolean;
function SevenZipReadFile(const AArchivePath, AInnerPath: string; AMaxBytes: Int64;
  out ABytes: TBytes; out ACode: Int64): Boolean;

implementation

/// <summary>Splits the part of a 7z:// URI after the first archive's base
/// path into per-level segments: one entry per further '!/' -- each
/// non-final segment names the file that is itself the next archive to
/// descend into, and the final segment is the inner path within the
/// deepest/current level (possibly '' for that level's root). A URI with a
/// single archive level yields exactly one segment, unchanged from before.</summary>
function SplitSevenZipChainSegments(const ARest: string): TArray<string>;
var
  S, Part: string;
  P, N: Integer;
begin
  SetLength(Result, 0);
  S := ARest;
  N := 0;
  while True do
  begin
    P := Pos('!/', S);
    if P = 0 then
    begin
      Inc(N);
      SetLength(Result, N);
      Result[N - 1] := SevenZipNormInner(S);
      Break;
    end;
    Part := Copy(S, 1, P - 1);
    Inc(N);
    SetLength(Result, N);
    Result[N - 1] := SevenZipNormInner(Part);
    S := Copy(S, P + 2, MaxInt);
  end;
end;

/// <summary>Walks ASegments[0..High-1] as nested-archive entry names,
/// extracting each to a cached temp file and re-opening it, so a chain like
/// "outer.tar.gz!/inner.tar!/" resolves to a real file on disk (the
/// extracted inner.tar) plus the last segment as its inner path -- rather
/// than the flat single-level path SzListDirectory etc. expect.</summary>
function ResolveSevenZipChain(const ABaseArchivePath: string;
  const ASegments: TArray<string>; out AArchivePath, AInnerPath: string): Boolean;
var
  Cur, TempFile, Err: string;
  I: Integer;
begin
  Result := False;
  Cur := ABaseArchivePath;
  for I := 0 to Length(ASegments) - 2 do
  begin
    if ASegments[I] = '' then
      Exit; // can't descend into an unnamed entry
    if not SevenZipResolveNestedArchive(Cur, ASegments[I], TempFile, Err) then
      Exit;
    Cur := TempFile;
  end;
  AArchivePath := Cur;
  if Length(ASegments) = 0 then
    AInnerPath := ''
  else
    AInnerPath := ASegments[High(ASegments)];
  Result := True;
end;

function ParseSevenZipUri(const AURI: string; out AArchivePath, AInnerPath: string): Boolean;
var
  S, Rest, Base: string;
  P: Integer;
  Segments: TArray<string>;
begin
  Result := False;
  AArchivePath := '';
  AInnerPath := '';
  S := Trim(AURI);
  if not S.StartsWith('7z:', True) then
    Exit;
  P := Pos('://', S);
  if P <= 0 then
    Exit;
  Rest := Copy(S, P + 3, MaxInt);
  while (Length(Rest) > 0) and (Rest[1] = '/') do
    Delete(Rest, 1, 1);
  P := Pos('!/', Rest);
  if P <= 0 then
  begin
    Base := StringReplace(Rest, '/', PathDelim, [rfReplaceAll]);
    AArchivePath := ExcludeTrailingPathDelimiter(Base);
    AInnerPath := '';
    Exit(AArchivePath <> '');
  end;
  Base := Copy(Rest, 1, P - 1);
  Base := StringReplace(Base, '/', PathDelim, [rfReplaceAll]);
  Base := ExcludeTrailingPathDelimiter(Base);
  if Base = '' then
    Exit;
  Segments := SplitSevenZipChainSegments(Copy(Rest, P + 2, MaxInt));
  if Length(Segments) <= 1 then
  begin
    AArchivePath := Base;
    if Length(Segments) = 1 then
      AInnerPath := Segments[0];
    Exit(True);
  end;
  Result := ResolveSevenZipChain(Base, Segments, AArchivePath, AInnerPath);
end;

function FirstSegment(const ARest: string; out AName, ATail: string): Boolean;
var
  P: Integer;
begin
  Result := ARest <> '';
  if not Result then
    Exit;
  P := Pos('/', ARest);
  if P = 0 then
  begin
    AName := ARest;
    ATail := '';
  end
  else
  begin
    AName := Copy(ARest, 1, P - 1);
    ATail := Copy(ARest, P + 1, MaxInt);
  end;
end;

function UnixMTime(ADt: TDateTime): Int64;
begin
  if ADt <= 0 then
    Result := 0
  else
    Result := DateTimeToUnix(ADt, False);
end;

function SevenZipListToJson(const AArchivePath, AInnerPath: string;
  out AJson: UTF8String; out ACode: Int64): Boolean;
var
  Items: TArray<T7zItem>;
  Err: string;
  Prefix, Rest, Name, Tail: string;
  Seen: TDictionary<string, Boolean>;
  Arr: TJSONArray;
  Obj: TJSONObject;
  Item: T7zItem;
  IsDir: Boolean;
  Size: Int64;
  MTime: TDateTime;
  Enc: Boolean;
begin
  Result := False;
  AJson := '[]';
  ACode := Int64(verIOError);
  if not SevenZipListArchive(AArchivePath, Items, Err) then
  begin
    if Err = 'Archive not found' then
      ACode := Int64(verNotFound)
    else if Err = 'Encrypted' then
      ACode := Int64(verAccessDenied)
    else if (Err = 'Not a 7z archive') or (Err = 'Not a supported archive') then
      ACode := Int64(verInvalidURI)
    else
      ACode := Int64(verIOError);
    Exit;
  end;

  Prefix := SevenZipNormInner(AInnerPath);
  if Prefix <> '' then
    Prefix := Prefix + '/';
  Seen := TDictionary<string, Boolean>.Create;
  Arr := TJSONArray.Create;
  try
    for Item in Items do
    begin
      if (Item.Path = '') or (Pos('..', Item.Path) > 0) then
        Continue;
      if Prefix = '' then
        Rest := Item.Path
      else if Item.Path.StartsWith(Prefix, True) then
        Rest := Copy(Item.Path, Length(Prefix) + 1, MaxInt)
      else
        Continue;
      if Rest = '' then
        Continue;
      if not FirstSegment(Rest, Name, Tail) then
        Continue;
      if Name = '' then
        Continue;
      IsDir := (Tail <> '') or Item.IsDir;
      if Seen.ContainsKey(LowerCase(Name)) then
        Continue;
      Seen.Add(LowerCase(Name), True);
      if IsDir then
      begin
        Size := 0;
        Enc := False;
        MTime := 0;
      end
      else
      begin
        Size := Item.Size;
        Enc := Item.Encrypted;
        MTime := Item.MTime;
      end;
      Obj := TJSONObject.Create;
      Obj.AddPair('name', Name);
      Obj.AddPair('ext', Copy(TPath.GetExtension(Name), 2, MaxInt));
      Obj.AddPair('size', TJSONNumber.Create(Size));
      Obj.AddPair('isDir', TJSONBool.Create(IsDir));
      Obj.AddPair('isEncrypted', TJSONBool.Create(Enc));
      Obj.AddPair('modified', TJSONNumber.Create(UnixMTime(MTime)));
      Arr.AddElement(Obj);
    end;
    AJson := UTF8String(Arr.ToString);
    ACode := Int64(verOk);
    Result := True;
  finally
    Arr.Free;
    Seen.Free;
  end;
end;

function SevenZipExistsAt(const AArchivePath, AInnerPath: string;
  out AIsDir: Boolean; out ACode: Int64): Boolean;
var
  Items: TArray<T7zItem>;
  Err, Inner, Prefix: string;
  Item: T7zItem;
begin
  Result := False;
  AIsDir := False;
  ACode := Int64(verNotFound);
  Inner := SevenZipNormInner(AInnerPath);
  if not SevenZipListArchive(AArchivePath, Items, Err) then
  begin
    if Err = 'Archive not found' then
      ACode := Int64(verNotFound)
    else if Err = 'Encrypted' then
      ACode := Int64(verAccessDenied)
    else
      ACode := Int64(verIOError);
    Exit;
  end;
  if Inner = '' then
  begin
    AIsDir := True;
    ACode := Int64(verOk);
    Exit(True);
  end;
  Prefix := Inner + '/';
  for Item in Items do
  begin
    if SameText(Item.Path, Inner) then
    begin
      AIsDir := Item.IsDir;
      ACode := Int64(verOk);
      Exit(True);
    end;
    if Item.Path.StartsWith(Prefix, True) then
    begin
      AIsDir := True;
      ACode := Int64(verOk);
      Exit(True);
    end;
  end;
end;

function SevenZipReadFile(const AArchivePath, AInnerPath: string; AMaxBytes: Int64;
  out ABytes: TBytes; out ACode: Int64): Boolean;
var
  Err: string;
  IsDir: Boolean;
  ExistsCode: Int64;
begin
  Result := False;
  SetLength(ABytes, 0);
  if SevenZipExistsAt(AArchivePath, AInnerPath, IsDir, ExistsCode) and IsDir then
  begin
    ACode := Int64(verNotSupported);
    Exit;
  end;
  if not SevenZipExtractFile(AArchivePath, AInnerPath, AMaxBytes, ABytes, Err) then
  begin
    if Err = 'Not found' then
      ACode := Int64(verNotFound)
    else if Err = 'Encrypted' then
      ACode := Int64(verAccessDenied)
    else if Err = 'Too large' then
      ACode := Int64(verNeedsBiggerBuffer)
    else
      ACode := Int64(verIOError);
    Exit;
  end;
  ACode := Int64(verOk);
  Result := True;
end;

end.
