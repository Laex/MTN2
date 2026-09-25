unit uDualPanelTabs;

{ Dual Panel Tab Manager: helper routines for managing Panel Tabs (Left/Right)
  and Workspace Tabs. Extracted from uDualPanelWindow.pas to isolate tab state
  manipulation and tab hit-testing.

  Includes:
    - TDualPanelTabManager — class methods for tab lifecycle (create/close/reorder/navigate)
    - Tab caption formatting helpers (WorkspaceTabCaption, PanelTabCaption, …)
    - Hit-testing for workspace and panel tabs (HitWorkspaceTabAtCol, HitPanelTabAtCol)
    - PaintTabCloseMark — draws the 'x' glyph in a TTerminalGrid cell
}

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  uDualPanelTypes, uThemeTypes, uTerminalTypes, uVfsTypes;

const
  /// <summary>Close-button character inside tab captions (ASCII 'x').</summary>
  cTabCloseChar = 'x';

{ --- Caption helpers ------------------------------------------------------- }

/// <summary>Format workspace tab caption with optional close mark.
/// Example: '[Home]' or '[Home x]'.</summary>
function WorkspaceTabCaption(const ATitle: string; AShowClose: Boolean): string;

/// <summary>Format panel tab caption with optional close mark.
/// Example: '[ home ]' or '[ home x ]'.</summary>
function PanelTabCaption(const ATitle: string; AShowClose: Boolean): string;

/// <summary>Column index of the close mark within a tab caption string.
/// Returns -1 when AShowClose is False.</summary>
function TabCaptionCloseCol(ATabLeft: Integer; const ACap: string;
  AShowClose: Boolean; APanelStyle: Boolean): Integer;

/// <summary>Render the tab close mark character into AGrid at (ACol, ARow).</summary>
procedure PaintTabCloseMark(const AGrid: TTerminalGrid; ACol, ARow: Integer;
  AFg, ABg: TAlphaColor);

/// <summary>First column of the panel tab bar (after the left frame).</summary>
function PanelTabHeadX(const ABounds: TRectI): Integer;

/// <summary>Right edge tabs must stop drawing before (reserves a margin at
/// the panel's top-right corner) and the per-tab caption length budget for
/// APanel's tab bar inside ABounds — shared by drawing (DrawPanel) and
/// hit-testing (HitPanelTabAtCol) so a click always lands on what's
/// actually on screen, including the close mark, even once captions are
/// dynamically truncated (see VfsUriDirTabTitle).</summary>
procedure ComputePanelTabLayout(const APanel: TPanelState; const ABounds: TRectI;
  out ATabsRight, ATabMaxLen: Integer);

{ --- Hit-testing ----------------------------------------------------------- }

/// <summary>Find which workspace tab (if any) a column click falls on.
/// AWorkspaceTabs — the full workspace tab array.
/// AShowClose — whether close marks are visible.
/// Returns True when hit; sets AIndex and AIsClose.</summary>
function HitWorkspaceTabAtCol(const AWorkspaceTabs: TArray<TDualPanelWorkspaceTab>;
  ACol: Integer; out AIndex: Integer; out AIsClose: Boolean): Boolean;

/// <summary>Find which panel tab (if any) a column click within ABounds falls on.
/// ABounds — outer frame rect of the panel.
/// Returns True when hit; sets AIndex and AIsClose.</summary>
function HitPanelTabAtCol(const APanel: TPanelState; const ABounds: TRectI;
  ACol: Integer; out AIndex: Integer; out AIsClose: Boolean): Boolean;

{ --- Tab lifecycle --------------------------------------------------------- }

