unit uDialogJson;

{ DIALOG_PLUGIN JSON subset <-> TDialogDeclaration (in-process seam for cdecl). }

interface

uses
  System.SysUtils,
  uDialogTypes;

function TryParseDialogJson(const AJson: string; out ADecl: TDialogDeclaration): Boolean;
function DeclarationToJson(const ADecl: TDialogDeclaration): string;

implementation

uses
  System.JSON, System.StrUtils, System.Generics.Collections;

function JsonBool(const AObj: TJSONObject; const AName: string;
  ADefault: Boolean = False): Boolean;
var
  V: TJSONValue;
begin
  Result := ADefault;
  if not Assigned(AObj) then
    Exit;
  V := AObj.Values[AName];
  if V is TJSONBool then
    Result := TJSONBool(V).AsBoolean;
end;

function JsonInt(const AObj: TJSONObject; const AName: string;
  ADefault: Integer): Integer;
var
  V: TJSONValue;
begin
  Result := ADefault;
  if not Assigned(AObj) then
    Exit;
  V := AObj.Values[AName];
  if V is TJSONNumber then
    Result := TJSONNumber(V).AsInt;
end;

function JsonStr(const AObj: TJSONObject; const AName: string;
  const ADefault: string = ''): string;
var
  V: TJSONValue;
begin
  Result := ADefault;
  if not Assigned(AObj) then
    Exit;
  V := AObj.Values[AName];
  if V is TJSONString then
    Result := TJSONString(V).Value;
end;

procedure AppendControl(var AList: TList<TDialogControl>; const ACtrl: TDialogControl);
begin
  AList.Add(ACtrl);
end;

procedure ApplyLayoutFromJson(var C: TDialogControl; const AObj: TJSONObject);
begin
  if not Assigned(AObj) then
    Exit;
  if Assigned(AObj.Values['col']) then
    C.Col := JsonInt(AObj, 'col', 0)
  else if Assigned(AObj.Values['x']) then
    C.Col := JsonInt(AObj, 'x', 0);
  if Assigned(AObj.Values['row']) then
    C.Row := JsonInt(AObj, 'row', 0)
  else if Assigned(AObj.Values['y']) then
    C.Row := JsonInt(AObj, 'y', 0);
  if Assigned(AObj.Values['width']) then
    C.BoxW := JsonInt(AObj, 'width', 0)
  else if Assigned(AObj.Values['w']) then
    C.BoxW := JsonInt(AObj, 'w', 0);
  if Assigned(AObj.Values['height']) then
    C.BoxH := JsonInt(AObj, 'height', 0)
  else if Assigned(AObj.Values['h']) then
    C.BoxH := JsonInt(AObj, 'h', 0);
end;

procedure AppendParsed(AList: TList<TDialogControl>; const ACtrl: TDialogControl;
  const AObj: TJSONObject);
var
  C: TDialogControl;
begin
  C := ACtrl;
  ApplyLayoutFromJson(C, AObj);
  AList.Add(C);
end;

type
  TControlParser = procedure(const AObj: TJSONObject; AList: TList<TDialogControl>);

  TNamedControlParser = record
    Typ: string;
    Parse: TControlParser;
  end;

procedure ParseControlObject(const AObj: TJSONObject; AList: TList<TDialogControl>); forward;

procedure CopyJsonStrings(const AArr: TJSONArray; out AItems: TArray<string>);
var
  I: Integer;
begin
  // A non-string element becomes '' so later items keep their indexes.
  if not Assigned(AArr) then
  begin
    SetLength(AItems, 0);
    Exit;
  end;
  SetLength(AItems, AArr.Count);
  for I := 0 to AArr.Count - 1 do
    if AArr.Items[I] is TJSONString then
      AItems[I] := TJSONString(AArr.Items[I]).Value
    else
      AItems[I] := '';
end;

procedure RadioGroupFromChildren(const AObj: TJSONObject;
  out AItems, AItemIds: TArray<string>; var ASel: Integer);
var
  Kids: TJSONArray;
  I, N: Integer;
  Child: TJSONValue;
  ChildObj: TJSONObject;
