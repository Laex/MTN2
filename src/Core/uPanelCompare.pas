unit uPanelCompare;

{ Compare folders (FAR Commands > Compare folders, TC Shift+F2): marks what
  differs between the two panels' current listings. Works on the rows the
  panels already hold -- no recursion, no file reads -- so any VFS (archives,
  SFTP, search results) compares the same way.

  A file is marked when it exists on one side only, or on the side where it
  is newer. Same time (within the FAT 2 s granularity) but a different size
  marks both. Folders are marked only when missing on the other side. Names
  compare case-insensitively; '..' is skipped. }

interface

uses
  uDualPanelTypes;

const
  /// <summary>FAT stores modification time in 2-second steps.</summary>
  cPanelCompareTimeToleranceSec = 2;

type
  TPanelCompareResult = record
    /// <summary>URIs to select on each side (the whole new selection).</summary>
    LeftUris: TArray<string>;
    RightUris: TArray<string>;
  end;

function ComparePanelRows(const ALeft, ARight: TPanelRows): TPanelCompareResult;
/// <summary>Row name without a trailing '/' or '\' (dirs may carry one).</summary>
function PanelCompareName(const ARow: TPanelRow): string;

implementation

uses
  System.SysUtils, System.DateUtils, System.Generics.Collections;

function PanelCompareName(const ARow: TPanelRow): string;
begin
  Result := ARow.Text;
  while (Result <> '') and CharInSet(Result[Length(Result)], ['/', '\']) do
    Delete(Result, Length(Result), 1);
end;

function IsComparable(const ARow: TPanelRow): Boolean;
begin
  Result := (not ARow.IsParent) and (ARow.URI <> '') and
    (PanelCompareName(ARow) <> '');
end;

function BuildIndex(const ARows: TPanelRows): TDictionary<string, Integer>;
var
  I: Integer;
  Key: string;
begin
  Result := TDictionary<string, Integer>.Create;
  for I := 0 to High(ARows) do
  begin
    if not IsComparable(ARows[I]) then
      Continue;
    Key := AnsiUpperCase(PanelCompareName(ARows[I]));
    if not Result.ContainsKey(Key) then
      Result.Add(Key, I);
  end;
end;

/// <summary>-1 A newer, 1 B newer, 0 same time.</summary>
function CompareTimes(const A, B: TDateTime): Integer;
var
  Diff: Int64;
begin
  if (A = 0) or (B = 0) then
    Exit(0); // VFS without times: only presence and size count
  Diff := SecondsBetween(A, B);
  if Diff <= cPanelCompareTimeToleranceSec then
    Exit(0);
  if A > B then
    Result := -1
  else
    Result := 1;
end;

procedure Add(var AList: TArray<string>; const AURI: string);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := AURI;
end;

procedure MarkUnique(const ARows: TPanelRows;
  AOther: TDictionary<string, Integer>; var AMarks: TArray<string>);
var
  R: TPanelRow;
begin
  for R in ARows do
    if IsComparable(R) and
       not AOther.ContainsKey(AnsiUpperCase(PanelCompareName(R))) then
      Add(AMarks, R.URI);
end;

function ComparePanelRows(const ALeft, ARight: TPanelRows): TPanelCompareResult;
var
  LeftIdx, RightIdx: TDictionary<string, Integer>;
  L, R: TPanelRow;
  J: Integer;
begin
  Result := Default(TPanelCompareResult);
  LeftIdx := BuildIndex(ALeft);
  RightIdx := BuildIndex(ARight);
  try
    MarkUnique(ALeft, RightIdx, Result.LeftUris);
    for L in ALeft do
    begin
      if not IsComparable(L) or L.IsDirectory or
         not RightIdx.TryGetValue(AnsiUpperCase(PanelCompareName(L)), J) then
        Continue;
      R := ARight[J];
      if R.IsDirectory then
        Continue; // file on one side, folder on the other: leave to the user
      case CompareTimes(L.ModificationTime, R.ModificationTime) of
        -1:
          Add(Result.LeftUris, L.URI);
        1:
          Add(Result.RightUris, R.URI);
      else
        if (L.Size >= 0) and (R.Size >= 0) and (L.Size <> R.Size) then
        begin
          Add(Result.LeftUris, L.URI);
          Add(Result.RightUris, R.URI);
        end;
      end;
    end;
    MarkUnique(ARight, LeftIdx, Result.RightUris);
  finally
    LeftIdx.Free;
    RightIdx.Free;
  end;
end;

end.
