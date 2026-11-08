unit TestYamlLite;

{ The YAML subset reader: structure, scalar typing, quoting, block scalars, errors. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestYamlLite = class
  public
    [Test] procedure TestMappingWithNestedMappingAndScalars;
    [Test] procedure TestSequenceOfScalarsAndMappings;
    [Test] procedure TestSequenceAtTheIndentOfItsKey;
    [Test] procedure TestScalarTypes;
    [Test] procedure TestQuotedScalarsKeepTheirText;
    [Test] procedure TestCommentsAreCutOutsideQuotes;
    [Test] procedure TestFlowCollections;
    [Test] procedure TestLiteralAndFoldedBlocks;
    [Test] procedure TestOnlyTheFirstDocumentIsRead;
    [Test] procedure TestEmptyValueIsNull;
    [Test] procedure TestAnchorsAreRefusedWithTheLine;
    [Test] procedure TestTabIndentIsRefused;
  end;

implementation

uses
  System.SysUtils, System.JSON, uYamlLite;

function Json(const AYaml: string): string;
var
  V: TJSONValue;
begin
  V := ParseYaml(AYaml);
  try
    Result := V.ToJSON;
  finally
    V.Free;
  end;
end;

const
  LF = #10;

procedure TTestYamlLite.TestMappingWithNestedMappingAndScalars;
begin
  Assert.AreEqual('{"a":1,"b":{"c":"x","d":true}}',
    Json('a: 1' + LF + 'b:' + LF + '  c: x' + LF + '  d: true' + LF));
end;

procedure TTestYamlLite.TestSequenceOfScalarsAndMappings;
begin
  Assert.AreEqual('{"l":[1,"two",{"k":"v","n":3},[4,5]]}',
    Json('l:' + LF + '  - 1' + LF + '  - two' + LF + '  - k: v' + LF + '    n: 3' + LF +
      '  -' + LF + '    - 4' + LF + '    - 5' + LF));
end;

procedure TTestYamlLite.TestSequenceAtTheIndentOfItsKey;
begin
  Assert.AreEqual('{"l":["a","b"],"z":1}', Json('l:' + LF + '- a' + LF + '- b' + LF + 'z: 1' + LF));
end;

procedure TTestYamlLite.TestScalarTypes;
begin
  Assert.AreEqual('{"a":null,"b":null,"c":false,"d":12,"e":1.5,"f":"007","g":"yes","h":"1.2.3"}',
    Json('a: ~' + LF + 'b: null' + LF + 'c: False' + LF + 'd: 12' + LF + 'e: 1.5' + LF +
      'f: 007' + LF + 'g: yes' + LF + 'h: 1.2.3' + LF));
end;

procedure TTestYamlLite.TestQuotedScalarsKeepTheirText;
begin
  Assert.AreEqual('{"a":"12","b":"it''s","c":"x: y # z","d":"line\none"}',
    Json('a: "12"' + LF + 'b: ''it''''s''' + LF + 'c: "x: y # z"' + LF + 'd: "line\none"' + LF));
  Assert.AreEqual('{"a b":1,"c:d":2}', Json('"a b": 1' + LF + '''c:d'': 2' + LF));
end;

procedure TTestYamlLite.TestCommentsAreCutOutsideQuotes;
begin
  Assert.AreEqual('{"a":1,"b":"x#y"}',
    Json('# head' + LF + 'a: 1 # tail' + LF + LF + 'b: x#y' + LF));
end;

procedure TTestYamlLite.TestFlowCollections;
begin
  Assert.AreEqual('{"a":[1,"b",[]],"c":{"d":1,"e":"f"},"g":{}}',
    Json('a: [1, b, []]' + LF + 'c: {d: 1, e: "f"}' + LF + 'g: {}' + LF));
end;

procedure TTestYamlLite.TestLiteralAndFoldedBlocks;
begin
  Assert.AreEqual('{"a":"one\ntwo\n","b":"one two\n","c":"keep"}',
    Json('a: |' + LF + '  one' + LF + '  two' + LF + 'b: >' + LF + '  one' + LF + '  two' + LF +
      'c: |-' + LF + '  keep' + LF));
end;

procedure TTestYamlLite.TestOnlyTheFirstDocumentIsRead;
begin
  Assert.AreEqual('{"a":1}', Json('---' + LF + 'a: 1' + LF + '---' + LF + 'b: 2' + LF));
end;

procedure TTestYamlLite.TestEmptyValueIsNull;
begin
  Assert.AreEqual('{"a":null,"b":1}', Json('a:' + LF + 'b: 1' + LF));
  Assert.AreEqual('null', Json(''));
end;

procedure TTestYamlLite.TestAnchorsAreRefusedWithTheLine;
begin
  Assert.WillRaiseWithMessageRegex(
    procedure begin Json('a: 1' + LF + 'b: &x 2' + LF); end, EYamlError, 'Line 2');
end;

procedure TTestYamlLite.TestTabIndentIsRefused;
begin
  Assert.WillRaiseWithMessageRegex(
    procedure begin Json('a:' + LF + #9 + 'b: 1' + LF); end, EYamlError, 'Line 2');
end;

end.
