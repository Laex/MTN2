unit uDualPanelCompare;

{ Folder compare, file compare and the group list. The window supplies the
  panels, the dialog and the diff viewer; cancelling the stub drops the
  background read. The selection the folder compare leaves is the result. }

interface

uses
  System.SysUtils,
  uDualPanelTypes, uDualPanelUiTypes, uDialogTypes,
  uVfsTypes, uPanelCompare, uFileCompare, uDiffViewer, uNotice, uToast;

type
  IDualPanelCompareHost = interface
    ['{A7C3E1B2-4D58-4F0A-9C21-6B8E4D2F1A90}']
    function CanStartOperation: Boolean;
    function ActiveWorkspace: TDualPanelWorkspaceTab;
    procedure SaveActiveWorkspace(const AWs: TDualPanelWorkspaceTab);
    function CompareDialogVisible: Boolean;
    procedure OpenCompareDialog(AKind: THostDialogKind; const ADecl: TDialogDeclaration);
    procedure CloseCompareDialog;
    procedure ClearCompareDialog;
    function CompareCheckbox(const AId: string): Boolean;
    function CompareListIndex(const AId: string): Integer;
    procedure SetCmdFocused(AValue: Boolean);
    procedure NotifyChanged;
    procedure Invalidate;
    function PanelViewKind(ASide: TPanelSide): TPanelViewKind;
    function RowsForSide(ASide: TPanelSide): TPanelRows;
    procedure ShowInfo(const ATitle, ADetail: string);
    procedure OpenStub(AKind: TStubKind; const ATitle, ADetail: string);
    procedure CloseStub;
    procedure CloseTransientUiBeforeDialog;
    function CompareLife: ILifeFlag;
    function CompareVfs: IVirtualFileSystem;
    function CompareDiffView: TDiffViewer;
    procedure CompareToast(const AText: string; AKind: TToastKind);
    function CompareJobState: TPanelJobState;
    procedure CompareReplayAsk;
  end;

  TDualPanelCompare = class
  private
    FHost: IDualPanelCompareHost;
    FOptions: TPanelCompareOptions;
    FToken: IJobCancelToken;
    FGroup: TArray<TComparePair>;
    FVerdicts: TArray<TCompareResult>;
    FSkipped, FSel: Integer;
    FListOpen, FReturn, FAskActive: Boolean;
    procedure ShowResult(const ATitle, AMessage: string);
    procedure ShowFileDiff(const ALeftName, ARightName, AStatus: string;
      const ASummary: TArray<TCompareSummaryRow>; const ALines: TArray<string>);
    procedure RunFolders;
    procedure ApplyFolderResult(const ADiff: TPanelCompareResult);
    procedure BeginGroup(const ALeftRows, ARightRows: TPanelRows;
      const ALeftTab, ARightTab: TTab);
    procedure ShowGroup(const APairs: TArray<TComparePair>;
      const AVerdicts: TArray<TCompareResult>; ASkipped: Integer);
    procedure OpenPair(const ALeftRow, ARightRow: TPanelRow;
      const ALeftName, ARightName, ATitle: string);
    procedure RunPlain(const ALeftRow, ARightRow: TPanelRow;
      const ALeftName, ARightName, ATitle: string; AToken: IJobCancelToken);
    procedure ReturnToGroup;
  public
    constructor Create(const AHost: IDualPanelCompareHost);
    procedure Cancel;
    function AskActive: Boolean;
    procedure CompareFolders;
    procedure DispatchOptionsCommand(const AControlId: string);
    procedure BeginFiles;
    procedure HandleResultCommand(const AControlId: string);
    function TryOverwriteAsk: Boolean;
    procedure ViewerClosed;
  end;

implementation

uses
  System.Classes, System.Math, System.UITypes,
  uDialogBuilders, uStrings;

const
  cSameFg = TAlphaColor($FF00D000);
  cDiffFg = TAlphaColor($FFFF4040);

constructor TDualPanelCompare.Create(const AHost: IDualPanelCompareHost);
begin
  inherited Create;
  FHost := AHost;
  FOptions := TPanelCompareOptions.Default;
