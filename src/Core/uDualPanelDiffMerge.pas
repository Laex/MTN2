unit uDualPanelDiffMerge;

{ Compare-and-merge window (Ctrl+Alt+C on two text files): the files side by side
  with the differing lines marked, hunk-wise copying in either direction, undo and
  saving of the changed sides. The line model lives in uDiffMerge. A pair that is
  binary, too big, unreadable or identical is handed back through the fallback so
  the plain compare result is shown instead. }

interface

uses
  System.SysUtils, System.Classes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uDiffMerge, uVfsTypes, uTextEncoding;

type
  TDiffMergeKindSetter = reference to procedure(AKind: THostDialogKind);
  TDiffMergeAreaFn = reference to function: Integer;
  TDiffMergeAliveFn = reference to function: Boolean;

  TDiffMergeController = class
  private
    FDialog: TDialogHost;
    FModel: TDiffMerge;
    FLayout: TDiffRowLayout;
    FVfs: IVirtualFileSystem;
    FLeftUri, FRightUri: string;
    FLeftEnc, FRightEnc: TTextFileEncoding;
    FLeftEol, FRightEol: string;
    FLeftFinal, FRightFinal: Boolean;
    FDiscardArmed: Boolean;
    FSaving: Boolean;
    FLoadGen: Integer;
    FLastSel: Integer;
    FNote: string;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TDiffMergeKindSetter;
    FOnPrepare: TProc;
    FOnNotify: TProc;
    FOnAreaCols: TDiffMergeAreaFn;
    FOnAlive: TDiffMergeAliveFn;
    procedure Show(const ALeftName, ARightName: string);
    procedure Refresh(ASelect: Integer; AKeepScroll: Boolean);
    procedure UpdateStatus;
    function SelectedRow: Integer;
    procedure CopySelected(AToRight: Boolean);
    procedure GoToHunk(ARow: Integer);
    procedure DoUndo;
    procedure Save;
    procedure SaveSide(ALeft: Boolean; const ANext: TProc);
    procedure ReleaseModel;
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: TDiffMergeKindSetter; const AOnPrepare, AOnNotify: TProc;
      const AOnAreaCols: TDiffMergeAreaFn; const AOnAlive: TDiffMergeAliveFn);
    destructor Destroy; override;
    /// <summary>Reads both files and opens the window; AOnFallback runs instead when
    /// the pair cannot be merged (binary, too big, unreadable, identical).</summary>
    procedure Open(const ALeftUri, ARightUri, ALeftName, ARightName: string;
      const AVfs: IVirtualFileSystem; const AOnFallback: TProc);
    /// <summary>The selection may have moved: refreshes the status line.</summary>
    procedure NotifyDialogChanged;
    function HandleListInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function DispatchCommand(const AControlId: string): Boolean;
  end;

implementation

uses
  System.Math, System.UITypes, uStrings, uTerminalTypes;

const
  cMaxBytes = 16 * 1024 * 1024;
  cMaxLines = 60000;
  cMinDialogCols = 100;
  cMaxDialogCols = 240;
  cDialogMargin = 3;
  cListCols = 5; // dialog width less the list's margins and scroll bar
  cChangedFg = TAlphaColor($FFFFC030);
  cLeftOnlyFg = TAlphaColor($FFFF6060);
  cRightOnlyFg = TAlphaColor($FF60E060);

constructor TDiffMergeController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: TDiffMergeKindSetter;
  const AOnPrepare, AOnNotify: TProc; const AOnAreaCols: TDiffMergeAreaFn;
  const AOnAlive: TDiffMergeAliveFn);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnPrepare := AOnPrepare;
  FOnNotify := AOnNotify;
  FOnAreaCols := AOnAreaCols;
  FOnAlive := AOnAlive;
  FLastSel := -1;
end;

destructor TDiffMergeController.Destroy;
begin
  ReleaseModel;
  inherited;
end;

procedure TDiffMergeController.ReleaseModel;
begin
  FreeAndNil(FModel);
end;

procedure TDiffMergeController.Open(const ALeftUri, ARightUri, ALeftName,
  ARightName: string; const AVfs: IVirtualFileSystem; const AOnFallback: TProc);
var
  Gen: Integer;
  Token: IJobCancelToken;
  LeftNameCopy, RightNameCopy: string;
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
  LeftNameCopy := ALeftName;
  RightNameCopy := ARightName;
  Inc(FLoadGen);
  Gen := FLoadGen;
  Token := TJobCancelToken.Create;
  AVfs.ReadBytesAsync(ALeftUri, cMaxBytes, Token,
    procedure(const ALeftBytes: TBytes; const ALeftErr: TVfsError)
    begin
      if (Gen <> FLoadGen) or (Assigned(FOnAlive) and not FOnAlive()) then
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
          if (Gen <> FLoadGen) or (Assigned(FOnAlive) and not FOnAlive()) then
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
          Show(LeftNameCopy, RightNameCopy);
        end);
    end);
