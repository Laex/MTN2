unit uMdiCompositor;

{ MDI compositor: owns a list of TTerminalWindow, paints them bottom-to-top by
  ZIndex, hit-tests top-to-bottom, and manages focus / bring-to-front. }

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections,
  uTerminalTypes, uThemeTypes, uTerminalWindow;

type
  TMdiCompositor = class
  private
    FTheme: IThemeRenderer;
    FWindows: TObjectList<TTerminalWindow>;
    FActive: TTerminalWindow;
    FNextId: Cardinal;
    FNextZ: Integer;
    FDiscarded: Boolean;   // set in Destroy; CloseWindow frees immediately instead of ForceQueue
    function VisibleCount: Integer;
    function IndexOfVisible(AWindow: TTerminalWindow): Integer;
    function VisibleAt(AIndex: Integer): TTerminalWindow;
  public
    constructor Create(const ATheme: IThemeRenderer);
    destructor Destroy; override;

    function AddWindow(const ATitle: string): TTerminalWindow;
    // Takes ownership of an already-created window (e.g. TDualPanelWindow).
    function AttachWindow(AWindow: TTerminalWindow): TTerminalWindow;
    function AllocId: Cardinal;
    // Detaches and frees AWindow after the current call stack unwinds.
    procedure CloseWindow(AWindow: TTerminalWindow);
    procedure Clear;

    procedure Activate(AWindow: TTerminalWindow);
    function ActivateAt(ACol, ARow: Integer): Boolean;
    procedure FocusNext;
    procedure FocusPrev;
    procedure BringToFront(AWindow: TTerminalWindow);

    procedure Paint(const AGrid: TTerminalGrid; ACols, ARows: Integer);
    // Cascaded demo layout for Stage 3 (≥2 overlapping windows).
    procedure LayoutCascade(ACols, ARows: Integer);
    // Single maximized window; ATopMargin reserves rows above (Dual Panel Tabs).
    procedure LayoutMaximized(ACols, ARows: Integer; ATopMargin: Integer = 0);

    property Theme: IThemeRenderer read FTheme;
    property Windows: TObjectList<TTerminalWindow> read FWindows;
    property Active: TTerminalWindow read FActive;
    property Count: Integer read VisibleCount;
  end;

implementation

constructor TMdiCompositor.Create(const ATheme: IThemeRenderer);
begin
  inherited Create;
  FTheme := ATheme;
  FWindows := TObjectList<TTerminalWindow>.Create(True);
  FActive := nil;
  FNextId := 1;
  FNextZ := 1;
  FDiscarded := False;
end;

destructor TMdiCompositor.Destroy;
begin
  // Mark first so any CloseWindow driven by pending callbacks during teardown
  // frees the window inline instead of queuing a ForceQueue that would fire
  // after FWindows is gone (double-free / access to freed list).
  FDiscarded := True;
  FActive := nil;
  FWindows.Free;
  inherited Destroy;
end;

function TMdiCompositor.VisibleCount: Integer;
var
  W: TTerminalWindow;
begin
  Result := 0;
  for W in FWindows do
    if W.Visible then
      Inc(Result);
end;

function TMdiCompositor.IndexOfVisible(AWindow: TTerminalWindow): Integer;
var
  W: TTerminalWindow;
begin
  Result := -1;
  if (AWindow = nil) or not AWindow.Visible then
    Exit;
  for W in FWindows do
    if W.Visible then
    begin
      Inc(Result);
      if W = AWindow then
        Exit;
    end;
  Result := -1;
end;

function TMdiCompositor.VisibleAt(AIndex: Integer): TTerminalWindow;
var
  W: TTerminalWindow;
  I: Integer;
begin
  Result := nil;
  I := 0;
  for W in FWindows do
    if W.Visible then
    begin
      if I = AIndex then
        Exit(W);
      Inc(I);
    end;
end;

function TMdiCompositor.AddWindow(const ATitle: string): TTerminalWindow;
begin
  Result := TTerminalWindow.Create(FTheme, FNextId);
  Inc(FNextId);
  Result.Title := ATitle;
  Result.ZIndex := FNextZ;
  Inc(FNextZ);
  Result.IsFocused := False;
  FWindows.Add(Result);
  Activate(Result);
end;

function TMdiCompositor.AttachWindow(AWindow: TTerminalWindow): TTerminalWindow;
begin
  Result := AWindow;
  if Result = nil then
    Exit;
  Result.ZIndex := FNextZ;
  Inc(FNextZ);
  Result.IsFocused := False;
  FWindows.Add(Result);
  if Result.Id >= FNextId then
    FNextId := Result.Id + 1;
  Activate(Result);
end;

function TMdiCompositor.AllocId: Cardinal;
begin
  Result := FNextId;
  Inc(FNextId);
end;

procedure TMdiCompositor.CloseWindow(AWindow: TTerminalWindow);
var
  Best: TTerminalWindow;
  W: TTerminalWindow;
  WasActive: Boolean;
begin
  if (AWindow = nil) or (FWindows.IndexOf(AWindow) < 0) then
    Exit;

  WasActive := FActive = AWindow;
  if WasActive then
    FActive := nil;

  // Extract without freeing — caller may still be inside AWindow methods.
  FWindows.Extract(AWindow);

  if WasActive then
  begin
    Best := nil;
    for W in FWindows do
      if W.Visible and ((Best = nil) or (W.ZIndex > Best.ZIndex)) then
        Best := W;
    if Best <> nil then
      Activate(Best);
  end;

  // During teardown we must not defer the free: a queued callback could run
  // after Destroy has already released FWindows. Free inline instead.
  if FDiscarded then
    AWindow.Free
  else
    TThread.ForceQueue(nil,
      procedure
      begin
        AWindow.Free;
      end);
