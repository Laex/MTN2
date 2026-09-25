unit uTerminalWindow;

{ A single MDI window. It renders its chrome (frame/title via IThemeRenderer)
  plus its own content into a private buffer (FBuffer), then blits that buffer
  into the compositor grid. The buffer is rebuilt only when geometry, title,
  focus or content change (FNeedRebuild). }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  uTerminalTypes, uThemeTypes;

type
  TTerminalWindow = class
  private
    FId: Cardinal;
    FTitle: string;
    FArea: TRectI;
    FZIndex: Integer;
    FIsFocused: Boolean;
    FVisible: Boolean;
    FState: TWindowState;
    FTheme: IThemeRenderer;
    FLayoutBottomMargin: Integer;
    FKeyModifiers: TShiftState;
    procedure SetArea(const AValue: TRectI);
    procedure SetTitle(const AValue: string);
    procedure SetFocused(AValue: Boolean);
  protected
    FBuffer: TTerminalGrid;
    FBodyFg: TAlphaColor;
    FBodyBg: TAlphaColor;
    FNeedRebuild: Boolean;
    function WidgetState: TThemeWidgetState;
    // Draws the window body content into the local buffer (0-based). Override
    // in descendants (Dual Panel, Viewer, ...). Base draws a placeholder.
    procedure DrawContent; virtual;
    property Theme: IThemeRenderer read FTheme;
    property Buffer: TTerminalGrid read FBuffer;
    property BodyFg: TAlphaColor read FBodyFg;
    property BodyBg: TAlphaColor read FBodyBg;
    procedure ClearBodyBuffer;
  public
    constructor Create(const ATheme: IThemeRenderer; AId: Cardinal);
    procedure RebuildBuffer; virtual;
    procedure Resize(AWidth, AHeight: Integer); virtual;
    procedure Paint(const ACompositor: TTerminalGrid); virtual;
    procedure Invalidate;
    function HitTest(ACol, ARow: Integer): Boolean;
    // Returns True if the key was consumed. Shift is FMX TShiftState.
    function HandleInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean; virtual;
    // Updates held Alt/Ctrl/Shift for the F-key bar; True if chrome should redraw.
    function SetKeyModifiers(AShift: TShiftState): Boolean; virtual;
    property Id: Cardinal read FId;
    property Title: string read FTitle write SetTitle;
    property Area: TRectI read FArea write SetArea;
    property ZIndex: Integer read FZIndex write FZIndex;
    property IsFocused: Boolean read FIsFocused write SetFocused;
    property State: TWindowState read FState write FState;
    property Visible: Boolean read FVisible write FVisible;
    property KeyModifiers: TShiftState read FKeyModifiers;
    // Rows reserved below this window by LayoutMaximized (e.g. Console leaves
    // the shared Dual Panel cmdline / F-keys / status visible).
    property LayoutBottomMargin: Integer read FLayoutBottomMargin write FLayoutBottomMargin;
  end;

implementation

constructor TTerminalWindow.Create(const ATheme: IThemeRenderer; AId: Cardinal);
begin
  inherited Create;
  FTheme := ATheme;
  FId := AId;
  FVisible := True;
  FIsFocused := True;
  FState := wsNormal;
  FBodyFg := TAlphaColor($FFE0E0E0);
  FBodyBg := TAlphaColor($FF0000A8);
  FArea := TRectI.Make(0, 0, 0, 0);
  FKeyModifiers := [];
  FNeedRebuild := True;
end;

function TTerminalWindow.SetKeyModifiers(AShift: TShiftState): Boolean;
var
  Next: TShiftState;
begin
  Next := AShift * [ssShift, ssAlt, ssCtrl];
  Result := Next <> FKeyModifiers;
  if Result then
  begin
    FKeyModifiers := Next;
    Invalidate;
  end;
end;

function TTerminalWindow.WidgetState: TThemeWidgetState;
begin
  Result := [];
  if FIsFocused then
    Include(Result, twFocused);
end;

