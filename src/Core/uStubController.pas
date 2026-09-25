unit uStubController;

{ Generic shell-info / folder-size message overlay ("stub"). }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  uTerminalTypes, uThemeTypes, uDualPanelUiTypes,
  uDualPanelOverlays, uDualPanelCmd;

type
  TStubController = class
  private
    FTheme: IThemeRenderer;
    FOnInvalidate: TProc;
    FKind: TStubKind;
    FText: string;
    FDetail: string;
    FBounds: TRectI;
    function GetVisible: Boolean;
  public
    constructor Create(const ATheme: IThemeRenderer; const AOnInvalidate: TProc);
    procedure SetTheme(const ATheme: IThemeRenderer);
    procedure Open(AKind: TStubKind; const ATitle, ADetail: string);
    procedure Close;
    procedure Layout(AClientWidth, AClientHeight: Integer);
    procedure Draw(const AGrid: TTerminalGrid; AClientWidth, AClientHeight: Integer);
    function HandleInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    property Visible: Boolean read GetVisible;
    property Bounds: TRectI read FBounds;
    property Text: string read FText write FText;
    property Detail: string read FDetail write FDetail;
  end;

implementation

const
  cCursorFg = TAlphaColor($FF000000);
  cFileFg   = TAlphaColor($FFAAAAAA);
  cPanelBg  = TAlphaColor($FF0000AA);
  cFrameActive = TAlphaColor($FF55FFFF);
  cMenuHot  = TAlphaColor($FFFFFF55);

constructor TStubController.Create(const ATheme: IThemeRenderer;
  const AOnInvalidate: TProc);
begin
  inherited Create;
  FTheme := ATheme;
  FOnInvalidate := AOnInvalidate;
  FKind := skNone;
end;

procedure TStubController.SetTheme(const ATheme: IThemeRenderer);
begin
  FTheme := ATheme;
end;

function TStubController.GetVisible: Boolean;
begin
  Result := FKind <> skNone;
end;

procedure TStubController.Open(AKind: TStubKind; const ATitle, ADetail: string);
begin
  FKind := AKind;
  FText := ATitle;
  FDetail := ADetail;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TStubController.Close;
begin
  FKind := skNone;
  FText := '';
  FDetail := '';
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TStubController.Layout(AClientWidth, AClientHeight: Integer);
var
  W, H, PanelW, Left, Top: Integer;
begin
  PanelW := AClientWidth;
  // Half of the client width (folder-size / shell-info stub).
  W := Max(PanelW div 2, 28);
  if W > PanelW - 2 then
    W := Max(PanelW - 2, 28);
  H := 9;
  Left := (PanelW - W) div 2;
  Top := Max(AClientHeight div 2 - H div 2, 3);
  if Left + W > PanelW then
    Left := Max(PanelW - W, 0);
  if Top + H > AClientHeight then
    Top := Max(AClientHeight - H, 1);
  FBounds := TRectI.Make(Left, Top, Left + W - 1, Top + H - 1);
end;

procedure TStubController.Draw(const AGrid: TTerminalGrid;
  AClientWidth, AClientHeight: Integer);
var
  R: TRectI;
  Line, Rest: string;
  MaxW, Y, Cut: Integer;
begin
  if FKind = skNone then
    Exit;
  Layout(AClientWidth, AClientHeight);
  R := FBounds;
  DrawHostOverlayFrame(AGrid, FTheme, R, FText,
    cFileFg, cPanelBg, cFrameActive, cCursorFg);
  MaxW := Max(R.Width - 2, 8);
  Rest := StringReplace(FDetail, #13#10, #10, [rfReplaceAll]);
  Rest := StringReplace(Rest, #13, #10, [rfReplaceAll]);
  Y := R.Top + 2;
  while (Rest <> '') and (Y <= R.Bottom - 3) do
  begin
    Cut := Pos(#10, Rest);
    if Cut > 0 then
    begin
      Line := Copy(Rest, 1, Cut - 1);
      Delete(Rest, 1, Cut);
    end
    else
    begin
      Line := Rest;
      Rest := '';
    end;
    if Length(Line) > MaxW then
    begin
      if (Pos('\', Line) > 0) or (Pos('/', Line) > 0) or (Pos(':', Line) > 0) then
        Line := CompactDisplayPath(Line, MaxW)
      else
        Line := Copy(Line, 1, MaxW - 3) + '...';
    end;
    PutOverlayText(AGrid, FTheme, R.Left + 1, Y, Line,
      False, False, False, cFileFg, cPanelBg);
    Inc(Y);
  end;
  PutOverlayText(AGrid, FTheme, R.Left + 1, R.Bottom - 1, 'Esc=Cancel',
    True, False, False, cMenuHot, cPanelBg);
end;

function TStubController.HandleInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  Result := True;
  if (AKey = vkEscape) or (AKey = vkReturn) then
  begin
    Close;
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    AKey := 0;
  end
  else
  begin
    AKey := 0;
    AKeyChar := #0;
  end;
end;

end.
