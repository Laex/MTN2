unit uChromeRows;

{ Which chrome the screen shows: the native window title bar, the menu bar
  on top, the F-key bar and the status line at the bottom ("Font / screen" dialog, Ctrl+B for the
  F-key bar). Every window that draws or hit-tests these rows takes their
  positions from here, so hiding one gives its row to the content. }

interface

var
  GShowTitleBar: Boolean = True;
  GShowMenuBar: Boolean = True;
  GShowKeyBar: Boolean = True;
  GShowStatusLine: Boolean = True;

/// <summary>Rows the menu bar takes on top: 1 or 0.</summary>
function MenuBarRows: Integer;
/// <summary>Rows the F-key bar and the status line take at the bottom.</summary>
function ChromeBottomRows: Integer;
/// <summary>Row of the F-key bar in AHeight rows, -1 when it is hidden.</summary>
function KeyBarRow(AHeight: Integer): Integer;
/// <summary>Row of the status line in AHeight rows, -1 when it is hidden.</summary>
function StatusLineRow(AHeight: Integer): Integer;
/// <summary>Panel window: the workspace tab bar, right under the menu bar.</summary>
function TabBarRow: Integer;
/// <summary>Panel window: first row of the panels, a document or a terminal.</summary>
function ContentTopRow: Integer;
/// <summary>Panel window: the command line, right above the bottom rows.</summary>
function CmdLineRow(AHeight: Integer): Integer;

implementation

function MenuBarRows: Integer;
begin
  Result := Ord(GShowMenuBar);
end;

function ChromeBottomRows: Integer;
begin
  Result := Ord(GShowKeyBar) + Ord(GShowStatusLine);
end;

function KeyBarRow(AHeight: Integer): Integer;
begin
  if not GShowKeyBar then
    Exit(-1);
  Result := AHeight - 1 - Ord(GShowStatusLine);
end;

function StatusLineRow(AHeight: Integer): Integer;
begin
  if not GShowStatusLine then
    Exit(-1);
  Result := AHeight - 1;
end;

function TabBarRow: Integer;
begin
  Result := MenuBarRows;
end;

function ContentTopRow: Integer;
begin
  Result := TabBarRow + 1;
end;

function CmdLineRow(AHeight: Integer): Integer;
begin
  Result := AHeight - 1 - ChromeBottomRows;
end;

end.
