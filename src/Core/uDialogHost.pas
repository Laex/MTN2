unit uDialogHost;

{ Host-built declarative dialogs (DIALOG_PLUGIN). Draws via IThemeRenderer;
  inputs use TInputLine. In-process — cdecl export comes with DLL stage. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, System.StrUtils,
  uTerminalTypes, uThemeTypes, uThemeDrawing, uDialogTypes, uDialogJson, uDialogRenderer,
  uInputLine, uFunctionBar, uColorCoding, uDialogHistory;

type
  TDialogHost = class
  private
    FTheme: IThemeRenderer;
    FVisible: Boolean;
    FDecl: TDialogDeclaration;
    FBounds: TRectI;
    FControlBounds: TArray<TRectI>;
    FAreaW: Integer;
    FAreaH: Integer;
    FFocusIndex: Integer;
    FClicks: TMouseClickCounter; // input fields: double = word, triple = all
    /// <summary>Host-side mirror of list selection (avoids dynarray-of-record writeback issues).</summary>
    FListSelId: string;
    FListSelIndex: Integer;
    /// <summary>First visible row for multi-line list (height &gt; 1).</summary>
    FListScrollTop: Integer;
    /// <summary>Open DropDown control index, or -1 when collapsed.</summary>
    FDropOpenIndex: Integer;
    /// <summary>Highlighted item while DropDown popup is open.</summary>
    FDropHover: Integer;
    /// <summary>First visible popup row when items do not fit in the dialog.</summary>
    FDropScrollTop: Integer;
    FOnCommand: TDialogCommandEvent;
    FOnChanged: TNotifyEvent;
    FCursorVisible: Boolean;
    FUpdateLock: Integer;
    FUpdateDirty: Boolean;
    function FirstFocusable: Integer;
    function NextFocusable(AFrom: Integer; AForward: Boolean): Integer;
    function FocusedIsInput: Boolean;
    function FocusedIsButton: Boolean;
    function NormalizeAcceptKey(var AKey: Word; var AKeyChar: Char): Boolean;
    procedure NotifyChanged;
    procedure FireCommand(const AId: string);
    procedure FireCancel;
    function FindDefaultButtonIndex: Integer;
    procedure FireDefault;
    procedure FireAccept;
    procedure CaptureListSelection;
    procedure SetListSelectedIndex(AControlIndex, ASelected: Integer);
    function ListSelectedIndexOf(const AId: string): Integer;
    function ListSelectedTextOf(const AId: string): string;
    function ListViewHeight(AControlIndex: Integer): Integer;
    procedure EnsureListInView(AControlIndex: Integer);
    function FindInputIndexById(const AId: string): Integer;
    function PadGridLine(const AText: string; AWidth: Integer): string;
    /// <summary>Themed vs fallback color for an always-selected row (combo
    /// display, focused/open DropDown field) — FTheme.ResolveDialogRowColors
    /// when themed, else the fixed FAR/NDN black-on-cyan cursor row.</summary>
    procedure ResolveSelectedRowColors(out AFg, ABg: TAlphaColor);
    /// <summary>Themed vs fallback color for a list row that may or may not
    /// be selected — same rule as ResolveSelectedRowColors, but falls back
    /// to the caller's own ANormalFg/ANormalBg when not selected and no
    /// theme is assigned.</summary>
    procedure ResolveRowHighlight(ASelected: Boolean; ANormalFg, ANormalBg: TAlphaColor;
      out AFg, ABg: TAlphaColor);
    procedure SelectRadio(AControlIndex: Integer);
    procedure NormalizeRadioGroups;
    procedure LayoutIn(AAreaW, AAreaH: Integer);
    procedure RebuildControlLayout;
    procedure EnsureLayout;
    procedure CloseDropDown;
    /// <summary>dckInput with a History key: drops its history down like a
    /// dckDropDown (↓ in the last cell).</summary>
    function IsHistoryInput(AControlIndex: Integer): Boolean;
    function IsCancelCommand(const AId: string): Boolean;
    procedure LoadInputHistory;
    procedure SaveInputHistory;
    procedure RemoveDropHoverFromHistory;
    procedure OpenDropDown(AControlIndex: Integer);
    function DropPopupBounds(out ARect: TRectI): Boolean;
    function DropPopupViewHeight: Integer;
    procedure EnsureDropHoverInView;
    procedure DrawDropDownPopup(const AGrid: TTerminalGrid);
    function CommitDropDown: Boolean;
    procedure DrawColorSampleControl(const AGrid: TTerminalGrid; const R: TRectI;
      const C: TDialogControl);
    procedure DrawRadioGroupControl(const AGrid: TTerminalGrid; const R: TRectI;
      AIndex: Integer; const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
    procedure DrawListControl(const AGrid: TTerminalGrid; const R: TRectI;
      AIndex: Integer; const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
    /// <summary>↓ of a DropDown / history field, in the field's colors inverted.</summary>
    procedure DrawDropArrow(const AGrid: TTerminalGrid; ACol, ARow: Integer;
      const AFieldColors: TInputLineColors);
    procedure DrawDropDownControl(const AGrid: TTerminalGrid; const R: TRectI;
      AIndex: Integer; const C: TDialogControl);
    procedure DrawButtonControl(const AGrid: TTerminalGrid; const R: TRectI;
      AIndex: Integer; const C: TDialogControl);
  public
    constructor Create(const ATheme: IThemeRenderer);
    procedure Open(const ADecl: TDialogDeclaration; AOnCommand: TDialogCommandEvent);
    /// <summary>DIALOG_PLUGIN JSON subset. Returns False if parse fails (no open).</summary>
    function OpenJson(const ADeclJson: string; AOnCommand: TDialogCommandEvent): Boolean;
    procedure Close;
    function Visible: Boolean;
    function GetValuesJson: string;
    function GetInputValue(const AId: string): string;
    /// <summary>Live-updates a dckInput's text on the already-open dialog
    /// (cursor moves to the end) — the setter counterpart to GetInputValue,
    /// for cross-field sync (e.g. picking a list preset fills a hex field)
    /// that would be too disruptive to do via the usual close/reopen-with-a
    /// -patched-declaration pattern (that's for committing a whole dialog's
    /// worth of fields, not a value that changes on every arrow key).
    /// No-op if AId isn't a dckInput.</summary>
    procedure SetInputValue(const AId, AValue: string);
    function GetCheckbox(const AId: string): Boolean;
    function GetRadio(const AGroupId: string): string;
    function GetListSelectedIndex(const AId: string): Integer;
    function GetListSelectedText(const AId: string): string;
    procedure SetStatus(const AId, AText: string);
    /// <summary>Live-update a dckLabel or dckStatus caption on the open
    /// dialog. No-op if AId is missing.</summary>
    procedure SetLabelText(const AId, AText: string);
    /// <summary>Coalesce OnChanged across a burst of live setters (progress
    /// labels). Nested; EndUpdate fires at most one notify if anything
    /// actually changed.</summary>
    procedure BeginUpdate;
    procedure EndUpdate;
    /// <summary>Replace items of an already-open dckList (dirsync preview,
    /// file diff). Resets scroll to the top.</summary>
    procedure SetListItems(const AId: string; const AItems: TArray<string>;
      ASelectedIndex: Integer = 0);
    procedure Draw(const AGrid: TTerminalGrid; AAreaW, AAreaH: Integer);
    function HandleInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    /// <summary>Hit-test buttons/checkboxes; fires command on button click.</summary>
    /// <summary>Shift+click in an input field extends its selection.</summary>
    function HandleClick(ALocalCol, ALocalRow: Integer;
      AShift: TShiftState = []): Boolean;
    /// <summary>True when (ACol,ARow) is inside the dialog frame (after layout).</summary>
    function ContainsLocal(ALocalCol, ALocalRow: Integer): Boolean;
    /// <summary>Design-time control count (mirrors the open declaration).</summary>
    function ControlCount: Integer;
    /// <summary>Design-time read-only copy of one control.</summary>
    function GetControl(AIndex: Integer): TDialogControl;
    /// <summary>Design-time layout box (grid-absolute, same coordinate space
    /// as HandleClick's col/row) of one control. Empty rect if out of range.</summary>
    function ControlBoundsAt(AIndex: Integer): TRectI;
    /// <summary>Design-time hit test: index of the control under
    /// (ALocalCol, ALocalRow), else -1. Unlike HandleClick this never fires
    /// commands, moves focus, or opens/closes the DropDown popup.</summary>
    function ControlIndexAt(ALocalCol, ALocalRow: Integer): Integer;
    /// <summary>Id of focused button, else default/yes/ok button, else ''.</summary>
    function FocusedOrDefaultButtonId: string;
    /// <summary>Id of whichever control currently has keyboard focus (any
    /// kind), '' when none focused. Unlike FocusedOrDefaultButtonId this
    /// never falls back to a button — for callers that need "the field the
    /// user is actually on" (e.g. F9 = pick a color for the focused hex
    /// input), a fallback would answer the wrong question.</summary>
    function FocusedControlId: string;
    function ChromeContext: TFunctionBarContext;
    /// <summary>A DropDown / history list is dropped down (it owns Enter).</summary>
    function DropDownOpen: Boolean;
    /// <summary>Adds the history fields to uDialogHistory unless ACommandId
    /// cancels the dialog. FireCommand does it itself; hosts that turn Enter
    /// into a command without going through HandleInput call it.</summary>
    procedure RecordInputHistory(const ACommandId: string);
    procedure SetCursorVisible(AVisible: Boolean);
    property CursorVisible: Boolean read FCursorVisible;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

function ControlRowSpan(const C: TDialogControl): Integer;
begin
  case C.Kind of
    dckList:
      begin
        Result := Length(C.Items);
        if Result < 1 then
          Result := 1;
      end;
    dckRadioGroup:
      begin
        Result := Length(C.Items);
        if C.Text <> '' then
          Inc(Result);
        if Result < 1 then
          Result := 1;
      end;
  else
    Result := 1;
  end;
end;

function ExtractControlHotkey(const AText, AId: string): Char;
var
  AmpPos: Integer;
  Id: string;
begin
  Result := #0;
  AmpPos := Pos('&', AText);
  if (AmpPos > 0) and (AmpPos < Length(AText)) then
    Exit(UpCase(AText[AmpPos + 1]));

  Id := LowerCase(Trim(AId));
  if Id = 'delete' then Exit('D');
  if Id = 'skip' then Exit('S');
  if Id = 'skipall' then Exit('A');
  if Id = 'overwrite' then Exit('O');
  if Id = 'rename' then Exit('R');
  if Id = 'append' then Exit('A');
  if Id = 'retry' then Exit('R');
  if Id = 'cancel' then Exit('C');

  if AText <> '' then
    Exit(UpCase(AText[1]));

  if AId <> '' then
    Exit(UpCase(AId[1]));
end;

function ButtonCellWidth(const C: TDialogControl): Integer;
begin
  Result := Min(14, Max(Length(C.Text) + 6, 10));
end;

function RadioGroupValueOf(const C: TDialogControl): string;
var
  Idx: Integer;
begin
  Result := '';
  if C.Kind <> dckRadioGroup then
    Exit;
  Idx := C.SelectedIndex;
  if (Idx >= 0) and (Idx <= High(C.ItemIds)) and (C.ItemIds[Idx] <> '') then
    Exit(C.ItemIds[Idx]);
  if (Idx >= 0) and (Idx <= High(C.Items)) then
    Result := C.Items[Idx];
end;

constructor TDialogHost.Create(const ATheme: IThemeRenderer);
begin
  inherited Create;
  FTheme := ATheme;
  FVisible := False;
  FFocusIndex := -1;
  FListSelId := '';
  FListSelIndex := 0;
  FListScrollTop := 0;
  FDropOpenIndex := -1;
  FDropHover := 0;
  FDropScrollTop := 0;
  FUpdateLock := 0;
  FUpdateDirty := False;
  FAreaW := 80;
  FAreaH := 25;
  SetLength(FControlBounds, 0);
end;

procedure TDialogHost.EnsureLayout;
begin
  if (FAreaW > 0) and (FAreaH > 0) then
    LayoutIn(FAreaW, FAreaH);
end;

procedure TDialogHost.NotifyChanged;
begin
  if FUpdateLock > 0 then
  begin
    FUpdateDirty := True;
    Exit;
  end;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TDialogHost.BeginUpdate;
begin
  Inc(FUpdateLock);
end;

procedure TDialogHost.EndUpdate;
begin
  if FUpdateLock <= 0 then
    Exit;
  Dec(FUpdateLock);
  if (FUpdateLock = 0) and FUpdateDirty then
  begin
    FUpdateDirty := False;
    NotifyChanged;
  end;
end;

function TDialogHost.Visible: Boolean;
begin
  Result := FVisible;
end;

function TDialogHost.FirstFocusable: Integer;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if FDecl.Controls[I].Kind in [dckInput, dckCheckbox, dckRadio, dckRadioGroup,
      dckButton, dckList, dckDropDown] then
      Exit(I);
  Result := -1;
end;

function TDialogHost.NextFocusable(AFrom: Integer; AForward: Boolean): Integer;
var
  N, Steps: Integer;
begin
  N := Length(FDecl.Controls);
  if N = 0 then
    Exit(-1);
  Result := AFrom;
  for Steps := 1 to N do
  begin
    if AForward then
      Result := (Result + 1) mod N
    else
      Result := (Result + N - 1) mod N;
    if FDecl.Controls[Result].Kind in [dckInput, dckCheckbox, dckRadio,
      dckRadioGroup, dckButton, dckList, dckDropDown] then
      Exit;
  end;
  Result := AFrom;
end;

function TDialogHost.FocusedIsInput: Boolean;
begin
  Result := (FFocusIndex >= 0) and (FFocusIndex <= High(FDecl.Controls)) and
    (FDecl.Controls[FFocusIndex].Kind = dckInput);
end;

function TDialogHost.FocusedIsButton: Boolean;
begin
  Result := (FFocusIndex >= 0) and (FFocusIndex <= High(FDecl.Controls)) and
    (FDecl.Controls[FFocusIndex].Kind = dckButton);
end;

function TDialogHost.NormalizeAcceptKey(var AKey: Word; var AKeyChar: Char): Boolean;
begin
  // FMX/Win: Enter may arrive as vkReturn, raw 13/10, KeyChar-only, or both.
  if (AKeyChar = #13) or (AKeyChar = #10) then
    AKey := vkReturn;
  if (AKey = 10) or (AKey = 13) or (AKey = vkReturn) or (AKey = vkAccept) then
  begin
    AKey := vkReturn;
    AKeyChar := #0;
    Exit(True);
  end;
  Result := False;
end;

procedure TDialogHost.Open(const ADecl: TDialogDeclaration;
  AOnCommand: TDialogCommandEvent);
begin
  FDecl := ADecl;
  if FDecl.Width < 28 then
    FDecl.Width := 28;
  if FDecl.Height < 6 then
    FDecl.Height := 6;
  FOnCommand := AOnCommand;
  FDropOpenIndex := -1;
  FDropHover := 0;
  FDropScrollTop := 0;
  FListScrollTop := 0;
  NormalizeRadioGroups;
  LoadInputHistory;
  FFocusIndex := FirstFocusable;
  FCursorVisible := True;
  CaptureListSelection;
  FVisible := True;
  NotifyChanged;
end;

procedure TDialogHost.SetCursorVisible(AVisible: Boolean);
begin
  if FCursorVisible = AVisible then
    Exit;
  FCursorVisible := AVisible;
  NotifyChanged;
end;

function TDialogHost.OpenJson(const ADeclJson: string;
  AOnCommand: TDialogCommandEvent): Boolean;
var
  Decl: TDialogDeclaration;
begin
  Result := TryParseDialogJson(ADeclJson, Decl);
  if not Result then
    Exit;
  Open(Decl, AOnCommand);
end;

procedure TDialogHost.Close;
begin
  if not FVisible then
    Exit;
  FVisible := False;
  FOnCommand := nil;
  FDropOpenIndex := -1;
  FDropHover := 0;
  FDropScrollTop := 0;
  FListScrollTop := 0;
  SetLength(FDecl.Controls, 0);
  SetLength(FControlBounds, 0);
  FFocusIndex := -1;
  FListSelId := '';
  FListSelIndex := 0;
  NotifyChanged;
end;

procedure TDialogHost.CloseDropDown;
begin
  if FDropOpenIndex < 0 then
    Exit;
  FDropOpenIndex := -1;
  FDropHover := 0;
  FDropScrollTop := 0;
  NotifyChanged;
end;

function TDialogHost.IsHistoryInput(AControlIndex: Integer): Boolean;
begin
  Result := (AControlIndex >= 0) and (AControlIndex <= High(FDecl.Controls)) and
    (FDecl.Controls[AControlIndex].Kind = dckInput) and
    (FDecl.Controls[AControlIndex].History <> '') and
    not FDecl.Controls[AControlIndex].Password;
end;

function TDialogHost.IsCancelCommand(const AId: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if FDecl.Controls[I].IsCancel and SameText(FDecl.Controls[I].Id, AId) then
      Exit(True);
  Result := False;
end;

procedure TDialogHost.LoadInputHistory;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if IsHistoryInput(I) then
      FDecl.Controls[I].Items := DialogHistoryItems(FDecl.Controls[I].History);
end;

procedure TDialogHost.SaveInputHistory;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if IsHistoryInput(I) then
      DialogHistoryAdd(FDecl.Controls[I].History, Trim(FDecl.Controls[I].Edit.Text));
end;

procedure TDialogHost.RemoveDropHoverFromHistory;
var
  C: TDialogControl;
begin
  if not IsHistoryInput(FDropOpenIndex) then
    Exit;
  C := FDecl.Controls[FDropOpenIndex];
  if (FDropHover < 0) or (FDropHover > High(C.Items)) then
    Exit;
  DialogHistoryRemove(C.History, C.Items[FDropHover]);
  FDecl.Controls[FDropOpenIndex].Items := DialogHistoryItems(C.History);
  if Length(FDecl.Controls[FDropOpenIndex].Items) = 0 then
  begin
    CloseDropDown;
    Exit;
  end;
  FDropHover := EnsureRange(FDropHover, 0, High(FDecl.Controls[FDropOpenIndex].Items));
  EnsureDropHoverInView;
  NotifyChanged;
end;

procedure TDialogHost.OpenDropDown(AControlIndex: Integer);
var
  I: Integer;
begin
  if (AControlIndex < 0) or (AControlIndex > High(FDecl.Controls)) then
    Exit;
  if (FDecl.Controls[AControlIndex].Kind <> dckDropDown) and
     not IsHistoryInput(AControlIndex) then
    Exit;
  if Length(FDecl.Controls[AControlIndex].Items) = 0 then
    Exit;
  FFocusIndex := AControlIndex;
  FDropOpenIndex := AControlIndex;
  FDropScrollTop := 0;
  if IsHistoryInput(AControlIndex) then
  begin
    // Start on the entry the field already holds, else the newest.
    FDropHover := 0;
    for I := 0 to High(FDecl.Controls[AControlIndex].Items) do
      if SameText(FDecl.Controls[AControlIndex].Items[I],
         FDecl.Controls[AControlIndex].Edit.Text) then
      begin
        FDropHover := I;
        Break;
      end;
  end
  else
  begin
    FDropHover := ListSelectedIndexOf(FDecl.Controls[AControlIndex].Id);
    if FDropHover < 0 then
      FDropHover := FDecl.Controls[AControlIndex].SelectedIndex;
  end;
  FDropHover := EnsureRange(FDropHover, 0, High(FDecl.Controls[AControlIndex].Items));
  EnsureLayout;
  EnsureDropHoverInView;
  NotifyChanged;
end;

function TDialogHost.CommitDropDown: Boolean;
begin
  Result := False;
  if FDropOpenIndex < 0 then
    Exit;
  if IsHistoryInput(FDropOpenIndex) then
  begin
    if (FDropHover >= 0) and (FDropHover <= High(FDecl.Controls[FDropOpenIndex].Items)) then
      InputLineSetText(FDecl.Controls[FDropOpenIndex].Edit,
        FDecl.Controls[FDropOpenIndex].Items[FDropHover]);
  end
  else
    SetListSelectedIndex(FDropOpenIndex, FDropHover);
  FDropOpenIndex := -1;
  FDropHover := 0;
  FDropScrollTop := 0;
  NotifyChanged;
  Result := True;
end;

function TDialogHost.DropPopupBounds(out ARect: TRectI): Boolean;
var
  R: TRectI;
  N, ItemH, FrameH, SpaceBelow, SpaceAbove: Integer;
  ClientTop, ClientBottom: Integer;
  OpenBelow, CanBelow, CanAbove, FitsBelow, FitsAbove: Boolean;
begin
  Result := False;
  if (FDropOpenIndex < 0) or (FDropOpenIndex > High(FControlBounds)) then
    Exit;
  R := FControlBounds[FDropOpenIndex];
  N := Length(FDecl.Controls[FDropOpenIndex].Items);
  if N < 1 then
    Exit;
  ClientTop := FBounds.Top + 1;
  ClientBottom := FBounds.Bottom - 1;
  SpaceBelow := ClientBottom - (R.Bottom + 1) + 1;
  SpaceAbove := R.Top - 1 - ClientTop + 1;
  CanBelow := SpaceBelow >= 3;
  CanAbove := SpaceAbove >= 3;
  FitsBelow := SpaceBelow >= N + 2;
  FitsAbove := SpaceAbove >= N + 2;
  // Prefer a side that can show every item; otherwise the side with more room
  // so Size/Zoom lists near the middle of a dialog still have a usable popup.
  if FitsBelow then
    OpenBelow := True
  else if FitsAbove then
    OpenBelow := False
  else if CanBelow and ((not CanAbove) or (SpaceBelow >= SpaceAbove)) then
    OpenBelow := True
  else if CanAbove then
    OpenBelow := False
  else
    OpenBelow := SpaceBelow >= SpaceAbove;
  // Outer rect includes a single-line box frame (visible items + 2).
  if OpenBelow then
  begin
    ItemH := Min(N, Max(SpaceBelow - 2, 1));
    FrameH := ItemH + 2;
    ARect := TRectI.Make(R.Left, R.Bottom + 1, R.Right, R.Bottom + FrameH);
  end
  else
  begin
    ItemH := Min(N, Max(SpaceAbove - 2, 1));
    FrameH := ItemH + 2;
    ARect := TRectI.Make(R.Left, R.Top - FrameH, R.Right, R.Top - 1);
  end;
  if ARect.Left < FBounds.Left + 1 then
    ARect.Left := FBounds.Left + 1;
  if ARect.Right > FBounds.Right - 1 then
    ARect.Right := FBounds.Right - 1;
  if ARect.Top < ClientTop then
    ARect.Top := ClientTop;
  if ARect.Bottom > ClientBottom then
    ARect.Bottom := ClientBottom;
  if ARect.Right < ARect.Left then
    ARect.Right := ARect.Left;
  if ARect.Bottom < ARect.Top then
    ARect.Bottom := ARect.Top;
  Result := (ARect.Height >= 3) and (ARect.Width >= 3);
end;

function TDialogHost.DropPopupViewHeight: Integer;
var
  Frame: TRectI;
begin
  Result := 0;
  if DropPopupBounds(Frame) then
    Result := Max(Frame.Height - 2, 0);
end;

procedure TDialogHost.EnsureDropHoverInView;
var
  ViewH, Count, MaxTop: Integer;
begin
  if FDropOpenIndex < 0 then
    Exit;
  ViewH := DropPopupViewHeight;
  Count := Length(FDecl.Controls[FDropOpenIndex].Items);
  if (ViewH <= 0) or (Count <= ViewH) then
  begin
    FDropScrollTop := 0;
    Exit;
  end;
  FDropHover := EnsureRange(FDropHover, 0, Count - 1);
  if FDropHover < FDropScrollTop then
    FDropScrollTop := FDropHover;
  if FDropHover >= FDropScrollTop + ViewH then
    FDropScrollTop := FDropHover - ViewH + 1;
  MaxTop := Count - ViewH;
  FDropScrollTop := EnsureRange(FDropScrollTop, 0, MaxTop);
end;

procedure TDialogHost.DrawDropDownPopup(const AGrid: TTerminalGrid);
var
  Frame, Content: TRectI;
  C: TDialogControl;
  J, Idx, ViewH, Count, TextW: Integer;
  Line: string;
  RowFg, RowBg, FrameFg, FrameBg: TAlphaColor;
  NeedBar: Boolean;
begin
  if not DropPopupBounds(Frame) then
    Exit;
  EnsureDropHoverInView;
  Content := TRectI.Make(Frame.Left + 1, Frame.Top + 1,
    Frame.Right - 1, Frame.Bottom - 1);
  if (Content.Right < Content.Left) or (Content.Bottom < Content.Top) then
    Exit;
  C := FDecl.Controls[FDropOpenIndex];
  ViewH := Content.Height;
  Count := Length(C.Items);
  NeedBar := Count > ViewH;
  TextW := Content.Width;
  if NeedBar then
    TextW := Max(Content.Width - 1, 1);
  // Same chrome as Sort/Column overlay menus: white body, black frame.
  FrameFg := TAlphaColor($FF000000);
  FrameBg := TAlphaColor($FFFFFFFF);

  DrawPanelFrameGlyphs(AGrid, Frame, chBoxTL, chBoxTR, chBoxBL, chBoxBR, chBoxH, chBoxV,
    FrameFg, FrameFg, FrameBg);

  for J := 0 to ViewH - 1 do
  begin
    Idx := FDropScrollTop + J;
    if (Idx < 0) or (Idx > High(C.Items)) then
      Line := ''
    else
      Line := C.Items[Idx];
    while Length(Line) < TextW do
      Line := Line + ' ';
    Line := Copy(Line, 1, Max(TextW, 1));
    ResolveRowHighlight(Idx = FDropHover, FrameFg, FrameBg, RowFg, RowBg);
    PutGridText(AGrid, Content.Left, Content.Top + J, Line, RowFg, RowBg);
  end;
  if NeedBar then
    DrawDialogScrollBar(AGrid, Content.Right, Content.Top, Content.Bottom,
      FDropScrollTop, Count, ViewH);
end;

procedure TDialogHost.CaptureListSelection;
var
  I: Integer;
begin
  FListSelId := '';
  FListSelIndex := 0;
  for I := 0 to High(FDecl.Controls) do
    if FDecl.Controls[I].Kind in [dckList, dckRadioGroup, dckDropDown] then
    begin
      FListSelId := FDecl.Controls[I].Id;
      FListSelIndex := FDecl.Controls[I].SelectedIndex;
      Exit;
    end;
end;

function TDialogHost.ListSelectedIndexOf(const AId: string): Integer;
var
  I: Integer;
begin
  if (FListSelId <> '') and SameText(FListSelId, AId) then
    Exit(FListSelIndex);
  Result := -1;
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind in [dckList, dckRadioGroup, dckDropDown]) and
       SameText(FDecl.Controls[I].Id, AId) then
      Exit(FDecl.Controls[I].SelectedIndex);
end;

function TDialogHost.ListSelectedTextOf(const AId: string): string;
var
  I, Idx: Integer;
begin
  Result := '';
  Idx := ListSelectedIndexOf(AId);
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind in [dckList, dckRadioGroup, dckDropDown]) and
       SameText(FDecl.Controls[I].Id, AId) then
    begin
      if (Idx >= 0) and (Idx <= High(FDecl.Controls[I].Items)) then
        Result := FDecl.Controls[I].Items[Idx];
      Exit;
    end;
end;

function TDialogHost.FindInputIndexById(const AId: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  if AId = '' then
    Exit;
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckInput) and SameText(FDecl.Controls[I].Id, AId) then
      Exit(I);
end;

function TDialogHost.PadGridLine(const AText: string; AWidth: Integer): string;
begin
  if AWidth < 1 then
    Exit('');
  if Length(AText) >= AWidth then
    Exit(Copy(AText, 1, AWidth));
  Result := AText + StringOfChar(' ', AWidth - Length(AText));
end;

procedure TDialogHost.SelectRadio(AControlIndex: Integer);
var
  G: string;
  I: Integer;
begin
  if (AControlIndex < 0) or (AControlIndex > High(FDecl.Controls)) then
    Exit;
  if FDecl.Controls[AControlIndex].Kind <> dckRadio then
    Exit;
  G := FDecl.Controls[AControlIndex].Group;
  if G = '' then
    G := FDecl.Controls[AControlIndex].Id;
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckRadio) and SameText(FDecl.Controls[I].Group, G) then
      FDecl.Controls[I].Checked := (I = AControlIndex);
end;

procedure TDialogHost.NormalizeRadioGroups;
var
  I, J: Integer;
  G: string;
  Seen: TArray<string>;
  HasChecked: Boolean;

  function GroupSeen(const AGroup: string): Boolean;
  var
    K: Integer;
  begin
    for K := 0 to High(Seen) do
      if SameText(Seen[K], AGroup) then
        Exit(True);
    Result := False;
  end;

begin
  SetLength(Seen, 0);
  for I := 0 to High(FDecl.Controls) do
  begin
    if FDecl.Controls[I].Kind <> dckRadio then
      Continue;
    G := FDecl.Controls[I].Group;
    if G = '' then
      Continue;
    if GroupSeen(G) then
      Continue;
    SetLength(Seen, Length(Seen) + 1);
    Seen[High(Seen)] := G;
    HasChecked := False;
    for J := 0 to High(FDecl.Controls) do
      if (FDecl.Controls[J].Kind = dckRadio) and SameText(FDecl.Controls[J].Group, G) and
         FDecl.Controls[J].Checked then
      begin
        HasChecked := True;
        Break;
      end;
    if not HasChecked then
    begin
      for J := 0 to High(FDecl.Controls) do
        if (FDecl.Controls[J].Kind = dckRadio) and SameText(FDecl.Controls[J].Group, G) then
        begin
          FDecl.Controls[J].Checked := True;
          Break;
        end;
    end
    else
    begin
      // Keep first checked only.
      HasChecked := False;
      for J := 0 to High(FDecl.Controls) do
        if (FDecl.Controls[J].Kind = dckRadio) and SameText(FDecl.Controls[J].Group, G) then
        begin
          if FDecl.Controls[J].Checked and not HasChecked then
            HasChecked := True
          else
            FDecl.Controls[J].Checked := False;
        end;
    end;
  end;
end;

function TDialogHost.GetInputValue(const AId: string): string;
var
  I: Integer;
begin
  Result := '';
  I := FindInputIndexById(AId);
  if I >= 0 then
    Result := FDecl.Controls[I].Edit.Text;
end;

procedure TDialogHost.SetInputValue(const AId, AValue: string);
var
  I: Integer;
begin
  I := FindInputIndexById(AId);
  if I >= 0 then
    InputLineSetText(FDecl.Controls[I].Edit, AValue);
end;

function TDialogHost.GetCheckbox(const AId: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckCheckbox) and SameText(FDecl.Controls[I].Id, AId) then
      Exit(FDecl.Controls[I].Checked);
end;

function TDialogHost.GetRadio(const AGroupId: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(FDecl.Controls) do
  begin
    if (FDecl.Controls[I].Kind = dckRadioGroup) and
       SameText(FDecl.Controls[I].Id, AGroupId) then
      Exit(RadioGroupValueOf(FDecl.Controls[I]));
    if (FDecl.Controls[I].Kind = dckRadio) and
       SameText(FDecl.Controls[I].Group, AGroupId) and
       FDecl.Controls[I].Checked then
    begin
      if FDecl.Controls[I].Id <> '' then
        Exit(FDecl.Controls[I].Id);
      Exit(FDecl.Controls[I].Text);
    end;
  end;
end;

function TDialogHost.GetListSelectedIndex(const AId: string): Integer;
begin
  Result := ListSelectedIndexOf(AId);
end;

function TDialogHost.GetListSelectedText(const AId: string): string;
begin
  Result := ListSelectedTextOf(AId);
end;

function TDialogHost.GetValuesJson: string;
var
  I, Idx: Integer;
  Parts: TArray<string>;
  N: Integer;
  Name, G: string;
  EmittedGroups: TArray<string>;

  function GroupEmitted(const AGroup: string): Boolean;
  var
    K: Integer;
  begin
    for K := 0 to High(EmittedGroups) do
      if SameText(EmittedGroups[K], AGroup) then
        Exit(True);
    Result := False;
  end;

  procedure MarkGroup(const AGroup: string);
  begin
    SetLength(EmittedGroups, Length(EmittedGroups) + 1);
    EmittedGroups[High(EmittedGroups)] := AGroup;
  end;

begin
  SetLength(Parts, 0);
  SetLength(EmittedGroups, 0);
  for I := 0 to High(FDecl.Controls) do
  begin
    case FDecl.Controls[I].Kind of
      dckInput:
        begin
          if FDecl.Controls[I].Id = '' then
            Continue;
          N := Length(Parts);
          SetLength(Parts, N + 1);
          Parts[N] := Format('"%s":"%s"',
            [FDecl.Controls[I].Id,
             StringReplace(FDecl.Controls[I].Edit.Text, '"', '\"', [rfReplaceAll])]);
        end;
      dckCheckbox:
        begin
          if FDecl.Controls[I].Id = '' then
            Continue;
          N := Length(Parts);
          SetLength(Parts, N + 1);
          if FDecl.Controls[I].Checked then
            Parts[N] := Format('"%s":true', [FDecl.Controls[I].Id])
          else
            Parts[N] := Format('"%s":false', [FDecl.Controls[I].Id]);
        end;
      dckList, dckDropDown:
        begin
          if FDecl.Controls[I].Id = '' then
            Continue;
          Idx := ListSelectedIndexOf(FDecl.Controls[I].Id);
          Name := '';
          if (Idx >= 0) and (Idx <= High(FDecl.Controls[I].Items)) then
            Name := FDecl.Controls[I].Items[Idx];
          N := Length(Parts);
          SetLength(Parts, N + 1);
          Parts[N] := Format('"%s":"%s"',
            [FDecl.Controls[I].Id,
             StringReplace(Name, '"', '\"', [rfReplaceAll])]);
        end;
      dckRadioGroup:
        begin
          if FDecl.Controls[I].Id = '' then
            Continue;
          Name := RadioGroupValueOf(FDecl.Controls[I]);
          N := Length(Parts);
          SetLength(Parts, N + 1);
          Parts[N] := Format('"%s":"%s"',
            [FDecl.Controls[I].Id,
             StringReplace(Name, '"', '\"', [rfReplaceAll])]);
        end;
      dckRadio:
        begin
          G := FDecl.Controls[I].Group;
          if (G = '') or not FDecl.Controls[I].Checked or GroupEmitted(G) then
            Continue;
          MarkGroup(G);
          if FDecl.Controls[I].Id <> '' then
            Name := FDecl.Controls[I].Id
          else
            Name := FDecl.Controls[I].Text;
          N := Length(Parts);
          SetLength(Parts, N + 1);
          Parts[N] := Format('"%s":"%s"',
            [G, StringReplace(Name, '"', '\"', [rfReplaceAll])]);
        end;
    end;
  end;
  Result := '{' + string.Join(',', Parts) + '}';
end;

procedure TDialogHost.SetStatus(const AId, AText: string);
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
      if (FDecl.Controls[I].Kind = dckStatus) and SameText(FDecl.Controls[I].Id, AId) then
    begin
      if FDecl.Controls[I].Text = AText then
        Exit;
      FDecl.Controls[I].Text := AText;
      NotifyChanged;
      Exit;
    end;
  SetLabelText(AId, AText);
end;

procedure TDialogHost.SetLabelText(const AId, AText: string);
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind in [dckLabel, dckStatus]) and
       SameText(FDecl.Controls[I].Id, AId) then
    begin
      if FDecl.Controls[I].Text = AText then
        Exit;
      FDecl.Controls[I].Text := AText;
      NotifyChanged;
      Exit;
    end;
end;

procedure TDialogHost.SetListItems(const AId: string; const AItems: TArray<string>;
  ASelectedIndex: Integer);
var
  I, Sel: Integer;
  Items: TArray<string>;
begin
  for I := 0 to High(FDecl.Controls) do
  begin
    if (FDecl.Controls[I].Kind <> dckList) or not SameText(FDecl.Controls[I].Id, AId) then
      Continue;
    if Length(AItems) = 0 then
    begin
      SetLength(Items, 1);
      Items[0] := '(none)';
    end
    else
      Items := Copy(AItems);
    FDecl.Controls[I].Items := Items;
    Sel := ASelectedIndex;
    if Sel < 0 then
      Sel := 0;
    if Sel > High(Items) then
      Sel := High(Items);
    FDecl.Controls[I].SelectedIndex := Sel;
    FListSelId := AId;
    FListSelIndex := Sel;
    FListScrollTop := 0;
    NotifyChanged;
    Exit;
  end;
end;

procedure TDialogHost.FireCommand(const AId: string);
var
  Cmd: TDialogCommandEvent;
  Values, Id: string;
begin
  Cmd := FOnCommand;
  // Own a reference to the id before invoking the handler. Callers pass
  // FDecl.Controls[I].Id, and handlers routinely call Close, which does
  // SetLength(FDecl.Controls, 0) — that drops the last reference and frees the
  // string out from under this `const` (no-refcount) parameter. Any
  // DialogCmdIs* test the handler runs after Close would then read freed
  // memory ("Invalid pointer operation").
  Id := AId;
  RecordInputHistory(Id);
  Values := GetValuesJson;
  if Assigned(Cmd) then
    Cmd(Id, Values);
end;

function TDialogHost.DropDownOpen: Boolean;
begin
  Result := FVisible and (FDropOpenIndex >= 0);
end;

procedure TDialogHost.RecordInputHistory(const ACommandId: string);
begin
  // Whatever the dialog does next, a non-cancel command used the fields.
  if not DialogCmdIsReject(ACommandId) and not IsCancelCommand(ACommandId) then
    SaveInputHistory;
end;

procedure TDialogHost.FireCancel;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if FDecl.Controls[I].IsCancel then
    begin
      FireCommand(FDecl.Controls[I].Id);
      Exit;
    end;
  FireCommand(cDlgCmdCancel);
end;

function TDialogHost.FindDefaultButtonIndex: Integer;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckButton) and FDecl.Controls[I].IsDefault then
      Exit(I);
  Result := -1;
end;

procedure TDialogHost.FireDefault;
var
  Idx, I: Integer;
begin
  Idx := FindDefaultButtonIndex;
  if Idx < 0 then
    for I := 0 to High(FDecl.Controls) do
      if (FDecl.Controls[I].Kind = dckButton) and
         DialogCmdIsAccept(FDecl.Controls[I].Id) then
      begin
        Idx := I;
        Break;
      end;
  if Idx < 0 then
    for I := 0 to High(FDecl.Controls) do
      if (FDecl.Controls[I].Kind = dckButton) and not FDecl.Controls[I].IsCancel then
      begin
        Idx := I;
        Break;
      end;
  if Idx >= 0 then
    FireCommand(FDecl.Controls[Idx].Id)
  else
  begin
    // List-only dialogs (e.g. Code page): Enter accepts current selection.
    for I := 0 to High(FDecl.Controls) do
      if FDecl.Controls[I].Kind = dckList then
      begin
        FireCommand(cDlgCmdOk);
        Exit;
      end;
  end;
end;

procedure TDialogHost.FireAccept;
begin
  // Windows-like: Enter on a focused push-button activates that button;
  // otherwise activate the dialog default.
  if FocusedIsButton then
    FireCommand(FDecl.Controls[FFocusIndex].Id)
  else
    FireDefault;
end;

procedure TDialogHost.SetListSelectedIndex(AControlIndex, ASelected: Integer);
var
  C: TDialogControl;
begin
  if (AControlIndex < 0) or (AControlIndex > High(FDecl.Controls)) then
    Exit;
  C := FDecl.Controls[AControlIndex];
  if not (C.Kind in [dckList, dckRadioGroup, dckDropDown]) then
    Exit;
  if Length(C.Items) = 0 then
    C.SelectedIndex := 0
  else
    C.SelectedIndex := EnsureRange(ASelected, 0, High(C.Items));
  FDecl.Controls[AControlIndex] := C;
  // Always keep host mirror in sync (source of truth for OK/Enter).
  FListSelId := C.Id;
  FListSelIndex := C.SelectedIndex;
  if C.Kind = dckList then
    EnsureListInView(AControlIndex);
end;

function TDialogHost.ListViewHeight(AControlIndex: Integer): Integer;
var
  R: TRectI;
  LastInner: Integer;
begin
  Result := 1;
  if (AControlIndex < 0) or (AControlIndex > High(FDecl.Controls)) then
    Exit;
  if Length(FControlBounds) > AControlIndex then
  begin
    R := FControlBounds[AControlIndex];
    Result := Max(R.Height, 1);
    // Last inner cell is FBounds.Bottom - 1 (bottom border occupies Bottom).
    LastInner := FBounds.Bottom - 1;
    if R.Top <= LastInner then
      Result := Max(Min(Result, LastInner - R.Top + 1), 1);
  end
  else if FDecl.Controls[AControlIndex].BoxH > 0 then
    Result := FDecl.Controls[AControlIndex].BoxH
  else
    Result := Max(ControlRowSpan(FDecl.Controls[AControlIndex]), 1);
end;

procedure TDialogHost.EnsureListInView(AControlIndex: Integer);
var
  ViewH, Count, Sel, MaxTop: Integer;
begin
  if (AControlIndex < 0) or (AControlIndex > High(FDecl.Controls)) then
    Exit;
  if FDecl.Controls[AControlIndex].Kind <> dckList then
    Exit;
  ViewH := ListViewHeight(AControlIndex);
  if ViewH <= 1 then
  begin
    FListScrollTop := 0;
    Exit;
  end;
  Count := Length(FDecl.Controls[AControlIndex].Items);
  Sel := ListSelectedIndexOf(FDecl.Controls[AControlIndex].Id);
  if Sel < 0 then
    Sel := 0;
  if Count <= ViewH then
  begin
    FListScrollTop := 0;
    Exit;
  end;
  if Sel < FListScrollTop then
    FListScrollTop := Sel;
  if Sel >= FListScrollTop + ViewH then
    FListScrollTop := Sel - ViewH + 1;
  MaxTop := Count - ViewH;
  FListScrollTop := EnsureRange(FListScrollTop, 0, MaxTop);
end;

procedure TDialogHost.ResolveSelectedRowColors(out AFg, ABg: TAlphaColor);
begin
  if Assigned(FTheme) then
    FTheme.ResolveDialogRowColors(True, AFg, ABg)
  else
  begin
    AFg := TAlphaColor($FF000000);
    ABg := TAlphaColor($FF00AAAA);
  end;
end;

procedure TDialogHost.ResolveRowHighlight(ASelected: Boolean; ANormalFg, ANormalBg: TAlphaColor;
  out AFg, ABg: TAlphaColor);
begin
  if Assigned(FTheme) then
    FTheme.ResolveDialogRowColors(ASelected, AFg, ABg)
  else if ASelected then
  begin
    AFg := TAlphaColor($FF000000);
    ABg := TAlphaColor($FF00AAAA);
  end
  else
  begin
    AFg := ANormalFg;
    ABg := ANormalBg;
  end;
end;

procedure TDialogHost.LayoutIn(AAreaW, AAreaH: Integer);
var
  W, H: Integer;
begin
  if AAreaW > 0 then
    FAreaW := AAreaW;
  if AAreaH > 0 then
    FAreaH := AAreaH;
  if IsDialogProtocolV2(FDecl.Version) then
  begin
    // Protocol 2.0: author owns dialog size; Host only clamps to the screen.
    W := Max(FDecl.Width, 1);
    H := Max(FDecl.Height, 1);
    if FAreaW > 2 then
      W := Min(W, FAreaW - 2);
    if FAreaH > 2 then
      H := Min(H, FAreaH - 2);
  end
  else
  begin
    W := Min(FDecl.Width, Max(FAreaW - 2, 28));
    H := Min(FDecl.Height, Max(FAreaH - 2, 6));
  end;
  FBounds := TRectI.Make(
    (FAreaW - W) div 2,
    Max((FAreaH - H) div 2, 2),
    (FAreaW - W) div 2 + W - 1,
    Max((FAreaH - H) div 2, 2) + H - 1);
  // Prefer keeping the dialog on-screen; shadow may clip at the edge.
  if FBounds.Right > FAreaW - 1 then
  begin
    FBounds.Right := FAreaW - 1;
    FBounds.Left := Max(FBounds.Right - W + 1, 0);
  end;
  if FBounds.Bottom > FAreaH - 1 then
  begin
    FBounds.Bottom := FAreaH - 1;
    FBounds.Top := Max(FBounds.Bottom - H + 1, 1);
  end;
  RebuildControlLayout;
end;

function DefaultControlWidth(const C: TDialogControl; AClientW: Integer): Integer;
var
  I: Integer;
begin
  case C.Kind of
    dckButton:
      Result := ButtonCellWidth(C);
    dckCheckbox, dckRadio:
      Result := Min(AClientW, Max(Length(C.Text) + 4, 8));
    dckLabel, dckStatus:
      Result := Min(AClientW, Max(Length(C.Text), 1));
    dckDropDown:
      begin
        Result := 12;
        for I := 0 to High(C.Items) do
          if Length(C.Items[I]) + 2 > Result then
            Result := Length(C.Items[I]) + 2;
        Result := Min(AClientW, Max(Result, 8));
      end;
  else
    Result := Max(AClientW, 1);
  end;
end;

function DefaultControlHeight(const C: TDialogControl): Integer;
begin
  case C.Kind of
    dckList, dckRadioGroup:
      Result := ControlRowSpan(C);
    dckDropDown:
      Result := 1;
  else
    Result := 1;
  end;
end;

procedure TDialogHost.RebuildControlLayout;
var
  I, Y, BtnX, BtnW, Span, InnerLeft, InnerRight: Integer;
  ClientLeft, ClientTop, ClientRight, ClientBottom, ClientW: Integer;
  CX, CY, CW, CH, L, T, Rgt, Bot: Integer;
  InButtonRow: Boolean;
  C: TDialogControl;
begin
  SetLength(FControlBounds, Length(FDecl.Controls));

  if IsDialogProtocolV2(FDecl.Version) then
  begin
    // Protocol 2.0: (col,row)=(0,0) is first cell inside the frame border.
    ClientLeft := FBounds.Left + 1;
    ClientTop := FBounds.Top + 1;
    ClientRight := FBounds.Right - 1;
    ClientBottom := FBounds.Bottom - 1;
    if ClientRight < ClientLeft then
      ClientRight := ClientLeft;
    if ClientBottom < ClientTop then
      ClientBottom := ClientTop;
    ClientW := ClientRight - ClientLeft + 1;

    for I := 0 to High(FDecl.Controls) do
    begin
      C := FDecl.Controls[I];
      if C.Col >= 0 then
        CX := C.Col
      else
        CX := 0;
      if C.Row >= 0 then
        CY := C.Row
      else
        CY := 0;
      if C.BoxW > 0 then
        CW := C.BoxW
      else
        CW := DefaultControlWidth(C, Max(ClientW - CX, 1));
      if C.BoxH > 0 then
        CH := C.BoxH
      else
        CH := DefaultControlHeight(C);
      L := ClientLeft + CX;
      T := ClientTop + CY;
      Rgt := L + CW - 1;
      Bot := T + CH - 1;
      if L < ClientLeft then
        L := ClientLeft;
      if T < ClientTop then
        T := ClientTop;
      if Rgt > ClientRight then
        Rgt := ClientRight;
      if Bot > ClientBottom then
        Bot := ClientBottom;
      if Rgt < L then
        Rgt := L;
      if Bot < T then
        Bot := T;
      FControlBounds[I] := TRectI.Make(L, T, Rgt, Bot);
    end;
    Exit;
  end;

  // Protocol 1.0: sequential flow layout.
  InnerLeft := FBounds.Left + 2;
  InnerRight := FBounds.Right - 2;
  if InnerRight < InnerLeft then
    InnerRight := InnerLeft;
  Y := FBounds.Top + 2;
  BtnX := InnerLeft;
  InButtonRow := False;

  for I := 0 to High(FDecl.Controls) do
  begin
    C := FDecl.Controls[I];
    if C.Kind = dckButton then
    begin
      BtnW := ButtonCellWidth(C);
      if not InButtonRow then
      begin
        InButtonRow := True;
        BtnX := InnerLeft;
      end
      else if (BtnX > InnerLeft) and (BtnX + BtnW - 1 > InnerRight) then
      begin
        // Wrap overflowing buttons onto the next row.
        Inc(Y);
        BtnX := InnerLeft;
      end;
      FControlBounds[I] := TRectI.Make(BtnX, Y, Min(BtnX + BtnW - 1, InnerRight), Y);
      Inc(BtnX, BtnW + 2);
    end
    else
    begin
      if InButtonRow then
      begin
        Inc(Y);
        InButtonRow := False;
        BtnX := InnerLeft;
      end;
      if C.Kind = dckList then
      begin
        Span := ControlRowSpan(C);
        FControlBounds[I] := TRectI.Make(InnerLeft, Y, InnerRight, Y + Span - 1);
        Inc(Y, Span);
      end
      else if C.Kind = dckRadioGroup then
      begin
        Span := ControlRowSpan(C);
        FControlBounds[I] := TRectI.Make(InnerLeft, Y, InnerRight, Y + Span - 1);
        Inc(Y, Span);
      end
      else
      begin
        FControlBounds[I] := TRectI.Make(InnerLeft, Y, InnerRight, Y);
        Inc(Y);
      end;
    end;
  end;
end;

procedure TDialogHost.DrawColorSampleControl(const AGrid: TTerminalGrid;
  const R: TRectI; const C: TDialogControl);
var
  SampleFg, SampleBg: TAlphaColor;
  SrcIdx: Integer;
begin
  // Re-resolved every Draw from the live (possibly uncommitted) text
  // of the source input(s) — no rebuild/reopen needed as the user
  // types. Blank/unparsable source text keeps whatever's pre-set
  // below as the fallback for that channel.
  //
  // When C.PanelState names a panel row (color-coding's editor sets
  // this — colorpicker.json's single-channel preview doesn't), an
  // unset channel previews as the THEME's own resolved color for
  // that row/state — the exact same "0 = inherit" meaning
  // TColorCodingColor.Fg/Bg=0 already has, so this shows what the
  // panel would actually render, not a placeholder. Without a theme
  // or a named state, falls back to fixed black-on-gray (still not
  // white — see dialog body note below).
  SampleFg := TAlphaColor($FF000000);
  SampleBg := TAlphaColor($FFC0C0C0); // not white: would blend into this Host's own (white) dialog body, hiding the swatch's extent
  if (C.PanelState <> cspsNone) and Assigned(FTheme) then
    FTheme.ResolveFileRowColors(False, False, False, '',
      C.PanelState = cspsSelected, C.PanelState = cspsCurrent, True,
      SampleFg, SampleBg);
  SrcIdx := FindInputIndexById(C.FgSourceId);
  if SrcIdx >= 0 then
    HexToColor(FDecl.Controls[SrcIdx].Edit.Text, SampleFg);
  SrcIdx := FindInputIndexById(C.BgSourceId);
  if SrcIdx >= 0 then
    HexToColor(FDecl.Controls[SrcIdx].Edit.Text, SampleBg);
  FillGridRect(AGrid, R.Left, R.Top, R.Right, R.Bottom, ' ', SampleFg, SampleBg);
  PutGridText(AGrid, R.Left, R.Top, Copy(C.Text, 1, Max(R.Width, 1)),
    SampleFg, SampleBg);
end;

procedure TDialogHost.DrawRadioGroupControl(const AGrid: TTerminalGrid;
  const R: TRectI; AIndex: Integer; const C: TDialogControl;
  ALabelFg, ALabelBg: TAlphaColor);
var
  J, Span, SelIdx: Integer;
  St: TThemeWidgetState;
  ItemFg, ItemBg: TAlphaColor;
begin
  Span := 0;
  SelIdx := ListSelectedIndexOf(C.Id);
  if C.Text <> '' then
  begin
    PutGridTextClipped(AGrid, R.Left, R.Top, R.Right,
      Copy(C.Text, 1, Max(R.Width, 1)), ALabelFg, ALabelBg);
    Span := 1;
  end;
  for J := 0 to High(C.Items) do
  begin
    if R.Top + Span + J >= FBounds.Bottom then
      Break;
    St := [];
    if (AIndex = FFocusIndex) and (J = SelIdx) then
      Include(St, twFocused);
    if Assigned(FTheme) and not FDecl.IsWarning then
      FTheme.DrawRadioBox(AGrid,
        TRectI.Make(R.Left, R.Top + Span + J, R.Right, R.Top + Span + J),
        C.Items[J], J = SelIdx, St)
    else
    begin
      if twFocused in St then
        ResolveSelectedRowColors(ItemFg, ItemBg)
      else
      begin
        ItemFg := ALabelFg;
        ItemBg := ALabelBg;
      end;
      PutGridTextClipped(AGrid, R.Left, R.Top + Span + J, R.Right,
        IfThen(J = SelIdx, '(*) ', '( ) ') + C.Items[J],
        ItemFg, ItemBg);
    end;
  end;
end;

procedure TDialogHost.DrawListControl(const AGrid: TTerminalGrid; const R: TRectI;
  AIndex: Integer; const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
var
  J, Span, Idx, TextW, Count, SelIdx: Integer;
  Line: string;
  RowFg, RowBg: TAlphaColor;
begin
  Span := ListViewHeight(AIndex);
  SelIdx := ListSelectedIndexOf(C.Id);
  if Span <= 1 then
  begin
    // Height 1: combo-style — show selected item (not items[0]).
    if (SelIdx >= 0) and (SelIdx <= High(C.Items)) then
      Line := C.Items[SelIdx]
    else
      Line := '';
    Line := PadGridLine(Line, Max(R.Width, 1));
    if R.Width >= 2 then
      Line[R.Width] := WideChar($2193); // ↓
    ResolveSelectedRowColors(RowFg, RowBg);
    PutGridText(AGrid, R.Left, R.Top, Line, RowFg, RowBg);
  end
  else
  begin
    EnsureListInView(AIndex);
    TextW := Max(R.Width - 1, 1); // reserve right column for scrollbar
    Count := Length(C.Items);
    for J := 0 to Span - 1 do
    begin
      if R.Top + J >= FBounds.Bottom then
        Break;
      Idx := FListScrollTop + J;
      if Idx <= High(C.Items) then
        Line := C.Items[Idx]
      else
        Line := '';
      Line := PadGridLine(Line, TextW);
      ResolveRowHighlight(Idx = SelIdx, ALabelFg, ALabelBg, RowFg, RowBg);
      PutGridText(AGrid, R.Left, R.Top + J, Line, RowFg, RowBg);
    end;
    DrawDialogScrollBar(AGrid, R.Right, R.Top, R.Bottom,
      FListScrollTop, Count, Span);
  end;
end;

procedure TDialogHost.DrawDropArrow(const AGrid: TTerminalGrid; ACol, ARow: Integer;
  const AFieldColors: TInputLineColors);
begin
  // Inverse of the field it belongs to: stands out as a button in any theme.
  PutGridText(AGrid, ACol, ARow, WideChar($2193), AFieldColors.Bg, AFieldColors.Fg);
end;

procedure TDialogHost.DrawDropDownControl(const AGrid: TTerminalGrid;
  const R: TRectI; AIndex: Integer; const C: TDialogControl);
var
  Idx: Integer;
  Line: string;
  RowFg, RowBg: TAlphaColor;
  Colors: TInputLineColors;
begin
  Idx := ListSelectedIndexOf(C.Id);
  if (Idx >= 0) and (Idx <= High(C.Items)) then
    Line := C.Items[Idx]
  else
    Line := '';
  Line := PadGridLine(Line, Max(R.Width, 1));
  // Focused / open: black-on-cyan like Sort menu cursor; else cyan field.
  if (AIndex = FFocusIndex) or (FDropOpenIndex = AIndex) then
  begin
    ResolveSelectedRowColors(RowFg, RowBg);
    Colors.Fg := RowFg;
    Colors.Bg := RowBg;
  end
  else
    Colors := InputLineDialogColors(False);
  PutGridText(AGrid, R.Left, R.Top, Line, Colors.Fg, Colors.Bg);
  if R.Width >= 2 then
    DrawDropArrow(AGrid, R.Left + R.Width - 1, R.Top, Colors);
end;

procedure TDialogHost.DrawButtonControl(const AGrid: TTerminalGrid; const R: TRectI;
  AIndex: Integer; const C: TDialogControl);
var
  St: TThemeWidgetState;
begin
  St := [];
  if AIndex = FFocusIndex then
    Include(St, twFocused);
  if C.IsDefault then
    Include(St, twSelected);
  if Assigned(FTheme) then
    FTheme.DrawButton(AGrid, R, C.Text, St)
  else if C.IsDefault then
    PutGridText(AGrid, R.Left, R.Top, '< ' + C.Text + ' >',
      TAlphaColor($FF000000), TAlphaColor($FF00AAAA))
  else
    PutGridText(AGrid, R.Left, R.Top, '[ ' + C.Text + ' ]',
      TAlphaColor($FF000000), TAlphaColor($FF00AAAA));
end;

procedure TDialogHost.Draw(const AGrid: TTerminalGrid; AAreaW, AAreaH: Integer);
var
  I: Integer;
  St: TThemeWidgetState;
  Colors: TInputLineColors;
  C: TDialogControl;
  LabelFg, LabelBg, ItemFg, ItemBg: TAlphaColor;
  R: TRectI;
begin
  if not FVisible then
    Exit;
  LayoutIn(AAreaW, AAreaH);
  // FAR-style modal dim: darken the already-painted scene, then paint chrome.
  {$IFDEF SKIA}
  DimGridExcept(AGrid, FBounds, 88);
  {$ELSE}
  DimGridExcept(AGrid, FBounds, 72);
  {$ENDIF}
  if FDecl.IsWarning then
    DrawWarningDialogFrame(AGrid, FBounds, FDecl.Title)
  else if Assigned(FTheme) then
    FTheme.DrawDialogFrame(AGrid, FBounds, FDecl.Title, [twFocused])
  else
    FillGridRect(AGrid, FBounds.Left, FBounds.Top, FBounds.Right, FBounds.Bottom,
      ' ', TAlphaColor($FF000000), TAlphaColor($FFFFFFFF));
  DrawDialogShadow(AGrid, FBounds);

  if FDecl.IsWarning then
  begin
    LabelFg := TAlphaColor($FFFFFFFF);
    LabelBg := TAlphaColor($FFAA0000);
  end
  else if Assigned(FTheme) then
    FTheme.ResolveDialogRowColors(False, LabelFg, LabelBg)
  else
  begin
    LabelFg := TAlphaColor($FF000000);
    LabelBg := TAlphaColor($FFFFFFFF);
  end;

  for I := 0 to High(FDecl.Controls) do
  begin
    if (I > High(FControlBounds)) then
      Break;
    R := FControlBounds[I];
    if (R.Top > FBounds.Bottom - 1) or (R.Bottom < FBounds.Top + 1) or
       (R.Left > FBounds.Right - 1) or (R.Right < FBounds.Left + 1) then
      Continue;
    C := FDecl.Controls[I];
    St := [];
    if I = FFocusIndex then
      Include(St, twFocused);
    case C.Kind of
      dckLabel, dckStatus:
        TDialogRenderer.DrawLabel(AGrid, R, C.Text, LabelFg, LabelBg);
      dckColorSample:
        DrawColorSampleControl(AGrid, R, C);
      dckInput:
        begin
          Colors := InputLineDialogColors(I = FFocusIndex);
          if IsHistoryInput(I) and (R.Width >= 3) then
          begin
            // Last cell: ↓ opens the history (like a dckDropDown field).
            InputLineDraw(AGrid, R.Left, R.Top, R.Width - 1,
              FDecl.Controls[I].Edit, I = FFocusIndex, Colors, FCursorVisible, False);
            DrawDropArrow(AGrid, R.Left + R.Width - 1, R.Top, Colors);
          end
          else
            InputLineDraw(AGrid, R.Left, R.Top, Max(R.Width, 8),
              FDecl.Controls[I].Edit, I = FFocusIndex, Colors, FCursorVisible,
              FDecl.Controls[I].Password);
        end;
      dckCheckbox:
        begin
          // Warning chrome is red: theme DrawCheckBox paints black-on-white
          // (dialog body), which shows as a white strip on the red fill —
          // worse after translation when the caption (and box) grow.
          if FDecl.IsWarning or not Assigned(FTheme) then
          begin
            if I = FFocusIndex then
              ResolveSelectedRowColors(ItemFg, ItemBg)
            else
            begin
              ItemFg := LabelFg;
              ItemBg := LabelBg;
            end;
            PutGridTextClipped(AGrid, R.Left, R.Top, R.Right,
              IfThen(C.Checked, '[x] ', '[ ] ') + C.Text,
              ItemFg, ItemBg);
          end
          else
            FTheme.DrawCheckBox(AGrid, R, C.Text, C.Checked, St);
        end;
      dckRadio:
        begin
          if FDecl.IsWarning or not Assigned(FTheme) then
          begin
            if I = FFocusIndex then
              ResolveSelectedRowColors(ItemFg, ItemBg)
            else
            begin
              ItemFg := LabelFg;
              ItemBg := LabelBg;
            end;
            PutGridTextClipped(AGrid, R.Left, R.Top, R.Right,
              IfThen(C.Checked, '(*) ', '( ) ') + C.Text,
              ItemFg, ItemBg);
          end
          else
            FTheme.DrawRadioBox(AGrid, R, C.Text, C.Checked, St);
        end;
      dckRadioGroup:
        DrawRadioGroupControl(AGrid, R, I, C, LabelFg, LabelBg);
      dckList:
        DrawListControl(AGrid, R, I, C, LabelFg, LabelBg);
      dckDropDown:
        DrawDropDownControl(AGrid, R, I, C);
      dckButton:
        DrawButtonControl(AGrid, R, I, C);
    end;
  end;
  // Half-block button shadows after faces (▄ right, ▀ below).
  for I := 0 to High(FDecl.Controls) do
  begin
    if (I > High(FControlBounds)) then
      Break;
    if FDecl.Controls[I].Kind <> dckButton then
      Continue;
    R := FControlBounds[I];
    if (R.Top > FBounds.Bottom - 1) or (R.Bottom < FBounds.Top + 1) then
      Continue;
    // ▄ sits at Right+1. Painting it onto the frame glyph replaces the
    // border with a half-block on white and looks like the button lost its
    // cyan. FitDialogToTranslatedText keeps two client cells free for this.
    if R.Right + 1 >= FBounds.Right then
      Continue;
    DrawButtonShadow(AGrid, R);
  end;
  DrawDropDownPopup(AGrid);
end;

function TDialogHost.ChromeContext: TFunctionBarContext;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if FDecl.Controls[I].Kind in [dckList, dckDropDown] then
      Exit(fbcDialogList);
  Result := fbcStubEdit;
end;

function TDialogHost.ContainsLocal(ALocalCol, ALocalRow: Integer): Boolean;
begin
  Result := False;
  if not FVisible then
    Exit;
  EnsureLayout;
  Result := FBounds.Contains(ALocalCol, ALocalRow);
end;

function TDialogHost.ControlCount: Integer;
begin
  Result := Length(FDecl.Controls);
end;

function TDialogHost.GetControl(AIndex: Integer): TDialogControl;
begin
  Result := FDecl.Controls[AIndex];
end;

function TDialogHost.ControlBoundsAt(AIndex: Integer): TRectI;
begin
  EnsureLayout;
  if (AIndex >= 0) and (AIndex <= High(FControlBounds)) then
    Result := FControlBounds[AIndex]
  else
    Result := TRectI.Make(0, 0, -1, -1);
end;

function TDialogHost.ControlIndexAt(ALocalCol, ALocalRow: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  if not FVisible then
    Exit;
  EnsureLayout;
  for I := 0 to High(FDecl.Controls) do
  begin
    if I > High(FControlBounds) then
      Break;
    if FControlBounds[I].Contains(ALocalCol, ALocalRow) then
      Exit(I);
  end;
end;

function TDialogHost.FocusedOrDefaultButtonId: string;
var
  I, Def: Integer;
begin
  Result := '';
  if FocusedIsButton then
    Exit(FDecl.Controls[FFocusIndex].Id);
  Def := FindDefaultButtonIndex;
  if Def >= 0 then
    Exit(FDecl.Controls[Def].Id);
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckButton) and
       DialogCmdIsAccept(FDecl.Controls[I].Id) then
      Exit(FDecl.Controls[I].Id);
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckButton) and not FDecl.Controls[I].IsCancel then
      Exit(FDecl.Controls[I].Id);
end;

function TDialogHost.FocusedControlId: string;
begin
  if (FFocusIndex >= 0) and (FFocusIndex <= High(FDecl.Controls)) then
    Result := FDecl.Controls[FFocusIndex].Id
  else
    Result := '';
end;

function TDialogHost.HandleClick(ALocalCol, ALocalRow: Integer;
  AShift: TShiftState): Boolean;
var
  I, Row, Idx, Count, Span, ViewH: Integer;
  C: TDialogControl;
  R, Popup: TRectI;
  NeedBar: Boolean;
begin
  Result := False;
  if not FVisible then
    Exit;
  // Hit-test must use current layout even if Draw has not run yet this frame.
  EnsureLayout;
  if WindowFrameCloseHit(FBounds, ALocalCol, ALocalRow) then
  begin
    CloseDropDown;
    FireCancel;
    Exit(True);
  end;
  if not FBounds.Contains(ALocalCol, ALocalRow) then
  begin
    CloseDropDown;
    // Outside click = Cancel when a cancel button exists.
    FireCancel;
    Exit(True);
  end;

  // DropDown popup takes priority while open.
  if (FDropOpenIndex >= 0) and DropPopupBounds(Popup) then
  begin
    if Popup.Contains(ALocalCol, ALocalRow) then
    begin
      EnsureDropHoverInView;
      Row := ALocalRow - (Popup.Top + 1);
      ViewH := Popup.Height - 2;
      Count := Length(FDecl.Controls[FDropOpenIndex].Items);
      NeedBar := Count > ViewH;
      if NeedBar and (ALocalCol = Popup.Right - 1) and (ViewH > 0) then
      begin
        if ALocalRow = Popup.Top + 1 then
          FDropHover := EnsureRange(FDropHover - 1, 0, Count - 1)
        else if ALocalRow = Popup.Bottom - 1 then
          FDropHover := EnsureRange(FDropHover + 1, 0, Count - 1)
        else
          FDropHover := EnsureRange(
            Round((ALocalRow - Popup.Top - 2) * (Count - 1) / Max(ViewH - 3, 1)),
            0, Count - 1);
        EnsureDropHoverInView;
        NotifyChanged;
        Exit(True);
      end;
      if (ALocalCol > Popup.Left) and
         ((not NeedBar and (ALocalCol < Popup.Right)) or
          (NeedBar and (ALocalCol < Popup.Right - 1))) and
         (Row >= 0) and (Row < ViewH) then
      begin
        Idx := FDropScrollTop + Row;
        if (Idx >= 0) and (Idx <= High(FDecl.Controls[FDropOpenIndex].Items)) then
        begin
          FDropHover := Idx;
          CommitDropDown;
        end;
        Exit(True);
      end;
      Exit(True);
    end;
    // Click outside popup collapses without changing selection.
    if (FDropOpenIndex <= High(FControlBounds)) and
       FControlBounds[FDropOpenIndex].Contains(ALocalCol, ALocalRow) then
    begin
      CloseDropDown;
      Exit(True);
    end;
    CloseDropDown;
    // Fall through to hit-test other controls.
  end;

  for I := 0 to High(FDecl.Controls) do
  begin
    if I > High(FControlBounds) then
      Break;
    R := FControlBounds[I];
    if not R.Contains(ALocalCol, ALocalRow) then
      Continue;
    C := FDecl.Controls[I];
    case C.Kind of
      dckButton:
        begin
          FFocusIndex := I;
          FireCommand(C.Id);
          Exit(True);
        end;
      dckCheckbox:
        begin
          FFocusIndex := I;
          FDecl.Controls[I].Checked := not FDecl.Controls[I].Checked;
          NotifyChanged;
          Exit(True);
        end;
      dckRadio:
        begin
          FFocusIndex := I;
          SelectRadio(I);
          NotifyChanged;
          Exit(True);
        end;
      dckInput:
        begin
          FFocusIndex := I;
          if IsHistoryInput(I) and (R.Width >= 3) and
             (ALocalCol = R.Left + R.Width - 1) then
          begin
            OpenDropDown(I);
            NotifyChanged;
            Exit(True);
          end;
          // Caret to the clicked cell; double click = word, triple = all;
          // Shift+click extends the selection from the current caret.
          if ssShift in AShift then
          begin
            FClicks.Reset;
            InputLineMouseClick(FDecl.Controls[I].Edit, ALocalCol - R.Left, 1, True);
          end
          else
            InputLineMouseClick(FDecl.Controls[I].Edit, ALocalCol - R.Left,
              FClicks.Hit(ALocalCol, ALocalRow));
          NotifyChanged;
          Exit(True);
        end;
      dckDropDown:
        begin
          FFocusIndex := I;
          if FDropOpenIndex = I then
            CloseDropDown
          else
            OpenDropDown(I);
          Exit(True);
        end;
      dckList:
        begin
          Span := R.Height;
          if (Span > 1) and (ALocalCol = R.Right) then
          begin
            // Scrollbar: ▲ / ▼ / track → move selection.
            FFocusIndex := I;
            EnsureListInView(I);
            Count := Length(FDecl.Controls[I].Items);
            if Count = 0 then
              Exit(True);
            if ALocalRow = R.Top then
              SetListSelectedIndex(I, ListSelectedIndexOf(C.Id) - 1)
            else if ALocalRow = R.Bottom then
              SetListSelectedIndex(I, ListSelectedIndexOf(C.Id) + 1)
            else if Count > Span then
              SetListSelectedIndex(I,
                EnsureRange(Round((ALocalRow - R.Top - 1) * (Count - 1) /
                  Max(Span - 3, 1)), 0, Count - 1))
            else
              SetListSelectedIndex(I, 0);
            NotifyChanged;
            Exit(True);
          end;
          Row := ALocalRow - R.Top;
          if Span > 1 then
          begin
            EnsureListInView(I);
            Idx := FListScrollTop + Row;
          end
          else
            Idx := Row;
          if (Row >= 0) and (Row < Span) and (Idx >= 0) and
             (Idx <= High(FDecl.Controls[I].Items)) then
          begin
            FFocusIndex := I;
            SetListSelectedIndex(I, Idx);
            NotifyChanged;
            Exit(True);
          end;
        end;
      dckRadioGroup:
        begin
          Row := ALocalRow - R.Top;
          if C.Text <> '' then
            Dec(Row);
          if (Row >= 0) and (Row <= High(FDecl.Controls[I].Items)) then
          begin
            FFocusIndex := I;
            SetListSelectedIndex(I, Row);
            NotifyChanged;
            Exit(True);
          end;
        end;
    end;
  end;
  Result := True;
end;

function TDialogHost.HandleInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  I, ViewH, Last: Integer;
  Ch: Char;
  C: TDialogControl;
  LineRes: TInputLineResult;
begin
  Result := False;
  if not FVisible then
    Exit;

  if not FCursorVisible then
  begin
    FCursorVisible := True;
    NotifyChanged;
  end;

  Result := True;

  // Open DropDown: Enter commits, Esc collapses (does not cancel dialog).
  if FDropOpenIndex >= 0 then
  begin
    if NormalizeAcceptKey(AKey, AKeyChar) or (AKey = vkSpace) or (AKeyChar = ' ') then
    begin
      CommitDropDown;
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;
    if AKey = vkEscape then
    begin
      CloseDropDown;
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;
    // History list: Del forgets the highlighted entry.
    if (AKey = vkDelete) and IsHistoryInput(FDropOpenIndex) then
    begin
      RemoveDropHoverFromHistory;
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;
    if AKey = vkTab then
    begin
      CloseDropDown;
      FFocusIndex := NextFocusable(FFocusIndex, not (ssShift in AShift));
      NotifyChanged;
      AKey := 0;
      Exit;
    end;
    if (AKey = vkUp) or (AKey = vkDown) or (AKey = vkHome) or (AKey = vkEnd) or
       (AKey = vkPrior) or (AKey = vkNext) then
    begin
      if Length(FDecl.Controls[FDropOpenIndex].Items) > 0 then
      begin
        Last := High(FDecl.Controls[FDropOpenIndex].Items);
        ViewH := Max(DropPopupViewHeight, 1);
        if AKey = vkUp then
          FDropHover := EnsureRange(FDropHover - 1, 0, Last)
        else if AKey = vkDown then
          FDropHover := EnsureRange(FDropHover + 1, 0, Last)
        else if AKey = vkHome then
          FDropHover := 0
        else if AKey = vkEnd then
          FDropHover := Last
        else if AKey = vkPrior then
          FDropHover := EnsureRange(FDropHover - ViewH, 0, Last)
        else
          FDropHover := EnsureRange(FDropHover + ViewH, 0, Last);
        EnsureDropHoverInView;
        NotifyChanged;
      end;
      AKey := 0;
      Exit;
    end;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;

  if NormalizeAcceptKey(AKey, AKeyChar) then
  begin
    FireAccept;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;

  if AKey = vkEscape then
  begin
    FireCancel;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;

  if AKey = vkTab then
  begin
    FFocusIndex := NextFocusable(FFocusIndex, not (ssShift in AShift));
    NotifyChanged;
    AKey := 0;
    Exit;
  end;

  // History input: Ctrl+Down / Alt+Down drop the history down.
  if IsHistoryInput(FFocusIndex) and (AKey = vkDown) and
     ((ssCtrl in AShift) or (ssAlt in AShift)) and not (ssShift in AShift) then
  begin
    OpenDropDown(FFocusIndex);
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;

  // Open DropDown: Space / Alt+Down / F4.
  if (FFocusIndex >= 0) and (FFocusIndex <= High(FDecl.Controls)) and
     (FDecl.Controls[FFocusIndex].Kind = dckDropDown) then
  begin
    if (AKey = vkF4) or ((AKey = vkDown) and (ssAlt in AShift)) or
       (AKey = vkSpace) or (AKeyChar = ' ') then
    begin
      OpenDropDown(FFocusIndex);
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;
  end;

  if (FFocusIndex >= 0) and (FFocusIndex <= High(FDecl.Controls)) and
     ((AKey = vkSpace) or (AKeyChar = ' ')) then
  begin
    if FDecl.Controls[FFocusIndex].Kind = dckCheckbox then
    begin
      FDecl.Controls[FFocusIndex].Checked := not FDecl.Controls[FFocusIndex].Checked;
      NotifyChanged;
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;
    if FDecl.Controls[FFocusIndex].Kind = dckRadio then
    begin
      SelectRadio(FFocusIndex);
      NotifyChanged;
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;
    if FDecl.Controls[FFocusIndex].Kind = dckRadioGroup then
    begin
      // Space keeps current selection (already exclusive).
      NotifyChanged;
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;
    if FDecl.Controls[FFocusIndex].Kind = dckButton then
    begin
      FireCommand(FDecl.Controls[FFocusIndex].Id);
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;
  end;

  // Hot-keys / Mnemonics in dialogs trigger when Alt is pressed OR when not focused on an input box.
  if (ssAlt in AShift) or not FocusedIsInput then
  begin
    Ch := UpCase(AKeyChar);
    if (Ch < 'A') or (Ch > 'Z') then
    begin
      if (AKeyChar = 'ы') or (AKeyChar = 'Ы') then Ch := 'S'
      else if (AKeyChar = 'ф') or (AKeyChar = 'Ф') then Ch := 'A'
      else if (AKeyChar = 'в') or (AKeyChar = 'В') then Ch := 'D'
      else if (AKeyChar = 'к') or (AKeyChar = 'К') then Ch := 'R'
      else if (AKeyChar = 'с') or (AKeyChar = 'С') then Ch := 'C'
      else if (AKeyChar = 'щ') or (AKeyChar = 'Щ') then Ch := 'O'
      else if (AKeyChar = 'д') or (AKeyChar = 'Д') then Ch := 'Y'
      else if (AKeyChar = 'н') or (AKeyChar = 'Н') or (AKeyChar = 'т') or (AKeyChar = 'Т') then Ch := 'N';
    end;
    if (Ch = #0) and (AKey >= Ord('A')) and (AKey <= Ord('Z')) then
      Ch := Char(AKey);

    // Explicit Y/N confirmation for Yes/No dialogs
    if (Ch = 'Y') or (AKeyChar = 'y') or (AKeyChar = 'Y') or
       (AKeyChar = 'д') or (AKeyChar = 'Д') then
    begin
      for I := 0 to High(FDecl.Controls) do
      begin
        C := FDecl.Controls[I];
        if (C.Kind = dckButton) and DialogCmdIsYes(C.Id) then
        begin
          FireCommand(C.Id);
          AKey := 0;
          AKeyChar := #0;
          Exit;
        end;
      end;
    end;

    if (Ch = 'N') or (AKeyChar = 'n') or (AKeyChar = 'N') or
       (AKeyChar = 'н') or (AKeyChar = 'Н') then
    begin
      for I := 0 to High(FDecl.Controls) do
      begin
        C := FDecl.Controls[I];
        if (C.Kind = dckButton) and DialogCmdIsNo(C.Id) then
        begin
          FireCommand(C.Id);
          AKey := 0;
          AKeyChar := #0;
          Exit;
        end;
      end;
    end;

    if (Ch >= 'A') and (Ch <= 'Z') then
    begin
      for I := 0 to High(FDecl.Controls) do
      begin
        C := FDecl.Controls[I];
        if ExtractControlHotkey(C.Text, C.Id) = Ch then
        begin
          case C.Kind of
            dckButton:
              begin
                FireCommand(C.Id);
                AKey := 0;
                AKeyChar := #0;
                Exit;
              end;
            dckCheckbox:
              begin
                FFocusIndex := I;
                FDecl.Controls[I].Checked := not FDecl.Controls[I].Checked;
                NotifyChanged;
                AKey := 0;
                AKeyChar := #0;
                Exit;
              end;
            dckRadio:
              begin
                FFocusIndex := I;
                SelectRadio(I);
                NotifyChanged;
                AKey := 0;
                AKeyChar := #0;
                Exit;
              end;
            dckInput, dckList, dckDropDown, dckRadioGroup:
              begin
                FFocusIndex := I;
                NotifyChanged;
                AKey := 0;
                AKeyChar := #0;
                Exit;
              end;
          end;
        end;
      end;
    end;
  end;

  if (FFocusIndex >= 0) and
     (FDecl.Controls[FFocusIndex].Kind in [dckList, dckRadioGroup, dckDropDown]) and
     ((AKey = vkUp) or (AKey = vkDown) or (AKey = vkHome) or (AKey = vkEnd) or
      (AKey = vkPrior) or (AKey = vkNext)) then
  begin
    if Length(FDecl.Controls[FFocusIndex].Items) > 0 then
    begin
      if AKey = vkUp then
        SetListSelectedIndex(FFocusIndex,
          FDecl.Controls[FFocusIndex].SelectedIndex - 1)
      else if AKey = vkDown then
        SetListSelectedIndex(FFocusIndex,
          FDecl.Controls[FFocusIndex].SelectedIndex + 1)
      else if AKey = vkHome then
        SetListSelectedIndex(FFocusIndex, 0)
      else if AKey = vkEnd then
        SetListSelectedIndex(FFocusIndex,
          High(FDecl.Controls[FFocusIndex].Items))
      else if (AKey = vkPrior) and
        (FDecl.Controls[FFocusIndex].Kind = dckList) then
        SetListSelectedIndex(FFocusIndex,
          FDecl.Controls[FFocusIndex].SelectedIndex -
            Max(ListViewHeight(FFocusIndex), 1))
      else if (AKey = vkNext) and
        (FDecl.Controls[FFocusIndex].Kind = dckList) then
        SetListSelectedIndex(FFocusIndex,
          FDecl.Controls[FFocusIndex].SelectedIndex +
            Max(ListViewHeight(FFocusIndex), 1))
      else if AKey = vkPrior then
        SetListSelectedIndex(FFocusIndex,
          FDecl.Controls[FFocusIndex].SelectedIndex - 1)
      else
        SetListSelectedIndex(FFocusIndex,
          FDecl.Controls[FFocusIndex].SelectedIndex + 1);
      NotifyChanged;
    end;
    AKey := 0;
    Exit;
  end;

  if FocusedIsInput then
  begin
    // Copy/writeback: dynarray-of-record field as var can drop edits otherwise.
    C := FDecl.Controls[FFocusIndex];
    if C.Password and (ssCtrl in AShift) and
       ((AKey = Ord('C')) or (AKey = Ord('X')) or (AKey = vkInsert)) then
    begin
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;
    LineRes := InputLineHandleInput(C.Edit, AKey, AShift, AKeyChar);
    FDecl.Controls[FFocusIndex] := C;
    case LineRes of
      ilrSubmit:
        FireAccept;
      ilrCancel:
        FireCommand(cDlgCmdCancel);
    else
      NotifyChanged;
    end;
    Exit;
  end;

  if (AKey = vkLeft) or (AKey = vkRight) or (AKey = vkUp) or (AKey = vkDown) then
  begin
    FFocusIndex := NextFocusable(FFocusIndex, (AKey = vkRight) or (AKey = vkDown));
    NotifyChanged;
    AKey := 0;
    Exit;
  end;

  AKey := 0;
  AKeyChar := #0;
end;

end.
