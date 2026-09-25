unit uFolderHistory;

{ Persistent global folder visit history (FAR Alt+F12). Stores VFS URIs. }

interface

uses
  System.SysUtils, System.Classes;

const
  cFolderHistoryMax = 50;

procedure FolderHistoryPush(const AURI: string);
function FolderHistoryCount: Integer;
/// <summary>Newest first.</summary>
function FolderHistoryGetUris: TArray<string>;
procedure FolderHistoryClear;

implementation

uses
  System.IOUtils, System.JSON, System.Generics.Collections,
  uConfigLocation, uVfsTypes;

var
  GLoaded: Boolean = False;
  GUris: TStringList;

const
  cFileName = 'folderhistory.json';

procedure EnsureLoaded;
var
  Path, Content: string;
  Root: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
  Item: TJSONValue;
  U: string;
begin
  if GLoaded then
    Exit;
  GLoaded := True;
  if GUris = nil then
  begin
    GUris := TStringList.Create;
    GUris.CaseSensitive := False;
  end
  else
    GUris.Clear;

  Path := GetConfigFilePath(cFileName);
  if not TFile.Exists(Path) then
    Exit;
  try
    Content := TFile.ReadAllText(Path, TEncoding.UTF8);
    Root := TJSONObject.ParseJSONValue(Content);
    if Root = nil then
      Exit;
    try
      if Root is TJSONArray then
        Arr := TJSONArray(Root)
      else if (Root is TJSONObject) and
              (TJSONObject(Root).Values['uris'] is TJSONArray) then
        Arr := TJSONArray(TJSONObject(Root).Values['uris'])
      else
        Exit;
      for I := 0 to Arr.Count - 1 do
      begin
        Item := Arr.Items[I];
        if Item = nil then
          Continue;
        U := Trim(Item.Value);
        if U <> '' then
          GUris.Add(U);
      end;
    finally
      Root.Free;
    end;
  except
    GUris.Clear;
  end;
end;

procedure SaveLocked;
var
  Path: string;
  Arr: TJSONArray;
  I: Integer;
begin
  if GUris = nil then
    Exit;
  Path := GetConfigFilePath(cFileName);
  Arr := TJSONArray.Create;
  try
    for I := 0 to GUris.Count - 1 do
      Arr.Add(GUris[I]);
    TFile.WriteAllText(Path, Arr.ToJSON, TEncoding.UTF8);
  finally
    Arr.Free;
  end;
end;

procedure FolderHistoryPush(const AURI: string);
var
  U: string;
  I: Integer;
begin
  U := Trim(AURI);
  if U = '' then
    Exit;
  EnsureLoaded;
  // Drop duplicates (compare via SameVfsUri when possible).
  for I := GUris.Count - 1 downto 0 do
    if SameVfsUri(GUris[I], U) then
      GUris.Delete(I);
  GUris.Add(U); // newest at end
  while GUris.Count > cFolderHistoryMax do
    GUris.Delete(0);
  try
    SaveLocked;
  except
  end;
end;

function FolderHistoryCount: Integer;
begin
  EnsureLoaded;
  Result := GUris.Count;
end;

function FolderHistoryGetUris: TArray<string>;
var
  I, N: Integer;
begin
  EnsureLoaded;
  N := GUris.Count;
  SetLength(Result, N);
  // Newest first for the dialog.
  for I := 0 to N - 1 do
    Result[I] := GUris[N - 1 - I];
end;

procedure FolderHistoryClear;
begin
  EnsureLoaded;
  GUris.Clear;
  try
    SaveLocked;
  except
  end;
end;

initialization

finalization
  FreeAndNil(GUris);

end.
