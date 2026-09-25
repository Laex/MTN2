unit uDialogRenderer;

{ Dialog Renderer: Isolates layout calculation and control rendering for
  declarative JSON dialogs from uDialogHost.pas. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  uTerminalTypes, uThemeTypes, uDialogTypes;

type
  /// <summary>Helper class for rendering dialog frames and controls.</summary>
  TDialogRenderer = class
  public
    class procedure DrawDialogFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const ATitle: string; const ATheme: IThemeRenderer);
    class procedure DrawButton(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const AText: string; AIsFocused, AIsDefault: Boolean; const ATheme: IThemeRenderer);
    class procedure DrawCheckbox(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const AText: string; AIsChecked, AIsFocused: Boolean; const ATheme: IThemeRenderer);
    /// <summary>Word-wrap AText to AWidth columns. Existing CR/LF are hard
    /// breaks; a token longer than AWidth is split at exactly AWidth.
    /// Always returns at least one (possibly empty) line.</summary>
    class function WrapLabelLines(const AText: string; AWidth: Integer): TArray<string>;
    class procedure DrawLabel(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const AText: string; AFg, ABg: TAlphaColor);
  end;

implementation

class procedure TDialogRenderer.DrawDialogFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const ATitle: string; const ATheme: IThemeRenderer);
begin
  if Assigned(ATheme) then
    ATheme.DrawDialogFrame(AGrid, ABounds, ATitle, [twFocused]);
end;

class procedure TDialogRenderer.DrawButton(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AText: string; AIsFocused, AIsDefault: Boolean; const ATheme: IThemeRenderer);
var
  LCaption: string;
  LState: TThemeWidgetState;
begin
  if AIsDefault then
    LCaption := '[< ' + AText + ' >]'
  else
    LCaption := '[ ' + AText + ' ]';

  if AIsFocused then
    LState := [twFocused]
  else
    LState := [];

  if Assigned(ATheme) then
    ATheme.DrawButton(AGrid, ABounds, LCaption, LState);
end;

class procedure TDialogRenderer.DrawCheckbox(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AText: string; AIsChecked, AIsFocused: Boolean; const ATheme: IThemeRenderer);
var
  LMark: string;
  LState: TThemeWidgetState;
begin
  if AIsChecked then
    LMark := '[x] '
  else
    LMark := '[ ] ';

  if AIsFocused then
    LState := [twFocused]
  else
    LState := [];

  if Assigned(ATheme) then
    ATheme.DrawCheckbox(AGrid, ABounds, LMark + AText, AIsChecked, LState);
end;

class function TDialogRenderer.WrapLabelLines(const AText: string;
  AWidth: Integer): TArray<string>;
var
  Lines: TStringList;
  I, Start, Cut, LastBreak: Integer;
  Para, Chunk: string;
begin
  if AWidth < 1 then
    AWidth := 1;
  Lines := TStringList.Create;
  try
    I := 1;
    while I <= Length(AText) do
    begin
      Start := I;
      while (I <= Length(AText)) and (AText[I] <> #10) and (AText[I] <> #13) do
        Inc(I);
      Para := Copy(AText, Start, I - Start);
      if Para = '' then
        Lines.Add('')
      else
        while Para <> '' do
        begin
          if Length(Para) <= AWidth then
          begin
            Lines.Add(Para);
            Break;
          end;
          Chunk := Copy(Para, 1, AWidth);
          LastBreak := 0;
          for Cut := Length(Chunk) downto 1 do
            if (Chunk[Cut] = ' ') or (Chunk[Cut] = #9) then
            begin
              LastBreak := Cut;
              Break;
            end;
          if (LastBreak > 1) and (LastBreak < AWidth) then
          begin
            Lines.Add(TrimRight(Copy(Para, 1, LastBreak - 1)));
            Para := TrimLeft(Copy(Para, LastBreak + 1, MaxInt));
          end
          else
          begin
            Lines.Add(Chunk);
            Para := TrimLeft(Copy(Para, AWidth + 1, MaxInt));
          end;
        end;
      if (I <= Length(AText)) and (AText[I] = #13) then
        Inc(I);
      if (I <= Length(AText)) and (AText[I] = #10) then
        Inc(I);
    end;
    if Lines.Count = 0 then
      Lines.Add('');
    Result := Lines.ToStringArray;
  finally
    Lines.Free;
  end;
end;

class procedure TDialogRenderer.DrawLabel(const AGrid: TTerminalGrid;
  const ABounds: TRectI; const AText: string; AFg, ABg: TAlphaColor);
var
  Lines: TArray<string>;
  Text: string;
  W, H, J: Integer;
  Rule: Boolean;
begin
  W := Max(ABounds.Width, 1);
  H := Max(ABounds.Height, 1);
  Text := AText;
  // Pure rule labels must fill the box; JSON sometimes stores fewer glyphs
  // than width, which leaves a gap before the right frame.
  if Text <> '' then
  begin
    Rule := True;
    for J := 1 to Length(Text) do
      if not ((Text[J] = '-') or (Text[J] = '=') or (Text[J] = '_') or
        (Ord(Text[J]) = $2500) or (Ord(Text[J]) = $2501) or
        (Ord(Text[J]) = $2550)) then
      begin
        Rule := False;
        Break;
      end;
    if Rule and (Length(Text) < W) then
      Text := StringOfChar(Text[1], W);
  end;
  Lines := WrapLabelLines(Text, W);
  for J := 0 to Min(High(Lines), H - 1) do
    PutGridText(AGrid, ABounds.Left, ABounds.Top + J,
      Copy(Lines[J], 1, W), AFg, ABg);
end;

end.