end;

procedure TDiffMergeController.Show(const ALeftName, ARightName: string);
var
  Cols: Integer;
begin
  Cols := cMinDialogCols;
  if Assigned(FOnAreaCols) then
    Cols := EnsureRange(FOnAreaCols() - 2 * cDialogMargin, cMinDialogCols, cMaxDialogCols);
  FLayout := DiffRowLayout(Cols - cListCols);
  FDiscardArmed := False;
  FSaving := False;
  FNote := '';
  FLastSel := -1;
  if Assigned(FOnPrepare) then
    FOnPrepare();
  if Assigned(FOnSetKind) then
    FOnSetKind(hdkDiffMerge);
  FDialog.Open(BuildDiffMergeDialog(Cols), FOnCommand);
  FDialog.SetLabelText('left_name', 'L: ' + ALeftName);
  FDialog.SetLabelText('right_name', 'R: ' + ARightName);
  FDialog.SetLabelText('columns',
    StringOfChar(' ', FLayout.NumCols + 1) + Copy(T('ui.diffMerge.colLeft', 'Left') +
      StringOfChar(' ', FLayout.CellCols), 1, FLayout.CellCols) +
    StringOfChar(' ', 3 + FLayout.NumCols + 1) + T('ui.diffMerge.colRight', 'Right'));
  FDialog.SetLabelText('hint', T('ui.diffMerge.hint',
    'Right / Left copy the difference to the right / left file, Ctrl+Down / Ctrl+Up move between differences.'));
  Refresh(FModel.Hunks[0].FirstRow, False);
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TDiffMergeController.Refresh(ASelect: Integer; AKeepScroll: Boolean);
var
  Rows: TArray<TDiffRow>;
  Items: TArray<string>;
  Swatches: TArray<TListSwatch>;
  I, ScrollTop: Integer;
begin
  Rows := FModel.Rows;
  SetLength(Items, Length(Rows));
  SetLength(Swatches, Length(Rows));
  for I := 0 to High(Rows) do
  begin
    Items[I] := FormatDiffRow(Rows[I], FLayout);
    Swatches[I] := Default(TListSwatch);
    if Rows[I].Kind <> drEqual then
    begin
      Swatches[I].Col := DiffMarkerCol(FLayout);
      Swatches[I].Text := DiffRowMarker(Rows[I].Kind);
      case Rows[I].Kind of
        drChanged: Swatches[I].Fg := cChangedFg;
        drLeftOnly: Swatches[I].Fg := cLeftOnlyFg;
      else
        Swatches[I].Fg := cRightOnlyFg;
      end;
    end;
  end;
  ScrollTop := FDialog.GetListScrollTop;
  FDialog.BeginUpdate;
  try
    FDialog.SetListItems('rows', Items, EnsureRange(ASelect, 0, Max(High(Items), 0)));
    FDialog.SetListSwatches('rows', Swatches);
    if AKeepScroll then
      FDialog.SetListScrollTop(ScrollTop);
  finally
    FDialog.EndUpdate;
  end;
  FLastSel := -1;
  UpdateStatus;
end;

function TDiffMergeController.SelectedRow: Integer;
begin
  Result := FDialog.GetListSelectedIndex('rows');
end;

procedure TDiffMergeController.UpdateStatus;
var
  Row, H: Integer;
  Text, Unsaved: string;
begin
  if not Assigned(FModel) or not FDialog.Visible then
    Exit;
  Row := SelectedRow;
  FLastSel := Row;
  H := FModel.HunkOfRow(Row);
  if FModel.HunkCount = 0 then
    Text := T('ui.diffMerge.noneLeft', 'No differences left.')
  else if H >= 0 then
    Text := T('ui.diffMerge.position', 'Difference %d of %d', [H + 1, FModel.HunkCount])
  else
    Text := T('ui.diffMerge.total', '%d difference(s)', [FModel.HunkCount]);
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
    Text := Text + '  [' + Unsaved + ']';
  if FNote <> '' then
    Text := Text + '  ' + FNote;
  FDialog.SetLabelText('status', Text + StringOfChar(' ', Max(0, 60 - Length(Text))));
end;

procedure TDiffMergeController.NotifyDialogChanged;
begin
  if not Assigned(FModel) or not FDialog.Visible then
    Exit;
  if SelectedRow <> FLastSel then
  begin
    FNote := '';
    FDiscardArmed := False;
    UpdateStatus;
  end;
end;

procedure TDiffMergeController.GoToHunk(ARow: Integer);
begin
  if ARow < 0 then
    Exit;
  Refresh(ARow, False);
end;

procedure TDiffMergeController.CopySelected(AToRight: Boolean);
var
  Row, H, NewRow: Integer;
