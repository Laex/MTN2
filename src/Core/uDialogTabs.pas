unit uDialogTabs;

{ Tab strip of a protocol 2.0 dialog: which controls a page shows and where each
  caption of the strip sits. Shared by layout, drawing, mouse and keys. }

interface

uses
  System.SysUtils, System.Math, uDialogTypes;

type
  /// <summary>One caption of the strip: Left is a cell offset from the strip's
  /// left edge.</summary>
  TDialogTabSpan = record
    Left, Width: Integer;
  end;

/// <summary>Index of the dialog's tab strip, -1 without one. Only the first
/// strip counts.</summary>
function DialogTabStripIndex(const AControls: TArray<TDialogControl>): Integer;

/// <summary>1-based page the strip shows; 0 without a strip, -1 when its captions
/// are all gone (no page is shown).</summary>
function DialogActiveTabPage(const AControls: TArray<TDialogControl>): Integer;

/// <summary>Caption of the strip that shows 1-based APage, -1 when none does.</summary>
function DialogTabItemOfPage(const AStrip: TDialogControl; APage: Integer): Integer;

/// <summary>True for a control of a page other than the shown one.</summary>
function DialogControlHiddenByTab(const AControls: TArray<TDialogControl>;
  AIndex: Integer): Boolean;

/// <summary>Cells the captions of a strip take, from its left edge. A caption
/// is drawn as "[ Name ]" for the shown page and "  Name  " for the others, so
/// the strip keeps its width when the page changes.</summary>
function DialogTabSpans(const AStrip: TDialogControl): TArray<TDialogTabSpan>;

/// <summary>Page under cell offset AOffset of the strip, -1 between captions.</summary>
function DialogTabAtOffset(const AStrip: TDialogControl; AOffset: Integer): Integer;

/// <summary>Page of a vertical strip on row ARow (from its top edge), -1 below the last.</summary>
function DialogTabAtRow(const AStrip: TDialogControl; ARow: Integer): Integer;

/// <summary>First caption of a vertical strip of ARows rows: ATop, moved as
/// little as keeps ASelected in view.</summary>
function DialogTabScrollTop(ATop, ASelected, ARows, ACount: Integer): Integer;

/// <summary>Widest caption of a strip plus the cells its marker takes.</summary>
function DialogTabColumnWidth(const AStrip: TDialogControl): Integer;

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
  if S < 0 then
    Exit(0);
  if Length(AControls[S].Items) = 0 then
    Exit(-1);
  if (AControls[S].SelectedIndex >= 0) and
     (AControls[S].SelectedIndex <= High(AControls[S].TabPages)) then
    Result := AControls[S].TabPages[AControls[S].SelectedIndex]
  else
    Result := AControls[S].SelectedIndex + 1;
end;

function DialogTabItemOfPage(const AStrip: TDialogControl; APage: Integer): Integer;
var
  I: Integer;
begin
  if Length(AStrip.TabPages) = 0 then
  begin
    if (APage >= 1) and (APage <= Length(AStrip.Items)) then
      Exit(APage - 1);
    Exit(-1);
  end;
  for I := 0 to High(AStrip.TabPages) do
    if AStrip.TabPages[I] = APage then
      Exit(I);
  Result := -1;
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
  Result := (Page <> 0) and (AControls[AIndex].TabPage <> Page);
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

function DialogTabAtRow(const AStrip: TDialogControl; ARow: Integer): Integer;
begin
  if (ARow >= 0) and (AStrip.TabTop + ARow <= High(AStrip.Items)) then
    Result := AStrip.TabTop + ARow
  else
    Result := -1;
end;

function DialogTabScrollTop(ATop, ASelected, ARows, ACount: Integer): Integer;
begin
  Result := Min(ATop, ASelected);
  Result := Max(Result, ASelected - ARows + 1);
  Result := Max(Min(Result, ACount - ARows), 0);
end;

function DialogTabColumnWidth(const AStrip: TDialogControl): Integer;
var
  I: Integer;
begin
  Result := 1;
  for I := 0 to High(AStrip.Items) do
    Result := Max(Result, TextDisplayWidth(AStrip.Items[I]) + 2);
end;

function DialogTabStep(ASelected, ACount, ADelta: Integer): Integer;
begin
  if ACount <= 0 then
    Exit(0);
  Result := ((ASelected + ADelta) mod ACount + ACount) mod ACount;
end;

end.