end;

procedure TDualPanelCompare.Cancel;
begin
  if Assigned(FToken) then
  begin
    FToken.Cancel;
    FToken := nil;
  end;
end;

function TDualPanelCompare.AskActive: Boolean;
begin
  Result := FAskActive;
end;

procedure TDualPanelCompare.ShowResult(const ATitle, AMessage: string);
begin
  if FHost.CompareDialogVisible then
    Exit;
  FHost.SetCmdFocused(False);
  FListOpen := False;
  FHost.OpenCompareDialog(hdkCompareResult, BuildConfirmDialog(ATitle, AMessage));
  FHost.NotifyChanged;
end;

procedure TDualPanelCompare.ShowFileDiff(const ALeftName, ARightName, AStatus: string;
  const ASummary: TArray<TCompareSummaryRow>; const ALines: TArray<string>);
var
  Items: TArray<string>;
  Swatches: TArray<TListSwatch>;
  I: Integer;
begin
  if FHost.CompareDialogVisible then
    Exit;
  FHost.SetCmdFocused(False);
  FListOpen := False;
  SetLength(Items, Length(ASummary));
  SetLength(Swatches, Length(ASummary));
  for I := 0 to High(ASummary) do
  begin
    Items[I] := ASummary[I].Text;
    Swatches[I].Col := 0;
    Swatches[I].Text := ASummary[I].Text;
    if ASummary[I].Same then
      Swatches[I].Fg := cSameFg
    else
      Swatches[I].Fg := cDiffFg;
  end;
  FHost.OpenCompareDialog(hdkCompareResult, BuildFileDiffDialog(ALeftName, ARightName,
    AStatus, Items, Swatches, ALines));
  FHost.NotifyChanged;
end;

procedure TDualPanelCompare.CompareFolders;
var
  Ws: TDualPanelWorkspaceTab;
  Title: string;
begin
  if not FHost.CanStartOperation or Assigned(FToken) then
    Exit;
  Ws := FHost.ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  Title := T('ui.compareFolders.title', 'Compare folders');
  if not (Ws.State.LeftVisible and Ws.State.RightVisible) or
     (FHost.PanelViewKind(psLeft) <> pvkFiles) or
     (FHost.PanelViewKind(psRight) <> pvkFiles) then
  begin
    ShowResult(Title, T('ui.compareFolders.needPanels',
      'Both panels must show file lists.'));
    Exit;
  end;
  FHost.CloseTransientUiBeforeDialog;
  FHost.OpenCompareDialog(hdkCompareOptions, BuildCompareOptionsDialog(FOptions.ByTime,
    FOptions.BySize, FOptions.ByContent));
  FHost.NotifyChanged;
end;

procedure TDualPanelCompare.DispatchOptionsCommand(const AControlId: string);
var
  Opt: TPanelCompareOptions;
begin
  Opt.ByTime := FHost.CompareCheckbox('by_time');
  Opt.BySize := FHost.CompareCheckbox('by_size');
  Opt.ByContent := FHost.CompareCheckbox('by_content');
  FHost.CloseCompareDialog;
  if DialogCmdIsAccept(AControlId) then
  begin
    FOptions := Opt;
    RunFolders;
  end;
  FHost.NotifyChanged;
end;

procedure TDualPanelCompare.ApplyFolderResult(const ADiff: TPanelCompareResult);
var
  Ws: TDualPanelWorkspaceTab;
  LeftTab, RightTab: TTab;
begin
  Ws := FHost.ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  LeftTab := ActiveTab(Ws.State.LeftPanel);
  LeftTab.SelectedURIs := ADiff.LeftUris;
  SetActiveTab(Ws.State.LeftPanel, LeftTab);
  RightTab := ActiveTab(Ws.State.RightPanel);
  RightTab.SelectedURIs := ADiff.RightUris;
  SetActiveTab(Ws.State.RightPanel, RightTab);
  FHost.SaveActiveWorkspace(Ws);
  FHost.Invalidate;
  // The marked rows are the whole result. A message is shown only when nothing differs.
  if (Length(ADiff.LeftUris) = 0) and (Length(ADiff.RightUris) = 0) then
    ShowResult(T('ui.compareFolders.title', 'Compare folders'),
      T('ui.compareFolders.same', 'The folders are identical.'));
