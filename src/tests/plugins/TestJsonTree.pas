unit TestJsonTree;

{ The tree of a JSON or YAML file: addresses, listing, values, and the VFS callbacks on top. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestJsonTree = class
  private
    FDir: string;
    function Write(const AName, AText: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestUriRoundTripsKeysWithSlashes;
    [Test] procedure TestForeignSchemeIsRejected;
    [Test] procedure TestObjectListsKeysTypesAndPreviews;
    [Test] procedure TestArrayItemsAreNamedByPaddedIndex;
    [Test] procedure TestYamlFileGivesTheSameTree;
    [Test] procedure TestMissingKeyIsNotFound;
    [Test] procedure TestInvalidJsonIsAnError;
    [Test] procedure TestHugeFileIsRefusedWithAReason;
    [Test] procedure TestChangedFileIsReadAgain;
    [Test] procedure TestTextOfScalarAndSubtree;
    [Test] procedure TestVfsListsAndReadsAValue;
    [Test] procedure TestHostArchiveRootUriListsTheFile;
    [Test] procedure TestVfsRefusesChanges;
    [Test] procedure TestVfsCopyWritesTheValue;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.StrUtils, System.IOUtils, System.JSON, uPluginHostAbi, uVfsTypes, uJsonTree, uJsonTreeVfs;

function TTestJsonTree.Write(const AName, AText: string): string;
begin
  Result := TPath.Combine(FDir, AName);
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

procedure TTestJsonTree.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'mtn2-jtree-' + TGUID.NewGuid.ToString.Substring(1, 8));
  TDirectory.CreateDirectory(FDir);
end;

procedure TTestJsonTree.TearDown;
begin
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

procedure TTestJsonTree.TestUriRoundTripsKeysWithSlashes;
var
  File_: string;
  Path: TArray<string>;
begin
  File_ := TPath.Combine(FDir, 'a b.json');
  Assert.IsTrue(ParseTreeUri(TreeUri(File_, ['x/y', '100%', 'z']), File_, Path));
  Assert.AreEqual(TPath.Combine(FDir, 'a b.json'), File_);
  Assert.AreEqual(3, Integer(Length(Path)));
  Assert.AreEqual('x/y', Path[0]);
  Assert.AreEqual('100%', Path[1]);
  Assert.IsTrue(ParseTreeUri(TreeUri(File_, nil), File_, Path));
  Assert.AreEqual(0, Integer(Length(Path)));
end;

procedure TTestJsonTree.TestForeignSchemeIsRejected;
var
  File_: string;
  Path: TArray<string>;
begin
  Assert.IsFalse(ParseTreeUri('7z:///x!/', File_, Path));
end;

procedure TTestJsonTree.TestObjectListsKeysTypesAndPreviews;
var
  F, Err: string;
  E: TJtEntries;
begin
  F := Write('o.json', '{"name":"x","n":3,"ok":true,"nil":null,"o":{"a":1},"l":[1,2]}');
  Assert.AreEqual(Ord(jrOk), Ord(TreeList(F, nil, E, Err)), Err);
  Assert.AreEqual(6, Integer(Length(E)));
  Assert.AreEqual('name', E[0].Name);
  Assert.AreEqual('string', E[0].Kind);
  Assert.AreEqual('x', E[0].Preview);
  Assert.AreEqual('number', E[1].Kind);
  Assert.AreEqual('boolean', E[2].Kind);
  Assert.AreEqual('null', E[3].Kind);
  Assert.IsTrue(E[4].IsDir);
  Assert.AreEqual('{1}', E[4].Preview);
  Assert.AreEqual('[2]', E[5].Preview);
end;

procedure TTestJsonTree.TestArrayItemsAreNamedByPaddedIndex;
var
  F, Err, Body: string;
  E: TJtEntries;
  I: Integer;
begin
  Body := '[';
  for I := 0 to 11 do
    Body := Body + IfThen(I > 0, ',', '') + IntToStr(I);
  F := Write('a.json', Body + ']');
  Assert.AreEqual(Ord(jrOk), Ord(TreeList(F, nil, E, Err)), Err);
  Assert.AreEqual(12, Integer(Length(E)));
  Assert.AreEqual('00', E[0].Name);
  Assert.AreEqual('11', E[11].Name);
end;

procedure TTestJsonTree.TestYamlFileGivesTheSameTree;
var
  F, Err: string;
  E: TJtEntries;
begin
  F := Write('t.yaml', 'name: x' + #10 + 'items:' + #10 + '  - 1' + #10 + '  - 2' + #10);
  Assert.AreEqual(Ord(jrOk), Ord(TreeList(F, ['items'], E, Err)), Err);
  Assert.AreEqual(2, Integer(Length(E)));
  Assert.AreEqual('number', E[0].Kind);
end;

procedure TTestJsonTree.TestMissingKeyIsNotFound;
var
  F, Err: string;
  IsDir: Boolean;
begin
  F := Write('m.json', '{"a":1}');
  Assert.AreEqual(Ord(jrNotFound), Ord(TreeStat(F, ['nope'], IsDir, Err)));
  Assert.AreEqual(Ord(jrNotFound), Ord(TreeStat(TPath.Combine(FDir, 'none.json'), nil, IsDir, Err)));
end;

procedure TTestJsonTree.TestInvalidJsonIsAnError;
var
  F, Err: string;
  IsDir: Boolean;
begin
  F := Write('bad.json', '{"a":');
  Assert.AreEqual(Ord(jrError), Ord(TreeStat(F, nil, IsDir, Err)));
  Assert.IsTrue(Err <> '');
end;

procedure TTestJsonTree.TestHugeFileIsRefusedWithAReason;
var
  F, Err: string;
  IsDir: Boolean;
  S: TFileStream;
begin
  F := Write('huge.json', '{}');
  S := TFileStream.Create(F, fmOpenWrite);
  try
    S.Size := Int64(201) * 1024 * 1024;
  finally
    S.Free;
  end;
  Assert.AreEqual(Ord(jrError), Ord(TreeStat(F, nil, IsDir, Err)));
  Assert.IsTrue(Pos('too large', Err) > 0, Err);
end;

procedure TTestJsonTree.TestChangedFileIsReadAgain;
var
  F, Err, Text: string;
begin
  F := Write('c.json', '{"v":"one"}');
  Assert.AreEqual(Ord(jrOk), Ord(TreeText(F, ['v'], Text, Err)));
  Assert.AreEqual('one', Text);
  // A longer text changes the size even when the clock did not tick.
  Write('c.json', '{"v":"three"}');
  Assert.AreEqual(Ord(jrOk), Ord(TreeText(F, ['v'], Text, Err)));
  Assert.AreEqual('three', Text);
end;

procedure TTestJsonTree.TestTextOfScalarAndSubtree;
var
  F, Err, Text: string;
begin
  F := Write('s.json', '{"n":3,"o":{"a":[1]}}');
  Assert.AreEqual(Ord(jrOk), Ord(TreeText(F, ['n'], Text, Err)));
  Assert.AreEqual('3', Text);
  Assert.AreEqual(Ord(jrOk), Ord(TreeText(F, ['o'], Text, Err)));
  Assert.IsTrue(Pos('"a"', Text) > 0);
  Assert.IsTrue(Pos(#10, Text) > 0, 'a subtree is formatted over several lines');
end;

procedure TTestJsonTree.TestVfsListsAndReadsAValue;
var
  Cb: TVfsCallbacksCdeclV2;
  Buf: TBytes;
  Neg, More: Int64;
  Uri: UTF8String;
  Arr: TJSONArray;
  F: string;
begin
  F := Write('v.json', '{"greeting":"hello"}');
  Cb := JsonTreeVfsCallbacks;
  SetLength(Buf, 65536);
  Uri := UTF8String(TreeUri(F, nil));
  Assert.AreEqual(Int64(Ord(verOk)), Cb.ListDirectory(PAnsiChar(Uri), nil, nil, 0, PAnsiChar(@Buf[0]), Length(Buf), Neg, More));
  Arr := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Buf, 0, Neg)) as TJSONArray;
  try
    Assert.AreEqual(1, Arr.Count);
    Assert.AreEqual('greeting', (Arr.Items[0] as TJSONObject).GetValue<string>('name'));
    Assert.AreEqual('hello', ((Arr.Items[0] as TJSONObject).GetValue('extra') as TJSONObject).GetValue<string>('value'));
  finally
    Arr.Free;
  end;
  Uri := UTF8String(TreeUri(F, ['greeting']));
  Assert.AreEqual(Int64(Ord(verOk)), Cb.ReadText(PAnsiChar(Uri), 0, nil, nil, PAnsiChar(@Buf[0]), Length(Buf), Neg));
  Assert.AreEqual('hello', TEncoding.UTF8.GetString(Buf, 0, Neg));
end;

procedure TTestJsonTree.TestHostArchiveRootUriListsTheFile;
var
  Cb: TVfsCallbacksCdeclV2;
  Buf: TBytes;
  Neg, More: Int64;
  Uri: UTF8String;
  F: string;
begin
  F := Write('data set.json', '[{"t":1},{"t":2}]');
  Cb := JsonTreeVfsCallbacks;
  SetLength(Buf, 65536);
  Uri := UTF8String(PathToArchiveRootUri('jtree', F));
  Assert.AreEqual(Int64(Ord(verOk)), Cb.ListDirectory(PAnsiChar(Uri), nil, nil, 0, PAnsiChar(@Buf[0]), Length(Buf), Neg, More),
    string(Uri));
end;

procedure TTestJsonTree.TestVfsRefusesChanges;
var
  Cb: TVfsCallbacksCdeclV2;
  Uri: UTF8String;
begin
  Cb := JsonTreeVfsCallbacks;
  Uri := UTF8String(TreeUri(Write('r.json', '{"a":1}'), ['a']));
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.Delete(PAnsiChar(Uri), 0, nil, nil));
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.CreateDirectory(PAnsiChar(Uri), nil, nil));
  Assert.AreEqual(Int64(Ord(verNotSupported)), Cb.WriteText(PAnsiChar(Uri), PAnsiChar(UTF8String('2')), nil, nil));
end;

procedure TTestJsonTree.TestVfsCopyWritesTheValue;
var
  Cb: TVfsCallbacksCdeclV2;
  Src, Dst: UTF8String;
  Target: string;
begin
  Cb := JsonTreeVfsCallbacks;
  Src := UTF8String(TreeUri(Write('k.json', '{"a":"value"}'), ['a']));
  Target := TPath.Combine(FDir, 'out.txt');
  Dst := UTF8String(PathToFileUri(Target));
  Assert.AreEqual(Int64(Ord(verOk)), Cb.CopyItem(PAnsiChar(Src), PAnsiChar(Dst), 0, nil, nil));
  Assert.AreEqual('value', TFile.ReadAllText(Target));
  Assert.AreEqual(Int64(Ord(verAlreadyExists)), Cb.CopyItem(PAnsiChar(Src), PAnsiChar(Dst), 0, nil, nil));
end;

end.
