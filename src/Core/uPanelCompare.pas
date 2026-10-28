unit uPanelCompare;

{ Compare folders (FAR Commands > Compare folders, TC Shift+F2): marks what
  differs between the two panels' current listings. Works on the rows the
  panels already hold -- no recursion, no file reads -- so any VFS (archives,
  SFTP, search results) compares the same way.

  A file is marked when it exists on one side only, or on the side where it
  is newer. Same time (within the FAT 2 s granularity) but a different size
  marks both. Folders are marked only when missing on the other side. Names
  compare case-insensitively; '..' is skipped.

  The options choose what counts as a difference between two files that exist
  on both sides: the modification time, the size, the content. A file that
  exists on one side only is always marked. }

interface

uses
  System.SysUtils, uDualPanelTypes;

const
  /// <summary>FAT stores modification time in 2-second steps.</summary>
  cPanelCompareTimeToleranceSec = 2;

type
  TPanelCompareOptions = record
    ByTime: Boolean;
    BySize: Boolean;
    /// <summary>Same-size files are read and compared byte by byte; needs
    /// AContentEqual in ComparePanelRows.</summary>
    ByContent: Boolean;
    class function Default: TPanelCompareOptions; static;
  end;

  /// <summary>True when the two rows hold identical content.</summary>
  TPanelContentEqualFn = reference to function(const ALeft, ARight: TPanelRow): Boolean;

  TPanelCompareResult = record
    /// <summary>URIs to select on each side (the whole new selection).</summary>
    LeftUris: TArray<string>;
    RightUris: TArray<string>;
  end;

/// <summary>Time and size, no content: the default of Compare folders.</summary>
function ComparePanelRows(const ALeft, ARight: TPanelRows): TPanelCompareResult; overload;
function ComparePanelRows(const ALeft, ARight: TPanelRows;
  const AOptions: TPanelCompareOptions;
  const AContentEqual: TPanelContentEqualFn): TPanelCompareResult; overload;
/// <summary>Byte-for-byte comparison of two local files; False when either
/// cannot be read. ACancelled is polled between blocks and stops the read
/// with False.</summary>
function LocalFilesHaveSameContent(const ALeftPath, ARightPath: string;
  const ACancelled: TFunc<Boolean>): Boolean;
/// <summary>Row name without a trailing '/' or '\' (dirs may carry one).</summary>
function PanelCompareName(const ARow: TPanelRow): string;
/// <summary>The two plain files marked in one panel, in listing order. False
/// unless exactly two rows are selected and neither is a folder or '..'.</summary>
function PickMarkedFilePair(const ARows: TPanelRows; const ATab: TTab;
  out ALeft, ARight: TPanelRow): Boolean;
/// <summary>One line of the compare-files summary; Same says whether the two
/// sides match (the dialog colors the whole line by it).</summary>
type
  TCompareSummaryRow = record
    Text: string;
    Same: Boolean;
  end;

/// <summary>Size, modified time and content of two compared files, one
/// localized row each, e.g. 'Size:     48 213 B = 48 213 B'. AContentEqual says
/// whether the bytes match; ADiffOffset is the first differing byte (> 0) or
/// not known.</summary>
function BuildCompareSummary(const ALeft, ARight: TPanelRow;
  AContentEqual: Boolean; ADiffOffset: Int64): TArray<TCompareSummaryRow>;
/// <summary>Size with digit grouping and a unit, e.g. '48 213 B'.</summary>
function FormatExactSize(ASize: Int64): string;

implementation

uses
  System.Classes, System.DateUtils, System.Math, System.Generics.Collections,
  uVfsTypes, uStrings;

class function TPanelCompareOptions.Default: TPanelCompareOptions;
begin
  Result.ByTime := True;
  Result.BySize := True;
  Result.ByContent := False;
end;

