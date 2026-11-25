unit uDialogJsonParse;

{ JSON control object -> TDialogControl list. Used by TryParseDialogJson. }

interface

uses
  System.SysUtils, System.JSON, System.Generics.Collections,
  uDialogTypes;

function JsonBool(const AObj: TJSONObject; const AName: string;
  ADefault: Boolean = False): Boolean;
function JsonInt(const AObj: TJSONObject; const AName: string;
  ADefault: Integer): Integer;
function JsonStr(const AObj: TJSONObject; const AName: string;
  const ADefault: string = ''): string;

procedure ParseControlObject(const AObj: TJSONObject; AList: TList<TDialogControl>);

implementation

uses
  System.StrUtils, System.Math;

function JsonBool(const AObj: TJSONObject; const AName: string;
  ADefault: Boolean): Boolean;
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
  const ADefault: string): string;
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
  if Assigned(AObj.Values['tab']) then
    C.TabPage := Max(JsonInt(AObj, 'tab', -1), -1) + 1;
end;

procedure AppendParsed(AList: TList<TDialogControl>; const ACtrl: TDialogControl;
  const AObj: TJSONObject);
var
  C: TDialogControl;
begin
  C := ACtrl;
  C.Hint := JsonStr(AObj, 'hint');
  ApplyLayoutFromJson(C, AObj);
  AList.Add(C);
end;

type
  TControlParser = procedure(const AObj: TJSONObject; AList: TList<TDialogControl>);

  TNamedControlParser = record
    Typ: string;
    Parse: TControlParser;
  end;


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
  C.HintArea := JsonBool(AObj, 'hint_area', False);
  C.GroupFrame := JsonBool(AObj, 'group', False);
  AppendParsed(AList, C, AObj);
end;

procedure ParseInput(const AObj: TJSONObject; AList: TList<TDialogControl>);
var
  C: TDialogControl;
begin
  C := MakeInput(JsonStr(AObj, 'id'), JsonStr(AObj, 'value'));
  C.Password := JsonBool(AObj, 'password', False);
  C.ReadOnly := JsonBool(AObj, 'readonly', False);
  C.HotKey := JsonBool(AObj, 'hotkey', False) and not C.Password;
  C.HotKeyMulti := C.HotKey and JsonBool(AObj, 'multi', False);
  if not C.Password and not C.HotKey then
    C.History := JsonStr(AObj, 'history');
  C.ColorPick := JsonBool(AObj, 'colorpick', False);
  C.DatePick := JsonBool(AObj, 'datepick', False);
  AppendParsed(AList, C, AObj);
end;

procedure ParseCheckbox(const AObj: TJSONObject; AList: TList<TDialogControl>);
var
  C: TDialogControl;
begin
  C := MakeCheckbox(JsonStr(AObj, 'id'), JsonStr(AObj, 'text'),
    JsonBool(AObj, 'checked', False));
  C.Tristate := JsonBool(AObj, 'tristate', False);
  C.Unknown := C.Tristate and JsonBool(AObj, 'unknown', False);
  AppendParsed(AList, C, AObj);
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

procedure ParseTabs(const AObj: TJSONObject; AList: TList<TDialogControl>);
var
  Items: TArray<string>;
  Strip: TDialogControl;
begin
  CopyJsonStrings(AObj.Values['items'] as TJSONArray, Items);
  Strip := MakeTabs(JsonStr(AObj, 'id'), Items, JsonInt(AObj, 'selected', 0));
  Strip.Vertical := JsonBool(AObj, 'vertical', False);
  AppendParsed(AList, Strip, AObj);
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
  cControlParsers: array[0..21] of TNamedControlParser = (
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
    (Typ: 'tabs'; Parse: ParseTabs),
    (Typ: 'tab_strip'; Parse: ParseTabs),
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

end.