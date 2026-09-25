unit uJobPopupRenderer;

{ Stateless rendering of the Copy/Move/Delete job popup (TPanelJobState is a
  snapshot passed in — this unit never mutates job state or drives the job
  state machine; see uDualPanelJobs.TPanelJobController for that). }

interface

uses
  System.SysUtils, System.Math, System.UITypes,
  uTerminalTypes, uThemeTypes, uDualPanelUiTypes, uDualPanelOverlays, uVfsTypes;

type
  TJobPopupRenderer = class
  public
    class function ComputeLayout(const AJob: TPanelJobState;
      AClientWidth, AClientHeight: Integer): TRectI; static;
    class procedure Draw(const AGrid: TTerminalGrid; const ATheme: IThemeRenderer;
      const AJob: TPanelJobState; const ATitle: string); static;
  end;

function JobPopupBackgroundButtonBounds(const ABounds: TRectI;
  AKind: TPanelJobKind): TRectI;
function JobPopupBackgroundHit(const ABounds: TRectI; AKind: TPanelJobKind;
  AX, AY: Integer): Boolean;

implementation

const
  cJobPopupBackgroundCaption = 'Background';
  cJobPopupBackgroundWidth = 15; // '[ Background ]'
  cCursorFg = TAlphaColor($FF000000);
  cFileFg   = TAlphaColor($FFAAAAAA);
  cPanelBg  = TAlphaColor($FF0000AA);
  cFrameActive = TAlphaColor($FF55FFFF);
  cMenuHot  = TAlphaColor($FFFFFF55);
  cSelectedFg = TAlphaColor($FFFFFF55);
  cScrollThumb = TAlphaColor($FF00AAAA);

function FormatGroupedInt64(AValue: Int64): string;
var
  S: string;
  I, Digits: Integer;
begin
  if AValue < 0 then
    AValue := 0;
  S := IntToStr(AValue);
  Result := '';
  Digits := 0;
  for I := Length(S) downto 1 do
  begin
    Inc(Digits);
    Result := S[I] + Result;
    if (Digits mod 3 = 0) and (I > 1) then
      Result := ' ' + Result;
  end;
end;

function EllipsizeLeft(const AText: string; AMaxLen: Integer): string;
begin
  if AMaxLen < 1 then
    Exit('');
  if Length(AText) <= AMaxLen then
    Exit(AText);
  if AMaxLen <= 2 then
    Exit(Copy(AText, 1, AMaxLen));
  Result := '..' + Copy(AText, Length(AText) - (AMaxLen - 2) + 1, AMaxLen - 2);
end;

function JobPopupActionRowY(const ABounds: TRectI; AKind: TPanelJobKind): Integer;
begin
  if AKind in [pjkCopy, pjkMove, pjkPack, pjkUnpack] then
    Result := ABounds.Top + 11
  else
    Result := ABounds.Top + 5;
end;

function JobPopupBackgroundButtonBounds(const ABounds: TRectI;
  AKind: TPanelJobKind): TRectI;
var
  Y: Integer;
begin
  Y := JobPopupActionRowY(ABounds, AKind);
  Result := TRectI.Make(ABounds.Left + 2, Y,
    ABounds.Left + 1 + cJobPopupBackgroundWidth, Y);
end;

function JobPopupBackgroundHit(const ABounds: TRectI; AKind: TPanelJobKind;
  AX, AY: Integer): Boolean;
begin
  Result := JobPopupBackgroundButtonBounds(ABounds, AKind).Contains(AX, AY);
end;

procedure DrawJobBackgroundButton(const AGrid: TTerminalGrid;
  const ATheme: IThemeRenderer; const ABounds: TRectI; AKind: TPanelJobKind;
  ABodyFg, ABodyBg: TAlphaColor);
var
  B: TRectI;
  HintX: Integer;
begin
  B := JobPopupBackgroundButtonBounds(ABounds, AKind);
  if Assigned(ATheme) then
    ATheme.DrawButton(AGrid, B, cJobPopupBackgroundCaption, [])
  else
    PutGridText(AGrid, B.Left, B.Top, '[ Background ]', ABodyFg, ABodyBg);
  HintX := B.Right + 2;
  if HintX + Length('Esc=Cancel') - 1 <= ABounds.Right - 2 then
    PutOverlayText(AGrid, ATheme, HintX, B.Top, 'Esc=Cancel',
      True, False, False, cMenuHot, cPanelBg);
