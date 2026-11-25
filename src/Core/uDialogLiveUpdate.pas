unit uDialogLiveUpdate;

{ JSON a live plugin dialog returns when a field changes. The window applies
  the labels and lists; a payload that is not an object is not an update, so
  the dialog is left as it is. A list entry without an items array is skipped:
  applying it would replace the list with nothing. }

interface

uses
  uDialogTypes;

type
  TDialogLiveLabel = record
    Id: string;
    Text: string;
  end;

  TDialogLiveList = record
    Id: string;
    Items: TArray<string>;
    Selected: Integer;
    Accents: TArray<TListAccent>;
  end;

  TDialogLiveUpdate = record
    Labels: TArray<TDialogLiveLabel>;
    Lists: TArray<TDialogLiveList>;
  end;

/// <summary>False when AJson is empty or not a JSON object. Label text is the
/// JSON value's own text, including a number written as digits.</summary>
function TryParseDialogLiveUpdate(const AJson: string;
  out AUpdate: TDialogLiveUpdate): Boolean;

implementation

uses
  System.SysUtils, System.JSON, System.Generics.Collections;

function ParseAccents(const AAccents: TJSONArray): TArray<TListAccent>;
var
  I, N: Integer;
  Triple: TJSONArray;
begin
  N := 0;
  for I := 0 to AAccents.Count - 1 do
    if (AAccents.Items[I] is TJSONArray) and
       (TJSONArray(AAccents.Items[I]).Count = 3) then
      Inc(N);
  SetLength(Result, N);
  N := 0;
  for I := 0 to AAccents.Count - 1 do
    if (AAccents.Items[I] is TJSONArray) and
       (TJSONArray(AAccents.Items[I]).Count = 3) then
    begin
      Triple := TJSONArray(AAccents.Items[I]);
      Result[N].Item := StrToIntDef(Triple.Items[0].Value, 0);
      Result[N].Col := StrToIntDef(Triple.Items[1].Value, 0);
      Result[N].Len := StrToIntDef(Triple.Items[2].Value, 0);
      Inc(N);
    end;
end;

function TryParseDialogLiveUpdate(const AJson: string;
  out AUpdate: TDialogLiveUpdate): Boolean;
var
  Root, ListObj: TJSONValue;
  Labels, Lists: TJSONObject;
  Pair: TJSONPair;
  Items, Accents: TJSONArray;
  LabelList: TList<TDialogLiveLabel>;
  ListList: TList<TDialogLiveList>;
  LiveLabel: TDialogLiveLabel;
  LiveList: TDialogLiveList;
  I: Integer;
begin
  AUpdate := Default(TDialogLiveUpdate);
  Result := False;
  if AJson = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(AJson);
  if Root = nil then
    Exit;
  try
    if not (Root is TJSONObject) then
      Exit;
    LabelList := TList<TDialogLiveLabel>.Create;
    try
      ListList := TList<TDialogLiveList>.Create;
      try
        if TJSONObject(Root).GetValue('labels') is TJSONObject then
        begin
          Labels := TJSONObject(TJSONObject(Root).GetValue('labels'));
          for Pair in Labels do
          begin
            LiveLabel.Id := Pair.JsonString.Value;
            LiveLabel.Text := Pair.JsonValue.Value;
            LabelList.Add(LiveLabel);
          end;
        end;
        if TJSONObject(Root).GetValue('lists') is TJSONObject then
        begin
          Lists := TJSONObject(TJSONObject(Root).GetValue('lists'));
          for Pair in Lists do
          begin
            ListObj := Pair.JsonValue;
            if not (ListObj is TJSONObject) then
              Continue;
            if not TJSONObject(ListObj).TryGetValue<TJSONArray>('items', Items) then
              Continue;
            LiveList := Default(TDialogLiveList);
            LiveList.Id := Pair.JsonString.Value;
            SetLength(LiveList.Items, Items.Count);
            for I := 0 to Items.Count - 1 do
              LiveList.Items[I] := Items.Items[I].Value;
            LiveList.Selected := 0;
            TJSONObject(ListObj).TryGetValue<Integer>('selected', LiveList.Selected);
            if TJSONObject(ListObj).TryGetValue<TJSONArray>('accents', Accents) then
              LiveList.Accents := ParseAccents(Accents);
            ListList.Add(LiveList);
          end;
        end;
        AUpdate.Labels := LabelList.ToArray;
        AUpdate.Lists := ListList.ToArray;
        Result := True;
      finally
        ListList.Free;
      end;
    finally
      LabelList.Free;
    end;
  finally
    Root.Free;
  end;
end;

end.
