unit uThumbsLayout;

{ Thumbnail sheet of a folder of pictures: the grid geometry, the selection and
  its keys, mouse hit testing, the area-average downscaling of a picture to a
  cell, and the painting of one page into a 32-bit (blue, green, red, alpha)
  frame. No host calls: the plugin gives it pixels and takes a frame back. }

{$POINTERMATH ON}

interface

uses
  System.SysUtils, System.Math;

const
  cCellW = 160;
  cCellH = 140;
  /// <summary>Room around the picture inside a cell.</summary>
  cCellPad = 10;
  cFrameWidth = 3;

type
  TThumbImage = record
    Width: Integer;
    Height: Integer;
    /// <summary>Width * Height pixels of 4 bytes; empty while not decoded.</summary>
    Pixels: TBytes;
    /// <summary>The picture could not be decoded: the cell shows a mark.</summary>
    Failed: Boolean;
  end;

  TThumbsModel = class
  private
    FCount: Integer;
    FSelected: Integer;
    FAreaW: Integer;
    FAreaH: Integer;
    function GetCols: Integer;
    function GetRows: Integer;
    function GetPerPage: Integer;
    function GetFirst: Integer;
    function MarginX: Integer;
    function MarginY: Integer;
  public
    constructor Create(ACount: Integer);
    procedure SetArea(AWidth, AHeight: Integer);
    /// <summary>Moves the selection for a key named as the host names it
    /// (Left, Right, Up, Down, Home, End, PageUp, PageDown). True when the key
    /// was a movement.</summary>
    function HandleKey(const AKey: string): Boolean;
    /// <summary>The picture under a pixel of the area, -1 for none.</summary>
    function HitTest(AX, AY: Integer): Integer;
    procedure Select(AIndex: Integer);
    /// <summary>The cell of picture AIndex when it is on the shown page.</summary>
    function CellRect(AIndex: Integer; out ALeft, ATop: Integer): Boolean;
    property Count: Integer read FCount;
    property Selected: Integer read FSelected;
    property Cols: Integer read GetCols;
    property Rows: Integer read GetRows;
    property PerPage: Integer read GetPerPage;
    /// <summary>Index of the first picture of the shown page.</summary>
    property First: Integer read GetFirst;
    property AreaWidth: Integer read FAreaW;
    property AreaHeight: Integer read FAreaH;
  end;

/// <summary>The size a picture takes in a box: scaled down to fit, never up.</summary>
procedure FitInBox(ASrcW, ASrcH, ABoxW, ABoxH: Integer; out AW, AH: Integer);

/// <summary>Shrinks BGRA pixels to ADstW x ADstH by averaging the source pixels
/// each target pixel covers.</summary>
function ShrinkPixels(const ASrc: TBytes; ASrcW, ASrcH, ADstW, ADstH: Integer): TBytes;

/// <summary>Paints the page of AModel that holds the selection: the cells of
/// AImages (indexed like the pictures) with a frame on the selected one. The
/// frame is AModel.AreaWidth x AModel.AreaHeight BGRA pixels.</summary>
function PaintSheet(const AModel: TThumbsModel; const AImages: TArray<TThumbImage>): TBytes;

implementation

const
  cBackground = $FF1E1E1E;
  cCellBackground = $FF2A2A2A;
  cSelectedBackground = $FF35507A;
  cFrameColor = $FF7FB2FF;
  cFailedMark = $FF8A4040;

constructor TThumbsModel.Create(ACount: Integer);
begin
  inherited Create;
  FCount := Max(ACount, 0);
  FAreaW := cCellW * 4;
  FAreaH := cCellH * 3;
end;

procedure TThumbsModel.SetArea(AWidth, AHeight: Integer);
begin
  FAreaW := Max(AWidth, cCellW);
  FAreaH := Max(AHeight, cCellH);
end;

function TThumbsModel.GetCols: Integer;
begin
  Result := Max(FAreaW div cCellW, 1);
end;

function TThumbsModel.GetRows: Integer;
begin
  Result := Max(FAreaH div cCellH, 1);
end;

function TThumbsModel.GetPerPage: Integer;
begin
  Result := GetCols * GetRows;
end;

function TThumbsModel.GetFirst: Integer;
begin
  Result := (FSelected div GetPerPage) * GetPerPage;
end;

function TThumbsModel.MarginX: Integer;
begin
  Result := (FAreaW - GetCols * cCellW) div 2;
end;

function TThumbsModel.MarginY: Integer;
begin
  Result := (FAreaH - GetRows * cCellH) div 2;
