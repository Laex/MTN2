unit TestGermanStrings;

{ The German locale (strings/de.json, embedded as STRINGS_DE): it is
  discovered, translates, and covers every key of the Russian translation
  with the same format placeholders. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestGermanStrings = class
  public
    [Test] procedure TestLocaleIsDiscovered;
    [Test] procedure TestTranslatesWithMnemonic;
    [Test] procedure TestCoversEveryRussianKey;
    [Test] procedure TestKeepsFormatPlaceholders;
    [Test] procedure TestMenuMnemonicsAreMarked;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  System.Generics.Collections,
  uStrings, uDisplaySettings;

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

function LoadFlat(const AFileName: string): TFlatStrings;
var
  Root: TJSONValue;
begin
  Result := TFlatStrings.Create;
  Root := TJSONObject.ParseJSONValue(
    TFile.ReadAllText(TPath.Combine('..\..\strings', AFileName), TEncoding.UTF8));
  try
    Assert.IsNotNull(Root, AFileName + ' parses');
    Flatten(Root, '', Result);
  finally
    Root.Free;
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

procedure TTestGermanStrings.TestLocaleIsDiscovered;
var
  Locale: string;
  Found: Boolean;
begin
  Found := False;
  for Locale in AvailableLocales do
    if SameText(Locale, 'de') then
      Found := True;
  Assert.IsTrue(Found, 'de is discovered from the embedded STRINGS_DE resource');
  Assert.AreEqual('Deutsch', DisplayLanguageName('de'));
end;

procedure TTestGermanStrings.TestTranslatesWithMnemonic;
begin
  SetLocale('de');
  try
    Assert.AreEqual('&Kopieren', T('menu.tmaFileCopy', 'Copy'));
    Assert.AreEqual('Abbrechen', T('status.Cancel', 'Cancel'));
    Assert.AreEqual('Fallback', T('this.key.does.not.exist', 'Fallback'),
      'a key absent from de.json falls back to the default text');
  finally
    SetLocale('en');
  end;
end;

procedure TTestGermanStrings.TestCoversEveryRussianKey;
var
  Ru, De: TFlatStrings;
  Key: string;
  Missing: string;
begin
  Ru := LoadFlat('ru.json');
  De := LoadFlat('de.json');
  try
    Missing := '';
    for Key in Ru.Keys do
      if not De.ContainsKey(Key) then
        Missing := Missing + ' ' + Key;
    Assert.AreEqual('', Missing, 'keys translated into Russian but not into German');
    for Key in De.Keys do
      Assert.IsTrue(Trim(De[Key]) <> '', 'value of ' + Key + ' is empty');
  finally
    Ru.Free;
    De.Free;
  end;
end;

procedure TTestGermanStrings.TestKeepsFormatPlaceholders;
var
  Ru, De: TFlatStrings;
  Key, Mark, Bad: string;
begin
  Ru := LoadFlat('ru.json');
  De := LoadFlat('de.json');
  try
    Bad := '';
    for Key in Ru.Keys do
      if De.ContainsKey(Key) then
        for Mark in ['%s', '%d', '%1', '{0}'] do
          if CountOf(Ru[Key], Mark) <> CountOf(De[Key], Mark) then
            Bad := Bad + ' ' + Key + '(' + Mark + ')';
    Assert.AreEqual('', Bad, 'placeholder counts differ from the Russian text');
  finally
    Ru.Free;
    De.Free;
  end;
end;

procedure TTestGermanStrings.TestMenuMnemonicsAreMarked;
var
  Ru, De: TFlatStrings;
  Key, Bad: string;
begin
  Ru := LoadFlat('ru.json');
  De := LoadFlat('de.json');
  try
    Bad := '';
    for Key in Ru.Keys do
      if Key.StartsWith('/menu/tma') and (Pos('&', Ru[Key]) > 0) and
         (Pos('&', De[Key]) = 0) then
        Bad := Bad + ' ' + Key;
    Assert.AreEqual('', Bad, 'menu entries with a mnemonic in Russian but none in German');
  finally
    Ru.Free;
    De.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGermanStrings);

end.