end;

procedure ResolveJobPopupColors(const ATheme: IThemeRenderer;
  out ABodyFg, ABodyBg, ABarFg, ARuleFg: TAlphaColor);
var
  Ed: TEditorThemeColors;
  Discard: TAlphaColor;
begin
  ResolveOverlayTextColors(ATheme, False, False, False, cFileFg, cPanelBg,
    ABodyFg, ABodyBg);
  ABarFg := cScrollThumb;
  ARuleFg := cFrameActive;
  if not Assigned(ATheme) then
    Exit;
  ATheme.ResolveEditorColors(Ed);
  ABarFg := Ed.ScrollThumb;
  ATheme.ResolvePanelChromeColors(pcpFrameActive, True, ARuleFg, Discard);
end;

procedure DrawJobSectionRule(const AGrid: TTerminalGrid; const ABounds: TRectI;
  AY: Integer; const ATitle: string; AFg, ABg: TAlphaColor);
var
  X, Mid, CapW: Integer;
  Cap: string;
  FrameV, LeftTee, RightTee, HBar: Char;
begin
  if (AY < ABounds.Top) or (AY > ABounds.Bottom) then
    Exit;
  // Join the already-drawn dialog verticals: double-line frames (NDN, TC,
  // High Contrast) get ╟─╢ mixed tees; single-line themes get ├─┤; ASCII `|`
  // gets `+` / `-`. Reading the cell avoids a second "is this NDN?" flag.
  FrameV := ' ';
  if (AY >= 0) and (AY <= High(AGrid)) and
     (ABounds.Left >= 0) and (ABounds.Left <= High(AGrid[AY])) then
    FrameV := AGrid[AY][ABounds.Left].CharValue;
  if FrameV = chDblV then
  begin
    LeftTee := chDblVSingleHR;
    RightTee := chDblVSingleHL;
    HBar := chBoxH;
  end
  else if FrameV = '|' then
  begin
    LeftTee := '+';
    RightTee := '+';
    HBar := '-';
  end
  else
  begin
    LeftTee := chBoxVR;
    RightTee := chBoxVL;
    HBar := chBoxH;
  end;
  DrawGridChar(AGrid, ABounds.Left, AY, LeftTee, AFg, ABg);
  DrawGridChar(AGrid, ABounds.Right, AY, RightTee, AFg, ABg);
  for X := ABounds.Left + 1 to ABounds.Right - 1 do
    DrawGridChar(AGrid, X, AY, HBar, AFg, ABg);
  Cap := ' ' + ATitle + ' ';
  CapW := Length(Cap);
  Mid := ABounds.Left + Max((ABounds.Width - CapW) div 2, 1);
  if Mid + CapW - 1 >= ABounds.Right then
    Mid := ABounds.Left + 1;
  PutGridText(AGrid, Mid, AY, Copy(Cap, 1, ABounds.Right - Mid), AFg, ABg);
end;

procedure DrawJobProgressBar(const AGrid: TTerminalGrid; AX, AY, AWidth,
  APct: Integer; ABarFg, ATrackFg, ABg: TAlphaColor);
var
  Pct: Integer;
  PctStr, Bar: string;
  BarW, FillW: Integer;
begin
  Pct := EnsureRange(APct, 0, 100);
  PctStr := Format('%3d%%', [Pct]);
  BarW := Max(AWidth - Length(PctStr) - 1, 4);
  FillW := EnsureRange(Round(BarW * Pct / 100), 0, BarW);
  Bar := StringOfChar(chBlock, FillW) + StringOfChar(chShadeLight, BarW - FillW);
  PutGridText(AGrid, AX, AY, Copy(Bar, 1, BarW), ABarFg, ABg);
  PutGridText(AGrid, AX + BarW + 1, AY, PctStr, ATrackFg, ABg);
end;

class function TJobPopupRenderer.ComputeLayout(const AJob: TPanelJobState;
  AClientWidth, AClientHeight: Integer): TRectI;
var
  W, H, PanelW, Left, Top: Integer;
  Rich, DeleteRunning: Boolean;