type
  TCloseWorkspaceKind = (cwkNone, cwkDocument, cwkTerminal, cwkPanels);
  TCloseWorkspaceIndexProc = procedure(AIndex: Integer) of object;

  TDualPanelEmbeddedHost = record
    CloseDocument: TCloseWorkspaceIndexProc;
    CloseTerminal: TCloseWorkspaceIndexProc;
    RemoveWorkspace: TCloseWorkspaceIndexProc;
  end;

  TDualPanelTabManager = class
  public
    class function CreateDefaultTab(AId: Cardinal; const ATitle, AURI: string): TTab;
    class function FindTabById(const ATabs: TArray<TTab>; AId: Cardinal): Integer;
    class function AddTab(var ATabs: TArray<TTab>; var ANextId: Cardinal;
      const ATitle, AURI: string): Integer;
    class function CloseTab(var ATabs: TArray<TTab>; var AActiveIndex: Integer;
      AIndexToClose: Integer): Boolean;
    class procedure NavigateTab(var ATab: TTab; const AURI: string;
      AAddToHistory: Boolean = True);
    class function CanGoBack(const ATab: TTab): Boolean;
    class function CanGoForward(const ATab: TTab): Boolean;
    class procedure GoBack(var ATab: TTab);
    class procedure GoForward(var ATab: TTab);
    /// <summary>Move tab AFrom → ATo; updates AActiveIndex.</summary>
    class function ReorderTab(var ATabs: TArray<TTab>; var AActiveIndex: Integer;
      AFrom, ATo: Integer): Boolean;
    /// <summary>Move workspace tab AFrom → ATo; updates AActiveIndex.</summary>
    class function ReorderWorkspace(var ATabs: TArray<TDualPanelWorkspaceTab>;
      var AActiveIndex: Integer; AFrom, ATo: Integer): Boolean;
    class function PanelsWorkspaceCount(
      const ATabs: TArray<TDualPanelWorkspaceTab>): Integer;
    class function FindFirstPanelsWorkspaceIndex(
      const ATabs: TArray<TDualPanelWorkspaceTab>): Integer;
    class function FindWorkspaceIndexById(
      const ATabs: TArray<TDualPanelWorkspaceTab>; AId: Cardinal): Integer;
    class function CanClosePanelsWorkspace(
      const ATabs: TArray<TDualPanelWorkspaceTab>): Boolean;
    class function NextWorkspaceIndex(AActive, ACount: Integer): Integer;
    class function PrevWorkspaceIndex(AActive, ACount: Integer): Integer;
    class function ActiveIndexAfterRemove(AActive, ARemoved, ANewCount,
      AReturnIdx: Integer): Integer;
    class function RemoveWorkspaceAt(var ATabs: TArray<TDualPanelWorkspaceTab>;
      AIndex: Integer): Boolean;
    class function ClonePanelsWorkspaceFrom(const ASrc: TDualPanelWorkspaceTab;
      var ANextId: Cardinal; AExistingCount: Integer): TDualPanelWorkspaceTab;
    class function FindDocumentWorkspaceIndex(
      const ATabs: TArray<TDualPanelWorkspaceTab>; const AURI: string;
      AViewOnly: Boolean): Integer;
    class function FindWorkspaceIndexByKindAndId(
      const ATabs: TArray<TDualPanelWorkspaceTab>; AKind: TWorkspaceKind;
      AId: Cardinal): Integer;
    class function WorkspaceInsertIndex(AActive, ACount: Integer): Integer;
    class function InsertWorkspaceAfterActive(
      var ATabs: TArray<TDualPanelWorkspaceTab>; var AActive: Integer;
      const AWs: TDualPanelWorkspaceTab): Integer;
    class function MakeEmbeddedWorkspaceTab(AId: Cardinal; const ATitle: string;
      AKind: TWorkspaceKind; AOriginId: Cardinal): TDualPanelWorkspaceTab;
    class function EmbeddedDocumentTitle(const AEditorCaption,
      AFallback: string): string;
    class function ClassifyCloseWorkspace(AIndex: Integer;
      const ATabs: TArray<TDualPanelWorkspaceTab>): TCloseWorkspaceKind;
    class procedure DispatchCloseWorkspace(const AHost: TDualPanelEmbeddedHost;
      AKind: TCloseWorkspaceKind; AIndex: Integer);
    class function ExportPanelsSession(
      const AState: TDualPanelWindowState): TDualPanelWindowState;
    class function FilterImportedSession(
      const AState: TDualPanelWindowState): TDualPanelWindowState;
    class function NextIdAfterSession(const AState: TDualPanelWindowState): Cardinal;
    class procedure RestoreBothVisibleIfHidden(var AWs: TDualPanelWorkspaceTab);
  end;

implementation

uses
  uStrings;

{ =========================================================================
  Caption helpers
  ========================================================================= }

