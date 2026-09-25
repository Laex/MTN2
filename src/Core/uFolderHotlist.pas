unit uFolderHotlist;

{ Persistent, user-managed directory bookmarks (TC Ctrl+D / FAR Alt+F10 style).
  Unlike uFolderHistory (auto-pushed, unnamed, capped, newest-first), entries
  here are explicit add/remove/rename only, named, and never auto-evicted. }

interface

uses
  System.SysUtils, System.Classes;

type
  TFolderHotlistEntry = record
    Name: string;
    URI: string;
    /// <summary>0 = none; 1..9 = Ctrl+1..Ctrl+9; 10 = Ctrl+0.</summary>
    HotKey: Integer;
  end;

procedure FolderHotlistAdd(const AName, AURI: string);
procedure FolderHotlistRemove(AIndex: Integer);
procedure FolderHotlistRename(AIndex: Integer; const ANewName: string);
/// <summary>Assigns AHotKey (1..10, see TFolderHotlistEntry.HotKey) to entry
/// AIndex, stealing it from whichever other entry currently holds it —
/// each hotkey maps to at most one entry. AHotKey = 0 clears AIndex's own
/// hotkey without assigning it elsewhere (toggle-off).</summary>
procedure FolderHotlistSetHotKey(AIndex, AHotKey: Integer);
/// <summary>Index of the entry bound to AHotKey (1..10), or -1 if none.</summary>
function FolderHotlistFindByHotKey(AHotKey: Integer): Integer;
function FolderHotlistGetEntries: TArray<TFolderHotlistEntry>;
procedure FolderHotlistClear;
/// <summary>Display label for AHotKey (1..10): 'Ctrl+1'..'Ctrl+9', 'Ctrl+0'; '' for 0.</summary>
function FolderHotlistKeyLabel(AHotKey: Integer): string;
/// <summary>Maps the raw VK code (Word) of a main-row '0'..'9' key to its
/// HotKey value (1..9, or 10 for '0', matching the 1-9-then-0 order on a
/// physical keyboard row); 0 for anything else. Takes AKey rather than
/// AKeyChar: Ctrl+digit has no ASCII control-code to reverse-map, so
/// AKeyChar is typically #0 for it (unlike Ctrl+letter, which reverse-maps
/// to its own letter) — callers gating on Ctrl+1..Ctrl+0 must check AKey.</summary>
function FolderHotlistKeyFromVKey(AKey: Word): Integer;
/// <summary>Index of the entry whose URI matches AUri (SameVfsUri-normalized),
/// or -1 if none.</summary>
function FolderHotlistFindByUri(const AUri: string): Integer;
/// <summary>Remove/rename/set-hotkey by URI rather than raw storage index —
/// safe to call with an entry taken from FolderHotlistGetEntries's result,
/// which is sorted by hotkey and so no longer matches storage order.</summary>
procedure FolderHotlistRemoveByUri(const AUri: string);
procedure FolderHotlistRenameByUri(const AUri, ANewName: string);
procedure FolderHotlistSetHotKeyByUri(const AUri: string; AHotKey: Integer);

implementation

uses
  System.IOUtils, System.JSON, System.Generics.Collections, System.Generics.Defaults,
  uConfigLocation, uVfsTypes;

var
  GLoaded: Boolean = False;
  GEntries: TList<TFolderHotlistEntry>;

const
  cFileName = 'folderhotlist.json';

procedure EnsureLoaded;
var
  Path, Content: string;
  Root: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
  Item: TJSONValue;
  Obj: TJSONObject;
  Entry: TFolderHotlistEntry;
  NameVal, UriVal: string;
  HotKeyVal: Integer;
