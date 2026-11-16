unit uServiceSchema;

{ The small JSON Schema subset that service descriptions use for their
  parameters (docs/PLUGIN_SERVICES.md, service.describe): "type" (object,
  string, integer, number, boolean, array), "properties", "required", "enum"
  and "items". A property the schema does not list is allowed. A keyword
  outside the subset is ignored, so a richer schema from an external
  process still checks what it can.

  A missing params value counts as an empty object. A schema that is not an
  object, or has a "type" outside the subset, is a fault of the provider and
  is reported as such, not as a fault of the parameters. }

interface

type
  TSchemaCheck = (scValid, scBadParams, scBadSchema);

/// <summary>Checks AParamsJson ('' = absent) against ASchemaJson ('' = no
/// schema, everything is valid). AWhy names the first problem.</summary>
function CheckServiceParams(const ASchemaJson, AParamsJson: string;
  out AWhy: string): TSchemaCheck;

implementation

uses
  System.SysUtils, System.JSON;

function TypeMatches(const AType: string; AValue: TJSONValue; out AKnown: Boolean): Boolean;
var
  Int: Int64;
begin
  AKnown := True;
  if AType = 'object' then
    Result := AValue is TJSONObject
  else if AType = 'array' then
    Result := AValue is TJSONArray
  else if AType = 'string' then
    Result := AValue is TJSONString
  else if AType = 'boolean' then
    Result := AValue is TJSONBool
  else if AType = 'number' then
    Result := AValue is TJSONNumber
  else if AType = 'integer' then
    Result := (AValue is TJSONNumber) and TryStrToInt64(TJSONNumber(AValue).Value, Int)
  else
  begin
    AKnown := False;
    Result := False;
  end;
end;

function InEnum(AEnum: TJSONArray; AValue: TJSONValue): Boolean;
var
  I: Integer;
begin
  for I := 0 to AEnum.Count - 1 do
    if AEnum.Items[I].ToJSON = AValue.ToJSON then
      Exit(True);
  Result := False;
end;

function CheckValue(ASchema: TJSONObject; AValue: TJSONValue; const APath: string;
  out AWhy: string): TSchemaCheck;
var
  TypeValue, Props, Req, Enum, Items: TJSONValue;
  Known: Boolean;
  I: Integer;
  Name: string;
  Child: TJSONValue;
  Pair: TJSONPair;
begin
  Result := scValid;
  AWhy := '';
  TypeValue := ASchema.GetValue('type');
  if TypeValue <> nil then
  begin
    if not (TypeValue is TJSONString) then
    begin
      AWhy := APath + ': "type" is not a string';
      Exit(scBadSchema);
    end;
    if not TypeMatches(TJSONString(TypeValue).Value, AValue, Known) then
    begin
      if not Known then
      begin
        AWhy := APath + ': unknown type "' + TJSONString(TypeValue).Value + '"';
        Exit(scBadSchema);
      end;
      AWhy := APath + ': expected ' + TJSONString(TypeValue).Value;
      Exit(scBadParams);
    end;
  end;
  Enum := ASchema.GetValue('enum');
  if Enum is TJSONArray then
    if not InEnum(TJSONArray(Enum), AValue) then
    begin
      AWhy := APath + ': not one of the allowed values';
      Exit(scBadParams);
    end;

  if AValue is TJSONObject then
  begin
    Req := ASchema.GetValue('required');
    if Req is TJSONArray then
      for I := 0 to TJSONArray(Req).Count - 1 do
      begin
        if not (TJSONArray(Req).Items[I] is TJSONString) then
        begin
          AWhy := APath + ': "required" holds a non-string';
          Exit(scBadSchema);
        end;
        Name := TJSONString(TJSONArray(Req).Items[I]).Value;
        if TJSONObject(AValue).GetValue(Name) = nil then
        begin
          AWhy := APath + ': "' + Name + '" is required';
          Exit(scBadParams);
        end;
      end;
    Props := ASchema.GetValue('properties');
    if Props is TJSONObject then
      for Pair in TJSONObject(Props) do
      begin
        Child := TJSONObject(AValue).GetValue(Pair.JsonString.Value);
        if Child = nil then
          Continue;
        if not (Pair.JsonValue is TJSONObject) then
        begin
          AWhy := APath + ': the schema of "' + Pair.JsonString.Value + '" is not an object';
          Exit(scBadSchema);
        end;
        Result := CheckValue(TJSONObject(Pair.JsonValue), Child,
          APath + '.' + Pair.JsonString.Value, AWhy);
        if Result <> scValid then
          Exit;
      end;
  end
  else if AValue is TJSONArray then
  begin
    Items := ASchema.GetValue('items');
    if Items is TJSONObject then
      for I := 0 to TJSONArray(AValue).Count - 1 do
      begin
        Result := CheckValue(TJSONObject(Items), TJSONArray(AValue).Items[I],
          APath + '[' + IntToStr(I) + ']', AWhy);
        if Result <> scValid then
          Exit;
      end;
  end;
end;

function CheckServiceParams(const ASchemaJson, AParamsJson: string;
  out AWhy: string): TSchemaCheck;
var
  Schema, Params: TJSONValue;
begin
  AWhy := '';
  if ASchemaJson = '' then
    Exit(scValid);
  Schema := nil;
  Params := nil;
  try
    try
      Schema := TJSONObject.ParseJSONValue(ASchemaJson, True, False);
    except
      Schema := nil;
    end;
    if not (Schema is TJSONObject) then
    begin
      AWhy := 'the schema is not a JSON object';
      Exit(scBadSchema);
    end;
    if AParamsJson = '' then
      Params := TJSONObject.Create
    else
    begin
      try
        Params := TJSONObject.ParseJSONValue(AParamsJson, True, False);
      except
        Params := nil;
      end;
      if Params = nil then
      begin
        AWhy := 'params: not JSON';
        Exit(scBadParams);
      end;
    end;
    Result := CheckValue(TJSONObject(Schema), Params, 'params', AWhy);
  finally
    Params.Free;
    Schema.Free;
  end;
end;

end.