begin
  SetLength(AItems, 0);
  SetLength(AItemIds, 0);
  Kids := AObj.Values['children'] as TJSONArray;
  if not Assigned(Kids) then
    Exit;
  // selected starts at -1 so the first checked radio can fill it in.
  // An authored selected (>= 0) stays. No checked radio leaves 0.
  N := 0;
  SetLength(AItems, Kids.Count);
  SetLength(AItemIds, Kids.Count);
  ASel := JsonInt(AObj, 'selected', -1);
  for I := 0 to Kids.Count - 1 do
  begin
    Child := Kids.Items[I];
    if not (Child is TJSONObject) then
      Continue;
    ChildObj := TJSONObject(Child);
    if not SameText(JsonStr(ChildObj, 'type'), 'radio') and
       not SameText(JsonStr(ChildObj, 'type'), 'radiobox') then
      Continue;
    AItems[N] := JsonStr(ChildObj, 'text');
    AItemIds[N] := JsonStr(ChildObj, 'id');
    if JsonBool(ChildObj, 'checked', False) and (ASel < 0) then
      ASel := N;
    Inc(N);
  end;
  SetLength(AItems, N);
  SetLength(AItemIds, N);
  if ASel < 0 then
    ASel := 0;
end;

procedure ParseLabel(const AObj: TJSONObject; AList: TList<TDialogControl>);
var
  C: TDialogControl;
begin
  C := MakeLabel(JsonStr(AObj, 'text'), JsonStr(AObj, 'id'));
  C.Accent := JsonBool(AObj, 'accent', False);
  C.Marked := JsonBool(AObj, 'marked', False);
  AppendParsed(AList, C, AObj);
end;

procedure ParseInput(const AObj: TJSONObject; AList: TList<TDialogControl>);
var
  C: TDialogControl;
begin
  C := MakeInput(JsonStr(AObj, 'id'), JsonStr(AObj, 'value'));
  C.Password := JsonBool(AObj, 'password', False);
  C.ReadOnly := JsonBool(AObj, 'readonly', False);
  if not C.Password then
    C.History := JsonStr(AObj, 'history');
  C.ColorPick := JsonBool(AObj, 'colorpick', False);
  C.DatePick := JsonBool(AObj, 'datepick', False);
  AppendParsed(AList, C, AObj);
end;

procedure ParseCheckbox(const AObj: TJSONObject; AList: TList<TDialogControl>);
begin
  AppendParsed(AList,
    MakeCheckbox(JsonStr(AObj, 'id'), JsonStr(AObj, 'text'),
      JsonBool(AObj, 'checked', False)), AObj);
end;

procedure ParseRadio(const AObj: TJSONObject; AList: TList<TDialogControl>);
var
  Id, Group: string;
begin
  Id := JsonStr(AObj, 'id');
  Group := JsonStr(AObj, 'group');
  if Group = '' then
    Group := Id;
  AppendParsed(AList,
    MakeRadio(Id, Group, JsonStr(AObj, 'text'), JsonBool(AObj, 'checked', False)), AObj);
end;

procedure ParseButton(const AObj: TJSONObject; AList: TList<TDialogControl>);
begin
  AppendParsed(AList,
    MakeButton(JsonStr(AObj, 'id'), JsonStr(AObj, 'text'),
      JsonBool(AObj, 'default', False), JsonBool(AObj, 'cancel', False)), AObj);
end;

procedure ParseStatus(const AObj: TJSONObject; AList: TList<TDialogControl>);
begin
  AppendParsed(AList, MakeStatus(JsonStr(AObj, 'id'), JsonStr(AObj, 'text')), AObj);
end;

procedure ParseSeparator(const AObj: TJSONObject; AList: TList<TDialogControl>);
begin
  // A full-width rule: TDialogHost joins it to the frame (╟───╢).
  AppendParsed(AList, MakeHRule(JsonInt(AObj, 'width', 1)), AObj);
end;

procedure ParseColorSample(const AObj: TJSONObject; AList: TList<TDialogControl>);
var
  C: TDialogControl;
begin
  C := MakeColorSample(JsonStr(AObj, 'id'), JsonStr(AObj, 'text'),
    JsonStr(AObj, 'fgFrom'), JsonStr(AObj, 'bgFrom'),
    ColorSamplePanelStateFromStr(JsonStr(AObj, 'panelState')));
  C.StyleSourceId := JsonStr(AObj, 'styleFrom');
  C.BaseStyle := JsonStr(AObj, 'baseStyle');
  C.FgFallbackId := JsonStr(AObj, 'fgFallback');
  C.BgFallbackId := JsonStr(AObj, 'bgFallback');
  AppendParsed(AList, C, AObj);
