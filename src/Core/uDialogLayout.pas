unit uDialogLayout;

{ Protocol 1 dialog flow layout. The caller supplies the frame and the
  controls; nothing here writes host fields. Buttons share a row until one
  would pass the right edge, then wrap. Anything else takes the whole width
  and starts a new row after a button row. }

interface

uses
  System.SysUtils, uDialogTypes, uThemeTypes;

type
  TDialogFlowLayout = record
    Bounds: TArray<TRectI>;
  end;

/// <summary>Places every control inside AFrame in protocol-1 order.</summary>
function LayoutDialogFlow(const AControls: TArray<TDialogControl>;
  const AFrame: TRectI): TDialogFlowLayout;

implementation

uses
  System.Math, uDialogV2Layout;

procedure PlaceFlowButton(var ABounds: TArray<TRectI>; AIndex: Integer;
  const C: TDialogControl; AInnerLeft, AInnerRight: Integer;
  var AY, ABtnX: Integer; var AInButtonRow: Boolean);
var
  BtnW: Integer;
begin
  BtnW := ButtonCellWidth(C);
  if not AInButtonRow then
  begin
    AInButtonRow := True;
    ABtnX := AInnerLeft;
  end
  else if (ABtnX > AInnerLeft) and (ABtnX + BtnW - 1 > AInnerRight) then
  begin
    // Wrap overflowing buttons onto the next row.
    Inc(AY);
    ABtnX := AInnerLeft;
  end;
  ABounds[AIndex] := TRectI.Make(ABtnX, AY,
    Min(ABtnX + BtnW - 1, AInnerRight), AY);
  Inc(ABtnX, BtnW + 2);
end;

procedure PlaceFlowBlock(var ABounds: TArray<TRectI>; AIndex: Integer;
  const C: TDialogControl; AInnerLeft, AInnerRight: Integer;
  var AY, ABtnX: Integer; var AInButtonRow: Boolean);
var
  Span: Integer;
begin
  if AInButtonRow then
  begin
    Inc(AY);
    AInButtonRow := False;
    ABtnX := AInnerLeft;
  end;
  // A list and a radio group both occupy ControlRowSpan rows.
  if C.Kind in [dckList, dckRadioGroup] then
  begin
    Span := ControlRowSpan(C);
    ABounds[AIndex] := TRectI.Make(AInnerLeft, AY, AInnerRight, AY + Span - 1);
    Inc(AY, Span);
  end
  else
  begin
    ABounds[AIndex] := TRectI.Make(AInnerLeft, AY, AInnerRight, AY);
    Inc(AY);
  end;
end;

function LayoutDialogFlow(const AControls: TArray<TDialogControl>;
  const AFrame: TRectI): TDialogFlowLayout;
var
  I, Y, BtnX, InnerLeft, InnerRight: Integer;
  InButtonRow: Boolean;
  C: TDialogControl;
begin
  SetLength(Result.Bounds, Length(AControls));
  InnerLeft := AFrame.Left + 2;
  InnerRight := AFrame.Right - 2;
  if InnerRight < InnerLeft then
    InnerRight := InnerLeft;
  Y := AFrame.Top + 2;
  BtnX := InnerLeft;
  InButtonRow := False;

  for I := 0 to High(AControls) do
  begin
    C := AControls[I];
    if C.Kind = dckButton then
      PlaceFlowButton(Result.Bounds, I, C, InnerLeft, InnerRight, Y, BtnX,
        InButtonRow)
    else
      PlaceFlowBlock(Result.Bounds, I, C, InnerLeft, InnerRight, Y, BtnX,
        InButtonRow);
  end;
end;

end.