begin
  if GLoaded then
    Exit;
  GLoaded := True;
  if GEntries = nil then
    GEntries := TList<TFolderHotlistEntry>.Create
  else
    GEntries.Clear;

  Path := GetConfigFilePath(cFileName);
  if not TFile.Exists(Path) then
    Exit;
  try
    Content := TFile.ReadAllText(Path, TEncoding.UTF8);
    Root := TJSONObject.ParseJSONValue(Content);
    if Root = nil then
      Exit;
    try
      if not (Root is TJSONArray) then
        Exit;
      Arr := TJSONArray(Root);
      for I := 0 to Arr.Count - 1 do
      begin
        Item := Arr.Items[I];
        if not (Item is TJSONObject) then
          Continue;
        Obj := TJSONObject(Item);
        if not Obj.TryGetValue<string>('uri', UriVal) then
          Continue;
        UriVal := Trim(UriVal);
        if UriVal = '' then
          Continue;
        if not Obj.TryGetValue<string>('name', NameVal) then
          NameVal := '';
        if not Obj.TryGetValue<Integer>('hotkey', HotKeyVal) then
          HotKeyVal := 0;
        if (HotKeyVal < 0) or (HotKeyVal > 10) then
          HotKeyVal := 0;
        Entry.Name := NameVal;
        Entry.URI := UriVal;
        Entry.HotKey := HotKeyVal;
        GEntries.Add(Entry);
      end;
      // Defend against a hand-edited file assigning the same hotkey twice —
      // each hotkey must map to at most one entry; keep the first, clear the rest.
      for I := 1 to GEntries.Count - 1 do
      begin
        Entry := GEntries[I];
        if (Entry.HotKey <> 0) and (FolderHotlistFindByHotKey(Entry.HotKey) < I) then
        begin
          Entry.HotKey := 0;
          GEntries[I] := Entry;
        end;
      end;
    finally
      Root.Free;
    end;
  except
    GEntries.Clear;
  end;
end;

procedure SaveLocked;
var
  Path: string;
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
begin
  if GEntries = nil then
    Exit;
  Path := GetConfigFilePath(cFileName);
  Arr := TJSONArray.Create;
  try
    for I := 0 to GEntries.Count - 1 do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('name', GEntries[I].Name);
      Obj.AddPair('uri', GEntries[I].URI);
      if GEntries[I].HotKey <> 0 then
        Obj.AddPair('hotkey', TJSONNumber.Create(GEntries[I].HotKey));
      Arr.AddElement(Obj);
    end;
    TFile.WriteAllText(Path, Arr.ToJSON, TEncoding.UTF8);
  finally
    Arr.Free;
  end;
end;

procedure FolderHotlistAdd(const AName, AURI: string);
var
  U, N: string;
  I: Integer;
  Entry: TFolderHotlistEntry;
begin
  U := Trim(AURI);
  if U = '' then
    Exit;
  N := Trim(AName);
  EnsureLoaded;
  // Replace an existing entry for the same directory rather than duplicating.
  for I := GEntries.Count - 1 downto 0 do
    if SameVfsUri(GEntries[I].URI, U) then
      GEntries.Delete(I);
  Entry.Name := N;
  Entry.URI := U;
  Entry.HotKey := 0;
  GEntries.Add(Entry);
  try
    SaveLocked;
  except
  end;
end;

procedure FolderHotlistRemove(AIndex: Integer);
begin
  EnsureLoaded;
  if (AIndex < 0) or (AIndex >= GEntries.Count) then
    Exit;
  GEntries.Delete(AIndex);
  try
    SaveLocked;
  except
  end;
end;

procedure FolderHotlistRename(AIndex: Integer; const ANewName: string);
var
  Entry: TFolderHotlistEntry;
begin
  EnsureLoaded;
  if (AIndex < 0) or (AIndex >= GEntries.Count) then
    Exit;
  Entry := GEntries[AIndex];
  Entry.Name := Trim(ANewName);
  GEntries[AIndex] := Entry;
  try
    SaveLocked;
  except
  end;
end;

