unit uDialogJson;

{ DIALOG_PLUGIN JSON subset ↔ TDialogDeclaration (in-process seam for cdecl). }

interface

uses
  System.SysUtils,
  uDialogTypes;

function TryParseDialogJson(const AJson: string; out ADecl: TDialogDeclaration): Boolean;
function DeclarationToJson(const ADecl: TDialogDeclaration): string;

implementation

uses
  System.JSON, System.Generics.Collections;

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

procedure ParseControlObject(const AObj: TJSONObject; AList: TList<TDialogControl>);
var
  Typ, Id, Text, Value, Group: string;
  Kids, ItemsArr: TJSONArray;
  Items, ItemIds: TArray<string>;
  I, Sel, N: Integer;
  Child: TJSONValue;
  ChildObj: TJSONObject;
  C: TDialogControl;
begin
  if not Assigned(AObj) then
    Exit;
  Typ := LowerCase(JsonStr(AObj, 'type'));
  Id := JsonStr(AObj, 'id');
  Text := JsonStr(AObj, 'text');
  Value := JsonStr(AObj, 'value');
  Group := JsonStr(AObj, 'group');

  if Typ = 'label' then
  begin
    AppendParsed(AList, MakeLabel(Text, Id), AObj)
  end
  else if Typ = 'input' then
  begin
    C := MakeInput(Id, Value);
    C.Password := JsonBool(AObj, 'password', False);
    if not C.Password then
      C.History := JsonStr(AObj, 'history');
    AppendParsed(AList, C, AObj);
  end
  else if Typ = 'checkbox' then
    AppendParsed(AList, MakeCheckbox(Id, Text, JsonBool(AObj, 'checked', False)), AObj)
  else if (Typ = 'radio') or (Typ = 'radiobox') then
  begin
    if Group = '' then
      Group := Id;
    AppendParsed(AList,
      MakeRadio(Id, Group, Text, JsonBool(AObj, 'checked', False)), AObj)
  end
  else if Typ = 'button' then
    AppendParsed(AList,
      MakeButton(Id, Text, JsonBool(AObj, 'default', False),
        JsonBool(AObj, 'cancel', False)), AObj)
  else if Typ = 'status' then
    AppendParsed(AList, MakeStatus(Id, Text), AObj)
  else if Typ = 'colorsample' then
    AppendParsed(AList,
      MakeColorSample(Id, Text, JsonStr(AObj, 'fgFrom'), JsonStr(AObj, 'bgFrom'),
        ColorSamplePanelStateFromStr(JsonStr(AObj, 'panelState'))), AObj)
  else if Typ = 'list' then
  begin
    SetLength(Items, 0);
    ItemsArr := AObj.Values['items'] as TJSONArray;
    if Assigned(ItemsArr) then
    begin
      SetLength(Items, ItemsArr.Count);
      for I := 0 to ItemsArr.Count - 1 do
        if ItemsArr.Items[I] is TJSONString then
          Items[I] := TJSONString(ItemsArr.Items[I]).Value
        else
          Items[I] := '';
    end;
    Sel := JsonInt(AObj, 'selected', 0);
    AppendParsed(AList, MakeList(Id, Items, Sel), AObj);
  end
  else if (Typ = 'dropdown') or (Typ = 'dropdownlist') or (Typ = 'drop_down') or
    (Typ = 'combo') then
  begin
    SetLength(Items, 0);
    ItemsArr := AObj.Values['items'] as TJSONArray;
    if Assigned(ItemsArr) then
    begin
      SetLength(Items, ItemsArr.Count);
      for I := 0 to ItemsArr.Count - 1 do
        if ItemsArr.Items[I] is TJSONString then
          Items[I] := TJSONString(ItemsArr.Items[I]).Value
        else
          Items[I] := '';
    end;
    Sel := JsonInt(AObj, 'selected', 0);
    AppendParsed(AList, MakeDropDown(Id, Items, Sel), AObj);
  end
  else if (Typ = 'radio_group') or (Typ = 'radiogroup') then
  begin
    SetLength(Items, 0);
    SetLength(ItemIds, 0);
    Sel := JsonInt(AObj, 'selected', 0);
    ItemsArr := AObj.Values['items'] as TJSONArray;
    if Assigned(ItemsArr) then
    begin
      SetLength(Items, ItemsArr.Count);
      for I := 0 to ItemsArr.Count - 1 do
        if ItemsArr.Items[I] is TJSONString then
          Items[I] := TJSONString(ItemsArr.Items[I]).Value
        else
          Items[I] := '';
      ItemsArr := AObj.Values['item_ids'] as TJSONArray;
      if not Assigned(ItemsArr) then
        ItemsArr := AObj.Values['itemIds'] as TJSONArray;
      if Assigned(ItemsArr) then
      begin
        SetLength(ItemIds, ItemsArr.Count);
        for I := 0 to ItemsArr.Count - 1 do
          if ItemsArr.Items[I] is TJSONString then
            ItemIds[I] := TJSONString(ItemsArr.Items[I]).Value
          else
            ItemIds[I] := '';
      end;
    end
    else
    begin
      Kids := AObj.Values['children'] as TJSONArray;
      if Assigned(Kids) then
      begin
        N := 0;
        SetLength(Items, Kids.Count);
        SetLength(ItemIds, Kids.Count);
        Sel := JsonInt(AObj, 'selected', -1);
        for I := 0 to Kids.Count - 1 do
        begin
          Child := Kids.Items[I];
          if not (Child is TJSONObject) then
            Continue;
          ChildObj := TJSONObject(Child);
          if not SameText(JsonStr(ChildObj, 'type'), 'radio') and
             not SameText(JsonStr(ChildObj, 'type'), 'radiobox') then
            Continue;
          Items[N] := JsonStr(ChildObj, 'text');
          ItemIds[N] := JsonStr(ChildObj, 'id');
          if JsonBool(ChildObj, 'checked', False) and (Sel < 0) then
            Sel := N;
          Inc(N);
        end;
        SetLength(Items, N);
        SetLength(ItemIds, N);
        if Sel < 0 then
          Sel := 0;
      end;
    end;
    AppendParsed(AList, MakeRadioGroup(Id, Text, Items, Sel, ItemIds), AObj);
  end
  else if (Typ = 'button_row') or (Typ = 'dialog') then
  begin
    Kids := AObj.Values['children'] as TJSONArray;
    if Assigned(Kids) then
      for I := 0 to Kids.Count - 1 do
      begin
        Child := Kids.Items[I];
        if Child is TJSONObject then
          ParseControlObject(TJSONObject(Child), AList);
      end;
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
        begin
          One := Format('{"type":"label","text":"%s"', [EscapeJson(C.Text)]);
          if C.Id <> '' then
            One := One + Format(',"id":"%s"', [EscapeJson(C.Id)]);
        end;
      dckInput:
        begin
          One := Format('{"type":"input","id":"%s","value":"%s"',
            [EscapeJson(C.Id), EscapeJson(C.Edit.Text)]);
          if C.Password then
            One := One + ',"password":true';
          if C.History <> '' then
            One := One + Format(',"history":"%s"', [EscapeJson(C.History)]);
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
      dckColorSample:
        begin
          One := Format('{"type":"colorsample","id":"%s","text":"%s"',
            [EscapeJson(C.Id), EscapeJson(C.Text)]);
          if C.FgSourceId <> '' then
            One := One + Format(',"fgFrom":"%s"', [EscapeJson(C.FgSourceId)]);
          if C.BgSourceId <> '' then
            One := One + Format(',"bgFrom":"%s"', [EscapeJson(C.BgSourceId)]);
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
    '{"type":"dialog","version":"%s","title":"%s","width":%d,"height":%d,"children":[%s]}',
    [EscapeJson(Ver), EscapeJson(ADecl.Title), ADecl.Width, ADecl.Height,
     string.Join(',', Parts)]);
end;

end.