end;

procedure TThumbsModel.Select(AIndex: Integer);
begin
  if FCount = 0 then
    FSelected := 0
  else
    FSelected := EnsureRange(AIndex, 0, FCount - 1);
end;

function TThumbsModel.HandleKey(const AKey: string): Boolean;
begin
  Result := True;
  if AKey = 'Left' then
    Select(FSelected - 1)
  else if AKey = 'Right' then
    Select(FSelected + 1)
  else if AKey = 'Up' then
    Select(FSelected - GetCols)
  else if AKey = 'Down' then
    Select(FSelected + GetCols)
  else if AKey = 'Home' then
    Select(0)
  else if AKey = 'End' then
    Select(FCount - 1)
  else if AKey = 'PageUp' then
    Select(FSelected - GetPerPage)
  else if AKey = 'PageDown' then
    Select(FSelected + GetPerPage)
  else
    Result := False;
end;

function TThumbsModel.HitTest(AX, AY: Integer): Integer;
var
  Col, Row: Integer;
begin
  Result := -1;
  AX := AX - MarginX;
  AY := AY - MarginY;
  if (AX < 0) or (AY < 0) then
    Exit;
  Col := AX div cCellW;
  Row := AY div cCellH;
  if (Col >= GetCols) or (Row >= GetRows) then
    Exit;
  Result := GetFirst + Row * GetCols + Col;
  if Result >= FCount then
    Result := -1;
end;

function TThumbsModel.CellRect(AIndex: Integer; out ALeft, ATop: Integer): Boolean;
var
  Slot: Integer;
begin
  Slot := AIndex - GetFirst;
  Result := (AIndex >= 0) and (AIndex < FCount) and (Slot >= 0) and (Slot < GetPerPage);
  if not Result then
    Exit;
  ALeft := MarginX + (Slot mod GetCols) * cCellW;
  ATop := MarginY + (Slot div GetCols) * cCellH;
end;

procedure FitInBox(ASrcW, ASrcH, ABoxW, ABoxH: Integer; out AW, AH: Integer);
var
  Scale: Double;
begin
  AW := 0;
  AH := 0;
  if (ASrcW <= 0) or (ASrcH <= 0) or (ABoxW <= 0) or (ABoxH <= 0) then
    Exit;
  Scale := Min(Min(ABoxW / ASrcW, ABoxH / ASrcH), 1.0);
  AW := Max(Round(ASrcW * Scale), 1);
  AH := Max(Round(ASrcH * Scale), 1);
end;

function ShrinkPixels(const ASrc: TBytes; ASrcW, ASrcH, ADstW, ADstH: Integer): TBytes;
var
  X, Y, SX, SY, X0, X1, Y0, Y1, N, C: Integer;
  Sum: array[0..3] of Cardinal;
  P: PByte;
begin
  SetLength(Result, 0);
  if (ASrcW <= 0) or (ASrcH <= 0) or (ADstW <= 0) or (ADstH <= 0) or
     (Length(ASrc) < ASrcW * ASrcH * 4) then
    Exit;
  SetLength(Result, ADstW * ADstH * 4);
  for Y := 0 to ADstH - 1 do
  begin
    Y0 := Y * ASrcH div ADstH;
    Y1 := Max((Y + 1) * ASrcH div ADstH, Y0 + 1);
    for X := 0 to ADstW - 1 do
    begin
      X0 := X * ASrcW div ADstW;
      X1 := Max((X + 1) * ASrcW div ADstW, X0 + 1);
      Sum[0] := 0;
      Sum[1] := 0;
      Sum[2] := 0;
      Sum[3] := 0;
      N := 0;
      for SY := Y0 to Min(Y1, ASrcH) - 1 do
      begin
        P := @ASrc[(SY * ASrcW + X0) * 4];
        for SX := X0 to Min(X1, ASrcW) - 1 do
        begin
          for C := 0 to 3 do
            Inc(Sum[C], P[C]);
          Inc(P, 4);
          Inc(N);
        end;
      end;
      if N = 0 then
        N := 1;
      for C := 0 to 3 do
        Result[(Y * ADstW + X) * 4 + C] := Byte(Sum[C] div Cardinal(N));
    end;
  end;
end;

procedure FillRectPx(var AFrame: TBytes; AFrameW, AFrameH, ALeft, ATop, AWidth, AHeight: Integer;
  AColor: Cardinal);
var
  X, Y, X0, X1, Y1: Integer;
  P: PCardinal;