function PanelCompareName(const ARow: TPanelRow): string;
begin
  Result := ARow.Text;
  while (Result <> '') and CharInSet(Result[Length(Result)], ['/', '\']) do
    Delete(Result, Length(Result), 1);
end;

function PickMarkedFilePair(const ARows: TPanelRows; const ATab: TTab;
  out ALeft, ARight: TPanelRow): Boolean;
var
  I, Found: Integer;
begin
  Found := 0;
  for I := 0 to High(ARows) do
  begin
    if ARows[I].IsParent or not TabIsSelected(ATab, ARows[I].URI) then
      Continue;
    if ARows[I].IsDirectory then
      Exit(False);
    if Found = 0 then
      ALeft := ARows[I]
    else if Found = 1 then
      ARight := ARows[I]
    else
      Exit(False);
    Inc(Found);
  end;
  Result := Found = 2;
end;

function FormatExactSize(ASize: Int64): string;
var
  Digits: string;
  I, N: Integer;
begin
  Digits := IntToStr(Abs(ASize));
  Result := '';
  N := 0;
  for I := Length(Digits) downto 1 do
  begin
    if (N > 0) and (N mod 3 = 0) then
      Result := ' ' + Result;
    Result := Digits[I] + Result;
    Inc(N);
  end;
  if ASize < 0 then
    Result := '-' + Result;
  Result := Result + ' B';
end;

function BuildCompareSummary(const ALeft, ARight: TPanelRow;
  AContentEqual: Boolean; ADiffOffset: Int64): TArray<TCompareSummaryRow>;
const
  cStampFormat = 'yyyy-mm-dd hh:nn:ss';
var
  SizeLabel, ModifiedLabel, ContentLabel, Word: string;
  LabelWidth: Integer;

  function Pair(const ALabel, ALeftText, ARightText: string;
    ASame: Boolean): TCompareSummaryRow;
  var
    ValueWidth: Integer;
    Mark: string;
  begin
    ValueWidth := Max(Length(ALeftText), Length(ARightText));
    if ASame then
      Mark := '='
    else
      Mark := '<>';
    Result.Text := ALabel.PadRight(LabelWidth) + ALeftText.PadRight(ValueWidth) +
      ' ' + Mark.PadRight(2) + ' ' + ARightText;
    Result.Same := ASame;
  end;

var
  Row: TCompareSummaryRow;
  SameTime: Boolean;
begin
  SizeLabel := T('ui.compareFiles.size', 'Size') + ':';
  ModifiedLabel := T('ui.compareFiles.modified', 'Modified') + ':';
  ContentLabel := T('ui.compareFiles.content', 'Content') + ':';
  LabelWidth := Max(Length(SizeLabel), Max(Length(ModifiedLabel),
    Length(ContentLabel))) + 1;
  SetLength(Result, 3);
  Result[0] := Pair(SizeLabel, FormatExactSize(ALeft.Size),
    FormatExactSize(ARight.Size), ALeft.Size = ARight.Size);
  SameTime := Abs(ALeft.ModificationTime - ARight.ModificationTime) * SecsPerDay <=
    cPanelCompareTimeToleranceSec;
  Result[1] := Pair(ModifiedLabel, FormatDateTime(cStampFormat, ALeft.ModificationTime),
    FormatDateTime(cStampFormat, ARight.ModificationTime), SameTime);
  if AContentEqual then
    Word := T('ui.compareFiles.contentEqual', 'identical')
  else if ADiffOffset > 0 then
    Word := T('ui.compareFiles.contentOffset', 'differs at byte offset %d',
      [ADiffOffset])
  else
    Word := T('ui.compareFiles.differs', 'differs');
  Row.Text := ContentLabel.PadRight(LabelWidth) + Word;
  Row.Same := AContentEqual;
  Result[2] := Row;
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
begin
  Result := ComparePanelRows(ALeft, ARight, TPanelCompareOptions.Default, nil);
end;

function ComparePanelRows(const ALeft, ARight: TPanelRows;
  const AOptions: TPanelCompareOptions;
  const AContentEqual: TPanelContentEqualFn): TPanelCompareResult;
var
  LeftIdx, RightIdx: TDictionary<string, Integer>;
  L, R: TPanelRow;
  J: Integer;
  Differs: Boolean;
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
      if AOptions.ByTime then
        case CompareTimes(L.ModificationTime, R.ModificationTime) of
          -1:
            begin
              Add(Result.LeftUris, L.URI);
              Continue;
            end;
          1:
            begin
              Add(Result.RightUris, R.URI);
              Continue;
            end;
        end;
      Differs := False;
      if (AOptions.BySize or AOptions.ByContent) and
         (L.Size >= 0) and (R.Size >= 0) and (L.Size <> R.Size) then
        Differs := True
      else if AOptions.ByContent and Assigned(AContentEqual) and
              (L.Size >= 0) and (R.Size >= 0) and not AContentEqual(L, R) then
        Differs := True;
      if Differs then
      begin
        Add(Result.LeftUris, L.URI);
        Add(Result.RightUris, R.URI);
      end;
    end;
    MarkUnique(ARight, LeftIdx, Result.RightUris);
  finally
    LeftIdx.Free;
    RightIdx.Free;
  end;
end;

function LocalFilesHaveSameContent(const ALeftPath, ARightPath: string;
  const ACancelled: TFunc<Boolean>): Boolean;
const
  cBlock = 256 * 1024;
var
  A, B: TFileStream;
  BufA, BufB: TBytes;
  NA, NB: Integer;
begin
  Result := False;
  try
    A := TFileStream.Create(WinApiPath(ALeftPath), fmOpenRead or fmShareDenyNone);
    try
      B := TFileStream.Create(WinApiPath(ARightPath), fmOpenRead or fmShareDenyNone);
      try
        if A.Size <> B.Size then
          Exit;
        SetLength(BufA, cBlock);
        SetLength(BufB, cBlock);
        repeat
          if Assigned(ACancelled) and ACancelled() then
            Exit;
          NA := A.Read(BufA[0], cBlock);
          NB := B.Read(BufB[0], cBlock);
          if (NA <> NB) or ((NA > 0) and not CompareMem(@BufA[0], @BufB[0], NA)) then
            Exit;
        until NA = 0;
        Result := True;
      finally
        B.Free;
      end;
    finally
      A.Free;
    end;
  except
    Result := False;
  end;
end;

end.