end;

procedure TDualPanelCompare.RunFolders;
var
  Life: ILifeFlag;
  Token: IJobCancelToken;
  LeftRows, RightRows: TPanelRows;
  Opt: TPanelCompareOptions;
  Title: string;
  Ws: TDualPanelWorkspaceTab;
  Host: IDualPanelCompareHost;
begin
  Ws := FHost.ActiveWorkspace;
  if IsFindUri(ActiveTab(Ws.State.LeftPanel).CurrentURI) or
     IsFindUri(ActiveTab(Ws.State.RightPanel).CurrentURI) then
  begin
    FHost.ShowInfo(T('ui.compareFolders.title', 'Compare folders'),
      T('ui.compareFolders.findPanel',
        'Search results cannot be compared with a folder.'));
    Exit;
  end;
  LeftRows := FHost.RowsForSide(psLeft);
  RightRows := FHost.RowsForSide(psRight);
  Opt := FOptions;
  if not Opt.ByContent then
  begin
    ApplyFolderResult(ComparePanelRows(LeftRows, RightRows, Opt, nil));
    Exit;
  end;
  Life := FHost.CompareLife;
  Token := TJobCancelToken.Create;
  FToken := Token;
  Title := T('ui.compareFolders.title', 'Compare folders');
  Host := FHost;
  FHost.OpenStub(skShellInfo, Title, T('ui.compareFolders.working', 'Comparing... Esc=Cancel'));
  TThread.CreateAnonymousThread(
    procedure
    var
      Diff: TPanelCompareResult;
      Err: string;
    begin
      Err := '';
      try
        Diff := ComparePanelRows(LeftRows, RightRows, Opt,
          function(const ALeft, ARight: TPanelRow): Boolean
          var
            LP, RP: string;
          begin
            if Token.IsCancellationRequested then
              Exit(True);
            LP := FileUriToPath(ALeft.URI);
            RP := FileUriToPath(ARight.URI);
            // Rows of other filesystems (archives, SFTP) are not read.
            if (LP = '') or (RP = '') then
              Exit(True);
            Result := LocalFilesHaveSameContent(LP, RP,
              function: Boolean
              begin
                Result := Token.IsCancellationRequested;
              end);
          end);
      except
        on E: Exception do
          Err := E.Message;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Token.IsCancellationRequested or not Life.Alive then
            Exit;
          FToken := nil;
          Host.CloseStub;
          if Err <> '' then
          begin
            Host.OpenStub(skShellInfo, Title, Err);
            Exit;
          end;
          ApplyFolderResult(Diff);
        end);
    end).Start;
end;

procedure TDualPanelCompare.BeginFiles;
var
  Ws: TDualPanelWorkspaceTab;
  LeftRows, RightRows: TPanelRows;
  LeftTab, RightTab: TTab;
  LeftIdx, RightIdx, LeftMarked, RightMarked: Integer;
  LeftRow, RightRow: TPanelRow;
  LeftName, RightName, Title: string;
  EitherSideNotAPlainFile, SamePanelPair: Boolean;
