unit uFolderHotlist;

{ Persistent, user-managed directory bookmarks (TC Ctrl+D / FAR Alt+F10 style).
  Unlike uFolderHistory (auto-pushed, unnamed, capped, newest-first), entries
  here are explicit add/remove/rename only, named, and never auto-evicted.

  Entries can be gathered into named groups. A group whose last entry left is
  kept as a placeholder entry (empty URI) until it is removed explicitly. }

interface

uses
  System.SysUtils, System.Classes;

type
  TFolderHotlistEntry = record
    Name: string;
    /// <summary>Empty for the placeholder of an empty group.</summary>
    URI: string;
    /// <summary>0 = none; 1..9 = Ctrl+1..Ctrl+9; 10 = Ctrl+0.</summary>
    HotKey: Integer;
    /// <summary>Group the entry is listed under; '' = ungrouped.</summary>
    Group: string;
  end;

procedure FolderHotlistAdd(const AName, AURI: string);
procedure FolderHotlistRemove(AIndex: Integer);
procedure FolderHotlistRename(AIndex: Integer; const ANewName: string);
/// <summary>Assigns AHotKey (1..10, see TFolderHotlistEntry.HotKey) to entry
/// AIndex, stealing it from whichever other entry currently holds it -
/// each hotkey maps to at most one entry. AHotKey = 0 clears AIndex's own
/// hotkey without assigning it elsewhere (toggle-off).</summary>
procedure FolderHotlistSetHotKey(AIndex, AHotKey: Integer);
/// <summary>Index of the entry bound to AHotKey (1..10), or -1 if none.</summary>
function FolderHotlistFindByHotKey(AHotKey: Integer): Integer;
/// <summary>The entries (and empty-group placeholders) in the order the user
/// arranged them (new ones go to the end, FolderHotlistMoveByUri reorders).</summary>
function FolderHotlistGetEntries: TArray<TFolderHotlistEntry>;
/// <summary>Moves the entry ADelta (+-1) places up (negative) or down; False
/// when it is not found or an ungrouped entry would leave the list. Inside a group it swaps with
/// its neighbour; at a group border it changes group instead of moving: a
/// grouped entry leaves its group, an ungrouped one joins the group of the
/// neighbour it would pass.</summary>
function FolderHotlistMoveByUri(const AUri: string; ADelta: Integer): Boolean;
procedure FolderHotlistClear;
/// <summary>Forgets the list in memory; the next use reads the file again.</summary>
procedure FolderHotlistReload;
/// <summary>Writes the list to disk now.</summary>
procedure FolderHotlistSave;
/// <summary>Replaces the whole list (for rolling back a cancelled edit).</summary>
procedure FolderHotlistSetEntries(const AEntries: TArray<TFolderHotlistEntry>);
/// <summary>Display label for AHotKey (1..10): 'Ctrl+1'..'Ctrl+9', 'Ctrl+0'; '' for 0.</summary>
function FolderHotlistKeyLabel(AHotKey: Integer): string;
/// <summary>Maps the raw VK code (Word) of a main-row '0'..'9' key to its
/// HotKey value (1..9, or 10 for '0', matching the 1-9-then-0 order on a
/// physical keyboard row); 0 for anything else. Takes AKey rather than
/// AKeyChar: Ctrl+digit has no ASCII control-code to reverse-map, so
/// AKeyChar is typically #0 for it (unlike Ctrl+letter, which reverse-maps
/// to its own letter) - callers gating on Ctrl+1..Ctrl+0 must check AKey.</summary>
function FolderHotlistKeyFromVKey(AKey: Word): Integer;
/// <summary>Index of the entry whose URI matches AUri (SameVfsUri-normalized),
/// or -1 if none.</summary>
function FolderHotlistFindByUri(const AUri: string): Integer;
/// <summary>Remove/rename/set-hotkey by URI rather than raw storage index -
/// safe to call with an entry taken from FolderHotlistGetEntries's result
/// whatever index it has in a list the caller has since changed.</summary>
procedure FolderHotlistRemoveByUri(const AUri: string);
procedure FolderHotlistRenameByUri(const AUri, ANewName: string);
procedure FolderHotlistSetHotKeyByUri(const AUri: string; AHotKey: Integer);
/// <summary>Puts the entry into AGroup ('' = ungrouped) and moves it next to
/// the other entries of that group (to the end of the group's block), so a
/// group's entries stay adjacent in the list.</summary>
procedure FolderHotlistSetGroupByUri(const AUri, AGroup: string);
/// <summary>The key a name or group name declares with '&' before a character
/// ("&Home" -> 'H'), upper-cased; #0 when there is none. "&&" is a literal '&'.</summary>
function HotlistKeyOf(const AText: string): Char;
/// <summary>AText as it is displayed: the '&' key marker removed.</summary>
function HotlistStripKey(const AText: string): string;
/// <summary>Renames the group AOld (matched without its '&' marker) to ANew
/// on every entry of it; False when the group does not exist or ANew is empty.</summary>
function FolderHotlistRenameGroup(const AOld, ANew: string): Boolean;
/// <summary>Deletes the placeholder of an empty group; False when the group
/// still has entries or does not exist.</summary>
function FolderHotlistRemoveEmptyGroup(const AGroup: string): Boolean;

