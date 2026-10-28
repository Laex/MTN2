unit uDialogValues;

{ JSON object of a dialog's current values. Reads each control from the
  caller's array: a copied record can drop the input line. List and drop-down
  selection prefers the host mirror (AListSelId / AListSelIndex) for the same
  reason. }

interface

uses
  System.SysUtils, uDialogTypes;

/// <summary>The selected item id of a radio group, or its visible text when
/// the item has no id. '' when AControl is not a radio group.</summary>
function RadioGroupValueOf(const AControl: TDialogControl): string;

/// <summary>{"id":value, ...} for the controls that have a value. A control
/// with an empty id is left out. A radio group contributes one field, from
/// the first checked button.</summary>
function DialogValuesJson(const AControls: TArray<TDialogControl>;
  const AListSelId: string; AListSelIndex: Integer): string;

implementation

function RadioGroupValueOf(const AControl: TDialogControl): string;
var
  Idx: Integer;
begin
  Result := '';
  if AControl.Kind <> dckRadioGroup then
    Exit;
  Idx := AControl.SelectedIndex;
  if (Idx >= 0) and (Idx <= High(AControl.ItemIds)) and (AControl.ItemIds[Idx] <> '') then
    Exit(AControl.ItemIds[Idx]);
  if (Idx >= 0) and (Idx <= High(AControl.Items)) then
    Result := AControl.Items[Idx];
end;

function JsonStringField(const AId, AValue: string): string;
begin
  Result := Format('"%s":"%s"', [AId,
    StringReplace(AValue, '"', '\"', [rfReplaceAll])]);
end;

function ChoiceIndex(const AControls: TArray<TDialogControl>; AIndex: Integer;
  const AListSelId: string; AListSelIndex: Integer): Integer;
begin
  if (AListSelId <> '') and SameText(AListSelId, AControls[AIndex].Id) then
    Exit(AListSelIndex);
  Result := AControls[AIndex].SelectedIndex;
end;

function InputValueJson(const AControls: TArray<TDialogControl>;
  AIndex: Integer): string;
begin
  Result := '';
  if AControls[AIndex].Id = '' then
    Exit;
  Result := JsonStringField(AControls[AIndex].Id, AControls[AIndex].Edit.Text);
end;

function CheckboxValueJson(const AControls: TArray<TDialogControl>;
  AIndex: Integer): string;
begin
  Result := '';
  if AControls[AIndex].Id = '' then
    Exit;
  if AControls[AIndex].Checked then
    Result := Format('"%s":true', [AControls[AIndex].Id])
  else
    Result := Format('"%s":false', [AControls[AIndex].Id]);
end;

function ListChoiceValueJson(const AControls: TArray<TDialogControl>;
  AIndex: Integer; const AListSelId: string; AListSelIndex: Integer): string;
var
  Idx: Integer;
  Name: string;
begin
  Result := '';
  if AControls[AIndex].Id = '' then
    Exit;
  Idx := ChoiceIndex(AControls, AIndex, AListSelId, AListSelIndex);
  Name := '';
  // A translated fixed choice reports its English ItemId.
  if (Idx >= 0) and (Idx <= High(AControls[AIndex].ItemIds)) and
     (AControls[AIndex].ItemIds[Idx] <> '') then
    Name := AControls[AIndex].ItemIds[Idx]
  else if (Idx >= 0) and (Idx <= High(AControls[AIndex].Items)) then
    Name := AControls[AIndex].Items[Idx];
  Result := JsonStringField(AControls[AIndex].Id, Name);
end;

function RadioGroupValueJson(const AControls: TArray<TDialogControl>;
  AIndex: Integer): string;
begin
  Result := '';
  if AControls[AIndex].Id = '' then
    Exit;
  Result := JsonStringField(AControls[AIndex].Id,
    RadioGroupValueOf(AControls[AIndex]));
end;

function RadioButtonValueJson(const AControls: TArray<TDialogControl>;
  AIndex: Integer; var AEmitted: TArray<string>): string;
var
  K: Integer;
  G, Name: string;
begin
  Result := '';
  G := AControls[AIndex].Group;
  if (G = '') or not AControls[AIndex].Checked then
    Exit;
  for K := 0 to High(AEmitted) do
    if SameText(AEmitted[K], G) then
      Exit;
  SetLength(AEmitted, Length(AEmitted) + 1);
  AEmitted[High(AEmitted)] := G;
  if AControls[AIndex].Id <> '' then
    Name := AControls[AIndex].Id
  else
    Name := AControls[AIndex].Text;
  Result := JsonStringField(G, Name);
end;

function DialogValuesJson(const AControls: TArray<TDialogControl>;
  const AListSelId: string; AListSelIndex: Integer): string;
var
  I: Integer;
  Parts: TArray<string>;
  Emitted: TArray<string>;
  Part: string;
begin
  SetLength(Parts, 0);
  SetLength(Emitted, 0);
  for I := 0 to High(AControls) do
  begin
    case AControls[I].Kind of
      dckInput:
        Part := InputValueJson(AControls, I);
      dckCheckbox:
        Part := CheckboxValueJson(AControls, I);
      dckList, dckDropDown:
        Part := ListChoiceValueJson(AControls, I, AListSelId, AListSelIndex);
      dckRadioGroup:
        Part := RadioGroupValueJson(AControls, I);
      dckRadio:
        Part := RadioButtonValueJson(AControls, I, Emitted);
    else
      Part := '';
    end;
    if Part <> '' then
    begin
      SetLength(Parts, Length(Parts) + 1);
      Parts[High(Parts)] := Part;
    end;
  end;
  Result := '{' + string.Join(',', Parts) + '}';
end;

end.
