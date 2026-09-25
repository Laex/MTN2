unit uTmpPanelStore;

{ In-memory file-list for the Temporary panel (Far TmpPanel analogue).
  Entries are references to real paths, not copies. }

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.JSON, System.IOUtils,
  System.DateUtils, System.Generics.Collections,
  Winapi.Windows,
  uVfsTypes, uPluginHostAbi;

procedure TmpPanelClear;
function TmpPanelAddFromUri(const AFromURI: string): Int64;
function TmpPanelRemoveFromUri(const AFromURI: string): Int64;
function TmpPanelListJson(out AJson: UTF8String): Int64;
function TmpPanelRootExists(out AIsDirectory: Boolean): Boolean;

implementation

type
  TTmpItem = record
    Path: string;
  end;

var
  GLock: TCriticalSection;
  GItems: TList<TTmpItem>;

function NormPath(const APath: string): string;
begin
  Result := LowerCase(ExcludeTrailingPathDelimiter(
    StringReplace(Trim(APath), '/', PathDelim, [rfReplaceAll])));
end;

function UnixMTime(const APath: string; AIsDir: Boolean): Int64;
var
  Dt: TDateTime;
begin
  Result := 0;
  try
    if AIsDir then
      Dt := TDirectory.GetLastWriteTime(APath)
    else
      Dt := TFile.GetLastWriteTime(APath);
    if Dt > 0 then
      Result := DateTimeToUnix(Dt, False);
  except
    Result := 0;
  end;
end;

procedure TmpPanelClear;
begin
  GLock.Acquire;
  try
    GItems.Clear;
  finally
    GLock.Release;
  end;
end;

function TmpPanelAddFromUri(const AFromURI: string): Int64;
var
  Path: string;
  Item: TTmpItem;
  I: Integer;
  Key: string;
begin
  Path := FileUriToPath(AFromURI);
  if Path = '' then
    Path := Trim(AFromURI);
  Path := ExpandFileName(Path);
  if (Path = '') or not (FileExists(Path) or TDirectory.Exists(Path)) then
    Exit(Int64(verNotFound));
  Key := NormPath(Path);
  GLock.Acquire;
  try
    for I := 0 to GItems.Count - 1 do
      if NormPath(GItems[I].Path) = Key then
        Exit(Int64(verOk));
    Item.Path := Path;
    GItems.Add(Item);
    Result := Int64(verOk);
  finally
    GLock.Release;
  end;
end;

function TmpPanelRemoveFromUri(const AFromURI: string): Int64;
var
  Path: string;
  I: Integer;
  Key: string;
begin
  Path := FileUriToPath(AFromURI);
  if Path = '' then
    Path := Trim(AFromURI);
  Path := ExpandFileName(Path);
  if Path = '' then
    Exit(Int64(verNotFound));
  Key := NormPath(Path);
  GLock.Acquire;
  try
    for I := GItems.Count - 1 downto 0 do
      if NormPath(GItems[I].Path) = Key then
        GItems.Delete(I);
    Result := Int64(verOk);
  finally
    GLock.Release;
  end;
end;

function TmpPanelListJson(out AJson: UTF8String): Int64;
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
  Path, Name: string;
  IsDir, Hidden, ReadOnly, SystemAttr: Boolean;
  Size: Int64;
  Attr: Integer;
begin
  Arr := TJSONArray.Create;
  GLock.Acquire;
  try
    for I := 0 to GItems.Count - 1 do
    begin
      Path := GItems[I].Path;
      if TDirectory.Exists(Path) then
      begin
        IsDir := True;
        Size := 0;
      end
      else if TFile.Exists(Path) then
      begin
        IsDir := False;
        try
          Size := TFile.GetSize(Path);
        except
          Size := 0;
        end;
      end
      else
        Continue;
      Attr := GetFileAttributes(PChar(Path));
      Hidden := (Attr <> Integer($FFFFFFFF)) and ((Attr and FILE_ATTRIBUTE_HIDDEN) <> 0);
      ReadOnly := (Attr <> Integer($FFFFFFFF)) and ((Attr and FILE_ATTRIBUTE_READONLY) <> 0);
      SystemAttr := (Attr <> Integer($FFFFFFFF)) and ((Attr and FILE_ATTRIBUTE_SYSTEM) <> 0);
      Name := TPath.GetFileName(ExcludeTrailingPathDelimiter(Path));
      if Name = '' then
        Name := Path;
      Obj := TJSONObject.Create;
      Obj.AddPair('name', Name);
      Obj.AddPair('ext', Copy(TPath.GetExtension(Name), 2, MaxInt));
      Obj.AddPair('size', TJSONNumber.Create(Size));
      Obj.AddPair('isDir', TJSONBool.Create(IsDir));
      Obj.AddPair('isHidden', TJSONBool.Create(Hidden));
      Obj.AddPair('isReadOnly', TJSONBool.Create(ReadOnly));
      Obj.AddPair('isSystem', TJSONBool.Create(SystemAttr));
      Obj.AddPair('modified', TJSONNumber.Create(UnixMTime(Path, IsDir)));
      Obj.AddPair('targetUri', PathToFileUri(Path));
      Arr.AddElement(Obj);
    end;
    AJson := UTF8String(Arr.ToString);
    Result := Int64(verOk);
  finally
    GLock.Release;
    Arr.Free;
  end;
end;

function TmpPanelRootExists(out AIsDirectory: Boolean): Boolean;
begin
  AIsDirectory := True;
  Result := True;
end;

initialization
  GLock := TCriticalSection.Create;
  GItems := TList<TTmpItem>.Create;

finalization
  FreeAndNil(GItems);
  FreeAndNil(GLock);

end.