function WorkspaceTabCaption(const ATitle: string; AShowClose: Boolean): string;
begin
  if AShowClose then
    Result := '[' + ATitle + ' ' + cTabCloseChar + ']'
  else
    Result := '[' + ATitle + ']';
end;

function PanelTabCaption(const ATitle: string; AShowClose: Boolean): string;
begin
  if AShowClose then
    Result := '[ ' + ATitle + ' ' + cTabCloseChar + ' ]'
  else
    Result := '[ ' + ATitle + ' ]';
end;

function TabCaptionCloseCol(ATabLeft: Integer; const ACap: string;
  AShowClose: Boolean; APanelStyle: Boolean): Integer;
begin
  // Close mark sits just before the trailing ']' (panel captions have a space after it).
  Result := -1;
  if not AShowClose then
    Exit;
  if APanelStyle then
    Result := ATabLeft + Length(ACap) - 3
  else
    Result := ATabLeft + Length(ACap) - 2;
end;

procedure PaintTabCloseMark(const AGrid: TTerminalGrid; ACol, ARow: Integer;
  AFg, ABg: TAlphaColor);
begin
  if ACol < 0 then
    Exit;
  DrawGridChar(AGrid, ACol, ARow, cTabCloseChar, AFg, ABg);
end;

function PanelTabHeadX(const ABounds: TRectI): Integer;
begin
  Result := ABounds.Left + 1;
end;

procedure ComputePanelTabLayout(const APanel: TPanelState; const ABounds: TRectI;
  out ATabsRight, ATabMaxLen: Integer);
const
  cReservedRightCols = 5;
var
  TabCount, ChromeLen: Integer;
begin
  ATabsRight := ABounds.Right - cReservedRightCols;
  TabCount := Max(Length(APanel.Tabs), 1);
  ChromeLen := 4; // '[ ' + ' ]'
  if Length(APanel.Tabs) > 1 then
    Inc(ChromeLen, 2); // ' x'
  Inc(ChromeLen); // separator before the next tab
  ATabMaxLen := Max((ATabsRight - PanelTabHeadX(ABounds)) div TabCount - ChromeLen, 3);
end;

{ =========================================================================
  Hit-testing
  ========================================================================= }

function HitWorkspaceTabAtCol(const AWorkspaceTabs: TArray<TDualPanelWorkspaceTab>;
  ACol: Integer; out AIndex: Integer; out AIsClose: Boolean): Boolean;
var
  I, X, CloseCol: Integer;
  Cap: string;
  ShowClose: Boolean;
begin
  Result   := False;
  AIndex   := -1;
  AIsClose := False;
  ShowClose := Length(AWorkspaceTabs) > 1;
  X := 0;
  for I := 0 to High(AWorkspaceTabs) do
  begin
    Cap := WorkspaceTabCaption(AWorkspaceTabs[I].Title, ShowClose);
    if (ACol >= X) and (ACol < X + Length(Cap)) then
    begin
      CloseCol := TabCaptionCloseCol(X, Cap, ShowClose, False);
      AIndex   := I;
      AIsClose := ShowClose and (ACol = CloseCol);
      Result   := True;
      Exit;
    end;
    Inc(X, Length(Cap) + 1);
  end;
end;

function HitPanelTabAtCol(const APanel: TPanelState; const ABounds: TRectI;
  ACol: Integer; out AIndex: Integer; out AIsClose: Boolean): Boolean;
var
  I, HeadX, CloseCol, TabsRight, TabMaxLen: Integer;
  Cap: string;
  ShowClose: Boolean;
begin
  Result   := False;
  AIndex   := -1;
  AIsClose := False;
  ShowClose := Length(APanel.Tabs) > 1;
  HeadX := PanelTabHeadX(ABounds);
  ComputePanelTabLayout(APanel, ABounds, TabsRight, TabMaxLen);
  for I := 0 to High(APanel.Tabs) do
  begin
    Cap := PanelTabCaption(
      VfsUriDirTabTitle(APanel.Tabs[I].CurrentURI, TabMaxLen), ShowClose);
    if HeadX + Length(Cap) >= TabsRight then
      Break;
    if (ACol >= HeadX) and (ACol < HeadX + Length(Cap)) then
    begin
      CloseCol := TabCaptionCloseCol(HeadX, Cap, ShowClose, True);
      AIndex   := I;
      AIsClose := ShowClose and (ACol = CloseCol);
      Result   := True;
      Exit;
    end;
    Inc(HeadX, Length(Cap));
    if (I < High(APanel.Tabs)) and (HeadX < TabsRight) then
      Inc(HeadX);
  end;
