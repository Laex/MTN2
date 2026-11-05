unit uPdfView;

{ View state of the PDF viewer: current page, zoom, scroll position and the
  keys and mouse moves that change them. It knows nothing about PDFium; the
  plugin asks Layout which part of the page to draw. }

interface

uses
  System.SysUtils;

type
  TPdfFit = (pfFitWidth, pfFitPage, pfZoom);

  /// <summary>What to draw: the page scaled to ScaledW x ScaledH pixels, of
  /// which the frame FrameW x FrameH shows the part whose top-left corner is
  /// (-StartX, -StartY) from the page's top-left corner.</summary>
  TPdfLayout = record
    Scale: Double;
    ScaledW, ScaledH: Integer;
    FrameW, FrameH: Integer;
    StartX, StartY: Integer;
  end;

  TPdfView = class
  private
    FPageCount: Integer;
    FPage: Integer;
    FPageW, FPageH: Double;
    FAreaW, FAreaH: Integer;
    FFit: TPdfFit;
    FZoom: Double;
    FOffX, FOffY: Integer;
    FPendingBottom: Boolean;
    FPageChanged: Boolean;
    function ScaleNow: Double;
    function MaxOffX: Integer;
    function MaxOffY: Integer;
    procedure Clamp;
    procedure GoPage(AIndex: Integer; AToBottom: Boolean);
    procedure ZoomBy(AFactor: Double);
  public
    constructor Create(APageCount: Integer);
    procedure SetArea(AWidth, AHeight: Integer);
    procedure SetPageSize(AWidth, AHeight: Double);
    function Layout: TPdfLayout;
    /// <summary>Key named as the host names them ("PageDown", "Space", "+", "w");
    /// True when the key changed something or is one the viewer owns.</summary>
    function HandleKey(const AKey: string): Boolean;
    /// <summary>Scrolls by pixels; going past the end of a page turns it.</summary>
    procedure ScrollBy(ADx, ADy: Integer);
    procedure Wheel(AClicks: Integer; ACtrl: Boolean);
    function StatusText(const AFormat: string): string;
    function Percent: Integer;
    /// <summary>True once after the current page changed, so the caller can
    /// read the new page's size before drawing.</summary>
    function TakePageChanged: Boolean;
    property Page: Integer read FPage;
    property PageCount: Integer read FPageCount;
    property Fit: TPdfFit read FFit;
    property AreaWidth: Integer read FAreaW;
    property AreaHeight: Integer read FAreaH;
  end;

/// <summary>A 24-bit BMP file image of ABgra (AWidth x AHeight, rows top to
/// bottom, 4 bytes per pixel); alpha is dropped. Empty when the size does not
/// match the data.</summary>
function BgraToBmp(const ABgra: TBytes; AWidth, AHeight: Integer): TBytes;

implementation

uses
  System.Math;

const
  cMinZoom = 0.1;
  cMaxZoom = 8.0;
  cMaxScaledSide = 16000;
  cScreenDpiRatio = 96 / 72;

function BgraToBmp(const ABgra: TBytes; AWidth, AHeight: Integer): TBytes;
const
  cHeaderSize = 54;
var
  RowBytes, Y, X, Src, Dst, Total: Integer;

  procedure PutInt(AOffset, AValue: Integer);
  begin
    Result[AOffset] := AValue and $FF;
    Result[AOffset + 1] := (AValue shr 8) and $FF;
    Result[AOffset + 2] := (AValue shr 16) and $FF;
    Result[AOffset + 3] := (AValue shr 24) and $FF;
  end;

begin
  SetLength(Result, 0);
  if (AWidth <= 0) or (AHeight <= 0) or (Length(ABgra) <> AWidth * AHeight * 4) then
    Exit;
  RowBytes := (AWidth * 3 + 3) and not 3;
  Total := cHeaderSize + RowBytes * AHeight;
  SetLength(Result, Total);
  FillChar(Result[0], Total, 0);
  Result[0] := Ord('B');
  Result[1] := Ord('M');
  PutInt(2, Total);
  PutInt(10, cHeaderSize);
  PutInt(14, 40);
  PutInt(18, AWidth);
  PutInt(22, AHeight);
  Result[26] := 1;
  Result[28] := 24;
  PutInt(34, RowBytes * AHeight);
  for Y := 0 to AHeight - 1 do
  begin
    Dst := cHeaderSize + (AHeight - 1 - Y) * RowBytes;
    Src := Y * AWidth * 4;
    for X := 0 to AWidth - 1 do
    begin
      Result[Dst] := ABgra[Src];
      Result[Dst + 1] := ABgra[Src + 1];
      Result[Dst + 2] := ABgra[Src + 2];
      Inc(Dst, 3);
      Inc(Src, 4);
    end;
  end;
end;

constructor TPdfView.Create(APageCount: Integer);
begin
  inherited Create;
  FPageCount := Max(APageCount, 1);
  FFit := pfFitWidth;
  FZoom := 1.0;
  FAreaW := 800;
  FAreaH := 600;
  FPageW := 595;
  FPageH := 842;
end;

procedure TPdfView.SetArea(AWidth, AHeight: Integer);
begin
  if (AWidth > 0) and (AHeight > 0) then
  begin
    FAreaW := AWidth;
    FAreaH := AHeight;
    Clamp;
  end;