begin
  if not FHost.CanStartOperation then
    Exit;
  FReturn := False;
  Ws := FHost.ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  Title := T('ui.compareFiles.title', 'Compare files');
  LeftRows := FHost.RowsForSide(psLeft);
  RightRows := FHost.RowsForSide(psRight);
  if (Length(LeftRows) = 0) or (Length(RightRows) = 0) then
    Exit;
  LeftTab := ActiveTab(Ws.State.LeftPanel);
  RightTab := ActiveTab(Ws.State.RightPanel);
  LeftMarked := CountMarkedRows(LeftRows, LeftTab);
  RightMarked := CountMarkedRows(RightRows, RightTab);
  if Ws.State.ActiveSide = psLeft then
    SamePanelPair := (RightMarked = 0) and
      PickMarkedFilePair(LeftRows, LeftTab, LeftRow, RightRow)
  else
    SamePanelPair := (LeftMarked = 0) and
      PickMarkedFilePair(RightRows, RightTab, LeftRow, RightRow);
  if (not SamePanelPair) and (Max(LeftMarked, RightMarked) >= 2) then
  begin
    BeginGroup(LeftRows, RightRows, LeftTab, RightTab);
    Exit;
  end;
  if not SamePanelPair then
  begin
    LeftIdx := EnsureRange(LeftTab.CursorIndex, 0, High(LeftRows));
    RightIdx := EnsureRange(RightTab.CursorIndex, 0, High(RightRows));
    LeftRow := LeftRows[LeftIdx];
    RightRow := RightRows[RightIdx];
    EitherSideNotAPlainFile := LeftRow.IsParent or RightRow.IsParent or
      LeftRow.IsDirectory or RightRow.IsDirectory;
    if EitherSideNotAPlainFile then
    begin
      ShowResult(Title, T('ui.compareFiles.needFiles',
        'Select a file (not a folder) on each panel.'));
      Exit;
    end;
  end;

  if SamePanelPair then
  begin
    LeftName := '1: ' + LeftRow.Text;
    RightName := '2: ' + RightRow.Text;
  end
  else
  begin
    LeftName := 'L: ' + LeftRow.Text;
    RightName := 'R: ' + RightRow.Text;
  end;
  OpenPair(LeftRow, RightRow, LeftName, RightName, Title);
end;

procedure TDualPanelCompare.OpenPair(const ALeftRow, ARightRow: TPanelRow;
  const ALeftName, ARightName, ATitle: string);
var
  Life: ILifeFlag;
  Token: IJobCancelToken;
  LeftRow, RightRow: TPanelRow;
  LeftName, RightName, Title: string;
begin
  Life := FHost.CompareLife;
  LeftRow := ALeftRow;
  RightRow := ARightRow;
  LeftName := ALeftName;
  RightName := ARightName;
  Title := ATitle;
  Token := TJobCancelToken.Create;
  FHost.CloseTransientUiBeforeDialog;
  FHost.CompareDiffView.Open(LeftRow.URI, RightRow.URI, LeftName, RightName,
    FHost.CompareVfs,
    procedure
    begin
      if Life.Alive then
        RunPlain(LeftRow, RightRow, LeftName, RightName, Title, Token);
    end);
end;

procedure TDualPanelCompare.BeginGroup(const ALeftRows, ARightRows: TPanelRows;
  const ALeftTab, ARightTab: TTab);
var
  Life: ILifeFlag;
  Token: IJobCancelToken;
  Pairs: TArray<TComparePair>;
  Verdicts: TArray<TCompareResult>;
  Step: TProc<Integer>;
  Skipped: Integer;
  Title: string;
  Host: IDualPanelCompareHost;
begin
  Title := T('ui.compareFiles.title', 'Compare files');
  Pairs := PairMarkedFilesByName(ALeftRows, ARightRows, ALeftTab, ARightTab, Skipped);
  if Length(Pairs) = 0 then
  begin
    ShowResult(Title, T('ui.compareGroup.none',
      'No files with the same name to compare.'));
    Exit;
  end;
  Life := FHost.CompareLife;
  Token := TJobCancelToken.Create;
  FToken := Token;
  SetLength(Verdicts, Length(Pairs));
  Host := FHost;
  Host.OpenStub(skShellInfo, Title, T('ui.compareGroup.working', 'Comparing... Esc=Cancel'));
  Step := procedure(AIdx: Integer)
    begin
      if Token.IsCancellationRequested or not Life.Alive then
      begin
        Step := nil;
        Exit;
      end;
      if AIdx > High(Pairs) then
      begin
        Step := nil;
        FToken := nil;
        Host.CloseStub;
        FSel := 0;
        ShowGroup(Pairs, Verdicts, Skipped);
        Exit;
      end;
      if (Pairs[AIdx].Left.Size >= 0) and (Pairs[AIdx].Right.Size >= 0) and
         (Pairs[AIdx].Left.Size <> Pairs[AIdx].Right.Size) then
      begin
        Verdicts[AIdx] := crDifferSize;
        Step(AIdx + 1);
        Exit;
      end;
      CompareFilesAsync(Pairs[AIdx].Left.URI, Pairs[AIdx].Right.URI, Host.CompareVfs, Token,
        procedure(AResult: TCompareResult; ADiffOffset: Int64; const AError: TVfsError)
        begin
          Verdicts[AIdx] := AResult;
          Step(AIdx + 1);
        end);
    end;
  Step(0);