begin
  X0 := Max(ALeft, 0);
  X1 := Min(ALeft + AWidth, AFrameW);
  Y1 := Min(ATop + AHeight, AFrameH);
  for Y := Max(ATop, 0) to Y1 - 1 do
  begin
    P := PCardinal(@AFrame[(Y * AFrameW + X0) * 4]);
    for X := X0 to X1 - 1 do
    begin
      P^ := AColor;
      Inc(P);
    end;
  end;
end;

procedure FrameRectPx(var AFrame: TBytes; AFrameW, AFrameH, ALeft, ATop, AWidth, AHeight,
  AThick: Integer; AColor: Cardinal);
begin
  FillRectPx(AFrame, AFrameW, AFrameH, ALeft, ATop, AWidth, AThick, AColor);
  FillRectPx(AFrame, AFrameW, AFrameH, ALeft, ATop + AHeight - AThick, AWidth, AThick, AColor);
  FillRectPx(AFrame, AFrameW, AFrameH, ALeft, ATop, AThick, AHeight, AColor);
  FillRectPx(AFrame, AFrameW, AFrameH, ALeft + AWidth - AThick, ATop, AThick, AHeight, AColor);
end;

/// <summary>Copies a picture into the frame, blending its alpha over what is there.</summary>
procedure BlendImage(var AFrame: TBytes; AFrameW, AFrameH, ALeft, ATop: Integer;
  const APixels: TBytes; AW, AH: Integer);
var
  X, Y, C, Alpha, Dx, Dy: Integer;
  S, D: PByte;
begin
  for Y := 0 to AH - 1 do
  begin
    Dy := ATop + Y;
    if (Dy < 0) or (Dy >= AFrameH) then
      Continue;
    for X := 0 to AW - 1 do
    begin
      Dx := ALeft + X;
      if (Dx < 0) or (Dx >= AFrameW) then
        Continue;
      S := @APixels[(Y * AW + X) * 4];
      D := @AFrame[(Dy * AFrameW + Dx) * 4];
      Alpha := S[3];
      for C := 0 to 2 do
        D[C] := Byte((S[C] * Alpha + D[C] * (255 - Alpha)) div 255);
      D[3] := 255;
    end;
  end;
end;

function PaintSheet(const AModel: TThumbsModel; const AImages: TArray<TThumbImage>): TBytes;
var
  I, Left, Top, W, H, Last: Integer;
  Img: TThumbImage;
  Small: TBytes;
  Selected: Boolean;
begin
  SetLength(Result, AModel.AreaWidth * AModel.AreaHeight * 4);
  FillRectPx(Result, AModel.AreaWidth, AModel.AreaHeight, 0, 0, AModel.AreaWidth,
    AModel.AreaHeight, cBackground);
  Last := Min(AModel.First + AModel.PerPage, AModel.Count) - 1;
  for I := AModel.First to Last do
  begin
    if not AModel.CellRect(I, Left, Top) then
      Continue;
    Selected := I = AModel.Selected;
    if Selected then
      FillRectPx(Result, AModel.AreaWidth, AModel.AreaHeight, Left + 2, Top + 2,
        cCellW - 4, cCellH - 4, cSelectedBackground)
    else
      FillRectPx(Result, AModel.AreaWidth, AModel.AreaHeight, Left + 2, Top + 2,
        cCellW - 4, cCellH - 4, cCellBackground);
    if I <= High(AImages) then
    begin
      Img := AImages[I];
      if Img.Failed then
        FillRectPx(Result, AModel.AreaWidth, AModel.AreaHeight, Left + cCellW div 2 - 12,
          Top + cCellH div 2 - 12, 24, 24, cFailedMark)
      else if (Img.Width > 0) and (Length(Img.Pixels) >= Img.Width * Img.Height * 4) then
      begin
        FitInBox(Img.Width, Img.Height, cCellW - 2 * cCellPad, cCellH - 2 * cCellPad, W, H);
        if (W = Img.Width) and (H = Img.Height) then
          Small := Img.Pixels
        else
          Small := ShrinkPixels(Img.Pixels, Img.Width, Img.Height, W, H);
        BlendImage(Result, AModel.AreaWidth, AModel.AreaHeight,
          Left + (cCellW - W) div 2, Top + (cCellH - H) div 2, Small, W, H);
      end;
    end;
    if Selected then
      FrameRectPx(Result, AModel.AreaWidth, AModel.AreaHeight, Left + 1, Top + 1,
        cCellW - 2, cCellH - 2, cFrameWidth, cFrameColor);
  end;
end;

end.
