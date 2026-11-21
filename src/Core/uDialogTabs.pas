unit uDialogTabs;

{ Tab strip of a protocol 2.0 dialog: which controls a page shows and where each
  caption of the strip sits. Shared by layout, drawing, mouse and keys. }

interface

uses
  System.SysUtils, uDialogTypes;

type
  /// <summary>One caption of the strip: Left is a cell offset from the strip's
  /// left edge.</summary>
  TDialogTabSpan = record
    Left, Width: Integer;
  end;

/// <summary>Index of the dialog's tab strip, -1 without one. Only the first
/// strip counts.</summary>
function DialogTabStripIndex(const AControls: TArray<TDialogControl>): Integer;

/// <summary>1-based page the strip shows; 0 without a strip.</summary>
function DialogActiveTabPage(const AControls: TArray<TDialogControl>): Integer;

/// <summary>True for a control of a page other than the shown one.</summary>
function DialogControlHiddenByTab(const AControls: TArray<TDialogControl>;
  AIndex: Integer): Boolean;

/// <summary>Cells the captions of a strip take, from its left edge. A caption
/// is drawn as "[ Name ]" for the shown page and "  Name  " for the others, so
/// the strip keeps its width when the page changes.</summary>
function DialogTabSpans(const AStrip: TDialogControl): TArray<TDialogTabSpan>;

/// <summary>Page under cell offset AOffset of the strip, -1 between captions.</summary>
function DialogTabAtOffset(const AStrip: TDialogControl; AOffset: Integer): Integer;

/// <summary>Page after moving ADelta pages from ASelected, wrapping around.</summary>
function DialogTabStep(ASelected, ACount, ADelta: Integer): Integer;

implementation

uses
  uCharWidth;

function DialogTabStripIndex(const AControls: TArray<TDialogControl>): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AControls) do
    if AControls[I].Kind = dckTab then
      Exit(I);
  Result := -1;
end;

function DialogActiveTabPage(const AControls: TArray<TDialogControl>): Integer;
var
  S: Integer;
begin
  S := DialogTabStripIndex(AControls);
  if (S < 0) or (Length(AControls[S].Items) = 0) then
    Result := 0
  else
    Result := AControls[S].SelectedIndex + 1;
end;

function DialogControlHiddenByTab(const AControls: TArray<TDialogControl>;
  AIndex: Integer): Boolean;
var
  Page: Integer;
begin
  Result := False;
  if (AIndex < 0) or (AIndex > High(AControls)) or (AControls[AIndex].TabPage <= 0) then
    Exit;
  Page := DialogActiveTabPage(AControls);
  Result := (Page > 0) and (AControls[AIndex].TabPage <> Page);
end;

function DialogTabSpans(const AStrip: TDialogControl): TArray<TDialogTabSpan>;
var
  I, X: Integer;
begin
  SetLength(Result, Length(AStrip.Items));
  X := 0;
  for I := 0 to High(AStrip.Items) do
  begin
    Result[I].Left := X;
    Result[I].Width := TextDisplayWidth(AStrip.Items[I]) + 4;
    Inc(X, Result[I].Width);
  end;
end;

function DialogTabAtOffset(const AStrip: TDialogControl; AOffset: Integer): Integer;
var
  Spans: TArray<TDialogTabSpan>;
  I: Integer;
begin
  Spans := DialogTabSpans(AStrip);
  for I := 0 to High(Spans) do
    if (AOffset >= Spans[I].Left) and (AOffset < Spans[I].Left + Spans[I].Width) then
      Exit(I);
  Result := -1;
end;

function DialogTabStep(ASelected, ACount, ADelta: Integer): Integer;
begin
  if ACount <= 0 then
    Exit(0);
  Result := ((ASelected + ADelta) mod ACount + ACount) mod ACount;
end;

end.