end;

procedure TDualPanelCompare.ShowGroup(const APairs: TArray<TComparePair>;
  const AVerdicts: TArray<TCompareResult>; ASkipped: Integer);
var
  Items: TArray<string>;
  Swatches: TArray<TListSwatch>;
  I, NameW, Same, Differ, NotCompared: Integer;
  Verdict: string;
begin
  if FHost.CompareDialogVisible then
    Exit;
  NameW := 0;
  for I := 0 to High(APairs) do
    NameW := Min(Max(NameW, Length(PanelCompareName(APairs[I].Left))), 52);
  SetLength(Items, Length(APairs));
  SetLength(Swatches, Length(APairs));
  Same := 0;
  Differ := 0;
  NotCompared := ASkipped;
  for I := 0 to High(APairs) do
  begin
    case AVerdicts[I] of
      crEqual:
        begin
          Verdict := T('ui.compareFiles.contentEqual', 'identical');
          Swatches[I].Fg := cSameFg;
          Inc(Same);
        end;
      crReadError:
        begin
          Verdict := T('ui.compareGroup.error', 'read error');
          Swatches[I].Fg := cDiffFg;
          Inc(NotCompared);
        end;
    else
      Verdict := T('ui.compareFiles.differs', 'differs');
      Swatches[I].Fg := cDiffFg;
      Inc(Differ);
    end;
    Items[I] := PanelCompareName(APairs[I].Left).PadRight(NameW) + '  ' + Verdict;
    Swatches[I].Col := 0;
    Swatches[I].Text := Items[I];
  end;
  FGroup := APairs;
  FVerdicts := AVerdicts;
  FSkipped := ASkipped;
  FListOpen := True;
  FReturn := False;
  FHost.SetCmdFocused(False);
  FHost.OpenCompareDialog(hdkCompareResult, BuildCompareGroupDialog(
    T('ui.compareGroup.status', '%d identical, %d differ, %d not compared',
      [Same, Differ, NotCompared]), Items, Swatches,
    EnsureRange(FSel, 0, High(APairs))));
  FHost.NotifyChanged;
end;

procedure TDualPanelCompare.HandleResultCommand(const AControlId: string);
var
  Idx: Integer;
  Pair: TComparePair;
begin
  if not FListOpen then
  begin
    FHost.CloseCompareDialog;
    ReturnToGroup;
    Exit;
  end;
  Idx := FHost.CompareListIndex('pairs');
  FHost.CloseCompareDialog;
  FListOpen := False;
  if (Idx >= 0) and (Idx <= High(FGroup)) and
     DialogCmdIsListAccept(AControlId, 'pairs') then
  begin
    Pair := FGroup[Idx];
    FSel := Idx;
    FReturn := True;
    OpenPair(Pair.Left, Pair.Right, 'L: ' + Pair.Left.Text,
      'R: ' + Pair.Right.Text, T('ui.compareFiles.title', 'Compare files'));
  end
  else
  begin
    FGroup := nil;
    FVerdicts := nil;
  end;
end;

procedure TDualPanelCompare.ReturnToGroup;
begin
  if not FReturn then
    Exit;
  FReturn := False;
  ShowGroup(FGroup, FVerdicts, FSkipped);
end;

procedure TDualPanelCompare.ViewerClosed;
begin
  if FAskActive then
  begin
    FAskActive := False;
    FHost.CompareReplayAsk;
    Exit;
  end;
  ReturnToGroup;