end;

procedure ParseColorPicker(const AObj: TJSONObject; AList: TList<TDialogControl>);
begin
  AppendParsed(AList, MakeColorPicker(JsonStr(AObj, 'id')), AObj);
end;

procedure ParseDatePicker(const AObj: TJSONObject; AList: TList<TDialogControl>);
begin
  AppendParsed(AList, MakeDatePicker(JsonStr(AObj, 'id')), AObj);
end;

procedure ParseList(const AObj: TJSONObject; AList: TList<TDialogControl>);
var
  Items: TArray<string>;
  C: TDialogControl;
begin
  CopyJsonStrings(AObj.Values['items'] as TJSONArray, Items);
  C := MakeList(JsonStr(AObj, 'id'), Items, JsonInt(AObj, 'selected', 0));
  C.Framed := JsonBool(AObj, 'frame', False);
  C.Plain := JsonBool(AObj, 'plain', False);
  C.KeyCommands := JsonBool(AObj, 'keycommands', False);
  AppendParsed(AList, C, AObj);
end;

procedure ParseDropDown(const AObj: TJSONObject; AList: TList<TDialogControl>);
var
  Items: TArray<string>;
begin
  CopyJsonStrings(AObj.Values['items'] as TJSONArray, Items);
  AppendParsed(AList,
    MakeDropDown(JsonStr(AObj, 'id'), Items, JsonInt(AObj, 'selected', 0)), AObj);
end;

procedure ParseRadioGroup(const AObj: TJSONObject; AList: TList<TDialogControl>);
var
  Items, ItemIds: TArray<string>;
  Sel: Integer;
  ItemsArr, IdsArr: TJSONArray;
begin
  Sel := JsonInt(AObj, 'selected', 0);
  ItemsArr := AObj.Values['items'] as TJSONArray;
  if Assigned(ItemsArr) then
  begin
    CopyJsonStrings(ItemsArr, Items);
    IdsArr := AObj.Values['item_ids'] as TJSONArray;
    if not Assigned(IdsArr) then
      IdsArr := AObj.Values['itemIds'] as TJSONArray;
    CopyJsonStrings(IdsArr, ItemIds);
  end
  else
    RadioGroupFromChildren(AObj, Items, ItemIds, Sel);
  AppendParsed(AList,
    MakeRadioGroup(JsonStr(AObj, 'id'), JsonStr(AObj, 'text'), Items, Sel, ItemIds), AObj);
end;

procedure ParseChildControls(const AObj: TJSONObject; AList: TList<TDialogControl>);
var
  Kids: TJSONArray;
  I: Integer;
  Child: TJSONValue;
begin
  Kids := AObj.Values['children'] as TJSONArray;
  if not Assigned(Kids) then
    Exit;
  for I := 0 to Kids.Count - 1 do
  begin
    Child := Kids.Items[I];
    if Child is TJSONObject then
      ParseControlObject(TJSONObject(Child), AList);
  end;
end;

// One parser per JSON control type, so ParseControlObject stays a lookup.
// button_row and dialog append nothing of their own: they walk children.
const
  cControlParsers: array[0..19] of TNamedControlParser = (
    (Typ: 'label'; Parse: ParseLabel),
    (Typ: 'input'; Parse: ParseInput),
    (Typ: 'checkbox'; Parse: ParseCheckbox),
    (Typ: 'radio'; Parse: ParseRadio),
    (Typ: 'radiobox'; Parse: ParseRadio),
    (Typ: 'button'; Parse: ParseButton),
    (Typ: 'status'; Parse: ParseStatus),
    (Typ: 'separator'; Parse: ParseSeparator),
    (Typ: 'colorsample'; Parse: ParseColorSample),
    (Typ: 'colorpicker'; Parse: ParseColorPicker),
    (Typ: 'datepicker'; Parse: ParseDatePicker),
    (Typ: 'list'; Parse: ParseList),
    (Typ: 'dropdown'; Parse: ParseDropDown),
    (Typ: 'dropdownlist'; Parse: ParseDropDown),
    (Typ: 'drop_down'; Parse: ParseDropDown),
    (Typ: 'combo'; Parse: ParseDropDown),
    (Typ: 'radio_group'; Parse: ParseRadioGroup),
    (Typ: 'radiogroup'; Parse: ParseRadioGroup),
    (Typ: 'button_row'; Parse: ParseChildControls),
    (Typ: 'dialog'; Parse: ParseChildControls)
  );