end;

{ =========================================================================
  TDualPanelTabManager
  ========================================================================= }

class function TDualPanelTabManager.CreateDefaultTab(AId: Cardinal;
  const ATitle, AURI: string): TTab;
begin
  Result.Id := AId;
  Result.Title := ATitle;
  Result.CurrentURI := AURI;
  SetLength(Result.History, 1);
  Result.History[0] := AURI;
  Result.HistoryIndex := 0;
  Result.CursorIndex := 0;
  Result.ScrollOffset := 0;
  SetLength(Result.SelectedURIs, 0);
  Result.WorkspaceBackUri := '';
  Result.WorkspaceBackTarget := '';
end;

class function TDualPanelTabManager.FindTabById(const ATabs: TArray<TTab>;
  AId: Cardinal): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ATabs) do
  begin
    if ATabs[I].Id = AId then
      Exit(I);
  end;
  Result := -1;
end;

class function TDualPanelTabManager.AddTab(var ATabs: TArray<TTab>;
  var ANextId: Cardinal; const ATitle, AURI: string): Integer;
var
  LIndex: Integer;
begin
  Inc(ANextId);
  LIndex := Length(ATabs);
  SetLength(ATabs, LIndex + 1);
  ATabs[LIndex] := CreateDefaultTab(ANextId, ATitle, AURI);
  Result := LIndex;
end;

class function TDualPanelTabManager.CloseTab(var ATabs: TArray<TTab>;
  var AActiveIndex: Integer; AIndexToClose: Integer): Boolean;
var
  I, LCount: Integer;
begin
  LCount := Length(ATabs);
  // Do not close the last tab
  if LCount <= 1 then
    Exit(False);

  if (AIndexToClose < 0) or (AIndexToClose >= LCount) then
    Exit(False);

  for I := AIndexToClose to LCount - 2 do
    ATabs[I] := ATabs[I + 1];

  SetLength(ATabs, LCount - 1);

  if AActiveIndex >= Length(ATabs) then
    AActiveIndex := Length(ATabs) - 1;

  Result := True;
end;

class procedure TDualPanelTabManager.NavigateTab(var ATab: TTab;
  const AURI: string; AAddToHistory: Boolean);
begin
  ATab.CurrentURI := AURI;
  if AAddToHistory then
  begin
    // Truncate forward history if navigating to a new URI
    SetLength(ATab.History, ATab.HistoryIndex + 1);
    SetLength(ATab.History, ATab.HistoryIndex + 2);
    Inc(ATab.HistoryIndex);
    ATab.History[ATab.HistoryIndex] := AURI;
  end;
  ATab.CursorIndex := 0;
  ATab.ScrollOffset := 0;
  SetLength(ATab.SelectedURIs, 0);
end;

class function TDualPanelTabManager.CanGoBack(const ATab: TTab): Boolean;
begin
  Result := ATab.HistoryIndex > 0;
end;

class function TDualPanelTabManager.CanGoForward(const ATab: TTab): Boolean;
begin
  Result := ATab.HistoryIndex < High(ATab.History);
end;

class procedure TDualPanelTabManager.GoBack(var ATab: TTab);
begin
  if CanGoBack(ATab) then
  begin
    Dec(ATab.HistoryIndex);
    ATab.CurrentURI := ATab.History[ATab.HistoryIndex];
    ATab.CursorIndex := 0;
    ATab.ScrollOffset := 0;
  end;
end;

class procedure TDualPanelTabManager.GoForward(var ATab: TTab);
begin
  if CanGoForward(ATab) then
  begin
    Inc(ATab.HistoryIndex);
    ATab.CurrentURI := ATab.History[ATab.HistoryIndex];
    ATab.CursorIndex := 0;
    ATab.ScrollOffset := 0;
  end;
end;