end;

function TDualPanelCompare.TryOverwriteAsk: Boolean;
var
  St: TPanelJobState;
  Life: ILifeFlag;
  Token: IJobCancelToken;
  SrcUri, DstUri: string;
begin
  St := FHost.CompareJobState;
  if St.PendingBothDirs or (St.PendingSrcURI = '') or (St.PendingDstURI = '') then
  begin
    FHost.CompareToast(T('ui.job.compareFoldersWarn', 'Only files can be compared.'), tkWarning);
    Exit(False);
  end;
  Life := FHost.CompareLife;
  Token := TJobCancelToken.Create;
  SrcUri := St.PendingSrcURI;
  DstUri := St.PendingDstURI;
  FHost.ClearCompareDialog;
  FAskActive := True;
  FHost.CloseTransientUiBeforeDialog;
  FHost.CompareDiffView.Open(SrcUri, DstUri, T('ui.job.compareNew', 'New'),
    T('ui.job.compareExisting', 'Existing'), FHost.CompareVfs,
    procedure
    begin
      if not Life.Alive then
        Exit;
      CompareFilesAsync(SrcUri, DstUri, FHost.CompareVfs, Token,
        procedure(AResult: TCompareResult; ADiffOffset: Int64; const AError: TVfsError)
        var
          Msg: string;
        begin
          if not Life.Alive then
            Exit;
          case AResult of
            crEqual:
              Msg := T('ui.compareFiles.identical', 'Files are identical.');
            crDifferSize:
              Msg := T('ui.compareFiles.sizeBinary', 'Files differ in size.');
            crDifferAtOffset:
              Msg := T('ui.compareFiles.offsetBinary',
                'Files differ at byte offset %d.', [ADiffOffset]);
          else
            Msg := T('ui.compareFiles.failed', 'Compare failed: %s', [AError.Message]);
          end;
          FHost.CompareToast(Msg, tkInfo);
          FAskActive := False;
          FHost.CompareReplayAsk;
        end);
    end);
  Result := True;
end;

procedure TDualPanelCompare.RunPlain(const ALeftRow, ARightRow: TPanelRow;
  const ALeftName, ARightName, ATitle: string; AToken: IJobCancelToken);
var
  Life: ILifeFlag;
  LeftRow, RightRow: TPanelRow;
  LeftName, RightName, Title: string;
begin
  Life := FHost.CompareLife;
  LeftRow := ALeftRow;
  RightRow := ARightRow;
  LeftName := ALeftName;
  RightName := ARightName;
  Title := ATitle;
  DiffFilesAsync(LeftRow.URI, RightRow.URI, FHost.CompareVfs, AToken,
    procedure(AResult: TCompareResult; ADiffOffset: Int64; const AError: TVfsError;
      const ADiffLines: TArray<string>; AChangedLines: Integer)
    var
      Status: string;
      Extra: TArray<string>;
    begin
      if not Life.Alive then
        Exit;
      if AResult = crReadError then
      begin
        ShowResult(Title, T('ui.compareFiles.failed', 'Compare failed: %s',
          [AError.Message]));
        Exit;
      end;
      Extra := nil;
      case AResult of
        crEqual:
          Status := T('ui.compareFiles.identical', 'Files are identical.');
        crDifferSize:
          Status := T('ui.compareFiles.sizeBinary', 'Files differ in size.');
      else
        Status := T('ui.compareFiles.offsetBinary',
          'Files differ at byte offset %d.', [ADiffOffset]);
      end;
      if (AResult <> crEqual) and (Length(ADiffLines) > 0) and (AChangedLines > 0) then
      begin
        Status := T('ui.compareFiles.linesDiffer', '%d line(s) differ', [AChangedLines]);
        Extra := ADiffLines;
      end;
      ShowFileDiff(LeftName, RightName, Status,
        BuildCompareSummary(LeftRow, RightRow, AResult = crEqual, ADiffOffset), Extra);
    end);
end;

end.