begin
  PanelW := AClientWidth;
  Rich := (AJob.Phase = pjpRunning) and
    (AJob.Kind in [pjkCopy, pjkMove, pjkPack, pjkUnpack]);
  DeleteRunning := (AJob.Phase = pjpRunning) and (AJob.Kind = pjkDelete);
  // +2 on both W and H over the content's own footprint: one border cell
  // plus one full blank cell of padding on every side between the frame and
  // the content drawn in Draw.
  if Rich then
  begin
    W := Min(72, Max(PanelW - 2, 48)) + 2;
    H := 13;
  end
  else if DeleteRunning then
  begin
    // As wide as the copy/move popup: the live delete progress line now
    // shows the full current path (see Draw below), which needs the room
    // just as much as Copy/Move's source/destination lines do. Other
    // "plain" phases (Confirm, Error, the Ask popups' hit-test bounds)
    // keep the narrower width — they don't show a path.
    W := Min(72, Max(PanelW - 2, 48)) + 2;
    H := 9;
  end
  else
  begin
    W := Min(44, Max(PanelW - 2, 24)) + 2;
    H := 9;
  end;
  Left := (PanelW - W) div 2;
  Top := Max(AClientHeight div 2 - H div 2, 2);
  if Left + W > PanelW then
    Left := Max(PanelW - W, 0);
  if Top + H > AClientHeight then
    Top := Max(AClientHeight - H, 1);
  Result := TRectI.Make(Left, Top, Left + W - 1, Top + H - 1);
end;

class procedure TJobPopupRenderer.Draw(const AGrid: TTerminalGrid;
  const ATheme: IThemeRenderer; const AJob: TPanelJobState; const ATitle: string);
var
  R: TRectI;
  Pct, FilePct, TotalPct, InnerW, FilesDone: Integer;
  Line, Verb, LabelL, LabelR: string;
  BodyFg, BodyBg, BarFg, RuleFg: TAlphaColor;
  BytesNow, BytesTot: Int64;
  FilesTotal: Integer;
