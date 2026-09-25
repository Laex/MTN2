unit uFileHistory;

{ Persistent Viewer/Editor file history (FAR Alt+F11): every URI opened with
  F3 / F4 (TDualPanelWindow.OpenDocument) and the mode it was last opened in.
  Newest first, one entry per file (SameVfsUri), capped at cFileHistoryMax.
  Stored in filehistory.json in the config folder: an array of objects
  with "uri" and "mode" ("view" / "edit"), newest first.
  The position inside the file is not kept here -- uFilePositions restores
  it on its own when the file is reopened. }

interface

uses
  System.SysUtils;

const
  cFileHistoryMax = 100;

type
  TFileHistoryEntry = record
    URI: string;
    Edit: Boolean; // last opened with F4 (Editor), else F3 (Viewer)
  end;

/// <summary>Moves AURI to the top (adding it if new) with its latest mode.</summary>
procedure FileHistoryPush(const AURI: string; AEdit: Boolean);
/// <summary>Newest first.</summary>
function FileHistoryGetEntries: TArray<TFileHistoryEntry>;
procedure FileHistoryRemove(const AURI: string);
procedure FileHistoryClear;
/// <summary>Drops the in-memory copy; the next call re-reads the file.</summary>
procedure FileHistoryReload;

implementation

uses
  System.IOUtils, System.JSON, System.Generics.Collections,
  uConfigLocation, uVfsTypes;

const
  cFileName = 'filehistory.json';
  cModeView = 'view';
  cModeEdit = 'edit';

var
  GLoaded: Boolean = False;
  GEntries: TList<TFileHistoryEntry>; // newest first

procedure EnsureLoaded;
var
  Path: string;
  Root: TJSONValue;
  Item: TJSONValue;
  Entry: TFileHistoryEntry;
begin
  if GLoaded then
    Exit;
  GLoaded := True;
  if GEntries = nil then
    GEntries := TList<TFileHistoryEntry>.Create
  else
    GEntries.Clear;

  Path := GetConfigFilePath(cFileName);
  if not TFile.Exists(Path) then
    Exit;
  try
    Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8));
    if Root = nil then
      Exit;
    try
      if not (Root is TJSONArray) then
        Exit;
      for Item in TJSONArray(Root) do
      begin
        if not (Item is TJSONObject) then
          Continue;
        Entry.URI := Trim(TJSONObject(Item).GetValue<string>('uri', ''));
        Entry.Edit := SameText(TJSONObject(Item).GetValue<string>('mode', ''), cModeEdit);
        if (Entry.URI <> '') and (GEntries.Count < cFileHistoryMax) then
          GEntries.Add(Entry);
      end;
    finally
      Root.Free;
    end;
  except
    GEntries.Clear;
  end;
end;

procedure Save;
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  Entry: TFileHistoryEntry;
begin
  Arr := TJSONArray.Create;
  try
    for Entry in GEntries do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('uri', Entry.URI);
      if Entry.Edit then
        Obj.AddPair('mode', cModeEdit)
      else
        Obj.AddPair('mode', cModeView);
      Arr.AddElement(Obj);
    end;
    try
      TFile.WriteAllText(GetConfigFilePath(cFileName), Arr.Format(2), TEncoding.UTF8);
    except
      // History is a convenience: a read-only config folder must not break F3/F4.
    end;
  finally
    Arr.Free;
  end;
end;

function IndexOfUri(const AURI: string): Integer;
var
  I: Integer;
begin
  for I := 0 to GEntries.Count - 1 do
    if SameVfsUri(GEntries[I].URI, AURI) then
      Exit(I);
  Result := -1;
end;

procedure FileHistoryPush(const AURI: string; AEdit: Boolean);
var
  Entry: TFileHistoryEntry;
  I: Integer;
begin
  Entry.URI := Trim(AURI);
  if Entry.URI = '' then
    Exit;
  Entry.Edit := AEdit;
  EnsureLoaded;
  I := IndexOfUri(Entry.URI);
  if I >= 0 then
    GEntries.Delete(I);
  GEntries.Insert(0, Entry);
  while GEntries.Count > cFileHistoryMax do
    GEntries.Delete(GEntries.Count - 1);
  Save;
end;

function FileHistoryGetEntries: TArray<TFileHistoryEntry>;
begin
  EnsureLoaded;
  Result := GEntries.ToArray;
end;

procedure FileHistoryRemove(const AURI: string);
var
  I: Integer;
begin
  EnsureLoaded;
  I := IndexOfUri(AURI);
  if I < 0 then
    Exit;
  GEntries.Delete(I);
  Save;
end;

procedure FileHistoryClear;
begin
  EnsureLoaded;
  GEntries.Clear;
  Save;
end;

procedure FileHistoryReload;
begin
  GLoaded := False;
end;

initialization

finalization
  FreeAndNil(GEntries);

end.
