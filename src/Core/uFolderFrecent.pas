unit uFolderFrecent;

{ Persistent per-folder visit counts for the frecent jump (Ctrl+Shift+F12).
  A folder ranks by how often and how recently it was entered: each visit adds
  to its count, and the count is weighted by the age of the last visit. }

interface

uses
  System.SysUtils;

const
  cFolderFrecentMax = 500;

/// <summary>Visit count weighted by the age of the last visit (seconds):
/// within an hour x4, a day x2, a week x0.5, older x0.25.</summary>
function FrecentScore(ACount: Integer; AAgeSec: Int64): Double;

procedure FolderFrecentVisit(const AURI: string; ANowUnix: Int64); overload;
procedure FolderFrecentVisit(const AURI: string); overload;
/// <summary>Best first; equal scores keep the more recent visit first.</summary>
function FolderFrecentGetUris(ANowUnix: Int64): TArray<string>; overload;
function FolderFrecentGetUris: TArray<string>; overload;
procedure FolderFrecentRemove(const AURI: string);
procedure FolderFrecentClear;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.Generics.Collections,
  System.Generics.Defaults, System.DateUtils, System.Math,
  uConfigLocation, uVfsTypes;

type
  TFrecentEntry = record
    URI: string;
    Count: Integer;
    LastVisit: Int64;
  end;

const
  cFileName = 'folderfrecent.json';
  cHour = 3600;
  cDay = 86400;
  cWeek = 7 * 86400;

var
  GLoaded: Boolean = False;
  GEntries: TList<TFrecentEntry>;

function FrecentScore(ACount: Integer; AAgeSec: Int64): Double;
begin
  if AAgeSec < cHour then
    Result := ACount * 4.0
  else if AAgeSec < cDay then
    Result := ACount * 2.0
  else if AAgeSec < cWeek then
    Result := ACount * 0.5
  else
    Result := ACount * 0.25;
end;

function NowUnix: Int64;
begin
  Result := DateTimeToUnix(Now, False);
end;

procedure EnsureLoaded;
var
  Path: string;
  Root: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
  Obj: TJSONObject;
  E: TFrecentEntry;
  V: TJSONValue;
begin
  if GLoaded then
    Exit;
  GLoaded := True;
  if GEntries = nil then
    GEntries := TList<TFrecentEntry>.Create
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
      Arr := TJSONArray(Root);
      for I := 0 to Arr.Count - 1 do
      begin
        if not (Arr.Items[I] is TJSONObject) then
          Continue;
        Obj := TJSONObject(Arr.Items[I]);
        E.URI := Trim(Obj.GetValue<string>('uri', ''));
        if E.URI = '' then
          Continue;
        V := Obj.Values['count'];
        if V is TJSONNumber then
          E.Count := Round(TJSONNumber(V).AsDouble)
        else
          E.Count := 1;
        V := Obj.Values['last'];
        if V is TJSONNumber then
          E.LastVisit := Round(TJSONNumber(V).AsDouble)
        else
          E.LastVisit := 0;
        if E.Count < 1 then
          E.Count := 1;
        GEntries.Add(E);
      end;
    finally
      Root.Free;
    end;
  except
    GEntries.Clear;
  end;
end;

procedure SaveToDisk;
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  E: TFrecentEntry;
begin
  Arr := TJSONArray.Create;
  try
    for E in GEntries do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('uri', E.URI);
      Obj.AddPair('count', TJSONNumber.Create(E.Count));
      Obj.AddPair('last', TJSONNumber.Create(E.LastVisit));
      Arr.AddElement(Obj);
    end;
    try
      TFile.WriteAllText(GetConfigFilePath(cFileName), Arr.ToJSON, TEncoding.UTF8);
    except
      // The ranking is a convenience: a read-only settings folder must not
      // break navigation.
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

procedure DropWeakest(ANowUnix: Int64);
var
  I, Worst: Integer;
  S, WorstScore: Double;
begin
  while GEntries.Count > cFolderFrecentMax do
  begin
    Worst := 0;
    WorstScore := MaxDouble;
    for I := 0 to GEntries.Count - 1 do
    begin
      S := FrecentScore(GEntries[I].Count, ANowUnix - GEntries[I].LastVisit);
      if S < WorstScore then
      begin
        WorstScore := S;
        Worst := I;
      end;
    end;
    GEntries.Delete(Worst);
  end;
end;

procedure FolderFrecentVisit(const AURI: string; ANowUnix: Int64);
var
  U: string;
  I: Integer;
  E: TFrecentEntry;
begin
  U := Trim(AURI);
  if U = '' then
    Exit;
  EnsureLoaded;
  I := IndexOfUri(U);
  if I >= 0 then
  begin
    E := GEntries[I];
    Inc(E.Count);
    E.LastVisit := ANowUnix;
    GEntries[I] := E;
  end
  else
  begin
    E.URI := U;
    E.Count := 1;
    E.LastVisit := ANowUnix;
    GEntries.Add(E);
    DropWeakest(ANowUnix);
  end;
  SaveToDisk;
end;

procedure FolderFrecentVisit(const AURI: string);
begin
  FolderFrecentVisit(AURI, NowUnix);
end;

function FolderFrecentGetUris(ANowUnix: Int64): TArray<string>;
var
  Sorted: TArray<TFrecentEntry>;
  I: Integer;
begin
  EnsureLoaded;
  Sorted := GEntries.ToArray;
  TArray.Sort<TFrecentEntry>(Sorted, TComparer<TFrecentEntry>.Construct(
    function(const L, R: TFrecentEntry): Integer
    var
      SL, SR: Double;
    begin
      SL := FrecentScore(L.Count, ANowUnix - L.LastVisit);
      SR := FrecentScore(R.Count, ANowUnix - R.LastVisit);
      if SL > SR then
        Result := -1
      else if SL < SR then
        Result := 1
      else if L.LastVisit > R.LastVisit then
        Result := -1
      else if L.LastVisit < R.LastVisit then
        Result := 1
      else
        Result := 0;
    end));
  SetLength(Result, Length(Sorted));
  for I := 0 to High(Sorted) do
    Result[I] := Sorted[I].URI;
end;

function FolderFrecentGetUris: TArray<string>;
begin
  Result := FolderFrecentGetUris(NowUnix);
end;

procedure FolderFrecentRemove(const AURI: string);
var
  I: Integer;
begin
  EnsureLoaded;
  I := IndexOfUri(Trim(AURI));
  if I < 0 then
    Exit;
  GEntries.Delete(I);
  SaveToDisk;
end;

procedure FolderFrecentClear;
begin
  EnsureLoaded;
  GEntries.Clear;
  SaveToDisk;
end;

initialization

finalization
  FreeAndNil(GEntries);

end.
