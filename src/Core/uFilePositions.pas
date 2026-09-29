unit uFilePositions;

{ Persistent per-file Viewer/Editor position (F3/F4): top-left scroll
  corner, cursor row/column, and - if one was active when the window
  closed - the selection range. Reopening the same file restores all of it,
  in both Viewer and Editor. The Viewer also keeps its line wrapping (F2)
  per file; the Editor, which does not wrap, leaves the saved mode alone. }

interface

uses
  System.SysUtils;

type
  /// <summary>The Viewer's line wrapping for a file: fwwKeep when none was
  /// saved (or, on save, to keep the one on record).</summary>
  TFileWordWrap = (fwwKeep, fwwOff, fwwOn);

  TFilePosition = record
    TopLine: Integer;
    LeftCol: Integer;
    CursorRow: Integer;
    CursorCol: Integer;
    /// <summary>True if a selection was active when saved - then
    /// SelAnchorRow/SelAnchorCol is the far end from CursorRow/CursorCol.</summary>
    HasSelection: Boolean;
    SelAnchorRow: Integer;
    SelAnchorCol: Integer;
    WordWrap: TFileWordWrap;
  end;

/// <summary>F3/F4: remembers top-left scroll, cursor, and (if any) selection.</summary>
procedure SaveFilePosition(const AURI: string; ATopLine, ALeftCol, ACursorRow,
  ACursorCol: Integer; AHasSelection: Boolean; ASelAnchorRow, ASelAnchorCol: Integer;
  AWordWrap: TFileWordWrap = fwwKeep);
/// <summary>True if a saved position exists for AURI; APosition is zeroed
/// (HasSelection = False) when no entry is found.</summary>
function TryGetFilePosition(const AURI: string; out APosition: TFilePosition): Boolean;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.Generics.Collections,
  uConfigLocation, uVfsTypes;

const
  cFileName = 'fileposition.json';
  cMaxEntries = 1000;

type
  TPosEntry = record
    URI: string;
    Position: TFilePosition;
  end;

var
  GLoaded: Boolean = False;
  GEntries: TList<TPosEntry>; // most-recently-touched last; linear scan is fine at this size

procedure EnsureLoaded;
var
  Path, Content: string;
  Root: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
  Item: TJSONValue;
  Obj: TJSONObject;
  Entry: TPosEntry;
  U: string;
  RowVal, ColVal, WrapVal: TJSONValue;
begin
  if GLoaded then
    Exit;
  GLoaded := True;
  if GEntries = nil then
    GEntries := TList<TPosEntry>.Create
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
        U := Trim(Obj.GetValue<string>('uri', ''));
        if U = '' then
          Continue;
        Entry.URI := U;
        Entry.Position.TopLine := Obj.GetValue<Integer>('top', 0);
        Entry.Position.LeftCol := Obj.GetValue<Integer>('left', 0);
        Entry.Position.CursorRow := Obj.GetValue<Integer>('cursorRow', 0);
        Entry.Position.CursorCol := Obj.GetValue<Integer>('cursorCol', 0);
        RowVal := Obj.Values['selAnchorRow'];
        ColVal := Obj.Values['selAnchorCol'];
        Entry.Position.HasSelection := Assigned(RowVal) and Assigned(ColVal);
        if Entry.Position.HasSelection then
        begin
          Entry.Position.SelAnchorRow := Obj.GetValue<Integer>('selAnchorRow', 0);
          Entry.Position.SelAnchorCol := Obj.GetValue<Integer>('selAnchorCol', 0);
        end
        else
        begin
          Entry.Position.SelAnchorRow := 0;
          Entry.Position.SelAnchorCol := 0;
        end;
        WrapVal := Obj.Values['wordWrap'];
        if WrapVal is TJSONBool then
        begin
          if TJSONBool(WrapVal).AsBoolean then
            Entry.Position.WordWrap := fwwOn
          else
            Entry.Position.WordWrap := fwwOff;
        end
        else
          Entry.Position.WordWrap := fwwKeep;
        GEntries.Add(Entry);
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
      Obj.AddPair('uri', GEntries[I].URI);
      Obj.AddPair('top', TJSONNumber.Create(GEntries[I].Position.TopLine));
      Obj.AddPair('left', TJSONNumber.Create(GEntries[I].Position.LeftCol));
      Obj.AddPair('cursorRow', TJSONNumber.Create(GEntries[I].Position.CursorRow));
      Obj.AddPair('cursorCol', TJSONNumber.Create(GEntries[I].Position.CursorCol));
      if GEntries[I].Position.HasSelection then
      begin
        Obj.AddPair('selAnchorRow', TJSONNumber.Create(GEntries[I].Position.SelAnchorRow));
        Obj.AddPair('selAnchorCol', TJSONNumber.Create(GEntries[I].Position.SelAnchorCol));
      end;
      if GEntries[I].Position.WordWrap <> fwwKeep then
        Obj.AddPair('wordWrap', TJSONBool.Create(GEntries[I].Position.WordWrap = fwwOn));
      Arr.AddElement(Obj);
    end;
    TFile.WriteAllText(Path, Arr.ToJSON, TEncoding.UTF8);
  finally
    Arr.Free;
  end;