procedure AdjustActiveAfterReorder(var AActiveIndex: Integer; AFrom, ATo: Integer);
begin
  if AActiveIndex = AFrom then
    AActiveIndex := ATo
  else if (AFrom < ATo) and (AActiveIndex > AFrom) and (AActiveIndex <= ATo) then
    Dec(AActiveIndex)
  else if (AFrom > ATo) and (AActiveIndex >= ATo) and (AActiveIndex < AFrom) then
    Inc(AActiveIndex);
end;

class function TDualPanelTabManager.ReorderTab(var ATabs: TArray<TTab>;
  var AActiveIndex: Integer; AFrom, ATo: Integer): Boolean;
var
  Tmp: TTab;
  I: Integer;
begin
  Result := False;
  if (AFrom = ATo) or (AFrom < 0) or (ATo < 0) or
     (AFrom > High(ATabs)) or (ATo > High(ATabs)) then
    Exit;
  Tmp := ATabs[AFrom];
  if AFrom < ATo then
    for I := AFrom to ATo - 1 do
      ATabs[I] := ATabs[I + 1]
  else
    for I := AFrom downto ATo + 1 do
      ATabs[I] := ATabs[I - 1];
  ATabs[ATo] := Tmp;
  AdjustActiveAfterReorder(AActiveIndex, AFrom, ATo);
  Result := True;
end;

class function TDualPanelTabManager.ReorderWorkspace(
  var ATabs: TArray<TDualPanelWorkspaceTab>; var AActiveIndex: Integer;
  AFrom, ATo: Integer): Boolean;
var
  Tmp: TDualPanelWorkspaceTab;
  I: Integer;
begin
  Result := False;
  if (AFrom = ATo) or (AFrom < 0) or (ATo < 0) or
     (AFrom > High(ATabs)) or (ATo > High(ATabs)) then
    Exit;
  Tmp := ATabs[AFrom];
  if AFrom < ATo then
    for I := AFrom to ATo - 1 do
      ATabs[I] := ATabs[I + 1]
  else
    for I := AFrom downto ATo + 1 do
      ATabs[I] := ATabs[I - 1];
  ATabs[ATo] := Tmp;
  AdjustActiveAfterReorder(AActiveIndex, AFrom, ATo);
  Result := True;
end;

class function TDualPanelTabManager.PanelsWorkspaceCount(
  const ATabs: TArray<TDualPanelWorkspaceTab>): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(ATabs) do
    if ATabs[I].Kind = wkPanels then
      Inc(Result);
end;

class function TDualPanelTabManager.FindFirstPanelsWorkspaceIndex(
  const ATabs: TArray<TDualPanelWorkspaceTab>): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ATabs) do
    if ATabs[I].Kind = wkPanels then
      Exit(I);
  Result := -1;
end;

class function TDualPanelTabManager.FindWorkspaceIndexById(
  const ATabs: TArray<TDualPanelWorkspaceTab>; AId: Cardinal): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ATabs) do
    if ATabs[I].Id = AId then
      Exit(I);
  Result := -1;
end;

class function TDualPanelTabManager.CanClosePanelsWorkspace(
  const ATabs: TArray<TDualPanelWorkspaceTab>): Boolean;
begin
  Result := (PanelsWorkspaceCount(ATabs) > 1) and (Length(ATabs) > 1);
end;

class function TDualPanelTabManager.NextWorkspaceIndex(AActive, ACount: Integer): Integer;
begin
  if ACount <= 1 then
    Result := AActive
  else
    Result := (AActive + 1) mod ACount;
end;

class function TDualPanelTabManager.PrevWorkspaceIndex(AActive, ACount: Integer): Integer;
begin
  if ACount <= 1 then
    Result := AActive
  else if AActive - 1 < 0 then
    Result := ACount - 1
  else
    Result := AActive - 1;
end;

class function TDualPanelTabManager.ActiveIndexAfterRemove(AActive, ARemoved,
  ANewCount, AReturnIdx: Integer): Integer;
begin
  if AReturnIdx >= 0 then
    Result := AReturnIdx
  else if AActive > ARemoved then
    Result := AActive - 1
  else if AActive >= ANewCount then
    Result := ANewCount - 1
  else
    Result := AActive;
  if Result < 0 then
    Result := 0;
end;

