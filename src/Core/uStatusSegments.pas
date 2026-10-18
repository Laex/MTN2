unit uStatusSegments;

{ What a section of the status line stands for, and which section a column
  falls in. The theme draws the sections one after another; this unit follows
  the same layout so a click can be mapped back to the section it hit. }

interface

type
  TStatusSegKind = (
    sskNone,
    sskSide,       // Left / Right: the drive list of that panel
    sskPath,       // folder of the panel: the folder history
    sskPosition,   // cursor position in a panel or a document: Go to line
    sskColumnMode, // the column mode menu
    sskItem,       // cursor item or selection: its properties
    sskFree,       // free space: the drive list
    sskEncoding,   // text encoding of a document
    sskFind        // result of the last search in a document: Find
  );

/// <summary>Index of the section under ACol, -1 between sections and outside
/// them. AThemed is the theme layout (sections separated by " | ", starting at
/// column 1); without a theme the sections are joined with two spaces.</summary>
function StatusSegmentAt(const ASegs: TArray<string>; ACol: Integer;
  AThemed: Boolean): Integer;

/// <summary>Sections of a panel status line in the order they are built.</summary>
function PanelStatusKinds(AIsPanels, AHasColumnMode, ACmdFocused, AHasItem,
  AHasFree: Boolean): TArray<TStatusSegKind>;

implementation

uses
  uCharWidth;

function StatusSegmentAt(const ASegs: TArray<string>; ACol: Integer;
  AThemed: Boolean): Integer;
var
  I, X, W, Gap: Integer;
begin
  Result := -1;
  if AThemed then
    Gap := 3
  else
    Gap := 2;
  X := 1;
  for I := 0 to High(ASegs) do
  begin
    W := TextDisplayWidth(ASegs[I]);
    if (ACol >= X) and (ACol < X + W) then
      Exit(I);
    Inc(X, W + Gap);
    if ACol < X then
      Exit;
  end;
end;

function PanelStatusKinds(AIsPanels, AHasColumnMode, ACmdFocused, AHasItem,
  AHasFree: Boolean): TArray<TStatusSegKind>;
begin
  Result := [sskSide, sskPath, sskPosition];
  if AIsPanels and AHasColumnMode then
    Result := Result + [sskColumnMode];
  if ACmdFocused then
    Result := Result + [sskNone]
  else if AHasItem then
    Result := Result + [sskItem];
  if AHasFree then
    Result := Result + [sskFree];
end;

end.