procedure TTerminalWindow.SetArea(const AValue: TRectI);
begin
  if (AValue.Left = FArea.Left) and (AValue.Top = FArea.Top) and
     (AValue.Right = FArea.Right) and (AValue.Bottom = FArea.Bottom) then
    Exit;
  FArea := AValue;
  Resize(FArea.Width, FArea.Height);
end;

procedure TTerminalWindow.SetTitle(const AValue: string);
begin
  if FTitle = AValue then
    Exit;
  FTitle := AValue;
  FNeedRebuild := True;
end;

procedure TTerminalWindow.SetFocused(AValue: Boolean);
begin
  if FIsFocused = AValue then
    Exit;
  FIsFocused := AValue;
  FNeedRebuild := True;
end;

procedure TTerminalWindow.Resize(AWidth, AHeight: Integer);
begin
  if AWidth < 1 then
    AWidth := 1;
  if AHeight < 1 then
    AHeight := 1;
  AllocTerminalGrid(FBuffer, AWidth, AHeight);
  FNeedRebuild := True;
end;

procedure TTerminalWindow.Invalidate;
begin
  FNeedRebuild := True;
end;

procedure TTerminalWindow.ClearBodyBuffer;
begin
  ClearTerminalGrid(FBuffer, FBodyFg, FBodyBg);
end;

procedure TTerminalWindow.DrawContent;
var
  FocusHint: string;
begin
  // Placeholder content; descendants (Dual Panel, Viewer, ...) override this.
  if Length(FBuffer) <= 2 then
    Exit;
  if FIsFocused then
    FocusHint := 'FOCUSED'
  else
    FocusHint := 'inactive';
  PutGridText(FBuffer, 2, 2,
    Format('Window #%d  [%s]  z=%d', [FId, FocusHint, FZIndex]), FBodyFg, FBodyBg);
  PutGridText(FBuffer, 2, 4, 'Click: activate (bring to front)', FBodyFg, FBodyBg);
  PutGridText(FBuffer, 2, 5, 'Tab / Shift+Tab: next / previous window', FBodyFg, FBodyBg);
  PutGridText(FBuffer, 2, 6, 'Esc: close focused   Enter: restore all', FBodyFg, FBodyBg);
end;

procedure TTerminalWindow.RebuildBuffer;
var
  Local: TRectI;
begin
  if (FArea.Width < 2) or (FArea.Height < 2) then
  begin
    FNeedRebuild := False;
    Exit;
  end;
  // Local (0-based) bounds of the private buffer.
  Local := TRectI.Make(0, 0, FArea.Width - 1, FArea.Height - 1);
  ClearTerminalGrid(FBuffer, FBodyFg, FBodyBg);
  if Assigned(FTheme) then
    FTheme.DrawWindowFrame(FBuffer, Local, FTitle, WidgetState);
  DrawContent;
  FNeedRebuild := False;
end;

procedure TTerminalWindow.Paint(const ACompositor: TTerminalGrid);
var
  Y, DstY, SrcX, DstX, CopyCount: Integer;
  MaxDstX, BufferWidth: Integer;
begin
  if not FVisible then
    Exit;
  if FNeedRebuild then
    RebuildBuffer;
  for Y := 0 to High(FBuffer) do
  begin
    DstY := FArea.Top + Y;
    if (DstY < 0) or (DstY > High(ACompositor)) then
      Continue;
    BufferWidth := Length(FBuffer[Y]);
    if BufferWidth = 0 then
      Continue;
    MaxDstX := Length(ACompositor[DstY]);
    SrcX := 0;
    DstX := FArea.Left;
    if DstX < 0 then
    begin
      SrcX := -DstX;
      DstX := 0;
    end;
    CopyCount := Min(BufferWidth - SrcX, MaxDstX - DstX);
    if CopyCount > 0 then
      Move(FBuffer[Y][SrcX], ACompositor[DstY][DstX], CopyCount * SizeOf(TCharCell));
  end;
end;

function TTerminalWindow.HitTest(ACol, ARow: Integer): Boolean;
begin
  Result := FVisible and FArea.Contains(ACol, ARow);
end;

function TTerminalWindow.HandleInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  Result := False;
end;

end.