procedure ParseControlObject(const AObj: TJSONObject; AList: TList<TDialogControl>);
var
  Typ: string;
  I: Integer;
begin
  if not Assigned(AObj) then
    Exit;
  Typ := LowerCase(JsonStr(AObj, 'type'));
  for I := Low(cControlParsers) to High(cControlParsers) do
    if cControlParsers[I].Typ = Typ then
    begin
      cControlParsers[I].Parse(AObj, AList);
      Exit;
    end;
end;

function TryParseDialogJson(const AJson: string; out ADecl: TDialogDeclaration): Boolean;
var
  Root: TJSONValue;
  Obj: TJSONObject;
  Kids: TJSONArray;
  List: TList<TDialogControl>;
  I: Integer;
  Child: TJSONValue;
begin
  Result := False;
  ADecl.Version := cDialogProtocolV1;
  ADecl.Title := '';
  ADecl.Width := 48;
  ADecl.Height := 8;
  ADecl.IsWarning := False;
  ADecl.NoAutoLayout := False;
  SetLength(ADecl.Controls, 0);
  if Trim(AJson) = '' then
    Exit;

  Root := TJSONObject.ParseJSONValue(AJson);
  if not Assigned(Root) then
    Exit;
  try
    if not (Root is TJSONObject) then
      Exit;
    Obj := TJSONObject(Root);
    ADecl.Version := JsonStr(Obj, 'version', cDialogProtocolV1);
    if Trim(ADecl.Version) = '' then
      ADecl.Version := cDialogProtocolV1;
    ADecl.Title := JsonStr(Obj, 'title', 'Dialog');
    ADecl.Width := JsonInt(Obj, 'width', 48);
    ADecl.Height := JsonInt(Obj, 'height', 8);
    ADecl.IsWarning := SameText(JsonStr(Obj, 'style', ''), 'warning') or
      SameText(JsonStr(Obj, 'style', ''), 'error');
    if Assigned(Obj.Values['autoLayout']) then
      ADecl.NoAutoLayout := Obj.Values['autoLayout'] is TJSONFalse;
    if ADecl.Width < 28 then
      ADecl.Width := 28;
    if ADecl.Height < 6 then
      ADecl.Height := 6;

    List := TList<TDialogControl>.Create;
    try
      Kids := Obj.Values['children'] as TJSONArray;
      if Assigned(Kids) then
        for I := 0 to Kids.Count - 1 do
        begin
          Child := Kids.Items[I];
          if Child is TJSONObject then
            ParseControlObject(TJSONObject(Child), List);
        end
      else
        // Flat controls array fallback: { "controls": [ ... ] }
        begin
          Kids := Obj.Values['controls'] as TJSONArray;
          if Assigned(Kids) then
            for I := 0 to Kids.Count - 1 do
            begin
              Child := Kids.Items[I];
              if Child is TJSONObject then
                ParseControlObject(TJSONObject(Child), List);
            end;
        end;

      if List.Count = 0 then
        Exit;
      ADecl.Controls := List.ToArray;
      Result := True;
    finally
      List.Free;
    end;
  finally
    Root.Free;
  end;
end;

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
        end;
      dckInput:
        begin
          One := Format('{"type":"input","id":"%s","value":"%s"',
            [EscapeJson(C.Id), EscapeJson(C.Edit.Text)]);
          if C.Password then
            One := One + ',"password":true';
          if C.ReadOnly then
            One := One + ',"readonly":true';
          if C.History <> '' then
            One := One + Format(',"history":"%s"', [EscapeJson(C.History)]);
          if C.ColorPick then
            One := One + ',"colorpick":true';
          if C.DatePick then
            One := One + ',"datepick":true';
        end;
      dckCheckbox:
        if C.Checked then
          One := Format('{"type":"checkbox","id":"%s","text":"%s","checked":true',
            [EscapeJson(C.Id), EscapeJson(C.Text)])
        else
          One := Format('{"type":"checkbox","id":"%s","text":"%s","checked":false',
            [EscapeJson(C.Id), EscapeJson(C.Text)]);
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