class function TDualPanelTabManager.RemoveWorkspaceAt(
  var ATabs: TArray<TDualPanelWorkspaceTab>; AIndex: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (AIndex < 0) or (AIndex > High(ATabs)) then
    Exit;
  for I := AIndex to High(ATabs) - 1 do
    ATabs[I] := ATabs[I + 1];
  SetLength(ATabs, Length(ATabs) - 1);
  Result := True;
end;

class function TDualPanelTabManager.ClonePanelsWorkspaceFrom(
  const ASrc: TDualPanelWorkspaceTab; var ANextId: Cardinal;
  AExistingCount: Integer): TDualPanelWorkspaceTab;
begin
  Result := Default(TDualPanelWorkspaceTab);
  Result.Id := ANextId;
  Inc(ANextId);
  Result.Kind := wkPanels;
  Result.DocURI := '';
  Result.ViewOnly := False;
  Result.OriginWorkspaceId := 0;
  Result.State.ActiveSide := ASrc.State.ActiveSide;
  Result.State.LeftVisible := ASrc.State.LeftVisible;
  Result.State.RightVisible := ASrc.State.RightVisible;
  Result.State.LeftPanel := ClonePanelState(ASrc.State.LeftPanel, ANextId);
  Result.State.RightPanel := ClonePanelState(ASrc.State.RightPanel, ANextId);
  Result.Title := MakePanelsWorkspaceTitle(Result.State);
  if Result.Title = '' then
    Result.Title := T('ui.workspace.session', 'Session %d', [AExistingCount + 1]);
end;

class function TDualPanelTabManager.FindDocumentWorkspaceIndex(
  const ATabs: TArray<TDualPanelWorkspaceTab>; const AURI: string;
  AViewOnly: Boolean): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ATabs) do
    if (ATabs[I].Kind = wkDocument) and
       SameVfsUri(ATabs[I].DocURI, AURI) and
       (ATabs[I].ViewOnly = AViewOnly) then
      Exit(I);
  Result := -1;
end;

class function TDualPanelTabManager.FindWorkspaceIndexByKindAndId(
  const ATabs: TArray<TDualPanelWorkspaceTab>; AKind: TWorkspaceKind;
  AId: Cardinal): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ATabs) do
    if (ATabs[I].Kind = AKind) and (ATabs[I].Id = AId) then
      Exit(I);
  Result := -1;
end;

class function TDualPanelTabManager.WorkspaceInsertIndex(AActive, ACount: Integer): Integer;
begin
  Result := AActive + 1;
  if Result < 0 then
    Result := 0;
  if Result > ACount then
    Result := ACount;
end;

class function TDualPanelTabManager.InsertWorkspaceAfterActive(
  var ATabs: TArray<TDualPanelWorkspaceTab>; var AActive: Integer;
  const AWs: TDualPanelWorkspaceTab): Integer;
var
  N: Integer;
begin
  N := Length(ATabs);
  Result := WorkspaceInsertIndex(AActive, N);
  SetLength(ATabs, N + 1);
  while N > Result do
  begin
    ATabs[N] := ATabs[N - 1];
    Dec(N);
  end;
  ATabs[Result] := AWs;
  AActive := Result;
end;

class function TDualPanelTabManager.MakeEmbeddedWorkspaceTab(AId: Cardinal;
  const ATitle: string; AKind: TWorkspaceKind; AOriginId: Cardinal): TDualPanelWorkspaceTab;
begin
  Result := Default(TDualPanelWorkspaceTab);
  Result.Id := AId;
  Result.Title := ATitle;
  Result.Kind := AKind;
  Result.OriginWorkspaceId := AOriginId;
  Result.State.ActiveSide := psLeft;
  Result.State.LeftVisible := True;
  Result.State.RightVisible := True;
  Result.State.LeftPanel.ActiveTabIndex := 0;
  SetLength(Result.State.LeftPanel.Tabs, 0);
  ClearPanelDriveDirs(Result.State.LeftPanel.DriveDirs);
  Result.State.RightPanel.ActiveTabIndex := 0;
  SetLength(Result.State.RightPanel.Tabs, 0);
  ClearPanelDriveDirs(Result.State.RightPanel.DriveDirs);
end;

class function TDualPanelTabManager.EmbeddedDocumentTitle(const AEditorCaption,
  AFallback: string): string;
begin
  Result := AEditorCaption;
  if Result = '' then
    Result := AFallback;