function FolderHotlistFindByHotKey(AHotKey: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  if AHotKey = 0 then
    Exit;
  EnsureLoaded;
  for I := 0 to GEntries.Count - 1 do
    if GEntries[I].HotKey = AHotKey then
      Exit(I);
end;

procedure FolderHotlistSetHotKey(AIndex, AHotKey: Integer);
var
  Entry: TFolderHotlistEntry;
  Prev: Integer;
begin
  EnsureLoaded;
  if (AIndex < 0) or (AIndex >= GEntries.Count) then
    Exit;
  if (AHotKey < 0) or (AHotKey > 10) then
    Exit;
  if AHotKey <> 0 then
  begin
    // Each hotkey maps to at most one entry — steal it from whoever had it.
    Prev := FolderHotlistFindByHotKey(AHotKey);
    if (Prev >= 0) and (Prev <> AIndex) then
    begin
      Entry := GEntries[Prev];
      Entry.HotKey := 0;
      GEntries[Prev] := Entry;
    end;
  end;
  Entry := GEntries[AIndex];
  Entry.HotKey := AHotKey;
  GEntries[AIndex] := Entry;
  try
    SaveLocked;
  except
  end;
end;

function FolderHotlistFindByUri(const AUri: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  if AUri = '' then
    Exit;
  EnsureLoaded;
  for I := 0 to GEntries.Count - 1 do
    if SameVfsUri(GEntries[I].URI, AUri) then
      Exit(I);
end;

procedure FolderHotlistRemoveByUri(const AUri: string);
begin
  FolderHotlistRemove(FolderHotlistFindByUri(AUri));
end;

procedure FolderHotlistRenameByUri(const AUri, ANewName: string);
begin
  FolderHotlistRename(FolderHotlistFindByUri(AUri), ANewName);
end;

procedure FolderHotlistSetHotKeyByUri(const AUri: string; AHotKey: Integer);
begin
  FolderHotlistSetHotKey(FolderHotlistFindByUri(AUri), AHotKey);
end;

function CompareHotlistEntries(const A, B: TFolderHotlistEntry): Integer;
var
  KeyA, KeyB: Integer;
begin
  // Assigned hotkeys (1..10) sort first in that order; unassigned (0) sort
  // after, alphabetically by name — so the list mirrors the Ctrl+1..Ctrl+0
  // jump order the user just set up in the dialog.
  KeyA := A.HotKey;
  if KeyA = 0 then
    KeyA := MaxInt;
  KeyB := B.HotKey;
  if KeyB = 0 then
    KeyB := MaxInt;
  Result := KeyA - KeyB;
  if Result = 0 then
    Result := CompareText(A.Name, B.Name);
end;

function FolderHotlistGetEntries: TArray<TFolderHotlistEntry>;
var
  I: Integer;
begin
  EnsureLoaded;
  SetLength(Result, GEntries.Count);
  for I := 0 to GEntries.Count - 1 do
    Result[I] := GEntries[I];
  TArray.Sort<TFolderHotlistEntry>(Result,
    TComparer<TFolderHotlistEntry>.Construct(CompareHotlistEntries));
end;

procedure FolderHotlistClear;
begin
  EnsureLoaded;
  GEntries.Clear;
  try
    SaveLocked;
  except
  end;
end;

function FolderHotlistKeyLabel(AHotKey: Integer): string;
begin
  if AHotKey = 10 then
    Result := 'Ctrl+0'
  else if (AHotKey >= 1) and (AHotKey <= 9) then
    Result := 'Ctrl+' + IntToStr(AHotKey)
  else
    Result := '';
end;

function FolderHotlistKeyFromVKey(AKey: Word): Integer;
begin
  if AKey = Ord('0') then
    Result := 10
  else if (AKey >= Ord('1')) and (AKey <= Ord('9')) then
    Result := AKey - Ord('0')
  else
    Result := 0;
end;

initialization

finalization
  FreeAndNil(GEntries);

end.
