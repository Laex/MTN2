unit TestChineseStrings;

{ The Chinese locale (the shipped resource\zh pack): it is
  discovered, translates, and covers every key of the Russian translation
  with the same format placeholders. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestChineseStrings = class
  public
    [Test] procedure TestLocaleIsDiscovered;
    [Test] procedure TestTranslatesWithMnemonic;
    [Test] procedure TestCoversEveryRussianKey;
    [Test] procedure TestKeepsFormatPlaceholders;
    [Test] procedure TestMenuMnemonicsAreMarked;
    [Test] procedure TestHelpCoversEveryEnglishTopic;
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

function LoadFlat(const ALocale: string): TFlatStrings;
var
  Root: TJSONValue;
begin
  Result := TFlatStrings.Create;
  Root := TJSONObject.ParseJSONValue(
    TFile.ReadAllText(TPath.Combine(TPath.Combine('../../../bin/win64/resource', ALocale), 'strings.json'), TEncoding.UTF8));
  try
    Assert.IsNotNull(Root, ALocale + ' strings.json parses');
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

procedure TTestChineseStrings.TestLocaleIsDiscovered;
var
  Locale: string;
  Found: Boolean;
begin
  Found := False;
  for Locale in AvailableLocales do
    if SameText(Locale, 'zh') then
      Found := True;
  Assert.IsTrue(Found, 'zh is discovered from the shipped resource\zh pack');
  Assert.AreEqual('简体中文', DisplayLanguageName('zh'));
end;

procedure TTestChineseStrings.TestTranslatesWithMnemonic;
begin
  SetLocale('zh');
  try
    Assert.AreEqual('复制(&C)', T('menu.tmaFileCopy', 'Copy'));
    Assert.AreEqual('取消', T('status.Cancel', 'Cancel'));
    Assert.AreEqual('Fallback', T('this.key.does.not.exist', 'Fallback'),
      'a key absent from the zh pack falls back to the default text');
  finally
    SetLocale('en');
  end;
end;

procedure TTestChineseStrings.TestCoversEveryRussianKey;
var
  Ru, Zh: TFlatStrings;
  Key: string;
  Missing: string;
begin
  Ru := LoadFlat('ru');
  Zh := LoadFlat('zh');
  try
    Missing := '';
    for Key in Ru.Keys do
      if not Zh.ContainsKey(Key) and not Key.StartsWith('/menu/alias.') and not Key.StartsWith('/menu/hint.') then
        Missing := Missing + ' ' + Key;
    Assert.AreEqual('', Missing, 'keys translated into Russian but not into Chinese');
    for Key in Zh.Keys do
      Assert.IsTrue(Trim(Zh[Key]) <> '', 'value of ' + Key + ' is empty');
  finally
    Ru.Free;
    Zh.Free;
  end;
end;

procedure TTestChineseStrings.TestKeepsFormatPlaceholders;
var
  Ru, Zh: TFlatStrings;
  Key, Mark, Bad: string;
begin
  Ru := LoadFlat('ru');
  Zh := LoadFlat('zh');
  try
    Bad := '';
    for Key in Ru.Keys do
      if Zh.ContainsKey(Key) then
        for Mark in ['%s', '%d', '%1', '{0}'] do
          if CountOf(Ru[Key], Mark) <> CountOf(Zh[Key], Mark) then
            Bad := Bad + ' ' + Key + '(' + Mark + ')';
    Assert.AreEqual('', Bad, 'placeholder counts differ from the Russian text');
  finally
    Ru.Free;
    Zh.Free;
  end;
end;

procedure TTestChineseStrings.TestMenuMnemonicsAreMarked;
var
  Ru, Zh: TFlatStrings;
  Key, Bad: string;
begin
  Ru := LoadFlat('ru');
  Zh := LoadFlat('zh');
  try
    Bad := '';
    for Key in Ru.Keys do
      if Key.StartsWith('/menu/tma') and (Pos('&', Ru[Key]) > 0) and
         (Pos('&', Zh[Key]) = 0) then
        Bad := Bad + ' ' + Key;
    Assert.AreEqual('', Bad, 'menu entries with a mnemonic in Russian but none in Chinese');
  finally
    Ru.Free;
    Zh.Free;
  end;
end;

procedure TTestChineseStrings.TestHelpCoversEveryEnglishTopic;
var
  EnDir, ZhDir, Topic, Missing: string;
begin
  EnDir := '../../../bin/win64/resource/en/help';
  ZhDir := '../../../bin/win64/resource/zh/help';
  Missing := '';
  for Topic in TDirectory.GetFiles(EnDir, '*.md') do
    if not TFile.Exists(TPath.Combine(ZhDir, ExtractFileName(Topic))) then
      Missing := Missing + ' ' + ExtractFileName(Topic);
  Assert.AreEqual('', Missing, 'English help topics without a Chinese page');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestChineseStrings);

end.
