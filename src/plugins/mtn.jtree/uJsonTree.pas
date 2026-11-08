unit uJsonTree;

{ A JSON or YAML file as a tree of folders: objects and arrays are folders, scalars are
  files. Address:  jtree:///<abs-path>!/<key>/<key>/...
  A key is one segment: "/" is written %2F and "%" is %25. Array items are named by their
  index, zero-padded to the width of the last index so the names sort in order. }

interface

type
  TJtResult = (jrOk, jrNotFound, jrError);

  TJtEntry = record
    Name: string;
    IsDir: Boolean;
    Kind: string;      // object, array, string, number, boolean, null
    Preview: string;   // the value of a scalar, "{3}" / "[3]" for a folder
    Size: Int64;       // length of the text of a scalar
  end;
  TJtEntries = TArray<TJtEntry>;

function JtEncode(const AText: string): string;
function JtDecode(const AText: string): string;
/// <summary>Splits an address into the file path and the keys below it.</summary>
function ParseTreeUri(const AUri: string; out AFilePath: string; out APath: TArray<string>): Boolean;
function TreeUri(const AFilePath: string; const APath: TArray<string>): string;

/// <summary>The children of the folder at APath.</summary>
function TreeList(const AFile: string; const APath: TArray<string>; out AEntries: TJtEntries;
  out AError: string): TJtResult;
/// <summary>What is at APath: AIsDir tells a folder from a scalar.</summary>
function TreeStat(const AFile: string; const APath: TArray<string>; out AIsDir: Boolean;
  out AError: string): TJtResult;
/// <summary>The text of a scalar, or the formatted JSON of a folder.</summary>
function TreeText(const AFile: string; const APath: TArray<string>; out AText: string;
  out AError: string): TJtResult;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.SyncObjs, System.StrUtils, System.Math, System.Generics.Collections,
  uPlatformPaths, uYamlLite;

const
  // The parsed tree takes several times the file size in memory.
  cMaxFileBytes = 200 * 1024 * 1024;

var
  GLock: TCriticalSection;
  GCacheFile: string;
  GCacheStamp: TDateTime;
  GCacheSize: Int64;
  GCacheRoot: TJSONValue;
  GCacheError: string;

function JtEncode(const AText: string): string;
begin
  Result := AText.Replace('%', '%25').Replace('/', '%2F');
end;

function JtDecode(const AText: string): string;
var
  I: Integer;
  Code: string;
begin
  Result := '';
  I := 1;
  while I <= Length(AText) do
  begin
    Code := Copy(AText, I, 3);
    if (AText[I] = '%') and SameText(Code, '%2F') then
    begin
      Result := Result + '/';
      Inc(I, 3);
    end
    else if (AText[I] = '%') and (Code = '%25') then
    begin
      Result := Result + '%';
      Inc(I, 3);
    end
    else
    begin
      Result := Result + AText[I];
      Inc(I);
    end;
  end;
end;

function ParseTreeUri(const AUri: string; out AFilePath: string; out APath: TArray<string>): Boolean;
var
  S, Rest, Inner, Seg: string;
  P: Integer;
begin
  Result := False;
  AFilePath := '';
  APath := nil;
  S := Trim(AUri);
  if not S.StartsWith('jtree:', True) then
    Exit;
  P := Pos('://', S);
  if P <= 0 then
    Exit;
  Rest := Copy(S, P + 3, MaxInt);
  while (Length(Rest) > 0) and (Rest[1] = '/') do
    Delete(Rest, 1, 1);
  // The slash after the authority belongs to a POSIX path; a Windows path starts at its drive letter.
  if PlatformPosixPaths then
    Rest := '/' + Rest;
  P := Pos('!/', Rest);
  if P > 0 then
  begin
    Inner := Copy(Rest, P + 2, MaxInt);
    Rest := Copy(Rest, 1, P - 1);
  end
  else
    Inner := '';
  AFilePath := ExcludeTrailingPathDelimiter(StringReplace(Rest, '/', PathDelim, [rfReplaceAll]));
  if AFilePath = '' then
    Exit;
  for Seg in Inner.Split(['/']) do
    if Seg <> '' then
      APath := APath + [JtDecode(Seg)];
  Result := True;
