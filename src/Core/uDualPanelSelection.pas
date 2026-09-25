unit uDualPanelSelection;

{ File mask selection helper (FAR Gray+ / Gray−) for Dual Panel.
  Extracted from TDualPanelWindow as part of Step 1 refactoring. }

interface

uses
  System.SysUtils, uDualPanelTypes;

type
  TDualPanelSelectionHelper = class
  private
    FLastSelectMask: string;
    FSelectFolders: Boolean;
  public
    constructor Create;
    procedure Reset;
    function MatchMask(const AFileName, AMask: string): Boolean;
    property LastSelectMask: string read FLastSelectMask write FLastSelectMask;
    property SelectFolders: Boolean read FSelectFolders write FSelectFolders;
  end;

/// <summary>URIs a copy/move/delete job would take from the active tab:
/// selected non-parent rows, or the cursor row when nothing is selected.</summary>
function CollectPanelJobSources(const ATab: TTab; const ARows: TPanelRows): TArray<string>;
function PendingSelectMatchIndex(const ARows: TPanelRows; const AWant: string): Integer;
function PendingSelectNameAtCursor(const ARows: TPanelRows; ACursorIndex: Integer): string;
function CollectVisibleRowNames(const ARows: TPanelRows): TArray<string>;

implementation

uses
  System.Masks;

constructor TDualPanelSelectionHelper.Create;
begin
  inherited Create;
  FLastSelectMask := '*.*';
  FSelectFolders := False;
end;

procedure TDualPanelSelectionHelper.Reset;
begin
  FLastSelectMask := '*.*';
end;

function TDualPanelSelectionHelper.MatchMask(const AFileName, AMask: string): Boolean;
var
  CleanMask: string;
begin
  CleanMask := Trim(AMask);
  if (CleanMask = '') or (CleanMask = '*.*') or (CleanMask = '*') then
    Exit(True);
  try
    Result := MatchesMask(AFileName, CleanMask);
  except
    Result := False;
  end;
end;

function CollectPanelJobSources(const ATab: TTab; const ARows: TPanelRows): TArray<string>;
var
  R: TPanelRow;
  N: Integer;
  Keys: TArray<string>;
begin
  SetLength(Result, 0);
  if Length(ATab.SelectedURIs) > 0 then
  begin
    Keys := TabSelectionKeys(ATab);
    for R in ARows do
      if (not R.IsParent) and (R.URI <> '') and SelectionKeysHas(Keys, R.URI) then
      begin
        N := Length(Result);
        SetLength(Result, N + 1);
        Result[N] := R.URI;
      end;
    Exit;
  end;
  if (ATab.CursorIndex >= 0) and (ATab.CursorIndex <= High(ARows)) then
  begin
    R := ARows[ATab.CursorIndex];
    if (not R.IsParent) and (R.URI <> '') then
    begin
      SetLength(Result, 1);
      Result[0] := R.URI;
    end;
  end;
end;

function PendingSelectMatchIndex(const ARows: TPanelRows; const AWant: string): Integer;
var
  I: Integer;
  Want, RowName: string;
begin
  Result := -1;
  Want := AWant;
  if (Want <> '') and (Want[Length(Want)] = '/') then
    Delete(Want, Length(Want), 1);
  if Want = '' then
    Exit;
  for I := 0 to High(ARows) do
  begin
    if ARows[I].IsParent then
      Continue;
    RowName := ARows[I].Text;
    if (RowName <> '') and (RowName[Length(RowName)] = '/') then
      Delete(RowName, Length(RowName), 1);
    if SameText(RowName, Want) then
      Exit(I);
  end;
end;

function PendingSelectNameAtCursor(const ARows: TPanelRows; ACursorIndex: Integer): string;
begin
  Result := '';
  if (ACursorIndex < 0) or (ACursorIndex > High(ARows)) then
    Exit;
  if ARows[ACursorIndex].IsParent then
    Exit;
  Result := ARows[ACursorIndex].Text;
  if (Result <> '') and (Result[Length(Result)] = '/') then
    Delete(Result, Length(Result), 1);
end;

function CollectVisibleRowNames(const ARows: TPanelRows): TArray<string>;
var
  I, N: Integer;
  Name: string;
begin
  SetLength(Result, Length(ARows));
  N := 0;
  for I := 0 to High(ARows) do
  begin
    if ARows[I].IsParent then
      Continue;
    Name := ARows[I].Text;
    while (Name <> '') and ((Name[Length(Name)] = '/') or
      (Name[Length(Name)] = '\')) do
      Delete(Name, Length(Name), 1);
    if Name = '' then
      Continue;
    Result[N] := Name;
    Inc(N);
  end;
  SetLength(Result, N);
end;

end.