end;

procedure TMdiCompositor.Clear;
begin
  FActive := nil;
  FWindows.Clear;
  FNextId := 1;
  FNextZ := 1;
end;

procedure TMdiCompositor.BringToFront(AWindow: TTerminalWindow);
begin
  if AWindow = nil then
    Exit;
  AWindow.ZIndex := FNextZ;
  Inc(FNextZ);
  AWindow.Invalidate;
end;

procedure TMdiCompositor.Activate(AWindow: TTerminalWindow);
var
  W: TTerminalWindow;
begin
  if (AWindow <> nil) and not AWindow.Visible then
    AWindow.Visible := True;

  for W in FWindows do
    W.IsFocused := (W = AWindow) and (AWindow <> nil);

  if AWindow <> nil then
    BringToFront(AWindow);

  FActive := AWindow;
end;

function TMdiCompositor.ActivateAt(ACol, ARow: Integer): Boolean;
var
  Best: TTerminalWindow;
  W: TTerminalWindow;
begin
  Best := nil;
  for W in FWindows do
    if W.HitTest(ACol, ARow) then
      if (Best = nil) or (W.ZIndex > Best.ZIndex) then
        Best := W;

  if Best <> nil then
  begin
    Activate(Best);
    Result := True;
  end
  else
  begin
    // Click on desktop: keep windows visible but clear focus chrome.
    Activate(nil);
    Result := False;
  end;
end;

procedure TMdiCompositor.FocusNext;
var
  N, Idx: Integer;
begin
  N := VisibleCount;
  if N = 0 then
  begin
    Activate(nil);
    Exit;
  end;
  Idx := IndexOfVisible(FActive);
  if Idx < 0 then
    Activate(VisibleAt(0))
  else
    Activate(VisibleAt((Idx + 1) mod N));
end;

procedure TMdiCompositor.FocusPrev;
var
  N, Idx: Integer;
begin
  N := VisibleCount;
  if N = 0 then
  begin
    Activate(nil);
    Exit;
  end;
  Idx := IndexOfVisible(FActive);
  if Idx < 0 then
    Activate(VisibleAt(N - 1))
  else
    Activate(VisibleAt((Idx - 1 + N) mod N));
end;

procedure TMdiCompositor.Paint(const AGrid: TTerminalGrid; ACols, ARows: Integer);
var
  Sorted: TArray<TTerminalWindow>;
  I, J: Integer;
  W: TTerminalWindow;
  Tmp: TTerminalWindow;
begin
  if Assigned(FTheme) then
    FTheme.DrawDesktop(AGrid, TRectI.Make(0, 0, ACols - 1, ARows - 1));

  SetLength(Sorted, FWindows.Count);
  for I := 0 to FWindows.Count - 1 do
    Sorted[I] := FWindows[I];

  // Insertion sort by ZIndex ascending (bottom → top).
  for I := 1 to High(Sorted) do
  begin
    Tmp := Sorted[I];
    J := I - 1;
    while (J >= 0) and (Sorted[J].ZIndex > Tmp.ZIndex) do
    begin
      Sorted[J + 1] := Sorted[J];
      Dec(J);
    end;
    Sorted[J + 1] := Tmp;
  end;

  for W in Sorted do
    if W.Visible then
      W.Paint(AGrid);
end;

procedure TMdiCompositor.LayoutCascade(ACols, ARows: Integer);
var
  I, N: Integer;
  W: TTerminalWindow;
  WinW, WinH, OffX, OffY: Integer;
  Left, Top, Right, Bottom: Integer;
begin
  N := 0;
  for W in FWindows do
    if W.Visible then
      Inc(N);
  if N = 0 then
    Exit;

  WinW := Max(ACols * 2 div 3, 24);
  WinH := Max(ARows * 2 div 3, 10);
  if WinW > ACols - 4 then
    WinW := Max(ACols - 4, 10);
  if WinH > ARows - 4 then
    WinH := Max(ARows - 4, 6);

  OffX := Max((ACols - WinW) div Max(N + 1, 2), 2);
  OffY := Max((ARows - WinH) div Max(N + 1, 2), 1);

  I := 0;
  for W in FWindows do
  begin
    if not W.Visible then
      Continue;
    Left := 2 + I * OffX;
    Top := 1 + I * OffY;
    Right := Left + WinW - 1;
    Bottom := Top + WinH - 1;
    if Right >= ACols - 1 then
    begin
      Right := ACols - 2;
      Left := Max(Right - WinW + 1, 1);
    end;
    if Bottom >= ARows - 1 then
    begin
      Bottom := ARows - 2;
      Top := Max(Bottom - WinH + 1, 0);
    end;
    W.Area := TRectI.Make(Left, Top, Right, Bottom);
    Inc(I);
  end;
end;

procedure TMdiCompositor.LayoutMaximized(ACols, ARows: Integer; ATopMargin: Integer);
var
  W: TTerminalWindow;
  TopRow, Bottom: Integer;
begin
  TopRow := Max(ATopMargin, 0);
  if TopRow > ARows - 2 then
    TopRow := Max(ARows - 2, 0);
  for W in FWindows do
    if W.Visible then
    begin
      Bottom := ARows - 1 - Max(W.LayoutBottomMargin, 0);
      if Bottom <= TopRow then
        Bottom := TopRow + 1;
      W.Area := TRectI.Make(0, TopRow, ACols - 1, Bottom);
    end;
end;

end.