end;

function IndexOfUri(const AURI: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to GEntries.Count - 1 do
    if SameVfsUri(GEntries[I].URI, AURI) then
      Exit(I);
end;

procedure UpsertPosition(const AURI: string; const APos: TFilePosition);
var
  Idx: Integer;
  Entry: TPosEntry;
begin
  EnsureLoaded;
  Idx := IndexOfUri(AURI);
  if Idx >= 0 then
    GEntries.Delete(Idx);
  Entry.URI := AURI;
  Entry.Position := APos;
  GEntries.Add(Entry); // most-recently-touched last
  while GEntries.Count > cMaxEntries do
    GEntries.Delete(0);
  try
    SaveLocked;
  except
    // Best-effort persistence - a write failure should not block closing the file.
  end;
end;

procedure SaveFilePosition(const AURI: string; ATopLine, ALeftCol, ACursorRow,
  ACursorCol: Integer; AHasSelection: Boolean; ASelAnchorRow, ASelAnchorCol: Integer;
  AWordWrap: TFileWordWrap);
var
  Pos, Old: TFilePosition;
begin
  if Trim(AURI) = '' then
    Exit;
  if AWordWrap = fwwKeep then
  begin
    TryGetFilePosition(AURI, Old);
    Pos.WordWrap := Old.WordWrap;
  end
  else
    Pos.WordWrap := AWordWrap;
  Pos.TopLine := ATopLine;
  Pos.LeftCol := ALeftCol;
  Pos.CursorRow := ACursorRow;
  Pos.CursorCol := ACursorCol;
  Pos.HasSelection := AHasSelection;
  if AHasSelection then
  begin
    Pos.SelAnchorRow := ASelAnchorRow;
    Pos.SelAnchorCol := ASelAnchorCol;
  end
  else
  begin
    Pos.SelAnchorRow := 0;
    Pos.SelAnchorCol := 0;
  end;
  UpsertPosition(AURI, Pos);
end;

function TryGetFilePosition(const AURI: string; out APosition: TFilePosition): Boolean;
var
  Idx: Integer;
begin
  EnsureLoaded;
  Idx := IndexOfUri(AURI);
  Result := Idx >= 0;
  if Result then
    APosition := GEntries[Idx].Position
  else
  begin
    APosition.TopLine := 0;
    APosition.LeftCol := 0;
    APosition.CursorRow := 0;
    APosition.CursorCol := 0;
    APosition.HasSelection := False;
    APosition.SelAnchorRow := 0;
    APosition.SelAnchorCol := 0;
    APosition.WordWrap := fwwKeep;
  end;
end;

initialization

finalization
  FreeAndNil(GEntries);

end.
