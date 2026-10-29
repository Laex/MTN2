unit uMenuNavigation;

{ Cursor movement shared by the list-like menus: Up, Down, Home, End, PgUp and
  PgDn over a row range where some rows (separators, headers) cannot hold the
  cursor. The menus keep their own drawing and activation; this only decides
  where the cursor goes. }

interface

uses
  System.SysUtils;

type
  /// <summary>True when the row can hold the cursor; nil means every row can.</summary>
  TMenuRowSelectable = reference to function(AIndex: Integer): Boolean;

/// <summary>Moves ACurrent by ADelta selectable rows. Stops at the last
/// selectable row when the list ends first; never wraps.</summary>
function MenuStepIndex(ACurrent, ACount, ADelta: Integer;
  const ASelectable: TMenuRowSelectable): Integer;

/// <summary>First (AFirst) or last selectable row; ACurrent when none is.</summary>
function MenuEdgeIndex(ACurrent, ACount: Integer; AFirst: Boolean;
  const ASelectable: TMenuRowSelectable): Integer;

/// <summary>Applies a navigation key (vkUp, vkDown, vkHome, vkEnd, vkPrior,
/// vkNext) to AIndex. APageRows is the number of rows a page key moves by.
/// False when AKey is not a navigation key.</summary>
function MenuNavigateKey(AKey: Word; var AIndex: Integer; ACount,
  APageRows: Integer; const ASelectable: TMenuRowSelectable): Boolean;

implementation

uses
  System.UITypes, System.Math;

function IsSelectableRow(AIndex: Integer;
  const ASelectable: TMenuRowSelectable): Boolean;
begin
  Result := not Assigned(ASelectable) or ASelectable(AIndex);
end;

function MenuStepIndex(ACurrent, ACount, ADelta: Integer;
  const ASelectable: TMenuRowSelectable): Integer;
var
  I, Remaining: Integer;
begin
  Result := ACurrent;
  if ACount <= 0 then
    Exit(0);
  I := ACurrent;
  Remaining := Abs(ADelta);
  while Remaining > 0 do
  begin
    Inc(I, Sign(ADelta));
    if (I < 0) or (I >= ACount) then
      Break;
    if IsSelectableRow(I, ASelectable) then
    begin
      Result := I;
      Dec(Remaining);
    end;
  end;
end;

function MenuEdgeIndex(ACurrent, ACount: Integer; AFirst: Boolean;
  const ASelectable: TMenuRowSelectable): Integer;
var
  I: Integer;
begin
  Result := ACurrent;
  if AFirst then
  begin
    for I := 0 to ACount - 1 do
      if IsSelectableRow(I, ASelectable) then
        Exit(I);
  end
  else
    for I := ACount - 1 downto 0 do
      if IsSelectableRow(I, ASelectable) then
        Exit(I);
end;

function MenuNavigateKey(AKey: Word; var AIndex: Integer; ACount,
  APageRows: Integer; const ASelectable: TMenuRowSelectable): Boolean;
begin
  Result := True;
  case AKey of
    vkUp: AIndex := MenuStepIndex(AIndex, ACount, -1, ASelectable);
    vkDown: AIndex := MenuStepIndex(AIndex, ACount, 1, ASelectable);
    vkHome: AIndex := MenuEdgeIndex(AIndex, ACount, True, ASelectable);
    vkEnd: AIndex := MenuEdgeIndex(AIndex, ACount, False, ASelectable);
    vkPrior: AIndex := MenuStepIndex(AIndex, ACount, -Max(APageRows, 1), ASelectable);
    vkNext: AIndex := MenuStepIndex(AIndex, ACount, Max(APageRows, 1), ASelectable);
  else
    Result := False;
  end;
end;

end.