begin
  if AJob.Phase = pjpNone then
    Exit;
  if AJob.Phase in [pjpConfirm, pjpOverwriteAsk, pjpDeleteAsk, pjpIOErrorAsk] then
    Exit;
  R := AJob.Bounds;
  if (R.Width < 10) or (R.Height < 5) then
    Exit;

  DrawHostOverlayFrame(AGrid, ATheme, R, ATitle,
    cFileFg, cPanelBg, cFrameActive, cCursorFg);
  ResolveJobPopupColors(ATheme, BodyFg, BodyBg, BarFg, RuleFg);

  case AJob.Phase of
    pjpRunning:
      if AJob.Kind in [pjkCopy, pjkMove, pjkPack, pjkUnpack] then
      begin
        // -4: one border cell plus one blank padding cell on each side.
        InnerW := Max(R.Width - 4, 8);
        case AJob.Kind of
          pjkMove: Verb := 'Moving the file';
          pjkPack: Verb := 'Packing';
          pjkUnpack: Verb := 'Unpacking';
        else
          Verb := 'Copying the file';
        end;
        PutOverlayText(AGrid, ATheme, R.Left + 2, R.Top + 2, Verb,
          False, False, False, cFileFg, cPanelBg);

        Line := AJob.CurrentSrcPath;
        if Line = '' then
          Line := AJob.CurrentName;
        PutOverlayText(AGrid, ATheme, R.Left + 2, R.Top + 3,
          EllipsizeLeft(Line, InnerW), False, False, False, cFileFg, cPanelBg);

        PutOverlayText(AGrid, ATheme, R.Left + 2, R.Top + 4, 'to',
          False, False, False, cFileFg, cPanelBg);

        Line := AJob.CurrentDstPath;
        if Line = '' then
        begin
          Line := FileUriToPath(AJob.DestDirURI);
          if Line = '' then
            Line := VfsUriTitle(AJob.DestDirURI);
        end;
        PutOverlayText(AGrid, ATheme, R.Left + 2, R.Top + 5,
          EllipsizeLeft(Line, InnerW), False, False, False, cFileFg, cPanelBg);

        if AJob.FileProgressTotal > 0 then
          FilePct := EnsureRange(Round(100 * AJob.FileProgressDone / AJob.FileProgressTotal), 0, 100)
        else
          FilePct := 0;
        DrawJobProgressBar(AGrid, R.Left + 2, R.Top + 6, InnerW, FilePct,
          BarFg, BodyFg, BodyBg);

        DrawJobSectionRule(AGrid, R, R.Top + 7, 'Total', RuleFg, BodyBg);

        FilesTotal := AJob.FilesTotal;
        if FilesTotal < 1 then
          FilesTotal := Length(AJob.Sources);
        FilesDone := EnsureRange(AJob.FilesDone, 0, FilesTotal);
        LabelL := 'Files:';
        LabelR := Format('%s / %s',
          [FormatGroupedInt64(FilesDone), FormatGroupedInt64(FilesTotal)]);
        Line := LabelL + StringOfChar(' ',
          Max(InnerW - Length(LabelL) - Length(LabelR), 1)) + LabelR;
        PutOverlayText(AGrid, ATheme, R.Left + 2, R.Top + 8,
          Copy(Line, 1, InnerW), False, False, False, cFileFg, cPanelBg);

        BytesNow := AJob.BytesDoneBase + AJob.ProgressDone;
        BytesTot := AJob.BytesTotal;
        if BytesTot < BytesNow then
          BytesTot := BytesNow;
        LabelL := 'Bytes:';
        LabelR := Format('%s / %s',
          [FormatGroupedInt64(BytesNow), FormatGroupedInt64(BytesTot)]);
        Line := LabelL + StringOfChar(' ',
          Max(InnerW - Length(LabelL) - Length(LabelR), 1)) + LabelR;
        PutOverlayText(AGrid, ATheme, R.Left + 2, R.Top + 9,
          Copy(Line, 1, InnerW), False, False, False, cFileFg, cPanelBg);

        if BytesTot > 0 then
          TotalPct := EnsureRange(Round(100 * BytesNow / BytesTot), 0, 100)
        else if FilesTotal > 0 then
          TotalPct := EnsureRange(Round(100 * FilesDone / FilesTotal), 0, 100)
        else
          TotalPct := FilePct;
        DrawJobProgressBar(AGrid, R.Left + 2, R.Top + 10, InnerW, TotalPct,
          BarFg, BodyFg, BodyBg);
        DrawJobBackgroundButton(AGrid, ATheme, R, AJob.Kind, BodyFg, BodyBg);
      end
      else
      begin
        InnerW := Max(R.Width - 4, 8);
        Line := AJob.CurrentSrcPath;
        if Line = '' then
          Line := AJob.CurrentName;
        if Line = '' then
          Line := Format('Item %d/%d', [AJob.Index + 1, Length(AJob.Sources)]);
        PutOverlayText(AGrid, ATheme, R.Left + 2, R.Top + 2,
          EllipsizeLeft(Line, InnerW), False, False, False, cFileFg, cPanelBg);
        if AJob.ProgressTotal > 0 then
          Pct := EnsureRange(Round(100 * AJob.ProgressDone / AJob.ProgressTotal), 0, 100)
        else if AJob.FilesTotal > 0 then
          Pct := EnsureRange(Round(100 * (AJob.Index + 1) / AJob.FilesTotal), 0, 100)
        else
          Pct := 0;
        DrawJobProgressBar(AGrid, R.Left + 2, R.Top + 4, InnerW, Pct,
          BarFg, BodyFg, BodyBg);
        DrawJobBackgroundButton(AGrid, ATheme, R, AJob.Kind, BodyFg, BodyBg);
      end;
    pjpError:
      begin
        InnerW := Max(R.Width - 4, 8);
        Line := AJob.Message;
        if Line = '' then
          Line := 'Error';
        if Length(Line) > InnerW then
          Line := Copy(Line, 1, InnerW);
        PutOverlayText(AGrid, ATheme, R.Left + 2, R.Top + 3, Line,
          False, True, False, cSelectedFg, cPanelBg);
        PutOverlayText(AGrid, ATheme, R.Left + 2, R.Top + 5, 'Enter/Esc=Close',
          True, False, False, cMenuHot, cPanelBg);
      end;
  end;
end;

end.