implementation

uses
  System.IOUtils, System.JSON, System.Generics.Collections, System.Generics.Defaults,
  System.UITypes, uConfigLocation, uVfsTypes, uPlatformUpdate;

var
  GLoaded: Boolean = False;
  GEntries: TList<TFolderHotlistEntry>;

const
  cFileName = 'folderhotlist.json';

function HotlistKeyOf(const AText: string): Char;
var
  I: Integer;
begin
  Result := #0;
  I := 1;
  while I < Length(AText) do
  begin
    if AText[I] = '&' then
    begin
      if AText[I + 1] <> '&' then
        Exit(UpCase(AText[I + 1]));
      Inc(I);
    end;
    Inc(I);
  end;
end;

function HotlistStripKey(const AText: string): string;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(AText) do
  begin
    if (AText[I] = '&') and (I < Length(AText)) then
      Inc(I);
    Result := Result + AText[I];
    Inc(I);
  end;
end;

// Groups are told apart by their name without the key marker, ignoring case.
function SameGroup(const A, B: string): Boolean;
begin
  Result := SameText(HotlistStripKey(A), HotlistStripKey(B));
end;

function RealCount(const AGroup: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to GEntries.Count - 1 do
    if (GEntries[I].URI <> '') and SameGroup(GEntries[I].Group, AGroup) then
      Inc(Result);
end;

function Placeholder(const AGroup: string): TFolderHotlistEntry;
begin
  Result.Name := '';
  Result.URI := '';
  Result.HotKey := 0;
  Result.Group := AGroup;
end;

function FindPlaceholder(const AGroup: string): Integer;
begin
  for Result := 0 to GEntries.Count - 1 do
    if (GEntries[Result].URI = '') and SameGroup(GEntries[Result].Group, AGroup) then
      Exit;
  Result := -1;
end;

// A group with an entry does not need its placeholder.
procedure DropPlaceholder(const AGroup: string);
var
  I: Integer;
begin
  if AGroup = '' then
    Exit;
  I := FindPlaceholder(AGroup);
  if I >= 0 then
    GEntries.Delete(I);
end;

type
  THotlistLoad = (hlOk, hlUnreadable, hlCorrupt);

var
  // The file exists but could not be read: the list in memory is empty
  // only because of that, so nothing is written over the file.
  GLoadFailed: Boolean = False;
  GLoadFailedAt: UInt64 = 0;
  // Size and time of the file as this process last read or wrote it: another
  // copy of the program sharing the settings folder changes it behind our
  // back, and the list in memory is then read again before it is used.
  GStamp: string = '';
  GStampCheckedAt: UInt64 = 0;
  GLoading: Boolean = False;

const
  cRetryAfterFailureMs = 2000;
  cStampCheckMs = 200;

function BackupPath: string;
begin
  Result := GetConfigFilePath(cFileName) + '.bak';
end;

function FileStamp(const APath: string): string;
begin
  try
    if TFile.Exists(APath) then
      Result := IntToStr(TFile.GetSize(APath)) + '|' +
        FloatToStr(TFile.GetLastWriteTimeUtc(APath))
    else
      Result := '';
  except
    Result := '?';
  end;
end;

// A file another process is writing or scanning can refuse a read for a
// moment; a few tries tell that apart from a file that is really unreadable.
function ReadHotlistFile(const APath: string; out AText: string): Boolean;
var
  Attempt: Integer;
begin
  for Attempt := 1 to 4 do
  begin
    try
      AText := TFile.ReadAllText(APath, TEncoding.UTF8);
      Exit(True);
    except
      Sleep(50 * Attempt);
    end;
  end;
  Result := False;
end;

// Fills GEntries from the file at APath.
function LoadHotlistFrom(const APath: string): THotlistLoad;
var
  Content: string;
  Root: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
  Item: TJSONValue;
  Obj: TJSONObject;
  Entry: TFolderHotlistEntry;
  NameVal, UriVal, GroupVal: string;
  HotKeyVal: Integer;
begin
  GEntries.Clear;
  if not ReadHotlistFile(APath, Content) then
    Exit(hlUnreadable);
  Root := TJSONObject.ParseJSONValue(Content);
  if not (Root is TJSONArray) then
  begin
    Root.Free;
    Exit(hlCorrupt);
  end;
  try
    try
      Arr := TJSONArray(Root);
      for I := 0 to Arr.Count - 1 do
      begin
        Item := Arr.Items[I];
        if not (Item is TJSONObject) then
          Continue;
        Obj := TJSONObject(Item);
        if not Obj.TryGetValue<string>('uri', UriVal) then
          UriVal := '';
        UriVal := Trim(UriVal);
        if not Obj.TryGetValue<string>('group', GroupVal) then
          GroupVal := '';
        GroupVal := Trim(GroupVal);
        // No URI: only a group placeholder is worth keeping.
        if (UriVal = '') and ((GroupVal = '') or (FindPlaceholder(GroupVal) >= 0)) then
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
        Entry.Group := GroupVal;
        GEntries.Add(Entry);
      end;
      // A group with entries needs no placeholder.
      for I := GEntries.Count - 1 downto 0 do
        if (GEntries[I].URI = '') and (RealCount(GEntries[I].Group) > 0) then
          GEntries.Delete(I);
      // Defend against a hand-edited file assigning the same hotkey twice -
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
      Result := hlOk;
    except
      GEntries.Clear;
      Result := hlCorrupt;
    end;
  finally
    Root.Free;
  end;
end;

procedure LoadAll;
var
  Path, Backup: string;
begin
  GLoadFailed := False;
  if GEntries = nil then
    GEntries := TList<TFolderHotlistEntry>.Create
  else
    GEntries.Clear;

  Path := GetConfigFilePath(cFileName);
  Backup := BackupPath;
  if not TFile.Exists(Path) then
  begin
    // A lost file with a backup beside it is restored from the backup.
    if TFile.Exists(Backup) and (LoadHotlistFrom(Backup) <> hlOk) then
      GEntries.Clear;
    Exit;
  end;
  case LoadHotlistFrom(Path) of
    hlOk:
      ;
    hlUnreadable:
      begin
        // Not the user's list: ask again later and write nothing meanwhile.
        GEntries.Clear;
        GLoaded := False;
        GLoadFailed := True;
        GLoadFailedAt := TThread.GetTickCount64;
      end;
    hlCorrupt:
      begin
        // A damaged file is kept for recovery; the last good copy takes over.
        try
          TFile.Copy(Path, Path + '.corrupt', True);
        except
        end;
        if (not TFile.Exists(Backup)) or (LoadHotlistFrom(Backup) <> hlOk) then
          GEntries.Clear;
      end;
  end;
end;

procedure EnsureLoaded;
begin
  if GLoading then
    Exit;
  if GLoaded then
  begin
    // The file changed since this process last saw it: another copy of the
    // program wrote it, and its list is the one to work on.
    if TThread.GetTickCount64 - GStampCheckedAt < cStampCheckMs then
      Exit;
    GStampCheckedAt := TThread.GetTickCount64;
    if FileStamp(GetConfigFilePath(cFileName)) = GStamp then
      Exit;
    GLoaded := False;
  end;
  // A read that failed a moment ago is not repeated on every call.
  if GLoadFailed and (TThread.GetTickCount64 - GLoadFailedAt < cRetryAfterFailureMs) then
    Exit;
  // Set first: loading calls back into the list (hotkey check).
  GLoaded := True;
  GLoading := True;
  try
    LoadAll;
  finally
    GLoading := False;
  end;
  GStamp := FileStamp(GetConfigFilePath(cFileName));
  GStampCheckedAt := TThread.GetTickCount64;
end;

procedure FolderHotlistReload;
begin
  GLoaded := False;
  GLoadFailed := False;
  EnsureLoaded;
end;

// The new content is written beside the file and moved over it, so a crash
// or a power loss leaves the file whole, with either the previous content or
// the new one, never half of it. A list with entries is also kept as .bak, the
// copy a damaged or lost file is restored from.
procedure SaveLocked;
var
  Path, Tmp, Error: string;
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
begin
  if (GEntries = nil) or GLoadFailed then
    Exit;
  Path := GetConfigFilePath(cFileName);
  Tmp := Path + '.tmp';
  Arr := TJSONArray.Create;
  try
    for I := 0 to GEntries.Count - 1 do
    begin
      Obj := TJSONObject.Create;
      if GEntries[I].URI <> '' then
      begin
        Obj.AddPair('name', GEntries[I].Name);
        Obj.AddPair('uri', GEntries[I].URI);
      end;
      if GEntries[I].HotKey <> 0 then
        Obj.AddPair('hotkey', TJSONNumber.Create(GEntries[I].HotKey));
      if GEntries[I].Group <> '' then
        Obj.AddPair('group', GEntries[I].Group);
      Arr.AddElement(Obj);
    end;
    TFile.WriteAllText(Tmp, Arr.ToJSON, TEncoding.UTF8);
  finally
    Arr.Free;
  end;
  if not PlatformMoveFile(Tmp, Path, True, Error) then
  begin
    TFile.Delete(Tmp);
    raise EInOutError.Create(Error);
  end;
  GStamp := FileStamp(Path);
  GStampCheckedAt := TThread.GetTickCount64;
  if GEntries.Count > 0 then
    try
      TFile.Copy(Path, BackupPath, True);
    except
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
    if (GEntries[I].URI <> '') and SameVfsUri(GEntries[I].URI, U) then
      GEntries.Delete(I);
  Entry.Name := N;
  Entry.URI := U;
  Entry.HotKey := 0;
  Entry.Group := '';
  GEntries.Add(Entry);
  try
    SaveLocked;
  except
  end;
end;

procedure FolderHotlistRemove(AIndex: Integer);
var
  Group: string;
  Last: Boolean;
begin
  EnsureLoaded;
  if (AIndex < 0) or (AIndex >= GEntries.Count) then
    Exit;
  Group := GEntries[AIndex].Group;
  Last := (GEntries[AIndex].URI <> '') and (Group <> '') and (RealCount(Group) = 1);
  GEntries.Delete(AIndex);
  // The emptied group stays where its last entry was.
  if Last then
    GEntries.Insert(AIndex, Placeholder(Group));
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
    // Each hotkey maps to at most one entry - steal it from whoever had it.
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
    if (GEntries[I].URI <> '') and SameVfsUri(GEntries[I].URI, AUri) then
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

procedure SaveSafe;
begin
  try
    SaveLocked;
  except
  end;
end;

// The spelling to use for a group named G: an existing group keeps its own
// (so its key survives), unless G brings a key marker - then every entry of
// the group takes G.
function CanonicalGroup(const G: string): string;
var
  I: Integer;
  Existing: string;
  Entry: TFolderHotlistEntry;
begin
  Result := G;
  if G = '' then
    Exit;
  Existing := '';
  for I := 0 to GEntries.Count - 1 do
    if SameGroup(GEntries[I].Group, G) then
    begin
      Existing := GEntries[I].Group;
      Break;
    end;
  if Existing = '' then
    Exit;
  if (HotlistKeyOf(G) = #0) or (Existing = G) then
    Exit(Existing);
  for I := 0 to GEntries.Count - 1 do
    if SameGroup(GEntries[I].Group, G) then
    begin
      Entry := GEntries[I];
      Entry.Group := G;
      GEntries[I] := Entry;
    end;
end;

procedure FolderHotlistSetGroupByUri(const AUri, AGroup: string);
var
  From, I, Dest: Integer;
  Entry: TFolderHotlistEntry;
  G: string;
begin
  From := FolderHotlistFindByUri(AUri);
  if From < 0 then
    Exit;
  G := CanonicalGroup(Trim(AGroup));
  Entry := GEntries[From];
  if SameGroup(Entry.Group, G) then
  begin
    // Retyping a group with a new key marker still renames it.
    if Entry.Group <> G then
      SaveSafe;
    Exit;
  end;
  // The emptied group stays, as a placeholder, where the entry was.
  if (Entry.Group <> '') and (RealCount(Entry.Group) = 1) then
    GEntries[From] := Placeholder(Entry.Group)
  else
    GEntries.Delete(From);
  Entry.Group := G;
  // Just after the last entry of the target group; a group that does not
  // exist yet (or no group) goes to the end.
  Dest := GEntries.Count;
  if G <> '' then
    for I := GEntries.Count - 1 downto 0 do
      if SameGroup(GEntries[I].Group, G) then
      begin
        Dest := I + 1;
        Break;
      end;
  GEntries.Insert(Dest, Entry);
  DropPlaceholder(G);
  try
    SaveLocked;
  except
  end;
end;

function FolderHotlistRenameGroup(const AOld, ANew: string): Boolean;
var
  I: Integer;
  N: string;
  Entry: TFolderHotlistEntry;
begin
  EnsureLoaded;
  N := Trim(ANew);
  Result := False;
  if N = '' then
    Exit;
  for I := 0 to GEntries.Count - 1 do
    if SameGroup(GEntries[I].Group, AOld) then
    begin
      Entry := GEntries[I];
      Entry.Group := N;
      GEntries[I] := Entry;
      Result := True;
    end;
  if Result then
    SaveSafe;
end;

function FolderHotlistRemoveEmptyGroup(const AGroup: string): Boolean;
var
  I: Integer;
begin
  EnsureLoaded;
  I := FindPlaceholder(AGroup);
  Result := I >= 0;
  if not Result then
    Exit;
  GEntries.Delete(I);
  try
    SaveLocked;
  except
  end;
end;

function FolderHotlistGetEntries: TArray<TFolderHotlistEntry>;
var
  I: Integer;
begin
  EnsureLoaded;
  SetLength(Result, GEntries.Count);
  for I := 0 to GEntries.Count - 1 do
    Result[I] := GEntries[I];
end;

function FolderHotlistMoveByUri(const AUri: string; ADelta: Integer): Boolean;
var
  From, Dest: Integer;
  Entry: TFolderHotlistEntry;
  Old: string;
  Last, OutOfRange: Boolean;
begin
  Result := False;
  From := FolderHotlistFindByUri(AUri);
  if From < 0 then
    Exit;
  Dest := From + ADelta;
  if Dest = From then
    Exit;
  Entry := GEntries[From];
  OutOfRange := (Dest < 0) or (Dest >= GEntries.Count);
  if not OutOfRange and SameGroup(GEntries[Dest].Group, Entry.Group) then
    GEntries.Move(From, Dest)
  else if Entry.Group <> '' then
  begin
    // Crossing a group border (or the end of the list): the entry keeps its
    // place and leaves its group.
    Old := Entry.Group;
    Last := RealCount(Old) = 1;
    Entry.Group := '';
    GEntries[From] := Entry;
    // The emptied group stays, on the side the entry came from.
    if Last then
      GEntries.Insert(From + Ord(ADelta < 0), Placeholder(Old));
  end
  else if OutOfRange then
    Exit
  else
  begin
    Entry.Group := GEntries[Dest].Group;
    GEntries[From] := Entry;
    DropPlaceholder(Entry.Group);
  end;
  Result := True;
  try
    SaveLocked;
  except
  end;
end;

procedure FolderHotlistSetEntries(const AEntries: TArray<TFolderHotlistEntry>);
var
  E: TFolderHotlistEntry;
begin
  EnsureLoaded;
  GEntries.Clear;
  for E in AEntries do
    GEntries.Add(E);
  try
    SaveLocked;
  except
  end;
end;

procedure FolderHotlistSave;
begin
  EnsureLoaded;
  SaveLocked;
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
  if AKey = vk0 then
    Result := 10
  else if (AKey >= vk1) and (AKey <= vk9) then
    Result := AKey - vk0
  else
    Result := 0;
end;

initialization

finalization
  FreeAndNil(GEntries);

end.