begin
  if not Assigned(FModel) or FSaving then
    Exit;
  Row := SelectedRow;
  H := FModel.HunkOfRow(Row);
  FDiscardArmed := False;
  if H < 0 then
  begin
    FNote := T('ui.diffMerge.notOnDifference', 'Select a marked line first.');
    UpdateStatus;
    Exit;
  end;
  FNote := '';
  if not FModel.CopyHunk(H, AToRight) then
    Exit;
  // The copied hunk is gone; its place is taken by the next one.
  if H < FModel.HunkCount then
    NewRow := FModel.Hunks[H].FirstRow
  else if FModel.HunkCount > 0 then
    NewRow := FModel.Hunks[FModel.HunkCount - 1].FirstRow
  else
    NewRow := Min(Row, High(FModel.Rows));
  Refresh(NewRow, False);
end;

procedure TDiffMergeController.DoUndo;
var
  Row: Integer;
begin
  if not Assigned(FModel) or FSaving or not FModel.CanUndo then
    Exit;
  Row := SelectedRow;
  FModel.Undo;
  FDiscardArmed := False;
  FNote := '';
  Refresh(Row, True);
end;

procedure TDiffMergeController.SaveSide(ALeft: Boolean; const ANext: TProc);
var
  Uri, Text: string;
  Enc: TTextFileEncoding;
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
  FVfs.WriteTextAsync(Uri, Text, Enc, TJobCancelToken.Create,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      if (Assigned(FOnAlive) and not FOnAlive()) or not Assigned(FModel) then
        Exit;
      if not ASuccess then
      begin
        FSaving := False;
        FNote := T('ui.diffMerge.saveFailed', 'Save failed: %s', [AError.Message]);
        UpdateStatus;
        if Assigned(FOnNotify) then
          FOnNotify();
        Exit;
      end;
      FModel.MarkSaved(ALeft, not ALeft);
      if Assigned(ANext) then
        ANext()
      else
      begin
        FSaving := False;
        FNote := T('ui.diffMerge.saved', 'Saved.');
        UpdateStatus;
        if Assigned(FOnNotify) then
          FOnNotify();
      end;
    end);
end;

procedure TDiffMergeController.Save;
begin
  if not Assigned(FModel) or FSaving then
    Exit;
  FDiscardArmed := False;
  if not (FModel.LeftDirty or FModel.RightDirty) then
  begin
    FNote := T('ui.diffMerge.nothingToSave', 'Nothing to save.');
    UpdateStatus;
    Exit;
  end;
  FSaving := True;
  FNote := T('ui.diffMerge.saving', 'Saving...');
  UpdateStatus;
  if FModel.LeftDirty and FModel.RightDirty then
    SaveSide(True,
      procedure
      begin
        SaveSide(False, nil);
      end)
  else
    SaveSide(FModel.LeftDirty, nil);
end;

function TDiffMergeController.HandleListInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  Result := False;
  if not Assigned(FModel) or not SameText(FDialog.FocusedControlId, 'rows') then
    Exit;
  if AShift = [] then
  begin
    case AKey of
      vkRight: CopySelected(True);
      vkLeft: CopySelected(False);
    else
      Exit;
    end;
  end
  else if AShift = [ssCtrl] then
  begin
    case AKey of
      vkDown: GoToHunk(FModel.NextHunkRow(SelectedRow));
      vkUp: GoToHunk(FModel.PrevHunkRow(SelectedRow));
      Ord('Z'): DoUndo;
      Ord('S'): Save;
    else
      Exit;
    end;
  end
  else
    Exit;
  AKey := 0;
  AKeyChar := #0;
  Result := True;
end;

function TDiffMergeController.DispatchCommand(const AControlId: string): Boolean;
begin
  Result := True;
  if not Assigned(FModel) then
  begin
    FDialog.Close;
    Exit;
  end;
  if DialogCmdIs(AControlId, 'dm_next') then
    GoToHunk(FModel.NextHunkRow(SelectedRow))
  else if DialogCmdIs(AControlId, 'dm_prev') then
    GoToHunk(FModel.PrevHunkRow(SelectedRow))
  else if DialogCmdIs(AControlId, 'dm_right') then
    CopySelected(True)
  else if DialogCmdIs(AControlId, 'dm_left') then
    CopySelected(False)
  else if DialogCmdIs(AControlId, 'dm_undo') then
    DoUndo
  else if DialogCmdIs(AControlId, 'dm_save') then
    Save
  else
  begin
    // Closing with unsaved changes asks once: the second close discards them.
    if (FModel.LeftDirty or FModel.RightDirty) and not FDiscardArmed and not FSaving then
    begin
      FDiscardArmed := True;
      FNote := T('ui.diffMerge.unsavedClose',
        'Unsaved changes: Save, or close again to discard them.');
      UpdateStatus;
      Exit;
    end;
    FDialog.Close;
    ReleaseModel;
  end;
end;

end.
