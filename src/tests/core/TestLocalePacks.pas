unit TestLocalePacks;

{ Every shipped language pack (resource\<locale>\strings.json) is checked
  against the English template src\strings\en.json and against the other
  packs: the template and the packs hold the same keys, no value is blank,
  and format placeholders match the template. Packs are discovered from the folder, so a new language is
  covered without editing this unit. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLocalePacks = class
  public
    [Test] procedure TestShippedPacksAreFound;
    [Test] procedure TestEveryTemplateKeyIsTranslated;
    [Test] procedure TestTemplateCoversEveryPackKey;
    [Test] procedure TestPacksShareOneKeySet;
    [Test] procedure TestNoBlankValues;
    [Test] procedure TestTemplatePlaceholdersAreKept;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  System.Generics.Collections;

const
  cResourceRoot = '../../../bin/win64/resource';
  cTemplate = '../../../src/strings/en.json';

type
  TFlatStrings = TDictionary<string, string>;

procedure Flatten(AValue: TJSONValue; const APath: string; AInto: TFlatStrings);
var
  Pair: TJSONPair;
begin
  if AValue is TJSONObject then
  begin
    for Pair in TJSONObject(AValue) do
      if not Pair.JsonString.Value.StartsWith('//') then
        Flatten(Pair.JsonValue, APath + '/' + Pair.JsonString.Value, AInto);
  end
  else
    AInto.AddOrSetValue(APath, AValue.Value);
end;

function LoadFlatFile(const AFileName: string): TFlatStrings;
var
  Root: TJSONValue;
begin
  Result := TFlatStrings.Create;
  Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(AFileName, TEncoding.UTF8));
  try
    Assert.IsNotNull(Root, AFileName + ' parses');
    Flatten(Root, '', Result);
  finally
    Root.Free;
  end;
end;

{ Locale folder name -> its flattened strings.json. Folders without a
  strings.json (themes, help-only folders) are not language packs. }
function LoadPacks: TObjectDictionary<string, TFlatStrings>;
var
  Dir, FileName: string;
begin
  Result := TObjectDictionary<string, TFlatStrings>.Create([doOwnsValues]);
  for Dir in TDirectory.GetDirectories(cResourceRoot) do
  begin
    FileName := TPath.Combine(Dir, 'strings.json');
    if TFile.Exists(FileName) then
      Result.Add(ExtractFileName(Dir), LoadFlatFile(FileName));
  end;
end;

function CountOf(const AText, ASub: string): Integer;
var
  P: Integer;
begin
  Result := 0;
  P := Pos(ASub, AText);
  while P > 0 do
  begin
    Inc(Result);
    P := Pos(ASub, AText, P + Length(ASub));
  end;
end;

procedure TTestLocalePacks.TestShippedPacksAreFound;
var
  Packs: TObjectDictionary<string, TFlatStrings>;
  Locale: string;
begin
  Packs := LoadPacks;
  try
    for Locale in ['ru', 'de', 'zh'] do
      Assert.IsTrue(Packs.ContainsKey(Locale), Locale + ' pack is shipped');
  finally
    Packs.Free;
  end;
end;

procedure TTestLocalePacks.TestEveryTemplateKeyIsTranslated;
var
  Template: TFlatStrings;
  Packs: TObjectDictionary<string, TFlatStrings>;
  Pack: TPair<string, TFlatStrings>;
  Key, Missing: string;
begin
  Template := LoadFlatFile(cTemplate);
  Packs := LoadPacks;
  try
    for Pack in Packs do
    begin
      Missing := '';
      for Key in Template.Keys do
        if not Pack.Value.ContainsKey(Key) then
          Missing := Missing + ' ' + Key;
      Assert.AreEqual('', Missing, Pack.Key + ': template keys missing from the pack');
    end;
  finally
    Packs.Free;
    Template.Free;
  end;
end;

procedure TTestLocalePacks.TestTemplateCoversEveryPackKey;
var
  Template: TFlatStrings;
  Packs: TObjectDictionary<string, TFlatStrings>;
  Pack: TPair<string, TFlatStrings>;
  Key, Missing: string;
begin
  Template := LoadFlatFile(cTemplate);
  Packs := LoadPacks;
  try
    for Pack in Packs do
    begin
      Missing := '';
      for Key in Pack.Value.Keys do
        if not Template.ContainsKey(Key) then
          Missing := Missing + ' ' + Key;
      Assert.AreEqual('', Missing, Pack.Key + ': pack keys absent from the English template');
    end;
  finally
    Packs.Free;
    Template.Free;
  end;
end;

procedure TTestLocalePacks.TestPacksShareOneKeySet;
var
  Packs: TObjectDictionary<string, TFlatStrings>;
  Pack, Other: TPair<string, TFlatStrings>;
  Key, Missing: string;
begin
  Packs := LoadPacks;
  try
    for Pack in Packs do
    begin
      Missing := '';
      for Other in Packs do
        for Key in Other.Value.Keys do
          if not Pack.Value.ContainsKey(Key) then
            Missing := Missing + ' ' + Key;
      Assert.AreEqual('', Missing, Pack.Key + ': keys present in another pack but not here');
    end;
  finally
    Packs.Free;
  end;
end;

procedure TTestLocalePacks.TestNoBlankValues;
var
  Packs: TObjectDictionary<string, TFlatStrings>;
  Pack: TPair<string, TFlatStrings>;
  Pair: TPair<string, string>;
  Blank: string;
begin
  Packs := LoadPacks;
  try
    for Pack in Packs do
    begin
      Blank := '';
      for Pair in Pack.Value do
        if Trim(Pair.Value) = '' then
          Blank := Blank + ' ' + Pair.Key;
      Assert.AreEqual('', Blank, Pack.Key + ': blank values');
    end;
  finally
    Packs.Free;
  end;
end;

procedure TTestLocalePacks.TestTemplatePlaceholdersAreKept;
var
  Template: TFlatStrings;
  Packs: TObjectDictionary<string, TFlatStrings>;
  Pack: TPair<string, TFlatStrings>;
  Pair: TPair<string, string>;
  Mark, Bad: string;
begin
  Template := LoadFlatFile(cTemplate);
  Packs := LoadPacks;
  try
    for Pack in Packs do
    begin
      Bad := '';
      for Pair in Template do
        if Pack.Value.ContainsKey(Pair.Key) then
          for Mark in ['%s', '%d', '%1', '{0}'] do
            if CountOf(Pair.Value, Mark) <> CountOf(Pack.Value[Pair.Key], Mark) then
              Bad := Bad + ' ' + Pair.Key + '(' + Mark + ')';
      Assert.AreEqual('', Bad, Pack.Key + ': placeholder counts differ from the template');
    end;
  finally
    Packs.Free;
    Template.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLocalePacks);

end.
