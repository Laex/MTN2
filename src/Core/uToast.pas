unit uToast;

{ Transient notice ("toast"): a one-line framed box at the bottom right of
  the Dual Panel window that hides itself after a few seconds. For commands
  whose result is not visible on screen -- copying a path or a name to the
  clipboard. Never modal: it takes no input, the next key goes on as usual,
  and a new notice replaces the current one instead of queueing. }

interface

uses
  System.SysUtils, System.UITypes, FMX.Types,
  uTerminalTypes, uThemeTypes, uNotice;

const
  cToastDurationMs = 2500;
  cToastWarningDurationMs = 3500;

type
  // TToastKind (tkInfo / tkWarning) lives in uNotice, the host-free entry
  // point other units use to raise a toast.
  TToast = class
  private
    FTimer: TTimer;
    FVisible: Boolean;
    FKind: TToastKind;
    FTemplate: string;
    FArg: string;
    FOnChanged: TProc;
    procedure TimerTick(Sender: TObject);
    procedure Changed;
  public
    /// <summary>AOnChanged: repaint request (show / hide).</summary>
    constructor Create(const AOnChanged: TProc);
    destructor Destroy; override;
    /// <summary>ATemplate may hold one %s: AArg goes there, shortened in the
    /// middle at paint time so the box fits the window. No-op while
    /// GShowToasts is off.</summary>
    procedure Show(const ATemplate: string; const AArg: string = '';
      AKind: TToastKind = tkInfo);
    procedure Hide;
    procedure Draw(const AGrid: TTerminalGrid; const ATheme: IThemeRenderer;
      AWidth, AHeight: Integer);
    property Visible: Boolean read FVisible;
    property Kind: TToastKind read FKind;
  end;

var
  /// <summary>Display dialog "Show notifications"; persisted in session.json
  /// (showNotifications).</summary>
  GShowToasts: Boolean = True;

/// <summary>ATemplate with AArg in its %s, at most AMaxLen chars: AArg is
/// shortened in the middle first (paths keep drive and tail), the whole text
/// is cut only if the template alone is too long. A template without %s (or a
/// bad translation) gets AArg appended.</summary>
function ToastFitText(const ATemplate, AArg: string; AMaxLen: Integer): string;
/// <summary>Box for a text of ATextLen chars in an AWidth x AHeight window:
/// right-aligned, bottom frame row two rows above the command line so the
/// shadow lands on the panel frame. Empty (Width 0) when the window is too
/// small.</summary>
function ToastBounds(ATextLen, AWidth, AHeight: Integer): TRectI;
/// <summary>Longest text a toast can show in a window AWidth wide.</summary>
function ToastMaxTextLen(AWidth: Integer): Integer;

implementation

uses
  uDualPanelOverlays, uPanelUriLabels, uThemeDrawing;

const
  cToastFg = TAlphaColor($FF000000);
  cToastBg = TAlphaColor($FFFFFFFF);
  // Box = frame + one space of padding on each side of the text.
  cToastChrome = 4;
  cToastRightMargin = 2;
  cToastMinWidth = 16;
  cToastMinHeight = 10;

function CutText(const S: string; AMaxLen: Integer): string;
begin
  if AMaxLen < 1 then
    Exit('');
  if Length(S) <= AMaxLen then
    Exit(S);
  if AMaxLen <= 3 then
    Exit(Copy(S, 1, AMaxLen));
  Result := Copy(S, 1, AMaxLen - 3) + '...';
end;

function ToastFitText(const ATemplate, AArg: string; AMaxLen: Integer): string;
var
  Fixed: string;
  Avail: Integer;
begin
  if AMaxLen < 1 then
    Exit('');
  if AArg = '' then
    Exit(CutText(ATemplate, AMaxLen));
  try
    Fixed := Format(ATemplate, ['']);
  except
    on EConvertError do
      Exit(CutText(ATemplate + ' ' + AArg, AMaxLen));
  end;
  if Fixed = ATemplate then
    Exit(CutText(ATemplate + ' ' + AArg, AMaxLen));
  Avail := AMaxLen - Length(Fixed);
  if Avail < 4 then
    Exit(CutText(Fixed, AMaxLen));
  Result := CutText(Format(ATemplate, [FitFolderHistoryLabel(AArg, Avail)]),
    AMaxLen);
end;

function ToastMaxTextLen(AWidth: Integer): Integer;
begin
  Result := AWidth - cToastChrome - cToastRightMargin - 2;
end;

function ToastBounds(ATextLen, AWidth, AHeight: Integer): TRectI;
var
  BoxW, Right, Bottom: Integer;
begin
  Result := TRectI.Make(0, 0, -1, -1);
  if (AWidth < cToastMinWidth) or (AHeight < cToastMinHeight) or (ATextLen < 1) then
    Exit;
  BoxW := ATextLen + cToastChrome;
  Right := AWidth - 1 - cToastRightMargin;
  // H-1 status, H-2 F-keys, H-3 command line, H-4 panel bottom frame (shadow).
  Bottom := AHeight - 5;
  Result := TRectI.Make(Right - BoxW + 1, Bottom - 2, Right, Bottom);
end;

{ TToast }

constructor TToast.Create(const AOnChanged: TProc);
begin
  inherited Create;
  FOnChanged := AOnChanged;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cToastDurationMs;
  FTimer.OnTimer := TimerTick;
end;

destructor TToast.Destroy;
begin
  FreeAndNil(FTimer);
  inherited Destroy;
end;

procedure TToast.Changed;
begin
  if Assigned(FOnChanged) then
    FOnChanged();
end;

procedure TToast.Show(const ATemplate, AArg: string; AKind: TToastKind);
begin
  if not GShowToasts or (ATemplate = '') then
    Exit;
  FTemplate := ATemplate;
  FArg := AArg;
  FKind := AKind;
  FVisible := True;
  // Restart the countdown: a repeated command keeps the box up.
  FTimer.Enabled := False;
  if AKind = tkWarning then
    FTimer.Interval := cToastWarningDurationMs
  else
    FTimer.Interval := cToastDurationMs;
  FTimer.Enabled := True;
  Changed;
end;

procedure TToast.Hide;
begin
  FTimer.Enabled := False;
  if not FVisible then
    Exit;
  FVisible := False;
  Changed;
end;

procedure TToast.TimerTick(Sender: TObject);
begin
  Hide;
end;

procedure TToast.Draw(const AGrid: TTerminalGrid; const ATheme: IThemeRenderer;
  AWidth, AHeight: Integer);
var
  Text: string;
  R: TRectI;
  Fg, Bg: TAlphaColor;
begin
  if not FVisible then
    Exit;
  Text := ToastFitText(FTemplate, FArg, ToastMaxTextLen(AWidth));
  R := ToastBounds(Length(Text), AWidth, AHeight);
  if R.Width < cToastChrome + 1 then
    Exit;
  // Plain double frame in the dialog colours: the theme's dialog frame adds
  // a close box, and a toast takes no clicks.
  ResolveOverlayTextColors(ATheme, False, False, False, cToastFg, cToastBg,
    Fg, Bg);
  DrawPanelFrameGlyphs(AGrid, R, chDblTL, chDblTR, chDblBL, chDblBR, chDblH,
    chDblV, Fg, Fg, Bg);
  DrawDialogShadow(AGrid, R);
  PutOverlayText(AGrid, ATheme, R.Left + 1, R.Top + 1, ' ' + Text + ' ',
    False, FKind = tkWarning, False, cToastFg, cToastBg);
end;

end.
