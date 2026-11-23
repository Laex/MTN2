unit uRenameJournal;

{ The last multi-rename batch as original -> new path pairs, kept on disk, and the
  plan that reverses it. A pair is only reversed when its new name still
  exists and its original name is free; a chain (a -> b, b -> c) is undone in an
  order that never lands on a taken name. }

interface

uses
  System.SysUtils;

const
  /// <summary>File name of the journal in the settings folder.</summary>
  cRenameJournalFile = 'renamelog.json';

/// <summary>Stores the batch: ASources[i] was renamed to ADests[i].</summary>
procedure SaveRenameJournal(const AFile: string; const ASources, ADests: TArray<string>);
/// <summary>False when there is no readable journal or it holds no pairs.</summary>
function LoadRenameJournal(const AFile: string; out ASources, ADests: TArray<string>): Boolean;
procedure ClearRenameJournal(const AFile: string);

/// <summary>The renames that undo the batch, in the order to run them:
/// AUndoFrom[i] goes back to AUndoTo[i]. Returns how many pairs cannot go back
/// because the renamed item is gone or the original name is taken.</summary>
function PlanRenameUndo(const ASources, ADests: TArray<string>;
  const AExists: TFunc<string, Boolean>; out AUndoFrom, AUndoTo: TArray<string>): Integer;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.Generics.Collections;

const
  cPairs = 'pairs';
  cFrom = 'from';
  cTo = 'to';

function PathKey(const APath: string): string;
begin
{$IFDEF MSWINDOWS}
  Result := LowerCase(APath);
{$ELSE}
  Result := APath;
{$ENDIF}
end;

procedure SaveRenameJournal(const AFile: string; const ASources, ADests: TArray<string>);
var
  Root: TJSONObject;
  Arr: TJSONArray;
  Pair: TJSONObject;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Arr := TJSONArray.Create;
    Root.AddPair(cPairs, Arr);
    for I := 0 to High(ASources) do
    begin
      Pair := TJSONObject.Create;
      Pair.AddPair(cFrom, ASources[I]);
      Pair.AddPair(cTo, ADests[I]);
      Arr.AddElement(Pair);
    end;
    ForceDirectories(ExtractFilePath(AFile));
    TFile.WriteAllText(AFile, Root.ToJSON, TEncoding.UTF8);
  finally
    Root.Free;
  end;
end;

function LoadRenameJournal(const AFile: string; out ASources, ADests: TArray<string>): Boolean;
var
  Root: TJSONValue;
  Arr: TJSONArray;
  Item: TJSONValue;
  From, Dest: string;
  N: Integer;
begin
  SetLength(ASources, 0);
  SetLength(ADests, 0);
  if not TFile.Exists(AFile) then
    Exit(False);
  try
    Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(AFile, TEncoding.UTF8));
  except
    Exit(False);
  end;
  if Root = nil then
    Exit(False);
  try
    if not (Root is TJSONObject) or not TJSONObject(Root).TryGetValue<TJSONArray>(cPairs, Arr) then
      Exit(False);
    for Item in Arr do
      if (Item is TJSONObject) and TJSONObject(Item).TryGetValue<string>(cFrom, From) and
         TJSONObject(Item).TryGetValue<string>(cTo, Dest) and (From <> '') and (Dest <> '') then
      begin
        N := Length(ASources);
        SetLength(ASources, N + 1);
        SetLength(ADests, N + 1);
        ASources[N] := From;
        ADests[N] := Dest;
      end;
    Result := Length(ASources) > 0;
  finally
    Root.Free;
  end;
end;

procedure ClearRenameJournal(const AFile: string);
begin
  if TFile.Exists(AFile) then
    TFile.Delete(AFile);
end;

function PlanRenameUndo(const ASources, ADests: TArray<string>;
  const AExists: TFunc<string, Boolean>; out AUndoFrom, AUndoTo: TArray<string>): Integer;
var
  Override: TDictionary<string, Boolean>;
  Done: TArray<Boolean>;
  I, N: Integer;
  Progress: Boolean;

  function Present(const APath: string): Boolean;
  begin
    if not Override.TryGetValue(PathKey(APath), Result) then
      Result := AExists(APath);
  end;

begin
  SetLength(AUndoFrom, 0);
  SetLength(AUndoTo, 0);
  SetLength(Done, Length(ASources));
  Override := TDictionary<string, Boolean>.Create;
  try
    repeat
      Progress := False;
      for I := 0 to High(ASources) do
        if not Done[I] and Present(ADests[I]) and not Present(ASources[I]) then
        begin
          N := Length(AUndoFrom);
          SetLength(AUndoFrom, N + 1);
          SetLength(AUndoTo, N + 1);
          AUndoFrom[N] := ADests[I];
          AUndoTo[N] := ASources[I];
          Override.AddOrSetValue(PathKey(ADests[I]), False);
          Override.AddOrSetValue(PathKey(ASources[I]), True);
          Done[I] := True;
          Progress := True;
        end;
    until not Progress;
  finally
    Override.Free;
  end;
  Result := Length(ASources) - Length(AUndoFrom);
end;

end.