end;

function TreeUri(const AFilePath: string; const APath: TArray<string>): string;
var
  Seg, Path: string;
begin
  Path := StringReplace(AFilePath, PathDelim, '/', [rfReplaceAll]);
  if (Path = '') or (Path[1] <> '/') then
    Path := '/' + Path;
  Result := 'jtree://' + Path + '!/';
  for Seg in APath do
    Result := Result + JtEncode(Seg) + '/';
  if Length(APath) > 0 then
    SetLength(Result, Length(Result) - 1);
end;

function IsYamlFile(const AFile: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFile));
  Result := (Ext = '.yaml') or (Ext = '.yml');
end;

// The cached tree of the file, parsed again when the file changed. Call under GLock.
function LoadRoot(const AFile: string; out AError: string): TJSONValue;
var
  Stamp: TDateTime;
  Size: Int64;
  Text: string;
begin
  AError := '';
  if not TFile.Exists(AFile) then
  begin
    AError := 'File not found';
    Exit(nil);
  end;
  Stamp := TFile.GetLastWriteTime(AFile);
  Size := TFile.GetSize(AFile);
  if (AFile = GCacheFile) and (Stamp = GCacheStamp) and (Size = GCacheSize) then
  begin
    AError := GCacheError;
    Exit(GCacheRoot);
  end;
  FreeAndNil(GCacheRoot);
  GCacheError := '';
  try
    if Size > cMaxFileBytes then
      raise Exception.CreateFmt('The file is too large for the tree (over %d MB)',
        [cMaxFileBytes div (1024 * 1024)]);
    Text := TFile.ReadAllText(AFile, TEncoding.UTF8);
    if IsYamlFile(AFile) then
      GCacheRoot := ParseYaml(Text)
    else
    begin
      GCacheRoot := TJSONObject.ParseJSONValue(Text);
      if GCacheRoot = nil then
        GCacheError := 'Not valid JSON';
    end;
  except
    on E: Exception do
    begin
      FreeAndNil(GCacheRoot);
      GCacheError := E.Message;
    end;
  end;
  GCacheFile := AFile;
  GCacheStamp := Stamp;
  GCacheSize := Size;
  AError := GCacheError;
  Result := GCacheRoot;
end;

function IndexWidth(ACount: Integer): Integer;
begin
  Result := Length(IntToStr(Max(ACount - 1, 0)));
end;

function Child(ANode: TJSONValue; const AKey: string): TJSONValue;
var
  I, N: Integer;
  Arr: TJSONArray;
begin
  Result := nil;
  if ANode is TJSONObject then
  begin
    for I := 0 to TJSONObject(ANode).Count - 1 do
      if TJSONObject(ANode).Pairs[I].JsonString.Value = AKey then
        Exit(TJSONObject(ANode).Pairs[I].JsonValue);
  end
  else if ANode is TJSONArray then
  begin
    Arr := TJSONArray(ANode);
    if TryStrToInt(AKey, N) and (N >= 0) and (N < Arr.Count) then
      Result := Arr.Items[N];
  end;
end;

function Resolve(ARoot: TJSONValue; const APath: TArray<string>): TJSONValue;
var
  Key: string;
begin
  Result := ARoot;
  for Key in APath do
  begin
    Result := Child(Result, Key);
    if Result = nil then
      Exit;
  end;
end;

function KindOf(ANode: TJSONValue): string;
begin
  if ANode is TJSONObject then
    Result := 'object'
  else if ANode is TJSONArray then
    Result := 'array'
  else if ANode is TJSONNumber then
    Result := 'number'
  else if ANode is TJSONBool then
    Result := 'boolean'
  else if ANode is TJSONNull then
    Result := 'null'
  else
    Result := 'string';
end;

function ScalarText(ANode: TJSONValue): string;
begin
  if ANode is TJSONString then
    Result := TJSONString(ANode).Value
  else if ANode is TJSONNumber then
    Result := TJSONNumber(ANode).Value
  else if ANode is TJSONNull then
    Result := 'null'
  else if ANode is TJSONBool then
    Result := IfThen(TJSONBool(ANode).AsBoolean, 'true', 'false')
  else
    Result := ANode.ToString;