end;

class function TDualPanelTabManager.ClassifyCloseWorkspace(AIndex: Integer;
  const ATabs: TArray<TDualPanelWorkspaceTab>): TCloseWorkspaceKind;
begin
  if (AIndex < 0) or (AIndex > High(ATabs)) then
    Exit(cwkNone);
  case ATabs[AIndex].Kind of
    wkDocument:
      Result := cwkDocument;
    wkTerminal:
      Result := cwkTerminal;
  else
    if CanClosePanelsWorkspace(ATabs) then
      Result := cwkPanels
    else
      Result := cwkNone;
  end;
end;

class procedure TDualPanelTabManager.DispatchCloseWorkspace(
  const AHost: TDualPanelEmbeddedHost; AKind: TCloseWorkspaceKind; AIndex: Integer);
begin
  case AKind of
    cwkDocument:
      AHost.CloseDocument(AIndex);
    cwkTerminal:
      AHost.CloseTerminal(AIndex);
    cwkPanels:
      AHost.RemoveWorkspace(AIndex);
  end;
end;

class function TDualPanelTabManager.ExportPanelsSession(
  const AState: TDualPanelWindowState): TDualPanelWindowState;
var
  I, N, ActivePanels: Integer;
begin
  Result.ActiveWorkspaceIndex := 0;
  SetLength(Result.WorkspaceTabs, 0);
  N := 0;
  ActivePanels := 0;
  for I := 0 to High(AState.WorkspaceTabs) do
  begin
    if AState.WorkspaceTabs[I].Kind <> wkPanels then
      Continue;
    SetLength(Result.WorkspaceTabs, N + 1);
    Result.WorkspaceTabs[N] := AState.WorkspaceTabs[I];
    if I <= AState.ActiveWorkspaceIndex then
      ActivePanels := N;
    Inc(N);
  end;
  if Length(Result.WorkspaceTabs) = 0 then
    Exit(AState);
  Result.ActiveWorkspaceIndex := ActivePanels;
end;

class function TDualPanelTabManager.FilterImportedSession(
  const AState: TDualPanelWindowState): TDualPanelWindowState;
var
  W, N: Integer;
  Ws: TDualPanelWorkspaceTab;
begin
  Result.ActiveWorkspaceIndex := 0;
  SetLength(Result.WorkspaceTabs, 0);
  N := 0;
  for W := 0 to High(AState.WorkspaceTabs) do
  begin
    Ws := AState.WorkspaceTabs[W];
    if (Ws.Kind = wkDocument) or (Ws.Kind = wkTerminal) then
      Continue;
    Ws.Kind := wkPanels;
    Ws.DocURI := '';
    Ws.ViewOnly := False;
    Ws.OriginWorkspaceId := 0;
    SetLength(Result.WorkspaceTabs, N + 1);
    Result.WorkspaceTabs[N] := Ws;
    if W <= AState.ActiveWorkspaceIndex then
      Result.ActiveWorkspaceIndex := N;
    Inc(N);
  end;
end;

class function TDualPanelTabManager.NextIdAfterSession(
  const AState: TDualPanelWindowState): Cardinal;
var
  W, I: Integer;
  Panel: TPanelState;
begin
  Result := 1;
  for W := 0 to High(AState.WorkspaceTabs) do
  begin
    if AState.WorkspaceTabs[W].Id >= Result then
      Result := AState.WorkspaceTabs[W].Id + 1;
    Panel := AState.WorkspaceTabs[W].State.LeftPanel;
    for I := 0 to High(Panel.Tabs) do
      if Panel.Tabs[I].Id >= Result then
        Result := Panel.Tabs[I].Id + 1;
    Panel := AState.WorkspaceTabs[W].State.RightPanel;
    for I := 0 to High(Panel.Tabs) do
      if Panel.Tabs[I].Id >= Result then
        Result := Panel.Tabs[I].Id + 1;
  end;
end;

class procedure TDualPanelTabManager.RestoreBothVisibleIfHidden(
  var AWs: TDualPanelWorkspaceTab);
begin
  if not AWs.State.LeftVisible and not AWs.State.RightVisible then
  begin
    AWs.State.LeftVisible := True;
    AWs.State.RightVisible := True;
  end;
end;

end.
