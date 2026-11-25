unit uDialogJsonSerialize;

{ TDialogDeclaration -> DIALOG_PLUGIN JSON subset. }

interface

uses
  System.SysUtils,
  uDialogTypes;

function DeclarationToJson(const ADecl: TDialogDeclaration): string;

implementation

uses
  System.StrUtils;

function EscapeJson(const S: string): string;
begin
  Result := StringReplace(S, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
end;

function ControlGeometryJson(const C: TDialogControl; AForce: Boolean): string;
begin
  Result := '';
  if AForce or (C.Col >= 0) or (C.Row >= 0) or (C.BoxW > 0) or (C.BoxH > 0) then
  begin
    if C.Col >= 0 then
      Result := Result + Format(',"col":%d', [C.Col]);
    if C.Row >= 0 then
      Result := Result + Format(',"row":%d', [C.Row]);
    if C.BoxW > 0 then
      Result := Result + Format(',"width":%d', [C.BoxW]);
    if C.BoxH > 0 then
      Result := Result + Format(',"height":%d', [C.BoxH]);
  end;
end;

function DeclarationToJson(const ADecl: TDialogDeclaration): string;
var
  Parts: TArray<string>;
  I, J, N: Integer;
  C: TDialogControl;
  One, Ver: string;
  ForceGeom: Boolean;
begin
  Ver := Trim(ADecl.Version);
  if Ver = '' then
    Ver := cDialogProtocolV1;
  ForceGeom := IsDialogProtocolV2(Ver);
  SetLength(Parts, 0);
  for I := 0 to High(ADecl.Controls) do
  begin
    C := ADecl.Controls[I];
    case C.Kind of
      dckLabel:
        if IsHRuleText(C.Text) then
          One := '{"type":"separator"'
        else
        begin
          One := Format('{"type":"label","text":"%s"', [EscapeJson(C.Text)]);
          if C.Id <> '' then
            One := One + Format(',"id":"%s"', [EscapeJson(C.Id)]);
          if C.Accent then
            One := One + ',"accent":true';
          if C.Marked then
            One := One + ',"marked":true';
          if C.HintArea then
            One := One + ',"hint_area":true';
          if C.GroupFrame then
            One := One + ',"group":true';
        end;
      dckInput:
        begin
          One := Format('{"type":"input","id":"%s","value":"%s"',
            [EscapeJson(C.Id), EscapeJson(C.Edit.Text)]);
          if C.Password then
            One := One + ',"password":true';
          if C.ReadOnly then
            One := One + ',"readonly":true';
          if C.HotKey then
            One := One + ',"hotkey":true';
          if C.HotKeyMulti then
            One := One + ',"multi":true';
          if C.History <> '' then
            One := One + Format(',"history":"%s"', [EscapeJson(C.History)]);
          if C.ColorPick then
            One := One + ',"colorpick":true';
          if C.DatePick then
            One := One + ',"datepick":true';
        end;
      dckCheckbox:
        begin
          if C.Checked then
            One := Format('{"type":"checkbox","id":"%s","text":"%s","checked":true',
              [EscapeJson(C.Id), EscapeJson(C.Text)])
          else
            One := Format('{"type":"checkbox","id":"%s","text":"%s","checked":false',
              [EscapeJson(C.Id), EscapeJson(C.Text)]);
          if C.Tristate then
            One := One + ',"tristate":true';
          if C.Unknown then
            One := One + ',"unknown":true';
        end;
      dckButton:
        begin
          One := Format('{"type":"button","id":"%s","text":"%s"',
            [EscapeJson(C.Id), EscapeJson(C.Text)]);
          if C.IsDefault then
            One := One + ',"default":true';
          if C.IsCancel then
            One := One + ',"cancel":true';
        end;
      dckStatus:
        One := Format('{"type":"status","id":"%s","text":"%s"',
          [EscapeJson(C.Id), EscapeJson(C.Text)]);
      dckColorPicker:
        One := Format('{"type":"colorpicker","id":"%s"', [EscapeJson(C.Id)]);
      dckDatePicker:
        One := Format('{"type":"datepicker","id":"%s"', [EscapeJson(C.Id)]);
      dckColorSample:
        begin
          One := Format('{"type":"colorsample","id":"%s","text":"%s"',
            [EscapeJson(C.Id), EscapeJson(C.Text)]);
          if C.FgSourceId <> '' then
            One := One + Format(',"fgFrom":"%s"', [EscapeJson(C.FgSourceId)]);
          if C.BgSourceId <> '' then
            One := One + Format(',"bgFrom":"%s"', [EscapeJson(C.BgSourceId)]);
          if C.StyleSourceId <> '' then
            One := One + Format(',"styleFrom":"%s"', [EscapeJson(C.StyleSourceId)]);
          if C.BaseStyle <> '' then
            One := One + Format(',"baseStyle":"%s"', [EscapeJson(C.BaseStyle)]);
          if C.FgFallbackId <> '' then
            One := One + Format(',"fgFallback":"%s"', [EscapeJson(C.FgFallbackId)]);
          if C.BgFallbackId <> '' then
            One := One + Format(',"bgFallback":"%s"', [EscapeJson(C.BgFallbackId)]);
        end;
      dckList:
        begin
          One := Format('{"type":"list","id":"%s","selected":%d,"items":[',
            [EscapeJson(C.Id), C.SelectedIndex]);
          for J := 0 to High(C.Items) do
          begin
            if J > 0 then
              One := One + ',';
            One := One + '"' + EscapeJson(C.Items[J]) + '"';
          end;
          One := One + ']';
          if C.Framed then
            One := One + ',"frame":true';
          if C.Plain then
            One := One + ',"plain":true';
          if C.KeyCommands then
            One := One + ',"keycommands":true';
        end;
      dckDropDown:
        begin
          One := Format('{"type":"dropdown","id":"%s","selected":%d,"items":[',
            [EscapeJson(C.Id), C.SelectedIndex]);
          for J := 0 to High(C.Items) do
          begin
            if J > 0 then
              One := One + ',';
            One := One + '"' + EscapeJson(C.Items[J]) + '"';
          end;
          One := One + ']';
        end;
      dckTab:
        begin
          One := Format('{"type":"tabs","id":"%s","selected":%d,"items":[',
            [EscapeJson(C.Id), C.SelectedIndex]);
          for J := 0 to High(C.Items) do
          begin
            if J > 0 then
              One := One + ',';
            One := One + '"' + EscapeJson(C.Items[J]) + '"';
          end;
          One := One + ']';
          if C.Vertical then
            One := One + ',"vertical":true';
        end;
      dckRadio:
        begin
          One := Format(
            '{"type":"radio","id":"%s","group":"%s","text":"%s"',
            [EscapeJson(C.Id), EscapeJson(C.Group), EscapeJson(C.Text)]);
          if C.Checked then
            One := One + ',"checked":true'
          else
            One := One + ',"checked":false';
        end;
      dckRadioGroup:
        begin
          One := Format(
            '{"type":"radio_group","id":"%s","text":"%s","selected":%d,"items":[',
            [EscapeJson(C.Id), EscapeJson(C.Text), C.SelectedIndex]);
          for J := 0 to High(C.Items) do
          begin
            if J > 0 then
              One := One + ',';
            One := One + '"' + EscapeJson(C.Items[J]) + '"';
          end;
          One := One + ']';
          if Length(C.ItemIds) > 0 then
          begin
            One := One + ',"item_ids":[';
            for J := 0 to High(C.ItemIds) do
            begin
              if J > 0 then
                One := One + ',';
              One := One + '"' + EscapeJson(C.ItemIds[J]) + '"';
            end;
            One := One + ']';
          end;
        end;
    else
      Continue;
    end;
    if C.Hint <> '' then
      One := One + Format(',"hint":"%s"', [EscapeJson(C.Hint)]);
    if C.TabPage > 0 then
      One := One + Format(',"tab":%d', [C.TabPage - 1]);
    One := One + ControlGeometryJson(C, ForceGeom) + '}';
    N := Length(Parts);
    SetLength(Parts, N + 1);
    Parts[N] := One;
  end;
  Result := Format(
    '{"type":"dialog","version":"%s","title":"%s","width":%d,"height":%d,%s"children":[%s]}',
    [EscapeJson(Ver), EscapeJson(ADecl.Title), ADecl.Width, ADecl.Height,
     IfThen(ADecl.NoAutoLayout, '"autoLayout":false,', ''), string.Join(',', Parts)]);
end;



end.