end;

function EntryOf(const AName: string; ANode: TJSONValue): TJtEntry;
var
  Text: string;
  P: Integer;
begin
  Result := Default(TJtEntry);
  Result.Name := JtEncode(AName);
  Result.Kind := KindOf(ANode);
  if ANode is TJSONObject then
  begin
    Result.IsDir := True;
    Result.Preview := '{' + IntToStr(TJSONObject(ANode).Count) + '}';
  end
  else if ANode is TJSONArray then
  begin
    Result.IsDir := True;
    Result.Preview := '[' + IntToStr(TJSONArray(ANode).Count) + ']';
  end
  else
  begin
    Text := ScalarText(ANode);
    Result.Size := Length(TEncoding.UTF8.GetBytes(Text));
    P := Pos(#10, Text);
    if P > 0 then
      Text := Copy(Text, 1, P - 1) + ' ...';
    if Length(Text) > 120 then
      Text := Copy(Text, 1, 117) + '...';
    Result.Preview := Text;
  end;
end;

function Fetch(const AFile: string; const APath: TArray<string>; out ANode: TJSONValue;
  out AError: string): TJtResult;
var
  Root: TJSONValue;
begin
  ANode := nil;
  Root := LoadRoot(AFile, AError);
  if Root = nil then
  begin
    if AError = 'File not found' then
      Exit(jrNotFound);
    if AError = '' then
      AError := 'Cannot read the file';
    Exit(jrError);
  end;
  ANode := Resolve(Root, APath);
  if ANode = nil then
  begin
    AError := 'Not found';
    Exit(jrNotFound);
  end;
  Result := jrOk;
end;

function TreeList(const AFile: string; const APath: TArray<string>; out AEntries: TJtEntries;
  out AError: string): TJtResult;
var
  Node: TJSONValue;
  I, W: Integer;
begin
  AEntries := nil;
  GLock.Enter;
  try
    Result := Fetch(AFile, APath, Node, AError);
    if Result <> jrOk then
      Exit;
    if Node is TJSONObject then
    begin
      SetLength(AEntries, TJSONObject(Node).Count);
      for I := 0 to High(AEntries) do
        AEntries[I] := EntryOf(TJSONObject(Node).Pairs[I].JsonString.Value,
          TJSONObject(Node).Pairs[I].JsonValue);
    end
    else if Node is TJSONArray then
    begin
      W := IndexWidth(TJSONArray(Node).Count);
      SetLength(AEntries, TJSONArray(Node).Count);
      for I := 0 to High(AEntries) do
        AEntries[I] := EntryOf(Format('%.*d', [W, I]), TJSONArray(Node).Items[I]);
    end
    else
    begin
      AError := 'Not a folder';
      Result := jrError;
    end;
  finally
    GLock.Leave;
  end;
end;

function TreeStat(const AFile: string; const APath: TArray<string>; out AIsDir: Boolean;
  out AError: string): TJtResult;
var
  Node: TJSONValue;
begin
  AIsDir := False;
  GLock.Enter;
  try
    Result := Fetch(AFile, APath, Node, AError);
    if Result = jrOk then
      AIsDir := (Node is TJSONObject) or (Node is TJSONArray);
  finally
    GLock.Leave;
  end;
end;

function TreeText(const AFile: string; const APath: TArray<string>; out AText: string;
  out AError: string): TJtResult;
var
  Node: TJSONValue;
begin
  AText := '';
  GLock.Enter;
  try
    Result := Fetch(AFile, APath, Node, AError);
    if Result <> jrOk then
      Exit;
    if (Node is TJSONObject) or (Node is TJSONArray) then
      AText := Node.Format(2)
    else
      AText := ScalarText(Node);
  finally
    GLock.Leave;
  end;
end;

initialization
  GLock := TCriticalSection.Create;

finalization
  FreeAndNil(GCacheRoot);
  FreeAndNil(GLock);

end.
