unit TestServiceSchema;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestServiceSchema = class
  public
    [Test] procedure TestNoSchemaAcceptsAnything;
    [Test] procedure TestRequiredAndTypes;
    [Test] procedure TestIntegerRejectsFractions;
    [Test] procedure TestEnumAndNestedValues;
    [Test] procedure TestArrayItems;
    [Test] procedure TestMissingParamsCountAsEmptyObject;
    [Test] procedure TestUnlistedPropertiesAndUnknownKeywordsAreAllowed;
    [Test] procedure TestBrokenSchemaIsNotTheCallersFault;
    [Test] procedure TestReasonNamesThePath;
  end;

implementation

uses
  uServiceSchema;

const
  cSchema =
    '{"type":"object","required":["root","mask"],"properties":{' +
    '"root":{"type":"string"},"mask":{"type":"string"},"subdirs":{"type":"boolean"},' +
    '"maxResults":{"type":"integer"},"mode":{"type":"string","enum":["a","b"]},' +
    '"names":{"type":"array","items":{"type":"string"}}}}';

function Check(const ASchema, AParams: string): TSchemaCheck;
var
  Why: string;
begin
  Result := CheckServiceParams(ASchema, AParams, Why);
end;

procedure TTestServiceSchema.TestNoSchemaAcceptsAnything;
begin
  Assert.IsTrue(Check('', '{"x":1}') = scValid);
  Assert.IsTrue(Check('', 'not json') = scValid, 'without a schema nothing is checked');
  Assert.IsTrue(Check('', '') = scValid);
end;

procedure TTestServiceSchema.TestRequiredAndTypes;
begin
  Assert.IsTrue(Check(cSchema, '{"root":"C:\\","mask":"*"}') = scValid);
  Assert.IsTrue(Check(cSchema, '{"root":"C:\\"}') = scBadParams, 'mask is required');
  Assert.IsTrue(Check(cSchema, '{"root":1,"mask":"*"}') = scBadParams, 'root must be a string');
  Assert.IsTrue(Check(cSchema, '{"root":"a","mask":"*","subdirs":"yes"}') = scBadParams, 'a boolean');
  Assert.IsTrue(Check(cSchema, '{"root":"a","mask":"*","subdirs":true}') = scValid);
  Assert.IsTrue(Check(cSchema, '[]') = scBadParams, 'the params must be an object');
  Assert.IsTrue(Check(cSchema, 'not json') = scBadParams);
end;

procedure TTestServiceSchema.TestIntegerRejectsFractions;
begin
  Assert.IsTrue(Check(cSchema, '{"root":"a","mask":"*","maxResults":10}') = scValid);
  Assert.IsTrue(Check(cSchema, '{"root":"a","mask":"*","maxResults":10.5}') = scBadParams);
  Assert.IsTrue(Check('{"type":"object","properties":{"n":{"type":"number"}}}', '{"n":10.5}') = scValid,
    'number accepts a fraction');
end;

procedure TTestServiceSchema.TestEnumAndNestedValues;
begin
  Assert.IsTrue(Check(cSchema, '{"root":"a","mask":"*","mode":"a"}') = scValid);
  Assert.IsTrue(Check(cSchema, '{"root":"a","mask":"*","mode":"c"}') = scBadParams);
  Assert.IsTrue(Check('{"type":"object","properties":{"o":{"type":"object","required":["k"]}}}',
    '{"o":{}}') = scBadParams, 'a required field of a nested object');
  Assert.IsTrue(Check('{"type":"object","properties":{"o":{"type":"object","required":["k"]}}}',
    '{"o":{"k":1}}') = scValid);
end;

procedure TTestServiceSchema.TestArrayItems;
begin
  Assert.IsTrue(Check(cSchema, '{"root":"a","mask":"*","names":["x","y"]}') = scValid);
  Assert.IsTrue(Check(cSchema, '{"root":"a","mask":"*","names":["x",2]}') = scBadParams, 'an item of the wrong type');
  Assert.IsTrue(Check(cSchema, '{"root":"a","mask":"*","names":"x"}') = scBadParams, 'not an array');
end;

procedure TTestServiceSchema.TestMissingParamsCountAsEmptyObject;
begin
  Assert.IsTrue(Check(cSchema, '') = scBadParams, 'required fields are missing');
  Assert.IsTrue(Check('{"type":"object","properties":{"a":{"type":"string"}}}', '') = scValid);
end;

procedure TTestServiceSchema.TestUnlistedPropertiesAndUnknownKeywordsAreAllowed;
begin
  Assert.IsTrue(Check(cSchema, '{"root":"a","mask":"*","extra":[1,2]}') = scValid, 'an unlisted property');
  Assert.IsTrue(Check('{"type":"object","additionalProperties":false,"properties":{"a":{"minLength":3}}}',
    '{"a":"x","b":1}') = scValid, 'keywords outside the subset are ignored');
end;

procedure TTestServiceSchema.TestBrokenSchemaIsNotTheCallersFault;
begin
  Assert.IsTrue(Check('not json', '{}') = scBadSchema);
  Assert.IsTrue(Check('[]', '{}') = scBadSchema, 'the schema must be an object');
  Assert.IsTrue(Check('{"type":"blob"}', '{}') = scBadSchema, 'an unknown type');
  Assert.IsTrue(Check('{"type":7}', '{}') = scBadSchema);
  Assert.IsTrue(Check('{"properties":{"a":5}}', '{"a":1}') = scBadSchema, 'a property schema must be an object');
  Assert.IsTrue(Check('{"required":[1]}', '{}') = scBadSchema);
end;

procedure TTestServiceSchema.TestReasonNamesThePath;
var
  Why: string;
begin
  Assert.IsTrue(CheckServiceParams(cSchema, '{"root":"a","mask":"*","names":["x",2]}', Why) = scBadParams);
  Assert.IsTrue(Pos('params.names[1]', Why) > 0, 'the path of the item: ' + Why);
  Assert.IsTrue(CheckServiceParams(cSchema, '{"root":"a"}', Why) = scBadParams);
  Assert.IsTrue(Pos('"mask"', Why) > 0, 'the missing field: ' + Why);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestServiceSchema);

end.