end;

procedure TPdfView.SetPageSize(AWidth, AHeight: Double);
begin
  if (AWidth > 0) and (AHeight > 0) then
  begin
    FPageW := AWidth;
    FPageH := AHeight;
  end;
  if FPendingBottom then
  begin
    FOffY := MaxInt div 2;
    FPendingBottom := False;
  end;
  Clamp;
end;

function TPdfView.ScaleNow: Double;
begin
  case FFit of
    pfFitWidth: Result := FAreaW / FPageW;
    pfFitPage: Result := Min(FAreaW / FPageW, FAreaH / FPageH);
  else
    Result := FZoom * cScreenDpiRatio;
  end;
  Result := Min(Result, cMaxScaledSide / Max(FPageW, FPageH));
  Result := Max(Result, 0.01);
end;

function TPdfView.MaxOffX: Integer;
begin
  Result := Max(0, Round(FPageW * ScaleNow) - FAreaW);
end;

function TPdfView.MaxOffY: Integer;
begin
  Result := Max(0, Round(FPageH * ScaleNow) - FAreaH);
end;

procedure TPdfView.Clamp;
begin
  FOffX := EnsureRange(FOffX, 0, MaxOffX);
  FOffY := EnsureRange(FOffY, 0, MaxOffY);
end;

function TPdfView.Layout: TPdfLayout;
begin
  Clamp;
  Result.Scale := ScaleNow;
  Result.ScaledW := Max(1, Round(FPageW * Result.Scale));
  Result.ScaledH := Max(1, Round(FPageH * Result.Scale));
  Result.FrameW := Min(FAreaW, Result.ScaledW);
  Result.FrameH := Min(FAreaH, Result.ScaledH);
  Result.StartX := -FOffX;
  Result.StartY := -FOffY;
end;

procedure TPdfView.GoPage(AIndex: Integer; AToBottom: Boolean);
begin
  AIndex := EnsureRange(AIndex, 0, FPageCount - 1);
  if AIndex = FPage then
    Exit;
  FPage := AIndex;
  FOffY := 0;
  FPendingBottom := AToBottom;
  FPageChanged := True;
end;

procedure TPdfView.ZoomBy(AFactor: Double);
var
  Before: Double;
begin
  Before := ScaleNow / cScreenDpiRatio;
  FZoom := EnsureRange(Before * AFactor, cMinZoom, cMaxZoom);
  FFit := pfZoom;
  Clamp;
end;

procedure TPdfView.ScrollBy(ADx, ADy: Integer);
begin
  FOffX := FOffX + ADx;
  if ADy > 0 then
  begin
    if (FOffY >= MaxOffY) and (FPage < FPageCount - 1) then
      GoPage(FPage + 1, False)
    else
      FOffY := FOffY + ADy;
  end
  else if ADy < 0 then
  begin
    if (FOffY <= 0) and (FPage > 0) then
      GoPage(FPage - 1, True)
    else
      FOffY := FOffY + ADy;
  end;
  Clamp;
end;

function TPdfView.HandleKey(const AKey: string): Boolean;
begin
  Result := True;
  if (AKey = 'PageDown') or (AKey = 'Space') then
    ScrollBy(0, Max(1, FAreaH * 9 div 10))
  else if (AKey = 'PageUp') or (AKey = 'Backspace') then
    ScrollBy(0, -Max(1, FAreaH * 9 div 10))
  else if AKey = 'Down' then
    ScrollBy(0, Max(1, FAreaH div 10))
  else if AKey = 'Up' then
    ScrollBy(0, -Max(1, FAreaH div 10))
  else if AKey = 'Right' then
    ScrollBy(Max(1, FAreaW div 10), 0)
  else if AKey = 'Left' then
    ScrollBy(-Max(1, FAreaW div 10), 0)
  else if AKey = 'Home' then
  begin
    GoPage(0, False);
    FOffY := 0;
  end
  else if AKey = 'End' then
    GoPage(FPageCount - 1, False)
  else if (AKey = '+') or (AKey = '=') then
    ZoomBy(1.25)
  else if (AKey = '-') or (AKey = '_') then
    ZoomBy(0.8)
  else if AKey = '0' then
    FFit := pfFitPage
  else if (AKey = 'w') or (AKey = 'W') then
    FFit := pfFitWidth
  else if AKey = '1' then
  begin
    FZoom := 1.0;
    FFit := pfZoom;
  end
  else
    Result := False;
  if Result then
    Clamp;
end;

procedure TPdfView.Wheel(AClicks: Integer; ACtrl: Boolean);
begin
  if AClicks = 0 then
    Exit;
  if ACtrl then
  begin
    if AClicks > 0 then
      ZoomBy(1.25)
    else
      ZoomBy(0.8);
  end
  else
    ScrollBy(0, -AClicks * Max(1, FAreaH div 8));
end;

function TPdfView.Percent: Integer;
begin
  Result := Round(ScaleNow / cScreenDpiRatio * 100);
end;

function TPdfView.StatusText(const AFormat: string): string;
begin
  Result := Format(AFormat, [FPage + 1, FPageCount, Percent]);
end;

function TPdfView.TakePageChanged: Boolean;
begin
  Result := FPageChanged;
  FPageChanged := False;
end;

end.
