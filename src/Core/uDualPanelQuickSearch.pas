unit uDualPanelQuickSearch;

{ Alt quick search on the file panels: the typed text, the optional filter
  that hides other names, and where the cursor goes. The window keeps the
  keymap entry points and the panel models. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDualPanelTypes;

type
  IDualPanelQuickSearchHost = interface
    ['{E7A1C4D8-2B60-4F15-9D33-8C5E1A7B0F42}']
    function ActiveWorkspace: TDualPanelWorkspaceTab;
    function ActivePanel(var AWs: TDualPanelWorkspaceTab): TPanelState;
    procedure SetActivePanel(var AWs: TDualPanelWorkspaceTab; const APanel: TPanelState);
    function RowsForSide(ASide: TPanelSide): TPanelRows;
    procedure SetNeedle(ASide: TPanelSide; const ANeedle: string; AFuzzy: Boolean);
    procedure SaveActiveWorkspace(const AWs: TDualPanelWorkspaceTab);
    function ListViewHeight: Integer;
    function ListColCount(ASide: TPanelSide): Integer;
    procedure ClampCursor(ASide: TPanelSide);
    procedure NotifyChanged;
  end;

  TDualPanelQuickSearch = class
  private
    FHost: IDualPanelQuickSearchHost;
    FActive: Boolean;
    // Opened by the Quick search action, with no Alt held: it lingers like a
    // sticky search whatever the setting says.
    FLatched: Boolean;
    FText: string;
    FFilterSide: TPanelSide;
    FFiltering: Boolean;
    FSticky: Boolean;
    FKeepEmpty: Boolean;
    FFilter: Boolean;
    FKeepFilter: Boolean;
    FFuzzy: Boolean;
    procedure SetNeedle(const AText: string);
    procedure FocusFirstFilteredRow;
  public
    constructor Create(const AHost: IDualPanelQuickSearchHost);
    procedure Clear;
    procedure Start;
    function Lingers: Boolean;
    function HandleInput(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
    /// <summary>Alt was released. Clears a search that lives only while Alt
    /// is held and returns True when the screen must be drawn again.</summary>
    function TakeAltRelease: Boolean;
    /// <summary>A click drops the search, unless the filter is meant to
    /// survive Enter and a click.</summary>
    function ClearsOnClick: Boolean;
    property Active: Boolean read FActive;
    property Text: string read FText;
    property Sticky: Boolean read FSticky write FSticky;
    property KeepEmpty: Boolean read FKeepEmpty write FKeepEmpty;
    property Filter: Boolean read FFilter write FFilter;
    property KeepFilter: Boolean read FKeepFilter write FKeepFilter;
    property Fuzzy: Boolean read FFuzzy write FFuzzy;
  end;

implementation

uses
  System.Math,
  uDualPanelInput, uPanelColumns;

constructor TDualPanelQuickSearch.Create(const AHost: IDualPanelQuickSearchHost);
begin
  inherited Create;
  FHost := AHost;
end;

procedure TDualPanelQuickSearch.SetNeedle(const AText: string);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Keep: string;
  I: Integer;
begin
  if not FFiltering and (AText = '') then
    Exit;
  // Ending the filter keeps the cursor on the same file, not on the same row.
  Keep := '';
  if FFiltering and (AText = '') then
  begin
    Ws := FHost.ActiveWorkspace;
    if Ws.State.ActiveSide = FFilterSide then
    begin
      Panel := FHost.ActivePanel(Ws);
      Tab := ActiveTab(Panel);
      Rows := FHost.RowsForSide(FFilterSide);
      if (Tab.CursorIndex >= 0) and (Tab.CursorIndex <= High(Rows)) then
        Keep := Rows[Tab.CursorIndex].Text;
    end;
  end;
  if FFiltering and (FFilterSide <> FHost.ActiveWorkspace.State.ActiveSide) then
    FHost.SetNeedle(FFilterSide, '', False);
  FFilterSide := FHost.ActiveWorkspace.State.ActiveSide;
  FHost.SetNeedle(FFilterSide, AText, FFuzzy);
  FFiltering := AText <> '';
  if Keep <> '' then
  begin
    Ws := FHost.ActiveWorkspace;
    Panel := FHost.ActivePanel(Ws);
    Tab := ActiveTab(Panel);
    Rows := FHost.RowsForSide(Ws.State.ActiveSide);
    for I := 0 to High(Rows) do
      if Rows[I].Text = Keep then
      begin
        Tab.CursorIndex := I;
        EnsurePanelCursorVisible(Tab, Length(Rows), Max(FHost.ListViewHeight, 1),
          FHost.ListColCount(Ws.State.ActiveSide));
        SetActiveTab(Panel, Tab);
        FHost.SetActivePanel(Ws, Panel);
        FHost.SaveActiveWorkspace(Ws);
        Break;
      end;
  end;
end;

procedure TDualPanelQuickSearch.FocusFirstFilteredRow;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  I: Integer;
begin
  Ws := FHost.ActiveWorkspace;
  Panel := FHost.ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  Rows := FHost.RowsForSide(Ws.State.ActiveSide);
  for I := 0 to High(Rows) do
    if not Rows[I].IsParent then
    begin
      Tab.CursorIndex := I;
      EnsurePanelCursorVisible(Tab, Length(Rows), Max(FHost.ListViewHeight, 1),
        FHost.ListColCount(Ws.State.ActiveSide));
      SetActiveTab(Panel, Tab);
      FHost.SetActivePanel(Ws, Panel);
      FHost.SaveActiveWorkspace(Ws);
      Exit;
    end;
  FHost.ClampCursor(Ws.State.ActiveSide);
end;

procedure TDualPanelQuickSearch.Clear;
begin
  if FFiltering then
    SetNeedle('');
  if not FActive and (FText = '') then
    Exit;
  FActive := False;
  FLatched := False;
  FText := '';
  FHost.NotifyChanged;
end;

function TDualPanelQuickSearch.Lingers: Boolean;
begin
  // A filtering search stays open after Alt is released: Esc or Enter is
  // the way to remove the filter.
  Result := FSticky or FLatched or FFilter;
end;

procedure TDualPanelQuickSearch.Start;
begin
  if FHost.ActiveWorkspace.Kind <> wkPanels then
    Exit;
  FActive := True;
  FLatched := True;
  FText := '';
  FHost.NotifyChanged;
end;

function TDualPanelQuickSearch.HandleInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Ch: Char;
begin
  Result := True;
  // A sticky search ends on Ctrl chords and on keys that are not text, Backspace
  // or Up / Down; the key itself then acts as usual.
  if QuickSearchEndsOnKey(Lingers, FActive, AShift, AKey, AKeyChar) then
  begin
    Clear;
    Exit(False);
  end;
  case ClassifyNeedleBoxKey(AKey, AKeyChar, Ch) of
    nbaClear:
      case ClassifyQuickSearchClear(FKeepFilter and FFiltering, Lingers, AKey) of
        qscKeepOpen:
          Exit(False);
        qscClearPassThrough:
          begin
            Clear;
            Exit(False);
          end;
      else
        begin
          Clear;
          AKey := 0;
          AKeyChar := #0;
        end;
      end;
    nbaBackspace:
      begin
        NeedleBackspace(FText);
        if FFilter then
        begin
          SetNeedle(FText);
          if FText <> '' then
          begin
            Ws := FHost.ActiveWorkspace;
            Panel := FHost.ActivePanel(Ws);
            Tab := ActiveTab(Panel);
            if ApplyQuickSearchMatch(Tab, FHost.RowsForSide(Ws.State.ActiveSide),
              FText, FHost.ListViewHeight, FHost.ListColCount(Ws.State.ActiveSide)) then
            begin
              SetActiveTab(Panel, Tab);
              FHost.SetActivePanel(Ws, Panel);
              FHost.SaveActiveWorkspace(Ws);
            end
            else if FFuzzy then
              FocusFirstFilteredRow;
          end;
        end;
        // An empty field stays open when asked for: a letter that cannot be
        // typed after Alt can be typed after any other Alt+letter and Backspace.
        if (FText = '') and not FKeepEmpty then
        begin
          FActive := False;
          FLatched := False;
        end;
        AKey := 0;
        AKeyChar := #0;
        FHost.NotifyChanged;
      end;
    nbaAppend:
      begin
        FActive := True;
        FText := FText + Ch;
        if FFilter then
          SetNeedle(FText);
        Ws := FHost.ActiveWorkspace;
        Panel := FHost.ActivePanel(Ws);
        Tab := ActiveTab(Panel);
        Rows := FHost.RowsForSide(Ws.State.ActiveSide);
        if ApplyQuickSearchMatch(Tab, Rows, FText, FHost.ListViewHeight,
          FHost.ListColCount(Ws.State.ActiveSide)) then
        begin
          SetActiveTab(Panel, Tab);
          FHost.SetActivePanel(Ws, Panel);
          FHost.SaveActiveWorkspace(Ws);
        end
        else if FFilter then
        begin
          if FFuzzy then
            FocusFirstFilteredRow
          else
            FHost.ClampCursor(Ws.State.ActiveSide);
        end;
        AKey := 0;
        AKeyChar := #0;
        FHost.NotifyChanged;
      end;
  else
    Result := False;
  end;
end;

function TDualPanelQuickSearch.TakeAltRelease: Boolean;
begin
  Result := False;
  if Lingers or not (FActive or (FText <> '')) then
    Exit;
  FActive := False;
  FText := '';
  Result := True;
end;

function TDualPanelQuickSearch.ClearsOnClick: Boolean;
begin
  Result := not (FKeepFilter and FFiltering);
end;

end.
