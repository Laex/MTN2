unit uDiffViewer;

{ Compare-and-merge window (Ctrl+Alt+C on two text files). Two text columns fill the
  Dual Panel area: the differing lines are marked, the changed part of a changed
  line is highlighted, a difference is copied in either direction, every copy can
  be undone and the changed sides are saved back. Like the Help window it is modal:
  the host paints it over everything and sends it every key and mouse event while
  it is visible. The line model lives in uDiffMerge. A pair that is binary, too
  big, unreadable or identical is handed back through the fallback so the plain
  compare result is shown instead. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uThemeTypes, uTerminalTypes, uVfsTypes, uDiffMerge, uTextEncoding;

type
  TDiffViewer = class
  private
    FTheme: IThemeRenderer;
    FLife: ILifeFlag;
    FOnChanged: TNotifyEvent;
    FModel: TDiffMerge;
    FVfs: IVirtualFileSystem;
    FLeftUri, FRightUri, FLeftName, FRightName: string;
    FLeftEnc, FRightEnc: TTextFileEncoding;
    FLeftEol, FRightEol: string;
    FLeftFinal, FRightFinal: Boolean;
    FVisible: Boolean;
    FDiscardArmed: Boolean;
    FSaving: Boolean;
    FLoadGen: Integer;
    FCur: Integer;      // selected row
    FTop: Integer;      // first visible row
    FHScroll: Integer;  // first visible character of the texts
    FBodyRows: Integer; // rows the body showed at the last Paint
    FNote: string;
    FBounds: TRectI;    // host-local cells of the last Paint
    FBodyTop: Integer;
    FScrollX: Integer;
    FKeyBarY: Integer;  // host row of the F-key bar at the last Paint, -1 when hidden
    FHostW: Integer;
    FMods: TShiftState; // held modifiers, for the F-key bar labels
    procedure Changed;
    procedure Show;
    procedure ReleaseModel;
    procedure EnsureCursorVisible;
    procedure SetCursor(ARow: Integer);
    procedure MoveCursor(ADelta: Integer);
    procedure GoToHunk(ARow: Integer);
    procedure CopySelected(AToRight: Boolean);
    procedure DoUndo;
    procedure SaveSide(ALeft: Boolean; const ANext: TProc);
    procedure Save;
    procedure RequestClose;
    function StatusSegments: TArray<string>;
    procedure DrawSide(const AGrid: TTerminalGrid; AX, AY, ANumW, ATextW, ANo: Integer;
      const AText: string; AFg, ABg, ANumFg, AHlFg, AHlBg: TAlphaColor;
      AHlStart, AHlLen: Integer);
  public
    constructor Create(const ATheme: IThemeRenderer);
    destructor Destroy; override;
    property Visible: Boolean read FVisible;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    /// <summary>Reads both files and opens the window; AOnFallback runs instead when
    /// the pair cannot be merged (binary, too big, unreadable, identical).</summary>
    procedure Open(const ALeftUri, ARightUri, ALeftName, ARightName: string;
      const AVfs: IVirtualFileSystem; const AOnFallback: TProc);
    /// <summary>Closes the window without asking about unsaved changes.</summary>
    procedure Close;
    procedure Paint(const AGrid: TTerminalGrid; AHostW, AHostH: Integer);
    function HandleInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function HandleMouseDown(AHostCol, AHostRow: Integer; AShift: TShiftState): Boolean;
    function HandleMouseWheel(ADelta: Integer): Boolean;
    /// <summary>Tracks the held modifiers for the F-key bar; True when the bar changed.</summary>
    function SetKeyModifiers(AShift: TShiftState): Boolean;
  end;

implementation

uses
  System.Math, uStrings, uChromeRows, uFunctionBar;

const
  cMaxBytes = 16 * 1024 * 1024;
  cMaxLines = 60000;
  cMinWidth = 40;
  cMinHeight = 10;
  cMarkerCols = 3;
  cHScrollStep = 8;
  cWheelRows = 3;
  cChangedFg = TAlphaColor($FFFFC030);
  cLeftOnlyFg = TAlphaColor($FFFF6060);
  cRightOnlyFg = TAlphaColor($FF60E060);

constructor TDiffViewer.Create(const ATheme: IThemeRenderer);
begin
  inherited Create;
  FTheme := ATheme;
  FLife := NewLifeFlag;
  FBounds := TRectI.Make(0, 0, -1, -1);
  FKeyBarY := -1;
end;

destructor TDiffViewer.Destroy;
begin
  FLife.Alive := False;
  ReleaseModel;
  inherited;
end;

procedure TDiffViewer.Changed;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TDiffViewer.ReleaseModel;
begin
  FreeAndNil(FModel);
end;

procedure TDiffViewer.Close;
begin
  Inc(FLoadGen);
  FVisible := False;
  ReleaseModel;
  Changed;
end;

procedure TDiffViewer.Open(const ALeftUri, ARightUri, ALeftName, ARightName: string;
  const AVfs: IVirtualFileSystem; const AOnFallback: TProc);
var
  Gen: Integer;
  Token: IJobCancelToken;
  Life: ILifeFlag;
begin
  if not Assigned(AVfs) then
  begin
    if Assigned(AOnFallback) then
      AOnFallback();
    Exit;
  end;
  FVfs := AVfs;
  FLeftUri := ALeftUri;
  FRightUri := ARightUri;
  FLeftName := ALeftName;
  FRightName := ARightName;
  Life := FLife;
  Inc(FLoadGen);
  Gen := FLoadGen;
  Token := TJobCancelToken.Create;
  AVfs.ReadBytesAsync(ALeftUri, cMaxBytes, Token,
    procedure(const ALeftBytes: TBytes; const ALeftErr: TVfsError)
    begin
      if not Life.Alive or (Gen <> FLoadGen) then
        Exit;
      if ALeftErr.Code <> vecOk then
      begin
        if Assigned(AOnFallback) then
          AOnFallback();
        Exit;
      end;
      AVfs.ReadBytesAsync(ARightUri, cMaxBytes, Token,
        procedure(const ARightBytes: TBytes; const ARightErr: TVfsError)
        var
          LeftText, RightText: string;
          LeftBin, RightBin: Boolean;
          LeftLines, RightLines: TArray<string>;
          Usable: Boolean;
        begin
          if not Life.Alive or (Gen <> FLoadGen) then
            Exit;
          Usable := ARightErr.Code = vecOk;
          if Usable then
          begin
            DetectAndDecodeText(ALeftBytes, LeftText, FLeftEnc, LeftBin);
            DetectAndDecodeText(ARightBytes, RightText, FRightEnc, RightBin);
            Usable := not (LeftBin or RightBin);
          end;
          if Usable then
          begin
            LeftLines := SplitTextLines(LeftText, FLeftEol, FLeftFinal);
            RightLines := SplitTextLines(RightText, FRightEol, FRightFinal);
            Usable := (Length(LeftLines) <= cMaxLines) and (Length(RightLines) <= cMaxLines);
          end;
          if Usable then
          begin
            ReleaseModel;
            FModel := TDiffMerge.Create(LeftLines, RightLines);
            Usable := FModel.HunkCount > 0;
          end;
          if not Usable then
          begin
            ReleaseModel;
            if Assigned(AOnFallback) then
              AOnFallback();
            Exit;
          end;
          Show;
        end);
    end);
end;

procedure TDiffViewer.Show;
begin
  FDiscardArmed := False;
  FSaving := False;
  FNote := '';
  FHScroll := 0;
  FTop := 0;
  FCur := FModel.Hunks[0].FirstRow;
  FBodyRows := 20;
  FVisible := True;
  EnsureCursorVisible;
  Changed;
end;

procedure TDiffViewer.EnsureCursorVisible;
var
  Rows: Integer;
begin
  Rows := Max(FBodyRows, 1);
  if FCur < FTop then
    FTop := FCur
  else if FCur >= FTop + Rows then
    FTop := FCur - Rows + 1;
  FTop := EnsureRange(FTop, 0, Max(Length(FModel.Rows) - Rows, 0));
end;

procedure TDiffViewer.SetCursor(ARow: Integer);
begin
  if not Assigned(FModel) or (Length(FModel.Rows) = 0) then
    Exit;
  FCur := EnsureRange(ARow, 0, High(FModel.Rows));
  FNote := '';
  FDiscardArmed := False;
  EnsureCursorVisible;
end;

procedure TDiffViewer.MoveCursor(ADelta: Integer);
begin
  SetCursor(FCur + ADelta);
end;

procedure TDiffViewer.GoToHunk(ARow: Integer);
begin
  if ARow >= 0 then
    SetCursor(ARow);
end;

procedure TDiffViewer.CopySelected(AToRight: Boolean);
var
  H: Integer;
begin
  if FSaving then
    Exit;
  H := FModel.HunkOfRow(FCur);
  FDiscardArmed := False;
  if H < 0 then
  begin
    FNote := T('ui.diffMerge.notOnDifference', 'Select a marked line first.');
    Exit;
  end;
  FNote := '';
  if not FModel.CopyHunk(H, AToRight) then
    Exit;
  // The copied hunk is gone; its place is taken by the next one.
  if H < FModel.HunkCount then
    FCur := FModel.Hunks[H].FirstRow
  else if FModel.HunkCount > 0 then
    FCur := FModel.Hunks[FModel.HunkCount - 1].FirstRow
  else
    FCur := Min(FCur, High(FModel.Rows));
  EnsureCursorVisible;
end;

procedure TDiffViewer.DoUndo;
begin
  if FSaving or not FModel.CanUndo then
    Exit;
  FModel.Undo;
  FDiscardArmed := False;
  FNote := '';
  FCur := EnsureRange(FCur, 0, Max(High(FModel.Rows), 0));
  EnsureCursorVisible;
end;

procedure TDiffViewer.SaveSide(ALeft: Boolean; const ANext: TProc);
var
  Uri, Text: string;
  Enc: TTextFileEncoding;
  Life: ILifeFlag;
begin
  if ALeft then
  begin
    Uri := FLeftUri;
    Enc := FLeftEnc;
    Text := JoinTextLines(FModel.LeftLines, FLeftEol, FLeftFinal);
  end
  else
  begin
    Uri := FRightUri;
    Enc := FRightEnc;
    Text := JoinTextLines(FModel.RightLines, FRightEol, FRightFinal);
  end;
  Life := FLife;
  FVfs.WriteTextAsync(Uri, Text, Enc, TJobCancelToken.Create,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      if not Life.Alive or not Assigned(FModel) then
        Exit;
      if not ASuccess then
      begin
        FSaving := False;
        FNote := T('ui.diffMerge.saveFailed', 'Save failed: %s', [AError.Message]);
        Changed;
        Exit;
      end;
      FModel.MarkSaved(ALeft, not ALeft);
      if Assigned(ANext) then
        ANext()
      else
      begin
        FSaving := False;
        FNote := T('ui.diffMerge.saved', 'Saved.');
        Changed;
      end;
    end);
end;

procedure TDiffViewer.Save;
begin
  if FSaving then
    Exit;
  FDiscardArmed := False;
  if not (FModel.LeftDirty or FModel.RightDirty) then
  begin
    FNote := T('ui.diffMerge.nothingToSave', 'Nothing to save.');
    Exit;
  end;
  FSaving := True;
  FNote := T('ui.diffMerge.saving', 'Saving...');
  if FModel.LeftDirty and FModel.RightDirty then
    SaveSide(True,
      procedure
      begin
        SaveSide(False, nil);
      end)
  else
    SaveSide(FModel.LeftDirty, nil);
end;

// Closing with unsaved changes asks once: the second close discards them.
procedure TDiffViewer.RequestClose;
begin
  if (FModel.LeftDirty or FModel.RightDirty) and not FDiscardArmed and not FSaving then
  begin
    FDiscardArmed := True;
    FNote := T('ui.diffMerge.unsavedClose',
      'Unsaved changes: Save, or close again to discard them.');
    Exit;
  end;
  Close;
end;

function TDiffViewer.StatusSegments: TArray<string>;
var
  H: Integer;
  Unsaved: string;
begin
  Result := TArray<string>.Create(T('ui.diffMerge.mode', 'Compare'));
  H := FModel.HunkOfRow(FCur);
  if FModel.HunkCount = 0 then
    Result := Result + [T('ui.diffMerge.noneLeft', 'No differences left.')]
  else if H >= 0 then
    Result := Result + [T('ui.diffMerge.position', 'Difference %d of %d',
      [H + 1, FModel.HunkCount])]
  else
    Result := Result + [T('ui.diffMerge.total', '%d difference(s)', [FModel.HunkCount])];
  Unsaved := '';
  if FModel.LeftDirty then
    Unsaved := T('ui.diffMerge.leftChanged', 'left changed');
  if FModel.RightDirty then
  begin
    if Unsaved <> '' then
      Unsaved := Unsaved + ', ';
    Unsaved := Unsaved + T('ui.diffMerge.rightChanged', 'right changed');
  end;
  if Unsaved <> '' then
    Result := Result + [Unsaved];
  if FNote <> '' then
    Result := Result + [FNote];
end;

function TDiffViewer.SetKeyModifiers(AShift: TShiftState): Boolean;
var
  Mods: TShiftState;
begin
  Mods := AShift * [ssShift, ssAlt, ssCtrl];
  Result := FVisible and (Mods <> FMods);
  FMods := Mods;
end;

// One side of a row: line number, then the visible part of the text. The changed
// part (AHlStart, AHlLen in characters of the whole line) is drawn over it.
procedure TDiffViewer.DrawSide(const AGrid: TTerminalGrid; AX, AY, ANumW, ATextW,
  ANo: Integer; const AText: string; AFg, ABg, ANumFg, AHlFg, AHlBg: TAlphaColor;
  AHlStart, AHlLen: Integer);
var
  Vis, NumText: string;
  I, A, B, TextX: Integer;
begin
  FillGridRect(AGrid, AX, AY, AX + ANumW + ATextW, AY, ' ', AFg, ABg);
  if ANo > 0 then
  begin
    NumText := IntToStr(ANo);
    PutGridText(AGrid, AX + ANumW - Length(NumText), AY, NumText, ANumFg, ABg);
    TextX := AX + ANumW + 1;
    Vis := Copy(AText, FHScroll + 1, ATextW);
    for I := 1 to Length(Vis) do
      if Vis[I] < ' ' then
        Vis[I] := ' ';
    PutGridTextClipped(AGrid, TextX, AY, TextX + ATextW - 1, Vis, AFg, ABg);
    if AHlLen > 0 then
    begin
      A := Max(AHlStart - FHScroll, 0);
      B := Min(AHlStart + AHlLen - FHScroll, Length(Vis));
      if B > A then
        PutGridTextClipped(AGrid, TextX + A, AY, TextX + ATextW - 1,
          Copy(Vis, A + 1, B - A), AHlFg, AHlBg, [ccaBold]);
    end;
  end;
end;

procedure TDiffViewer.Paint(const AGrid: TTerminalGrid; AHostW, AHostH: Integer);
var
  C: TEditorThemeColors;
  InL, InR, StatusY, FrameBottom, BodyRows, Total, NumW, SideW, RightW: Integer;
  Items, Letters: TArray<string>;
  Colors: TFunctionBarColors;
  LeftX, MarkX, RightX, Y, Row, ThumbH, ThumbTop, HlStart, LeftLen, RightLen: Integer;
  R: TDiffRow;
  Sel: Boolean;
  Fg, Bg, KindFg, LFg, RFg, HlFg, HlBg: TAlphaColor;
  Text: string;
  MarkAttr: TCharCellAttributes;
begin
  if not FVisible or not Assigned(FModel) then
    Exit;
  // Like the Viewer and Editor: the frame closes above the chrome rows, then the
  // F-key bar and the status line.
  FBodyTop := 2;
  FrameBottom := AHostH - 1 - ChromeBottomRows;
  BodyRows := FrameBottom - FBodyTop;
  FKeyBarY := KeyBarRow(AHostH);
  FHostW := AHostW;
  if (AHostW < cMinWidth) or (AHostH < cMinHeight) or (BodyRows < 3) then
  begin
    FBounds := TRectI.Make(0, 0, -1, -1);
    FKeyBarY := -1;
    Exit;
  end;
  FBounds := TRectI.Make(0, 0, AHostW - 1, FrameBottom);
  FBodyRows := BodyRows;
  EnsureCursorVisible;
  FTheme.ResolveEditorColors(C);
  FTheme.DrawWindowFrame(AGrid, FBounds, T('ui.diffMerge.title', 'Compare and merge'),
    [twFocused]);
  InL := 1;
  InR := AHostW - 2;
  FillGridRect(AGrid, InL, 1, InR, FrameBottom - 1, ' ', C.BodyFg, C.BodyBg);

  Total := Length(FModel.Rows);
  NumW := Max(3, Length(IntToStr(Max(Length(FModel.LeftLines), Length(FModel.RightLines)))));
  SideW := (InR - InL - cMarkerCols) div 2;
  RightW := InR - InL - cMarkerCols - SideW;
  LeftX := InL;
  MarkX := LeftX + SideW;
  RightX := MarkX + cMarkerCols;
  FScrollX := InR;

  // Header: the two file names over their columns.
  FillGridRect(AGrid, InL, 1, InR, 1, ' ', C.FrameFocus, C.BodyBg);
  PutGridTextClipped(AGrid, LeftX + 1, 1, MarkX - 1, FLeftName, C.FrameFocus, C.BodyBg, [ccaBold]);
  PutGridTextClipped(AGrid, RightX + 1, 1, InR - 1, FRightName, C.FrameFocus, C.BodyBg, [ccaBold]);

  for Y := 0 to BodyRows - 1 do
  begin
    Row := FTop + Y;
    if Row >= Total then
    begin
      FillGridRect(AGrid, InL, FBodyTop + Y, InR - 1, FBodyTop + Y, ' ', C.BodyFg, C.BodyBg);
      Continue;
    end;
    R := FModel.Rows[Row];
    Sel := Row = FCur;
    if Sel then
    begin
      Fg := C.SelFg;
      Bg := C.SelBg;
    end
    else
    begin
      Fg := C.BodyFg;
      Bg := C.BodyBg;
    end;
    case R.Kind of
      drChanged: KindFg := cChangedFg;
      drLeftOnly: KindFg := cLeftOnlyFg;
      drRightOnly: KindFg := cRightOnlyFg;
    else
      KindFg := C.FrameIdle;
    end;
    LFg := Fg;
    RFg := Fg;
    if not Sel then
    begin
      if R.Kind = drLeftOnly then
        LFg := cLeftOnlyFg
      else if R.Kind = drRightOnly then
        RFg := cRightOnlyFg;
    end;
    HlStart := 0;
    LeftLen := 0;
    RightLen := 0;
    if R.Kind = drChanged then
      DiffInnerSpan(R.Left, R.Right, HlStart, LeftLen, RightLen);
    // The changed part stands out on the selected row by reversing it.
    if Sel then
    begin
      HlFg := C.SelBg;
      HlBg := C.SelFg;
    end
    else
    begin
      HlFg := cChangedFg;
      HlBg := Bg;
    end;
    DrawSide(AGrid, LeftX, FBodyTop + Y, NumW, SideW - NumW - 1, R.LeftNo, R.Left, LFg, Bg,
      KindFg, HlFg, HlBg, HlStart, LeftLen);
    DrawSide(AGrid, RightX, FBodyTop + Y, NumW, RightW - NumW - 1, R.RightNo, R.Right, RFg, Bg,
      KindFg, HlFg, HlBg, HlStart, RightLen);
    if R.Kind = drEqual then
      Text := ' ' + chBoxV + ' '
    else
      Text := DiffRowMarker(R.Kind);
    if Sel then
      PutGridText(AGrid, MarkX, FBodyTop + Y, Text, C.SelFg, C.SelBg)
    else
    begin
      if R.Kind = drEqual then
        MarkAttr := []
      else
        MarkAttr := [ccaBold];
      PutGridText(AGrid, MarkX, FBodyTop + Y, Text, KindFg, C.BodyBg, MarkAttr);
    end;
  end;

  // Scroll bar: a track with a thumb sized to the visible share of the rows.
  for Y := 0 to BodyRows - 1 do
    PutGridText(AGrid, FScrollX, FBodyTop + Y, chShadeLight, C.ScrollFg, C.BodyBg);
  if Total > BodyRows then
  begin
    ThumbH := Max(1, BodyRows * BodyRows div Total);
    ThumbTop := FTop * (BodyRows - ThumbH) div (Total - BodyRows);
    for Y := ThumbTop to ThumbTop + ThumbH - 1 do
      PutGridText(AGrid, FScrollX, FBodyTop + Y, chBlock, C.ScrollThumb, C.BodyBg);
  end;

  if FKeyBarY >= 0 then
  begin
    FunctionBarGetItems(fbcDiffMerge, FMods, Items, Letters);
    Colors := FunctionBarDefaultColors;
    Colors.Bg := C.BodyBg;
    DrawFunctionBar(AGrid, FKeyBarY, AHostW, Items, Letters, FMods, Colors, FTheme);
  end;
  StatusY := StatusLineRow(AHostH);
  if StatusY >= 0 then
    FTheme.DrawStatusLine(AGrid, TRectI.Make(0, StatusY, AHostW - 1, StatusY),
      StatusSegments, []);
end;

function TDiffViewer.HandleInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  Mods: TShiftState;
begin
  Result := FVisible;
  if not FVisible or not Assigned(FModel) then
    Exit;
  if (AKey = 0) and (AKeyChar = #9) then
    AKey := vkTab;
  Mods := AShift * [ssShift, ssAlt, ssCtrl];
  try
    if Mods = [] then
      case AKey of
        vkEscape, vkF10: RequestClose;
        vkDown: MoveCursor(1);
        vkUp: MoveCursor(-1);
        vkNext: MoveCursor(Max(FBodyRows - 1, 1));
        vkPrior: MoveCursor(-Max(FBodyRows - 1, 1));
        vkHome: SetCursor(0);
        vkEnd: SetCursor(High(FModel.Rows));
        vkRight: CopySelected(True);
        vkLeft: CopySelected(False);
        vkTab, vkF3: GoToHunk(FModel.NextHunkRow(FCur));
        vkF4: GoToHunk(FModel.PrevHunkRow(FCur));
        vkF2: Save;
        vkF5: CopySelected(True);
        vkF6: CopySelected(False);
        vkF8: DoUndo;
      end
    else if Mods = [ssShift] then
    begin
      if AKey = vkTab then
        GoToHunk(FModel.PrevHunkRow(FCur));
    end
    else if Mods = [ssCtrl] then
      case AKey of
        vkDown: GoToHunk(FModel.NextHunkRow(FCur));
        vkUp: GoToHunk(FModel.PrevHunkRow(FCur));
        vkRight: Inc(FHScroll, cHScrollStep);
        vkLeft: FHScroll := Max(FHScroll - cHScrollStep, 0);
        vkHome: FHScroll := 0;
        Ord('Z'): DoUndo;
        Ord('S'): Save;
      end;
  finally
    if FVisible then
    begin
      AKey := 0;
      AKeyChar := #0;
    end;
    Changed;
  end;
end;

function TDiffViewer.HandleMouseDown(AHostCol, AHostRow: Integer;
  AShift: TShiftState): Boolean;
var
  Row, Total: Integer;
  Items, Letters: TArray<string>;
  Hit: TFunctionBarHit;
  Key: Word;
  KeyChar: Char;
  Shift: TShiftState;
begin
  Result := FVisible;
  if not FVisible or not Assigned(FModel) then
    Exit;
  if (FKeyBarY >= 0) and (AHostRow = FKeyBarY) then
  begin
    FunctionBarGetItems(fbcDiffMerge, FMods, Items, Letters);
    Hit := FunctionBarHitTest(AHostCol, FHostW, Items, Letters, FMods, Assigned(FTheme));
    if FunctionBarHitToInput(Hit, FMods, Key, KeyChar, Shift) then
      HandleInput(Key, Shift, KeyChar);
    Exit;
  end;
  if not FBounds.Contains(AHostCol, AHostRow) then
    Exit;
  if (AHostRow = FBounds.Top) and (AHostCol >= FBounds.Right - 4) then
  begin
    RequestClose;
    Changed;
    Exit;
  end;
  if (AHostRow < FBodyTop) or (AHostRow >= FBodyTop + FBodyRows) then
    Exit;
  Total := Length(FModel.Rows);
  if AHostCol = FScrollX then
  begin
    // A click on the scroll bar jumps to that share of the rows.
    FTop := EnsureRange((AHostRow - FBodyTop) * Total div Max(FBodyRows, 1) - FBodyRows div 2,
      0, Max(Total - FBodyRows, 0));
    FCur := EnsureRange(FCur, FTop, Min(FTop + FBodyRows - 1, Total - 1));
  end
  else
  begin
    Row := FTop + AHostRow - FBodyTop;
    if Row < Total then
      SetCursor(Row);
  end;
  Changed;
end;

function TDiffViewer.HandleMouseWheel(ADelta: Integer): Boolean;
var
  Total, Step: Integer;
begin
  Result := FVisible;
  if not FVisible or not Assigned(FModel) then
    Exit;
  Total := Length(FModel.Rows);
  if ADelta > 0 then
    Step := -cWheelRows
  else
    Step := cWheelRows;
  FTop := EnsureRange(FTop + Step, 0, Max(Total - FBodyRows, 0));
  FCur := EnsureRange(FCur, FTop, Min(FTop + FBodyRows - 1, Total - 1));
  Changed;
end;

end.
